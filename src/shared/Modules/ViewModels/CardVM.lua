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
function CardVM.build(cardId, collectionEntry, profileState)
	if not cardId then
		error("CardVM.build: cardId is required")
	end
	
	-- Get card metadata from catalog
	local card = CardCatalog.GetCard(cardId)
	if not card then
		error("CardVM.build: Invalid card ID: " .. tostring(cardId))
	end
	
	-- Determine ownership and level/count
	local owned = collectionEntry ~= nil
	local level = 1
	local count = 0
	if owned then
		level = collectionEntry.level or 1
		count = collectionEntry.count or 0
	end
	
	-- Build base view model
	local vm = {
		id = cardId,
		name = card.name,
		rarity = card.rarity,
		class = card.class,
		slotNumber = card.slotNumber,
		description = card.description,
		-- Additional metadata
		baseStats = card.baseStats,
		levelIncrements = card.levelIncrements,
		-- Ownership flag
		owned = owned,
		maxLevel = 10
	}
	
	-- Add ownership-specific data only if owned
	if owned then
		vm.level = level
		vm.count = count
		
		-- Compute stats for this level
		local stats = CardStats.ComputeStats(cardId, level)
		if stats then
			vm.stats = {
				atk = stats.atk,
				hp = stats.hp,
				defence = stats.defence
			}
			vm.power = CardStats.ComputePower(stats)
		end
		
		-- Compute upgrade information if profile state is provided
		local upgradeInfo = {}
		if profileState then
			-- Use selectors to compute upgradeability
			local selectors = require(game:GetService("ReplicatedStorage").Modules.ViewModels.selectors)
			if selectors and selectors.selectCanLevelUp then
				local canLevelUp = selectors.selectCanLevelUp(profileState, cardId)
				upgradeInfo = {
					canLevelUp = canLevelUp.can,
					nextLevel = canLevelUp.nextLevel,
					requiredCount = canLevelUp.requiredCount,
					softAmount = canLevelUp.softAmount,
					shortfallCount = canLevelUp.shortfallCount,
					shortfallSoft = canLevelUp.shortfallSoft,
					reason = canLevelUp.reason
				}
			else
				-- Fallback to simple check
				upgradeInfo = {
					canLevelUp = level < 7 and count >= 10,
					nextLevel = level < 7 and (level + 1) or nil,
					reason = level >= 7 and "LEVEL_MAXED" or (count < 10 and "INSUFFICIENT_COPIES" or nil)
				}
			end
		else
			-- No profile state, use simple check
			upgradeInfo = {
				canLevelUp = level < 7 and count >= 10,
				nextLevel = level < 7 and (level + 1) or nil,
				reason = level >= 7 and "LEVEL_MAXED" or (count < 10 and "INSUFFICIENT_COPIES" or nil)
			}
		end
		
		-- Add upgrade information
		vm.canLevelUp = upgradeInfo.canLevelUp
		vm.nextLevel = upgradeInfo.nextLevel
		vm.requiredCount = upgradeInfo.requiredCount
		vm.softAmount = upgradeInfo.softAmount
		vm.shortfallCount = upgradeInfo.shortfallCount
		vm.shortfallSoft = upgradeInfo.shortfallSoft
		vm.upgradeReason = upgradeInfo.reason
	else
		-- For unowned cards, set upgrade fields to indicate not upgradeable
		vm.canLevelUp = false
		vm.upgradeReason = "CARD_NOT_OWNED"
	end
	
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
	
	-- Get card rarity from catalog
	local card = CardCatalog.GetCard(cardId)
	if not card then
		return nil
	end
	
	return CardLevels.GetLevelCost(nextLevel, card.rarity)
end

-- Check if card can be leveled up
function CardVM.canLevelUp(cardId, currentLevel, currentCount, softCurrency)
	if not cardId or not currentLevel or not currentCount or not softCurrency then
		return false, "Missing required parameters"
	end
	
	-- Import CardLevels for validation
	local CardLevels = Utilities.CardLevels
	
	-- Get card rarity from catalog
	local card = CardCatalog.GetCard(cardId)
	if not card then
		return false, "Card not found in catalog"
	end
	
	return CardLevels.CanLevelUp(cardId, currentLevel, currentCount, softCurrency, card.rarity)
end

-- Build list of upgradeable cards from profile state
function CardVM.buildUpgradeableList(profileState)
	if not profileState or not profileState.profile or not profileState.profile.collection then
		return {}
	end
	
	-- Use selectors to get upgradeable cards
	local selectors = require(game:GetService("ReplicatedStorage").Modules.ViewModels.selectors)
	if selectors and selectors.selectUpgradeableCards then
		local upgradeableData = selectors.selectUpgradeableCards(profileState)
		local vms = {}
		
		for _, data in ipairs(upgradeableData) do
			local collectionEntry = profileState.profile.collection[data.cardId]
			local vm = CardVM.build(data.cardId, collectionEntry, profileState)
			table.insert(vms, vm)
		end
		
		return vms
	else
		-- Fallback: build all cards and filter
		local allVms = CardVM.buildCollection(profileState.profile.collection)
		local upgradeable = {}
		
		for _, vm in ipairs(allVms) do
			if vm.canLevelUp then
				table.insert(upgradeable, vm)
			end
		end
		
		return upgradeable
	end
end

-- Build VMs from unified collection data (for Collection screen)
function CardVM.buildFromUnifiedCollection(unifiedCollection, profileState)
	local vms = {}
	
	for _, unifiedCard in ipairs(unifiedCollection) do
		local collectionEntry = nil
		if unifiedCard.owned then
			collectionEntry = {
				level = unifiedCard.level,
				count = unifiedCard.count
			}
		end
		
		local vm = CardVM.build(unifiedCard.cardId, collectionEntry, profileState)
		table.insert(vms, vm)
	end
	
	return vms
end

return CardVM
