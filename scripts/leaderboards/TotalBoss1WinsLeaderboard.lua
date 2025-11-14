--[[
	Total Boss 1 Wins Leaderboard Script

	Copy this into the SurfaceGui Script for the Boss 1 wins leaderboard model.
	It reads the player's boss win counters (profile.bossWins["1"]) and publishes
	the totals via an OrderedDataStore so the leaderboard stays global.
]]

-- Configuration
local DISPLAY_NAME = "Boss 1 Wins"
local DATASTORE_KEY = "GlobalLeaderboard_Boss1Wins"
local MAX_ITEMS = 100
local MIN_VALUE_DISPLAY = 0
local MAX_VALUE_DISPLAY = 9.9e14
local UPDATE_INTERVAL = 120 -- seconds (2 minutes)
local MIN_DELTA_TO_SAVE = 1
local DATASTORE_RETRIES = 3
local RETRY_BACKOFF = 2 -- seconds

-- Services & modules
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local ProfileManager = require(game.ServerScriptService.Persistence.ProfileManager)

local dataStore = DataStoreService:GetOrderedDataStore(DATASTORE_KEY)

-- UI references
local surfaceGui = script.Parent
local sample = script:WaitForChild("Sample")
local listFrame = surfaceGui.Frame.List
local itemsFrame = listFrame.ListContent.Items

-- Internal state
local cachedTotalsByUserId = {}
local sessionEntries = {}

local function roundNumber(value)
	if typeof(value) ~= "number" then
		return 0
	end
	return math.floor(value + 0.5)
end

local function getBossWins(userId)
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

	local bossWins = profile.bossWins or {}
	return math.max(0, roundNumber(bossWins["1"] or 0))
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

		warn(string.format("[Boss1WinsLeaderboard] Failed to write value for user %d (attempt %d/%d): %s",
			userId, attempt, DATASTORE_RETRIES, tostring(err)))
		task.wait(RETRY_BACKOFF * attempt)
	end

	return false
end

local function syncPlayerTotal(userId, forceWrite)
	local total = getBossWins(userId)
	if total == nil then
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

local function clearItems()
	for _, child in ipairs(itemsFrame:GetChildren()) do
		if child:IsA("ImageLabel") then
			child:Destroy()
		end
	end
end

local function buildRows()
	local rows = {}
	local usedDataStore = false

	local success, sortedData = pcall(function()
		return dataStore:GetSortedAsync(false, MAX_ITEMS, MIN_VALUE_DISPLAY, MAX_VALUE_DISPLAY)
	end)

	if success then
		local page = sortedData:GetCurrentPage()
		local indexByUserId = {}

		for _, entry in ipairs(page) do
			local userId = tonumber(entry.key)
			local wins = tonumber(entry.value) or 0
			table.insert(rows, {
				userId = userId,
				wins = wins
			})
			indexByUserId[userId] = #rows
		end

		for userId, wins in pairs(sessionEntries) do
			local existingIndex = indexByUserId[userId]
			if existingIndex then
				if wins > rows[existingIndex].wins then
					rows[existingIndex].wins = wins
				end
			else
				table.insert(rows, { userId = userId, wins = wins })
			end
		end

		usedDataStore = true
	else
		warn("[Boss1WinsLeaderboard] Failed to fetch leaderboard data: " .. tostring(sortedData))
	end

	if not usedDataStore then
		for userId, wins in pairs(sessionEntries) do
			table.insert(rows, { userId = userId, wins = wins })
		end
	end

	table.sort(rows, function(a, b)
		return (a.wins or 0) > (b.wins or 0)
	end)

	if #rows > MAX_ITEMS then
		rows = { table.unpack(rows, 1, MAX_ITEMS) }
	end

	return rows
end

local function updateLeaderboardDisplay()
	local rows = buildRows()

	surfaceGui.Heading.Heading.Text = DISPLAY_NAME
	listFrame.ListContent.GuideTopBar.Value.Text = DISPLAY_NAME

	itemsFrame.Nothing.Visible = (#rows == 0)
	clearItems()

	for index, entry in ipairs(rows) do
		local userId = entry.userId
		local wins = entry.wins or 0
		local username = "[Not Available]"

		local player = Players:GetPlayerByUserId(userId or 0)
		if player then
			username = player.Name
		else
			local successName, fetchedName = pcall(function()
				return Players:GetNameFromUserIdAsync(userId or 0)
			end)
			if successName and fetchedName then
				username = fetchedName
			end
		end

		local color = Color3.fromRGB(38, 50, 56)
		if index == 1 then
			color = Color3.fromRGB(255, 215, 0)
		elseif index == 2 then
			color = Color3.fromRGB(192, 192, 192)
		elseif index == 3 then
			color = Color3.fromRGB(205, 127, 50)
		end

		local item = sample:Clone()
		item.Name = tostring(userId)
		item.LayoutOrder = index
		item.Values.Number.TextColor3 = color
		item.Values.Number.Text = tostring(index)
		item.Values.Username.Text = username
		item.Values.Value.Text = tostring(wins)
		item.Parent = itemsFrame
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
		updateLeaderboardDisplay()
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	task.defer(function()
		task.wait(2)
		syncPlayerTotal(player.UserId, true)
		sessionEntries[player.UserId] = nil
		updateLeaderboardDisplay()
	end)
end)

task.defer(function()
	refresh()
	updateLeaderboardDisplay()
end)

while task.wait(UPDATE_INTERVAL) do
	refresh()
	updateLeaderboardDisplay()
end

