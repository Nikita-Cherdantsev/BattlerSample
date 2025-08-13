--[[
	StatsHandler Module
	Handles player stats UI
	
	This module manages:
	- Displaying player stats (total currency, etc.)
	- Updating stats UI when values change
]]

--// Module
local StatsHandler = {}

--// State
StatsHandler.Connections = {}
StatsHandler._initialized = false

--// Initialization
function StatsHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	self.Utilities = controller:GetModule("Utilities")
	
	if not self.ClientState:IsInitialized() then
		warn("ClientState not initialized, cannot initialize StatsHandler")
		return false
	end
	
	self:SetupStatsUI()
	self._initialized = true
	print("✅ StatsHandler initialized successfully!")
	return true
end

function StatsHandler:SetupStatsUI()
	local Frames = self.ClientState:GetFrames()
	local PlayerData = self.ClientState:GetPlayerData()
	local GameSettings = self.ClientState:GetGameSettings()

	local StatsFrame = Frames.Stats
	-- TotalCurrency UI removed
end

--// Public Methods
function StatsHandler:IsInitialized()
	return self._initialized
end

--// Cleanup
function StatsHandler:Cleanup()
	print("Cleaning up StatsHandler...")
	for _, connection in ipairs(self.Connections) do
		if connection then connection:Disconnect() end
	end
	self.Connections = {}
	self._initialized = false
	print("✅ StatsHandler cleaned up")
end

return StatsHandler 