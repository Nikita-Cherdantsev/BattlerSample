local ProfileSnapshotService = {}

-- Services
local Players = game:GetService("Players")

-- Modules
local ServicesFolder = game.ServerScriptService:WaitForChild("Services")
local PersistenceFolder = game.ServerScriptService:WaitForChild("Persistence")
local PlayerDataService = require(ServicesFolder:WaitForChild("PlayerDataService"))
local ProfileManager = require(PersistenceFolder:WaitForChild("ProfileManager"))
local DailyService = require(ServicesFolder:WaitForChild("DailyService"))
local PlaytimeService = require(ServicesFolder:WaitForChild("PlaytimeService"))
local Logger = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Logger"))

-- Utilities
local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, innerValue in pairs(value) do
		copy[key] = deepCopy(innerValue)
	end
	return copy
end

local function cloneArray(array)
	if type(array) ~= "table" then
		return {}
	end

	local result = {}

	-- Preserve numeric indices even if there are gaps
	for index, value in pairs(array) do
		if type(index) == "number" then
			result[index] = deepCopy(value)
		end
	end

	-- Copy any non-numeric keys as well
	for key, value in pairs(array) do
		if type(key) ~= "number" then
			result[key] = deepCopy(value)
		end
	end

	return result
end

local function sanitizeCurrencies(currencies)
	if type(currencies) ~= "table" then
		return { soft = 0, hard = 0 }
	end

	return {
		soft = tonumber(currencies.soft) or 0,
		hard = tonumber(currencies.hard) or 0,
	}
end

local function sanitizePlaytime(playtime)
	if type(playtime) ~= "table" then
		return nil
	end

	return {
		totalTime = tonumber(playtime.totalTime) or 0,
		lastSyncTime = tonumber(playtime.lastSyncTime) or 0,
		claimedRewards = cloneArray(playtime.claimedRewards or {}),
		rewardsConfig = deepCopy(playtime.rewardsConfig or nil),
	}
end

local function sanitizeLootboxes(lootboxes)
	if type(lootboxes) ~= "table" then
		return {}
	end

	return cloneArray(lootboxes)
end

local function sanitizePendingLootbox(pendingLootbox)
	if type(pendingLootbox) ~= "table" then
		return nil
	end

	return deepCopy(pendingLootbox)
end

local function sanitizeProfileSnapshot(player, profile)
	local snapshot = {
		version = profile.version,
		playerId = profile.playerId,
		createdAt = profile.createdAt,
		lastLoginAt = profile.lastLoginAt,
		loginStreak = profile.loginStreak,
		favoriteLastSeen = profile.favoriteLastSeen,
		tutorialStep = profile.tutorialStep,
		squadPower = profile.squadPower or 0,
		deck = cloneArray(profile.deck or {}),
		currencies = sanitizeCurrencies(profile.currencies),
		lootboxes = sanitizeLootboxes(profile.lootboxes or {}),
		pendingLootbox = sanitizePendingLootbox(profile.pendingLootbox),
		playtime = sanitizePlaytime(profile.playtime),
		likeReward = profile.likeReward and deepCopy(profile.likeReward) or {
			lastRequest = nil,
			claimed = false,
			eligible = false
		},
		updatedAt = profile.updatedAt or os.time(),
	}

	-- Keep compatibility with systems expecting profile v2 format
	if not snapshot.version then
		snapshot.version = 2
	end

	-- Ensure deck is always an array (no nil gaps)
	if snapshot.deck then
		local compactedDeck = {}
		for _, cardId in ipairs(snapshot.deck) do
			table.insert(compactedDeck, cardId)
		end
		snapshot.deck = compactedDeck
	end

	return snapshot
end

-- Public helpers ----------------------------------------------------------------

function ProfileSnapshotService.CreateCollectionSummary(collection)
	local summary = {}

	if type(collection) ~= "table" then
		return summary
	end

	for cardId, entry in pairs(collection) do
		local count = type(entry) == "table" and entry.count or entry
		local level = type(entry) == "table" and entry.level or 1

		table.insert(summary, {
			cardId = cardId,
			count = count or 0,
			level = level or 1,
		})
	end

	table.sort(summary, function(a, b)
		return tostring(a.cardId) < tostring(b.cardId)
	end)

	return summary
end

function ProfileSnapshotService.CreateLoginInfo(player)
	if not player then
		return nil
	end
	
	-- Get profile directly from ProfileManager (single source of truth)
	local profile = ProfileManager.GetCachedProfile(player.UserId)
	if not profile then
		profile = ProfileManager.LoadProfile(player.UserId)
	end
	
	if not profile then
		return nil
	end

	return {
		lastLoginAt = profile.lastLoginAt,
		loginStreak = profile.loginStreak,
	}
end

-- Snapshot builder ---------------------------------------------------------------

function ProfileSnapshotService.GetSnapshot(player, options)
	options = options or {}

	if not player then
		return nil, "PROFILE_LOAD_FAILED", "No player specified"
	end

	-- Get profile directly from ProfileManager (single source of truth)
	-- This ensures we always have the latest data after any ProfileManager.UpdateProfile calls
	local profile = ProfileManager.GetCachedProfile(player.UserId)
	if not profile then
		profile = ProfileManager.LoadProfile(player.UserId)
	end

	if not profile then
		return nil, "PROFILE_LOAD_FAILED", "Failed to load profile"
	end

	local snapshot = sanitizeProfileSnapshot(player, profile)

	-- Collection summary (enabled by default)
	if options.includeCollection ~= false then
		-- Collection is part of the profile, use it directly
		if profile.collection then
			snapshot.collectionSummary = ProfileSnapshotService.CreateCollectionSummary(profile.collection)
		end
	end

	-- Login info (disabled by default)
	if options.includeLoginInfo then
		snapshot.loginInfo = ProfileSnapshotService.CreateLoginInfo(player)
	end

	-- Daily data (disabled by default)
	if options.includeDaily then
		local dailyData = DailyService.GetDailyData(player.UserId)
		if dailyData then
			snapshot.daily = {
				streak = dailyData.streak,
				lastLogin = dailyData.lastLogin,
				currentDay = dailyData.currentDay,
				isClaimed = dailyData.isClaimed,
				rewardsConfig = deepCopy(dailyData.rewardsConfig or {}),
			}
		end
	end

	-- Playtime data (disabled by default). If explicitly requested, fetch from PlaytimeService.
	if options.includePlaytime then
		local playtimeData = PlaytimeService.GetPlaytimeData(player.UserId)
		if playtimeData then
			snapshot.playtime = {
				totalTime = tonumber(playtimeData.totalTime) or 0,
				lastSyncTime = tonumber(playtimeData.lastSyncTime) or 0,
				claimedRewards = cloneArray(playtimeData.claimedRewards or {}),
				rewardsConfig = deepCopy(playtimeData.rewardsConfig or {}),
				nextRewardTimeSeconds = playtimeData.nextRewardTimeSeconds,
				hasAvailableReward = playtimeData.hasAvailableReward,
			}
		end
	end

	return snapshot
end

-- Diagnostic logging ------------------------------------------------------------

function ProfileSnapshotService.LogSnapshot(player, context, snapshot)
	local userId = player and player.UserId or "unknown"
	local softCurrency = snapshot.currencies and snapshot.currencies.soft or 0
	local hardCurrency = snapshot.currencies and snapshot.currencies.hard or 0
	local errorCode = snapshot.error and snapshot.error.code or "none"

	Logger.info(
		"PROFILE_UPDATE user=%s context=%s soft=%d hard=%d updatedAt=%s error=%s",
		tostring(userId),
		tostring(context or "unspecified"),
		softCurrency,
		hardCurrency,
		tostring(snapshot.updatedAt or "nil"),
		tostring(errorCode)
	)
end

function ProfileSnapshotService.LogSnapshotFailure(player, context, errorCode, errorMessage)
	local userId = player and player.UserId or "unknown"
	Logger.warn(
		"PROFILE_UPDATE_FAILED user=%s context=%s code=%s message=%s",
		tostring(userId),
		tostring(context or "unspecified"),
		tostring(errorCode or "unknown"),
		tostring(errorMessage or "unknown")
	)
end

return ProfileSnapshotService

