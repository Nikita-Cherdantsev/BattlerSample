--[[
	Currency Handler
	
	Manages the display of soft and hard currency in the UI.
	Automatically updates currency values when the player profile changes.
]]

local CurrencyHandler = {}
CurrencyHandler.__index = CurrencyHandler

-- UI References
CurrencyHandler.UI = nil
CurrencyHandler.HardCurrencyLabel = nil
CurrencyHandler.SoftCurrencyLabel = nil

-- State
CurrencyHandler.isInitialized = false

-- Initialize the currency handler
function CurrencyHandler:Init(controller)
	local self = setmetatable({}, CurrencyHandler)
	
	self.Controller = controller
	self.ClientState = nil
	self.stateSubscription = nil
	self.profileReadyDisconnect = nil
	self.connections = {}
	
	if controller and controller.GetClientState then
		self.ClientState = controller:GetClientState()
	end
	
	if self:SetupCurrencyUI() then
		self:SetupStateListeners()
		self.isInitialized = true
	else
		warn("❌ CurrencyHandler: Failed to initialize")
	end
	
	return self
end

-- Setup currency UI elements
function CurrencyHandler:SetupCurrencyUI()
	-- Wait for GameUI to be available
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	
	local gameUI = player:WaitForChild("PlayerGui"):WaitForChild("GameUI", 15)
	if not gameUI then
		warn("❌ CurrencyHandler: GameUI not found")
		return false
	end
	
	-- Find currency UI elements
	local topPanel = gameUI:FindFirstChild("TopPanel")
	if not topPanel then
		warn("❌ CurrencyHandler: TopPanel not found")
		return false
	end
	
	local currency1 = topPanel:FindFirstChild("Currency1")
	local currency2 = topPanel:FindFirstChild("Currency2")
	
	if not currency1 or not currency2 then
		warn("❌ CurrencyHandler: Currency frames not found")
		return false
	end
	
	local currency1Content = currency1:FindFirstChild("Content")
	local currency2Content = currency2:FindFirstChild("Content")
	
	if not currency1Content or not currency2Content then
		warn("❌ CurrencyHandler: Currency content frames not found")
		return false
	end
	
	self.HardCurrencyLabel = currency1Content:FindFirstChild("TxtValue")
	self.SoftCurrencyLabel = currency2Content:FindFirstChild("TxtValue")
	
	if not self.HardCurrencyLabel or not self.SoftCurrencyLabel then
		warn("❌ CurrencyHandler: Currency text labels not found")
		return false
	end
	
	return true
end

function CurrencyHandler:SetupStateListeners()
	if self.ClientState then
		-- Apply immediately if profile already loaded
		local profile = self.ClientState.getProfile and self.ClientState.getProfile()
		if profile and profile.currencies then
			self:UpdateCurrencyDisplay(profile.currencies)
		end
		
		-- Subscribe to ongoing state updates
		if self.ClientState.subscribe then
			self.stateSubscription = self.ClientState.subscribe(function(state)
				if state.profile and state.profile.currencies then
					self:UpdateCurrencyDisplay(state.profile.currencies)
				end
			end)
		end
		
		-- Ensure we pick up the very first profile snapshot if it arrives later
		if self.ClientState.onProfileReady then
			self.profileReadyDisconnect = self.ClientState.onProfileReady(function(readyProfile)
				if readyProfile and readyProfile.currencies then
					self:UpdateCurrencyDisplay(readyProfile.currencies)
				end
			end)
		end
	else
		-- Fallback: listen directly to ProfileUpdated events
		local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
		local connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
			if payload.currencies then
				self:UpdateCurrencyDisplay(payload.currencies)
			end
		end)
		table.insert(self.connections, connection)
	end
end

-- Update currency display
function CurrencyHandler:UpdateCurrencyDisplay(currencies)
	if not self.HardCurrencyLabel or not self.SoftCurrencyLabel then
		return
	end
	
	local hardCurrency = currencies.hard or 0
	local softCurrency = currencies.soft or 0
	
	-- Update the labels
	self.HardCurrencyLabel.Text = tostring(hardCurrency)
	self.SoftCurrencyLabel.Text = tostring(softCurrency)
	
end

-- Manual currency update (for debugging)
function CurrencyHandler:UpdateCurrencies(hard, soft)
	if not self.HardCurrencyLabel or not self.SoftCurrencyLabel then
		return
	end
	
	self.HardCurrencyLabel.Text = tostring(hard or 0)
	self.SoftCurrencyLabel.Text = tostring(soft or 0)
	
end

-- Cleanup
function CurrencyHandler:Cleanup()
	-- Disconnect any connections if needed
	if self.stateSubscription then
		self.stateSubscription()
		self.stateSubscription = nil
	end
	
	if self.profileReadyDisconnect then
		self.profileReadyDisconnect()
		self.profileReadyDisconnect = nil
	end
	
	for _, connection in ipairs(self.connections) do
		if connection and connection.Disconnect then
			connection:Disconnect()
		end
	end
	self.connections = {}
	
	self.isInitialized = false
end

return CurrencyHandler
