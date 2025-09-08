--[[
	Client Utilities - Simple client-side utilities for mock system
	
	This module provides only the essential utilities that the client needs
	for the mock system to work, without complex dependencies.
]]

local Utilities = {}

-- Essential Types (hardcoded for client, matching server format)
Utilities.Types = {
	Rarity = { Common = "common", Rare = "rare", Epic = "epic", Legendary = "legendary" },
	Class = { DPS = "dps", Support = "support", Tank = "tank" },
	LootboxState = { Idle = "idle", Unlocking = "unlocking", Ready = "ready" }
}

-- Essential TimeUtils (hardcoded for client, matching server format)
Utilities.TimeUtils = {
	nowUnix = function() return os.time() end,
	seconds = function(s) return s * 60 end, -- Convert minutes to seconds like server
	lootboxDurations = {
		Common = 20,
		Rare = 60,
		Epic = 240,
		Legendary = 480
	}
}

-- Client-side card data (matching server-side CardCatalog)
Utilities.CardCatalog = {
	GetAllCards = function() 
		return {
			-- Common cards
			["dps_001"] = { slotNumber = 10, rarity = "common", class = "dps" },
			["support_001"] = { slotNumber = 20, rarity = "common", class = "support" },
			
			-- Rare cards
			["tank_001"] = { slotNumber = 30, rarity = "rare", class = "tank" },
			["dps_002"] = { slotNumber = 40, rarity = "rare", class = "dps" },
			["support_002"] = { slotNumber = 50, rarity = "rare", class = "support" },
			
			-- Epic cards
			["dps_003"] = { slotNumber = 60, rarity = "epic", class = "dps" },
			["tank_002"] = { slotNumber = 70, rarity = "epic", class = "tank" },
			
			-- Legendary cards
			["dps_004"] = { slotNumber = 80, rarity = "legendary", class = "dps" },
		}
	end,
	GetCard = function(cardId)
		local cards = Utilities.CardCatalog.GetAllCards()
		return cards[cardId]
	end
}

-- Client-side deck validation
Utilities.DeckValidator = {
	ValidateDeck = function(deckIds)
		if not deckIds or #deckIds ~= 6 then
			return false, "Deck must contain exactly 6 cards"
		end
		
		-- Check for duplicates
		local seen = {}
		for _, cardId in ipairs(deckIds) do
			if seen[cardId] then
				return false, "Deck contains duplicate cards"
			end
			seen[cardId] = true
		end
		
		return true
	end
}

-- Client-side card levels (matching server CardLevels)
Utilities.CardLevels = {
	MAX_LEVEL = 7,
	GetLevelCost = function(level)
		local levelCosts = {
			[1] = { requiredCount = 1, softAmount = 0 },
			[2] = { requiredCount = 10, softAmount = 12000 },
			[3] = { requiredCount = 20, softAmount = 50000 },
			[4] = { requiredCount = 40, softAmount = 200000 },
			[5] = { requiredCount = 80, softAmount = 500000 },
			[6] = { requiredCount = 160, softAmount = 800000 },
			[7] = { requiredCount = 320, softAmount = 1200000 }
		}
		return levelCosts[level]
	end
}

-- Client-side card stats
Utilities.CardStats = {
	GetCardStats = function(cardId, level)
		-- Simple power calculation for mocks
		local basePower = 100
		local levelBonus = (level - 1) * 5
		return {
			attack = 3,
			health = 4,
			defence = 1,
			power = basePower + levelBonus
		}
	end,
	ComputeStats = function(cardId, level)
		return Utilities.CardStats.GetCardStats(cardId, level)
	end,
	ComputePower = function(stats)
		return stats.power or 100
	end
}

-- Stub modules for compatibility
Utilities.ErrorMap = {
	toUserMessage = function(code, fallback)
		return { title = "Error", message = fallback or "An error occurred" }
	end
}

Utilities.BoardLayout = {
	SLOT_ORDER = function() return {1, 2, 3, 4, 5, 6} end,
	gridForDeck = function(deckIds) return {} end,
	oppositeSlot = function(slot) return slot end,
	isValidSlot = function(slot) return slot >= 1 and slot <= 6 end
}

Utilities.Assets = {
	Manifest = {},
	Resolver = {
		getCardImage = function() return "rbxassetid://0" end,
		getClassIcon = function() return "rbxassetid://0" end,
		getRarityFrame = function() return "rbxassetid://0" end,
		getRarityColor = function() return Color3.fromRGB(150, 150, 150) end
	}
}

-- Empty UI utilities (not needed for mock system)
Utilities.Audio = {}
Utilities.ButtonHandler = {}
Utilities.ButtonAnimations = {}
Utilities.Dropdown = {}
Utilities.Icons = {}
Utilities.Particles = {}
Utilities.Popup = {}
Utilities.Short = {}
Utilities.Tween = {}
Utilities.TweenUI = {}
Utilities.Typewrite = {}

return Utilities
