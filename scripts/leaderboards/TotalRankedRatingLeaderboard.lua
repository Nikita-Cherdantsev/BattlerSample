--[[
	Total Ranked Rating Leaderboard Script

	Copy this script into the SurfaceGui Script for the ranked rating leaderboard model.
	Model name (as per your place): TotalRankedRatingLeaderboard

	It reads `pvpRating` from player profiles and keeps a global leaderboard
	via an OrderedDataStore.

	Notes on "cross-server актуальность":
	- This script writes each player's latest rating to the OrderedDataStore on:
	  - PlayerAdded (after a short delay, force write)
	  - PlayerRemoving (force write)
	  - Periodic refresh loop
	- That means when a player teleports between servers, the leaving server should
	  persist the newest rating, and the new server will read it from DataStore.
]]

-- Configuration
local DISPLAY_NAME = "Ranked Rating"
local DATASTORE_KEY = "GlobalLeaderboard_RankedRating"
local MAX_ITEMS = 100
local MIN_VALUE_DISPLAY = 0
local MAX_VALUE_DISPLAY = 9.9e14
local UPDATE_INTERVAL = 120 -- seconds (2 minutes)
local MIN_DELTA_TO_SAVE = 1 -- rating changes in whole numbers
local DATASTORE_RETRIES = 3
local RETRY_BACKOFF = 2 -- seconds
local CACHE_DURATION = 30 -- Cache GetSorted results for 30 seconds
local BUDGET_THRESHOLD = 0.5 -- Only make requests if budget > 50%

-- Services & modules
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local ProfileManager = require(game.ServerScriptService.Persistence.ProfileManager)
local RankedConstants = require(game.ReplicatedStorage.Modules.Constants.RankedConstants)
local Manifest = require(game.ReplicatedStorage.Modules.Assets.Manifest)

local dataStore = DataStoreService:GetOrderedDataStore(DATASTORE_KEY)

-- UI references
local surfaceGui = script.Parent
local sample = script:WaitForChild("Sample")
local listFrame = surfaceGui.Frame.List
local itemsFrame = listFrame.ListContent.Items

-- Internal state
local cachedTotalsByUserId = {}
local sessionEntries = {}
local cachedLeaderboardData = nil -- Cached leaderboard rows
local cacheTimestamp = 0 -- When cache was last updated

-- Cache for usernames to avoid repeated API calls
local usernameCache = {}
local CACHE_USERNAME_DURATION = 300 -- Cache usernames for 5 minutes

local function roundNumber(value)
	if typeof(value) ~= "number" then
		return 0
	end
	return math.floor(value + 0.5)
end

local function getRankedRating(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	if not profile then
		local success, loaded = pcall(function()
			return ProfileManager.LoadProfile(userId)
		end)
		if success then
			profile = loaded
		end
	end

	if not profile then
		return nil
	end

	local rating = tonumber(profile.pvpRating)
	if not rating or rating < 0 then
		rating = RankedConstants.START_RATING
	end

	return math.max(0, roundNumber(rating))
end

local function getUsername(userId)
	if not userId or userId == 0 then
		return "User " .. tostring(userId or "Unknown")
	end

	-- Check cache first
	local cached = usernameCache[userId]
	if cached and (os.time() - cached.timestamp) < CACHE_USERNAME_DURATION then
		return cached.username
	end

	-- Try to get player from current game session
	local player = Players:GetPlayerByUserId(userId)
	if player then
		local username = player.Name
		usernameCache[userId] = {
			username = username,
			timestamp = os.time(),
		}
		return username
	end

	-- Try to fetch from API (with better error handling)
	local success, fetchedName = pcall(function()
		if type(userId) ~= "number" or userId <= 0 then
			return nil
		end
		return Players:GetNameFromUserIdAsync(userId)
	end)

	if success and fetchedName and type(fetchedName) == "string" and fetchedName ~= "" then
		usernameCache[userId] = {
			username = fetchedName,
			timestamp = os.time(),
		}
		return fetchedName
	end

	return "User " .. tostring(userId)
end

local function writeTotalToDataStore(userId, total)
	total = roundNumber(total)
	for attempt = 1, DATASTORE_RETRIES do
		local success, err = pcall(function()
			dataStore:UpdateAsync(userId, function()
				return total
			end)
		end)

		if success then
			return true
		end

		warn(string.format("[RankedRatingLeaderboard] Failed to write value for user %d (attempt %d/%d): %s",
			userId, attempt, DATASTORE_RETRIES, tostring(err)))
		task.wait(RETRY_BACKOFF * attempt)
	end

	return false
end

local function syncPlayerTotal(userId, forceWrite)
	local rating = getRankedRating(userId)
	if rating == nil then
		return
	end

	sessionEntries[userId] = rating

	local lastRecorded = cachedTotalsByUserId[userId]
	local delta = lastRecorded and math.abs(rating - lastRecorded) or math.huge

	if forceWrite or delta >= MIN_DELTA_TO_SAVE then
		if writeTotalToDataStore(userId, rating) then
			cachedTotalsByUserId[userId] = rating
		end
	end
end

local function clearItems()
	for _, child in ipairs(itemsFrame:GetChildren()) do
		if child:IsA("ImageLabel") then
			child:Destroy()
		end
	end
end

local function checkBudget()
	local success, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetSortedAsync)
	end)

	if success and budget then
		return budget >= BUDGET_THRESHOLD
	end

	return true
end

local function buildRows()
	local now = os.time()
	if cachedLeaderboardData and (now - cacheTimestamp) < CACHE_DURATION then
		return cachedLeaderboardData
	end

	local rows = {}
	local usedDataStore = false

	if not checkBudget() then
		warn("[RankedRatingLeaderboard] DataStore budget too low, using cached data or session entries")
		if cachedLeaderboardData then
			return cachedLeaderboardData
		end
	else
		local success, sortedData = pcall(function()
			return dataStore:GetSortedAsync(false, MAX_ITEMS, MIN_VALUE_DISPLAY, MAX_VALUE_DISPLAY)
		end)

		if success then
			local page = sortedData:GetCurrentPage()
			local indexByUserId = {}

			for _, entry in ipairs(page) do
				local userId = tonumber(entry.key)
				local rating = tonumber(entry.value) or 0
				table.insert(rows, {
					userId = userId,
					rating = rating,
				})
				indexByUserId[userId] = #rows
			end

			for userId, rating in pairs(sessionEntries) do
				local existingIndex = indexByUserId[userId]
				if existingIndex then
					if rating > rows[existingIndex].rating then
						rows[existingIndex].rating = rating
					end
				else
					table.insert(rows, { userId = userId, rating = rating })
				end
			end

			usedDataStore = true
			cachedLeaderboardData = rows
			cacheTimestamp = now
		else
			warn("[RankedRatingLeaderboard] Failed to fetch leaderboard data: " .. tostring(sortedData))
		end
	end

	if not usedDataStore then
		for userId, rating in pairs(sessionEntries) do
			table.insert(rows, { userId = userId, rating = rating })
		end
	end

	table.sort(rows, function(a, b)
		return (a.rating or 0) > (b.rating or 0)
	end)

	if #rows > MAX_ITEMS then
		rows = { table.unpack(rows, 1, MAX_ITEMS) }
	end

	return rows
end

local function updateLeaderboardDisplay()
	local rows = buildRows()

	surfaceGui.Heading.Heading.Text = DISPLAY_NAME

	itemsFrame.Nothing.Visible = (#rows == 0)
	clearItems()

	for index, entry in ipairs(rows) do
		local userId = entry.userId
		local rating = entry.rating or 0
		local username = getUsername(userId)

		-- Colors from Manifest based on position
		local colorFrom, colorTo
		if index == 1 then
			colorFrom = Manifest.RarityColors.Legendary
			colorTo = Manifest.RarityColorsGradient.Legendary
		elseif index == 2 then
			colorFrom = Manifest.RarityColors.Epic
			colorTo = Manifest.RarityColorsGradient.Epic
		elseif index == 3 then
			colorFrom = Manifest.RarityColors.Rare
			colorTo = Manifest.RarityColorsGradient.Rare
		elseif index == 4 then
			colorFrom = Manifest.RarityColors.Uncommon
			colorTo = Manifest.RarityColorsGradient.Uncommon
		else
			colorFrom = Color3.fromHex("#7A6B78")
			colorTo = Color3.fromHex("#221421")
		end

		local item = sample:Clone()
		item.Name = tostring(userId)
		item.LayoutOrder = index
		item.Values.Number.TextColor3 = colorFrom
		item.Values.Number.Text = tostring(index)
		item.Values.Username.Text = username
		item.Values.Value.Text = tostring(rating)
		item.Parent = itemsFrame
		item.UIStroke.UIGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, colorFrom),
			ColorSequenceKeypoint.new(1, colorTo),
		})
	end

	listFrame.CanvasSize = UDim2.new(0, 0, 0, itemsFrame.UIListLayout.AbsoluteContentSize.Y + 35)
end

local function refresh()
	for _, player in ipairs(Players:GetPlayers()) do
		syncPlayerTotal(player.UserId, false)
	end

	updateLeaderboardDisplay()
end

Players.PlayerAdded:Connect(function(player)
	cachedTotalsByUserId[player.UserId] = nil
	sessionEntries[player.UserId] = 0
	task.defer(function()
		task.wait(5)
		syncPlayerTotal(player.UserId, true)
		cacheTimestamp = 0
		updateLeaderboardDisplay()
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	task.defer(function()
		task.wait(2)
		syncPlayerTotal(player.UserId, true)
		sessionEntries[player.UserId] = nil
		cacheTimestamp = 0
		updateLeaderboardDisplay()
	end)
end)

task.defer(function()
	refresh()
	updateLeaderboardDisplay()
end)

-- Add random offset to prevent all leaderboards updating at once
local randomOffset = math.random(0, 30)
task.wait(randomOffset)

while task.wait(UPDATE_INTERVAL) do
	refresh()
	updateLeaderboardDisplay()
end

