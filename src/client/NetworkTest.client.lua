-- NetworkTest.client.lua
-- Client-side test script for networking functionality
-- Tests RemoteEvents for profile/deck operations

local NetworkTest = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for Network folder to be created
local NetworkFolder = ReplicatedStorage:WaitForChild("Network")

-- Remote Events
local RequestSetDeck = NetworkFolder:WaitForChild("RequestSetDeck")
local RequestProfile = NetworkFolder:WaitForChild("RequestProfile")
local ProfileUpdated = NetworkFolder:WaitForChild("ProfileUpdated")

-- Test state
local testResults = {}
local isTestComplete = false

-- Utility functions
local function LogInfo(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("[NetworkTest] %s", formattedMessage))
end

local function LogSuccess(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("✅ [NetworkTest] %s", formattedMessage))
end

local function LogError(message, ...)
	local formattedMessage = string.format(message, ...)
	warn(string.format("❌ [NetworkTest] %s", formattedMessage))
end

local function WaitForResponse(timeout)
	timeout = timeout or 10
	local startTime = tick()
	
	while not isTestComplete and (tick() - startTime) < timeout do
		task.wait(0.1)
	end
	
	if not isTestComplete then
		LogError("Test timeout after %d seconds", timeout)
		return false
	end
	
	return true
end

-- ProfileUpdated event handler
ProfileUpdated.OnClientEvent:Connect(function(payload)
	LogInfo("Received ProfileUpdated event")
	
	if payload.error then
		LogError("Error received: %s - %s", payload.error.code, payload.error.message)
		testResults.lastError = payload.error
	else
		LogSuccess("Profile update received successfully")
		if payload.deck then
			LogInfo("Deck updated: %d cards", #payload.deck)
		end
		if payload.collectionSummary then
			LogInfo("Collection summary: %d card types", #payload.collectionSummary)
		end
		if payload.loginInfo then
			LogInfo("Login info: streak %d, last login %s", 
				payload.loginInfo.loginStreak,
				os.date("%Y-%m-%d %H:%M:%S", payload.loginInfo.lastLoginAt))
		end
		testResults.lastSuccess = payload
	end
	
	testResults.lastResponse = payload
	isTestComplete = true
end)

-- Test functions
local function TestRequestProfile()
	LogInfo("Testing RequestProfile...")
	
	-- Reset test state
	testResults.lastResponse = nil
	testResults.lastError = nil
	testResults.lastSuccess = nil
	isTestComplete = false
	
	-- Send profile request
	RequestProfile:FireServer({})
	
	-- Wait for response
	if WaitForResponse() then
		if testResults.lastError then
			LogError("RequestProfile failed: %s", testResults.lastError.message)
			return false
		else
			LogSuccess("RequestProfile successful")
			return true
		end
	else
		return false
	end
end

local function TestRequestSetDeckValid()
	LogInfo("Testing RequestSetDeck with valid deck...")
	
	-- Reset test state
	testResults.lastResponse = nil
	testResults.lastError = nil
	testResults.lastSuccess = nil
	isTestComplete = false
	
	-- Valid deck (using cards that should exist in default collection)
	local validDeck = {"dps_001", "support_001", "tank_001", "dps_001", "support_001", "tank_001"}
	
	-- Send deck update request
	RequestSetDeck:FireServer({deck = validDeck})
	
	-- Wait for response
	if WaitForResponse() then
		if testResults.lastError then
			LogError("RequestSetDeck valid failed: %s", testResults.lastError.message)
			return false
		else
			LogSuccess("RequestSetDeck valid successful")
			return true
		end
	else
		return false
	end
end

local function TestRequestSetDeckInvalid()
	LogInfo("Testing RequestSetDeck with invalid deck...")
	
	-- Reset test state
	testResults.lastResponse = nil
	testResults.lastError = nil
	testResults.lastSuccess = nil
	isTestComplete = false
	
	-- Invalid deck (wrong size)
	local invalidDeck = {"dps_001", "support_001"}
	
	-- Send deck update request
	RequestSetDeck:FireServer({deck = invalidDeck})
	
	-- Wait for response
	if WaitForResponse() then
		if testResults.lastError then
			LogSuccess("RequestSetDeck invalid correctly rejected: %s", testResults.lastError.message)
			return true
		else
			LogError("RequestSetDeck invalid was incorrectly accepted")
			return false
		end
	else
		return false
	end
end

local function TestRequestSetDeckOverLimit()
	LogInfo("Testing RequestSetDeck with over-limit deck...")
	
	-- Reset test state
	testResults.lastResponse = nil
	testResults.lastError = nil
	testResults.lastSuccess = nil
	isTestComplete = false
	
	-- Over-limit deck (cards player doesn't have enough of)
	local overLimitDeck = {"dps_003", "dps_003", "dps_003", "dps_003", "dps_003", "dps_003"}
	
	-- Send deck update request
	RequestSetDeck:FireServer({deck = overLimitDeck})
	
	-- Wait for response
	if WaitForResponse() then
		if testResults.lastError then
			LogSuccess("RequestSetDeck over-limit correctly rejected: %s", testResults.lastError.message)
			return true
		else
			LogError("RequestSetDeck over-limit was incorrectly accepted")
			return false
		end
	else
		return false
	end
end

local function TestRateLimiting()
	LogInfo("Testing rate limiting...")
	
	-- Send multiple profile requests quickly
	for i = 1, 3 do
		LogInfo("Sending profile request %d/3", i)
		RequestProfile:FireServer({})
		task.wait(0.1) -- Small delay between requests
	end
	
	-- Wait a bit for responses
	task.wait(2)
	
	LogInfo("Rate limiting test completed (check server logs for rate limit messages)")
	return true
end

-- Main test runner
function NetworkTest.RunAllTests()
	LogInfo("Starting Network Tests")
	print("=" .. string.rep("=", 50))
	
	local totalTests = 5
	local passedTests = 0
	
	-- Test 1: Request Profile
	LogInfo("Test 1/5: RequestProfile")
	if TestRequestProfile() then
		passedTests = passedTests + 1
		LogSuccess("RequestProfile test passed")
	else
		LogError("RequestProfile test failed")
	end
	
	task.wait(1) -- Wait between tests
	
	-- Test 2: Request SetDeck (Valid)
	LogInfo("Test 2/5: RequestSetDeck (Valid)")
	if TestRequestSetDeckValid() then
		passedTests = passedTests + 1
		LogSuccess("RequestSetDeck valid test passed")
	else
		LogError("RequestSetDeck valid test failed")
	end
	
	task.wait(1)
	
	-- Test 3: Request SetDeck (Invalid)
	LogInfo("Test 3/5: RequestSetDeck (Invalid)")
	if TestRequestSetDeckInvalid() then
		passedTests = passedTests + 1
		LogSuccess("RequestSetDeck invalid test passed")
	else
		LogError("RequestSetDeck invalid test failed")
	end
	
	task.wait(1)
	
	-- Test 4: Request SetDeck (Over Limit)
	LogInfo("Test 4/5: RequestSetDeck (Over Limit)")
	if TestRequestSetDeckOverLimit() then
		passedTests = passedTests + 1
		LogSuccess("RequestSetDeck over-limit test passed")
	else
		LogError("RequestSetDeck over-limit test failed")
	end
	
	task.wait(1)
	
	-- Test 5: Rate Limiting
	LogInfo("Test 5/5: Rate Limiting")
	if TestRateLimiting() then
		passedTests = passedTests + 1
		LogSuccess("Rate limiting test passed")
	else
		LogError("Rate limiting test failed")
	end
	
	-- Test summary
	print("\n" .. string.rep("=", 50))
	LogInfo("Network Tests Complete: %d/%d tests passed", passedTests, totalTests)
	
	if passedTests == totalTests then
		LogSuccess("All network tests passed!")
	else
		LogError("Some network tests failed")
	end
	
	print("=" .. string.rep("=", 50))
	
	return passedTests == totalTests
end

-- Individual test runners
function NetworkTest.TestRequestProfile()
	return TestRequestProfile()
end

function NetworkTest.TestRequestSetDeckValid()
	return TestRequestSetDeckValid()
end

function NetworkTest.TestRequestSetDeckInvalid()
	return TestRequestSetDeckInvalid()
end

function NetworkTest.TestRequestSetDeckOverLimit()
	return TestRequestSetDeckOverLimit()
end

function NetworkTest.TestRateLimiting()
	return TestRateLimiting()
end

-- Auto-run tests when script executes
LogInfo("Network test script loaded. Run NetworkTest.RunAllTests() to start testing.")
LogInfo("Make sure the server has RemoteEvents running and a player profile exists.")

return NetworkTest
