--[[
	CardVM - Card View Model
	
	Builds card view models with stats, power, and metadata
	for UI consumption. Pure functions with no side effects.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utilities = require(ReplicatedStorage.Modules.Utilities)
local Types = Utilities.Types
local CardCatalog = Utilities.CardCatalog
local CardStats = Utilities.CardStats

local CardVM = {}

-- Build a card view model
function CardVM.build(cardId, collectionEntry)
	if not cardId then
		error("CardVM.build: cardId is required")
	end
	
	-- Get card metadata from catalog
	local card = CardCatalog.GetCard(cardId)
	if not card then
		error("CardVM.build: Invalid card ID: " .. tostring(cardId))
	end
	
	-- Determine level (from collection or default to 1)
	local level = 1
	local count = 0
	if collectionEntry then
		level = collectionEntry.level or 1
		count = collectionEntry.count or 0
	end
	
	-- Compute stats for this level
	local stats = CardStats.ComputeStats(cardId, level)
	
	-- Compute power
	local power = CardStats.ComputePower(stats)
	
	-- Build view model
	local vm = {
		id = cardId,
		name = card.name,
		rarity = card.rarity,
		class = card.class,
		level = level,
		count = count,
		stats = {
			atk = stats.atk,
			hp = stats.hp,
			defence = stats.defence
		},
		power = power,
		slotNumber = card.slotNumber,
		description = card.description,
		-- Additional metadata
		baseStats = card.baseStats,
		levelIncrements = card.levelIncrements,
		-- Computed properties
		isOwned = count > 0,
		canLevelUp = level < 7 and count >= 10, -- Simplified level-up check
		maxLevel = 7
	}
	
	return vm
end

-- Build multiple card view models
function CardVM.buildMultiple(cardIds, collection)
	collection = collection or {}
	local vms = {}
	
	for _, cardId in ipairs(cardIds) do
		local collectionEntry = collection[cardId]
		local vm = CardVM.build(cardId, collectionEntry)
		table.insert(vms, vm)
	end
	
	return vms
end

-- Build all cards in collection
function CardVM.buildCollection(collection)
	collection = collection or {}
	local vms = {}
	
	for cardId, entry in pairs(collection) do
		local vm = CardVM.build(cardId, entry)
		table.insert(vms, vm)
	end
	
	return vms
end

-- Get card level cost information
function CardVM.getLevelCost(cardId, currentLevel)
	if not cardId or not currentLevel then
		return nil
	end
	
	-- Import CardLevels for cost calculation
	local CardLevels = Utilities.CardLevels
	local nextLevel = currentLevel + 1
	
	if nextLevel > CardLevels.MAX_LEVEL then
		return nil -- Already at max level
	end
	
	return CardLevels.GetLevelCost(nextLevel)
end

-- Check if card can be leveled up
function CardVM.canLevelUp(cardId, currentLevel, currentCount, softCurrency)
	if not cardId or not currentLevel or not currentCount or not softCurrency then
		return false, "Missing required parameters"
	end
	
	-- Import CardLevels for validation
	local CardLevels = Utilities.CardLevels
	return CardLevels.CanLevelUp(cardId, currentLevel, currentCount, softCurrency)
end

return CardVM
