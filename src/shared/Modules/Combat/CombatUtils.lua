local CombatUtils = {}

local CombatTypes = require(script.Parent.CombatTypes)

-- Calculate damage with pure armor pool model
-- If damage <= defence: defence -= damage; HP unchanged
-- If damage > defence: residual = damage - defence; defence = 0; HP -= residual
function CombatUtils.CalculateDamage(baseDamage, targetDefence)
	if not baseDamage or baseDamage <= 0 then
		return 0
	end
	
	-- If no defence, apply full damage to hp
	if not targetDefence or targetDefence <= 0 then
		return baseDamage
	end
	
	-- Pure armor pool: damage depletes defence first, residual goes to HP
	if baseDamage <= targetDefence then
		-- Full absorb: no damage to HP
		return 0
	else
		-- Partial absorb: residual damage to HP
		return baseDamage - targetDefence
	end
end

-- Apply damage with permanent defense model
-- Defense is permanent and never decreases
-- Formula: damageToHp = max(0, damage - defense)
-- Returns: { damageToHp, defenceReduced }
function CombatUtils.ApplyDamageWithDefence(unit, damage)
	if not unit or not damage or damage <= 0 then
		return { damageToHp = 0, defenceReduced = 0 }
	end
	
	local currentDefence = unit.stats.defence or 0
	
	-- Calculate damage to HP after permanent defense reduction
	-- Formula: damageToHp = max(0, damage - defense)
	-- Defense is permanent and never decreases
	local damageToHp = math.max(0, damage - currentDefence)
	local defenceReduced = math.min(damage, currentDefence)
	
	-- Apply damage to hp (health cannot go below 0)
	-- Formula: newHealth = max(0, health - damageToHp)
	local newHealth = math.max(0, unit.stats.health - damageToHp)
	local actualDamage = unit.stats.health - newHealth
	unit.stats.health = newHealth
	
	-- Check if unit died
	if unit.stats.health <= 0 then
		unit.stats.health = 0
		unit.state = CombatTypes.UnitState.DEAD
	end
	
	return { damageToHp = actualDamage, defenceReduced = defenceReduced }
end

-- Legacy function for backward compatibility (now uses armor pool)
function CombatUtils.CalculateDamageLegacy(baseDamage, targetArmor)
	-- Note: This function now uses defence as armor pool instead of armor
	-- The old armor parameter is treated as defence
	return CombatUtils.CalculateDamage(baseDamage, targetArmor)
end

-- Legacy function for backward compatibility (now uses armor pool)
function CombatUtils.ApplyDamage(unit, damage)
	local result = CombatUtils.ApplyDamageWithDefence(unit, damage)
	return result.damageToHp
end

-- Calculate healing with potential buffs/debuffs
function CombatUtils.CalculateHealing(baseHealing, targetStatusEffects)
	if not baseHealing or baseHealing <= 0 then
		return 0
	end
	
	local healingMultiplier = 1.0
	
	-- Apply healing buffs/debuffs from status effects
	if targetStatusEffects then
		for _, effect in pairs(targetStatusEffects) do
			if effect.type == CombatTypes.StatusEffect.REGENERATION then
				healingMultiplier = healingMultiplier * 1.5
			elseif effect.type == CombatTypes.StatusEffect.POISON then
				healingMultiplier = healingMultiplier * 0.5
			end
		end
	end
	
	return math.floor(baseHealing * healingMultiplier)
end

-- Check if a unit can perform actions
function CombatUtils.CanUnitAct(unit)
	if not unit then
		return false
	end
	
	-- Dead units can't act
	if unit.state == CombatTypes.UnitState.DEAD then
		return false
	end
	
	-- Stunned units can't act
	if unit.state == CombatTypes.UnitState.STUNNED then
		return false
	end
	
	-- Units that already acted this turn can't act again
	if unit.hasActed then
		return false
	end
	
	return true
end

-- Check if a unit can be targeted
function CombatUtils.CanUnitBeTargeted(unit, targetType)
	if not unit then
		return false
	end
	
	-- Dead units can't be targeted (except for special effects)
	if unit.state == CombatTypes.UnitState.DEAD then
		return false
	end
	
	-- Invulnerable units can't be targeted by attacks
	if unit.state == CombatTypes.UnitState.INVULNERABLE and targetType == CombatTypes.ActionType.ATTACK then
		return false
	end
	
	return true
end

-- Find valid targets for an action
function CombatUtils.FindValidTargets(board, sourceSlot, targetType, actionType)
	local validTargets = {}
	
	if targetType == CombatTypes.TargetType.SELF then
		-- Self-targeting
		if board[sourceSlot] and CombatUtils.CanUnitBeTargeted(board[sourceSlot], actionType) then
			table.insert(validTargets, sourceSlot)
		end
		
	elseif targetType == CombatTypes.TargetType.SINGLE_ALLY then
		-- Single ally targeting
		for slotIndex, unit in pairs(board) do
			if slotIndex ~= sourceSlot and CombatUtils.CanUnitBeTargeted(unit, actionType) then
				table.insert(validTargets, slotIndex)
			end
		end
		
	elseif targetType == CombatTypes.TargetType.SINGLE_ENEMY then
		-- Single enemy targeting (assumes opposite board)
		-- This would be implemented when we have enemy board logic
		
	elseif targetType == CombatTypes.TargetType.ALL_ALLIES then
		-- All allies including self
		for slotIndex, unit in pairs(board) do
			if CombatUtils.CanUnitBeTargeted(unit, actionType) then
				table.insert(validTargets, slotIndex)
			end
		end
		
	elseif targetType == CombatTypes.TargetType.RANDOM_ALLY then
		-- Random ally (excluding self)
		for slotIndex, unit in pairs(board) do
			if slotIndex ~= sourceSlot and CombatUtils.CanUnitBeTargeted(unit, actionType) then
				table.insert(validTargets, slotIndex)
			end
		end
	end
	
	return validTargets
end

-- Apply healing to a unit
function CombatUtils.ApplyHealing(unit, healing)
	if not unit or not healing or healing <= 0 then
		return 0
	end
	
	-- Can't heal dead units
	if unit.state == CombatTypes.UnitState.DEAD then
		return 0
	end
	
	-- Apply healing (can't exceed max health)
	local actualHealing = math.min(healing, unit.stats.maxHealth - unit.stats.health)
	unit.stats.health = unit.stats.health + actualHealing
	
	return actualHealing
end

-- Apply status effect to a unit
function CombatUtils.ApplyStatusEffect(unit, effectType, duration, value)
	if not unit or not effectType then
		return false
	end
	
	-- Can't apply effects to dead units
	if unit.state == CombatTypes.UnitState.DEAD then
		return false
	end
	
	-- Create or update status effect
	local effectId = effectType .. "_" .. unit.slotIndex
	unit.statusEffects[effectId] = {
		type = effectType,
		duration = duration or 1,
		value = value or 0,
		appliedAt = os.time()
	}
	
	return true
end

-- Process status effects for a unit (called at turn start/end)
function CombatUtils.ProcessStatusEffects(unit)
	if not unit or not unit.statusEffects then
		return
	end
	
	local effectsToRemove = {}
	
	for effectId, effect in pairs(unit.statusEffects) do
		-- Reduce duration
		effect.duration = effect.duration - 1
		
		-- Apply effect value (damage, healing, etc.)
		if effect.type == CombatTypes.StatusEffect.POISON then
			CombatUtils.ApplyDamage(unit, effect.value)
		elseif effect.type == CombatTypes.StatusEffect.REGENERATION then
			CombatUtils.ApplyHealing(unit, effect.value)
		end
		
		-- Mark for removal if duration expired
		if effect.duration <= 0 then
			table.insert(effectsToRemove, effectId)
		end
	end
	
	-- Remove expired effects
	for _, effectId in ipairs(effectsToRemove) do
		unit.statusEffects[effectId] = nil
	end
end

-- Calculate turn order based on fixed slot order (1-6)
-- Note: MVP uses fixed turn order, speed is deprecated
function CombatUtils.CalculateTurnOrder(board)
	local units = {}
	
	-- Collect all units in slot order
	for slotIndex = 1, 6 do
		local unit = board[slotIndex]
		if unit and unit.state ~= CombatTypes.UnitState.DEAD then
			table.insert(units, {
				slotIndex = slotIndex,
				unit = unit
			})
		end
	end
	
	-- Sort by slot index (1-6 order)
	table.sort(units, function(a, b)
		return a.slotIndex < b.slotIndex
	end)
	
	-- Assign turn order
	for i, unitData in ipairs(units) do
		unitData.unit.turnOrder = i
	end
	
	return units
end

-- Check if match has ended
function CombatUtils.CheckMatchEnd(playerBoard, enemyBoard)
	-- Check if all player units are dead
	local allPlayerDead = true
	for _, unit in pairs(playerBoard) do
		if unit.state ~= CombatTypes.UnitState.DEAD then
			allPlayerDead = false
			break
		end
	end
	
	if allPlayerDead then
		return "defeat"
	end
	
	-- Check if all enemy units are dead
	local allEnemyDead = true
	for _, unit in pairs(enemyBoard) do
		if unit.state ~= CombatTypes.UnitState.DEAD then
			allEnemyDead = false
			break
		end
	end
	
	if allEnemyDead then
		return "victory"
	end
	
	return "ongoing"
end

return CombatUtils
