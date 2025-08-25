--[[
	ProfileVM - Profile View Model
	
	Builds profile view models with deck, collection, lootboxes,
	and other profile data for UI consumption. Pure functions with no side effects.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utilities = require(ReplicatedStorage.Modules.Utilities)
local Types = Utilities.Types
local TimeUtils = Utilities.TimeUtils
local CardVM = require(script.Parent.CardVM)
local DeckVM = require(script.Parent.DeckVM)

local ProfileVM = {}

-- Build a profile view model
function ProfileVM.build(profile, serverNow)
	if not profile then
		error("ProfileVM.build: profile is required")
	end
	
	serverNow = serverNow or os.time()
	
	-- Build deck view model
	local deckVM = DeckVM.buildFromProfile(profile)
	
	-- Build collection view models
	local collectionVM = CardVM.buildCollection(profile.collection or {})
	
	-- Build lootbox view models with remaining time
	local lootboxes = {}
	for _, lootbox in ipairs(profile.lootboxes or {}) do
		local lootboxVM = {
			entry = lootbox,
			remaining = nil
		}
		
		-- Calculate remaining time for unlocking lootboxes
		if lootbox.state == Types.LootboxState.Unlocking and lootbox.endsAt then
			lootboxVM.remaining = math.max(0, lootbox.endsAt - serverNow)
		end
		
		table.insert(lootboxes, lootboxVM)
	end
	
	-- Build profile view model
	local vm = {
		deckVM = deckVM,
		collectionVM = collectionVM,
		lootboxes = lootboxes,
		currencies = profile.currencies or { soft = 0, hard = 0 },
		loginInfo = {
			lastLoginAt = profile.lastLoginAt or 0,
			loginStreak = profile.loginStreak or 0
		},
		squadPower = profile.squadPower or 0,
		-- Additional profile data
		playerId = profile.playerId or "",
		createdAt = profile.createdAt or 0,
		tutorialStep = profile.tutorialStep or 0,
		favoriteLastSeen = profile.favoriteLastSeen or 0,
		version = profile.version or 0,
		-- Computed properties
		hasProfile = true,
		collectionSize = #collectionVM,
		lootboxCount = #lootboxes,
		unlockingLootboxes = 0,
		readyLootboxes = 0
	}
	
	-- Count lootbox states
	for _, lootbox in ipairs(lootboxes) do
		if lootbox.entry.state == Types.LootboxState.Unlocking then
			vm.unlockingLootboxes = vm.unlockingLootboxes + 1
		elseif lootbox.entry.state == Types.LootboxState.Ready then
			vm.readyLootboxes = vm.readyLootboxes + 1
		end
	end
	
	return vm
end

-- Build profile from ClientState
function ProfileVM.buildFromState(state)
	if not state or not state.profile then
		return nil
	end
	
	return ProfileVM.build(state.profile, state.serverNow)
end

-- Get collection sorted by various criteria
function ProfileVM.getCollectionSorted(vm, sortBy)
	if not vm or not vm.collectionVM then
		return {}
	end
	
	local collection = {}
	for _, card in ipairs(vm.collectionVM) do
		table.insert(collection, card)
	end
	
	sortBy = sortBy or "name"
	
	if sortBy == "rarity" then
		table.sort(collection, function(a, b)
			local rarityOrder = {
				[Types.Rarity.Common] = 1,
				[Types.Rarity.Rare] = 2,
				[Types.Rarity.Epic] = 3,
				[Types.Rarity.Legendary] = 4
			}
			
			local rarityA = rarityOrder[a.rarity] or 0
			local rarityB = rarityOrder[b.rarity] or 0
			
			if rarityA ~= rarityB then
				return rarityA > rarityB -- Higher rarity first
			end
			
			return a.id < b.id -- Then by name
		end)
	elseif sortBy == "level" then
		table.sort(collection, function(a, b)
			if a.level ~= b.level then
				return a.level > b.level -- Higher level first
			end
			return a.id < b.id -- Then by name
		end)
	elseif sortBy == "power" then
		table.sort(collection, function(a, b)
			if a.power ~= b.power then
				return a.power > b.power -- Higher power first
			end
			return a.id < b.id -- Then by name
		end)
	elseif sortBy == "slotNumber" then
		table.sort(collection, function(a, b)
			if a.slotNumber ~= b.slotNumber then
				return a.slotNumber < b.slotNumber
			end
			return a.id < b.id
		end)
	else -- "name" (default)
		table.sort(collection, function(a, b)
			return a.id < b.id
		end)
	end
	
	return collection
end

-- Get cards by class
function ProfileVM.getCardsByClass(vm, class)
	if not vm or not vm.collectionVM then
		return {}
	end
	
	local cards = {}
	for _, card in ipairs(vm.collectionVM) do
		if card.class == class then
			table.insert(cards, card)
		end
	end
	
	return cards
end

-- Get cards by rarity
function ProfileVM.getCardsByRarity(vm, rarity)
	if not vm or not vm.collectionVM then
		return {}
	end
	
	local cards = {}
	for _, card in ipairs(vm.collectionVM) do
		if card.rarity == rarity then
			table.insert(cards, card)
		end
	end
	
	return cards
end

-- Get cards that can be leveled up
function ProfileVM.getCardsCanLevelUp(vm)
	if not vm or not vm.collectionVM then
		return {}
	end
	
	local cards = {}
	for _, card in ipairs(vm.collectionVM) do
		if card.canLevelUp then
			table.insert(cards, card)
		end
	end
	
	return cards
end

-- Get lootboxes by state
function ProfileVM.getLootboxesByState(vm, state)
	if not vm or not vm.lootboxes then
		return {}
	end
	
	local lootboxes = {}
	for _, lootbox in ipairs(vm.lootboxes) do
		if lootbox.entry.state == state then
			table.insert(lootboxes, lootbox)
		end
	end
	
	return lootboxes
end

-- Get unlocking lootboxes with formatted remaining time
function ProfileVM.getUnlockingLootboxes(vm)
	local unlocking = ProfileVM.getLootboxesByState(vm, Types.LootboxState.Unlocking)
	
	for _, lootbox in ipairs(unlocking) do
		if lootbox.remaining then
			lootbox.formattedRemaining = TimeUtils.formatDuration(lootbox.remaining)
		end
	end
	
	return unlocking
end

-- Get ready lootboxes
function ProfileVM.getReadyLootboxes(vm)
	return ProfileVM.getLootboxesByState(vm, Types.LootboxState.Ready)
end

-- Get profile statistics
function ProfileVM.getStats(vm)
	if not vm then
		return {}
	end
	
	local stats = {
		totalCards = vm.collectionSize,
		squadPower = vm.squadPower,
		loginStreak = vm.loginInfo.loginStreak,
		softCurrency = vm.currencies.soft or 0,
		hardCurrency = vm.currencies.hard or 0,
		lootboxCount = vm.lootboxCount,
		unlockingLootboxes = vm.unlockingLootboxes,
		readyLootboxes = vm.readyLootboxes
	}
	
	-- Collection stats
	if vm.collectionVM then
		local totalLevel = 0
		local totalPower = 0
		local classCounts = {}
		local rarityCounts = {}
		
		for _, card in ipairs(vm.collectionVM) do
			totalLevel = totalLevel + card.level
			totalPower = totalPower + card.power
			
			classCounts[card.class] = (classCounts[card.class] or 0) + 1
			rarityCounts[card.rarity] = (rarityCounts[card.rarity] or 0) + 1
		end
		
		stats.averageLevel = vm.collectionSize > 0 and (totalLevel / vm.collectionSize) or 0
		stats.totalPower = totalPower
		stats.classCounts = classCounts
		stats.rarityCounts = rarityCounts
	end
	
	return stats
end

-- Check if profile has any errors or issues
function ProfileVM.validate(vm)
	if not vm then
		return false, "No profile view model"
	end
	
	if not vm.deckVM then
		return false, "No deck view model"
	end
	
	local deckValid, deckError = DeckVM.validate(vm.deckVM)
	if not deckValid then
		return false, "Invalid deck: " .. deckError
	end
	
	return true
end

return ProfileVM
