--[[
	RankedService (MVP)

	Responsibilities:
	- Maintain a cross-server "public deck snapshot" for matchmaking (MemoryStore)
	- Pick an opponent within +/- range of rating (two-phase flow)
	- Validate opponent selection tickets
]]

local RankedService = {}

local Players = game:GetService("Players")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")

local DataStoreWrapper = require(script.Parent.Parent.Persistence.DataStoreWrapper)
local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)
local RankedConstants = require(game.ReplicatedStorage.Modules.Constants.RankedConstants)
local GhostDeckGenerator = require(game.ReplicatedStorage.Modules.Matchmaking.GhostDeckGenerator)

-- MemoryStore structures
local ratingIndex = nil -- SortedMap: key=userId, value=rating
local snapshotMap = nil -- HashMap: key=userId, value=snapshot(json)
local ticketMap = nil   -- HashMap: key=userId, value=ticket(json)

-- Studio / transient MemoryStore failures can spam warnings from the engine itself.
-- To reduce noise, we stop matchmaking on the first MemoryStore GetRange failure
-- and apply a short cooldown before trying again.
local memoryStoreBackoffUntil = 0

-- DataStore fallback (more stable, slower)
local DS_SNAPSHOT = "ranked_snapshot_v1"
local DS_BUCKETS = "ranked_buckets_v1"

-- Throttle DataStore writes per user to avoid excessive UpdateAsync spam
local lastPersistAtByUserId = {} -- userId -> os.time()
local PERSIST_MIN_INTERVAL_SEC = 15

-- Debug logging (set true temporarily when diagnosing matchmaking issues)
local DEBUG = true

local function debugLog(fmt, ...)
	if not DEBUG then
		return
	end
	print(string.format("[RankedService] " .. fmt, ...))
end

local function safeJsonEncode(value)
	local ok, result = pcall(function()
		return HttpService:JSONEncode(value)
	end)
	if ok then
		return result
	end
	return nil
end

local function safeJsonDecode(value)
	if type(value) ~= "string" then
		return nil
	end
	local ok, result = pcall(function()
		return HttpService:JSONDecode(value)
	end)
	if ok then
		return result
	end
	return nil
end

local function initStores()
	if ratingIndex and snapshotMap and ticketMap then
		return true
	end

	local ok1, s1 = pcall(function()
		return MemoryStoreService:GetSortedMap("ranked_rating_index_v1")
	end)
	local ok2, s2 = pcall(function()
		return MemoryStoreService:GetHashMap("ranked_deck_snapshot_v1")
	end)
	local ok3, s3 = pcall(function()
		return MemoryStoreService:GetHashMap("ranked_ticket_v1")
	end)

	if ok1 then ratingIndex = s1 end
	if ok2 then snapshotMap = s2 end
	if ok3 then ticketMap = s3 end

	return ratingIndex ~= nil and snapshotMap ~= nil and ticketMap ~= nil
end

local function buildSnapshotFromProfile(profile)
	if not profile then
		return nil
	end

	local rating = profile.pvpRating
	if type(rating) ~= "number" or rating < 0 then
		rating = RankedConstants.START_RATING
	end

	-- IMPORTANT: profile.deck can be a sparse array; ipairs would stop on the first nil.
	-- Compact into a dense 1..N array in declared order (max 6 cards).
	local deck = {}
	if type(profile.deck) == "table" then
		for i = 1, 6 do
			local cardId = profile.deck[i]
			if type(cardId) == "string" and cardId ~= "" then
				table.insert(deck, cardId)
			end
		end
	end

	-- Levels aligned with deck array indices (not board slots).
	local levels = {}
	local collection = profile.collection or {}
	for i, cardId in ipairs(deck) do
		local entry = collection[cardId]
		levels[i] = (entry and entry.level) or 1
	end

	return {
		rating = math.floor(rating),
		deck = deck,
		levels = levels,
		updatedAt = os.time(),
	}
end

local function buildGhostOpponent(playerSnapshot, myRating)
	local seed = os.time() * 1000 + math.floor(os.clock() * 1000)
	local ghost = GhostDeckGenerator.Generate(
		playerSnapshot.deck or {},
		playerSnapshot.levels or {},
		seed,
		{
			minStrengthMult = RankedConstants.GHOST_MIN_STRENGTH_MULT,
			maxStrengthMult = RankedConstants.GHOST_MAX_STRENGTH_MULT,
			sizeVariance = RankedConstants.GHOST_SIZE_VARIANCE,
			levelVarianceMin = RankedConstants.GHOST_LEVEL_VARIANCE_MIN,
			levelVarianceMax = RankedConstants.GHOST_LEVEL_VARIANCE_MAX,
			attempts = RankedConstants.GHOST_ATTEMPTS,
		}
	)

	local shownRating = myRating
	do
		local jitter = tonumber(RankedConstants.GHOST_RATING_JITTER) or 0
		if jitter > 0 then
			local r = Random.new(seed)
			shownRating = math.max(0, math.floor((myRating or RankedConstants.START_RATING) + r:NextInteger(-jitter, jitter)))
		end
	end

	return {
		id = "ghost:" .. HttpService:GenerateGUID(false),
		snapshot = {
			isGhost = true,
			rating = shownRating,
			deck = ghost.deck or {},
			levels = ghost.levels or {},
			strength = ghost.strength or 0,
			updatedAt = os.time(),
			seed = seed,
		},
	}
end

-- Upsert player's snapshot and rating into MemoryStore.
-- Best-effort: failure should not block gameplay.
function RankedService.UpsertSnapshot(userId, profile)
	userId = tostring(userId)
	if not initStores() then
		debugLog("UpsertSnapshot skipped (MemoryStore unavailable) userId=%s", userId)
		return false, "MEMORYSTORE_UNAVAILABLE"
	end

	local now = os.time()

	local snapshot = buildSnapshotFromProfile(profile)
	if not snapshot or type(snapshot.deck) ~= "table" then
		debugLog("UpsertSnapshot invalid profile userId=%s", userId)
		return false, "INVALID_PROFILE"
	end
	debugLog("UpsertSnapshot userId=%s rating=%d deckSize=%d", userId, snapshot.rating, #snapshot.deck)

	local encoded = safeJsonEncode(snapshot)
	if not encoded then
		return false, "ENCODE_FAILED"
	end

	local okSnap, errSnap = pcall(function()
		snapshotMap:SetAsync(userId, encoded, RankedConstants.SNAPSHOT_TTL)
	end)
	if not okSnap then
		debugLog("UpsertSnapshot snapshotMap:SetAsync FAILED userId=%s err=%s", userId, tostring(errSnap))
	end

	local okIdx, errIdx = pcall(function()
		-- SortedMap ordering is driven by sortKey, NOT value.
		-- Store a tiny value (timestamp) and put rating into sortKey for range queries.
		ratingIndex:SetAsync(userId, now, RankedConstants.INDEX_TTL, snapshot.rating)
	end)
	if not okIdx then
		debugLog("UpsertSnapshot ratingIndex:SetAsync FAILED userId=%s err=%s", userId, tostring(errIdx))
	end

	-- DataStore fallback: persist snapshot + add to bucket index (best effort, throttled)
	local last = lastPersistAtByUserId[userId]
	if not last or (now - last) >= PERSIST_MIN_INTERVAL_SEC then
		lastPersistAtByUserId[userId] = now
		pcall(function()
			DataStoreWrapper.UpdateAsync(DS_SNAPSHOT, userId, function()
				return snapshot
			end, 2)
		end)
		-- Bucket index: bucketKey -> { [userId] = updatedAt }
		local bucketSize = RankedConstants.BUCKET_SIZE or 100
		local bucketId = math.floor(snapshot.rating / bucketSize)
		local bucketKey = "b_" .. tostring(bucketId)
		pcall(function()
			DataStoreWrapper.UpdateAsync(DS_BUCKETS, bucketKey, function(old)
				local map = (type(old) == "table") and old or {}
				map[userId] = now

				-- Soft cleanup if bucket grows too large
				local cap = RankedConstants.DATASTORE_BUCKET_CAP or 500
				local count = 0
				for _ in pairs(map) do
					count = count + 1
					if count > cap then
						break
					end
				end
				if count > cap then
					-- Remove oldest entries until under cap
					local entries = {}
					for k, ts in pairs(map) do
						table.insert(entries, { k = k, ts = ts })
					end
					table.sort(entries, function(a, b)
						return (a.ts or 0) < (b.ts or 0)
					end)
					local toRemove = math.max(0, #entries - cap)
					for i = 1, toRemove do
						map[entries[i].k] = nil
					end
				end

				return map
			end, 2)
		end)
	end

	return true
end

local function getSnapshot(userId)
	userId = tostring(userId)
	if not initStores() then
		return nil
	end

	local ok, value = pcall(function()
		return snapshotMap:GetAsync(userId)
	end)
	if not ok then
		return nil
	end
	return safeJsonDecode(value)
end

-- Pick a random opponent within +/- range (expands if needed).
function RankedService.PickOpponent(userId, rating)
	userId = tostring(userId)
	if not initStores() then
		debugLog("PickOpponent: MemoryStore unavailable")
		-- Still allow DataStore fallback (supports offline opponent selection)
		local dsPick = RankedService.PickOpponentFromDataStore(userId, rating, RankedConstants.INITIAL_RANGE)
		local dsPickNum = dsPick and tonumber(dsPick) or nil
		if dsPickNum and dsPickNum > 0 and tostring(dsPickNum) ~= userId then
			debugLog("PickOpponent: DataStore fallback chosen=%s (MemoryStore unavailable)", dsPick)
			return tostring(dsPickNum)
		end
		return nil, "NO_OPPONENTS"
	end

	-- Cooldown after transient MemoryStore internal errors
	if os.time() < memoryStoreBackoffUntil then
		debugLog("PickOpponent: backoff active (%d sec left)", math.max(0, memoryStoreBackoffUntil - os.time()))
		-- During backoff, try DataStore fallback (supports offline opponent selection)
		local dsPick = RankedService.PickOpponentFromDataStore(userId, rating, RankedConstants.INITIAL_RANGE)
		local dsPickNum = dsPick and tonumber(dsPick) or nil
		if dsPickNum and dsPickNum > 0 and tostring(dsPickNum) ~= userId then
			debugLog("PickOpponent: DataStore fallback chosen=%s (backoff active)", dsPick)
			return tostring(dsPickNum)
		end
		return nil, "NO_OPPONENTS"
	end

	if type(rating) ~= "number" or rating < 0 then
		rating = RankedConstants.START_RATING
	end

	local range = RankedConstants.INITIAL_RANGE
	local rng = Random.new(os.clock() * 1000)

	while range <= RankedConstants.MAX_RANGE do
		local minR = math.max(0, rating - range)
		local maxR = rating + range

		local ok, entries = pcall(function()
			-- GetRangeAsync expects bounds as tables: { key=?, sortKey=? }.
			-- We constrain by sortKey (rating).
			local lowerBound = { sortKey = minR }
			local upperBound = { sortKey = maxR }
			return ratingIndex:GetRangeAsync(Enum.SortDirection.Ascending, RankedConstants.MAX_CANDIDATES, lowerBound, upperBound)
		end)

		-- IMPORTANT: On some Studio sessions MemoryStore can throw InternalError and Roblox will print it.
		-- If that happens, don't keep retrying/expanding range (it just spams the same error xN).
		if not ok then
			memoryStoreBackoffUntil = os.time() + 10
			debugLog("PickOpponent: GetRangeAsync failed, entering backoff")
			-- Fallback to DataStore-based matchmaking
			local dsPick = RankedService.PickOpponentFromDataStore(userId, rating, range)
			if dsPick then
				debugLog("PickOpponent: DataStore fallback chosen=%s", dsPick)
				return dsPick
			end
			return nil, "NO_OPPONENTS"
		end

		if ok and type(entries) == "table" and #entries > 0 then
			debugLog("PickOpponent: range=%d gotEntries=%d", range, #entries)
			-- Filter out self and any invalid keys
			local candidates = {}
			for _, entry in ipairs(entries) do
				local key = tostring(entry.key)
				debugLog("  entry key=%s value=%s", tostring(entry.key), tostring(entry.value))
				if key ~= userId then
					table.insert(candidates, key)
				end
			end

			if #candidates > 0 then
				local chosen = candidates[rng:NextInteger(1, #candidates)]
				debugLog("PickOpponent: chosen=%s (candidates=%d)", chosen, #candidates)
				return chosen
			else
				-- Common in solo test: index contains only self. Allow DataStore fallback.
				local dsPick = RankedService.PickOpponentFromDataStore(userId, rating, range)
				local dsPickNum = dsPick and tonumber(dsPick) or nil
				if dsPickNum and dsPickNum > 0 and tostring(dsPickNum) ~= userId then
					debugLog("PickOpponent: DataStore fallback chosen=%s (only-self in MemoryStore, range=%d)", dsPick, range)
					return tostring(dsPickNum)
				end
			end
		else
			debugLog("PickOpponent: range=%d gotEntries=0", range)
			-- If MemoryStore is working but empty, allow DS fallback too (helps when index TTL expired)
			local dsPick = RankedService.PickOpponentFromDataStore(userId, rating, range)
			if dsPick then
				debugLog("PickOpponent: DataStore fallback chosen=%s (range=%d)", dsPick, range)
				return dsPick
			end
		end

		range = range + RankedConstants.RANGE_STEP
	end

	return nil, "NO_OPPONENTS"
end

-- DataStore fallback opponent selection.
-- Reads bucket maps around the player's bucket and picks a random recent user.
function RankedService.PickOpponentFromDataStore(selfUserId, rating, range)
	selfUserId = tostring(selfUserId)
	if type(rating) ~= "number" or rating < 0 then
		rating = RankedConstants.START_RATING
	end

	local bucketSize = RankedConstants.BUCKET_SIZE or 100
	local baseBucket = math.floor(rating / bucketSize)
	local bucketDelta = math.max(1, math.ceil(range / bucketSize))

	local now = os.time()
	local staleAfter = RankedConstants.DATASTORE_SNAPSHOT_TTL or (24 * 60 * 60)

	local candidates = {}
	for b = baseBucket - bucketDelta, baseBucket + bucketDelta do
		local bucketKey = "b_" .. tostring(b)
		local ok, bucketMap = pcall(function()
			return DataStoreWrapper.GetAsync(DS_BUCKETS, bucketKey, 1)
		end)
		if ok and type(bucketMap) == "table" then
			for userId, updatedAt in pairs(bucketMap) do
				-- Defensive: bucket maps should be { [userIdString] = updatedAtNumber }.
				-- Ignore any malformed keys/values (prevents selecting invalid opponentUserId like -2).
				local userIdNum = tonumber(userId)
				if userIdNum and userIdNum > 0 then
					local normalized = tostring(userIdNum)
					if normalized ~= selfUserId then
						if type(updatedAt) == "number" and (now - updatedAt) <= staleAfter then
							table.insert(candidates, normalized)
						end
					end
				else
					-- If bucket content is malformed (e.g. array), don't treat numeric indices as userIds
					-- (pairs() would yield 1,2,3... keys which are NOT userIds).
				end
			end
		end
	end

	if #candidates == 0 then
		return nil
	end

	local rng = Random.new(os.clock() * 1000)
	return candidates[rng:NextInteger(1, #candidates)]
end

-- Two-phase flow: request opponent, issue a short-lived ticket to bind selection.
function RankedService.RequestOpponent(player)
	if not player or not player.UserId then
		return { ok = false, error = { code = "INVALID_PLAYER", message = "Invalid player" } }
	end

	local userId = tostring(player.UserId)

	-- Ensure caller profile loaded
	local profile = ProfileManager.GetCachedProfile(player.UserId)
	if not profile then
		profile = ProfileManager.LoadProfile(player.UserId)
	end
	if not profile then
		return { ok = false, error = { code = "PROFILE_LOAD_FAILED", message = "Failed to load profile" } }
	end

	-- Upsert self snapshot for matchmaking visibility
	RankedService.UpsertSnapshot(userId, profile)

	local myRating = profile.pvpRating or RankedConstants.START_RATING
	local opponentUserId, reason = RankedService.PickOpponent(userId, myRating)
	local mySnapshot = buildSnapshotFromProfile(profile)
	if not opponentUserId then
		-- Cold start fallback: generate a ghost deck using the same style as NPC deck gen.
		if RankedConstants.GHOST_ENABLED and mySnapshot and type(mySnapshot.deck) == "table" and #mySnapshot.deck > 0 then
			local ghost = buildGhostOpponent(mySnapshot, myRating)
			local opponentName = "Ghost Rival"

			local ticket = HttpService:GenerateGUID(false)
			local ticketPayload = {
				ticket = ticket,
				opponentUserId = ghost.id,
				issuedAt = os.time(),
				ghostSnapshot = ghost.snapshot,
			}
			local encodedTicket = safeJsonEncode(ticketPayload)
			if encodedTicket then
				pcall(function()
					ticketMap:SetAsync(userId, encodedTicket, RankedConstants.TICKET_TTL)
				end)
			end

			debugLog("RequestOpponent: ghost fallback issued player=%s ghostId=%s deckSize=%d rating=%d",
				userId, ghost.id, #(ghost.snapshot.deck or {}), tonumber(ghost.snapshot.rating) or -1)

			return {
				ok = true,
				opponent = {
					userId = ghost.id, -- string id, passed back as-is
					name = opponentName,
					rating = ghost.snapshot.rating,
					isGhost = true,
				},
				deck = ghost.snapshot.deck,
				levels = ghost.snapshot.levels or {},
				ticket = ticket,
			}
		end

		-- Otherwise: no opponent available
		return { ok = false, error = { code = tostring(reason or "NO_OPPONENTS"), message = tostring(reason or "No opponents available") } }
	end

	-- Safety: never allow invalid opponent ids to escape to client
	local oppNum = tonumber(opponentUserId)
	if not oppNum or oppNum <= 0 or tostring(oppNum) == userId then
		return { ok = false, error = { code = "NO_OPPONENTS", message = "No opponents available" } }
	end
	opponentUserId = tostring(oppNum)

	local oppSnapshot = getSnapshot(opponentUserId)
	-- If MemoryStore snapshot is missing, try DataStore snapshot.
	if not oppSnapshot then
		local ok, dsSnapshot = pcall(function()
			return DataStoreWrapper.GetAsync(DS_SNAPSHOT, tostring(opponentUserId), 1)
		end)
		if ok and type(dsSnapshot) == "table" then
			oppSnapshot = dsSnapshot
		end
	end
	if not oppSnapshot or type(oppSnapshot.deck) ~= "table" or #oppSnapshot.deck == 0 then
		return { ok = false, error = { code = "OPPONENT_SNAPSHOT_MISSING", message = "Opponent snapshot missing" } }
	end

	local opponentName = nil
	local oppPlayer = Players:GetPlayerByUserId(tonumber(opponentUserId))
	if oppPlayer then
		opponentName = oppPlayer.Name
	else
		-- Offline/other server: resolve username (best-effort)
		local okName, nameOrErr = pcall(function()
			return Players:GetNameFromUserIdAsync(tonumber(opponentUserId))
		end)
		if okName and type(nameOrErr) == "string" and nameOrErr ~= "" then
			opponentName = nameOrErr
		else
			opponentName = "Player " .. tostring(opponentUserId)
		end
	end

	local ticket = HttpService:GenerateGUID(false)
	local ticketPayload = {
		ticket = ticket,
		opponentUserId = opponentUserId,
		issuedAt = os.time(),
	}

	local encodedTicket = safeJsonEncode(ticketPayload)
	if encodedTicket then
		pcall(function()
			ticketMap:SetAsync(userId, encodedTicket, RankedConstants.TICKET_TTL)
		end)
	end

	return {
		ok = true,
		opponent = {
			userId = tonumber(opponentUserId),
			name = opponentName,
			rating = math.floor(tonumber(oppSnapshot.rating) or RankedConstants.START_RATING),
		},
		deck = oppSnapshot.deck,
		levels = oppSnapshot.levels or {},
		ticket = ticket,
	}
end

function RankedService.ValidateTicketAndGetPayload(playerUserId, opponentUserId, ticket)
	playerUserId = tostring(playerUserId)
	opponentUserId = tostring(opponentUserId)

	if not initStores() then
		return false, "MEMORYSTORE_UNAVAILABLE"
	end

	if type(ticket) ~= "string" or ticket == "" then
		return false, "INVALID_TICKET"
	end

	local ok, value = pcall(function()
		return ticketMap:GetAsync(playerUserId)
	end)
	if not ok then
		return false, "TICKET_LOOKUP_FAILED"
	end

	local decoded = safeJsonDecode(value)
	if not decoded or decoded.ticket ~= ticket or tostring(decoded.opponentUserId) ~= opponentUserId then
		return false, "TICKET_MISMATCH"
	end

	return true, decoded
end

function RankedService.ValidateTicket(playerUserId, opponentUserId, ticket)
	playerUserId = tostring(playerUserId)
	opponentUserId = tostring(opponentUserId)

	if not initStores() then
		return false, "MEMORYSTORE_UNAVAILABLE"
	end

	if type(ticket) ~= "string" or ticket == "" then
		return false, "INVALID_TICKET"
	end

	local ok, value = pcall(function()
		return ticketMap:GetAsync(playerUserId)
	end)
	if not ok then
		return false, "TICKET_LOOKUP_FAILED"
	end

	local decoded = safeJsonDecode(value)
	if not decoded or decoded.ticket ~= ticket or tostring(decoded.opponentUserId) ~= opponentUserId then
		return false, "TICKET_MISMATCH"
	end

	return true
end

function RankedService.GetOpponentSnapshot(opponentUserId)
	-- Prefer MemoryStore (fast), but allow DataStore fallback for offline opponents
	local snap = getSnapshot(opponentUserId)
	if snap and type(snap.deck) == "table" and #snap.deck > 0 then
		return snap
	end

	local ok, dsSnapshot = pcall(function()
		return DataStoreWrapper.GetAsync(DS_SNAPSHOT, tostring(opponentUserId), 1)
	end)
	if ok and type(dsSnapshot) == "table" and type(dsSnapshot.deck) == "table" and #dsSnapshot.deck > 0 then
		return dsSnapshot
	end

	return nil
end

return RankedService

