--[[
	Total Playtime Leaderboard Script

	This script is meant to be copied manually into the SurfaceGui script
	inside `Workspace/Demon Japan LeaderBoard/LeaderBoard/SurfaceGui`.
	It reads playtime data from PlaytimeService and displays a cross-server
	leaderboard backed by an OrderedDataStore.
]]

-- Configuration
local DISPLAY_NAME = "Total Playtime"
local DATASTORE_KEY = "GlobalLeaderboard_TotalPlaytimeSeconds"
local MAX_ITEMS = 100
local MIN_VALUE_DISPLAY = 0
local MAX_VALUE_DISPLAY = 9.9e14 -- Roughly 30000 years in seconds
local UPDATE_INTERVAL = 120 -- Seconds between refreshes (2 minutes)
local MIN_DELTA_TO_SAVE = 60 -- Minimum seconds before writing to DataStore
local DATASTORE_RETRIES = 3
local RETRY_BACKOFF = 2 -- Seconds

-- Services
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local PlaytimeService = require(game.ServerScriptService.Services.PlaytimeService)
if PlaytimeService.Init then
	-- Safe to call multiple times (service guards against re-init)
	PlaytimeService.Init()
end

local dataStore = DataStoreService:GetOrderedDataStore(DATASTORE_KEY)

-- UI References (expecting SurfaceGui > Script hierarchy)
local surfaceGui = script.Parent
local sample = script:WaitForChild("Sample")
local listFrame = surfaceGui.Frame.List
local itemsFrame = listFrame.ListContent.Items

-- Internal state
local cachedSecondsByUserId = {}  -- userId -> last value written to DataStore
local lastProfilePlaytime = {}    -- userId -> last totalTime from profile (for delta calculation)
local sessionEntries = {}

-- Utils
local function roundNumber(value)
	if typeof(value) ~= "number" then
		return 0
	end
	return math.floor(value + 0.5)
end

local function formatSeconds(seconds)
	seconds = math.max(0, roundNumber(seconds or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60

	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end

	return string.format("%02d:%02d", minutes, secs)
end

local function writeSecondsToDataStore(userId, seconds, delta)
	seconds = roundNumber(seconds)
	delta = roundNumber(delta or 0)
	
	for attempt = 1, DATASTORE_RETRIES do
		local success, err = pcall(function()
			dataStore:UpdateAsync(userId, function(currentValue)
				local existing = tonumber(currentValue) or 0
				
				if delta > 0 then
					return existing + delta
				end
				
				return math.max(existing, seconds)
			end)
		end)

		if success then
			return true
		end

		warn(string.format("[Leaderboard] Failed to write playtime for user %d (attempt %d/%d): %s",
			userId, attempt, DATASTORE_RETRIES, tostring(err)))
		task.wait(RETRY_BACKOFF * attempt)
	end

	return false
end

local function getCurrentPlaytimeSeconds(userId)
	local success, data = pcall(function()
		return PlaytimeService.GetPlaytimeData(userId)
	end)

	if not success then
		warn(string.format("[Leaderboard] Failed to read playtime for user %d: %s",
			userId, tostring(data)))
		return nil
	end

	if data and data.totalTime then
		return math.max(0, roundNumber(data.totalTime))
	end

	return nil
end

local function syncPlayerPlaytime(userId, forceWrite)
	local playtimeSeconds = getCurrentPlaytimeSeconds(userId)
	if not playtimeSeconds then
		return
	end

	sessionEntries[userId] = playtimeSeconds

	local lastProfileValue = lastProfilePlaytime[userId]
	local delta = 0
	
	if lastProfileValue then
		if playtimeSeconds >= lastProfileValue then
			delta = playtimeSeconds - lastProfileValue
		end
	else
		local lastRecorded = cachedSecondsByUserId[userId]
		if lastRecorded then
			if playtimeSeconds < lastRecorded * 0.5 then
				delta = 0
			else
				delta = math.max(0, playtimeSeconds - (lastRecorded or 0))
			end
		else
			-- First write ever - use current value
			delta = playtimeSeconds
		end
	end

	local lastRecorded = cachedSecondsByUserId[userId]
	local shouldWrite = false
	
	if forceWrite then
		shouldWrite = true
	elseif lastProfileValue then
		shouldWrite = delta >= MIN_DELTA_TO_SAVE
	else
		shouldWrite = true
	end

	if shouldWrite then
		if writeSecondsToDataStore(userId, playtimeSeconds, delta) then
			cachedSecondsByUserId[userId] = (cachedSecondsByUserId[userId] or 0) + (delta > 0 and delta or 0)
			lastProfilePlaytime[userId] = playtimeSeconds
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
		for _, entry in ipairs(page) do
			table.insert(rows, {
				userId = tonumber(entry.key),
				seconds = tonumber(entry.value) or 0
			})
		end
		usedDataStore = true
	else
		warn("[Leaderboard] Failed to fetch leaderboard data: " .. tostring(sortedData))
	end

	if not usedDataStore then
		for userId, seconds in pairs(sessionEntries) do
			table.insert(rows, { userId = userId, seconds = seconds })
		end
		table.sort(rows, function(a, b)
			return a.seconds > b.seconds
		end)
		if #rows > MAX_ITEMS then
			rows = { table.unpack(rows, 1, MAX_ITEMS) }
		end
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
		local value = entry.seconds or 0
		local username = "[Not Available]"

		local player = Players:GetPlayerByUserId(userId)
		if player then
			username = player.Name
		else
			local successName, fetchedName = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
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
		item.Values.Value.Text = formatSeconds(value)
		item.Parent = itemsFrame
	end

	listFrame.CanvasSize = UDim2.new(0, 0, 0, itemsFrame.UIListLayout.AbsoluteContentSize.Y + 35)
end

local function refresh()
	for _, player in ipairs(Players:GetPlayers()) do
		syncPlayerPlaytime(player.UserId, false)
	end

	updateLeaderboardDisplay()
end

Players.PlayerAdded:Connect(function(player)
	cachedSecondsByUserId[player.UserId] = nil
	lastProfilePlaytime[player.UserId] = nil  -- Reset on player join
	sessionEntries[player.UserId] = 0
	task.defer(function()
		task.wait(5)
		syncPlayerPlaytime(player.UserId, true)
		updateLeaderboardDisplay()
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	task.defer(function()
		task.wait(2)
		syncPlayerPlaytime(player.UserId, true)
		sessionEntries[player.UserId] = nil
		lastProfilePlaytime[player.UserId] = nil  -- Clear on player leave
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

