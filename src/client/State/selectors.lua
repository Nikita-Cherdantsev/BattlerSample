--[[
	Selectors - Pure functions for extracting and transforming state data
	
	Provides side-effect free functions to extract specific data
	from ClientState for UI consumption.
]]

local Utilities = require(script.Parent.Parent.Utilities)
local Types = Utilities.Types
local CardCatalog = Utilities.CardCatalog
local CardStats = Utilities.CardStats

local selectors = {}

-- Basic selectors

-- Get deck IDs from state
function selectors.selectDeckIds(state)
	if not state.profile or not state.profile.deck then
		return nil
	end
	return state.profile.deck
end

-- Get collection map from state
function selectors.selectCollectionMap(state)
	if not state.profile or not state.profile.collection then
		return {}
	end
	return state.profile.collection
end

-- Get currencies from state
function selectors.selectCurrencies(state)
	if not state.profile or not state.profile.currencies then
		return { soft = 0, hard = 0 }
	end
	return state.profile.currencies
end

-- Get lootboxes from state
function selectors.selectLootboxes(state)
	if not state.profile or not state.profile.lootboxes then
		return {}
	end
	return state.profile.lootboxes
end

-- Get server time from state
function selectors.selectServerNow(state)
	return state.serverNow
end

-- Collection as sorted list
function selectors.selectCollectionAsList(state, opts)
	opts = opts or {}
	local collection = selectors.selectCollectionMap(state)
	
	local list = {}
	for cardId, entry in pairs(collection) do
		table.insert(list, {
			cardId = cardId,
			count = entry.count,
			level = entry.level
		})
	end
	
	-- Sort based on options
	local sortBy = opts.sortBy or "name"
	
	if sortBy == "rarity" then
		table.sort(list, function(a, b)
			local cardA = CardCatalog.GetCard(a.cardId)
			local cardB = CardCatalog.GetCard(b.cardId)
			if not cardA or not cardB then return false end
			
			local rarityOrder = {
				[Types.Rarity.Common] = 1,
				[Types.Rarity.Rare] = 2,
				[Types.Rarity.Epic] = 3,
				[Types.Rarity.Legendary] = 4
			}
			
			local rarityA = rarityOrder[cardA.rarity] or 0
			local rarityB = rarityOrder[cardB.rarity] or 0
			
			if rarityA ~= rarityB then
				return rarityA > rarityB -- Higher rarity first
			end
			
			return a.cardId < b.cardId -- Then by name
		end)
	elseif sortBy == "level" then
		table.sort(list, function(a, b)
			if a.level ~= b.level then
				return a.level > b.level -- Higher level first
			end
			return a.cardId < b.cardId -- Then by name
		end)
	elseif sortBy == "slotNumber" then
		table.sort(list, function(a, b)
			local cardA = CardCatalog.GetCard(a.cardId)
			local cardB = CardCatalog.GetCard(b.cardId)
			if not cardA or not cardB then return false end
			
			if cardA.slotNumber ~= cardB.slotNumber then
				return cardA.slotNumber < cardB.slotNumber
			end
			return a.cardId < b.cardId
		end)
	else -- "name" (default)
		table.sort(list, function(a, b)
			return a.cardId < b.cardId
		end)
	end
	
	return list
end

-- Get squad power from state
function selectors.selectSquadPower(state)
	if not state.profile then
		return 0
	end
	return state.profile.squadPower or 0
end

-- Get login info from state
function selectors.selectLoginInfo(state)
	if not state.profile then
		return { lastLoginAt = 0, loginStreak = 0 }
	end
	return {
		lastLoginAt = state.profile.lastLoginAt or 0,
		loginStreak = state.profile.loginStreak or 0
	}
end

-- Get tutorial step from state
function selectors.selectTutorialStep(state)
	if not state.profile then
		return 0
	end
	return state.profile.tutorialStep or 0
end

-- Get favorite last seen from state
function selectors.selectFavoriteLastSeen(state)
	if not state.profile then
		return 0
	end
	return state.profile.favoriteLastSeen or 0
end

-- Get profile creation time from state
function selectors.selectCreatedAt(state)
	if not state.profile then
		return 0
	end
	return state.profile.createdAt or 0
end

-- Get player ID from state
function selectors.selectPlayerId(state)
	if not state.profile then
		return ""
	end
	return state.profile.playerId or ""
end

-- Get profile version from state
function selectors.selectProfileVersion(state)
	if not state.profile then
		return 0
	end
	return state.profile.version or 0
end

-- Level-up selectors

-- Get card entry from collection
function selectors.selectCardEntry(state, cardId)
	if not state.profile or not state.profile.collection then
		return nil
	end
	return state.profile.collection[cardId]
end

-- Check if a card can be leveled up
function selectors.selectCanLevelUp(state, cardId)
	if not state.profile or not state.profile.collection then
		return { can = false, reason = "NO_PROFILE" }
	end
	
	local entry = state.profile.collection[cardId]
	if not entry then
		return { can = false, reason = "CARD_NOT_OWNED" }
	end
	
	-- Check if already at max level
	if entry.level >= 7 then
		return { can = false, reason = "LEVEL_MAXED" }
	end
	
	-- Get next level cost
	local nextLevel = entry.level + 1
	local cost = CardStats.GetLevelCost and CardStats.GetLevelCost(nextLevel)
	if not cost then
		-- Fallback to hardcoded costs if CardStats not available
		local levelCosts = {
			[2] = { requiredCount = 10, softAmount = 12000 },
			[3] = { requiredCount = 20, softAmount = 50000 },
			[4] = { requiredCount = 40, softAmount = 200000 },
			[5] = { requiredCount = 80, softAmount = 500000 },
			[6] = { requiredCount = 160, softAmount = 800000 },
			[7] = { requiredCount = 320, softAmount = 1200000 }
		}
		cost = levelCosts[nextLevel]
	end
	
	if not cost then
		return { can = false, reason = "INVALID_LEVEL" }
	end
	
	-- Check resources
	local currencies = state.profile.currencies or { soft = 0 }
	local shortfallCount = math.max(0, cost.requiredCount - entry.count)
	local shortfallSoft = math.max(0, cost.softAmount - currencies.soft)
	
	if shortfallCount > 0 then
		return {
			can = false,
			reason = "INSUFFICIENT_COPIES",
			nextLevel = nextLevel,
			requiredCount = cost.requiredCount,
			softAmount = cost.softAmount,
			shortfallCount = shortfallCount,
			shortfallSoft = shortfallSoft
		}
	end
	
	if shortfallSoft > 0 then
		return {
			can = false,
			reason = "INSUFFICIENT_SOFT",
			nextLevel = nextLevel,
			requiredCount = cost.requiredCount,
			softAmount = cost.softAmount,
			shortfallCount = shortfallCount,
			shortfallSoft = shortfallSoft
		}
	end
	
	-- Can level up
	return {
		can = true,
		nextLevel = nextLevel,
		requiredCount = cost.requiredCount,
		softAmount = cost.softAmount,
		shortfallCount = 0,
		shortfallSoft = 0
	}
end

-- Get all upgradeable cards
function selectors.selectUpgradeableCards(state)
	if not state.profile or not state.profile.collection then
		return {}
	end
	
	local upgradeable = {}
	
	for cardId, entry in pairs(state.profile.collection) do
		local canLevelUp = selectors.selectCanLevelUp(state, cardId)
		if canLevelUp.can then
			table.insert(upgradeable, {
				cardId = cardId,
				nextLevel = canLevelUp.nextLevel,
				requiredCount = canLevelUp.requiredCount,
				softAmount = canLevelUp.softAmount
			})
		end
	end
	
	-- Sort by rarity then slot number for UI-friendly ordering
	table.sort(upgradeable, function(a, b)
		local cardA = CardCatalog.GetCard and CardCatalog.GetCard(a.cardId)
		local cardB = CardCatalog.GetCard and CardCatalog.GetCard(b.cardId)
		
		if cardA and cardB then
			-- Sort by rarity first (legendary > epic > rare > common)
			local rarityOrder = { legendary = 4, epic = 3, rare = 2, common = 1 }
			local rarityA = rarityOrder[cardA.rarity] or 0
			local rarityB = rarityOrder[cardB.rarity] or 0
			
			if rarityA ~= rarityB then
				return rarityA > rarityB
			end
			
			-- Then by slot number
			return (cardA.slotNumber or 999) < (cardB.slotNumber or 999)
		end
		
		return a.cardId < b.cardId
	end)
	
	return upgradeable
end

return selectors
