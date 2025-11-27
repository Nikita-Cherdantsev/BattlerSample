--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
PlaytimeHandler.isWindowOpen = false
PlaytimeHandler.totalPlaytime = 0  -- Server time in seconds
PlaytimeHandler.lastServerSync = 0  -- Last server sync time (os.time())
PlaytimeHandler.rewardsConfig = {}
PlaytimeHandler.claimedRewards = {}  -- Array of claimed reward indices
PlaytimeHandler.claimedRewardsSet = {}  -- Set for fast lookup
PlaytimeHandler.thresholds = {}
PlaytimeHandler.NetworkClient = nil
PlaytimeHandler.updateTimer = nil
PlaytimeHandler.syncTask = nil
PlaytimeHandler.pendingClaim = nil
PlaytimeHandler.NotificationMarkerHandler = nil

--// Constants
local SYNC_INTERVAL = 5  -- Sync with server every 5 seconds

--// Initialization
function PlaytimeHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	
	-- Get NetworkClient
	local success, NetworkClient = pcall(function()
		local StarterPlayer = game:GetService("StarterPlayer")
		local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
		local Controllers = StarterPlayerScripts:WaitForChild("Controllers")
		return require(Controllers:WaitForChild("NetworkClient"))
	end)
	
	if success and NetworkClient then
		self.NetworkClient = NetworkClient
	else
		warn("PlaytimeHandler: Could not load NetworkClient: " .. tostring(NetworkClient))
		return false
	end
	
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
	self.totalPlaytime = 0
	self.lastServerSync = 0
	self.rewardsConfig = {}
	self.claimedRewards = {}
	self.claimedRewardsSet = {}
	self.thresholds = {}
	self.isWindowOpen = false
	self.updateTimer = nil
	self.syncTask = nil
	self.pendingClaim = nil

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
		return
	end
	
	-- Store UI reference for later use
	self.UI = gameGui
	self.PlaytimeFrame = playtimeFrame
	self.InputBlocker = playtimeFrame:FindFirstChild("InputBlocker")
	
	-- Hide playtime initially
	playtimeFrame.Visible = false
	
	-- Setup playtime functionality
	self:SetupOpenButton()
	self:SetupCloseButton()
	self:SetupClaimButtons()
	
	-- Setup ProfileUpdated handler
	self:SetupProfileUpdatedHandler()
	
	if self.NetworkClient then
		self.NetworkClient.requestPlaytimeData()
	end
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
	else
		warn("PlaytimeHandler: Found element '" .. playtimeButton.Name .. "' but it's not a GuiButton (it's a " .. playtimeButton.ClassName .. ")")
	end
end

function PlaytimeHandler:SetupCloseButton()
	-- Close button is now handled by CloseButtonHandler
	-- No need to set up individual close button here
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
			else
				warn("PlaytimeHandler: Claim button not found for Reward" .. i)
			end
		else
			warn("PlaytimeHandler: Reward" .. i .. " frame not found")
		end
	end
end

-- Get current playtime in seconds (server time + elapsed since last sync)
function PlaytimeHandler:GetCurrentPlaytime()
	local currentLocalTime = os.time()
	local elapsedSinceSync = currentLocalTime - self.lastServerSync
	return self.totalPlaytime + elapsedSinceSync
end

function PlaytimeHandler:GetCurrentPlaytimeMinutes()
	return math.floor(self:GetCurrentPlaytime() / 60)
end

function PlaytimeHandler:IsRewardClaimed(rewardIndex)
	return self.claimedRewardsSet[rewardIndex] == true
end

function PlaytimeHandler:IsRewardAvailable(rewardIndex)
	local threshold = self.thresholds[rewardIndex]
	if not threshold then return false end
	
	local currentMinutes = self:GetCurrentPlaytimeMinutes()
	return currentMinutes >= threshold and not self:IsRewardClaimed(rewardIndex)
end

function PlaytimeHandler:ClaimReward(rewardIndex)
	if not self:IsRewardAvailable(rewardIndex) then
		return
	end
	
	-- Block input while processing
	self:BlockInput(true, "claim")
	self.pendingClaim = rewardIndex
	
	-- Send to server for validation and actual reward granting
	if self.NetworkClient then
		self.NetworkClient.requestClaimPlaytimeReward(rewardIndex)
	else
		warn("PlaytimeHandler: NetworkClient not available")
		self:BlockInput(false, "claim")
		self.pendingClaim = nil
	end
end

function PlaytimeHandler:LoadRewardsConfig(rewardsConfig)
	if rewardsConfig then
		self.rewardsConfig = rewardsConfig.rewards or {}
		self.thresholds = rewardsConfig.thresholds or {}
	else
		warn("PlaytimeHandler: No rewards config provided")
	end
end

function PlaytimeHandler:UpdatePlaytimeDisplay()
	local listFrame = self.PlaytimeFrame:FindFirstChild("List")
	if not listFrame then return end
	
	local currentPlaytimeSeconds = self:GetCurrentPlaytime()
	
	for i = 1, 7 do
		local rewardFrame = listFrame:FindFirstChild("Reward" .. i)
		if rewardFrame then
			local content = rewardFrame:FindFirstChild("Content")
			if content then
				local txtTime = content:FindFirstChild("TxtTime")
				if txtTime and not self:IsRewardClaimed(i) then
					local threshold = self.thresholds[i]
					if threshold then
						local remainingTotalSeconds = math.max(0, (threshold * 60) - math.floor(currentPlaytimeSeconds))
						if remainingTotalSeconds > 0 then
							local remainingMinutes = math.floor(remainingTotalSeconds / 60)
							local remainingSeconds = remainingTotalSeconds % 60
							txtTime.Text = string.format("%02d:%02d", remainingMinutes, remainingSeconds)
						else
							txtTime.Text = "00:00"
						end
					end
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
					local threshold = self.thresholds[rewardIndex]
					if threshold then
						textLabel.Text = threshold .. " min"
					end
				end
			end
		end
	end
	
	-- Update claim button and timer visibility
	local btnClaim = content:FindFirstChild("BtnClaim")
	local imgClaimed = content:FindFirstChild("ImgClaimed")
	local txtTime = content:FindFirstChild("TxtTime")
	
	if self:IsRewardClaimed(rewardIndex) then
		if btnClaim then btnClaim.Visible = false end
		if imgClaimed then imgClaimed.Visible = true end
		if txtTime then txtTime.Visible = false end
	elseif self:IsRewardAvailable(rewardIndex) then
		if btnClaim then btnClaim.Visible = true end
		if imgClaimed then imgClaimed.Visible = false end
		if txtTime then txtTime.Visible = false end
	else
		if btnClaim then btnClaim.Visible = false end
		if imgClaimed then imgClaimed.Visible = false end
		if txtTime then txtTime.Visible = true end
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
					local assetId = Resolver.getRewardAsset(reward.type, reward.name, "Big")
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

	-- Request playtime data from server
	if self.NetworkClient then
		self.NetworkClient.requestPlaytimeData()
	end

	-- Hide HUD panels if they exist
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = false
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = false
	end

	-- Show playtime gui
	self.PlaytimeFrame.Visible = true
	self.isWindowOpen = true
	
	-- Register with close button handler
	self:RegisterWithCloseButton(true)

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
	
	-- Start automatic updates
	self:StartAutoUpdates()
end

function PlaytimeHandler:CloseWindow()
	if self.isAnimating then return end
	self.isAnimating = true

	-- Stop automatic updates
	self:StopAutoUpdates()

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

	self.isWindowOpen = false

	-- Show HUD panels
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = true
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = true
	end
	
	-- Register with close button handler
	self:RegisterWithCloseButton(false)
end

function PlaytimeHandler:SetupProfileUpdatedHandler()
	-- Listen for ProfileUpdated events to handle playtime reward responses
	local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
	
	local connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
		-- Handle errors
		if payload.error then
			warn("PlaytimeHandler: Received error from server: " .. tostring(payload.error.message))
			-- Unblock input on error if we were waiting for claim response
			if self.pendingClaim then
				self:BlockInput(false, "claim")
				self.pendingClaim = nil
			end
			return
		end
		
		-- Handle playtime data updates
		if payload.playtime then
			self:HandlePlaytimeUpdate(payload.playtime)
			-- Unblock input after successful update if we were waiting for claim response
			if self.pendingClaim then
				self:BlockInput(false, "claim")
				self.pendingClaim = nil
			end
		end
	end)
	
	-- Store connection for cleanup
	table.insert(self.Connections, connection)
end

function PlaytimeHandler:HandlePlaytimeUpdate(playtimeData)
	local shouldUpdateMarker = false
	
	-- Update total playtime and sync time
	if playtimeData.totalTime then
		local oldTotalTime = self.totalPlaytime
		self.totalPlaytime = playtimeData.totalTime
		self.lastServerSync = os.time()
		
		-- Check if new rewards became available
		if self.isWindowOpen then
			self:CheckAndUpdateAvailableRewards(oldTotalTime, self.totalPlaytime)
		end
		
		-- Only update marker if hasAvailableReward was explicitly provided
		-- This prevents marker from being hidden when playtime data is included
		-- in ProfileUpdated without hasAvailableReward (e.g., when opening lootbox)
		if playtimeData.hasAvailableReward ~= nil then
			shouldUpdateMarker = true
		end
	end
	
	if playtimeData.claimedRewards then
		self.claimedRewards = playtimeData.claimedRewards
		self.claimedRewardsSet = {}
		for _, rewardIndex in ipairs(self.claimedRewards) do
			self.claimedRewardsSet[rewardIndex] = true
		end
		
		-- Only update marker if hasAvailableReward was explicitly provided
		if playtimeData.hasAvailableReward ~= nil then
			shouldUpdateMarker = true
		end
	end
	
	-- Update rewards config if provided
	if playtimeData.rewardsConfig then
		self:LoadRewardsConfig(playtimeData.rewardsConfig)
		-- Don't update marker just because config changed
	end
	
	-- Only update marker if hasAvailableReward was explicitly provided by server
	if playtimeData.hasAvailableReward ~= nil then
		shouldUpdateMarker = true
		self:UpdateNotificationMarkerWithRetry(playtimeData.hasAvailableReward)
	elseif shouldUpdateMarker then
		-- If other data changed but hasAvailableReward wasn't provided,
		-- recalculate it locally (but only if we have valid data)
		if self.thresholds and self.totalPlaytime > 0 then
			self:UpdateNotificationMarker()
		end
	end
	
	-- Update UI if window is open
	if self.isWindowOpen then
		self:UpdateAllRewardsDisplay()
	end
end

function PlaytimeHandler:CheckAndUpdateAvailableRewards(oldTime, newTime)
	local oldMinutes = math.floor(oldTime / 60)
	local newMinutes = math.floor(newTime / 60)
	
	-- Check if any threshold was crossed
	for i = 1, 7 do
		local threshold = self.thresholds[i]
		if threshold then
			local wasAvailable = oldMinutes >= threshold
			local isAvailable = newMinutes >= threshold
			
			if not wasAvailable and isAvailable and not self:IsRewardClaimed(i) then
				-- New reward became available, update UI
				self:UpdateRewardDisplay(i)
			end
		end
	end
end

function PlaytimeHandler:StartAutoUpdates()
	if self.updateTimer then
		return  -- Already running
	end
	
	-- Update UI periodically (only when window is open)
	self.updateTimer = RunService.Heartbeat:Connect(function()
		if self.isWindowOpen then
			self:UpdatePlaytimeDisplay()
		end
	end)
	
	-- Sync with server periodically (only when window is open)
	if self.syncTask then
		task.cancel(self.syncTask)
	end
	
	self.syncTask = task.spawn(function()
		while self.isWindowOpen do
			task.wait(SYNC_INTERVAL)
			if self.isWindowOpen and self.NetworkClient then
				self.NetworkClient.requestPlaytimeData()
			end
		end
	end)
end

function PlaytimeHandler:StopAutoUpdates()
	if self.updateTimer then
		self.updateTimer:Disconnect()
		self.updateTimer = nil
	end
	
	if self.syncTask then
		task.cancel(self.syncTask)
		self.syncTask = nil
	end
end

--// Public Methods
function PlaytimeHandler:IsInitialized()
	return self._initialized
end

function PlaytimeHandler:GetTotalPlaytime()
	return self.totalPlaytime
end

--// Cleanup
function PlaytimeHandler:Cleanup()
	-- Stop automatic updates
	self:StopAutoUpdates()

	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			if connection.Disconnect then
				connection:Disconnect()
			end
		end
	end
	self.Connections = {}

	self._initialized = false
end

function PlaytimeHandler:BlockInput(value, source)
	if not self.InputBlocker then
		-- InputBlocker is optional, don't warn if missing
		return
	end

	self.InputBlocker.Active = value
	self.InputBlocker.Visible = value
end

-- Register with close button handler
function PlaytimeHandler:RegisterWithCloseButton(isOpen)
	local success, CloseButtonHandler = pcall(function()
		return require(game.ReplicatedStorage.ClientModules.CloseButtonHandler)
	end)
	
	if success and CloseButtonHandler then
		local instance = CloseButtonHandler.GetInstance()
		if instance and instance.isInitialized then
			if isOpen then
				instance:RegisterFrameOpen("Playtime")
			else
				instance:RegisterFrameClosed("Playtime")
			end
		end
	end
end

-- Close the playtime frame (called by close button handler)
function PlaytimeHandler:CloseFrame()
	if self.PlaytimeFrame and self.PlaytimeFrame.Visible then
		self:CloseWindow()
	end
end

function PlaytimeHandler:UpdateNotificationMarkerWithRetry(hasAvailableReward, retryCount)
	retryCount = retryCount or 0
	local maxRetries = 5
	
	if not self._initialized then
		return
	end
	
	if not self.NotificationMarkerHandler then
		local success, NotificationMarkerHandler = pcall(function()
			return require(ReplicatedStorage.ClientModules.NotificationMarkerHandler)
		end)
		
		if success and NotificationMarkerHandler and NotificationMarkerHandler:IsInitialized() then
			self.NotificationMarkerHandler = NotificationMarkerHandler
		else
			if retryCount < maxRetries then
				local delay = 0.05 * (2 ^ retryCount)
				task.delay(delay, function()
					if self._initialized then
						self:UpdateNotificationMarkerWithRetry(hasAvailableReward, retryCount + 1)
					end
				end)
			end
			return
		end
	end
	
	if hasAvailableReward ~= nil then
		self:UpdateNotificationMarker(hasAvailableReward)
	else
		self:UpdateNotificationMarker()
	end
end

function PlaytimeHandler:UpdateNotificationMarker(hasAvailableRewards)
	if hasAvailableRewards == nil then
		if not self.thresholds or self.totalPlaytime == 0 then
			return
		end
		
		local currentPlaytimeSeconds = self:GetCurrentPlaytime()
		local currentMinutes = math.floor(currentPlaytimeSeconds / 60)
		
		hasAvailableRewards = false
		for i = 1, 7 do
			local threshold = self.thresholds[i]
			if threshold and not self:IsRewardClaimed(i) then
				if currentMinutes >= threshold then
					hasAvailableRewards = true
					break
				end
			end
		end
	end
	
	if self.NotificationMarkerHandler and self.NotificationMarkerHandler:IsInitialized() then
		self.NotificationMarkerHandler:SetMarkerVisible("BtnPlaytime", hasAvailableRewards)
	end
end

return PlaytimeHandler
