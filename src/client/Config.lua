--[[
	Client Configuration - Feature flags and settings
	
	Controls various development and debugging features.
	Recommended defaults:
	- Development: USE_MOCKS=true, SHOW_DEV_PANEL=true, DEBUG_LOGS=true
	- Production: USE_MOCKS=false, SHOW_DEV_PANEL=false, DEBUG_LOGS=false
]]

local Config = {}

-- Mock Configuration
Config.USE_MOCKS = false  -- Route networking through mocks instead of real remotes

-- UI Configuration
Config.SHOW_DEV_PANEL = true  -- Attach Dev Panel UI at runtime

-- Debug Configuration
Config.DEBUG_LOGS = false  -- Enable verbose prints in NetworkClient/ClientState

-- Auto-Configuration
Config.AUTO_REQUEST_PROFILE = true  -- Auto call requestProfile() on startup

-- Mock Settings (when USE_MOCKS is true)
Config.MOCK_SETTINGS = {
	NETWORK_LATENCY_MS = 150,  -- Simulated network delay
	PROFILE_UPDATE_DELAY_MS = 100,  -- Delay for profile updates
	MATCH_RESPONSE_DELAY_MS = 200,  -- Delay for match responses
}

-- Dev Panel Settings
Config.DEV_PANEL_SETTINGS = {
	POSITION = UDim2.new(0, 10, 0, 10),  -- Top-left corner
	SIZE = UDim2.new(0, 200, 0, 300),    -- Small panel size
	Z_INDEX = 100,                       -- High z-index to stay on top
}

return Config
