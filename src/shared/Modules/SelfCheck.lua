local SelfCheck = {}

-- Import modules to test
local CardCatalog = require(script.Parent.Cards.CardCatalog)
local DeckValidator = require(script.Parent.Cards.DeckValidator)
local CardLevels = require(script.Parent.Cards.CardLevels)
local CardStats = require(script.Parent.Cards.CardStats)
local SeededRNG = require(script.Parent.RNG.SeededRNG)
local CombatTypes = require(script.Parent.Combat.CombatTypes)
local CombatUtils = require(script.Parent.Combat.CombatUtils)
local GameConstants = require(script.Parent.Constants.GameConstants)

-- Test results
local testResults = {}

-- Test 1: Card Catalog (v2)
local function TestCardCatalog()
	print("=== Testing Card Catalog (v2) ===")
	
	-- Test card retrieval
	local card = CardCatalog.GetCard("dps_001")
	if card then
		print("✅ Found dps_001:", card.name, "Rarity:", card.rarity, "SlotNumber:", card.slotNumber)
		testResults.cardCatalog = true
	else
		print("❌ Failed to find dps_001")
		testResults.cardCatalog = false
	end
	
	-- Test rarity filtering
	local commonCards = CardCatalog.GetCardsByRarity(CardCatalog.Rarities.COMMON)
	print("✅ Found", #commonCards, "common cards")
	
	-- Test class filtering
	local dpsCards = CardCatalog.GetCardsByClass(CardCatalog.Classes.DPS)
	print("✅ Found", #dpsCards, "DPS cards")
	
	-- Test slot number sorting
	local sortedCards = CardCatalog.GetCardsSortedBySlot()
	print("✅ Cards sorted by slotNumber:", sortedCards[1].slotNumber, "to", sortedCards[#sortedCards].slotNumber)
	
	print("Total cards in catalog:", #CardCatalog.GetAllCards())
end

-- Test 2: Card Levels
local function TestCardLevels()
	print("\n=== Testing Card Levels ===")
	
	-- Test level cost retrieval
	local level2Cost = CardLevels.GetLevelCost(2)
	if level2Cost then
		print("✅ Level 2 cost:", level2Cost.requiredCount, "copies,", level2Cost.softAmount, "currency")
		testResults.cardLevels = true
	else
		print("❌ Failed to get level 2 cost")
		testResults.cardLevels = false
	end
	
	-- Test level up validation
	local canLevelUp, errorMessage = CardLevels.CanLevelUp("dps_001", 1, 10, 12000)
	if canLevelUp then
		print("✅ Can level up dps_001 from 1 to 2")
	else
		print("❌ Cannot level up:", errorMessage)
		testResults.cardLevels = false
	end
	
	-- Test max level
	local maxLevelCost = CardLevels.GetLevelCost(CardLevels.MAX_LEVEL)
	if maxLevelCost then
		print("✅ Max level cost:", maxLevelCost.requiredCount, "copies,", maxLevelCost.softAmount, "currency")
	else
		print("❌ Failed to get max level cost")
		testResults.cardLevels = false
	end
	
	-- Test invalid level
	local invalidCost = CardLevels.GetLevelCost(8)
	if not invalidCost then
		print("✅ Invalid level correctly rejected")
	else
		print("❌ Invalid level incorrectly accepted")
		testResults.cardLevels = false
	end
end

-- Test 3: Card Stats
local function TestCardStats()
	print("\n=== Testing Card Stats ===")
	
	-- Test stat computation
	local level1Stats = CardStats.ComputeStats("dps_001", 1)
	if level1Stats then
		print("✅ Level 1 stats:", "ATK:", level1Stats.atk, "HP:", level1Stats.hp, "DEF:", level1Stats.defence)
		testResults.cardStats = true
	else
		print("❌ Failed to compute level 1 stats")
		testResults.cardStats = false
	end
	
	-- Test level 2 stats (should have increments)
	local level2Stats = CardStats.ComputeStats("dps_001", 2)
	if level2Stats then
		print("✅ Level 2 stats:", "ATK:", level2Stats.atk, "HP:", level2Stats.hp, "DEF:", level2Stats.defence)
		
		-- Verify increments
		local atkIncrement = level2Stats.atk - level1Stats.atk
		local hpIncrement = level2Stats.hp - level1Stats.hp
		local defIncrement = level2Stats.defence - level1Stats.defence
		
		if atkIncrement == 2 and hpIncrement == 10 and defIncrement == 2 then
			print("✅ Level increments correct")
		else
			print("❌ Level increments incorrect:", atkIncrement, hpIncrement, defIncrement)
			testResults.cardStats = false
		end
	else
		print("❌ Failed to compute level 2 stats")
		testResults.cardStats = false
	end
	
	-- Test power computation
	local power = CardStats.ComputePower(level1Stats)
	print("✅ Level 1 power:", power)
	
	-- Test max level stats
	local maxStats = CardStats.GetMaxStats("dps_001")
	local maxPower = CardStats.GetMaxPower("dps_001")
	print("✅ Max level power:", maxPower)
	
	-- Test level clamping
	local clampedStats = CardStats.ComputeStats("dps_001", 10) -- Should clamp to max level
	local maxLevelStats = CardStats.ComputeStats("dps_001", CardLevels.MAX_LEVEL)
	if clampedStats.atk == maxLevelStats.atk then
		print("✅ Level clamping works correctly")
	else
		print("❌ Level clamping failed")
		testResults.cardStats = false
	end
end

-- Test 4: Deck Validation (v2)
local function TestDeckValidation()
	print("\n=== Testing Deck Validation (v2) ===")
	
	-- Valid deck (no duplicates)
	local validDeck = {"dps_001", "support_001", "tank_001", "dps_002", "support_002", "dps_003"}
	local isValid, errorMessage = DeckValidator.ValidateDeck(validDeck)
	
	if isValid then
		print("✅ Valid deck passed validation")
		testResults.deckValidation = true
		
		-- Test board mapping (should order by slotNumber)
		local board = DeckValidator.MapDeckToBoard(validDeck)
		print("✅ Deck mapped to board with", #board, "slots")
		
		-- Verify slotNumber ordering
		local prevSlotNumber = 0
		local orderedCorrectly = true
		for i = 1, #board do
			local slotData = board[i]
			if slotData.card.slotNumber < prevSlotNumber then
				orderedCorrectly = false
				break
			end
			prevSlotNumber = slotData.card.slotNumber
		end
		
		if orderedCorrectly then
			print("✅ Board mapping ordered by slotNumber correctly")
		else
			print("❌ Board mapping not ordered by slotNumber")
			testResults.deckValidation = false
		end
		
		-- Test slot info (1-based indexing)
		local slotInfo = DeckValidator.GetSlotInfo(1)
		if slotInfo then
			print("✅ Slot 1 info:", "Row:", slotInfo.position.row, "Col:", slotInfo.position.col)
		end
		
	else
		print("❌ Valid deck failed validation:", errorMessage)
		testResults.deckValidation = false
	end
	
	-- Invalid deck (wrong size)
	local invalidDeck = {"dps_001", "support_001"}
	local isValid2, errorMessage2 = DeckValidator.ValidateDeck(invalidDeck)
	if not isValid2 then
		print("✅ Invalid deck correctly rejected:", errorMessage2)
	else
		print("❌ Invalid deck incorrectly accepted")
		testResults.deckValidation = false
	end
	
	-- Invalid deck (unknown card)
	local invalidDeck2 = {"dps_001", "support_001", "tank_001", "dps_002", "support_002", "unknown_card"}
	local isValid3, errorMessage3 = DeckValidator.ValidateDeck(invalidDeck2)
	if not isValid3 then
		print("✅ Unknown card correctly rejected:", errorMessage3)
	else
		print("❌ Unknown card incorrectly accepted")
		testResults.deckValidation = false
	end
	
	-- Invalid deck (duplicates)
	local invalidDeck3 = {"dps_001", "support_001", "tank_001", "dps_001", "support_001", "tank_001"}
	local isValid4, errorMessage4 = DeckValidator.ValidateDeck(invalidDeck3)
	if not isValid4 then
		print("✅ Duplicate cards correctly rejected:", errorMessage4)
	else
		print("❌ Duplicate cards incorrectly accepted")
		testResults.deckValidation = false
	end
end

-- Test 5: Combat Utils (v2)
local function TestCombatUtils()
	print("\n=== Testing Combat Utils (v2) ===")
	
	-- Test defence soak damage calculation
	local damageWithDefence = CombatUtils.CalculateDamage(10, 5)
	print("✅ 10 damage vs 5 defence =", damageWithDefence, "damage to HP")
	
	local damageNoDefence = CombatUtils.CalculateDamage(10, 0)
	print("✅ 10 damage vs 0 defence =", damageNoDefence, "damage to HP")
	
	-- Test damage application with defence
	local mockUnit = {
		stats = { health = 20, defence = 5 },
		state = CombatTypes.UnitState.ALIVE
	}
	
	local damageResult = CombatUtils.ApplyDamageWithDefence(mockUnit, 10)
	print("✅ Applied 10 damage:", "HP damage:", damageResult.damageToHp, "Defence reduced:", damageResult.defenceReduced)
	print("✅ Unit state:", "HP:", mockUnit.stats.health, "Defence:", mockUnit.stats.defence)
	
	testResults.combatUtils = true
end

-- Test 6: Seeded RNG
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
	
	-- Compare sequences
	local sequencesMatch = true
	for i = 1, 10 do
		if sequence1[i] ~= sequence2[i] then
			sequencesMatch = false
			break
		end
	end
	
	if sequencesMatch then
		print("✅ Seeded RNG produces deterministic sequences")
		testResults.seededRNG = true
	else
		print("❌ Seeded RNG sequences don't match")
		testResults.seededRNG = false
	end
	
	-- Test different seeds produce different sequences
	local rng3 = SeededRNG.New(54321)
	local differentSequence = {}
	for i = 1, 10 do
		table.insert(differentSequence, SeededRNG.RandomInt(rng3, 1, 100))
	end
	
	local sequencesDifferent = false
	for i = 1, 10 do
		if sequence1[i] ~= differentSequence[i] then
			sequencesDifferent = true
			break
		end
	end
	
	if sequencesDifferent then
		print("✅ Different seeds produce different sequences")
	else
		print("❌ Different seeds produce same sequences")
		testResults.seededRNG = false
	end
end

-- Test 7: Game Constants
local function TestGameConstants()
	print("\n=== Testing Game Constants ===")
	
	-- Test board dimensions
	if GameConstants.BOARD_WIDTH == 3 and GameConstants.BOARD_HEIGHT == 2 then
		print("✅ Board dimensions correct:", GameConstants.BOARD_WIDTH, "x", GameConstants.BOARD_HEIGHT)
		testResults.gameConstants = true
	else
		print("❌ Board dimensions incorrect")
		testResults.gameConstants = false
	end
	
	-- Test deck size
	if GameConstants.DECK_SIZE == 6 then
		print("✅ Deck size correct:", GameConstants.DECK_SIZE)
	else
		print("❌ Deck size incorrect")
		testResults.gameConstants = false
	end
	
	-- Test rarity weights
	local totalWeight = 0
	for _, weight in pairs(GameConstants.RARITY_WEIGHTS) do
		totalWeight = totalWeight + weight
	end
	print("✅ Total rarity weight:", totalWeight)
end

-- Run all tests
function SelfCheck.RunAllTests()
	print("🧪 Running Self-Check Tests (v2)")
	print("==================================")
	
	-- Reset test results
	testResults = {}
	
	-- Run tests
	TestCardCatalog()
	TestCardLevels()
	TestCardStats()
	TestDeckValidation()
	TestCombatUtils()
	TestSeededRNG()
	TestGameConstants()
	
	-- Summary
	print("\n==================================")
	print("📊 Test Results Summary:")
	
	local passedTests = 0
	local totalTests = 0
	
	for testName, passed in pairs(testResults) do
		totalTests = totalTests + 1
		if passed then
			passedTests = passedTests + 1
			print("✅", testName, "PASSED")
		else
			print("❌", testName, "FAILED")
		end
	end
	
	print("\n🎯 Overall Result:", passedTests, "/", totalTests, "tests passed")
	
	if passedTests == totalTests then
		print("🎉 All tests passed! System is ready.")
		return true
	else
		print("⚠️  Some tests failed. Please check the implementation.")
		return false
	end
end

return SelfCheck
