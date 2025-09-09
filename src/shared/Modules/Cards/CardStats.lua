local CardStats = {}

local CardCatalog = require(script.Parent.CardCatalog)
local Types = require(script.Parent.Parent.Types)

-- Compute stats for a card at a specific level
-- Uses per-card base + growth tables, clamps level to [1,MAX_LEVEL]
function CardStats.ComputeStats(cardId, level)
	local card = CardCatalog.GetCard(cardId)
	if not card then
		error("Invalid card ID: " .. tostring(cardId))
	end
	
	-- Clamp level to valid range
	level = math.max(1, math.min(level, Types.MAX_LEVEL))
	
	-- Start with base stats (level 1)
	local stats = {
		atk = card.base.atk,
		hp = card.base.hp,
		defence = card.base.defence
	}
	
	-- Apply per-level growth deltas (from level 2 upwards)
	if level > 1 then
		for l = 2, level do
			local growth = card.growth[l]
			if growth then
				stats.atk = stats.atk + (growth.atk or 0)
				stats.hp = stats.hp + (growth.hp or 0)
				stats.defence = stats.defence + (growth.defence or 0)
			end
		end
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
	return CardStats.ComputeStats(cardId, Types.MAX_LEVEL)
end

-- Get the maximum possible power for a card (at max level)
function CardStats.GetMaxPower(cardId)
	return CardStats.ComputeCardPower(cardId, Types.MAX_LEVEL)
end

return CardStats
