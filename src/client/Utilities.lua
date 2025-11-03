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
	LootboxState = { Idle = "Idle", Unlocking = "Unlocking", Ready = "Ready" }
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
			-- Legendary cards
			["card_100"] = { slotNumber = 100, rarity = "legendary", class = "dps" },    -- Monkey D. Luffy
			["card_200"] = { slotNumber = 200, rarity = "legendary", class = "tank" },   -- Roronoa Zoro
			["card_800"] = { slotNumber = 800, rarity = "legendary", class = "dps" },   -- Vegeta
			["card_1000"] = { slotNumber = 1000, rarity = "legendary", class = "dps" },  -- Goku
			
			-- Epic cards
			["card_300"] = { slotNumber = 300, rarity = "epic", class = "dps" },        -- Rock Lee
			["card_400"] = { slotNumber = 400, rarity = "epic", class = "tank" },        -- Tsunade
			["card_1200"] = { slotNumber = 1200, rarity = "epic", class = "dps" },       -- All Might
			
			-- Rare cards
			["card_500"] = { slotNumber = 500, rarity = "rare", class = "dps" },        -- Sanji
			["card_900"] = { slotNumber = 900, rarity = "rare", class = "dps" },         -- Shino Aburame
			["card_1500"] = { slotNumber = 1500, rarity = "rare", class = "dps" },       -- Bakugo
			
			-- Uncommon cards
			["card_600"] = { slotNumber = 600, rarity = "uncommon", class = "support" },  -- Tenten
			["card_700"] = { slotNumber = 700, rarity = "uncommon", class = "support" }, -- Koby
			["card_1100"] = { slotNumber = 1100, rarity = "uncommon", class = "support" }, -- Usopp
			["card_1300"] = { slotNumber = 1300, rarity = "uncommon", class = "support" }, -- Chopper
			["card_1400"] = { slotNumber = 1400, rarity = "uncommon", class = "support" }, -- Krillin
			["card_1600"] = { slotNumber = 1600, rarity = "uncommon", class = "dps" },   -- Yamcha
			["card_1700"] = { slotNumber = 1700, rarity = "uncommon", class = "dps" },   -- Midoriya
			["card_1800"] = { slotNumber = 1800, rarity = "uncommon", class = "support" }, -- Piccolo
		}
	end,
	GetCard = function(cardId)
		-- Access the cards directly to avoid circular reference
		local cards = {
			-- Legendary cards
			["card_100"] = { slotNumber = 100, rarity = "legendary", class = "dps" },    -- Monkey D. Luffy
			["card_200"] = { slotNumber = 200, rarity = "legendary", class = "tank" },   -- Roronoa Zoro
			["card_800"] = { slotNumber = 800, rarity = "legendary", class = "dps" },   -- Vegeta
			["card_1000"] = { slotNumber = 1000, rarity = "legendary", class = "dps" },  -- Goku
			
			-- Epic cards
			["card_300"] = { slotNumber = 300, rarity = "epic", class = "dps" },        -- Rock Lee
			["card_400"] = { slotNumber = 400, rarity = "epic", class = "tank" },        -- Tsunade
			["card_1200"] = { slotNumber = 1200, rarity = "epic", class = "dps" },       -- All Might
			
			-- Rare cards
			["card_500"] = { slotNumber = 500, rarity = "rare", class = "dps" },        -- Sanji
			["card_900"] = { slotNumber = 900, rarity = "rare", class = "dps" },         -- Shino Aburame
			["card_1500"] = { slotNumber = 1500, rarity = "rare", class = "dps" },       -- Bakugo
			
			-- Uncommon cards
			["card_600"] = { slotNumber = 600, rarity = "uncommon", class = "support" },  -- Tenten
			["card_700"] = { slotNumber = 700, rarity = "uncommon", class = "support" }, -- Koby
			["card_1100"] = { slotNumber = 1100, rarity = "uncommon", class = "support" }, -- Usopp
			["card_1300"] = { slotNumber = 1300, rarity = "uncommon", class = "support" }, -- Chopper
			["card_1400"] = { slotNumber = 1400, rarity = "uncommon", class = "support" }, -- Krillin
			["card_1600"] = { slotNumber = 1600, rarity = "uncommon", class = "dps" },   -- Yamcha
			["card_1700"] = { slotNumber = 1700, rarity = "uncommon", class = "dps" },   -- Midoriya
			["card_1800"] = { slotNumber = 1800, rarity = "uncommon", class = "support" }, -- Piccolo
		}
		return cards[cardId]
	end
}

-- Client-side deck validation
Utilities.DeckValidator = {
	ValidateDeck = function(deckIds)
		-- Allow decks with 1-6 cards
		if not deckIds or #deckIds == 0 then
			return false, "Deck must contain at least 1 card"
		end
		if #deckIds > 6 then
			return false, "Deck must contain at most 6 cards"
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
	MAX_LEVEL = 10,
	GetLevelCost = function(level)
		local levelCosts = {
			[1] = { requiredCount = 1, softAmount = 0 },
			[2] = { requiredCount = 10, softAmount = 12000 },
			[3] = { requiredCount = 20, softAmount = 50000 },
			[4] = { requiredCount = 40, softAmount = 200000 },
			[5] = { requiredCount = 80, softAmount = 500000 },
			[6] = { requiredCount = 160, softAmount = 800000 },
			[7] = { requiredCount = 320, softAmount = 1200000 },
			-- TODO(design): placeholder, replace with final numbers
			[8] = { requiredCount = 640, softAmount = 2000000 },
			[9] = { requiredCount = 1280, softAmount = 5000000 },
			[10] = { requiredCount = 2560, softAmount = 10000000 }
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
