--[[
	UIHandler Module
	Handles UI-related functionality
	
	This module manages:
	- Currency display and updates
	- Popup animations
	- Frame opening/closing
	- Button interactions
]]

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local AvatarEditorService = game:GetService("AvatarEditorService")

--// Module
local UIHandler = {}

--// State
UIHandler.Connections = {}
UIHandler._initialized = false
UIHandler.BaseSize = {}

--// Initialization
function UIHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	self.Utilities = controller:GetModule("Utilities")
	
	if not self.ClientState:IsInitialized() then
		warn("ClientState not initialized, cannot initialize UIHandler")
		return false
	end
	
	-- Setup UI functionality
	self:SetupCurrencyDisplay()
	self:SetupPopups()
	self:SetupFavorite()
	-- TODO: @emegerd добавить обработку этого куска.
	--[[self:SetupFrames()
	self:SetupButtons()]]
	
	self._initialized = true
	print("✅ UIHandler initialized successfully!")
	return true
end

function UIHandler:SetupCurrencyDisplay()
	local UI = self.ClientState:GetUI()
	local PlayerData = self.ClientState:GetPlayerData()
	
	local TopPanel = UI["TopPanel"]
	
	self:UpdateCurrencyDisplay(TopPanel.Currency1.Container.Text, PlayerData.Currency1)

	self:UpdateCurrencyDisplay(TopPanel.Currency2.Container.Text, PlayerData.Currency2)

	self:UpdateCurrencyDisplay(TopPanel.Currency3.Container.Text, PlayerData.Currency3)
end

function UIHandler:UpdateCurrencyDisplay(label, currencyValue)
	label.Amount.Text = self.Utilities.Short.en(currencyValue.Value)
	
	local connection = currencyValue.Changed:Connect(function()
		label.Amount.Text = self.Utilities.Short.en(currencyValue.Value)
	end)
	
	table.insert(self.Connections, connection)
end

function UIHandler:SetupPopups()
	local UI = self.ClientState:GetUI()
	local PlayerData = self.ClientState:GetPlayerData()
	
	-- Setup like notification timer (every 5 minutes for 10 seconds)
	task.spawn(function()
		while true do
			task.wait(300) -- Wait 5 minutes (300 seconds)
			
			-- Show notification for 10 seconds
			self:ShowLikeNotification(true)
			task.wait(10)
			self:ShowLikeNotification(false)
		end
	end)
	
	local CurrencyContainer = UI.TopPanel
	local Currency1Old = PlayerData.Currency1.Value
	
	--// Currency 1 change popup.
	local connection = PlayerData.Currency1.Changed:Connect(function(NewValue)
		
		task.spawn(function()
			if NewValue > Currency1Old then
				local amount = NewValue - Currency1Old
				self:ShowSplittedCurrency("Currency1", amount)
			end
		end)
		
		Currency1Old = NewValue
	end)
	
	table.insert(self.Connections, connection)
	
	local Currency2Old = PlayerData.Currency2.Value

	--// Currency 2 change popup.
	local connection = PlayerData.Currency2.Changed:Connect(function(NewValue)

		task.spawn(function()
			if NewValue > Currency2Old then
				local amount = NewValue - Currency2Old
				self:ShowSplittedCurrency("Currency2", amount)	
			end
		end)

		Currency2Old = NewValue
	end)

	table.insert(self.Connections, connection)
	
	local Currency3Old = PlayerData.Currency3.Value

	--// Currency 3 change popup.
	local connection = PlayerData.Currency3.Changed:Connect(function(NewValue)

		task.spawn(function()
			if NewValue > Currency3Old then
				local amount = NewValue - Currency3Old
				self:ShowSplittedCurrency("Currency3", amount)
			end
		end)

		Currency3Old = NewValue
	end)

	table.insert(self.Connections, connection)
end

function UIHandler:SetupFavorite()
	local Remotes = self.ClientState:GetRemotes()
	local connection = Remotes.Favorite.OnClientEvent:Connect(function()
		pcall(function()
			AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
			print(" ⭐ Show 'Favorites prompt'...")
		end)
		
		AvatarEditorService.PromptSetFavoriteCompleted:Connect(function(result: Enum.AvatarPromptResult)
			if result ~= Enum.AvatarPromptResult.PermissionDenied then
				print(" ⭐✅ Added to favorites!")
			else
				print(" ⭐❌ Cancelled.")
			end
		end)
	end)

	table.insert(self.Connections, connection)
end

local function splitCurrency(amount, maxPerPopup)
	local parts = {}

	while amount > maxPerPopup do
		table.insert(parts, maxPerPopup)
		amount -= maxPerPopup
	end

	if amount > 0 then
		table.insert(parts, amount)
	end

	return parts
end

function UIHandler:ShowSplittedCurrency(currency, amount)
	local UI = self.ClientState:GetUI()
	local targetContainer = UI.TopPanel[ currency ]
	local spawnContainer = UI.Popups
	local emoji = currency == "Currency1" and " 🙋 " or (currency == "Currency2" and " 👁️ " or " 🔔 ")
	
	local maxPerPopup = 10000
	
	local currencyImage = self.Utilities.Icons[ currency ].image
	if amount <= maxPerPopup then
		self:CreatePopup(amount, currencyImage, spawnContainer, targetContainer)
		print( emoji .. "+" .. amount )
		return
	end

	local parts = splitCurrency(amount, maxPerPopup)

	for i, part in ipairs(parts) do
		self:CreatePopup(part, currencyImage, spawnContainer, targetContainer)
		print( emoji .. "+" .. part )
	end
end

local function GetTargetPosition(movingFrame, targetFrame)
	local targetCenter = targetFrame.AbsolutePosition + (targetFrame.AbsoluteSize / 2)
	local movingSize = movingFrame.AbsoluteSize
	local parentAbsPos = movingFrame.Parent.AbsolutePosition

	local offsetX = targetCenter.X - parentAbsPos.X - (movingSize.X / 2)
	local offsetY = targetCenter.Y - parentAbsPos.Y - (movingSize.Y / 2)

	local goalPosition = UDim2.fromOffset(offsetX, offsetY)
	
	return goalPosition
end

function UIHandler:CreatePopup(amount, image, spawnContainer, targetContainer)
	local UI = self.ClientState:GetUI()
	
	local NewPopup = ReplicatedStorage.ClientGui.Popup:Clone()
	NewPopup.Size = UDim2.new(0, 0, 0, 0)
	NewPopup.Currency.Image = image
	NewPopup.Amount.Text = "+"..self.Utilities.Short.en(amount)
	NewPopup.Position = UDim2.new(math.random(40, 60) / 100, 0, math.random(40, 60) / 100, 0)
	NewPopup.Parent = spawnContainer
	
	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(
		NewPopup, 
		tweenInfo, {Size = UDim2.new(0.053, 0, 0.076, 0)})
	
	tween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween = TweenService:Create(
				NewPopup, 
				tweenInfo, {
					Size = UDim2.new(0, 0, 0, 0),
					Position = GetTargetPosition(NewPopup, targetContainer)
				})
			
			tween.Completed:Connect(function(playbackState)
				if playbackState == Enum.PlaybackState.Completed then
					NewPopup:Destroy()
				end
			end)
			
			tween:Play()
		end
	end)
	
	tween:Play()
end

function UIHandler:SetupFrames()
	local Frames = self.ClientState:GetFrames()
	
	-- Store base sizes for all frames
	for _, Frame in Frames:GetChildren() do
		if not Frame:IsA("Frame") then continue end
		
		self.BaseSize[Frame.Name] = Frame.Size
		
		-- Setup close buttons
		if Frame:FindFirstChild("Close") then
			self.Utilities.ButtonAnimations.Create(Frame.Close)
			
			local connection = Frame.Close.Click.MouseButton1Click:Connect(function()
				self.Utilities.ButtonHandler.OnClick(Frame, UDim2.new(0,0,0,0))
				self.Utilities.Audio.PlayAudio("Click")
			end)
			
			table.insert(self.Connections, connection)
		end
	end
end

function UIHandler:SetupButtons()
	local UI = self.ClientState:GetUI()
	
	-- Here we are configuring the button container (need to place all the buttons to the at the "UIContainer" frame)
	local ButtonContainer = UI["UIContainer"].Buttons
	
	for _, Button in ButtonContainer:GetChildren() do
		if not Button:IsA("Frame") then continue end
		
		self.Utilities.ButtonAnimations.Create(Button)
		
		local connection = Button.Click.MouseButton1Click:Connect(function()
			local Frames = self.ClientState:GetFrames()
			self.Utilities.ButtonHandler.OnClick(UI.Frames[Button.Name], self.BaseSize[Button.Name])
			self.Utilities.Audio.PlayAudio("Click")
		end)
		
		table.insert(self.Connections, connection)
	end
end

--// Public Methods
function UIHandler:IsInitialized()
	return self._initialized
end

function UIHandler:ShowLikeNotification(show)
	local UI = self.ClientState:GetUI()
	local likeNotification = UI:FindFirstChild("LikeNotification")
	
	if not likeNotification then
		warn("LikeNotification frame not found in GameUI")
		return
	end
	
	-- Store original size if not already stored
	if not self.LikeNotificationOriginalSize then
		self.LikeNotificationOriginalSize = likeNotification.Size
	end
	
	if show then
		-- Show the notification with animation
		likeNotification.Visible = true
		likeNotification.Size = UDim2.new(0, 0, 0, 0) -- Start from size 0
		likeNotification:TweenSize(self.LikeNotificationOriginalSize, Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
	else
		-- Hide the notification with animation
		likeNotification:TweenSize(UDim2.new(0, 0, 0, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
		task.wait(0.3)
		likeNotification.Visible = false
	end
end

function UIHandler:GetBaseSize(frameName)
	return self.BaseSize[frameName]
end

--// Cleanup
function UIHandler:Cleanup()
	print("Cleaning up UIHandler...")
	
	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}
	
	self._initialized = false
	print("✅ UIHandler cleaned up")
end

return UIHandler 