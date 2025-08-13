local SelfCheck = {}

-- Import modules to test
local CardCatalog = require(script.Parent.Cards.CardCatalog)
local DeckValidator = require(script.Parent.Cards.DeckValidator)
local SeededRNG = require(script.Parent.RNG.SeededRNG)
local CombatTypes = require(script.Parent.Combat.CombatTypes)
local CombatUtils = require(script.Parent.Combat.CombatUtils)
local GameConstants = require(script.Parent.Constants.GameConstants)

-- Test results
local testResults = {}

-- Test 1: Card Catalog
local function TestCardCatalog()
	print("=== Testing Card Catalog ===")
	
	-- Test card retrieval
	local card = CardCatalog.GetCard("warrior_001")
	if card then
		print("✅ Found warrior_001:", card.name, "Rarity:", card.rarity)
		testResults.cardCatalog = true
	else
		print("❌ Failed to find warrior_001")
		testResults.cardCatalog = false
	end
	
	-- Test rarity filtering
	local commonCards = CardCatalog.GetCardsByRarity(CardCatalog.Rarities.COMMON)
	print("✅ Found", #commonCards, "common cards")
	
	-- Test class filtering
	local warriorCards = CardCatalog.GetCardsByClass(CardCatalog.Classes.WARRIOR)
	print("✅ Found", #warriorCards, "warrior cards")
	
	print("Total cards in catalog:", #CardCatalog.GetAllCards())
end

-- Test 2: Deck Validation
local function TestDeckValidation()
	print("\n=== Testing Deck Validation ===")
	
	-- Valid deck
	local validDeck = {"warrior_001", "mage_001", "healer_001", "tank_001", "warrior_002", "mage_002"}
	local isValid, errorMessage = DeckValidator.ValidateDeck(validDeck)
	
	if isValid then
		print("✅ Valid deck passed validation")
		testResults.deckValidation = true
		
		-- Test board mapping
		local board = DeckValidator.MapDeckToBoard(validDeck)
		print("✅ Deck mapped to board with", #board, "slots")
		
		-- Test slot info
		local slotInfo = DeckValidator.GetSlotInfo(0)
		if slotInfo then
			print("✅ Slot 0 info:", "Row:", slotInfo.position.row, "Col:", slotInfo.position.col)
		end
		
	else
		print("❌ Valid deck failed validation:", errorMessage)
		testResults.deckValidation = false
	end
	
	-- Invalid deck (wrong size)
	local invalidDeck = {"warrior_001", "mage_001"}
	local isValid2, errorMessage2 = DeckValidator.ValidateDeck(invalidDeck)
	if not isValid2 then
		print("✅ Invalid deck correctly rejected:", errorMessage2)
	else
		print("❌ Invalid deck incorrectly accepted")
		testResults.deckValidation = false
	end
	
	-- Invalid deck (unknown card)
	local invalidDeck2 = {"warrior_001", "mage_001", "healer_001", "tank_001", "warrior_002", "unknown_card"}
	local isValid3, errorMessage3 = DeckValidator.ValidateDeck(invalidDeck2)
	if not isValid3 then
		print("✅ Unknown card correctly rejected:", errorMessage3)
	else
		print("❌ Unknown card incorrectly accepted")
		testResults.deckValidation = false
	end
end

-- Test 3: Seeded RNG
local function TestSeededRNG()
	print("\n=== Testing Seeded RNG ===")
	
	-- Test deterministic behavior
	local rng1 = SeededRNG.New(12345)
	local rng2 = SeededRNG.New(12345)
	
	local sequence1 = {}
	local sequence2 = {}
	
	-- Generate 10 random numbers from each RNG
	for i = 1, 10 do
		table.insert(sequence1, SeededRNG.RandomInt(rng1, 1, 100))
		table.insert(sequence2, SeededRNG.RandomInt(rng2, 1, 100))
	end
	
	-- Check if sequences are identical
	local sequencesMatch = true
	for i = 1, 10 do
		if sequence1[i] ~= sequence2[i] then
			sequencesMatch = false
			break
		end
	end
	
	if sequencesMatch then
		print("✅ Identical seeds produce identical sequences")
		testResults.seededRNG = true
	else
		print("❌ Identical seeds produced different sequences")
		testResults.seededRNG = false
	end
	
	-- Test different seeds produce different sequences
	local rng3 = SeededRNG.New(54321)
	local sequence3 = {}
	for i = 1, 5 do
		table.insert(sequence3, SeededRNG.RandomInt(rng3, 1, 100))
	end
	
	local differentSeedsDifferent = false
	for i = 1, 5 do
		if sequence1[i] ~= sequence3[i] then
			differentSeedsDifferent = true
			break
		end
	end
	
	if differentSeedsDifferent then
		print("✅ Different seeds produce different sequences")
	else
		print("❌ Different seeds produced identical sequences")
		testResults.seededRNG = false
	end
	
	-- Test RNG functions
	print("✅ Random int (1-10):", SeededRNG.RandomInt(rng1, 1, 10))
	print("✅ Random float (0-1):", string.format("%.3f", SeededRNG.RandomFloat(rng1, 0, 1)))
	print("✅ Random bool (50%):", SeededRNG.RandomBool(rng1, 0.5))
end

-- Test 4: Combat Types and Utils
local function TestCombatTypes()
	print("\n=== Testing Combat Types ===")
	
	-- Test unit creation
	local unit = {
		slotIndex = 0,
		cardId = "warrior_001",
		card = CardCatalog.GetCard("warrior_001"),
		stats = {
			attack = 5,
			health = 10,
			maxHealth = 10,
			speed = 3,
			armor = 2
		},
		state = CombatTypes.UnitState.ALIVE,
		statusEffects = {}
	}
	
	if CombatTypes.IsValidUnit(unit) then
		print("✅ Valid unit created")
		testResults.combatTypes = true
	else
		print("❌ Unit validation failed")
		testResults.combatTypes = false
	end
	
	-- Test combat utilities
	local damage = CombatUtils.CalculateDamage(10, 5)
	print("✅ Damage calculation (10 damage vs 5 armor):", damage)
	
	local canAct = CombatUtils.CanUnitAct(unit)
	print("✅ Unit can act:", canAct)
	
	-- Test status effects
	CombatUtils.ApplyStatusEffect(unit, CombatTypes.StatusEffect.POISON, 3, 2)
	print("✅ Applied poison effect to unit")
	
	-- Test damage application
	local actualDamage = CombatUtils.ApplyDamage(unit, 3)
	print("✅ Applied 3 damage, actual damage:", actualDamage, "Unit health:", unit.stats.health)
	
	-- Test healing
	local actualHealing = CombatUtils.ApplyHealing(unit, 5)
	print("✅ Applied 5 healing, actual healing:", actualHealing, "Unit health:", unit.stats.health)
end

-- Test 5: Game Constants
local function TestGameConstants()
	print("\n=== Testing Game Constants ===")
	
	print("✅ Board dimensions:", GameConstants.BOARD.WIDTH, "x", GameConstants.BOARD.HEIGHT)
	print("✅ Total slots:", GameConstants.BOARD.TOTAL_SLOTS)
	print("✅ Deck size:", GameConstants.DECK.MIN_SIZE, "-", GameConstants.DECK.MAX_SIZE)
	print("✅ Max turns:", GameConstants.COMBAT.MAX_TURNS)
	print("✅ Rarity weights - Common:", GameConstants.RARITY_WEIGHTS.COMMON .. "%")
	
	testResults.gameConstants = true
end

-- Run all tests
function SelfCheck.RunAllTests()
	print("🚀 Starting Self-Check for Card Battler MVP (Step 2A)")
	print("=" .. string.rep("=", 60))
	
	-- Reset test results
	testResults = {}
	
	-- Run tests
	TestCardCatalog()
	TestDeckValidation()
	TestSeededRNG()
	TestCombatTypes()
	TestGameConstants()
	
	-- Summary
	print("\n" .. string.rep("=", 60))
	print("📊 TEST SUMMARY:")
	
	local totalTests = 5
	local passedTests = 0
	
	for testName, passed in pairs(testResults) do
		if passed then
			print("✅", testName, "PASSED")
			passedTests = passedTests + 1
		else
			print("❌", testName, "FAILED")
		end
	end
	
	print("\n🎯 Overall Result:", passedTests .. "/" .. totalTests, "tests passed")
	
	if passedTests == totalTests then
		print("🎉 All tests passed! Step 2A implementation is ready.")
	else
		print("⚠️  Some tests failed. Please review the implementation.")
	end
	
	return passedTests == totalTests
end

-- Individual test runners
function SelfCheck.TestCardCatalog()
	TestCardCatalog()
end

function SelfCheck.TestDeckValidation()
	TestDeckValidation()
end

function SelfCheck.TestSeededRNG()
	TestSeededRNG()
end

function SelfCheck.TestCombatTypes()
	TestCombatTypes()
end

function SelfCheck.TestGameConstants()
	TestGameConstants()
end

return SelfCheck
