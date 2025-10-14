--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

--// Module
local DailyHandler = {}

--// State
DailyHandler.Connections = {}
DailyHandler._initialized = false

DailyHandler.isAnimating = false

--// Initialization
function DailyHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	
	-- Safe require of Utilities to avoid loading errors
	local success, utilities = pcall(function()
		return controller:GetModule("Utilities")
	end)
	
	if success then
		self.Utilities = utilities
	else
		warn("DailyHandler: Could not load Utilities module: " .. tostring(utilities))
		self.Utilities = {
			CardCatalog = { GetAllCards = function() return {} end }
		}
	end

	-- Setup daily bonus functionality
	self:SetupDaily()

	self._initialized = true
	print("✅ DailyHandler initialized successfully!")
	return true
end

function DailyHandler:SetupDaily()
	-- Try to access UI from player's PlayerGui (which should be copied from StarterGui)
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	
	-- Debug: Print all children in PlayerGui
	for _, child in pairs(playerGui:GetChildren()) do
	end
	
	-- Debug: Check if GameUI already exists
	local existingGameUI = playerGui:FindFirstChild("GameUI")
	if existingGameUI then
	else
	end
	
	-- Wait for Roblox to automatically clone GameUI from StarterGui
	-- This is the correct way to get the UI that the player can actually interact with
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
		for _, child in pairs(gameGui:GetChildren()) do
		end
		return
	end
	
	
	-- Store UI reference for later use
	self.UI = gameGui
	self.DailyFrame = dailyFrame
	
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
	-- Path: GameUI -> LeftPanel -> Daily -> Button
	
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
	
	
	-- Test if the button has the right events
	if dailyButton:IsA("GuiButton") then
		local connection = dailyButton.MouseButton1Click:Connect(function()
			-- For now, just open the window for testing
			-- TODO: Add RemoteEvent integration when DailyBonus remote is available
			self:OpenWindow({}, 1, false)
		end)
		table.insert(self.Connections, connection)
		print("✅ DailyHandler: Open button connected")
	else
		warn("DailyHandler: Found element '" .. dailyButton.Name .. "' but it's not a GuiButton (it's a " .. dailyButton.ClassName .. ")")
	end
end

function DailyHandler:SetupClaimButton()
	-- Look for claim button in the daily frame
	local claimButton = self.DailyFrame:FindFirstChild("Claim")
	if claimButton then
		claimButton = claimButton:FindFirstChild("Button")
	end
	
	-- Alternative: look for claim button directly in daily frame
	if not claimButton then
		claimButton = self.DailyFrame:FindFirstChild("ClaimButton")
	end
	
	if not claimButton then
		warn("DailyHandler: Claim button not found - you may need to add a ClaimButton to Daily frame")
		return
	end

	local connection = claimButton.MouseButton1Click:Connect(function()
		-- For now, simulate claim for testing
		-- TODO: Add RemoteEvent integration when DailyBonus remote is available
		self:CloseWindow()
	end)

	table.insert(self.Connections, connection)
	print("✅ DailyHandler: Claim button connected")
end

function DailyHandler:SetupCloseButton()
	-- Close button is now handled by CloseButtonHandler
	-- No need to set up individual close button here
end

function DailyHandler:OpenWindow(rewards, day, isClaimed)
	if self.isAnimating then return end
	self.isAnimating = true

	-- Hide HUD panels if they exist
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = false
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = false
	end

	-- Show daily gui
	self:UpdateDaily(rewards, day, isClaimed)

	self.DailyFrame.Visible = true
	
	-- Register with close button handler
	self:RegisterWithCloseButton(true)

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
	
	print("✅ DailyHandler: Daily window opened")
end

function DailyHandler:UpdateDaily(rewards, day, isClaimed)
	-- Check if the expected UI structure exists
	if not self.DailyFrame or not self.DailyFrame:FindFirstChild("Base") then
		return
	end

	-- Update rewards display
	for i, dailyRewards in ipairs(rewards) do
		local rewardFrame = self.DailyFrame.Base.Inner.Content.Rewards["Reward" .. i]
		if rewardFrame then
			for j, reward in ipairs(dailyRewards) do
				local rewardElement = rewardFrame["Reward" .. j]
				if rewardElement then
					if rewardElement.Amount and rewardElement.Amount.TextLabel then
						rewardElement.Amount.TextLabel.Text = tostring(reward.Count or 0)
					end
					if rewardElement.Image and rewardElement.Image.ImageLabel then
						rewardElement.Image.ImageLabel.Image = self.Utilities and self.Utilities.Icons and self.Utilities.Icons[reward.Name] and self.Utilities.Icons[reward.Name].image or ""
					end
				end
			end

			-- Update visual states
			if rewardFrame.Focus then
				rewardFrame.Focus.Visible = i == day
			end
			if rewardFrame.Claimed then
				rewardFrame.Claimed.Visible = isClaimed and i <= day or i < day	
			end
			if rewardFrame.Day then
				rewardFrame.Day.Visible = not (rewardFrame.Claimed and rewardFrame.Claimed.Visible)
			end
		end
	end

	-- Update button visibility
	if self.DailyFrame.Claim then
		self.DailyFrame.Claim.Visible = not isClaimed
	end
	if self.DailyFrame.Close then
		self.DailyFrame.Close.Visible = isClaimed
	end
end

function DailyHandler:CloseWindow()
	if self.isAnimating then return end
	self.isAnimating = true

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

--// Public Methods
function DailyHandler:IsInitialized()
	return self._initialized
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
			end
		end
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

	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}

	self._initialized = false
	print("✅ DailyHandler cleaned up")
end

return DailyHandler