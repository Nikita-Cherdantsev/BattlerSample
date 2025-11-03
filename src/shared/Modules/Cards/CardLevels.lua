local CardLevels = {}

local Types = require(script.Parent.Parent.Types)

-- Level progression table by rarity (levels 1-10)
-- Each level requires: requiredCount copies + softAmount currency to unlock
CardLevels.LevelTable = {
	uncommon = {
		[1] = { requiredCount = 1, softAmount = 0 },
		[2] = { requiredCount = 2, softAmount = 96 },
		[3] = { requiredCount = 3, softAmount = 115 },
		[4] = { requiredCount = 4, softAmount = 138 },
		[5] = { requiredCount = 5, softAmount = 166 },
		[6] = { requiredCount = 6, softAmount = 199 },
		[7] = { requiredCount = 8, softAmount = 239 },
		[8] = { requiredCount = 10, softAmount = 287 },
		[9] = { requiredCount = 12, softAmount = 344 },
		[10] = { requiredCount = 15, softAmount = 413 }
	},
	rare = {
		[1] = { requiredCount = 1, softAmount = 0 },
		[2] = { requiredCount = 4, softAmount = 150 },
		[3] = { requiredCount = 5, softAmount = 188 },
		[4] = { requiredCount = 7, softAmount = 234 },
		[5] = { requiredCount = 10, softAmount = 293 },
		[6] = { requiredCount = 13, softAmount = 366 },
		[7] = { requiredCount = 18, softAmount = 458 },
		[8] = { requiredCount = 25, softAmount = 572 },
		[9] = { requiredCount = 33, softAmount = 715 },
		[10] = { requiredCount = 45, softAmount = 894 }
	},
	epic = {
		[1] = { requiredCount = 1, softAmount = 0 },
		[2] = { requiredCount = 7, softAmount = 234 },
		[3] = { requiredCount = 11, softAmount = 304 },
		[4] = { requiredCount = 15, softAmount = 395 },
		[5] = { requiredCount = 22, softAmount = 514 },
		[6] = { requiredCount = 32, softAmount = 668 },
		[7] = { requiredCount = 46, softAmount = 869 },
		[8] = { requiredCount = 67, softAmount = 1129 },
		[9] = { requiredCount = 98, softAmount = 1468 },
		[10] = { requiredCount = 142, softAmount = 1909 }
	},
	legendary = {
		[1] = { requiredCount = 1, softAmount = 0 },
		[2] = { requiredCount = 12, softAmount = 378 },
		[3] = { requiredCount = 19, softAmount = 510 },
		[4] = { requiredCount = 30, softAmount = 689 },
		[5] = { requiredCount = 46, softAmount = 930 },
		[6] = { requiredCount = 72, softAmount = 1256 },
		[7] = { requiredCount = 111, softAmount = 1695 },
		[8] = { requiredCount = 172, softAmount = 2288 },
		[9] = { requiredCount = 267, softAmount = 3089 },
		[10] = { requiredCount = 413, softAmount = 4170 }
	}
}

-- Maximum level (use shared constant)
CardLevels.MAX_LEVEL = Types.MAX_LEVEL

-- Get level cost information for a specific rarity
function CardLevels.GetLevelCost(level, rarity)
	if level < 1 or level > CardLevels.MAX_LEVEL then
		return nil
	end
	
	local rarityTable = CardLevels.LevelTable[rarity]
	if not rarityTable then
		return nil
	end
	
	return rarityTable[level]
end

-- Check if a card can be leveled up
function CardLevels.CanLevelUp(cardId, currentLevel, currentCount, softCurrency, rarity)
	if currentLevel >= CardLevels.MAX_LEVEL then
		return false, "Already at maximum level"
	end
	
	local nextLevel = currentLevel + 1
	local cost = CardLevels.GetLevelCost(nextLevel, rarity)
	
	if not cost then
		return false, "Invalid level or rarity"
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
function CardLevels.GetLevelUpCost(cardId, currentLevel, currentCount, softCurrency, rarity)
	if currentLevel >= CardLevels.MAX_LEVEL then
		return nil, "Already at maximum level"
	end
	
	local nextLevel = currentLevel + 1
	local cost = CardLevels.GetLevelCost(nextLevel, rarity)
	
	if not cost then
		return nil, "Invalid level or rarity"
	end
	
	return {
		requiredCount = cost.requiredCount,
		softAmount = cost.softAmount,
		canAfford = (currentCount >= cost.requiredCount and softCurrency >= cost.softAmount)
	}
end

return CardLevels
