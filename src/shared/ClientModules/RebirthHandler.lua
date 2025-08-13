--[[
	RebirthHandler Module
	Handles rebirth system functionality
	
	This module manages:
	- Rebirth cost calculations
	- Rebirth UI updates
	- Rebirth purchases
	- Linear and exponential rebirth types
]]

--// Module
local RebirthHandler = {}

--// State
RebirthHandler.Connections = {}
RebirthHandler._initialized = false
RebirthHandler.RebirthPrice = 0
RebirthHandler.RebirthMulti = 0

--// Initialization
function RebirthHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	self.Utilities = controller:GetModule("Utilities")
	
	if not self.ClientState:IsInitialized() then
		warn("ClientState not initialized, cannot initialize RebirthHandler")
		return false
	end
	
	-- Get rebirth settings
	self:LoadRebirthSettings()
	
	-- Setup rebirth functionality
	self:SetupRebirthUI()
	
	self._initialized = true
	print("✅ RebirthHandler initialized successfully!")
	return true
end

function RebirthHandler:LoadRebirthSettings()
	local GameSettings = self.ClientState:GetGameSettings()
	
	self.RebirthPrice = GameSettings.RebirthBasePrice.Value
	self.RebirthMulti = GameSettings.RebirthMultiplier.Value
end

function RebirthHandler:SetupRebirthUI()
	local Frames = self.ClientState:GetFrames()
	local PlayerData = self.ClientState:GetPlayerData()
	local Remotes = self.ClientState:GetRemotes()
	local GameSettings = self.ClientState:GetGameSettings()
	
	-- Setup rebirth info
	self:UpdateRebirthInfo()
	
	-- Connect rebirth value changes
	local rebirthConnection = PlayerData.Rebirth.Changed:Connect(function()
		self:UpdateRebirthInfo()
	end)
	table.insert(self.Connections, rebirthConnection)
	
	-- Setup buy button
	self.Utilities.ButtonAnimations.Create(Frames.Rebirth.Buy)
	
	local buyConnection = Frames.Rebirth.Buy.Click.MouseButton1Click:Connect(function()
		Remotes.Rebirth:FireServer()
		self.Utilities.Audio.PlayAudio("Click")
	end)
	table.insert(self.Connections, buyConnection)
end

function RebirthHandler:UpdateRebirthInfo()
	local Frames = self.ClientState:GetFrames()
	local PlayerData = self.ClientState:GetPlayerData()
	local GameSettings = self.ClientState:GetGameSettings()
	
	-- Update counter
	Frames.Rebirth.Counter.Text = "You have "..self.Utilities.Short.en(PlayerData.Rebirth.Value).." Rebirths"
	
	-- Update description and cost based on rebirth type
	if GameSettings.RebirthType.Value == "Linear" then
		Frames.Rebirth.Description.Text = "Buying a Rebirth will increase your "..GameSettings.CurrencyName.Value.." Multiplier with x"..self.RebirthMulti
		Frames.Rebirth.Cost.Text = "You need atleast "..self.Utilities.Short.en(self.RebirthPrice * (PlayerData.Rebirth.Value + 1)).." "..GameSettings.CurrencyName.Value
	elseif GameSettings.RebirthType.Value == "Exponential" then
		Frames.Rebirth.Description.Text = "Buying a Rebirth will increase your "..GameSettings.CurrencyName.Value.." Multiplier with ^"..(self.RebirthMulti+0.5)
		Frames.Rebirth.Cost.Text = "You need atleast "..self.Utilities.Short.en(self.RebirthPrice * ((self.RebirthMulti+1.25) ^ PlayerData.Rebirth.Value)).." "..GameSettings.CurrencyName.Value
	end
end

--// Public Methods
function RebirthHandler:IsInitialized()
	return self._initialized
end

function RebirthHandler:GetRebirthCost()
	local PlayerData = self.ClientState:GetPlayerData()
	local GameSettings = self.ClientState:GetGameSettings()
	
	if GameSettings.RebirthType.Value == "Linear" then
		return self.RebirthPrice * (PlayerData.Rebirth.Value + 1)
	elseif GameSettings.RebirthType.Value == "Exponential" then
		return self.RebirthPrice * ((self.RebirthMulti+1.25) ^ PlayerData.Rebirth.Value)
	end
	
	return 0
end

function RebirthHandler:CanAffordRebirth()
	local PlayerData = self.ClientState:GetPlayerData()
	local cost = self:GetRebirthCost()
	
	return PlayerData.Currency.Value >= cost
end

--// Cleanup
function RebirthHandler:Cleanup()
	print("Cleaning up RebirthHandler...")
	
	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}
	
	self._initialized = false
	print("✅ RebirthHandler cleaned up")
end

return RebirthHandler 