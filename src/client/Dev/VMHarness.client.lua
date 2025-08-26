--[[
	VMHarness - View Model Dev Harness
	
	Console-only dev harness to test and demonstrate the client integration layer.
	Easy to delete later when UI is implemented.
]]

local VMHarness = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Client modules
local NetworkClient = require(script.Parent.Parent.Controllers.NetworkClient)
local ClientState = require(script.Parent.Parent.State.ClientState)
local selectors = require(script.Parent.Parent.State.selectors)

local Utilities = require(script.Parent.Parent.Utilities)
local Types = Utilities.Types
local TimeUtils = Utilities.TimeUtils

-- Use card data from Utilities
local CLIENT_CARD_DATA = Utilities.CardCatalog.GetAllCards()

-- Client-side simplified ViewModels
local ClientDeckVM = {}

function ClientDeckVM.build(deckIds, collection)
	if not deckIds or #deckIds ~= 6 then
		return nil
	end
	
	local slots = {}
	for i, cardId in ipairs(deckIds) do
		local card = CLIENT_CARD_DATA[cardId]
		if card then
			-- Simple grid layout: 3x2 grid
			local row = i <= 3 and 1 or 2
			local col = ((i - 1) % 3) + 1
			
			table.insert(slots, {
				slot = i,
				row = row,
				col = col,
				card = {
					id = cardId,
					level = collection and collection[cardId] and collection[cardId].level or 1,
					power = 100 + (card.rarity == "Rare" and 50 or card.rarity == "Epic" and 150 or card.rarity == "Legendary" and 300 or 0)
				}
			})
		end
	end
	
	return {
		slots = slots,
		cardIds = deckIds,
		squadPower = 0 -- Will be computed by caller
	}
end

function ClientDeckVM.getComposition(deckVM)
	if not deckVM or not deckVM.slots then
		return { classes = {}, rarities = {} }
	end
	
	local classes = { DPS = 0, Support = 0, Tank = 0 }
	local rarities = { Common = 0, Rare = 0, Epic = 0, Legendary = 0 }
	
	for _, slot in ipairs(deckVM.slots) do
		local card = CLIENT_CARD_DATA[slot.card.id]
		if card then
			classes[card.class] = (classes[card.class] or 0) + 1
			rarities[card.rarity] = (rarities[card.rarity] or 0) + 1
		end
	end
	
	return { classes = classes, rarities = rarities }
end

function ClientDeckVM.getAverageLevel(deckVM)
	if not deckVM or not deckVM.slots then
		return 1
	end
	
	local totalLevel = 0
	local count = 0
	
	for _, slot in ipairs(deckVM.slots) do
		totalLevel = totalLevel + (slot.card.level or 1)
		count = count + 1
	end
	
	return count > 0 and math.floor(totalLevel / count) or 1
end

local ClientProfileVM = {}

function ClientProfileVM.buildFromState(state)
	if not state.profile then
		return nil
	end
	
	local profile = state.profile
	
	-- Build deck VM
	local deckVM = ClientDeckVM.build(profile.deck, profile.collection)
	
	-- Compute squad power
	local squadPower = 0
	if profile.deck then
		for _, cardId in ipairs(profile.deck) do
			local card = CLIENT_CARD_DATA[cardId]
			if card then
				local basePower = 100
				local rarityBonus = {
					["Common"] = 0,
					["Rare"] = 50,
					["Epic"] = 150,
					["Legendary"] = 300
				}
				squadPower = squadPower + basePower + (rarityBonus[card.rarity] or 0)
			end
		end
	end
	
	-- Update deck VM squad power
	if deckVM then
		deckVM.squadPower = squadPower
	end
	
	-- Build collection VM
	local collectionVM = {
		cardCount = 0,
		uniqueCards = 0,
		highestLevel = 1
	}
	
	if profile.collection then
		for cardId, entry in pairs(profile.collection) do
			collectionVM.cardCount = collectionVM.cardCount + (entry.count or 0)
			collectionVM.uniqueCards = collectionVM.uniqueCards + 1
			collectionVM.highestLevel = math.max(collectionVM.highestLevel, entry.level or 1)
		end
	end
	
	return {
		deckVM = deckVM,
		collectionVM = collectionVM,
		squadPower = squadPower,
		collectionSize = collectionVM.uniqueCards,
		loginInfo = {
			loginStreak = profile.loginStreak or 0
		},
		currencies = profile.currencies or { soft = 0, hard = 0 },
		lootboxCount = profile.lootboxes and #profile.lootboxes or 0,
		unlockingLootboxes = 0,
		readyLootboxes = 0,
		lootboxes = profile.lootboxes or {}
	}
end

function ClientProfileVM.getCollectionSorted(profileVM, sortBy)
	if not profileVM or not profileVM.collectionVM then
		return {}
	end
	
	-- Simplified sorting - just return first few cards
	local sorted = {}
	local count = 0
	for cardId, _ in pairs(CLIENT_CARD_DATA) do
		if count < 5 then
			table.insert(sorted, { cardId = cardId, name = cardId })
			count = count + 1
		end
	end
	
	return sorted
end

function ClientProfileVM.getStats(profileVM)
	return {
		totalCards = profileVM and profileVM.collectionSize or 0,
		squadPower = profileVM and profileVM.squadPower or 0,
		loginStreak = profileVM and profileVM.loginInfo and profileVM.loginInfo.loginStreak or 0
	}
end

-- State
local isInitialized = false
local profileVM = nil

-- Utility functions
local function log(message, ...)
	print(string.format("[VMHarness] %s", string.format(message, ...)))
end

local function printSeparator()
	print("=" .. string.rep("=", 60))
end

-- Initialize the harness
function VMHarness.init()
	if isInitialized then
		log("Already initialized")
		return
	end
	
	log("Initializing VMHarness...")
	
	-- Initialize ClientState with NetworkClient
	ClientState.init(NetworkClient)
	
	-- Subscribe to state changes
	ClientState.subscribe(function(state)
		if state.profile then
			profileVM = ClientProfileVM.buildFromState(state)
			log("Profile VM updated: squadPower=%d, collectionSize=%d", 
				profileVM.squadPower, profileVM.collectionSize)
		end
	end)
	
	-- Request initial profile
	NetworkClient.requestProfile()
	
	isInitialized = true
	log("VMHarness initialized successfully")
end

-- Print profile summary
function VMHarness.PrintProfile()
	if not isInitialized then
		log("VMHarness not initialized. Call VMHarness.init() first.")
		return
	end
	
	if not profileVM then
		log("No profile available yet. Waiting for server response...")
		return
	end
	
	printSeparator()
	log("PROFILE SUMMARY")
	printSeparator()
	
	-- Basic info
	log("Squad Power: %d", profileVM.squadPower)
	log("Collection Size: %d cards", profileVM.collectionSize)
	log("Login Streak: %d days", profileVM.loginInfo.loginStreak)
	log("Soft Currency: %d", profileVM.currencies.soft or 0)
	log("Hard Currency: %d", profileVM.currencies.hard or 0)
	log("Lootboxes: %d total (%d unlocking, %d ready)", 
		profileVM.lootboxCount, profileVM.unlockingLootboxes, profileVM.readyLootboxes)
	
	-- Deck grid
	if profileVM.deckVM then
		printSeparator()
		log("DECK GRID (slot,row,col,id,level,power)")
		printSeparator()
		
		for _, slot in ipairs(profileVM.deckVM.slots) do
			log("Slot %d: row=%d, col=%d, %s (L%d, P%d)", 
				slot.slot, slot.row, slot.col, slot.card.id, slot.card.level, slot.card.power)
		end
		
		-- Deck composition
		local composition = ClientDeckVM.getComposition(profileVM.deckVM)
		log("Deck Composition:")
		log("  Classes: %s", table.concat({composition.classes.DPS or 0, composition.classes.Support or 0, composition.classes.Tank or 0}, "/"))
		log("  Rarities: %s", table.concat({composition.rarities.Common or 0, composition.rarities.Rare or 0, composition.rarities.Epic or 0, composition.rarities.Legendary or 0}, "/"))
	end
	
	-- Collection preview
	if profileVM.collectionVM then
		printSeparator()
		log("COLLECTION PREVIEW (first 5 cards)")
		printSeparator()
		
		local sortedCollection = ClientProfileVM.getCollectionSorted(profileVM, "power")
		for i = 1, math.min(5, #sortedCollection) do
			local card = sortedCollection[i]
			log("%d. %s (L%d, P%d, %s %s)", 
				i, card.id, card.level, card.power, card.rarity, card.class)
		end
	end
	
	-- Lootboxes
	if profileVM.lootboxes and #profileVM.lootboxes > 0 then
		printSeparator()
		log("LOOTBOXES")
		printSeparator()
		
		for i, lootbox in ipairs(profileVM.lootboxes) do
			local status = lootbox.entry.state
			local remaining = ""
			
			if status == Types.LootboxState.Unlocking and lootbox.remaining then
				remaining = string.format(" (%s remaining)", TimeUtils.formatDuration(lootbox.remaining))
			end
			
			log("%d. %s %s%s", i, lootbox.entry.rarity, status, remaining)
		end
	end
	
	printSeparator()
end

-- Set random deck
function VMHarness.SetDeckRandom()
	if not isInitialized then
		log("VMHarness not initialized. Call VMHarness.init() first.")
		return
	end
	
	-- Get all available card IDs from catalog
	local allCardIds = {}
	for cardId, _ in pairs(CardCatalog.GetAllCards()) do
		table.insert(allCardIds, cardId)
	end
	
	-- Pick 6 unique random cards
	local selectedCards = {}
	local usedIndices = {}
	
	while #selectedCards < 6 and #selectedCards < #allCardIds do
		local randomIndex = math.random(1, #allCardIds)
		
		-- Avoid duplicates
		if not usedIndices[randomIndex] then
			usedIndices[randomIndex] = true
			table.insert(selectedCards, allCardIds[randomIndex])
		end
	end
	
	if #selectedCards < 6 then
		log("Not enough unique cards available")
		return
	end
	
	log("Setting random deck: %s", table.concat(selectedCards, ", "))
	
	-- Set saving state
	ClientState.setSavingDeck(true)
	
	-- Request deck update
	local success, error = NetworkClient.requestSetDeck(selectedCards)
	
	if not success then
		log("Failed to request deck update: %s", error)
		ClientState.setSavingDeck(false)
		return
	end
	
	log("Deck update requested successfully")
	
	-- The profile will be updated via the normal flow
	-- and the VM will be rebuilt automatically
end

-- Print collection sorted by various criteria
function VMHarness.PrintCollection(sortBy)
	if not isInitialized or not profileVM then
		log("No profile available")
		return
	end
	
	sortBy = sortBy or "power"
	
	printSeparator()
	log("COLLECTION SORTED BY %s", string.upper(sortBy))
	printSeparator()
	
			local sortedCollection = ClientProfileVM.getCollectionSorted(profileVM, sortBy)
	
	for i, card in ipairs(sortedCollection) do
		log("%d. %s (L%d, P%d, %s %s, Count: %d)", 
			i, card.id, card.level, card.power, card.rarity, card.class, card.count)
	end
	
	printSeparator()
end

-- Print deck analysis
function VMHarness.PrintDeckAnalysis()
	if not isInitialized or not profileVM or not profileVM.deckVM then
		log("No deck available")
		return
	end
	
	printSeparator()
	log("DECK ANALYSIS")
	printSeparator()
	
	local deck = profileVM.deckVM
			local composition = ClientDeckVM.getComposition(deck)
	local averageLevel = ClientDeckVM.getAverageLevel(deck)
	
	log("Squad Power: %d", deck.squadPower)
	log("Average Level: %.1f", averageLevel)
	log("Class Distribution:")
	log("  DPS: %d", composition.classes.DPS or 0)
	log("  Support: %d", composition.classes.Support or 0)
	log("  Tank: %d", composition.classes.Tank or 0)
	log("Rarity Distribution:")
	log("  Common: %d", composition.rarities.Common or 0)
	log("  Rare: %d", composition.rarities.Rare or 0)
	log("  Epic: %d", composition.rarities.Epic or 0)
	log("  Legendary: %d", composition.rarities.Legendary or 0)
	
	printSeparator()
end

-- Print profile statistics
function VMHarness.PrintStats()
	if not isInitialized or not profileVM then
		log("No profile available")
		return
	end
	
	printSeparator()
	log("PROFILE STATISTICS")
	printSeparator()
	
	local stats = ClientProfileVM.getStats(profileVM)
	
	log("Collection Stats:")
	log("  Total Cards: %d", stats.totalCards)
	log("  Average Level: %.1f", stats.averageLevel)
	log("  Total Power: %d", stats.totalPower)
	
	if stats.classCounts then
		log("  Class Distribution:")
		log("    DPS: %d", stats.classCounts.DPS or 0)
		log("    Support: %d", stats.classCounts.Support or 0)
		log("    Tank: %d", stats.classCounts.Tank or 0)
	end
	
	if stats.rarityCounts then
		log("  Rarity Distribution:")
		log("    Common: %d", stats.rarityCounts.Common or 0)
		log("    Rare: %d", stats.rarityCounts.Rare or 0)
		log("    Epic: %d", stats.rarityCounts.Epic or 0)
		log("    Legendary: %d", stats.rarityCounts.Legendary or 0)
	end
	
	printSeparator()
end

-- Auto-initialize when script runs (only if dev panel is not shown)
local Config = require(script.Parent.Parent.Config)
if not Config.SHOW_DEV_PANEL then
	VMHarness.init()
end

return VMHarness
