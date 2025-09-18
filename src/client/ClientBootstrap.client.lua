--[[
	ClientBootstrap.client.lua - Main client entry point
	
	Automatically initializes the MainController and all handlers
	when the client starts up.
]]

-- Services
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")

-- Wait for MainController to be available
local Controllers = StarterPlayerScripts:WaitForChild("Controllers")
local MainController = require(Controllers:WaitForChild("MainController"))

-- Initialize the client system
local function InitializeClient()
    print("🎮 Starting client initialization...")
    
    -- Initialize MainController (this will initialize all handlers)
    MainController:Init()
    
    print("🎉 Client initialization complete!")
end

-- Start initialization
InitializeClient()