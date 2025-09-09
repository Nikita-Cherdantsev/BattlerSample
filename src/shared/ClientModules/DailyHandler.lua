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
	self.Utilities = controller:GetModule("Utilities")

	-- Setup daily bonus functionality
	self:SetupDaily()

	self._initialized = true
	print("✅ DailyHandler initialized successfully!")
	return true
end

function DailyHandler:SetupDaily()
	local UI = self.ClientState:getUI()
	--local Remotes = self.ClientState:GetRemotes()
	--local PlayerData = self.ClientState:getProfile()

	if not UI then
		warn("DailyHandler: UI not available")
		return
	end

	-- Ensure Daily window exists
	if not UI:FindFirstChild("Daily") then
		warn("DailyHandler: Daily window not found in UI")
		return
	end

	UI.Daily.Visible = false

	-- Setup HUD button click
	self:SetupOpenButton(UI--[[, Remotes, PlayerData]])

	-- Setup claim click
	self:SetupClaimButton(UI--[[, Remotes]])

	-- Setup close button
	self:SetupCloseButton(UI)

	-- Setup remote event listener
	--[[if Remotes and Remotes.DailyBonus then
		local connection = Remotes.DailyBonus.OnClientEvent:Connect(function(action, ...)
			local rewards, day, isClaimed = ...
			if action == "Show" then
				self:OpenWindow(UI, rewards, day, isClaimed)
			elseif action == "Claimed" then
				self:UpdateDaily(UI, rewards, day, isClaimed)
				task.wait(0.3)
				self:CloseWindow(UI)
			end
		end)
		
		table.insert(self.Connections, connection)
	else
		warn("DailyHandler: DailyBonus remote not found")
	end]]
end

function DailyHandler:SetupOpenButton(UI, Remotes, PlayerData)
	if not UI.LeftPanel or not UI.LeftPanel:FindFirstChild("Daily") then
		warn("DailyHandler: Daily button not found in LeftPanel")
		return
	end

	local button : TextButton = UI.LeftPanel.Daily.Button
	local connection = button.MouseButton1Click:Connect(function()
		if Remotes and Remotes.DailyBonus then
			Remotes.DailyBonus:FireServer("ShowRequest")
		else
			-- Fallback: just open the window for testing
			self:OpenWindow(UI, {}, 1, false)
		end
	end)

	table.insert(self.Connections, connection)
end

function DailyHandler:SetupClaimButton(UI, Remotes)	
	if not UI.Daily or not UI.Daily:FindFirstChild("Claim") then
		warn("DailyHandler: Claim button not found in Daily window")
		return
	end

	local button : TextButton = UI.Daily.Claim.Button
	local connection = button.MouseButton1Click:Connect(function()
		if Remotes and Remotes.DailyBonus then
			Remotes.DailyBonus:FireServer("Claim")
		else
			-- Fallback: simulate claim for testing
			print("DailyHandler: Claim button clicked (mock mode)")
			self:CloseWindow(UI)
		end
	end)

	table.insert(self.Connections, connection)
end

function DailyHandler:SetupCloseButton(UI)
	if not UI.Daily or not UI.Daily:FindFirstChild("Close") then
		warn("DailyHandler: Close button not found in Daily window")
		return
	end

	local button : TextButton = UI.Daily.Close.Button
	local connection = button.MouseButton1Click:Connect(function()
		self:CloseWindow(UI)
	end)

	table.insert(self.Connections, connection)
end

function DailyHandler:OpenWindow(UI, rewards, day, isClaimed)
	if self.isAnimating then return end
	self.isAnimating = true

	-- Hide HUD
	if UI.LeftPanel then
		UI.LeftPanel.Visible = false
	end
	if UI.BottomPanel then
		UI.BottomPanel.Visible = false
	end

	-- Show daily gui
	self:UpdateDaily(UI, rewards, day, isClaimed)

	UI.Daily.Visible = true

	-- Use TweenUI if available, otherwise just show
	if self.Utilities and self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
		self.Utilities.TweenUI.FadeIn(UI.Daily, .3, function ()
			self.isAnimating = false
		end)
	else
		-- Fallback: no animation
		self.isAnimating = false
	end
end

function DailyHandler:UpdateDaily(UI, rewards, day, isClaimed)
	-- Check if the expected UI structure exists
	if not UI.Daily or not UI.Daily:FindFirstChild("Base") then
		return
	end

	-- Update rewards display
	for i, dailyRewards in ipairs(rewards) do
		local rewardFrame : Frame = UI.Daily.Base.Inner.Content.Rewards["Reward" .. i]
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
	if UI.Daily.Claim then
		UI.Daily.Claim.Visible = not isClaimed
	end
	if UI.Daily.Close then
		UI.Daily.Close.Visible = isClaimed
	end
end

function DailyHandler:CloseWindow(UI)
	if self.isAnimating then return end
	self.isAnimating = true

	-- Hide daily gui
	if self.Utilities and self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
		self.Utilities.TweenUI.FadeOut(UI.Daily, .3, function () 
			UI.Daily.Visible = false
			self.isAnimating = false
		end)
	else
		-- Fallback: no animation
		UI.Daily.Visible = false
		self.isAnimating = false
	end

	-- Show HUD
	if UI.LeftPanel then
		UI.LeftPanel.Visible = true
	end
	if UI.BottomPanel then
		UI.BottomPanel.Visible = true
	end
end

--// Public Methods
function DailyHandler:IsInitialized()
	return self._initialized
end

--// Cleanup
function DailyHandler:Cleanup()
	print("Cleaning up DailyHandler...")

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
