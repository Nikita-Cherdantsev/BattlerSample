--[[
	BossDecks - Hardcoded boss decks for different difficulty levels
	
	Stores predefined decks for each boss at each difficulty level.
	Format: BossDecks[bossId][difficulty] = { deck = {...}, levels = {...} }
	
	Boss IDs are extracted from part names (e.g., "BossMode1Trigger" -> bossId = "1")
	Difficulty levels: "easy", "normal", "hard", "nightmare", "hell"
]]

local BossDecks = {}

-- Boss 1 decks (example - replace with actual boss decks)
BossDecks["1"] = {
	["easy"] = {
		deck = {
			"card_600", -- Uncommon
			"card_700", -- Uncommon
			"card_1100" -- Uncommon
		},
		levels = { 1, 1, 1 }, -- All level 1 for easy
		reward = {
			type = "lootbox",
			rarity = "uncommon",
			count = 1
		}
	},
	["normal"] = {
		deck = {
			"card_500", -- Rare
			"card_600", -- Uncommon
			"card_700", -- Uncommon
			"card_900" -- Rare
		},
		levels = { 2, 1, 1, 2 }, -- Mix of levels
		reward = {
			type = "lootbox",
			rarity = "rare",
			count = 1
		}
	},
	["hard"] = {
		deck = {
			"card_300", -- Epic
			"card_400", -- Epic
			"card_500", -- Rare
			"card_900", -- Rare
			"card_1200" -- Epic
		},
		levels = { 3, 3, 2, 2, 3 },
		reward = {
			type = "lootbox",
			rarity = "epic",
			count = 1
		}
	},
	["nightmare"] = {
		deck = {
			"card_100", -- Legendary
			"card_200", -- Legendary
			"card_300", -- Epic
			"card_400", -- Epic
			"card_800", -- Legendary
			"card_1000" -- Legendary
		},
		levels = { 5, 5, 4, 4, 5, 5 },
		reward = {
			type = "lootbox",
			rarity = "legendary",
			count = 1
		}
	},
	["hell"] = {
		deck = {
			"card_100", -- Legendary
			"card_200", -- Legendary
			"card_800", -- Legendary
			"card_1000", -- Legendary
			"card_300", -- Epic
			"card_1200" -- Epic
		},
		levels = { 10, 10, 10, 10, 8, 8 }, -- Max levels for hell difficulty
		reward = {
			type = "lootbox",
			rarity = "legendary",
			count = 2 -- Hell difficulty gives 2 legendary lootboxes
		}
	}
}

-- TODO: Add more bosses as needed
-- BossDecks["2"] = { ... }
-- BossDecks["3"] = { ... }

-- Get boss deck for a specific boss and difficulty
function BossDecks.GetDeck(bossId, difficulty)
	if not BossDecks[bossId] then
		warn(string.format("BossDecks: Boss ID '%s' not found", tostring(bossId)))
		return nil
	end
	
	if not BossDecks[bossId][difficulty] then
		warn(string.format("BossDecks: Difficulty '%s' not found for boss '%s'", tostring(difficulty), tostring(bossId)))
		return nil
	end
	
	return BossDecks[bossId][difficulty]
end

-- Get all available difficulties for a boss
function BossDecks.GetDifficulties(bossId)
	if not BossDecks[bossId] then
		return {}
	end
	
	local difficulties = {}
	for difficulty, _ in pairs(BossDecks[bossId]) do
		table.insert(difficulties, difficulty)
	end
	
	-- Sort by difficulty order
	local order = {
		["easy"] = 1,
		["normal"] = 2,
		["hard"] = 3,
		["nightmare"] = 4,
		["hell"] = 5
	}
	
	table.sort(difficulties, function(a, b)
		return (order[a] or 999) < (order[b] or 999)
	end)
	
	return difficulties
end

-- Check if a boss exists
function BossDecks.BossExists(bossId)
	return BossDecks[bossId] ~= nil
end

-- Check if a difficulty exists for a boss
function BossDecks.DifficultyExists(bossId, difficulty)
	return BossDecks[bossId] and BossDecks[bossId][difficulty] ~= nil
end

return BossDecks
