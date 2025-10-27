--[[
	Lootbox Drop Tables
	
	Defines reward probabilities and ranges for each lootbox rarity.
	Used by BoxRoller for deterministic reward generation.
]]

local BoxDropTables = {}

local BoxTypes = require(script.Parent.BoxTypes)

-- Drop table for Uncommon boxes
BoxDropTables.UNCOMMON = {
	softRange = { min = 80, max = 120 },
	hardChance = 0, -- 0% chance
	hardAmount = 0,
	characterRewards = {
		{
			rarity = BoxTypes.BoxRarity.UNCOMMON,
			probability = 0.80, -- 80%
			copiesRange = { min = 2, max = 4 }
		},
		{
			rarity = BoxTypes.BoxRarity.RARE,
			probability = 0.15, -- 15%
			copiesRange = { min = 2, max = 4 }
		},
		{
			rarity = BoxTypes.BoxRarity.EPIC,
			probability = 0.04, -- 4%
			copiesRange = { min = 2, max = 3 }
		},
		{
			rarity = BoxTypes.BoxRarity.LEGENDARY,
			probability = 0.01, -- 1%
			copiesRange = { min = 1, max = 2 }
		}
	}
}

-- Drop table for Rare boxes
BoxDropTables.RARE = {
	softRange = { min = 140, max = 200 },
	hardChance = 0, -- 0% chance
	hardAmount = 0,
	characterRewards = {
		{
			rarity = BoxTypes.BoxRarity.RARE,
			probability = 0.85, -- 85%
			copiesRange = { min = 3, max = 6 }
		},
		{
			rarity = BoxTypes.BoxRarity.EPIC,
			probability = 0.12, -- 12%
			copiesRange = { min = 2, max = 4 }
		},
		{
			rarity = BoxTypes.BoxRarity.LEGENDARY,
			probability = 0.03, -- 3%
			copiesRange = { min = 2, max = 3 }
		}
	}
}

-- Drop table for Epic boxes
BoxDropTables.EPIC = {
	softRange = { min = 220, max = 320 },
	hardChance = 0.09, -- 9% chance
	hardRange = { min = 1, max = 29 }, -- Random int 1..29
	characterRewards = {
		{
			rarity = BoxTypes.BoxRarity.EPIC,
			probability = 0.90, -- 90%
			copiesRange = { min = 4, max = 7 }
		},
		{
			rarity = BoxTypes.BoxRarity.LEGENDARY,
			probability = 0.10, -- 10%
			copiesRange = { min = 2, max = 4 }
		}
	}
}

-- Drop table for Legendary boxes
BoxDropTables.LEGENDARY = {
	softRange = { min = 350, max = 450 },
	hardChance = 0.12, -- 12% chance
	hardRange = { min = 1, max = 77 }, -- Random int 1..77
	characterRewards = {
		{
			rarity = BoxTypes.BoxRarity.LEGENDARY,
			probability = 1.00, -- 100%
			copiesRange = { min = 3, max = 6 }
		}
	}
}

-- Drop table for One Piece boxes
BoxDropTables.ONEPIECE = {
	softRange = { min = 350, max = 450 },
	hardChance = 0.12, -- 12% chance
	hardRange = { min = 1, max = 77 }, -- Random int 1..77
	characterRewards = {
		{
			rarity = BoxTypes.BoxRarity.ONEPIECE,
			probability = 1.00, -- 100%
			copiesRange = { min = 3, max = 6 }
		}
	}
}

-- Get drop table for a specific rarity
function BoxDropTables.GetTable(rarity)
	if rarity == BoxTypes.BoxRarity.UNCOMMON then
		return BoxDropTables.UNCOMMON
	elseif rarity == BoxTypes.BoxRarity.RARE then
		return BoxDropTables.RARE
	elseif rarity == BoxTypes.BoxRarity.EPIC then
		return BoxDropTables.EPIC
	elseif rarity == BoxTypes.BoxRarity.LEGENDARY then
		return BoxDropTables.LEGENDARY
	elseif rarity == BoxTypes.BoxRarity.ONEPIECE then
		return BoxDropTables.ONEPIECE
	else
		error("Invalid rarity: " .. tostring(rarity))
	end
end

-- Validate that all probabilities sum to 1.0 (within floating point tolerance)
function BoxDropTables.ValidateProbabilities()
	local tolerance = 0.001
	
	for rarity, _ in pairs(BoxTypes.BoxRarity) do
		local table = BoxDropTables.GetTable(BoxTypes.BoxRarity[rarity])
		local totalProbability = 0
		
		for _, reward in ipairs(table.characterRewards) do
			totalProbability = totalProbability + reward.probability
		end
		
		if math.abs(totalProbability - 1.0) > tolerance then
			error("Invalid probability sum for " .. rarity .. ": " .. totalProbability)
		end
	end
	
	return true
end

return BoxDropTables
