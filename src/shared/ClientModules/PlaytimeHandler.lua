--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--// Modules
local Resolver = require(ReplicatedStorage.Modules.Assets.Resolver)

--// Module
local PlaytimeHandler = {}

--// State
PlaytimeHandler.Connections = {}
PlaytimeHandler._initialized = false

PlaytimeHandler.isAnimating = false
PlaytimeHandler.isTracking = false
PlaytimeHandler.startTime = 0
PlaytimeHandler.totalPlaytime = 0
PlaytimeHandler.lastSaveTime = 0
PlaytimeHandler.rewardsConfig = {}
PlaytimeHandler.claimedRewards = {}

--// Constants
local REWARD_THRESHOLDS = {3, 6, 9, 12, 15, 18, 22} -- minutes
local SAVE_INTERVAL = 30 -- seconds

--// Initialization
function PlaytimeHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	
	-- Safe require of Utilities to avoid loading errors
	local success, utilities = pcall(function()
		return controller:GetModule("Utilities")
	end)
	
	if success then
		self.Utilities = utilities
	else
		warn("PlaytimeHandler: Could not load Utilities module: " .. tostring(utilities))
		self.Utilities = {
			TweenUI = { FadeIn = function() end, FadeOut = function() end },
			Blur = { Show = function() end, Hide = function() end }
		}
	end

	-- Initialize state
	self.Connections = {}
	self.isTracking = false
	self.startTime = 0
	self.totalPlaytime = 0
	self.lastSaveTime = 0
	self.rewardsConfig = {}
	self.claimedRewards = {}

	-- Setup playtime functionality
	self:SetupPlaytime()

	self._initialized = true
	print("✅ PlaytimeHandler initialized successfully!")
	return true
end

function PlaytimeHandler:SetupPlaytime()
	-- Access UI from player's PlayerGui (which should be copied from StarterGui)
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	
	-- Debug: Print all children in PlayerGui
	for _, child in pairs(playerGui:GetChildren()) do
	end
	
	-- Wait for Roblox to automatically clone GameUI from StarterGui
	local gameGui = playerGui:WaitForChild("GameUI", 5) -- Initial wait
	
	if not gameGui then
		gameGui = playerGui:WaitForChild("GameUI", 10) -- Extended wait
		
		if not gameGui then
			warn("PlaytimeHandler: GameUI not found in PlayerGui after extended waiting")
			return
		end
	end
	
	
	-- Check if Playtime frame exists
	local playtimeFrame = gameGui:FindFirstChild("Playtime")
	if not playtimeFrame then
		warn("PlaytimeHandler: Playtime frame not found in " .. gameGui.Name .. " - Playtime UI not available")
		for _, child in pairs(gameGui:GetChildren()) do
		end
		return
	end
	
	
	-- Store UI reference for later use
	self.UI = gameGui
	self.PlaytimeFrame = playtimeFrame
	
	-- Hide playtime initially
	playtimeFrame.Visible = false
	
	-- Setup playtime functionality
	self:SetupOpenButton()
	self:SetupCloseButton()
	self:SetupClaimButtons()
	
	-- Load saved playtime data
	self:LoadPlaytimeData()
	
	-- Start time tracking
	self:StartTimeTracking()
	
	-- Setup ProfileUpdated handler
	self:SetupProfileUpdatedHandler()
	
	print("✅ PlaytimeHandler: Playtime UI setup completed")
end

function PlaytimeHandler:SetupOpenButton()
	-- Look for playtime button in the UI
	-- Path: GameUI -> LeftPanel -> Playtime -> Button
	
	local leftPanel = self.UI:FindFirstChild("LeftPanel")
	if not leftPanel then
		warn("PlaytimeHandler: LeftPanel not found in GameUI")
		return
	end
	
	
	local playtimeButton = leftPanel:FindFirstChild("BtnPlaytime")
	if not playtimeButton then
		warn("PlaytimeHandler: Button not found in Playtime frame")
		return
	end
	
	
	-- Test if the button has the right events
	if playtimeButton:IsA("TextButton") then
		local connection = playtimeButton.MouseButton1Click:Connect(function()
			self:OpenWindow()
		end)
		table.insert(self.Connections, connection)
		print("✅ PlaytimeHandler: Open button connected")
	else
		warn("PlaytimeHandler: Found element '" .. playtimeButton.Name .. "' but it's not a GuiButton (it's a " .. playtimeButton.ClassName .. ")")
	end
end

function PlaytimeHandler:SetupCloseButton()
	-- Look for close button in the playtime frame
	local closeButton = self.PlaytimeFrame:FindFirstChild("TopPanel")
	if closeButton then
		closeButton = closeButton:FindFirstChild("BtnClose")
		if closeButton then
			closeButton = closeButton:FindFirstChild("Button")
		end
	end
	
	if not closeButton then
		warn("PlaytimeHandler: Close button not found - you may need to add a CloseButton to Playtime frame")
		return
	end

	local connection = closeButton.MouseButton1Click:Connect(function()
		self:CloseWindow()
	end)

	table.insert(self.Connections, connection)
	print("✅ PlaytimeHandler: Close button connected")
end

function PlaytimeHandler:SetupClaimButtons()
	-- Look for reward list
	local listFrame = self.PlaytimeFrame:FindFirstChild("List")
	if not listFrame then
		warn("PlaytimeHandler: List frame not found in Playtime frame")
		return
	end
	
	-- Setup claim buttons for each reward slot
	for i = 1, 7 do
		local rewardFrame = listFrame:FindFirstChild("Reward" .. i)
		if rewardFrame then
			local claimButton = rewardFrame:FindFirstChild("Content")
			if claimButton then
				claimButton = claimButton:FindFirstChild("BtnClaim")
			end
			
			if claimButton then
				local connection = claimButton.MouseButton1Click:Connect(function()
					self:ClaimReward(i)
				end)
				table.insert(self.Connections, connection)
				print("✅ PlaytimeHandler: Claim button connected for Reward" .. i)
			else
				warn("PlaytimeHandler: Claim button not found for Reward" .. i)
			end
		else
			warn("PlaytimeHandler: Reward" .. i .. " frame not found")
		end
	end
end

function PlaytimeHandler:LoadPlaytimeData()
	-- Load playtime data from client state
	if self.ClientState and self.ClientState.GetState then
		local state = self.ClientState:GetState()
		if state and state.playtime then
			self.totalPlaytime = state.playtime.totalTime or 0
			self.claimedRewards = state.playtime.claimedRewards or {}
		end
	end
end

function PlaytimeHandler:SavePlaytimeData()
	-- Save playtime data to client state
	if self.ClientState and self.ClientState.SetState then
		local state = self.ClientState:GetState() or {}
		state.playtime = {
			totalTime = self.totalPlaytime,
			claimedRewards = self.claimedRewards
		}
		self.ClientState:SetState(state)
	end
end

function PlaytimeHandler:StartTimeTracking()
	if self.isTracking then return end
	
	self.isTracking = true
	self.startTime = tick()
	self.lastSaveTime = self.startTime
	
	-- Connect to RunService for continuous tracking
	local connection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		local sessionTime = currentTime - self.startTime
		self.totalPlaytime = self.totalPlaytime + sessionTime
		self.startTime = currentTime
		
		-- Save periodically
		if currentTime - self.lastSaveTime >= SAVE_INTERVAL then
			self:SavePlaytimeData()
			self.lastSaveTime = currentTime
		end
		
		-- Update UI if window is open
		if self.PlaytimeFrame and self.PlaytimeFrame.Visible then
			self:UpdatePlaytimeDisplay()
		end
	end)
	
	table.insert(self.Connections, connection)
	print("✅ PlaytimeHandler: Time tracking started")
end

function PlaytimeHandler:StopTimeTracking()
	if not self.isTracking then return end
	
	-- Save final time
	local currentTime = tick()
	local sessionTime = currentTime - self.startTime
	self.totalPlaytime = self.totalPlaytime + sessionTime
	self:SavePlaytimeData()
	
	self.isTracking = false
	print("✅ PlaytimeHandler: Time tracking stopped")
end

function PlaytimeHandler:GetCurrentPlaytimeMinutes()
	return math.floor(self.totalPlaytime / 60)
end

function PlaytimeHandler:IsRewardClaimed(rewardIndex)
	for _, claimedIndex in ipairs(self.claimedRewards) do
		if claimedIndex == rewardIndex then
			return true
		end
	end
	return false
end

function PlaytimeHandler:IsRewardAvailable(rewardIndex)
	local threshold = REWARD_THRESHOLDS[rewardIndex]
	if not threshold then return false end
	
	local currentMinutes = self:GetCurrentPlaytimeMinutes()
	return currentMinutes >= threshold and not self:IsRewardClaimed(rewardIndex)
end

function PlaytimeHandler:ClaimReward(rewardIndex)
	if not self:IsRewardAvailable(rewardIndex) then
		return
	end
	
	
	-- Add to claimed rewards
	table.insert(self.claimedRewards, rewardIndex)
	
	-- Save data
	self:SavePlaytimeData()
	
	-- Update UI
	self:UpdateRewardDisplay(rewardIndex)
	
	-- TODO: Send to server for validation and actual reward granting
	-- NetworkClient.requestClaimPlaytimeReward(rewardIndex)
	
	print("✅ PlaytimeHandler: Reward " .. rewardIndex .. " claimed")
end

function PlaytimeHandler:LoadRewardsConfig()
	-- TODO: Load rewards configuration from server
	-- For now, use mock data
	self.rewardsConfig = {
		[1] = { -- 3 minutes
			{type = "Currency", name = "Soft", amount = 90}
		},
		[2] = { -- 6 minutes
            {type = "Currency", name = "Soft", amount = 120}
		},
		[3] = { -- 9 minutes
			{type = "Currency", name = "Soft", amount = 150},
			{type = "Currency", name = "Hard", amount = 20}
		},
		[4] = { -- 12 minutes
			{type = "Currency", name = "Soft", amount = 195},
			{type = "Lootbox", name = "Uncommon", amount = 1}
		},
		[5] = { -- 15 minutes
			{type = "Currency", name = "Soft", amount = 225},
		},
		[6] = { -- 18 minutes
			{type = "Currency", name = "Soft", amount = 300},
			{type = "Currency", name = "Hard", amount = 30},
			{type = "Lootbox", name = "Rare", amount = 1}
		},
		[7] = { -- 22 minutes
			{type = "Currency", name = "Soft", amount = 375}
		}
	}
	
	print("✅ PlaytimeHandler: Rewards config loaded")
end

function PlaytimeHandler:UpdatePlaytimeDisplay()
	-- Update current playtime display
	local listFrame = self.PlaytimeFrame:FindFirstChild("List")
	if not listFrame then return end
	
	local currentMinutes = self:GetCurrentPlaytimeMinutes()
	
	-- Update each reward's time display
	for i = 1, 7 do
		local rewardFrame = listFrame:FindFirstChild("Reward" .. i)
		if rewardFrame then
			local content = rewardFrame:FindFirstChild("Content")
			if content then
				local txtTime = content:FindFirstChild("TxtTime")
				if txtTime then
					txtTime.Text = currentMinutes .. " min"
				end
			end
		end
	end
end

function PlaytimeHandler:UpdateRewardDisplay(rewardIndex)
	local listFrame = self.PlaytimeFrame:FindFirstChild("List")
	if not listFrame then return end
	
	local rewardFrame = listFrame:FindFirstChild("Reward" .. rewardIndex)
	if not rewardFrame then return end
	
	local content = rewardFrame:FindFirstChild("Content")
	if not content then return end
	
	-- Update header with threshold time
	local header = content:FindFirstChild("Header")
	if header then
		local headerContent = header:FindFirstChild("Content")
		if headerContent then
			local text = headerContent:FindFirstChild("Text")
			if text then
				local textLabel = text:FindFirstChild("TextLabel")
				if textLabel then
					textLabel.Text = REWARD_THRESHOLDS[rewardIndex] .. " min"
				end
			end
		end
	end
	
	-- Update claim button visibility
	local btnClaim = content:FindFirstChild("BtnClaim")
	local imgClaimed = content:FindFirstChild("ImgClaimed")
	
	if self:IsRewardClaimed(rewardIndex) then
		if btnClaim then btnClaim.Visible = false end
		if imgClaimed then imgClaimed.Visible = true end
	elseif self:IsRewardAvailable(rewardIndex) then
		if btnClaim then btnClaim.Visible = true end
		if imgClaimed then imgClaimed.Visible = false end
	else
		if btnClaim then btnClaim.Visible = false end
		if imgClaimed then imgClaimed.Visible = false end
	end
	
	-- Update rewards display
	local rewardsContent = content:FindFirstChild("Content")
	if rewardsContent and self.rewardsConfig[rewardIndex] then
		local rewards = self.rewardsConfig[rewardIndex]
		
		for i, reward in ipairs(rewards) do
			local rewardFrame = rewardsContent:FindFirstChild("Reward" .. i)
			if rewardFrame then
				-- Update reward image
				local imgReward = rewardFrame:FindFirstChild("ImgReward")
				if imgReward then
					local assetId = Resolver.getRewardAsset(reward.type, reward.name)
					imgReward.Image = assetId
				end
				
				-- Update reward amount
				local txtValue = rewardFrame:FindFirstChild("TxtValue")
				if txtValue then
					txtValue.Text = tostring(reward.amount)
				end
			end
		end
	end
end

function PlaytimeHandler:UpdateAllRewardsDisplay()
	-- Update all reward displays
	for i = 1, 7 do
		self:UpdateRewardDisplay(i)
	end
end

function PlaytimeHandler:OpenWindow()
	if self.isAnimating then return end
	self.isAnimating = true

	-- Load rewards config if not loaded
	if not next(self.rewardsConfig) then
		self:LoadRewardsConfig()
	end

	-- Hide HUD panels if they exist
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = false
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = false
	end

	-- Update all displays
	self:UpdatePlaytimeDisplay()
	self:UpdateAllRewardsDisplay()

	-- Show playtime gui
	self.PlaytimeFrame.Visible = true

	-- Use TweenUI if available, otherwise just show
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
			self.Utilities.TweenUI.FadeIn(self.PlaytimeFrame, .3, function ()
				self.isAnimating = false
			end)
		end
		if self.Utilities.Blur then
			self.Utilities.Blur.Show()
		end
	else
		-- Fallback: no animation
		self.isAnimating = false
	end
	
	print("✅ PlaytimeHandler: Playtime window opened")
end

function PlaytimeHandler:CloseWindow()
	if self.isAnimating then return end
	self.isAnimating = true

	-- Hide playtime gui
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
			self.Utilities.TweenUI.FadeOut(self.PlaytimeFrame, .3, function () 
				self.PlaytimeFrame.Visible = false
				self.isAnimating = false
			end)
		end
		if self.Utilities.Blur then
			self.Utilities.Blur.Hide()
		end
	else
		-- Fallback: no animation
		self.PlaytimeFrame.Visible = false
		self.isAnimating = false
	end

	-- Show HUD panels
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = true
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = true
	end
	
	print("✅ PlaytimeHandler: Playtime window closed")
end

function PlaytimeHandler:SetupProfileUpdatedHandler()
	-- Listen for ProfileUpdated events to handle playtime reward responses
	local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
	
	local connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
		-- Check if this is a playtime reward response
		if payload.playtimeReward then
			-- TODO: Handle server response for playtime rewards
		end
	end)
	
	-- Store connection for cleanup
	table.insert(self.Connections, connection)
end

--// Public Methods
function PlaytimeHandler:IsInitialized()
	return self._initialized
end

function PlaytimeHandler:GetTotalPlaytime()
	return self.totalPlaytime
end

function PlaytimeHandler:GetCurrentPlaytimeMinutes()
	return math.floor(self.totalPlaytime / 60)
end

--// Cleanup
function PlaytimeHandler:Cleanup()

	-- Stop time tracking
	self:StopTimeTracking()

	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}

	self._initialized = false
	print("✅ PlaytimeHandler cleaned up")
end

return PlaytimeHandler
