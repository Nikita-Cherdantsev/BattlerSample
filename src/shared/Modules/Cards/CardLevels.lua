local CardLevels = {}

local Types = require(script.Parent.Parent.Types)

-- Level progression table (levels 1-10)
-- Each level requires: requiredCount copies + softAmount currency to unlock
CardLevels.LevelTable = {
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

-- Maximum level (use shared constant)
CardLevels.MAX_LEVEL = Types.MAX_LEVEL

-- Get level cost information
function CardLevels.GetLevelCost(level)
	if level < 1 or level > CardLevels.MAX_LEVEL then
		return nil
	end
	return CardLevels.LevelTable[level]
end

-- Check if a card can be leveled up
function CardLevels.CanLevelUp(cardId, currentLevel, currentCount, softCurrency)
	if currentLevel >= CardLevels.MAX_LEVEL then
		return false, "Already at maximum level"
	end
	
	local nextLevel = currentLevel + 1
	local cost = CardLevels.GetLevelCost(nextLevel)
	
	if not cost then
		return false, "Invalid level"
	end
	
	if currentCount < cost.requiredCount then
		return false, string.format("Need %d copies (have %d)", cost.requiredCount, currentCount)
	end
	
	if softCurrency < cost.softAmount then
		return false, string.format("Need %d soft currency (have %d)", cost.softAmount, softCurrency)
	end
	
	return true, nil
end

-- Calculate the cost to level up (returns copies and currency needed)
function CardLevels.GetLevelUpCost(cardId, currentLevel, currentCount, softCurrency)
	if currentLevel >= CardLevels.MAX_LEVEL then
		return nil, "Already at maximum level"
	end
	
	local nextLevel = currentLevel + 1
	local cost = CardLevels.GetLevelCost(nextLevel)
	
	if not cost then
		return nil, "Invalid level"
	end
	
	return {
		requiredCount = cost.requiredCount,
		softAmount = cost.softAmount,
		canAfford = (currentCount >= cost.requiredCount and softCurrency >= cost.softAmount)
	}
end

return CardLevels
