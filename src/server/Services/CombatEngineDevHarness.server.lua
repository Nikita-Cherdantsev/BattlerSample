-- CombatEngineDevHarness.server.lua
-- Development-only self-check harness for CombatEngine
-- Tests determinism, battle termination, and basic invariants

local CombatEngineDevHarness = {}

-- Modules
local CombatEngine = require(script.Parent.CombatEngine)

-- Test decks
local TEST_DECKS = {
	-- Mirror match (same deck vs itself)
	MIRROR_MATCH = {
		deckA = {"dps_001", "support_001", "tank_001", "dps_001", "support_001", "tank_001"},
		deckB = {"dps_001", "support_001", "tank_001", "dps_001", "support_001", "tank_001"},
		description = "Mirror match with balanced deck"
	},
	
	-- High damage vs high health
	AGGRESSIVE_VS_DEFENSIVE = {
		deckA = {"dps_002", "dps_003", "dps_004", "dps_002", "dps_003", "dps_004"}, -- High damage
		deckB = {"tank_001", "tank_002", "support_001", "tank_001", "tank_002", "support_001"}, -- High health
		description = "High damage vs high health"
	},
	
	-- Speed advantage
	SPEED_VS_POWER = {
		deckA = {"support_002", "support_002", "support_002", "support_002", "support_002", "support_002"}, -- High speed
		deckB = {"tank_001", "tank_001", "tank_001", "tank_001", "tank_001", "tank_001"}, -- Low speed, high health
		description = "High speed vs high health"
	},
	
	-- Mixed composition
	MIXED_COMPOSITION = {
		deckA = {"dps_001", "support_001", "tank_001", "dps_002", "support_002", "tank_002"},
		deckB = {"dps_002", "support_002", "tank_002", "dps_001", "support_001", "tank_001"},
		description = "Mixed composition battle"
	}
}

-- Test results
local testResults = {}

-- Utility functions
local function LogInfo(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("[CombatEngineTest] %s", formattedMessage))
end

local function LogSuccess(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("✅ [CombatEngineTest] %s", formattedMessage))
end

local function LogError(message, ...)
	local formattedMessage = string.format(message, ...)
	warn(string.format("❌ [CombatEngineTest] %s", formattedMessage))
end

local function PrintBattleResult(result, testName)
	print("\n" .. string.rep("=", 50))
	print("📊 Battle Result: " .. testName)
	print("=" .. string.rep("=", 50))
	print("Winner:", result.winner)
	print("Rounds:", result.rounds)
	print("Survivors A:", #result.survivorsA)
	print("Survivors B:", #result.survivorsB)
	print("Total Actions:", #result.battleLog)
	
	-- Show first few actions
	print("\nFirst 5 Actions:")
	local actionCount = 0
	for _, logEntry in ipairs(result.battleLog) do
		if logEntry.type == "attack" and actionCount < 5 then
			print(string.format("  Round %d: %s slot %d → %s slot %d, damage: %d%s", 
				logEntry.round,
				logEntry.attackerPlayer,
				logEntry.attackerSlot,
				logEntry.defenderPlayer,
				logEntry.defenderSlot,
				logEntry.damage,
				logEntry.defenderKO and " (KO)" or ""
			))
			actionCount = actionCount + 1
		end
	end
	
	print("=" .. string.rep("=", 50))
end

-- Test functions
local function TestDeterminism()
	LogInfo("Testing determinism...")
	
	local testDeck = TEST_DECKS.MIRROR_MATCH
	local seed = 12345
	
	-- Run same battle twice
	local result1 = CombatEngine.ExecuteBattle(testDeck.deckA, testDeck.deckB, seed)
	local result2 = CombatEngine.ExecuteBattle(testDeck.deckA, testDeck.deckB, seed)
	
	-- Compare results
	local isDeterministic = true
	local differences = {}
	
	if result1.winner ~= result2.winner then
		table.insert(differences, "Winner differs: " .. result1.winner .. " vs " .. result2.winner)
		isDeterministic = false
	end
	
	if result1.rounds ~= result2.rounds then
		table.insert(differences, "Rounds differ: " .. result1.rounds .. " vs " .. result2.rounds)
		isDeterministic = false
	end
	
	if #result1.battleLog ~= #result2.battleLog then
		table.insert(differences, "Battle log length differs: " .. #result1.battleLog .. " vs " .. #result2.battleLog)
		isDeterministic = false
	end
	
	-- Compare battle logs
	for i = 1, math.min(#result1.battleLog, #result2.battleLog) do
		local entry1 = result1.battleLog[i]
		local entry2 = result2.battleLog[i]
		
		if entry1.type ~= entry2.type then
			table.insert(differences, "Log entry " .. i .. " type differs: " .. entry1.type .. " vs " .. entry2.type)
			isDeterministic = false
		elseif entry1.type == "attack" then
			if entry1.attackerSlot ~= entry2.attackerSlot or
			   entry1.defenderSlot ~= entry2.defenderSlot or
			   entry1.damage ~= entry2.damage then
				table.insert(differences, "Log entry " .. i .. " attack details differ")
				isDeterministic = false
			end
		end
	end
	
	if isDeterministic then
		LogSuccess("Determinism test passed - identical results for same seed")
		testResults.determinism = true
	else
		LogError("Determinism test failed:")
		for _, diff in ipairs(differences) do
			LogError("  %s", diff)
		end
		testResults.determinism = false
	end
	
	return isDeterministic
end

local function TestBattleTermination()
	LogInfo("Testing battle termination...")
	
	local allTestsPassed = true
	
	-- Test each deck combination
	for testName, testDeck in pairs(TEST_DECKS) do
		LogInfo("Testing termination for: %s", testDeck.description)
		
		local result = CombatEngine.ExecuteBattle(testDeck.deckA, testDeck.deckB, 12345)
		
		-- Check basic termination
		if result.winner and result.rounds > 0 then
			LogSuccess("Battle terminated properly: %s wins in %d rounds", result.winner, result.rounds)
		else
			LogError("Battle failed to terminate properly")
			allTestsPassed = false
		end
		
		-- Check round cap
		if result.rounds <= 50 then
			LogSuccess("Battle completed within round cap (%d rounds)", result.rounds)
		else
			LogError("Battle exceeded round cap (%d rounds)", result.rounds)
			allTestsPassed = false
		end
		
		-- Check winner validity
		if result.winner == "A" or result.winner == "B" or result.winner == "Draw" then
			LogSuccess("Valid winner: %s", result.winner)
		else
			LogError("Invalid winner: %s", result.winner)
			allTestsPassed = false
		end
	end
	
	testResults.termination = allTestsPassed
	return allTestsPassed
end

local function TestBasicInvariants()
	LogInfo("Testing basic invariants...")
	
	local allTestsPassed = true
	
	-- Test each deck combination
	for testName, testDeck in pairs(TEST_DECKS) do
		LogInfo("Testing invariants for: %s", testDeck.description)
		
		local result = CombatEngine.ExecuteBattle(testDeck.deckA, testDeck.deckB, 12345)
		
		-- Validate battle result
		local isValid, errorMessage = CombatEngine.ValidateBattleResult(result)
		if isValid then
			LogSuccess("Battle result validation passed")
		else
			LogError("Battle result validation failed: %s", errorMessage)
			allTestsPassed = false
		end
		
		-- Check that no dead units are in survivors
		for _, survivor in ipairs(result.survivorsA) do
			if survivor.state ~= "alive" then
				LogError("Dead unit in survivors A: slot %d", survivor.slotIndex)
				allTestsPassed = false
			end
		end
		
		for _, survivor in ipairs(result.survivorsB) do
			if survivor.state ~= "alive" then
				LogError("Dead unit in survivors B: slot %d", survivor.slotIndex)
				allTestsPassed = false
			end
		end
		
		-- Check that battle log is consistent
		local attackCount = 0
		local roundCount = 0
		
		for _, logEntry in ipairs(result.battleLog) do
			if logEntry.type == "attack" then
				attackCount = attackCount + 1
				
				-- Check attack log entry validity
				if not logEntry.attackerSlot or not logEntry.defenderSlot or not logEntry.damage then
					LogError("Invalid attack log entry")
					allTestsPassed = false
				end
				
				-- Check damage is non-negative
				if logEntry.damage < 0 then
					LogError("Negative damage in log: %d", logEntry.damage)
					allTestsPassed = false
				end
				
			elseif logEntry.type == "round_start" then
				roundCount = roundCount + 1
			end
		end
		
		LogSuccess("Battle log: %d attacks, %d rounds", attackCount, roundCount)
		
		-- Check that round count matches
		if roundCount == result.rounds then
			LogSuccess("Round count consistency verified")
		else
			LogError("Round count mismatch: log shows %d, result shows %d", roundCount, result.rounds)
			allTestsPassed = false
		end
	end
	
	testResults.invariants = allTestsPassed
	return allTestsPassed
end

local function TestTurnOrder()
	LogInfo("Testing turn order...")
	
	local testDeck = TEST_DECKS.SPEED_VS_POWER
	local result = CombatEngine.ExecuteBattle(testDeck.deckA, testDeck.deckB, 12345)
	
	-- Check that high-speed units act first
	local firstAttack = nil
	for _, logEntry in ipairs(result.battleLog) do
		if logEntry.type == "attack" then
			firstAttack = logEntry
			break
		end
	end
	
	if firstAttack then
		LogInfo("First attack: %s slot %d → %s slot %d", 
			firstAttack.attackerPlayer, firstAttack.attackerSlot,
			firstAttack.defenderPlayer, firstAttack.defenderSlot)
		
		-- In this test, support_002 has higher speed than tank_001
		-- So we expect the high-speed deck to act first
		if firstAttack.attackerPlayer == "A" then
			LogSuccess("High-speed deck acted first (as expected)")
			testResults.turnOrder = true
		else
			LogError("Low-speed deck acted first (unexpected)")
			testResults.turnOrder = false
		end
	else
		LogError("No attacks found in battle log")
		testResults.turnOrder = false
	end
	
	return testResults.turnOrder
end

local function TestTargeting()
	LogInfo("Testing targeting...")
	
	local testDeck = TEST_DECKS.MIRROR_MATCH
	local result = CombatEngine.ExecuteBattle(testDeck.deckA, testDeck.deckB, 12345)
	
	-- Check that mirror targeting is working
	local mirrorTargets = 0
	local totalAttacks = 0
	
	for _, logEntry in ipairs(result.battleLog) do
		if logEntry.type == "attack" then
			totalAttacks = totalAttacks + 1
			
			-- Check if this is a mirror target (slot 1->4, 2->5, 3->6, etc.)
			local expectedMirror = nil
			if logEntry.attackerSlot == 1 then expectedMirror = 4
			elseif logEntry.attackerSlot == 2 then expectedMirror = 5
			elseif logEntry.attackerSlot == 3 then expectedMirror = 6
			elseif logEntry.attackerSlot == 4 then expectedMirror = 1
			elseif logEntry.attackerSlot == 5 then expectedMirror = 2
			elseif logEntry.attackerSlot == 6 then expectedMirror = 3
			end
			
			if logEntry.defenderSlot == expectedMirror then
				mirrorTargets = mirrorTargets + 1
			end
		end
	end
	
	local mirrorPercentage = (mirrorTargets / totalAttacks) * 100
	LogInfo("Mirror targeting: %d/%d attacks (%.1f%%)", mirrorTargets, totalAttacks, mirrorPercentage)
	
	-- In a mirror match, we expect high mirror targeting
	if mirrorPercentage >= 50 then
		LogSuccess("Mirror targeting working as expected")
		testResults.targeting = true
	else
		LogError("Mirror targeting lower than expected")
		testResults.targeting = false
	end
	
	return testResults.targeting
end

local function TestBattleStats()
	LogInfo("Testing battle statistics...")
	
	local testDeck = TEST_DECKS.AGGRESSIVE_VS_DEFENSIVE
	local result = CombatEngine.ExecuteBattle(testDeck.deckA, testDeck.deckB, 12345)
	
	local stats = CombatEngine.GetBattleStats(result)
	
	LogInfo("Battle Statistics:")
	LogInfo("  Total Rounds: %d", stats.totalRounds)
	LogInfo("  Winner: %s", stats.winner)
	LogInfo("  Survivors A: %d", stats.survivorsA)
	LogInfo("  Survivors B: %d", stats.survivorsB)
	LogInfo("  Total Actions: %d", stats.totalActions)
	LogInfo("  Total Damage: %d", stats.totalDamage)
	LogInfo("  Total KOs: %d", stats.totalKOs)
	
	-- Validate stats
	local isValid = true
	
	if stats.totalRounds ~= result.rounds then
		LogError("Stats round count mismatch")
		isValid = false
	end
	
	if stats.winner ~= result.winner then
		LogError("Stats winner mismatch")
		isValid = false
	end
	
	if stats.survivorsA ~= #result.survivorsA then
		LogError("Stats survivors A mismatch")
		isValid = false
	end
	
	if stats.survivorsB ~= #result.survivorsB then
		LogError("Stats survivors B mismatch")
		isValid = false
	end
	
	if stats.totalDamage < 0 then
		LogError("Negative total damage")
		isValid = false
	end
	
	if stats.totalKOs < 0 or stats.totalKOs > 12 then
		LogError("Invalid total KOs: %d", stats.totalKOs)
		isValid = false
	end
	
	if isValid then
		LogSuccess("Battle statistics validation passed")
		testResults.battleStats = true
	else
		LogError("Battle statistics validation failed")
		testResults.battleStats = false
	end
	
	return isValid
end

-- Main test runner
function CombatEngineDevHarness.RunAllTests()
	LogInfo("Starting CombatEngine Self-Check Tests")
	print("=" .. string.rep("=", 60))
	
	-- Reset test results
	testResults = {}
	
	-- Run tests
	local determinismPassed = TestDeterminism()
	task.wait(0.5)
	
	local terminationPassed = TestBattleTermination()
	task.wait(0.5)
	
	local invariantsPassed = TestBasicInvariants()
	task.wait(0.5)
	
	local turnOrderPassed = TestTurnOrder()
	task.wait(0.5)
	
	local targetingPassed = TestTargeting()
	task.wait(0.5)
	
	local battleStatsPassed = TestBattleStats()
	
	-- Test summary
	print("\n" .. string.rep("=", 60))
	LogInfo("CombatEngine Test Summary:")
	
	local totalTests = 6
	local passedTests = 0
	
	if determinismPassed then
		LogSuccess("✅ Determinism Test PASSED")
		passedTests = passedTests + 1
	else
		LogError("❌ Determinism Test FAILED")
	end
	
	if terminationPassed then
		LogSuccess("✅ Battle Termination Test PASSED")
		passedTests = passedTests + 1
	else
		LogError("❌ Battle Termination Test FAILED")
	end
	
	if invariantsPassed then
		LogSuccess("✅ Basic Invariants Test PASSED")
		passedTests = passedTests + 1
	else
		LogError("❌ Basic Invariants Test FAILED")
	end
	
	if turnOrderPassed then
		LogSuccess("✅ Turn Order Test PASSED")
		passedTests = passedTests + 1
	else
		LogError("❌ Turn Order Test FAILED")
	end
	
	if targetingPassed then
		LogSuccess("✅ Targeting Test PASSED")
		passedTests = passedTests + 1
	else
		LogError("❌ Targeting Test FAILED")
	end
	
	if battleStatsPassed then
		LogSuccess("✅ Battle Statistics Test PASSED")
		passedTests = passedTests + 1
	else
		LogError("❌ Battle Statistics Test FAILED")
	end
	
	print("\n" .. string.rep("=", 60))
	LogInfo("Overall Result: %d/%d tests passed", passedTests, totalTests)
	
	if passedTests == totalTests then
		LogSuccess("🎉 All CombatEngine tests passed!")
	else
		LogError("⚠️  Some CombatEngine tests failed")
	end
	
	print("=" .. string.rep("=", 60))
	
	return passedTests == totalTests
end

-- Individual test runners
function CombatEngineDevHarness.TestDeterminism()
	return TestDeterminism()
end

function CombatEngineDevHarness.TestBattleTermination()
	return TestBattleTermination()
end

function CombatEngineDevHarness.TestBasicInvariants()
	return TestBasicInvariants()
end

function CombatEngineDevHarness.TestTurnOrder()
	return TestTurnOrder()
end

function CombatEngineDevHarness.TestTargeting()
	return TestTargeting()
end

function CombatEngineDevHarness.TestBattleStats()
	return TestBattleStats()
end

-- Auto-run tests when script is executed
LogInfo("CombatEngine dev harness loaded. Run CombatEngineDevHarness.RunAllTests() to start testing.")

return CombatEngineDevHarness
