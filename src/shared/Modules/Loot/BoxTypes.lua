--[[
	Lootbox Types and Constants
	
	Defines enums, constants, and helper functions for the lootbox system.
]]

local BoxTypes = {}

-- Box rarity enum
BoxTypes.BoxRarity = {
	UNCOMMON = "uncommon",
	RARE = "rare", 
	EPIC = "epic",
	LEGENDARY = "legendary"
}

-- Box state enum
BoxTypes.BoxState = {
	IDLE = "Idle",
	UNLOCKING = "Unlocking",
	READY = "Ready",
	CONSUMED = "Consumed"
}

-- Duration in seconds for each rarity
BoxTypes.DurationSeconds = {
	[BoxTypes.BoxRarity.UNCOMMON] = 7 * 60,    -- 7 minutes
	[BoxTypes.BoxRarity.RARE] = 30 * 60,       -- 30 minutes
	[BoxTypes.BoxRarity.EPIC] = 120 * 60,     -- 120 minutes
	[BoxTypes.BoxRarity.LEGENDARY] = 240 * 60  -- 240 minutes
}

-- Hard currency cost to buy a box from store
BoxTypes.StoreHardCost = {
	[BoxTypes.BoxRarity.UNCOMMON] = 7,
	[BoxTypes.BoxRarity.RARE] = 22,
	[BoxTypes.BoxRarity.EPIC] = 55,
	[BoxTypes.BoxRarity.LEGENDARY] = 100
}

-- Base cost for instant opening (before pro-rata calculation)
BoxTypes.InstantOpenBaseCost = {
	-- Original costs (commented for testing):
	-- [BoxTypes.BoxRarity.UNCOMMON] = 4,
	-- [BoxTypes.BoxRarity.RARE] = 11,
	-- [BoxTypes.BoxRarity.EPIC] = 27,
	-- [BoxTypes.BoxRarity.LEGENDARY] = 50
	
	-- Testing: Set to 0 for free SpeedUp
	[BoxTypes.BoxRarity.UNCOMMON] = 0,
	[BoxTypes.BoxRarity.RARE] = 0,
	[BoxTypes.BoxRarity.EPIC] = 0,
	[BoxTypes.BoxRarity.LEGENDARY] = 0
}

-- Maximum number of lootbox slots per profile
BoxTypes.MAX_SLOTS = 4

-- Helper function to compute instant open cost with pro-rata rule
function BoxTypes.ComputeInstantOpenCost(rarity, remainingSeconds, totalSeconds)
	local baseCost = BoxTypes.InstantOpenBaseCost[rarity]
	if not baseCost then
		error("Invalid rarity: " .. tostring(rarity))
	end
	
	if remainingSeconds <= 0 then
		return 0 -- Minimum cost (testing: was 1)
	end
	
	if remainingSeconds >= totalSeconds then
		return baseCost -- Full cost
	end
	
	-- Pro-rata calculation: ceil(baseCost * (remaining / total))
	local ratio = remainingSeconds / totalSeconds
	local cost = math.ceil(baseCost * ratio)
	return math.max(0, cost) -- Ensure minimum cost of 0 (testing: was 1)
end

-- Helper function to get duration for a rarity
function BoxTypes.GetDuration(rarity)
	return BoxTypes.DurationSeconds[rarity] or 0
end

-- Helper function to get store cost for a rarity
function BoxTypes.GetStoreCost(rarity)
	return BoxTypes.StoreHardCost[rarity] or 0
end

-- Helper function to get base instant cost for a rarity
function BoxTypes.GetInstantBaseCost(rarity)
	return BoxTypes.InstantOpenBaseCost[rarity] or 0
end

-- Helper function to validate rarity
function BoxTypes.IsValidRarity(rarity)
	return rarity == BoxTypes.BoxRarity.UNCOMMON or
		   rarity == BoxTypes.BoxRarity.RARE or
		   rarity == BoxTypes.BoxRarity.EPIC or
		   rarity == BoxTypes.BoxRarity.LEGENDARY
end

-- Helper function to validate state
function BoxTypes.IsValidState(state)
	return state == BoxTypes.BoxState.IDLE or
		   state == BoxTypes.BoxState.UNLOCKING or
		   state == BoxTypes.BoxState.READY or
		   state == BoxTypes.BoxState.CONSUMED
end

return BoxTypes
