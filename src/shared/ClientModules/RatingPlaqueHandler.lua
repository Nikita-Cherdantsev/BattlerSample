--[[
	RatingPlaqueHandler - Displays PvP rating above player heads
	
	Creates a BillboardGui above each player's character showing their ranked rating.
	Uses leaderstats.Rating (replicated from server) as the data source.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RatingPlaqueHandler = {}
RatingPlaqueHandler._initialized = false

-- Plaque styling
local PLAQUE_OFFSET = Vector3.new(0, 2.5, 0)
local DEFAULT_RATING = 1000

-- Color by rating (500-point tiers)
local function getColorForRating(rating)
	local r = math.floor(tonumber(rating) or 0)
	if r >= 4000 then return Color3.fromRGB(220, 50, 50) end   -- red
	if r >= 3500 then return Color3.fromRGB(180, 80, 220) end   -- purple
	if r >= 3000 then return Color3.fromRGB(80, 140, 255) end  -- blue
	if r >= 2500 then return Color3.fromRGB(60, 200, 220) end   -- cyan
	if r >= 2000 then return Color3.fromRGB(100, 220, 120) end -- green
	if r >= 1500 then return Color3.fromRGB(255, 220, 60) end  -- gold
	if r >= 1000 then return Color3.fromRGB(255, 180, 50) end  -- amber
	return Color3.fromRGB(255, 140, 60)                          -- orange
end

local function formatRating(value)
	local n = math.floor(tonumber(value) or DEFAULT_RATING)
	if n < 0 then n = 0 end
	local s = tostring(n)
	local k = #s % 3
	if k == 0 then k = 3 end
	return s:sub(1, k) .. s:sub(k + 1):gsub("(%d%d%d)", ",%1")
end

local function createPlaqueGui(player)
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then return nil end

	local screenGui = playerGui:FindFirstChild("RatingPlaques")
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "RatingPlaques"
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = true
		screenGui.DisplayOrder = 10
		screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screenGui.Parent = playerGui
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RatingPlaque_" .. tostring(player.UserId)
	billboard.Adornee = nil
	billboard.Size = UDim2.new(3, 0, 1, 0)
	billboard.StudsOffset = PLAQUE_OFFSET
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 100
	billboard.Parent = screenGui

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent = billboard

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.05, 0)
	layout.Parent = container

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(0.35, 0, 1, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = "🔥"
	iconLabel.TextColor3 = getColorForRating(DEFAULT_RATING)
	iconLabel.TextScaled = true
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.Parent = container

	local label = Instance.new("TextLabel")
	label.Name = "Rating"
	label.Size = UDim2.new(0.6, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = formatRating(DEFAULT_RATING)
	label.TextColor3 = getColorForRating(DEFAULT_RATING)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = container

	return { billboard = billboard, label = label, iconLabel = iconLabel }
end

local function setupPlaqueForPlayer(player)
	local character = player.Character or player.CharacterAdded:Wait()
	local head = character:WaitForChild("Head", 5)
	if not head then return end

	local plaque = createPlaqueGui(player)
	if not plaque then return end

	plaque.billboard.Adornee = head

	local function updateRating()
		local leaderstats = player:FindFirstChild("leaderstats")
		local ratingVal = leaderstats and leaderstats:FindFirstChild("Rating")
		local value = (ratingVal and ratingVal:IsA("IntValue")) and ratingVal.Value or DEFAULT_RATING
		local color = getColorForRating(value)
		plaque.label.Text = formatRating(value)
		plaque.label.TextColor3 = color
		if plaque.iconLabel then
			plaque.iconLabel.TextColor3 = color
		end
	end

	updateRating()

	-- leaderstats is created by server; wait for it and connect to updates
	task.defer(function()
		local leaderstats = player:WaitForChild("leaderstats", 15)
		if leaderstats then
			local ratingVal = leaderstats:WaitForChild("Rating", 5)
			if ratingVal and ratingVal:IsA("IntValue") then
				ratingVal.Changed:Connect(updateRating)
				updateRating()
			end
		end
	end)

	player.CharacterAdded:Connect(function()
		local newChar = player.Character
		if not newChar then return end
		local newHead = newChar:WaitForChild("Head", 5)
		if newHead then
			plaque.billboard.Adornee = newHead
		end
	end)
end

local function cleanupPlaqueForPlayer(player)
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then return end
	local screenGui = playerGui:FindFirstChild("RatingPlaques")
	if not screenGui then return end
	local billboard = screenGui:FindFirstChild("RatingPlaque_" .. tostring(player.UserId))
	if billboard then
		billboard:Destroy()
	end
end

function RatingPlaqueHandler:Init(controller)
	if self._initialized then
		return true
	end

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			setupPlaqueForPlayer(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			setupPlaqueForPlayer(player)
		end)
	end)

	Players.PlayerRemoving:Connect(cleanupPlaqueForPlayer)

	self._initialized = true
	return true
end

return RatingPlaqueHandler
