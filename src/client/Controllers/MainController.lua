--[[
	MainController - Central client controller for initializing all handlers
	
	Manages the initialization of all client-side handlers and modules,
	providing a unified interface for the client architecture.
]]

local MainController = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local NetworkClient = require(script.Parent.NetworkClient)
local ClientState = require(script.Parent.Parent.State.ClientState)
local DailyHandler = require(ReplicatedStorage.ClientModules.DailyHandler)
local DeckHandler = require(ReplicatedStorage.ClientModules.DeckHandler)
local CardInfoHandler = require(ReplicatedStorage.ClientModules.CardInfoHandler)
local PlaytimeHandler = require(ReplicatedStorage.ClientModules.PlaytimeHandler)
local ShopHandler = require(ReplicatedStorage.ClientModules.ShopHandler)

-- State
local isInitialized = false
local cardInfoHandlerInstance = nil

-- Public API

-- Initialize MainController and all handlers
function MainController:Init()
    if isInitialized then
        print("MainController already initialized")
        return
    end
    
    print("🚀 Initializing MainController...")
    
    -- Initialize ClientState first
    ClientState.init(NetworkClient)
    
    -- Request initial profile
	NetworkClient.requestProfile()
	
	-- Initialize handlers
	DailyHandler:Init(self)
	DeckHandler:Init(self)
	cardInfoHandlerInstance = CardInfoHandler
	cardInfoHandlerInstance:Init(self)
	PlaytimeHandler:Init(self)
	ShopHandler:Init(self)
    
    isInitialized = true
    print("✅ MainController initialized successfully!")
end

-- Get the ClientState instance
function MainController:GetClientState()
    return ClientState
end

-- Get a module by name
function MainController:GetModule(moduleName)
    if moduleName == "Utilities" then
        return require(ReplicatedStorage.Modules.Utilities)
    end
    return nil
end

-- Get CardInfoHandler instance
function MainController:GetCardInfoHandler()
    return cardInfoHandlerInstance
end

-- Check if MainController is initialized
function MainController:IsInitialized()
    return isInitialized
end

-- Cleanup function
function MainController:Cleanup()
    if not isInitialized then
        return
    end
    
    print("🧹 Cleaning up MainController...")
    
    -- Cleanup handlers
    if DailyHandler.Cleanup then
        DailyHandler:Cleanup()
    end
    
    if DeckHandler.Cleanup then
        DeckHandler:Cleanup()
    end
    
    if cardInfoHandlerInstance and cardInfoHandlerInstance.Cleanup then
        cardInfoHandlerInstance:Cleanup()
    end
    
    if PlaytimeHandler.Cleanup then
        PlaytimeHandler:Cleanup()
    end
    
    if ShopHandler.Cleanup then
        ShopHandler:Cleanup()
    end
    
    isInitialized = false
    print("✅ MainController cleaned up")
end

return MainController