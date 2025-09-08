local LevelUpDevHarness = {}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Modules
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local CardCatalog = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("CardCatalog"))
local CardLevels = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("CardLevels"))

-- Test configuration
local TEST_USER_ID = 999999999 -- Unique test user ID
local MockPlayer = {
	UserId = TEST_USER_ID,
	Name = "LevelUpTestUser"
}

-- Utility functions
local function LogInfo(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("[LevelUpHarness] %s", formattedMessage))
end

local function LogSuccess(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("[LevelUpHarness] ✅ %s", formattedMessage))
end

local function LogError(message, ...)
	local formattedMessage = string.format(message, ...)
	warn(string.format("[LevelUpHarness] ❌ %s", formattedMessage))
end

-- Test helper: Create a test profile with specific card levels and resources
local function CreateTestProfile()
	-- Grant enough cards and currency for testing
	PlayerDataService.GrantCards(MockPlayer, {
		dps_001 = 50,  -- Enough for multiple level-ups
		tank_001 = 1,  -- Just one copy (insufficient for level-up)
		support_001 = 15  -- Enough for one level-up
	})
	
	-- Add soft currency
	local profile = PlayerDataService.GetProfile(MockPlayer)
	if profile then
		profile.currencies.soft = 200000  -- Enough for multiple level-ups
		-- Force save the profile
		PlayerDataService.ForceSave(MockPlayer)
	end
end

-- Test 1: Happy path - successful level-up
local function TestHappyPath()
	LogInfo("Testing happy path level-up...")
	
	-- Get baseline
	local profile = PlayerDataService.GetProfile(MockPlayer)
	local baselineCount = profile.collection["dps_001"].count
	local baselineLevel = profile.collection["dps_001"].level
	local baselineSoft = profile.currencies.soft
	local baselineSquadPower = profile.squadPower
	
	-- Perform level-up
	local success, errorMessage = PlayerDataService.LevelUpCard(MockPlayer, "dps_001")
	
	if not success then
		LogError("Happy path failed: %s", errorMessage)
		return false
	end
	
	-- Verify results
	profile = PlayerDataService.GetProfile(MockPlayer)
	local newCount = profile.collection["dps_001"].count
	local newLevel = profile.collection["dps_001"].level
	local newSoft = profile.currencies.soft
	local newSquadPower = profile.squadPower
	
	-- Check level increased by 1
	if newLevel ~= baselineLevel + 1 then
		LogError("Level not increased correctly. Expected: %d, Got: %d", baselineLevel + 1, newLevel)
		return false
	end
	
	-- Check count decreased by required amount
	local expectedCount = baselineCount - 10  -- Level 2 requires 10 copies
	if newCount ~= expectedCount then
		LogError("Count not decreased correctly. Expected: %d, Got: %d", expectedCount, newCount)
		return false
	end
	
	-- Check soft currency decreased
	local expectedSoft = baselineSoft - 12000  -- Level 2 requires 12,000 soft
	if newSoft ~= expectedSoft then
		LogError("Soft currency not decreased correctly. Expected: %d, Got: %d", expectedSoft, newSoft)
		return false
	end
	
	-- Check squad power increased (dps_001 is in default deck)
	if newSquadPower <= baselineSquadPower then
		LogError("Squad power not increased. Expected > %d, Got: %d", baselineSquadPower, newSquadPower)
		return false
	end
	
	LogSuccess("Happy path test passed - level %d, count %d, soft %d, squad power %d", 
		newLevel, newCount, newSoft, newSquadPower)
	return true
end

-- Test 2: Card not owned
local function TestCardNotOwned()
	LogInfo("Testing card not owned...")
	
	local success, errorMessage = PlayerDataService.LevelUpCard(MockPlayer, "dps_004")  -- Not granted
	
	if success then
		LogError("Card not owned test failed: should have failed but succeeded")
		return false
	end
	
	if errorMessage ~= "CARD_NOT_OWNED" then
		LogError("Wrong error message. Expected: CARD_NOT_OWNED, Got: %s", errorMessage)
		return false
	end
	
	LogSuccess("Card not owned test passed")
	return true
end

-- Test 3: Level maxed
local function TestLevelMaxed()
	LogInfo("Testing level maxed...")
	
	-- First, level up support_001 to max level (requires multiple level-ups)
	local profile = PlayerDataService.GetProfile(MockPlayer)
	local currentLevel = profile.collection["support_001"].level
	
	-- Level up to max (7) - this will require multiple calls
	while currentLevel < CardLevels.MAX_LEVEL do
		local success, errorMessage = PlayerDataService.LevelUpCard(MockPlayer, "support_001")
		if not success then
			-- If we can't level up due to insufficient resources, grant more
			if errorMessage == "INSUFFICIENT_COPIES" or errorMessage == "INSUFFICIENT_SOFT" then
				PlayerDataService.GrantCards(MockPlayer, { support_001 = 100 })
				profile = PlayerDataService.GetProfile(MockPlayer)
				profile.currencies.soft = 5000000  -- Massive amount
				PlayerDataService.ForceSave(MockPlayer)
			else
				LogError("Unexpected error while leveling to max: %s", errorMessage)
				return false
			end
		else
			profile = PlayerDataService.GetProfile(MockPlayer)
			currentLevel = profile.collection["support_001"].level
		end
	end
	
	-- Now try to level up again (should fail)
	local success, errorMessage = PlayerDataService.LevelUpCard(MockPlayer, "support_001")
	
	if success then
		LogError("Level maxed test failed: should have failed but succeeded")
		return false
	end
	
	if errorMessage ~= "LEVEL_MAXED" then
		LogError("Wrong error message. Expected: LEVEL_MAXED, Got: %s", errorMessage)
		return false
	end
	
	LogSuccess("Level maxed test passed")
	return true
end

-- Test 4: Insufficient copies
local function TestInsufficientCopies()
	LogInfo("Testing insufficient copies...")
	
	local success, errorMessage = PlayerDataService.LevelUpCard(MockPlayer, "tank_001")  -- Only 1 copy
	
	if success then
		LogError("Insufficient copies test failed: should have failed but succeeded")
		return false
	end
	
	if errorMessage ~= "INSUFFICIENT_COPIES" then
		LogError("Wrong error message. Expected: INSUFFICIENT_COPIES, Got: %s", errorMessage)
		return false
	end
	
	LogSuccess("Insufficient copies test passed")
	return true
end

-- Test 5: Insufficient soft currency
local function TestInsufficientSoft()
	LogInfo("Testing insufficient soft currency...")
	
	-- Set soft currency to 0
	local profile = PlayerDataService.GetProfile(MockPlayer)
	profile.currencies.soft = 0
	PlayerDataService.ForceSave(MockPlayer)
	
	local success, errorMessage = PlayerDataService.LevelUpCard(MockPlayer, "dps_001")
	
	if success then
		LogError("Insufficient soft test failed: should have failed but succeeded")
		return false
	end
	
	if errorMessage ~= "INSUFFICIENT_SOFT" then
		LogError("Wrong error message. Expected: INSUFFICIENT_SOFT, Got: %s", errorMessage)
		return false
	end
	
	LogSuccess("Insufficient soft currency test passed")
	return true
end

-- Test 6: Rate limiting (simulated)
local function TestRateLimit()
	LogInfo("Testing rate limiting...")
	
	-- Restore soft currency for this test
	local profile = PlayerDataService.GetProfile(MockPlayer)
	profile.currencies.soft = 200000
	PlayerDataService.ForceSave(MockPlayer)
	
	-- Make multiple rapid requests (should hit rate limit)
	local successCount = 0
	for i = 1, 15 do  -- More than the 10/minute limit
		local success, errorMessage = PlayerDataService.LevelUpCard(MockPlayer, "dps_001")
		if success then
			successCount = successCount + 1
		elseif errorMessage == "RATE_LIMITED" then
			LogSuccess("Rate limiting test passed - hit rate limit after %d successful requests", successCount)
			return true
		end
	end
	
	LogError("Rate limiting test failed - no rate limit hit after 15 requests")
	return false
end

-- Main test runner
function LevelUpDevHarness.RunAllTests()
	if not RunService:IsStudio() then
		LogError("Level-up harness only runs in Studio")
		return
	end
	
	LogInfo("Starting Level-Up Dev Harness tests...")
	
	-- Clean up any existing test profile
	PlayerDataService.ClearCache(TEST_USER_ID)
	
	-- Create test profile
	CreateTestProfile()
	
	local tests = {
		{"Happy Path", TestHappyPath},
		{"Card Not Owned", TestCardNotOwned},
		{"Level Maxed", TestLevelMaxed},
		{"Insufficient Copies", TestInsufficientCopies},
		{"Insufficient Soft", TestInsufficientSoft},
		{"Rate Limiting", TestRateLimit}
	}
	
	local passed = 0
	local total = #tests
	
	for _, test in ipairs(tests) do
		local testName, testFunc = test[1], test[2]
		LogInfo("Running test: %s", testName)
		
		local success = testFunc()
		if success then
			passed = passed + 1
		end
		
		-- Small delay between tests
		task.wait(0.1)
	end
	
	-- Cleanup
	PlayerDataService.ClearCache(TEST_USER_ID)
	
	LogInfo("Level-Up Dev Harness completed: %d/%d tests passed", passed, total)
	
	if passed == total then
		LogSuccess("All level-up tests passed!")
	else
		LogError("Some level-up tests failed")
	end
	
	return passed == total
end

return LevelUpDevHarness
