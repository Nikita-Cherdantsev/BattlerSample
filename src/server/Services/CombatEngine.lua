local CombatEngine = {}

-- Modules
local DeckValidator = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("DeckValidator"))
local SeededRNG = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RNG"):WaitForChild("SeededRNG"))
local CombatTypes = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Combat"):WaitForChild("CombatTypes"))
local CombatUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Combat"):WaitForChild("CombatUtils"))
local CardCatalog = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("CardCatalog"))
local CardStats = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("CardStats"))

-- Configuration
local MAX_ROUNDS = 50 -- Hard cap to prevent infinite battles

-- Battle state
local BattleState = {
	round = 0,
	winner = nil,
	boardA = {}, -- Player A units (slots 1-6)
	boardB = {}, -- Player B units (slots 1-6)
	rng = nil,
	battleLog = {},
	isComplete = false
}

-- Utility functions
local function LogInfo(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("[CombatEngine] %s", formattedMessage))
end

local function LogWarning(message, ...)
	local formattedMessage = string.format(message, ...)
	warn(string.format("[CombatEngine] %s", formattedMessage))
end

local function CreateUnitFromCard(cardId, slotIndex, playerId, level)
	local card = CardCatalog.GetCard(cardId)
	if not card then
		error("Invalid card ID: " .. tostring(cardId))
	end
	
	-- Compute stats for the card at the given level
	local stats = CardStats.ComputeStats(cardId, level or 1)
	
	return {
		slotIndex = slotIndex,
		playerId = playerId,
		cardId = cardId,
		card = card,
		stats = {
			attack = stats.atk,
			health = stats.hp,
			maxHealth = stats.hp,
			defence = stats.defence
		},
		state = CombatTypes.UnitState.ALIVE,
		statusEffects = {},
		hasActed = false,
		turnOrder = 0
	}
end

local function InitializeBoard(deck, playerId, collection)
	local board = {}
	
	-- Validate deck for battle (must have 1-6 cards)
	local isValid, errorMessage = DeckValidator.ValidateDeckForBattle(deck)
	if not isValid then
		error("Invalid deck for player " .. playerId .. ": " .. errorMessage)
	end
	
	local boardMapping = DeckValidator.MapDeckToBoard(deck)
	
	-- Create units from board mapping with levels from collection
	for slotIndex, slotData in pairs(boardMapping) do
		local cardEntry = collection and collection[slotData.cardId]
		local level = cardEntry and cardEntry.level or 1
		
		board[slotIndex] = CreateUnitFromCard(slotData.cardId, slotIndex, playerId, level)
	end
	
	return board
end

local function GetAliveUnits(board)
	local aliveUnits = {}
	for slotIndex, unit in pairs(board) do
		if unit.state == CombatTypes.UnitState.ALIVE then
			table.insert(aliveUnits, unit)
		end
	end
	return aliveUnits
end

-- Fixed turn order: 1, 2, 3, 4, 5, 6 (v2 combat rules)
local function CalculateTurnOrder(boardA, boardB)
	local allUnits = {}
	
	-- Collect all alive units from both boards in slot order
	for slotIndex = 1, 6 do
		local unitA = boardA[slotIndex]
		if unitA and unitA.state == CombatTypes.UnitState.ALIVE then
			table.insert(allUnits, unitA)
		end
		
		local unitB = boardB[slotIndex]
		if unitB and unitB.state == CombatTypes.UnitState.ALIVE then
			table.insert(allUnits, unitB)
		end
	end
	
	-- Sort by slot index (1-6 order)
	table.sort(allUnits, function(a, b)
		return a.slotIndex < b.slotIndex
	end)
	
	-- Assign turn order
	for i, unit in ipairs(allUnits) do
		unit.turnOrder = i
	end
	
	return allUnits
end

-- Find target: first available slot starting from slot 1
local function FindTarget(attacker, boardA, boardB)
	local targetBoard = (attacker.playerId == "A") and boardB or boardA
	
	-- Find first available living enemy starting from slot 1
	for slotIndex = 1, 6 do
		local unit = targetBoard[slotIndex]
		if unit and unit.state == CombatTypes.UnitState.ALIVE then
			return unit
		end
	end
	
	-- No targets available
	return nil
end

local function ApplyPassiveEffects(unit, effectType, context)
	-- Placeholder for passive effects
	-- This is where passive perks would be applied later
	-- effectType: "pre_attack", "on_hit", "on_death", etc.
	-- context: additional data for the effect
	
	-- For MVP, no passive effects are applied
	return context
end

-- Calculate base damage with effects (defense is handled in ApplyDamageWithDefence)
local function CalculateDamage(attacker, defender)
	-- Apply pre-attack effects
	local attackContext = {
		damage = attacker.stats.attack,
		attacker = attacker,
		defender = defender
	}
	attackContext = ApplyPassiveEffects(attacker, "pre_attack", attackContext)
	
	-- Return base damage after pre-attack effects (defense will be handled separately)
	local baseDamage = attackContext.damage
	
	-- Apply on-hit effects
	local hitContext = {
		damage = baseDamage,
		attacker = attacker,
		defender = defender
	}
	hitContext = ApplyPassiveEffects(attacker, "on_hit", hitContext)
	
	-- Return the final base damage (defense will be applied in ApplyDamageWithDefence)
	return hitContext.damage
end

-- Execute attack with defence soak model
local function ExecuteAttack(attacker, defender, battleState)
	-- Validate attack
	if attacker.state ~= CombatTypes.UnitState.ALIVE then
		LogWarning("Dead unit attempted to attack")
		return false
	end
	
	if defender.state ~= CombatTypes.UnitState.ALIVE then
		LogWarning("Attempted to attack dead unit")
		return false
	end
	
	if attacker.hasActed then
		LogWarning("Unit already acted this turn")
		return false
	end
	
	-- Calculate damage
	local damage = CalculateDamage(attacker, defender)
	
	-- Apply damage with defence soak model
	local damageResult = CombatUtils.ApplyDamageWithDefence(defender, damage)
	
	-- Mark attacker as acted
	attacker.hasActed = true
	
	-- Log the attack
	local logEntry = {
		type = "attack",
		round = battleState.round,
		attackerSlot = attacker.slotIndex,
		attackerPlayer = attacker.playerId,
		defenderSlot = defender.slotIndex,
		defenderPlayer = defender.playerId,
		damage = damageResult.damageToHp,
		defenceReduced = damageResult.defenceReduced,
		defenderHealth = defender.stats.health,
		defenderDefence = defender.stats.defence,
		defenderKO = (defender.state == CombatTypes.UnitState.DEAD)
	}
	
	table.insert(battleState.battleLog, logEntry)
	
	-- Apply on-death effects if defender died
	if defender.state == CombatTypes.UnitState.DEAD then
		LogInfo("KO: %s slot %d (%s) defeated", defender.playerId, defender.slotIndex, defender.cardId)
		local deathContext = {
			killer = attacker,
			victim = defender
		}
		ApplyPassiveEffects(attacker, "on_death", deathContext)
	end
	
	-- LogInfo("Attack: %s slot %d → %s slot %d, HP damage: %d, armor reduced: %d, defender HP: %d, defender armor: %d, KO: %s", 
	--	attacker.playerId, attacker.slotIndex, 
	--	defender.playerId, defender.slotIndex, 
	--	damageResult.damageToHp, damageResult.defenceReduced, defender.stats.health, defender.stats.defence, tostring(logEntry.defenderKO))
	
	return true
end

local function CheckBattleEnd(boardA, boardB)
	local aliveA = GetAliveUnits(boardA)
	local aliveB = GetAliveUnits(boardB)
	
	if #aliveA == 0 and #aliveB == 0 then
		return "Draw"
	elseif #aliveA == 0 then
		return "B"
	elseif #aliveB == 0 then
		return "A"
	else
		return nil -- Battle continues
	end
end

local function ResetTurnFlags(boardA, boardB)
	for _, unit in pairs(boardA) do
		unit.hasActed = false
	end
	for _, unit in pairs(boardB) do
		unit.hasActed = false
	end
end

local function ProcessStatusEffects(boardA, boardB)
	-- Process status effects for all units
	for _, unit in pairs(boardA) do
		CombatUtils.ProcessStatusEffects(unit)
	end
	for _, unit in pairs(boardB) do
		CombatUtils.ProcessStatusEffects(unit)
	end
end

-- Public API

-- Execute a complete battle between two decks
function CombatEngine.ExecuteBattle(deckA, deckB, seed, collectionA, collectionB)
	LogInfo("Starting battle with seed: %s", tostring(seed))
	
	-- Initialize battle state
	local battleState = {
		round = 0,
		winner = nil,
		boardA = InitializeBoard(deckA, "A", collectionA),
		boardB = InitializeBoard(deckB, "B", collectionB),
		rng = SeededRNG.New(seed),
		battleLog = {},
		isComplete = false
	}
	
	-- Battle loop
	while battleState.round < MAX_ROUNDS do
		battleState.round = battleState.round + 1
		-- LogInfo("Starting round %d", battleState.round)
		
		-- Add round marker to log
		table.insert(battleState.battleLog, {
			type = "round_start",
			round = battleState.round
		})
		
		-- Process status effects at start of round
		ProcessStatusEffects(battleState.boardA, battleState.boardB)
		
		-- Calculate turn order (fixed 1-6 order)
		local turnOrder = CalculateTurnOrder(battleState.boardA, battleState.boardB)
		
		-- Execute turns
		for _, unit in ipairs(turnOrder) do
			-- Skip if unit is dead
			if unit.state ~= CombatTypes.UnitState.ALIVE then
				-- Skip to next iteration
			elseif unit.stats.attack <= 0 then
				-- Skip units with zero or negative attack (they can't deal damage)
				LogInfo("Skip: %s slot %d (%s) - zero attack", unit.playerId, unit.slotIndex, unit.cardId)
				-- Skip to next iteration
			else
				-- Find target
				local target = FindTarget(unit, battleState.boardA, battleState.boardB)
				if not target then
					-- No valid targets, skip turn
					LogInfo("Skip: %s slot %d (%s) - no valid target", unit.playerId, unit.slotIndex, unit.cardId)
					-- Skip to next iteration
				else
					-- Execute attack
					ExecuteAttack(unit, target, battleState)
					
					-- Check if battle ended
					local winner = CheckBattleEnd(battleState.boardA, battleState.boardB)
					if winner then
						battleState.winner = winner
						battleState.isComplete = true
						break
					end
				end
			end
		end
		
		-- Reset turn flags for next round
		ResetTurnFlags(battleState.boardA, battleState.boardB)
		
		-- Check if battle ended
		if battleState.isComplete then
			break
		end
	end
	
	-- Handle stalemate
	if not battleState.isComplete then
		battleState.winner = "Draw"
		battleState.isComplete = true
		LogWarning("Battle ended in stalemate after %d rounds", MAX_ROUNDS)
	end
	
	-- Create battle result
	local result = {
		winner = battleState.winner,
		rounds = battleState.round,
		survivorsA = GetAliveUnits(battleState.boardA),
		survivorsB = GetAliveUnits(battleState.boardB),
		battleLog = battleState.battleLog
	}
	
	-- LogInfo("Battle complete. Winner: %s, Rounds: %d", result.winner, result.rounds)
	
	return result
end

-- Get battle statistics
function CombatEngine.GetBattleStats(battleResult)
	local stats = {
		totalRounds = battleResult.rounds,
		winner = battleResult.winner,
		survivorsA = #battleResult.survivorsA,
		survivorsB = #battleResult.survivorsB,
		totalActions = 0,
		totalDamage = 0,
		totalDefenceReduced = 0,
		totalKOs = 0
	}
	
	for _, logEntry in ipairs(battleResult.battleLog) do
		if logEntry.type == "attack" then
			stats.totalActions = stats.totalActions + 1
			stats.totalDamage = stats.totalDamage + logEntry.damage
			stats.totalDefenceReduced = stats.totalDefenceReduced + (logEntry.defenceReduced or 0)
			if logEntry.defenderKO then
				stats.totalKOs = stats.totalKOs + 1
			end
		end
	end
	
	return stats
end

-- Validate battle result
function CombatEngine.ValidateBattleResult(battleResult)
	-- Check required fields
	if not battleResult.winner or not battleResult.rounds or not battleResult.battleLog then
		return false, "Missing required fields"
	end
	
	-- Check winner is valid
	if battleResult.winner ~= "A" and battleResult.winner ~= "B" and battleResult.winner ~= "Draw" then
		return false, "Invalid winner"
	end
	
	-- Check rounds is reasonable
	if battleResult.rounds < 1 or battleResult.rounds > MAX_ROUNDS then
		return false, "Invalid round count"
	end
	
	-- Check battle log structure
	for i, logEntry in ipairs(battleResult.battleLog) do
		if not logEntry.type then
			return false, "Log entry " .. i .. " missing type"
		end
		
		if logEntry.type == "attack" then
			if not logEntry.attackerSlot or not logEntry.defenderSlot or not logEntry.damage then
				return false, "Attack log entry " .. i .. " missing required fields"
			end
		end
	end
	
	return true
end

return CombatEngine
