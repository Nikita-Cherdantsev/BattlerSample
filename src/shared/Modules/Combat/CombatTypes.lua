local CombatTypes = {}

-- Unit state during combat
CombatTypes.UnitState = {
	ALIVE = "alive",
	DEAD = "dead",
	STUNNED = "stunned",
	INVULNERABLE = "invulnerable"
}

-- Action types that can be performed
CombatTypes.ActionType = {
	ATTACK = "attack",
	DEFEND = "defend",
	HEAL = "heal",
	SPECIAL = "special",
	PASS = "pass"
}

-- Target types for actions
CombatTypes.TargetType = {
	SELF = "self",
	SINGLE_ALLY = "single_ally",
	SINGLE_ENEMY = "single_enemy",
	ALL_ALLIES = "all_allies",
	ALL_ENEMIES = "all_enemies",
	RANDOM_ENEMY = "random_enemy",
	RANDOM_ALLY = "random_ally"
}

-- Effect types that can be applied
CombatTypes.EffectType = {
	BUFF = "buff",
	DEBUFF = "debuff",
	DAMAGE = "damage",
	HEALING = "healing",
	STATUS = "status"
}

-- Status effect types
CombatTypes.StatusEffect = {
	POISON = "poison",
	BURN = "burn",
	FREEZE = "freeze",
	STUN = "stun",
	SHIELD = "shield",
	REGENERATION = "regeneration"
}

-- Combat unit structure
CombatTypes.Unit = {
	-- Basic properties
	slotIndex = 0,           -- Board position (0-5)
	cardId = "",              -- Reference to card definition
	card = nil,               -- Card data from catalog
	
	-- Combat stats (can be modified during battle)
	stats = {
		attack = 0,
		health = 0,
		maxHealth = 0,
		speed = 0,
		armor = 0
	},
	
	-- State
	state = CombatTypes.UnitState.ALIVE,
	
	-- Status effects
	statusEffects = {},
	
	-- Combat tracking
	lastAction = nil,
	turnOrder = 0,
	hasActed = false
}

-- Action structure
CombatTypes.Action = {
	actionType = CombatTypes.ActionType.ATTACK,
	sourceSlot = 0,          -- Source unit slot
	targetSlot = 0,          -- Target unit slot (if applicable)
	cardId = "",             -- Card used for action
	priority = 0,            -- Action priority (higher = goes first)
	
	-- Action results
	effects = {},            -- Array of effects to apply
	damage = 0,              -- Base damage
	healing = 0,             -- Base healing
	
	-- Metadata
	turnNumber = 0,
	actionId = ""            -- Unique identifier for this action
}

-- Effect structure
CombatTypes.Effect = {
	effectType = CombatTypes.EffectType.DAMAGE,
	targetSlot = 0,          -- Target unit slot
	value = 0,               -- Effect magnitude
	duration = 1,            -- How many turns effect lasts
	statusEffect = nil,      -- Status effect type if applicable
	
	-- Effect metadata
	sourceAction = nil,      -- Reference to source action
	effectId = ""            -- Unique identifier for this effect
}

-- Combat result structure
CombatTypes.CombatResult = {
	action = nil,            -- The action that was performed
	effects = {},            -- Effects that were applied
	damageDealt = 0,        -- Total damage dealt
	healingDone = 0,        -- Total healing done
	statusEffectsApplied = {}, -- Status effects applied
	unitStates = {},         -- Unit states after action
	
	-- Metadata
	turnNumber = 0,
	timestamp = 0
}

-- Turn structure
CombatTypes.Turn = {
	turnNumber = 0,
	actions = {},            -- Actions performed this turn
	results = {},            -- Results of all actions
	unitStates = {},         -- State of all units at end of turn
	
	-- Turn metadata
	startTime = 0,
	endTime = 0,
	phase = "execution"      -- "planning", "execution", "cleanup"
}

-- Match state structure
CombatTypes.MatchState = {
	matchId = "",
	phase = "setup",         -- "setup", "combat", "victory", "defeat"
	turnNumber = 0,
	currentTurn = nil,       -- Current turn data
	
	-- Board state
	playerBoard = {},        -- Player units (slots 0-5)
	enemyBoard = {},         -- Enemy units (slots 0-5)
	
	-- Match metadata
	startTime = 0,
	lastActionTime = 0,
	seed = 0,               -- RNG seed for determinism
	
	-- Victory conditions
	victoryConditions = {},
	defeatConditions = {}
}

-- Utility functions for type checking
function CombatTypes.IsValidUnit(unit)
	return unit and 
		   type(unit.slotIndex) == "number" and
		   type(unit.cardId) == "string" and
		   unit.card ~= nil and
		   unit.stats and
		   unit.state
end

function CombatTypes.IsValidAction(action)
	return action and
		   type(action.actionType) == "string" and
		   type(action.sourceSlot) == "number" and
		   type(action.targetSlot) == "number" and
		   type(action.cardId) == "string"
end

function CombatTypes.IsValidEffect(effect)
	return effect and
		   type(effect.effectType) == "string" and
		   type(effect.targetSlot) == "number" and
		   type(effect.value) == "number"
end

return CombatTypes
