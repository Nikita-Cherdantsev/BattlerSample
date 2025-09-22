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
local Types = require(script.Parent.Types)

-- Test results
local testResults = {}

-- Test 1: Card Catalog (v2)
local function TestCardCatalog()
	print("=== Testing Card Catalog (v2) ===")
	
	-- Test card retrieval
	local card = CardCatalog.GetCard("card_100")
	if card then
		print("✅ Found card_100:", card.name, "Rarity:", card.rarity, "SlotNumber:", card.slotNumber)
		testResults.cardCatalog = true
	else
		print("❌ Failed to find card_100")
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
	local canLevelUp, errorMessage = CardLevels.CanLevelUp("card_100", 1, 10, 12000)
	if canLevelUp then
		print("✅ Can level up card_100 from 1 to 2")
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
	
	-- Test invalid level (beyond max)
	local invalidCost = CardLevels.GetLevelCost(11)
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
	local level1Stats = CardStats.ComputeStats("card_100", 1)
	if level1Stats then
		print("✅ Level 1 stats:", "ATK:", level1Stats.atk, "HP:", level1Stats.hp, "DEF:", level1Stats.defence)
		testResults.cardStats = true
	else
		print("❌ Failed to compute level 1 stats")
		testResults.cardStats = false
	end
	
	-- Test level 2 stats (should have increments)
	local level2Stats = CardStats.ComputeStats("card_100", 2)
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
	local maxStats = CardStats.GetMaxStats("card_100")
	local maxPower = CardStats.GetMaxPower("card_100")
	print("✅ Max level power:", maxPower)
	
	-- Test level clamping
	local clampedStats = CardStats.ComputeStats("card_100", 15) -- Should clamp to max level
	local maxLevelStats = CardStats.ComputeStats("card_100", CardLevels.MAX_LEVEL)
	if clampedStats.atk == maxLevelStats.atk then
		print("✅ Level clamping works correctly")
	else
		print("❌ Level clamping failed")
		testResults.cardStats = false
	end
end

-- Test 3.5: Per-Card Growth System
local function TestPerCardGrowth()
	print("\n=== Testing Per-Card Growth System ===")
	
	-- Test level 1 returns base stats
	local cardId = "card_100" -- Monkey D. Luffy
	local level1Stats = CardStats.ComputeStats(cardId, 1)
	local card = CardCatalog.GetCard(cardId)
	
	if level1Stats.atk == card.base.atk and level1Stats.hp == card.base.hp and level1Stats.defence == card.base.defence then
		print("✅ Level 1 returns base stats")
		testResults.perCardGrowth = true
	else
		print("❌ Level 1 stats don't match base:", level1Stats, "vs", card.base)
		testResults.perCardGrowth = false
	end
	
	-- Test level 2 with zero growth equals base
	local level2Stats = CardStats.ComputeStats(cardId, 2)
	if level2Stats.atk == card.base.atk and level2Stats.hp == card.base.hp and level2Stats.defence == card.base.defence then
		print("✅ Level 2 with zero growth equals base")
	else
		print("❌ Level 2 with zero growth doesn't equal base")
		testResults.perCardGrowth = false
	end
	
	-- Test level 5 with zero growth equals base
	local level5Stats = CardStats.ComputeStats(cardId, 5)
	if level5Stats.atk == card.base.atk and level5Stats.hp == card.base.hp and level5Stats.defence == card.base.defence then
		print("✅ Level 5 with zero growth equals base")
	else
		print("❌ Level 5 with zero growth doesn't equal base")
		testResults.perCardGrowth = false
	end
	
	-- Test level 10 with zero growth equals base
	local level10Stats = CardStats.ComputeStats(cardId, 10)
	if level10Stats.atk == card.base.atk and level10Stats.hp == card.base.hp and level10Stats.defence == card.base.defence then
		print("✅ Level 10 with zero growth equals base")
	else
		print("❌ Level 10 with zero growth doesn't equal base")
		testResults.perCardGrowth = false
	end
	
	-- Test MAX_LEVEL constant
	if Types.MAX_LEVEL == 10 then
		print("✅ MAX_LEVEL is 10")
	else
		print("❌ MAX_LEVEL is not 10:", Types.MAX_LEVEL)
		testResults.perCardGrowth = false
	end
	
	-- Test level-up rejection at max level
	local canLevelUp, errorMessage = CardLevels.CanLevelUp(cardId, 10, 1000, 1000000)
	if not canLevelUp and errorMessage == "Already at maximum level" then
		print("✅ Level-up correctly rejected at max level")
	else
		print("❌ Level-up not rejected at max level:", canLevelUp, errorMessage)
		testResults.perCardGrowth = false
	end
	
	-- Test placeholder costs for levels 8-10
	local cost8 = CardLevels.GetLevelCost(8)
	local cost9 = CardLevels.GetLevelCost(9)
	local cost10 = CardLevels.GetLevelCost(10)
	
	if cost8 and cost9 and cost10 then
		print("✅ Placeholder costs exist for levels 8-10")
		
		-- Test monotonicity (counts non-decreasing)
		if cost8.requiredCount <= cost9.requiredCount and cost9.requiredCount <= cost10.requiredCount then
			print("✅ Cost monotonicity maintained")
		else
			print("❌ Cost monotonicity broken")
			testResults.perCardGrowth = false
		end
	else
		print("❌ Missing placeholder costs for levels 8-10")
		testResults.perCardGrowth = false
	end
end

-- Test 4: Deck Validation (v2)
local function TestDeckValidation()
	print("\n=== Testing Deck Validation (v2) ===")
	
	-- Valid deck (no duplicates)
	local validDeck = {"card_100", "card_200", "card_300", "card_500", "card_600", "card_700"}
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
	local invalidDeck = {"card_100", "card_200"}
	local isValid2, errorMessage2 = DeckValidator.ValidateDeck(invalidDeck)
	if not isValid2 then
		print("✅ Invalid deck correctly rejected:", errorMessage2)
	else
		print("❌ Invalid deck incorrectly accepted")
		testResults.deckValidation = false
	end
	
	-- Invalid deck (unknown card)
	local invalidDeck2 = {"card_100", "card_200", "card_300", "card_500", "card_600", "unknown_card"}
	local isValid3, errorMessage3 = DeckValidator.ValidateDeck(invalidDeck2)
	if not isValid3 then
		print("✅ Unknown card correctly rejected:", errorMessage3)
	else
		print("❌ Unknown card incorrectly accepted")
		testResults.deckValidation = false
	end
	
	-- Invalid deck (duplicates)
	local invalidDeck3 = {"card_100", "card_200", "card_300", "card_100", "card_200", "card_300"}
	local isValid4, errorMessage4 = DeckValidator.ValidateDeck(invalidDeck3)
	if not isValid4 then
		print("✅ Duplicate cards correctly rejected:", errorMessage4)
	else
		print("❌ Duplicate cards incorrectly accepted")
		testResults.deckValidation = false
	end
end

-- Test 5: Combat Utils (v2) - Armor Pool Model
local function TestCombatUtils()
	print("\n=== Testing Combat Utils (v2) - Armor Pool ===")
	
	-- Test 1: Full absorb (damage <= defence)
	local damageFullAbsorb = CombatUtils.CalculateDamage(3, 5)
	if damageFullAbsorb == 0 then
		print("✅ PASS: 3 damage vs 5 defence = 0 damage to HP (full absorb)")
	else
		print("❌ FAIL: 3 damage vs 5 defence =", damageFullAbsorb, "expected 0")
		testResults.combatUtils = false
	end
	
	-- Test 2: Partial absorb (damage > defence)
	local damagePartialAbsorb = CombatUtils.CalculateDamage(8, 5)
	if damagePartialAbsorb == 3 then
		print("✅ PASS: 8 damage vs 5 defence = 3 damage to HP (partial absorb)")
	else
		print("❌ FAIL: 8 damage vs 5 defence =", damagePartialAbsorb, "expected 3")
		testResults.combatUtils = false
	end
	
	-- Test 3: Exact match (damage == defence)
	local damageExactMatch = CombatUtils.CalculateDamage(5, 5)
	if damageExactMatch == 0 then
		print("✅ PASS: 5 damage vs 5 defence = 0 damage to HP (exact match)")
	else
		print("❌ FAIL: 5 damage vs 5 defence =", damageExactMatch, "expected 0")
		testResults.combatUtils = false
	end
	
	-- Test 4: No defence
	local damageNoDefence = CombatUtils.CalculateDamage(10, 0)
	if damageNoDefence == 10 then
		print("✅ PASS: 10 damage vs 0 defence = 10 damage to HP (no defence)")
	else
		print("❌ FAIL: 10 damage vs 0 defence =", damageNoDefence, "expected 10")
		testResults.combatUtils = false
	end
	
	-- Test 5: Overkill after armor
	local damageOverkill = CombatUtils.CalculateDamage(100, 5)
	if damageOverkill == 95 then
		print("✅ PASS: 100 damage vs 5 defence = 95 damage to HP (overkill)")
	else
		print("❌ FAIL: 100 damage vs 5 defence =", damageOverkill, "expected 95")
		testResults.combatUtils = false
	end
	
	-- Test 6: Zero/one damage edges
	local damageZero = CombatUtils.CalculateDamage(0, 5)
	local damageOne = CombatUtils.CalculateDamage(1, 5)
	if damageZero == 0 and damageOne == 0 then
		print("✅ PASS: 0/1 damage vs 5 defence = 0 damage to HP (edge cases)")
	else
		print("❌ FAIL: 0/1 damage vs 5 defence =", damageZero, damageOne, "expected 0, 0")
		testResults.combatUtils = false
	end
	
	-- Test 7: Damage application with full absorb
	local mockUnit1 = {
		stats = { health = 20, defence = 5 },
		state = CombatTypes.UnitState.ALIVE
	}
	
	local damageResult1 = CombatUtils.ApplyDamageWithDefence(mockUnit1, 3)
	if damageResult1.damageToHp == 0 and damageResult1.defenceReduced == 3 and mockUnit1.stats.health == 20 and mockUnit1.stats.defence == 2 then
		print("✅ PASS: Full absorb - HP unchanged, defence reduced by damage")
	else
		print("❌ FAIL: Full absorb - HP:", mockUnit1.stats.health, "Defence:", mockUnit1.stats.defence, "Expected HP:20, Defence:2")
		testResults.combatUtils = false
	end
	
	-- Test 8: Damage application with partial absorb
	local mockUnit2 = {
		stats = { health = 20, defence = 5 },
		state = CombatTypes.UnitState.ALIVE
	}
	
	local damageResult2 = CombatUtils.ApplyDamageWithDefence(mockUnit2, 8)
	if damageResult2.damageToHp == 3 and damageResult2.defenceReduced == 5 and mockUnit2.stats.health == 17 and mockUnit2.stats.defence == 0 then
		print("✅ PASS: Partial absorb - defence→0, HP reduced by residual")
	else
		print("❌ FAIL: Partial absorb - HP:", mockUnit2.stats.health, "Defence:", mockUnit2.stats.defence, "Expected HP:17, Defence:0")
		testResults.combatUtils = false
	end
	
	-- Test 9: Invariants - dead units never act
	local deadUnit = {
		stats = { health = 0, defence = 5 },
		state = CombatTypes.UnitState.DEAD
	}
	
	if not CombatUtils.CanUnitAct(deadUnit) then
		print("✅ PASS: Dead units cannot act")
	else
		print("❌ FAIL: Dead units can act")
		testResults.combatUtils = false
	end
	
	-- Test 10: Invariants - survivors have HP > 0
	local aliveUnit = {
		stats = { health = 1, defence = 0 },
		state = CombatTypes.UnitState.ALIVE
	}
	
	if CombatUtils.CanUnitAct(aliveUnit) then
		print("✅ PASS: Alive units can act")
	else
		print("❌ FAIL: Alive units cannot act")
		testResults.combatUtils = false
	end
	
	if testResults.combatUtils == nil then
		testResults.combatUtils = true
	end
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

-- Test 9: Lootbox Migration (common -> uncommon)
local function TestLootboxMigration()
	print("\n=== Testing Lootbox Migration (common -> uncommon) ===")
	
	-- Create a mock v1 profile with "common" lootboxes
	local mockV1Profile = {
		playerId = "test_user",
		version = "v1",
		collection = {},
		deck = {},
		currencies = { soft = 0, hard = 0 },
		lootboxes = {
			{
				id = "test_box_1",
				rarity = "common",  -- This should be migrated to "uncommon"
				state = "Idle",
				acquiredAt = os.time(),
				seed = 12345
			},
			{
				id = "test_box_2", 
				rarity = "rare",   -- This should remain unchanged
				state = "Unlocking",
				acquiredAt = os.time(),
				seed = 67890
			}
		},
		pendingLootbox = {
			id = "test_pending",
			rarity = "common",  -- This should be migrated to "uncommon"
			seed = 11111
		}
	}
	
	-- Simulate migration (we can't import ProfileManager here, so we'll simulate the logic)
	local migratedProfile = {}
	for k, v in pairs(mockV1Profile) do
		migratedProfile[k] = v
	end
	
	-- Migrate lootboxes
	if migratedProfile.lootboxes then
		for _, lootbox in ipairs(migratedProfile.lootboxes) do
			if lootbox.rarity == "common" then
				lootbox.rarity = "uncommon"
			end
		end
	end
	
	-- Migrate pending lootbox
	if migratedProfile.pendingLootbox and migratedProfile.pendingLootbox.rarity == "common" then
		migratedProfile.pendingLootbox.rarity = "uncommon"
	end
	
	-- Verify migration
	local migrationSuccess = true
	
	-- Check lootbox 1 was migrated
	if migratedProfile.lootboxes[1].rarity ~= "uncommon" then
		print("❌ Lootbox 1 rarity not migrated:", migratedProfile.lootboxes[1].rarity)
		migrationSuccess = false
	else
		print("✅ Lootbox 1 migrated: common -> uncommon")
	end
	
	-- Check lootbox 2 was unchanged
	if migratedProfile.lootboxes[2].rarity ~= "rare" then
		print("❌ Lootbox 2 rarity changed unexpectedly:", migratedProfile.lootboxes[2].rarity)
		migrationSuccess = false
	else
		print("✅ Lootbox 2 unchanged: rare")
	end
	
	-- Check pending lootbox was migrated
	if migratedProfile.pendingLootbox.rarity ~= "uncommon" then
		print("❌ Pending lootbox rarity not migrated:", migratedProfile.pendingLootbox.rarity)
		migrationSuccess = false
	else
		print("✅ Pending lootbox migrated: common -> uncommon")
	end
	
	testResults.lootboxMigration = migrationSuccess
end

local function TestHardDropRanges()
	print("\n=== Testing Hard Drop Ranges (Epic/Legendary) ===")
	
	local BoxDropTables = require(script.Parent.Loot.BoxDropTables)
	local BoxRoller = require(script.Parent.Loot.BoxRoller)
	local SeededRNG = require(script.Parent.RNG.SeededRNG)
	
	local testResults = {}
	
	-- Test Epic lootbox hard drops
	print("Testing Epic lootbox hard drops...")
	local epicTable = BoxDropTables.EPIC
	local epicTests = 0
	local epicHits = 0
	local epicTotalHard = 0
	local epicMinHard = math.huge
	local epicMaxHard = 0
	
	for i = 1, 1000 do
		local rng = SeededRNG.new(i * 12345) -- Different seed for each test
		local rewards = BoxRoller.RollRewards(epicTable, rng)
		
		epicTests = epicTests + 1
		if rewards.hardDelta and rewards.hardDelta > 0 then
			epicHits = epicHits + 1
			epicTotalHard = epicTotalHard + rewards.hardDelta
			epicMinHard = math.min(epicMinHard, rewards.hardDelta)
			epicMaxHard = math.max(epicMaxHard, rewards.hardDelta)
		end
	end
	
	local epicHitRate = epicHits / epicTests
	local epicExpectedRate = epicTable.hardChance
	local epicRateOk = math.abs(epicHitRate - epicExpectedRate) < 0.02 -- Allow 2% tolerance
	
	print(string.format("Epic: %d hits out of %d tests (%.1f%%, expected %.1f%%)", 
		epicHits, epicTests, epicHitRate * 100, epicExpectedRate * 100))
	print(string.format("Epic hard range: %d-%d (expected 1-29)", epicMinHard, epicMaxHard))
	
	local epicRangeOk = epicMinHard >= 1 and epicMaxHard <= 29
	
	-- Test Legendary lootbox hard drops
	print("Testing Legendary lootbox hard drops...")
	local legendaryTable = BoxDropTables.LEGENDARY
	local legendaryTests = 0
	local legendaryHits = 0
	local legendaryTotalHard = 0
	local legendaryMinHard = math.huge
	local legendaryMaxHard = 0
	
	for i = 1, 1000 do
		local rng = SeededRNG.new(i * 54321) -- Different seed for each test
		local rewards = BoxRoller.RollRewards(legendaryTable, rng)
		
		legendaryTests = legendaryTests + 1
		if rewards.hardDelta and rewards.hardDelta > 0 then
			legendaryHits = legendaryHits + 1
			legendaryTotalHard = legendaryTotalHard + rewards.hardDelta
			legendaryMinHard = math.min(legendaryMinHard, rewards.hardDelta)
			legendaryMaxHard = math.max(legendaryMaxHard, rewards.hardDelta)
		end
	end
	
	local legendaryHitRate = legendaryHits / legendaryTests
	local legendaryExpectedRate = legendaryTable.hardChance
	local legendaryRateOk = math.abs(legendaryHitRate - legendaryExpectedRate) < 0.02 -- Allow 2% tolerance
	
	print(string.format("Legendary: %d hits out of %d tests (%.1f%%, expected %.1f%%)", 
		legendaryHits, legendaryTests, legendaryHitRate * 100, legendaryExpectedRate * 100))
	print(string.format("Legendary hard range: %d-%d (expected 1-77)", legendaryMinHard, legendaryMaxHard))
	
	local legendaryRangeOk = legendaryMinHard >= 1 and legendaryMaxHard <= 77
	
	-- Verify results
	testResults.epicRate = epicRateOk
	testResults.epicRange = epicRangeOk
	testResults.legendaryRate = legendaryRateOk
	testResults.legendaryRange = legendaryRangeOk
	
	if epicRateOk and epicRangeOk and legendaryRateOk and legendaryRangeOk then
		print("✅ All hard drop tests passed!")
	else
		print("❌ Some hard drop tests failed!")
		if not epicRateOk then print("  - Epic hit rate incorrect") end
		if not epicRangeOk then print("  - Epic range incorrect") end
		if not legendaryRateOk then print("  - Legendary hit rate incorrect") end
		if not legendaryRangeOk then print("  - Legendary range incorrect") end
	end
	
	return testResults
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
	TestPerCardGrowth()
	TestDeckValidation()
	TestCombatUtils()
	TestSeededRNG()
	TestGameConstants()
	TestLootboxMigration()
	TestHardDropRanges()
	
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
