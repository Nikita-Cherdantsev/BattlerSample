--[[
	Selectors - Pure functions for extracting and transforming state data
	
	Provides side-effect free functions to extract specific data
	from ClientState for UI consumption.
]]

local Utilities = require(script.Parent.Parent.Utilities)
local Types = Utilities.Types
local CardCatalog = Utilities.CardCatalog
local CardStats = Utilities.CardStats
local BoxTypes = Utilities.BoxTypes

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

-- Get pending lootbox from state
function selectors.selectPendingLootbox(state)
	if not state.profile then
		return nil
	end
	return state.profile.pendingLootbox
end

-- Get unlocking count (max 1)
function selectors.selectUnlockingCount(state)
	local lootboxes = selectors.selectLootboxes(state)
	local count = 0
	for _, lootbox in ipairs(lootboxes) do
		if lootbox.state == "Unlocking" then
			count = count + 1
		end
	end
	return count
end

-- Check if can start unlock (no other unlocking, slot is Idle)
function selectors.selectCanStartUnlock(state, slotIndex, now)
	local lootboxes = selectors.selectLootboxes(state)
	local unlockingCount = selectors.selectUnlockingCount(state)
	
	-- Can't start if another is unlocking
	if unlockingCount > 0 then
		return false
	end
	
	-- Check if slot exists and is idle
	local lootbox = lootboxes[slotIndex]
	if not lootbox or lootbox.state ~= "Idle" then
		return false
	end
	
	return true
end

-- Get remaining seconds for a slot
function selectors.selectRemainingSeconds(state, slotIndex, now)
	local lootboxes = selectors.selectLootboxes(state)
	local lootbox = lootboxes[slotIndex]
	
	if not lootbox or not lootbox.unlocksAt then
		return 0
	end
	
	local remaining = lootbox.unlocksAt - now
	return math.max(0, remaining)
end

-- Get instant open cost for a slot
function selectors.selectInstantOpenCost(state, slotIndex, now)
	local lootboxes = selectors.selectLootboxes(state)
	local lootbox = lootboxes[slotIndex]
	
	if not lootbox then
		return 0
	end
	
	local rarity = lootbox.rarity
	local totalDuration = BoxTypes.GetDuration(rarity)
	local remainingTime = 0
	
	if lootbox.state == "Idle" then
		remainingTime = totalDuration
	elseif lootbox.state == "Unlocking" and lootbox.unlocksAt then
		remainingTime = math.max(0, lootbox.unlocksAt - now)
	end
	
	return BoxTypes.ComputeInstantOpenCost(rarity, remainingTime, totalDuration)
end

-- Get lootbox summary (counts by rarity/state)
function selectors.selectLootSummary(state)
	local lootboxes = selectors.selectLootboxes(state)
	local summary = {
		total = #lootboxes,
		byRarity = {},
		byState = {},
		unlockingCount = 0
	}
	
	-- Initialize counters
	local rarities = {"uncommon", "rare", "epic", "legendary"}
	local states = {"Idle", "Unlocking", "Ready", "Consumed"}
	
	for _, rarity in ipairs(rarities) do
		summary.byRarity[rarity] = 0
	end
	
	for _, state in ipairs(states) do
		summary.byState[state] = 0
	end
	
	-- Count lootboxes
	for _, lootbox in ipairs(lootboxes) do
		summary.byRarity[lootbox.rarity] = (summary.byRarity[lootbox.rarity] or 0) + 1
		summary.byState[lootbox.state] = (summary.byState[lootbox.state] or 0) + 1
		
		if lootbox.state == "Unlocking" then
			summary.unlockingCount = summary.unlockingCount + 1
		end
	end
	
	return summary
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
	if entry.level >= 10 then
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

-- Collection data surface - unified catalog + ownership

-- Get unified collection (all catalog cards with ownership overlay)
function selectors.selectUnifiedCollection(state, opts)
	opts = opts or {}
	local collection = selectors.selectCollectionMap(state)
	
	-- Get all cards from catalog
	local allCards = CardCatalog.GetAllCards()
	if not allCards then
		return {}
	end
	
	local unified = {}
	
	-- Merge catalog with ownership data
	for cardId, cardData in pairs(allCards) do
		local collectionEntry = collection[cardId]
		local owned = collectionEntry ~= nil
		
		local unifiedCard = {
			cardId = cardId,
			name = cardData.name,
			rarity = cardData.rarity,
			class = cardData.class,
			slotNumber = cardData.slotNumber,
			description = cardData.description,
			owned = owned
		}
		
		-- Add ownership data if owned
		if owned then
			unifiedCard.level = collectionEntry.level
			unifiedCard.count = collectionEntry.count
			
			-- Compute stats and power for owned cards
			local stats = CardStats.ComputeStats(cardId, collectionEntry.level)
			if stats then
				unifiedCard.stats = {
					atk = stats.atk,
					hp = stats.hp,
					defence = stats.defence
				}
				unifiedCard.power = CardStats.ComputePower(stats)
			end
		end
		
		table.insert(unified, unifiedCard)
	end
	
	-- Apply sorting/grouping/filtering
	return selectors.applyCollectionFilters(unified, opts)
end

-- Apply sorting, grouping, and filtering to unified collection
function selectors.applyCollectionFilters(unified, opts)
	opts = opts or {}
	local filtered = {}
	
	-- Apply filters
	for _, card in ipairs(unified) do
		local include = true
		
		-- Owned only filter
		if opts.ownedOnly and not card.owned then
			include = false
		end
		
		-- Search term filter
		if include and opts.searchTerm then
			local searchLower = string.lower(opts.searchTerm)
			local nameMatch = string.find(string.lower(card.name), searchLower, 1, true)
			local idMatch = string.find(string.lower(card.cardId), searchLower, 1, true)
			if not nameMatch and not idMatch then
				include = false
			end
		end
		
		-- Rarity filter
		if include and opts.rarityIn and #opts.rarityIn > 0 then
			local rarityMatch = false
			for _, rarity in ipairs(opts.rarityIn) do
				if card.rarity == rarity then
					rarityMatch = true
					break
				end
			end
			if not rarityMatch then
				include = false
			end
		end
		
		-- Class filter
		if include and opts.classIn and #opts.classIn > 0 then
			local classMatch = false
			for _, class in ipairs(opts.classIn) do
				if card.class == class then
					classMatch = true
					break
				end
			end
			if not classMatch then
				include = false
			end
		end
		
		if include then
			table.insert(filtered, card)
		end
	end
	
	-- Apply sorting
	local sortBy = opts.sortBy or "slotNumber"
	table.sort(filtered, function(a, b)
		if sortBy == "rarity" then
			local rarityOrder = { legendary = 4, epic = 3, rare = 2, common = 1 }
			local rarityA = rarityOrder[a.rarity] or 0
			local rarityB = rarityOrder[b.rarity] or 0
			
			if rarityA ~= rarityB then
				return rarityA > rarityB -- Higher rarity first
			end
			-- Tie-breaker: slot number
			return a.slotNumber < b.slotNumber
			
		elseif sortBy == "class" then
			if a.class ~= b.class then
				return a.class < b.class
			end
			-- Tie-breaker: slot number
			return a.slotNumber < b.slotNumber
			
		elseif sortBy == "name" then
			if a.name ~= b.name then
				return a.name < b.name
			end
			-- Tie-breaker: slot number
			return a.slotNumber < b.slotNumber
			
		elseif sortBy == "power" then
			-- Only owned cards have power, unowned cards go to end
			if a.owned and not b.owned then
				return true
			elseif not a.owned and b.owned then
				return false
			elseif a.owned and b.owned then
				if a.power ~= b.power then
					return a.power > b.power -- Higher power first
				end
			end
			-- Tie-breaker: slot number
			return a.slotNumber < b.slotNumber
			
		else -- "slotNumber" (default)
			return a.slotNumber < b.slotNumber
		end
	end)
	
	-- Apply grouping if requested
	if opts.groupBy then
		return selectors.groupCollection(filtered, opts.groupBy)
	end
	
	return filtered
end

-- Group collection by specified field
function selectors.groupCollection(collection, groupBy)
	local groups = {}
	local groupMap = {}
	
	for _, card in ipairs(collection) do
		local groupKey = card[groupBy]
		if not groupMap[groupKey] then
			groupMap[groupKey] = {
				groupKey = groupKey,
				items = {}
			}
			table.insert(groups, groupMap[groupKey])
		end
		table.insert(groupMap[groupKey].items, card)
	end
	
	-- Sort groups
	if groupBy == "rarity" then
		table.sort(groups, function(a, b)
			local rarityOrder = { legendary = 4, epic = 3, rare = 2, common = 1 }
			return rarityOrder[a.groupKey] > rarityOrder[b.groupKey]
		end)
	elseif groupBy == "class" then
		table.sort(groups, function(a, b)
			return a.groupKey < b.groupKey
		end)
	end
	
	return groups
end

return selectors
