--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--// Modules
local Resolver = require(ReplicatedStorage.Modules.Assets.Resolver)

--// Module
local DailyHandler = {}

--// State
DailyHandler.Connections = {}
DailyHandler._initialized = false

DailyHandler.isAnimating = false
DailyHandler.isWindowOpen = false
DailyHandler.streak = 0
DailyHandler.lastLogin = 0
DailyHandler.currentDay = 1
DailyHandler.isClaimed = false
DailyHandler.rewardsConfig = {}
DailyHandler.NetworkClient = nil
DailyHandler.syncTask = nil  -- Task for periodic sync
DailyHandler.lastServerSync = 0  -- Last server sync time (os.time())
DailyHandler.hasCheckedAutoOpen = false  -- Flag to track if we've checked for auto-open
DailyHandler.lastAutoOpenDay = 0  -- Track which day we last auto-opened for
DailyHandler.pendingClaim = false  -- Flag to track if we're waiting for claim response

--// Constants
local SYNC_INTERVAL = 30  -- Sync with server every 30 seconds when window is open

--// Initialization
function DailyHandler:Init(controller)
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
		warn("DailyHandler: Could not load NetworkClient: " .. tostring(NetworkClient))
		return false
	end
	
	-- Safe require of Utilities to avoid loading errors
	local success, utilities = pcall(function()
		return controller:GetModule("Utilities")
	end)
	
	if success then
		self.Utilities = utilities
	else
		warn("DailyHandler: Could not load Utilities module: " .. tostring(utilities))
		self.Utilities = {
			TweenUI = { FadeIn = function() end, FadeOut = function() end },
			Blur = { Show = function() end, Hide = function() end }
		}
	end

	-- Initialize state
	self.Connections = {}
	self.streak = 0
	self.lastLogin = 0
	self.currentDay = 1
	self.isClaimed = false
	self.rewardsConfig = {}
	self.isWindowOpen = false
	self.syncTask = nil
	self.lastServerSync = 0
	self.hasCheckedAutoOpen = false
	self.lastAutoOpenDay = 0
	self.pendingClaim = false

	-- Setup daily functionality
	self:SetupDaily()
	
	-- Setup profile updated handler
	self:SetupProfileUpdatedHandler()
	
	-- Request daily data to check if we should auto-open the window
	self:CheckAndAutoOpen()

	self._initialized = true
	print("✅ DailyHandler initialized successfully!")
	return true
end

function DailyHandler:SetupDaily()
	-- Access UI from player's PlayerGui (which should be copied from StarterGui)
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Wait for Roblox to automatically clone GameUI from StarterGui
	local gameGui = playerGui:WaitForChild("GameUI", 5) -- Initial wait
	
	if not gameGui then
		gameGui = playerGui:WaitForChild("GameUI", 10) -- Extended wait
		
		if not gameGui then
			warn("DailyHandler: GameUI not found in PlayerGui after extended waiting")
			return
		end
	end
	
	-- Check if Daily frame exists
	local dailyFrame = gameGui:FindFirstChild("Daily")
	if not dailyFrame then
		warn("DailyHandler: Daily frame not found in " .. gameGui.Name .. " - Daily UI not available")
		return
	end
	
	-- Store UI reference for later use
	self.UI = gameGui
	self.DailyFrame = dailyFrame
	self.InputBlocker = dailyFrame:FindFirstChild("InputBlocker")
	
	-- Hide daily initially
	dailyFrame.Visible = false
	
	-- Setup daily functionality
	self:SetupOpenButton()
	self:SetupClaimButton()
	self:SetupCloseButton()
	
	print("✅ DailyHandler: Daily UI setup completed")
end

function DailyHandler:SetupOpenButton()
	-- Look for daily button in the UI
	local leftPanel = self.UI:FindFirstChild("LeftPanel")
	if not leftPanel then
		warn("DailyHandler: LeftPanel not found in GameUI")
		return
	end
	
	local dailyButton = leftPanel:FindFirstChild("BtnDaily")
	if not dailyButton then
		warn("DailyHandler: Button not found in Daily frame")
		return
	end
	
	if dailyButton:IsA("GuiButton") or dailyButton:IsA("TextButton") then
		local connection = dailyButton.MouseButton1Click:Connect(function()
			self:OpenWindow()
		end)
		table.insert(self.Connections, connection)
		print("✅ DailyHandler: Open button connected")
	else
		warn("DailyHandler: Found element '" .. dailyButton.Name .. "' but it's not a GuiButton (it's a " .. dailyButton.ClassName .. ")")
	end
end

function DailyHandler:SetupCloseButton()
	-- Close button is now handled by CloseButtonHandler
	-- No need to set up individual close button here
end

function DailyHandler:SetupClaimButton()
	-- Look for claim button in the daily frame
	local frameFrame = self.DailyFrame:FindFirstChild("Frame")
	local buttonsFrame = frameFrame and frameFrame:FindFirstChild("Buttons")
	if not buttonsFrame then
		warn("DailyHandler: Buttons frame not found in Daily frame")
		return
	end
	
	local claimButton = buttonsFrame:FindFirstChild("BtnClaim")
	if not claimButton then
		warn("DailyHandler: Claim button not found - you may need to add a ClaimButton to Daily frame")
		return
	end

	local connection = claimButton.MouseButton1Click:Connect(function()
		self:ClaimReward()
	end)

	table.insert(self.Connections, connection)
	print("✅ DailyHandler: Claim button connected")
end

function DailyHandler:OpenWindow()
	if self.isAnimating then return end
	self.isAnimating = true

	-- Request daily data from server
	if self.NetworkClient then
		self.NetworkClient.requestDailyData()
	end

	-- Hide HUD panels if they exist
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = false
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = false
	end

	-- Show daily gui
	self.DailyFrame.Visible = true
	self.isWindowOpen = true
	
	-- Register with close button handler
	-- Hide close button if reward is available (user must claim it)
	self:RegisterWithCloseButton(true)
	self:UpdateCloseButtonVisibility()

	-- Use TweenUI if available, otherwise just show
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
			self.Utilities.TweenUI.FadeIn(self.DailyFrame, .3, function ()
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
	
	print("✅ DailyHandler: Daily window opened")
end

function DailyHandler:CloseWindow()
	if self.isAnimating then return end
	self.isAnimating = true

	-- Stop automatic updates
	self:StopAutoUpdates()

	-- Hide daily gui
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
			self.Utilities.TweenUI.FadeOut(self.DailyFrame, .3, function () 
				self.DailyFrame.Visible = false
				self.isAnimating = false
			end)
		end
		if self.Utilities.Blur then
			self.Utilities.Blur.Hide()
		end
	else
		-- Fallback: no animation
		self.DailyFrame.Visible = false
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
	
	print("✅ DailyHandler: Daily window closed")
end

function DailyHandler:ClaimReward()
	if self.isClaimed then
		return
	end
	
	-- Block input while processing
	self:BlockInput(true, "claim")
	self.pendingClaim = true
	
	-- Send to server for validation and actual reward granting
	if self.NetworkClient then
		self.NetworkClient.requestClaimDailyReward(self.currentDay)
	else
		warn("DailyHandler: NetworkClient not available")
		self:BlockInput(false, "claim")
		self.pendingClaim = false
	end
end

function DailyHandler:UpdateDailyDisplay()
	-- Check if the expected UI structure exists
	local frameFrame = self.DailyFrame:FindFirstChild("Frame")
	if not frameFrame or not frameFrame:FindFirstChild("Main") then
		return
	end

	local mainFrame = frameFrame.Main
	if not mainFrame or not mainFrame.Content or not mainFrame.Content.Content then
		return
	end

	-- Update rewards display for all 7 days
	for i = 1, 7 do
		local frameNum = i > 6 and 2 or 1
		local dayFrame = mainFrame.Content.Content["Frame" .. frameNum]
		if dayFrame then
			dayFrame = dayFrame["Day" .. i]
		end
		
		if dayFrame then
			local contentFrame = dayFrame:FindFirstChild("Content")
			
			-- Update rewards display
			if contentFrame and self.rewardsConfig[i] then
				local rewards = self.rewardsConfig[i]
				for j, reward in ipairs(rewards) do
					local rewardElement = contentFrame:FindFirstChild("Reward" .. j)
					if rewardElement then
						local txtValue = rewardElement:FindFirstChild("TxtValue")
						if txtValue then
							txtValue.Text = tostring(reward.amount)
						end
						local imgReward = rewardElement:FindFirstChild("ImgReward")
						if imgReward then
							imgReward.Image = Resolver.getRewardAsset(reward.type, reward.name, "Big")
						end
					end
				end
			end

			-- Update visual states (Current frame)
			local currentFrame = dayFrame:FindFirstChild("Current")
			if currentFrame then
				currentFrame.Visible = (i == self.currentDay)
			end
			local headerCurrentFrame = dayFrame:FindFirstChild("HeaderCurrent")
			local headerFrame = dayFrame:FindFirstChild("Header")
			headerCurrentFrame.Visible = (i == self.currentDay)
			headerFrame.Visible = (i ~= self.currentDay)
			
			-- Update Claimed visibility
			if contentFrame then
				local claimedFrame = contentFrame:FindFirstChild("Claimed")
				if claimedFrame then
					-- Show claimed if already claimed today (current day) or past days
					local isPastDay = i < self.currentDay
					local isCurrentDayClaimed = (i == self.currentDay and self.isClaimed)
					claimedFrame.Visible = isPastDay or isCurrentDayClaimed
				end
			end
		end
	end

	-- Update button visibility
	local buttonsFrame = frameFrame and frameFrame:FindFirstChild("Buttons")
	if buttonsFrame then
		local claimButton = buttonsFrame:FindFirstChild("BtnClaim")
		if claimButton then
			claimButton.Visible = not self.isClaimed
		end
	end
	
	-- Update close button visibility after updating display
	if self.isWindowOpen then
		self:UpdateCloseButtonVisibility()
	end
end

function DailyHandler:SetupProfileUpdatedHandler()
	-- Listen for ProfileUpdated events to handle daily reward responses
	local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
	
	local connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
		-- Handle errors
		if payload.error then
			warn("DailyHandler: Received error from server: " .. tostring(payload.error.message))
			-- Unblock input on error if we were waiting for claim response
			if self.pendingClaim then
				self:BlockInput(false, "claim")
				self.pendingClaim = false
			end
			return
		end
		
		-- Handle daily data updates (process even if window is not open for auto-open logic)
		if payload.daily then
			self:HandleDailyUpdate(payload.daily)
			-- Unblock input after successful update if we were waiting for claim response
			if self.pendingClaim then
				self:BlockInput(false, "claim")
				self.pendingClaim = false
			end
		end
	end)
	
	-- Store connection for cleanup
	table.insert(self.Connections, connection)
end

function DailyHandler:HandleDailyUpdate(dailyData)
	-- Update server sync time
	self.lastServerSync = os.time()
	
	-- Store previous state to detect changes
	local prevCurrentDay = self.currentDay
	local prevIsClaimed = self.isClaimed
	
	-- Update daily data
	if dailyData.streak ~= nil then
		self.streak = dailyData.streak
	end
	
	if dailyData.lastLogin ~= nil then
		self.lastLogin = dailyData.lastLogin
	end
	
	if dailyData.currentDay ~= nil then
		self.currentDay = dailyData.currentDay
	end
	
	if dailyData.isClaimed ~= nil then
		self.isClaimed = dailyData.isClaimed
	end
	
	-- Update rewards config if provided
	if dailyData.rewardsConfig then
		self.rewardsConfig = dailyData.rewardsConfig
	end
	
	-- Check if day changed or claim status changed
	local dayChanged = (prevCurrentDay ~= self.currentDay)
	local claimStatusChanged = (prevIsClaimed ~= self.isClaimed)
	
	-- Check for auto-open: if reward is not claimed and window is not open, auto-open it
	-- Only auto-open if it's a new day (different from last auto-open day) to avoid reopening
	local shouldAutoOpen = false
	if not self.isClaimed and not self.isWindowOpen then
		-- Check if this is a new day we haven't auto-opened for yet
		if self.currentDay ~= self.lastAutoOpenDay then
			shouldAutoOpen = true
			self.lastAutoOpenDay = self.currentDay
		end
	end
	
	if shouldAutoOpen then
		-- Delay auto-open slightly to ensure UI is ready (async to avoid blocking)
		task.spawn(function()
			task.wait(1.5) -- Wait a bit for UI to be fully ready
			-- Double-check conditions after delay
			if not self.isClaimed and not self.isWindowOpen and self._initialized then
				print("📅 DailyHandler: Auto-opening daily window - reward available and not claimed (Day " .. self.currentDay .. ")")
				self:OpenWindow()
			end
		end)
	end
	
	-- Mark as checked once we have valid data
	if not self.hasCheckedAutoOpen and self.currentDay > 0 then
		self.hasCheckedAutoOpen = true
	end
	
	-- Update UI if window is open
	if self.isWindowOpen then
		-- Always update display when data changes
		self:UpdateDailyDisplay()
	end
	
	-- Update close button visibility when claim status changes
	if claimStatusChanged then
		self:UpdateCloseButtonVisibility()
		
		-- Auto-close window after successful reward claim
		-- Only close if status changed from "not claimed" to "claimed"
		if prevIsClaimed == false and self.isClaimed == true and self.isWindowOpen then
			-- Delay auto-close slightly to let user see the reward confirmation
			task.spawn(function()
				task.wait(1.5) -- Give time to see the UI update
				-- Double-check conditions before closing
				if self.isWindowOpen and self.isClaimed then
					print("📅 DailyHandler: Auto-closing daily window after successful reward claim")
					self:CloseWindow()
				end
			end)
		end
	end
end

function DailyHandler:StartAutoUpdates()
	if self.syncTask then
		return  -- Already running
	end
	
	-- Sync with server periodically to detect day changes
	self.syncTask = task.spawn(function()
		while self.isWindowOpen do
			task.wait(SYNC_INTERVAL)
			-- Double-check window is still open before requesting
			if self.isWindowOpen and self.NetworkClient then
				self.NetworkClient.requestDailyData()
			end
		end
	end)
end

function DailyHandler:StopAutoUpdates()
	-- Cancel sync task if running
	if self.syncTask then
		task.cancel(self.syncTask)
		self.syncTask = nil
	end
end

--// Public Methods
function DailyHandler:IsInitialized()
	return self._initialized
end

function DailyHandler:BlockInput(value, source)
	if not self.InputBlocker then
		-- InputBlocker is optional, don't warn if missing
		return
	end

	self.InputBlocker.Active = value
	self.InputBlocker.Visible = value
end

-- Register with close button handler
function DailyHandler:RegisterWithCloseButton(isOpen)
	local success, CloseButtonHandler = pcall(function()
		return require(game.ReplicatedStorage.ClientModules.CloseButtonHandler)
	end)
	
	if success and CloseButtonHandler then
		local instance = CloseButtonHandler.GetInstance()
		if instance and instance.isInitialized then
			if isOpen then
				instance:RegisterFrameOpen("Daily")
			else
				instance:RegisterFrameClosed("Daily")
				-- Unblock close button when Daily closes
				instance:UnblockCloseButton()
			end
		end
	end
end

-- Update close button visibility based on reward availability
function DailyHandler:UpdateCloseButtonVisibility()
	local success, CloseButtonHandler = pcall(function()
		return require(game.ReplicatedStorage.ClientModules.CloseButtonHandler)
	end)
	
	if success and CloseButtonHandler then
		local instance = CloseButtonHandler.GetInstance()
		if instance and instance.isInitialized then
			-- If window is open and reward is NOT claimed, block close button
			-- User must claim the reward before they can close the window
			if self.isWindowOpen and not self.isClaimed then
				instance:BlockCloseButton()
			else
				instance:UnblockCloseButton()
			end
		end
	end
end

	-- Check and auto-open window if needed (called after initialization)
function DailyHandler:CheckAndAutoOpen()
	-- Request daily data to check if we should auto-open
	if self.NetworkClient then
		self.NetworkClient.requestDailyData()
	end
end

-- Close the daily frame (called by close button handler)
function DailyHandler:CloseFrame()
	if self.DailyFrame and self.DailyFrame.Visible then
		self:CloseWindow()
	end
end

--// Cleanup
function DailyHandler:Cleanup()
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
	print("✅ DailyHandler cleaned up")
end

return DailyHandler
