--[[
	Total Collection Power Leaderboard Script

	Manually copy this script into the SurfaceGui Script of the collection-power
	leaderboard model. It sums the power of every card in a player's collection
	(using the current level of each card) and syncs the totals through an
	OrderedDataStore so the leaderboard is global.
]]

-- Configuration
local DISPLAY_NAME = "Total Collection Power"
local DATASTORE_KEY = "GlobalLeaderboard_TotalCollectionPower"
local MAX_ITEMS = 100
local MIN_VALUE_DISPLAY = 0
local MAX_VALUE_DISPLAY = 9.9e14
local UPDATE_INTERVAL = 120 -- seconds between refreshes (2 minutes)
local MIN_DELTA_TO_SAVE = 1 -- any positive change triggers a save
local DATASTORE_RETRIES = 3
local RETRY_BACKOFF = 2 -- seconds (exponential backoff multiplier)
local CACHE_DURATION = 30 -- Cache GetSorted results for 30 seconds
local BUDGET_THRESHOLD = 0.5 -- Only make requests if budget > 50%

-- Services & modules
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local ProfileManager = require(game.ServerScriptService.Persistence.ProfileManager)
local CardStats = require(game.ReplicatedStorage.Modules.Cards.CardStats)
local Manifest = require(game.ReplicatedStorage.Modules.Assets.Manifest)

local dataStore = DataStoreService:GetOrderedDataStore(DATASTORE_KEY)

-- UI references (SurfaceGui -> Script)
local surfaceGui = script.Parent
local sample = script:WaitForChild("Sample")
local listFrame = surfaceGui.Frame.List
local itemsFrame = listFrame.ListContent.Items

-- Internal state
local cachedTotalsByUserId = {}
local sessionEntries = {}
local cachedLeaderboardData = nil  -- Cached leaderboard rows
local cacheTimestamp = 0  -- When cache was last updated

-- Cache for usernames to avoid repeated API calls
local usernameCache = {}
local CACHE_USERNAME_DURATION = 300 -- Cache usernames for 5 minutes

local function roundNumber(value)
	if typeof(value) ~= "number" then
		return 0
	end
	return math.floor(value + 0.5)
end

local function getProfile(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	if profile then
		return profile
	end

	local success, loaded = pcall(function()
		return ProfileManager.LoadProfile(userId)
	end)

	if success then
		return loaded
	end

	return nil
end

local function computeCollectionPower(userId)
	local profile = getProfile(userId)
	if not profile or not profile.collection then
		return nil
	end

	local total = 0
	for cardId, entry in pairs(profile.collection) do
		local level = entry and entry.level or 1
		level = math.max(1, math.floor(level))
		total = total + CardStats.ComputeCardPower(cardId, level)
	end

	return roundNumber(total)
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

		warn(string.format("[CollectionPowerLeaderboard] Failed to write value for user %d (attempt %d/%d): %s",
			userId, attempt, DATASTORE_RETRIES, tostring(err)))
		task.wait(RETRY_BACKOFF * attempt)
	end

	return false
end

local function syncPlayerTotal(userId, forceWrite)
	local total = computeCollectionPower(userId)
	if not total then
		return
	end

	sessionEntries[userId] = total

	local lastRecorded = cachedTotalsByUserId[userId]
	local delta = lastRecorded and math.abs(total - lastRecorded) or math.huge

	if forceWrite or delta >= MIN_DELTA_TO_SAVE then
		if writeTotalToDataStore(userId, total) then
			cachedTotalsByUserId[userId] = total
		end
	end
end

-- Get username with caching and improved error handling
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
		-- Update cache
		usernameCache[userId] = {
			username = username,
			timestamp = os.time()
		}
		return username
	end
	
	-- Try to fetch from API (with better error handling)
	local success, fetchedName = pcall(function()
		-- Validate userId before calling API
		if type(userId) ~= "number" or userId <= 0 then
			return nil
		end
		return Players:GetNameFromUserIdAsync(userId)
	end)
	
	if success and fetchedName and type(fetchedName) == "string" and fetchedName ~= "" then
		-- Update cache
		usernameCache[userId] = {
			username = fetchedName,
			timestamp = os.time()
		}
		return fetchedName
	end
	
	-- Fallback: return userId as string if we can't get name
	return "User " .. tostring(userId)
end

local function clearItems()
	for _, child in ipairs(itemsFrame:GetChildren()) do
		if child:IsA("ImageLabel") then
			child:Destroy()
		end
	end
end

-- Check DataStore budget before making requests
local function checkBudget()
	local success, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetSortedAsync)
	end)
	
	if success and budget then
		return budget >= BUDGET_THRESHOLD
	end
	
	-- If we can't check budget, allow request but with caution
	return true
end

local function buildRows()
	-- Use cached data if available and fresh
	local now = os.time()
	if cachedLeaderboardData and (now - cacheTimestamp) < CACHE_DURATION then
		return cachedLeaderboardData
	end
	
	local rows = {}
	local usedDataStore = false

	-- Check budget before making request
	if not checkBudget() then
		warn("[CollectionPowerLeaderboard] DataStore budget too low, using cached data or session entries")
		if cachedLeaderboardData then
			return cachedLeaderboardData
		end
		-- Fall through to session entries
	else
		local success, sortedData = pcall(function()
			return dataStore:GetSortedAsync(false, MAX_ITEMS, MIN_VALUE_DISPLAY, MAX_VALUE_DISPLAY)
		end)

		if success then
			local page = sortedData:GetCurrentPage()
			local indexByUserId = {}

			for _, entry in ipairs(page) do
				local userId = tonumber(entry.key)
				local total = tonumber(entry.value) or 0
				table.insert(rows, {
					userId = userId,
					total = total
				})
				indexByUserId[userId] = #rows
			end

			for userId, total in pairs(sessionEntries) do
				local existingIndex = indexByUserId[userId]
				if existingIndex then
					if total > rows[existingIndex].total then
						rows[existingIndex].total = total
					end
				else
					table.insert(rows, { userId = userId, total = total })
				end
			end

			usedDataStore = true
			-- Update cache
			cachedLeaderboardData = rows
			cacheTimestamp = now
		else
			warn("[CollectionPowerLeaderboard] Failed to fetch leaderboard data: " .. tostring(sortedData))
		end
	end

	if not usedDataStore then
		for userId, total in pairs(sessionEntries) do
			table.insert(rows, { userId = userId, total = total })
		end
	end

	table.sort(rows, function(a, b)
		return (a.total or 0) > (b.total or 0)
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
		local total = entry.total or 0
		local username = getUsername(userId)

		-- Get colors from Manifest based on position
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
			-- Default colors for positions 5+
			colorFrom = Color3.fromHex("#7A6B78")
			colorTo = Color3.fromHex("#221421")
		end

		local item = sample:Clone()
		item.Name = tostring(userId)
		item.LayoutOrder = index
		item.Values.Number.TextColor3 = colorFrom
		item.Values.Number.Text = tostring(index)
		item.Values.Username.Text = username
		item.Values.Value.Text = tostring(total)
		item.Parent = itemsFrame
		item.UIStroke.UIGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, colorFrom),
			ColorSequenceKeypoint.new(1, colorTo)
		})
	end

	listFrame.CanvasSize = UDim2.new(0, 0, 0, itemsFrame.UIListLayout.AbsoluteContentSize.Y + 35)
end

local function refresh()
	for _, player in ipairs(Players:GetPlayers()) do
		syncPlayerTotal(player.UserId, false)
	end

	-- Only update display, don't force refresh from DataStore
	updateLeaderboardDisplay()
end

Players.PlayerAdded:Connect(function(player)
	cachedTotalsByUserId[player.UserId] = nil
	sessionEntries[player.UserId] = 0
	task.defer(function()
		task.wait(5)
		syncPlayerTotal(player.UserId, true)
		-- Invalidate cache to force refresh
		cacheTimestamp = 0
		updateLeaderboardDisplay()
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	task.defer(function()
		task.wait(2)
		syncPlayerTotal(player.UserId, true)
		sessionEntries[player.UserId] = nil
		-- Invalidate cache to force refresh
		cacheTimestamp = 0
		updateLeaderboardDisplay()
	end)
end)

task.defer(function()
	refresh()
	updateLeaderboardDisplay()
end)

-- Add random offset to prevent all leaderboards updating at once
local randomOffset = math.random(0, 30)  -- 0-30 second offset
task.wait(randomOffset)

while task.wait(UPDATE_INTERVAL) do
	refresh()
	updateLeaderboardDisplay()
end
