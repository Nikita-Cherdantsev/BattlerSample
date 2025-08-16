local GameConstants = {}

-- Board configuration
GameConstants.BOARD = {
	WIDTH = 3,
	HEIGHT = 2,
	TOTAL_SLOTS = 6,
	SLOT_INDICES = {1, 2, 3, 4, 5, 6}
}

-- Deck configuration
GameConstants.DECK = {
	MIN_SIZE = 6,
	MAX_SIZE = 6,
	MAX_DUPLICATES = 6 -- For Step 2A, allow unlimited duplicates
}

-- Combat configuration
GameConstants.COMBAT = {
	MIN_DAMAGE = 1,
	MAX_DAMAGE = 999,
	MIN_HEALING = 0,
	MAX_HEALING = 999,
	MIN_ARMOR = 0,
	MAX_ARMOR = 100,
	
	-- Turn configuration
	TURN_TIMEOUT = 30, -- seconds
	MAX_TURNS = 100,   -- prevent infinite matches
	
	-- Status effect durations
	STATUS_EFFECT = {
		MIN_DURATION = 1,
		MAX_DURATION = 10,
		DEFAULT_DURATION = 3
	}
}

-- Card rarity weights (for lootbox generation later)
GameConstants.RARITY_WEIGHTS = {
	COMMON = 60,      -- 60%
	RARE = 30,        -- 30%
	EPIC = 8,         -- 8%
	LEGENDARY = 2     -- 2%
}

-- Card class distribution limits (for deck building later)
GameConstants.CLASS_LIMITS = {
	DPS = {min = 0, max = 6},
	SUPPORT = {min = 0, max = 6},
	TANK = {min = 0, max = 6}
}

-- Match configuration
GameConstants.MATCH = {
	-- Victory conditions
	VICTORY_CONDITIONS = {
		ALL_ENEMIES_DEAD = "all_enemies_dead",
		SPECIAL_OBJECTIVE = "special_objective"
	},
	
	-- Defeat conditions
	DEFEAT_CONDITIONS = {
		ALL_PLAYERS_DEAD = "all_players_dead",
		TURN_LIMIT_REACHED = "turn_limit_reached"
	}
}

-- RNG configuration
GameConstants.RNG = {
	-- Seed generation
	SEED_SOURCES = {
		MATCH_ID = "match_id",
		TIMESTAMP = "timestamp",
		PLAYER_ID = "player_id"
	},
	
	-- Default seed fallback
	DEFAULT_SEED = 12345
}

-- Performance configuration
GameConstants.PERFORMANCE = {
	-- Combat calculation limits
	MAX_ACTIONS_PER_TURN = 10,
	MAX_EFFECTS_PER_ACTION = 5,
	
	-- Board state limits
	MAX_STATUS_EFFECTS_PER_UNIT = 10,
	MAX_UNITS_PER_BOARD = 6
}

-- Validation configuration
GameConstants.VALIDATION = {
	-- Input validation
	MAX_CARD_ID_LENGTH = 50,
	MAX_CARD_NAME_LENGTH = 100,
	
	-- Stat validation
	MIN_STAT_VALUE = 0,
	MAX_STAT_VALUE = 999
}

return GameConstants
