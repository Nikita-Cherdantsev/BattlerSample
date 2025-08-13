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
	local UI = self.ClientState:GetUI()
	local Remotes = self.ClientState:GetRemotes()
	local PlayerData = self.ClientState:GetPlayerData()
	
	UI.Daily.Visible = false

	-- Setup HUD button click
	self:SetupOpenButton(UI, Remotes, PlayerData)
	
	-- Setup claim click
	self:SetupClaimButton(UI, Remotes)

	-- Setup close button
	self:SetupCloseButton(UI)
	
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
end

function DailyHandler:SetupOpenButton(UI, Remotes, PlayerData)
	local button : TextButton = UI.LeftPanel.Daily.Button
	local connection = button.MouseButton1Click:Connect(function()
		Remotes.DailyBonus:FireServer("ShowRequest")
	end)

	table.insert(self.Connections, connection)
end

function DailyHandler:SetupClaimButton(UI, Remotes)	
	local button : TextButton = UI.Daily.Claim.Button
	local connection = button.MouseButton1Click:Connect(function()
		Remotes.DailyBonus:FireServer("Claim")
	end)
end

function DailyHandler:SetupCloseButton(UI)
	local button : TextButton = UI.Daily.Close.Button
	local connection = button.MouseButton1Click:Connect(function()
		self:CloseWindow(UI)
	end)

	table.insert(self.Connections, connection)
end

function DailyHandler:ClaimReward(UI, Remotes, PlayerData, rewards, streak)
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
	UI.LeftPanel.Visible   = false
	UI.BottomPanel.Visible = false

	-- Show daily gui
	self:UpdateDaily(UI, rewards, day, isClaimed)
	
	UI.Daily.Visible = true
	self.Utilities.TweenUI.FadeIn(UI.Daily, .3, function ()
		self.isAnimating = false
	end)
end

function DailyHandler:UpdateDaily(UI, rewards, day, isClaimed)
	for i, dailyRewards in ipairs(rewards) do
		local rewardFrame : Frame = UI.Daily.Base.Inner.Content.Rewards["Reward" .. i]
		for j, reward in ipairs(dailyRewards) do
			rewardFrame["Reward" .. j].Amount.TextLabel.Text = reward.Count
			rewardFrame["Reward" .. j].Image.ImageLabel.Image =  self.Utilities.Icons[reward.Name].image
		end
		
		rewardFrame.Focus.Visible = i == day
		rewardFrame.Claimed.Visible = isClaimed and i <= day or i < day	
		rewardFrame.Day.Visible = not rewardFrame.Claimed.Visible
	end
	
	UI.Daily.Claim.Visible = not isClaimed
	UI.Daily.Close.Visible = isClaimed
end

function DailyHandler:CloseWindow(UI)
	if self.isAnimating then return end
	self.isAnimating = true
	
	-- Hide daily gui
	self.Utilities.TweenUI.FadeOut(UI.Daily, .3, function () 
		UI.Daily.Visible = false
		self.isAnimating = false
	end)

	-- Show HUD
	UI.LeftPanel.Visible   = true
	UI.BottomPanel.Visible = true
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
