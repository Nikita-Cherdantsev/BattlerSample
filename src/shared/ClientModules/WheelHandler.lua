--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

--// Module
local WheelHandler = {}

--// State
WheelHandler.Connections = {}
WheelHandler._initialized = false

WheelHandler.Data = {
	Rewards = nil,
	Prices = nil
}

--// Wheel settings
local TOTAL_CELLS = 8
local SPIN_ROUNDS = 2
local SPIN_DURATION = 2
local CELL_ANGLE = 360 / TOTAL_CELLS

local isSpinning = false
local prevIndex = 0
local fullSpins = 0

--// Initialization
function WheelHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	self.Utilities = controller:GetModule("Utilities")

	-- Setup clicker functionality
	self:SetupWheel()

	self._initialized = true
	print("✅ WheelHandler initialized successfully!")
	return true
end

function WheelHandler:SetupWheel()
	local UI = self.ClientState:GetUI()
	local Remotes = self.ClientState:GetRemotes()
	local PlayerData = self.ClientState:GetPlayerData()
	
	self.Data = Remotes.WheelGetData:InvokeServer()
	
	UI.Wheel.Visible = false
	
	-- Setup HUD button click
	self:SetupOpenButton(UI, Remotes, PlayerData)

	-- Setup spin button click
	self:SetupSpinButton(UI, Remotes)
	
	-- Setup bet buttons
	self:SetupBetButtons(UI, Remotes, PlayerData)
	
	-- Setup close button
	self:SetupCloseButton(UI)
end

function WheelHandler:SetupOpenButton(UI, Remotes, PlayerData)
	local button : TextButton = UI.LeftPanel.Wheel.Button
	local connection = button.MouseButton1Click:Connect(function()
		self:OpenWindow(UI, Remotes, PlayerData)
	end)

	table.insert(self.Connections, connection)
end

function WheelHandler:SetupSpinButton(UI, Remotes)	
	local button : TextButton = UI.Wheel.Spin.Button.Button
	local connection = button.MouseButton1Click:Connect(function()
		self:RequestSpin(UI, Remotes)
	end)

	table.insert(self.Connections, connection)
	
	connection = Remotes.WheelSpinResult.OnClientEvent:Connect(function(rewardIndex, rewardName, rewardAmount)
		if not rewardIndex then
			WheelHandler:CompleteSpin(UI)
			return
		end
		task.delay(2, function()  -- Wait for the confirmation dialog to close
			self:StartSpin(UI, rewardIndex, rewardName, rewardAmount)
		end)
	end)

	table.insert(self.Connections, connection)
end

function WheelHandler:SetupBetButtons(UI, Remotes, PlayerData)
	local oldBet = PlayerData.WheelBet.Value
	
	UI.Wheel.Bet.Pointer.Position = UI.Wheel.Bet["Bet" .. oldBet .. "Button"].Position
	
	for i = 1, 5 do
		local button : TextButton = UI.Wheel.Bet[ "Bet" .. i .. "Button"]
		button.Text = "x" .. self.Data.Prices[i].Bet
			
		local connection = button.MouseButton1Click:Connect(function()
			Remotes.WheelBet:FireServer(i)
			local tween = TweenService:Create(UI.Wheel.Bet.Pointer, TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Position = UI.Wheel.Bet["Bet" .. i .. "Button"].Position
			})

			tween:Play()
		end)

		table.insert(self.Connections, connection)
	end
	
	local connection = PlayerData.WheelBet.Changed:Connect(function(newBet)
		task.spawn(function()
			if newBet ~= oldBet then
				self:UpdateWheel(UI, newBet)
			end
		end)

		oldBet = newBet
	end)

	table.insert(self.Connections, connection)
end

function WheelHandler:SetupCloseButton(UI)
	local button : TextButton = UI.Wheel.Close.Button
	local connection = button.MouseButton1Click:Connect(function()
		self:CloseWindow(UI)
	end)

	table.insert(self.Connections, connection)
end

function WheelHandler:RequestSpin(UI, Remotes)
	if isSpinning then return end
	
	UI.Wheel.Spin.Button.Button.Interactable = false
	UI.Wheel.Bet.Bet1Button.Interactable = false
	UI.Wheel.Bet.Bet2Button.Interactable = false
	UI.Wheel.Bet.Bet3Button.Interactable = false
	UI.Wheel.Bet.Bet4Button.Interactable = false
	UI.Wheel.Close.Button.Interactable = false
	
	Remotes.WheelRequestSpin:FireServer()
end

function WheelHandler:StartSpin(UI, rewardIndex, rewardName, rewardAmount)
	if not UI.Wheel.Visible then
		return
	end
	coroutine.wrap(function()
		isSpinning = true
		self:AnimateSpin(UI, rewardIndex)
		task.wait(SPIN_DURATION)
		self:ShowReward(UI, rewardName, rewardAmount, function ()
			self:CompleteSpin(UI)
			isSpinning = false
		end)
	end)()
end

function WheelHandler:ShowReward(UI, rewardName, rewardAmount, onCloseCallback)
	local reward = UI.Wheel.Reward
	
	local image : ImageLabel = UI.Wheel.Reward.Content.Image.RewardImage
	local amount : TextLabel = UI.Wheel.Reward.Content.Text.RewardAmount
	image.Image = self.Utilities.Icons[rewardName].image
	amount.Text = rewardAmount

	self.Utilities.TweenUI.FadeIn(reward, .3, function () 
		task.wait(1)
		self.Utilities.TweenUI.FadeOut(reward, .3, onCloseCallback)
	end)
end

function WheelHandler:CompleteSpin(UI)	
	UI.Wheel.Spin.Button.Button.Interactable = true
	UI.Wheel.Bet.Bet1Button.Interactable = true
	UI.Wheel.Bet.Bet2Button.Interactable = true
	UI.Wheel.Bet.Bet3Button.Interactable = true
	UI.Wheel.Bet.Bet4Button.Interactable = true
	UI.Wheel.Close.Button.Interactable = true
end

function WheelHandler:OpenWindow(UI, Remotes, PlayerData)
	-- Hide HUD
	UI.LeftPanel.Visible   = false
	UI.BottomPanel.Visible = false
	
	-- Get data for wheel
	local wheelData = Remotes.WheelGetData:InvokeServer()
	self.Data = wheelData

	-- Show wheel gui
	self:UpdateWheel(UI, PlayerData.WheelBet.Value)
	
	UI.Wheel.Visible = true
	self.Utilities.TweenUI.FadeIn(UI.Wheel, .3)
end

function WheelHandler:CloseWindow(UI)
	-- Hide wheel gui
	self.Utilities.TweenUI.FadeOut(UI.Wheel, .3, function () 
		UI.Wheel.Visible = false
	end)
	
	-- Clear data for wheel
	self.Data = {}
	
	-- Show HUD
	UI.LeftPanel.Visible   = true
	UI.BottomPanel.Visible = true
end

function WheelHandler:UpdateWheel(UI, bet)
	local prices = self.Data.Prices
	local rewards = self.Data.Rewards
	
	local spinButton : TextLabel = UI.Wheel.Spin.Shadow.Content
	local spinningWheel : Frame = UI.Wheel.SpinningWheel.Rewards
	
	-- Setup spin button
	local currentBetData = prices[bet];
	local isDiscount = currentBetData.Price ~= currentBetData.DiscountPrice
	local originalPrice = isDiscount and " <s>" .. currentBetData.Price .. "</s>" or ""
	spinButton.Price.Text = currentBetData.DiscountPrice .. originalPrice

	-- Setup spinnig wheel
	local radius = 200
	local center = UDim2.fromScale(0.5, 0.5)

	for _, child in ipairs(spinningWheel:GetChildren()) do
		if child:IsA("GuiObject") and (child.Name == "Separator" or child:IsA("TextLabel")) then
			child:Destroy()
		end
	end

	for i, reward in ipairs(rewards) do
		local rewardFrame = spinningWheel[ "Reward" .. i ]
		local imageLabel : ImageLabel = rewardFrame.Image.ImageLabel
		local textLabel : TextLabel = rewardFrame.Text.TextLabel
		
		imageLabel.Image = self.Utilities.Icons[reward.Name].image
		textLabel.Text = reward.Count * currentBetData.Bet
	end
end

function WheelHandler:AnimateSpin(UI, targetIndex)
	local spinningWheel : Frame = UI.Wheel.SpinningWheel.Rewards
	local currentRotation = math.abs(spinningWheel.Rotation)

	local randomOffset = math.random(0, 3) * CELL_ANGLE * 0.1
	randomOffset = math.fmod(randomOffset, 2) == 0 and randomOffset or -randomOffset
	local targetAngle = (targetIndex - 1) * CELL_ANGLE + randomOffset

	fullSpins = prevIndex > targetIndex and fullSpins + SPIN_ROUNDS + 1 or fullSpins + SPIN_ROUNDS

	local finalRotation = -(fullSpins * 360 + targetAngle)

	local tween = TweenService:Create(spinningWheel, TweenInfo.new(SPIN_DURATION, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Rotation = finalRotation
	})

	tween:Play()
	prevIndex = targetIndex
end

--// Public Methods
function WheelHandler:IsInitialized()
	return self._initialized
end

--// Cleanup
function WheelHandler:Cleanup()
	print("Cleaning up WheelHandler...")

	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}

	self._initialized = false
	print("✅ WheelHandler cleaned up")
end

return WheelHandler 
