--[[
	Lootbox Roller
	
	Deterministic reward generation using SeededRNG.
	Generates consistent rewards based on box rarity and stored seed.
]]

local BoxRoller = {}

local BoxTypes = require(script.Parent.BoxTypes)
local BoxDropTables = require(script.Parent.BoxDropTables)
local CardCatalog = require(script.Parent.Parent.Cards.CardCatalog)
local SeededRNG = require(script.Parent.Parent.RNG.SeededRNG)

-- Roll rewards for a lootbox of given rarity using the provided RNG
function BoxRoller.RollRewards(rng, rarity)
	if not BoxTypes.IsValidRarity(rarity) then
		error("Invalid rarity: " .. tostring(rarity))
	end
	
	local dropTable = BoxDropTables.GetTable(rarity)
	local rewards = {
		softDelta = 0,
		hardDelta = 0,
		card = nil
	}
	
	-- Roll soft currency (uniform distribution within range)
	local softRoll = rng:NextFloat()
	local softRange = dropTable.softRange.max - dropTable.softRange.min
	rewards.softDelta = dropTable.softRange.min + math.floor(softRoll * (softRange + 1))
	
	-- Roll hard currency (if applicable)
	if dropTable.hardChance > 0 then
		local hardRoll = rng:NextFloat()
		if hardRoll < dropTable.hardChance then
			-- Use ranged amount if available, otherwise fall back to fixed amount
			if dropTable.hardRange then
				local hardRange = dropTable.hardRange.max - dropTable.hardRange.min
				rewards.hardDelta = dropTable.hardRange.min + math.floor(rng:NextFloat() * (hardRange + 1))
			else
				rewards.hardDelta = dropTable.hardAmount or 0
			end
		end
	end
	
	-- Roll character reward
	local characterRoll = rng:NextFloat()
	local cumulativeProbability = 0
	
	for i, reward in ipairs(dropTable.characterRewards) do
		cumulativeProbability = cumulativeProbability + reward.probability
		if characterRoll <= cumulativeProbability then
			-- Select a card of this rarity
			local cardId = BoxRoller.SelectCardByRarity(reward.rarity, rng)
			if cardId then
				-- Roll copies within range
				local copiesRange = reward.copiesRange.max - reward.copiesRange.min
				local copiesRoll = rng:NextFloat()
				local copies = reward.copiesRange.min + math.floor(copiesRoll * (copiesRange + 1))
				
				rewards.card = {
					cardId = cardId,
					copies = copies
				}
			end
			break
		end
	end
	
	-- Ensure we got a card (fallback safety)
	if not rewards.card then
		error("Failed to roll character reward for rarity: " .. rarity)
	end
	
	return rewards
end

-- Select a card uniformly from cards of the given rarity
-- If no cards of that rarity exist, fallback to next lower rarity with cards
function BoxRoller.SelectCardByRarity(targetRarity, rng)
	local rarityOrder = {
		BoxTypes.BoxRarity.ONEPIECE,
		BoxTypes.BoxRarity.LEGENDARY,
		BoxTypes.BoxRarity.EPIC,
		BoxTypes.BoxRarity.RARE,
		BoxTypes.BoxRarity.UNCOMMON
	}
	
	-- Find the target rarity in the order
	local startIndex = nil
	for i, rarity in ipairs(rarityOrder) do
		if rarity == targetRarity then
			startIndex = i
			break
		end
	end
	
	if not startIndex then
		error("Invalid target rarity: " .. tostring(targetRarity))
	end
	
	-- Try target rarity first, then fallback to lower rarities
	for i = startIndex, #rarityOrder do
		local rarity = rarityOrder[i]
		local cardsOfRarity = CardCatalog.GetCardsByRarity(rarity)
		
		if #cardsOfRarity > 0 then
			-- Select uniformly from available cards using the provided RNG
			local cardIndex = rng:NextInt(1, #cardsOfRarity)
			return cardsOfRarity[cardIndex].id
		end
	end
	
	-- If no cards exist at all (edge case), return a default
	local allCards = CardCatalog.GetAllCards()
	for cardId, _ in pairs(allCards) do
		return cardId -- Return first available card
	end
	
	error("No cards available in catalog")
end

-- Generate a unique box ID (for persistence)
function BoxRoller.GenerateBoxId()
	-- Simple timestamp-based ID (in production, use UUID or similar)
	return "box_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
end

-- Generate a seed for deterministic rolling
function BoxRoller.GenerateSeed()
	return math.random(1, 2147483647) -- 32-bit positive integer
end

return BoxRoller
