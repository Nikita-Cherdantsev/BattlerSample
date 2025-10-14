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
local LootboxUIHandler = require(ReplicatedStorage.ClientModules.LootboxUIHandler)
local PlaytimeHandler = require(ReplicatedStorage.ClientModules.PlaytimeHandler)
local ShopHandler = require(ReplicatedStorage.ClientModules.ShopHandler)
local CurrencyHandler = require(ReplicatedStorage.ClientModules.CurrencyHandler)
local CloseButtonHandler = require(ReplicatedStorage.ClientModules.CloseButtonHandler)

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
	
	-- Initialize handlers with error handling
	local handlers = {
		{name = "DailyHandler", handler = DailyHandler},
		{name = "DeckHandler", handler = DeckHandler},
		{name = "CardInfoHandler", handler = CardInfoHandler},
		{name = "LootboxUIHandler", handler = LootboxUIHandler},
		{name = "PlaytimeHandler", handler = PlaytimeHandler},
		{name = "ShopHandler", handler = ShopHandler},
		{name = "CurrencyHandler", handler = CurrencyHandler},
		{name = "CloseButtonHandler", handler = CloseButtonHandler}
	}
	
	for _, handlerInfo in ipairs(handlers) do
		local success, result = pcall(function()
			if handlerInfo.name == "CardInfoHandler" then
				cardInfoHandlerInstance = handlerInfo.handler
				return handlerInfo.handler:Init(self)
			else
				return handlerInfo.handler:Init(self)
			end
		end)
		
		if success then
			print("✅ " .. handlerInfo.name .. " initialized successfully")
		else
			warn("❌ Failed to initialize " .. handlerInfo.name .. ": " .. tostring(result))
		end
	end
    
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

	-- Get the DeckHandler instance
function MainController:GetDeckHandler()
    return DeckHandler
end

-- Get the LootboxUIHandler instance
function MainController:GetLootboxUIHandler()
    return LootboxUIHandler
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
    if LootboxUIHandler.Cleanup then
        LootboxUIHandler:Cleanup()
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