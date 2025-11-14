--[[
	Total Robux Spent Leaderboard Script

	This script should be pasted into the SurfaceGui script of the Robux leaderboard.
	It tracks how much Robux each player has spent on developer products (hard currency packs)
	and synchronizes the totals across servers via an OrderedDataStore.
]]

-- Configuration
local DISPLAY_NAME = "Total Robux Spent"
local DATASTORE_KEY = "GlobalLeaderboard_TotalRobuxSpent"
local MAX_ITEMS = 100
local MIN_VALUE_DISPLAY = 0
local MAX_VALUE_DISPLAY = 9.9e14
local UPDATE_INTERVAL = 120 -- seconds (2 minutes)
local MIN_DELTA_TO_SAVE = 1 -- Robux increments are whole numbers
local DATASTORE_RETRIES = 3
local RETRY_BACKOFF = 2 -- seconds

-- Services
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local ProfileManager = require(game.ServerScriptService.Persistence.ProfileManager)

local dataStore = DataStoreService:GetOrderedDataStore(DATASTORE_KEY)

-- UI references (expecting SurfaceGui -> Script)
local surfaceGui = script.Parent
local sample = script:WaitForChild("Sample")
local listFrame = surfaceGui.Frame.List
local itemsFrame = listFrame.ListContent.Items

-- Internal state
local cachedTotalsByUserId = {}
local sessionEntries = {}

-- Helpers
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

local function getTotalRobuxSpent(userId)
	local profile = getProfile(userId)
	if not profile then
		return nil
	end

	return math.max(0, roundNumber(profile.totalRobuxSpent or 0))
end

local function writeTotalToDataStore(userId, amount)
	amount = roundNumber(amount)
	for attempt = 1, DATASTORE_RETRIES do
		local success, err = pcall(function()
			dataStore:UpdateAsync(userId, function()
				return amount
			end)
		end)

		if success then
			return true
		end

		warn(string.format("[RobuxLeaderboard] Failed to write value for user %d (attempt %d/%d): %s",
			userId, attempt, DATASTORE_RETRIES, tostring(err)))
		task.wait(RETRY_BACKOFF * attempt)
	end

	return false
end

local function syncPlayerTotal(userId, forceWrite)
	local total = getTotalRobuxSpent(userId)
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
			local total = tonumber(entry.value) or 0
			table.insert(rows, {
				userId = userId,
				total = total
			})
			indexByUserId[userId] = #rows
		end

		for userId, total in pairs(sessionEntries) do
			if indexByUserId[userId] and total > rows[indexByUserId[userId]].total then
				rows[indexByUserId[userId]].total = total
			elseif not indexByUserId[userId] then
				table.insert(rows, { userId = userId, total = total })
			end
		end

		usedDataStore = true
	else
		warn("[RobuxLeaderboard] Failed to fetch leaderboard data: " .. tostring(sortedData))
	end

	if not usedDataStore then
		for userId, total in pairs(sessionEntries) do
			table.insert(rows, { userId = userId, total = total })
		end
		table.sort(rows, function(a, b)
			return a.total > b.total
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
		local total = entry.total or 0
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
		item.Values.Value.Text = tostring(total)
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

