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

-- Shared modules
local Utilities = require(ReplicatedStorage.Modules.Utilities)
local Types = Utilities.Types
local CardCatalog = Utilities.CardCatalog
local TimeUtils = Utilities.TimeUtils
local DeckVM = require(ReplicatedStorage.Modules.ViewModels.DeckVM)
local ProfileVM = require(ReplicatedStorage.Modules.ViewModels.ProfileVM)

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
			profileVM = ProfileVM.buildFromState(state)
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
		local composition = DeckVM.getComposition(profileVM.deckVM)
		log("Deck Composition:")
		log("  Classes: %s", table.concat({composition.classes.DPS or 0, composition.classes.Support or 0, composition.classes.Tank or 0}, "/"))
		log("  Rarities: %s", table.concat({composition.rarities.Common or 0, composition.rarities.Rare or 0, composition.rarities.Epic or 0, composition.rarities.Legendary or 0}, "/"))
	end
	
	-- Collection preview
	if profileVM.collectionVM then
		printSeparator()
		log("COLLECTION PREVIEW (first 5 cards)")
		printSeparator()
		
		local sortedCollection = ProfileVM.getCollectionSorted(profileVM, "power")
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
	
	local sortedCollection = ProfileVM.getCollectionSorted(profileVM, sortBy)
	
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
	local composition = DeckVM.getComposition(deck)
	local averageLevel = DeckVM.getAverageLevel(deck)
	
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
	
	local stats = ProfileVM.getStats(profileVM)
	
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
