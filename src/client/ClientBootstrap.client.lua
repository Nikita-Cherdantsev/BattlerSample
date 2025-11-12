--[[
	ClientBootstrap.client.lua - Main client entry point
	
	Automatically initializes the MainController and all handlers
	when the client starts up.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")

-- Wait for MainController to be available
local Controllers = StarterPlayerScripts:WaitForChild("Controllers")
local MainController = require(Controllers:WaitForChild("MainController"))

-- Initialize the client system
local function InitializeClient()
    print("🎮 Starting client initialization...")
    
    ReplicatedStorage:SetAttribute("ClientInitialized", false)
    
    MainController:Init()
    
    ReplicatedStorage:SetAttribute("ClientInitialized", true)
    print("🎉 Client initialization complete!")
end

-- Start initialization
InitializeClient()