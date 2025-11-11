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
local BattlePrepHandler = require(ReplicatedStorage.ClientModules.BattlePrepHandler)
local BattleHandler = require(ReplicatedStorage.ClientModules.BattleHandler)
local RewardsHandler = require(ReplicatedStorage.ClientModules.RewardsHandler)
local FollowRewardHandler = require(ReplicatedStorage.ClientModules.FollowRewardHandler)

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
		{name = "CloseButtonHandler", handler = CloseButtonHandler},
		{name = "BattlePrepHandler", handler = BattlePrepHandler},
		{name = "BattleHandler", handler = BattleHandler},
		{name = "RewardsHandler", handler = RewardsHandler},
		{name = "FollowRewardHandler", handler = FollowRewardHandler}
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
    elseif moduleName == "Manifest" then
        return require(ReplicatedStorage.Modules.Assets.Manifest)
    elseif moduleName == "CardCatalog" then
        return require(ReplicatedStorage.Modules.Cards.CardCatalog)
    elseif moduleName == "CardStats" then
        return require(ReplicatedStorage.Modules.Cards.CardStats)
    elseif moduleName == "CardLevels" then
        return require(ReplicatedStorage.Modules.Cards.CardLevels)
    elseif moduleName == "DeckValidator" then
        return require(ReplicatedStorage.Modules.Cards.DeckValidator)
    elseif moduleName == "BoxTypes" then
        return require(ReplicatedStorage.Modules.Loot.BoxTypes)
    elseif moduleName == "BoxDropTables" then
        return require(ReplicatedStorage.Modules.Loot.BoxDropTables)
    elseif moduleName == "BoxRoller" then
        return require(ReplicatedStorage.Modules.Loot.BoxRoller)
    elseif moduleName == "BoxValidator" then
        return require(ReplicatedStorage.Modules.Loot.BoxValidator)
    elseif moduleName == "ShopPacksCatalog" then
        return require(ReplicatedStorage.Modules.Shop.ShopPacksCatalog)
    elseif moduleName == "SeededRNG" then
        return require(ReplicatedStorage.Modules.RNG.SeededRNG)
    elseif moduleName == "GameConstants" then
        return require(ReplicatedStorage.Modules.Constants.GameConstants)
    elseif moduleName == "UIConstants" then
        return require(ReplicatedStorage.Modules.Constants.UIConstants)
    elseif moduleName == "BattleAnimationHandler" then
        return require(ReplicatedStorage.ClientModules.BattleAnimationHandler)
    elseif moduleName == "CombatTypes" then
        return require(ReplicatedStorage.Modules.Combat.CombatTypes)
    elseif moduleName == "CombatUtils" then
        return require(ReplicatedStorage.Modules.Combat.CombatUtils)
    elseif moduleName == "Types" then
        return require(ReplicatedStorage.Modules.Types)
    elseif moduleName == "CardVM" then
        return require(ReplicatedStorage.Modules.ViewModels.CardVM)
    elseif moduleName == "DeckVM" then
        return require(ReplicatedStorage.Modules.ViewModels.DeckVM)
    elseif moduleName == "BoardLayout" then
        return require(ReplicatedStorage.Modules.BoardLayout)
    elseif moduleName == "SelfCheck" then
        return require(ReplicatedStorage.Modules.SelfCheck)
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

-- Get NetworkClient instance
function MainController:GetNetworkClient()
    return NetworkClient
end

-- Get BattleHandler instance
function MainController:GetBattleHandler()
    return BattleHandler
end

-- Get RewardsHandler instance
function MainController:GetRewardsHandler()
    return RewardsHandler
end

-- Get LootboxHandler instance (alias for LootboxUIHandler)
function MainController:GetLootboxHandler()
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