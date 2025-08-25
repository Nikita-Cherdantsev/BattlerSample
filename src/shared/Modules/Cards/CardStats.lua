local CardStats = {}

local CardCatalog = require(script.Parent.CardCatalog)
local CardLevels = require(script.Parent.CardLevels)

-- Compute stats for a card at a specific level
-- Uses baseStats + per-level increments, clamps level to [1,7]
function CardStats.ComputeStats(cardId, level)
	local card = CardCatalog.GetCard(cardId)
	if not card then
		error("Invalid card ID: " .. tostring(cardId))
	end
	
	-- Clamp level to valid range
	level = math.max(1, math.min(level, CardLevels.MAX_LEVEL))
	
	-- Start with base stats (level 1)
	local stats = {
		atk = card.baseStats.attack,
		hp = card.baseStats.health,
		defence = card.baseStats.defence or 0  -- Default to 0 if not present
	}
	
	-- Apply level increments (from level 2 upwards)
	if level > 1 then
		local increments = card.levelIncrements or CardLevels.DefaultIncrements
		local levelsToApply = level - 1
		
		stats.atk = stats.atk + (increments.atk * levelsToApply)
		stats.hp = stats.hp + (increments.hp * levelsToApply)
		stats.defence = stats.defence + (increments.defence * levelsToApply)
	end
	
	return stats
end

-- Compute power from stats (floor of average of atk + defence + hp)
function CardStats.ComputePower(stats)
	if not stats or not stats.atk or not stats.defence or not stats.hp then
		error("Invalid stats object")
	end
	
	return math.floor((stats.atk + stats.defence + stats.hp) / 3)
end

-- Compute power for a card at a specific level
function CardStats.ComputeCardPower(cardId, level)
	local stats = CardStats.ComputeStats(cardId, level)
	return CardStats.ComputePower(stats)
end

-- Get the maximum possible stats for a card (at max level)
function CardStats.GetMaxStats(cardId)
	return CardStats.ComputeStats(cardId, CardLevels.MAX_LEVEL)
end

-- Get the maximum possible power for a card (at max level)
function CardStats.GetMaxPower(cardId)
	return CardStats.ComputeCardPower(cardId, CardLevels.MAX_LEVEL)
end

return CardStats
