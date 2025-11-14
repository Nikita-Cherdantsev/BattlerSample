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
			"card_700",
			"card_1100",
			"card_1300"
		},
		levels = { 1, 1, 1 },
		reward = {
			type = "lootbox",
			rarity = "onepiece",
			count = 1
		}
	},
	["normal"] = {
		deck = {
			"card_500",
			"card_700",
			"card_1100",
			"card_1300"
		},
		levels = { 1, 3, 3, 3 },
		reward = {
			type = "lootbox",
			rarity = "onepiece",
			count = 1
		}
	},
	["hard"] = {
		deck = {
			"card_100",
			"card_200",
			"card_500",
			"card_700",
			"card_1100",
			"card_1300"
		},
		levels = { 1, 1, 5, 10, 10, 10 },
		reward = {
			type = "lootbox",
			rarity = "onepiece",
			count = 1
		}
	},
	["nightmare"] = {
		deck = {
			"card_100",
			"card_200",
			"card_500",
			"card_700",
			"card_1100",
			"card_1300"
		},
		levels = { 3, 3, 7, 10, 10, 10 },
		reward = {
			type = "lootbox",
			rarity = "onepiece",
			count = 1
		}
	},
	["hell"] = {
		deck = {
			"card_100",
			"card_200",
			"card_500",
			"card_700",
			"card_1100",
			"card_1300"
		},
		levels = { 5, 5, 10, 10, 10, 10 },
		reward = {
			type = "lootbox",
			rarity = "onepiece",
			count = 1
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
