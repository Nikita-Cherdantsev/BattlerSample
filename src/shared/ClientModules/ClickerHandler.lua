--[[
	ClickerHandler Module
	Handles clicker mechanics and input handling
	
	This module manages:
	- Click button functionality
	- Global clicking (if enabled)
	- Click audio and animations
]]

--// Services
local UserInputService = game:GetService("UserInputService")

--// Module
local ClickerHandler = {}

--// State
ClickerHandler.Connections = {}
ClickerHandler._initialized = false

ClickerHandler.isAutoclick = false
ClickerHandler.isHolding = false
ClickerHandler.holdStartTime = 0
ClickerHandler.HOLD_TIME = 1.0 -- seconds to trigger long press

--// Initialization
function ClickerHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	self.Utilities = controller:GetModule("Utilities")
	self.isAutoclick = self.ClientState:GetPlayerData().Autoclick.Value
	
	-- Setup clicker functionality
	self:SetupClicker()
	
	self._initialized = true
	print("✅ ClickerHandler initialized successfully!")
	return true
end

function ClickerHandler:SetupClicker()
	local UI = self.ClientState:GetUI()
	local Remotes = self.ClientState:GetRemotes()
	
	-- Setup main click button
	self:SetupClickButton(UI, Remotes)
	
	-- Global clicking disabled - only button clicks work
	-- self:SetupGlobalClicking(Remotes)
end

function ClickerHandler:SetupClickButton(UI, Remotes)
	-- Create button animations
	-- TODO: @emegerd добавить обработку анимаций кнопок с наведением.
	--[[self.Utilities.ButtonAnimations.Create(UI.Clicker)]]
	
	-- Set autoclick state
	local image : ImageLabel = UI.BottomPanel.Play.Content.Image.Default
	image.Visible = not self.isAutoclick
	
	-- Connect input events for the button
	self:SetupButtonInputEvents(UI, Remotes)
end

function ClickerHandler:SetupButtonInputEvents(UI, Remotes)
	local button = UI.BottomPanel.Play.Button
	local image : ImageLabel = UI.BottomPanel.Play.Content.Image.Default
	
	-- Input began (mouse down/touch start)
	local inputBeganConnection = button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			
			-- Start holding
			self.isHolding = true
			self.holdStartTime = tick()
			
			-- Hide the image immediately
			image.Visible = false
			
			-- Fire server event for immediate click
			Remotes.Clicker:FireServer(self.isAutoclick)
			
			-- Start long press timer
			task.delay(self.HOLD_TIME, function()
				if self.isHolding and tick() - self.holdStartTime >= self.HOLD_TIME then
					-- Long press detected - toggle autoclick
					self.isAutoclick = not self.isAutoclick
					Remotes.Clicker:FireServer(self.isAutoclick)
					
					-- Update image visibility based on new state
					image.Visible = not self.isAutoclick
				end
			end)
		end
	end)
	
	-- Input ended (mouse up/touch end)
	local inputEndedConnection = button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			
			-- Stop holding
			self.isHolding = false
			
			-- Only show image if not in autoclick mode
			if not self.isAutoclick then
				image.Visible = true
			end
		end
	end)
	
	-- Store connections for cleanup
	table.insert(self.Connections, inputBeganConnection)
	table.insert(self.Connections, inputEndedConnection)
end

function ClickerHandler:SetupGlobalClicking(Remotes)
	-- Connect global input event
	local connection = UserInputService.InputBegan:Connect(function(Input, Processed)
		if Processed then return end
		if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		
		-- Only handle global clicks if not in autoclick mode
		if not self.isAutoclick then
			Remotes.Clicker:FireServer(self.isAutoclick)
		end
	end)
	
	table.insert(self.Connections, connection)
end

--// Public Methods
function ClickerHandler:IsInitialized()
	return self._initialized
end

function ClickerHandler:GetAutoclickState()
	return self.isAutoclick
end

function ClickerHandler:SetAutoclickState(state)
	self.isAutoclick = state
end

--// Cleanup
function ClickerHandler:Cleanup()
	print("Cleaning up ClickerHandler...")
	
	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}
	
	self._initialized = false
	print("✅ ClickerHandler cleaned up")
end

return ClickerHandler 