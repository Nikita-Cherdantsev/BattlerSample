-- MatchServiceDevHarness.server.lua
-- Development-only test harness for MatchService
-- Tests match execution, error handling, and determinism

local MatchServiceDevHarness = {}

-- Modules
local MatchService = require(script.Parent:WaitForChild("MatchService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

-- Test results
local testResults = {}

-- Mock player for testing
local MockPlayer = {
	UserId = 999997, -- Different from other harnesses
	Name = "MatchService_TestPlayer"
}

-- Utility functions
local function LogInfo(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("[MatchServiceTest] %s", formattedMessage))
end

local function LogSuccess(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("✅ [MatchServiceTest] %s", formattedMessage))
end

local function LogError(message, ...)
	local formattedMessage = string.format(message, ...)
	warn(string.format("❌ [MatchServiceTest] %s", formattedMessage))
end

local function PrintMatchResult(result, testName)
	print("\n" .. string.rep("=", 50))
	print("🎮 Match Result: " .. testName)
	print("=" .. string.rep("=", 50))
	
	if result.ok then
		print("Status: SUCCESS")
		print("Match ID:", result.matchId)
		print("Seed:", result.seed)
		print("Winner:", result.result.winner)
		print("Rounds:", result.result.rounds)
		print("Survivors A:", result.result.survivorsA)
		print("Survivors B:", result.result.survivorsB)
		print("Log Entries:", #result.log)
		
		-- Show first few log entries
		print("\nFirst 5 Log Entries:")
		for i = 1, math.min(5, #result.log) do
			local entry = result.log[i]
			if entry.t == "a" then
				print(string.format("  %d: Attack - %s slot %d → %s slot %d, damage: %d%s", 
					i, entry.ap, entry.as, entry.dp, entry.ds, entry.d, entry.k and " (KO)" or ""))
			elseif entry.t == "r" then
				print(string.format("  %d: Round %d start", i, entry.r))
			end
		end
	else
		print("Status: FAILED")
		print("Error Code:", result.error.code)
		print("Error Message:", result.error.message)
	end
	
	print("=" .. string.rep("=", 50))
end

-- Test functions
local function TestHappyPath()
	LogInfo("Testing happy path...")
	
	-- Enable test mode to bypass rate limits
	MatchService.EnableTestMode(MockPlayer)
	
	-- Ensure player has a valid deck
	local validDeck = {"dps_001", "support_001", "tank_001", "dps_001", "support_001", "tank_001"}
	
	-- Set up player deck (this would normally be done via PlayerDataService)
	-- For testing, we'll assume the player has a valid deck
	
	local requestData = {
		mode = "PvE",
		seed = 12345 -- This will be ignored by server
	}
	
	local result = MatchService.ExecuteMatch(MockPlayer, requestData)
	
	if result.ok then
		LogSuccess("Happy path test passed")
		PrintMatchResult(result, "Happy Path (PvE)")
		testResults.happyPath = true
		return true
	else
		LogError("Happy path test failed: %s", result.error.message)
		testResults.happyPath = false
		return false
	end
end

local function TestDeterminism()
	LogInfo("Testing determinism...")
	
	local requestData = {
		mode = "PvE",
		seed = 424242 -- Fixed seed for determinism test
	}
	
	-- Run same match twice (test mode already enabled)
	local result1 = MatchService.ExecuteMatch(MockPlayer, requestData)
	local result2 = MatchService.ExecuteMatch(MockPlayer, requestData)
	
	if not result1.ok or not result2.ok then
		LogError("Determinism test failed - one or both matches failed")
		testResults.determinism = false
		return false
	end
	
	-- Compare results
	local isDeterministic = true
	local differences = {}
	
	if result1.result.winner ~= result2.result.winner then
		table.insert(differences, "Winner differs: " .. result1.result.winner .. " vs " .. result2.result.winner)
		isDeterministic = false
	end
	
	if result1.result.rounds ~= result2.result.rounds then
		table.insert(differences, "Rounds differ: " .. result1.result.rounds .. " vs " .. result2.result.rounds)
		isDeterministic = false
	end
	
	if #result1.log ~= #result2.log then
		table.insert(differences, "Log length differs: " .. #result1.log .. " vs " .. #result2.log)
		isDeterministic = false
	end
	
	-- Compare log entries
	for i = 1, math.min(#result1.log, #result2.log) do
		local entry1 = result1.log[i]
		local entry2 = result2.log[i]
		
		if entry1.t ~= entry2.t then
			table.insert(differences, "Log entry " .. i .. " type differs")
			isDeterministic = false
		elseif entry1.t == "a" then
			if entry1.as ~= entry2.as or entry1.ds ~= entry2.ds or entry1.d ~= entry2.d then
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

local function TestRateLimiting()
	LogInfo("Testing rate limiting...")
	
	-- Temporarily disable test mode to test real rate limiting
	MatchService.DisableTestMode(MockPlayer)
	
	local requestData = {
		mode = "PvE"
	}
	
	-- Send multiple requests quickly
	local results = {}
	for i = 1, 3 do
		LogInfo("Sending match request %d/3", i)
		local result = MatchService.ExecuteMatch(MockPlayer, requestData)
		table.insert(results, result)
		task.wait(0.1) -- Small delay between requests
	end
	
	-- Re-enable test mode for other tests
	MatchService.EnableTestMode(MockPlayer)
	
	-- Check results
	local rateLimitedCount = 0
	for i, result in ipairs(results) do
		if not result.ok and result.error.code == "RATE_LIMITED" then
			rateLimitedCount = rateLimitedCount + 1
		end
	end
	
	if rateLimitedCount > 0 then
		LogSuccess("Rate limiting working: %d/%d requests were rate limited", rateLimitedCount, #results)
		testResults.rateLimiting = true
	else
		LogError("Rate limiting not working: no requests were rate limited")
		testResults.rateLimiting = false
	end
	
	return testResults.rateLimiting
end

local function TestConcurrencyGuard()
	LogInfo("Testing concurrency guard...")
	
	-- Ensure test mode is enabled for concurrency testing
	MatchService.EnableTestMode(MockPlayer)
	
	-- Kick off the first match in another thread (it sets isInMatch = true immediately)
	local ok1, code1
	task.spawn(function()
		ok1, code1 = MatchService.ExecuteMatch(MockPlayer, { mode = "PvE", seed = math.random(1, 1e9) })
	end)
	
	-- Do NOT wait here; call again immediately:
	local result2 = MatchService.ExecuteMatch(MockPlayer, { mode = "PvE", seed = math.random(1, 1e9) })
	
	if result2.ok or result2.error.code ~= "BUSY" then
		LogError("[MatchServiceTest] Concurrency guard failed: expected BUSY, got %s", tostring(result2.error and result2.error.code or "unknown"))
		testResults.concurrencyGuard = false
	else
		LogSuccess("[MatchServiceTest] Concurrency guard working (BUSY rejection)")
		testResults.concurrencyGuard = true
	end
	
	return testResults.concurrencyGuard
end

local function TestInvalidRequests()
	LogInfo("Testing invalid requests...")
	
	-- Ensure test mode is enabled for validation tests
	MatchService.EnableTestMode(MockPlayer)
	
	-- Clear any existing match state to avoid concurrency guard interference
	MatchService.ForceCleanup(MockPlayer)
	
	local allTestsPassed = true
	
	-- Test invalid mode
	local invalidModeResult = MatchService.ExecuteMatch(MockPlayer, {mode = "INVALID"})
	if not invalidModeResult.ok and invalidModeResult.error.code == "INVALID_REQUEST" then
		LogSuccess("Invalid mode correctly rejected")
	else
		LogError("Invalid mode not properly rejected")
		allTestsPassed = false
	end
	
	-- Test missing deck (would require mocking PlayerDataService)
	-- For now, we'll just test the structure
	
	if allTestsPassed then
		LogSuccess("Invalid request tests passed")
		testResults.invalidRequests = true
	else
		LogError("Invalid request tests failed")
		testResults.invalidRequests = false
	end
	
	return allTestsPassed
end

local function TestPvPMode()
	LogInfo("Testing PvP mode...")
	
	-- Ensure test mode is enabled for PvP testing
	MatchService.EnableTestMode(MockPlayer)
	
	local requestData = {
		mode = "PvP"
	}
	
	local result = MatchService.ExecuteMatch(MockPlayer, requestData)
	
	if result.ok then
		LogSuccess("PvP mode test passed")
		PrintMatchResult(result, "PvP Mode")
		testResults.pvpMode = true
		return true
	else
		LogError("PvP mode test failed: %s", result.error.message)
		testResults.pvpMode = false
		return false
	end
end

local function TestPlayerStatus()
	LogInfo("Testing player status...")
	
	-- Ensure test mode is enabled for status testing
	MatchService.EnableTestMode(MockPlayer)
	
	local status = MatchService.GetPlayerStatus(MockPlayer)
	
	LogInfo("Player Status:")
	LogInfo("  Is in match: %s", tostring(status.isInMatch))
	LogInfo("  Last request: %d", status.lastRequest)
	LogInfo("  Request count: %d", status.requestCount)
	
	-- Test status after a match
	local requestData = {mode = "PvE"}
	local result = MatchService.ExecuteMatch(MockPlayer, requestData)
	
	local statusAfter = MatchService.GetPlayerStatus(MockPlayer)
	
	if not statusAfter.isInMatch then
		LogSuccess("Player status correctly updated after match")
		testResults.playerStatus = true
	else
		LogError("Player status not properly updated after match")
		testResults.playerStatus = false
	end
	
	return testResults.playerStatus
end

-- Main test runner
function MatchServiceDevHarness.RunAllTests()
	LogInfo("Starting MatchService Self-Check Tests")
	print("=" .. string.rep("=", 60))
	
	-- Reset test results
	testResults = {}
	
	-- Run tests
	local happyPathPassed = TestHappyPath()
	task.wait(0.5)
	
	local determinismPassed = TestDeterminism()
	task.wait(0.5)
	
	local rateLimitingPassed = TestRateLimiting()
	task.wait(0.5)
	
	local concurrencyGuardPassed = TestConcurrencyGuard()
	task.wait(0.5)
	
	local invalidRequestsPassed = TestInvalidRequests()
	task.wait(0.5)
	
	local pvpModePassed = TestPvPMode()
	task.wait(0.5)
	
	local playerStatusPassed = TestPlayerStatus()
	
	-- Test summary
	print("\n" .. string.rep("=", 60))
	LogInfo("MatchService Test Summary:")
	
	local totalTests = 7
	local passedTests = 0
	
	if happyPathPassed then
		LogSuccess("✅ Happy Path Test PASSED")
		passedTests = passedTests + 1
	else
		LogError("❌ Happy Path Test FAILED")
	end
	
	if determinismPassed then
		LogSuccess("✅ Determinism Test PASSED")
		passedTests = passedTests + 1
	else
		LogError("❌ Determinism Test FAILED")
	end
	
	if rateLimitingPassed then
		LogSuccess("✅ Rate Limiting Test PASSED")
		passedTests = passedTests + 1
	else
		LogError("❌ Rate Limiting Test FAILED")
	end
	
	if concurrencyGuardPassed then
		LogSuccess("✅ Concurrency Guard Test PASSED")
		passedTests = passedTests + 1
	else
		LogError("❌ Concurrency Guard Test FAILED")
	end
	
	if invalidRequestsPassed then
		LogSuccess("✅ Invalid Requests Test PASSED")
		passedTests = passedTests + 1
	else
		LogError("❌ Invalid Requests Test FAILED")
	end
	
	if pvpModePassed then
		LogSuccess("✅ PvP Mode Test PASSED")
		passedTests = passedTests + 1
	else
		LogError("❌ PvP Mode Test FAILED")
	end
	
	if playerStatusPassed then
		LogSuccess("✅ Player Status Test PASSED")
		passedTests = passedTests + 1
	else
		LogError("❌ Player Status Test FAILED")
	end
	
	print("\n" .. string.rep("=", 60))
	LogInfo("Overall Result: %d/%d tests passed", passedTests, totalTests)
	
	if passedTests == totalTests then
		LogSuccess("🎉 All MatchService tests passed!")
	else
		LogError("⚠️  Some MatchService tests failed")
	end
	
	print("=" .. string.rep("=", 60))
	
	-- Clean up test mode
	MatchService.DisableTestMode(MockPlayer)
	MatchService.ForceCleanup(MockPlayer)
	LogInfo("Test cleanup completed")
	
	return passedTests == totalTests
end

-- Individual test runners
function MatchServiceDevHarness.TestHappyPath()
	return TestHappyPath()
end

function MatchServiceDevHarness.TestDeterminism()
	return TestDeterminism()
end

function MatchServiceDevHarness.TestRateLimiting()
	return TestRateLimiting()
end

function MatchServiceDevHarness.TestConcurrencyGuard()
	return TestConcurrencyGuard()
end

function MatchServiceDevHarness.TestInvalidRequests()
	return TestInvalidRequests()
end

function MatchServiceDevHarness.TestPvPMode()
	return TestPvPMode()
end

function MatchServiceDevHarness.TestPlayerStatus()
	return TestPlayerStatus()
end

-- Auto-run tests when script is executed (if in Studio)
if game:GetService("RunService"):IsStudio() then
	LogInfo("🎮 Studio detected. Auto-running MatchService dev harness...")
	spawn(function()
		task.wait(11) -- Wait for services to initialize and other harnesses
		MatchServiceDevHarness.RunAllTests()
	end)
end

return MatchServiceDevHarness
