--[[
	DeckVM - Deck View Model
	
	Builds deck view models with grid layout and squad power
	for UI consumption. Pure functions with no side effects.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utilities = require(ReplicatedStorage.Modules.Utilities)
local Types = Utilities.Types
local BoardLayout = Utilities.BoardLayout
local CardVM = require(script.Parent.CardVM)

local DeckVM = {}

-- Build a deck view model
function DeckVM.build(deckIds, collection)
	if not deckIds or #deckIds > 6 then
		error("DeckVM.build: deckIds must have between 0 and 6 cards")
	end
	
	collection = collection or {}
	
	-- Sort deck by slotNumber to ensure proper slot assignment
	local sortedDeck = {}
	for _, cardId in ipairs(deckIds) do
		table.insert(sortedDeck, cardId)
	end
	
	-- Sort by slotNumber (ascending)
	table.sort(sortedDeck, function(a, b)
		local cardA = Utilities.CardCatalog.GetCard(a)
		local cardB = Utilities.CardCatalog.GetCard(b)
		if not cardA or not cardB then return false end
		return cardA.slotNumber < cardB.slotNumber
	end)
	
	-- Build grid layout
	local grid = BoardLayout.gridForDeck(sortedDeck)
	
	-- Build slot view models
	local slots = {}
	local totalSquadPower = 0
	
	for i, gridEntry in ipairs(grid) do
		local cardId = gridEntry.cardId
		local collectionEntry = collection[cardId]
		local cardVM = CardVM.build(cardId, collectionEntry)
		
		local slotVM = {
			slot = gridEntry.slot,
			row = gridEntry.row,
			col = gridEntry.col,
			card = cardVM
		}
		
		table.insert(slots, slotVM)
		totalSquadPower = totalSquadPower + cardVM.power
	end
	
	-- Build deck view model
	local vm = {
		slots = slots,
		squadPower = totalSquadPower,
		cardIds = sortedDeck,
		-- Additional computed properties
		slotCount = #slots,
		isValid = #slots == 6,
		-- Grid properties
		grid = grid
	}
	
	return vm
end

-- Build deck from profile
function DeckVM.buildFromProfile(profile)
	if not profile or not profile.deck then
		return nil
	end
	
	return DeckVM.build(profile.deck, profile.collection)
end

-- Get slot by index (1-6)
function DeckVM.getSlot(vm, slotIndex)
	if not vm or not vm.slots then
		return nil
	end
	
	for _, slot in ipairs(vm.slots) do
		if slot.slot == slotIndex then
			return slot
		end
	end
	
	return nil
end

-- Get card by slot index
function DeckVM.getCard(vm, slotIndex)
	local slot = DeckVM.getSlot(vm, slotIndex)
	return slot and slot.card or nil
end

-- Get cards by class
function DeckVM.getCardsByClass(vm, class)
	if not vm or not vm.slots then
		return {}
	end
	
	local cards = {}
	for _, slot in ipairs(vm.slots) do
		if slot.card.class == class then
			table.insert(cards, slot.card)
		end
	end
	
	return cards
end

-- Get cards by rarity
function DeckVM.getCardsByRarity(vm, rarity)
	if not vm or not vm.slots then
		return {}
	end
	
	local cards = {}
	for _, slot in ipairs(vm.slots) do
		if slot.card.rarity == rarity then
			table.insert(cards, slot.card)
		end
	end
	
	return cards
end

-- Get average card level
function DeckVM.getAverageLevel(vm)
	if not vm or not vm.slots or #vm.slots == 0 then
		return 0
	end
	
	local totalLevel = 0
	for _, slot in ipairs(vm.slots) do
		totalLevel = totalLevel + slot.card.level
	end
	
	return totalLevel / #vm.slots
end

-- Get deck composition summary
function DeckVM.getComposition(vm)
	if not vm or not vm.slots then
		return { classes = {}, rarities = {} }
	end
	
	local classes = {}
	local rarities = {}
	
	for _, slot in ipairs(vm.slots) do
		local class = slot.card.class
		local rarity = slot.card.rarity
		
		classes[class] = (classes[class] or 0) + 1
		rarities[rarity] = (rarities[rarity] or 0) + 1
	end
	
	return {
		classes = classes,
		rarities = rarities
	}
end

-- Validate deck (basic validation)
function DeckVM.validate(vm)
	if not vm then
		return false, "No deck view model"
	end
	
	if not vm.slots or #vm.slots ~= 6 then
		return false, "Invalid slot count"
	end
	
	-- Check for duplicate cards
	local seenCards = {}
	for _, slot in ipairs(vm.slots) do
		if seenCards[slot.card.id] then
			return false, "Duplicate card: " .. slot.card.id
		end
		seenCards[slot.card.id] = true
	end
	
	return true
end

return DeckVM
