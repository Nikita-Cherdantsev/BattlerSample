--[[
	Selectors - Pure functions for extracting and transforming state data
	
	Provides side-effect free functions to extract specific data
	from ClientState for UI consumption.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utilities = require(ReplicatedStorage.Modules.Utilities)
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

return selectors
