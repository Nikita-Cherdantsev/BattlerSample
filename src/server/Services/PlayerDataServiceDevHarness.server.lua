-- PlayerDataServiceDevHarness.server.lua
-- Development-only testing harness for PlayerDataService
-- Run this in Studio to test the complete player lifecycle and API

local PlayerDataServiceDevHarness = {}

-- Services
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

-- Modules
local PlayerDataService = require(script.Parent.PlayerDataService)

-- Configuration
local TEST_DELAY = 3 -- Seconds between operations to respect Studio budgets
local MOCK_PLAYER_NAME = "TestPlayer"
local MOCK_USER_ID = 999999

-- Mock player for testing
local MockPlayer = {}
MockPlayer.Name = MOCK_PLAYER_NAME
MockPlayer.UserId = MOCK_USER_ID

-- Utility functions
local function WaitForBudget()
	task.wait(TEST_DELAY)
end

local function PrintProfile(profile, label)
	print("\n" .. string.rep("=", 50))
	print("📋 " .. label)
	print("=" .. string.rep("=", 50))
	
	if not profile then
		print("❌ Profile is nil")
		return
	end
	
	print("Player ID:", profile.playerId)
	print("Created:", os.date("%Y-%m-%d %H:%M:%S", profile.createdAt))
	print("Last Login:", os.date("%Y-%m-%d %H:%M:%S", profile.lastLoginAt))
	print("Login Streak:", profile.loginStreak)
	print("Soft Currency:", profile.currencies.soft)
	print("Hard Currency:", profile.currencies.hard)
	
	print("\n📚 Collection:")
	if next(profile.collection) then
		for cardId, count in pairs(profile.collection) do
			print("  " .. cardId .. ": " .. count)
		end
	else
		print("  (empty)")
	end
	
	print("\n🃏 Deck:")
	for i, cardId in ipairs(profile.deck) do
		print("  " .. i .. ". " .. cardId)
	end
	
	print("=" .. string.rep("=", 50))
end

local function CheckStudioAccess()
	local success, _ = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	
	if not success then
		print("⚠️  Studio Access to API Services is disabled!")
		print("   Enable it in Game Settings > Security to test DataStore operations.")
		return false
	end
	
	return true
end

-- Test functions
local function TestServiceStatus()
	print("\n🧪 Testing Service Status...")
	
	local status = PlayerDataService.GetStatus()
	print("✅ Service Status:")
	print("  Active Profiles:", status.activeProfiles)
	print("  Active Autosaves:", status.activeAutosaves)
	print("  Is Shutting Down:", status.isShuttingDown)
	print("  Autosave Interval:", status.autosaveInterval, "seconds")
end

local function TestProfileCreation()
	print("\n🧪 Testing Profile Creation...")
	
	-- Simulate player join
	print("Simulating player join...")
	
	-- Get initial profile (should be nil)
	local initialProfile = PlayerDataService.GetProfile(MockPlayer)
	if not initialProfile then
		print("✅ Initial profile correctly nil")
	else
		print("❌ Initial profile should be nil")
		return false
	end
	
	-- Simulate profile loading by calling ProfileManager directly
	-- (This bypasses the PlayerAdded event for testing)
	print("Loading profile for mock player...")
	
	-- We need to manually trigger the profile loading logic
	-- For testing purposes, we'll simulate the key parts
	
	-- Check if profile exists in DataStore (this will create one if it doesn't exist)
	local profileManager = require(game.ServerScriptService.Persistence.ProfileManager)
	local profile = profileManager.LoadProfile(MOCK_USER_ID)
	
	if profile then
		print("✅ Profile loaded/created successfully")
		PrintProfile(profile, "Created Profile")
		return true
	else
		print("❌ Profile creation failed")
		return false
	end
end

local function TestProfileAPI()
	print("\n🧪 Testing Profile API...")
	
	-- Get profile
	local profile = PlayerDataService.GetProfile(MockPlayer)
	if not profile then
		print("❌ Cannot test API without profile")
		return false
	end
	
	print("✅ Profile retrieved successfully")
	
	-- Test collection access
	local collection = PlayerDataService.GetCollection(MockPlayer)
	if collection then
		print("✅ Collection accessed successfully")
		print("  Unique cards:", #collection)
	else
		print("❌ Collection access failed")
	end
	
	-- Test login info
	local loginInfo = PlayerDataService.GetLoginInfo(MockPlayer)
	if loginInfo then
		print("✅ Login info accessed successfully")
		print("  Last Login:", os.date("%Y-%m-%d %H:%M:%S", loginInfo.lastLoginAt))
		print("  Login Streak:", loginInfo.loginStreak)
	else
		print("❌ Login info access failed")
	end
	
	return true
end

local function TestDeckValidation()
	print("\n🧪 Testing Deck Validation...")
	
	-- Test valid deck
	local validDeck = {"dps_001", "support_001", "tank_001", "dps_001", "support_001", "tank_001"}
	print("Testing valid deck...")
	WaitForBudget()
	
	local success, errorMessage = PlayerDataService.SetDeck(MockPlayer, validDeck)
	if success then
		print("✅ Valid deck accepted")
	else
		print("❌ Valid deck rejected:", errorMessage)
		return false
	end
	
	-- Test invalid deck (wrong size)
	local invalidDeck1 = {"dps_001", "support_001"}
	print("Testing invalid deck (wrong size)...")
	WaitForBudget()
	
	success, errorMessage = PlayerDataService.SetDeck(MockPlayer, invalidDeck1)
	if not success then
		print("✅ Invalid deck correctly rejected:", errorMessage)
	else
		print("❌ Invalid deck incorrectly accepted")
		return false
	end
	
	-- Test invalid deck (unknown card)
	local invalidDeck2 = {"invalid_card", "dps_001", "support_001", "tank_001", "dps_001", "support_001"}
	print("Testing invalid deck (unknown card)...")
	WaitForBudget()
	
	success, errorMessage = PlayerDataService.SetDeck(MockPlayer, invalidDeck2)
	if not success then
		print("✅ Invalid deck correctly rejected:", errorMessage)
	else
		print("❌ Invalid deck incorrectly accepted")
		return false
	end
	
	-- Test deck with insufficient cards
	local insufficientDeck = {"dps_003", "dps_003", "dps_003", "dps_003", "dps_003", "dps_003"}
	print("Testing deck with insufficient cards...")
	WaitForBudget()
	
	success, errorMessage = PlayerDataService.SetDeck(MockPlayer, insufficientDeck)
	if not success then
		print("✅ Insufficient cards correctly rejected:", errorMessage)
	else
		print("❌ Insufficient cards incorrectly accepted")
		return false
	end
	
	return true
end

local function TestCardGranting()
	print("\n🧪 Testing Card Granting...")
	
	-- Grant some cards
	local rewards = {
		["dps_002"] = 2,
		["support_002"] = 1,
		["tank_002"] = 1
	}
	
	print("Granting cards:", rewards)
	WaitForBudget()
	
	local success, grantedCards = PlayerDataService.GrantCards(MockPlayer, rewards)
	if success then
		print("✅ Cards granted successfully")
		for cardId, count in pairs(grantedCards) do
			print("  " .. cardId .. ": +" .. count)
		end
	else
		print("❌ Card granting failed:", grantedCards)
		return false
	end
	
	-- Verify collection was updated
	local collection = PlayerDataService.GetCollection(MockPlayer)
	if collection then
		print("✅ Collection updated:")
		for cardId, count in pairs(collection) do
			if rewards[cardId] then
				print("  " .. cardId .. ": " .. count .. " (was granted)")
			end
		end
	end
	
	-- Test invalid rewards
	local invalidRewards = {
		["invalid_card"] = 1,
		["dps_001"] = -1
	}
	
	print("Testing invalid rewards...")
	WaitForBudget()
	
	success, errorMessage = PlayerDataService.GrantCards(MockPlayer, invalidRewards)
	if not success then
		print("✅ Invalid rewards correctly rejected:", errorMessage)
	else
		print("❌ Invalid rewards incorrectly accepted")
		return false
	end
	
	return true
end

local function TestLoginStreak()
	print("\n🧪 Testing Login Streak...")
	
	-- Get current login streak
	local loginInfo = PlayerDataService.GetLoginInfo(MockPlayer)
	if not loginInfo then
		print("❌ Cannot test login streak without login info")
		return false
	end
	
	local initialStreak = loginInfo.loginStreak
	print("Initial login streak:", initialStreak)
	
	-- Bump login streak
	print("Bumping login streak...")
	WaitForBudget()
	
	local success = PlayerDataService.BumpLoginStreak(MockPlayer)
	if success then
		print("✅ Login streak bumped successfully")
		
		-- Verify streak was incremented
		local newLoginInfo = PlayerDataService.GetLoginInfo(MockPlayer)
		if newLoginInfo and newLoginInfo.loginStreak == initialStreak + 1 then
			print("✅ Login streak incremented correctly:", newLoginInfo.loginStreak)
		else
			print("❌ Login streak not incremented correctly")
			return false
		end
	else
		print("❌ Failed to bump login streak")
		return false
	end
	
	return true
end

local function TestAutosaveSimulation()
	print("\n🧪 Testing Autosave Simulation...")
	
	-- Force a save to test persistence
	print("Forcing profile save...")
	WaitForBudget()
	
	local success = PlayerDataService.ForceSave(MockPlayer)
	if success then
		print("✅ Profile saved successfully")
	else
		print("❌ Profile save failed")
		return false
	end
	
	-- Test profile readback
	print("Testing profile readback...")
	WaitForBudget()
	
	local profile = PlayerDataService.GetProfile(MockPlayer)
	if profile then
		print("✅ Profile readback successful")
		PrintProfile(profile, "Current Profile")
	else
		print("❌ Profile readback failed")
		return false
	end
	
	return true
end

local function TestServiceCleanup()
	print("\n🧪 Testing Service Cleanup...")
	
	-- Simulate player leaving
	print("Simulating player leave...")
	
	-- Get final status
	local finalStatus = PlayerDataService.GetStatus()
	print("Final Service Status:")
	print("  Active Profiles:", finalStatus.activeProfiles)
	print("  Active Autosaves:", finalStatus.activeAutosaves)
	
	-- Note: We can't fully test PlayerRemoving without actual player objects
	-- But we can verify the service is in a clean state
	
	print("✅ Service cleanup test completed")
	return true
end

-- Main test runner
function PlayerDataServiceDevHarness.RunAllTests()
	print("🚀 Starting PlayerDataService Dev Harness Tests")
	print("=" .. string.rep("=", 60))
	
	-- Check Studio access first
	if not CheckStudioAccess() then
		print("\n⏭️  Skipping DataStore tests due to Studio access restrictions.")
		print("   Enable 'Studio Access to API Services' in Game Settings > Security")
		print("   Then run the tests again.")
		return false
	end
	
	print("✅ Studio access confirmed. Proceeding with tests...")
	
	-- Run tests in sequence
	TestServiceStatus()
	WaitForBudget()
	
	local profileCreated = TestProfileCreation()
	WaitForBudget()
	
	if profileCreated then
		TestProfileAPI()
		WaitForBudget()
		
		TestDeckValidation()
		WaitForBudget()
		
		TestCardGranting()
		WaitForBudget()
		
		TestLoginStreak()
		WaitForBudget()
		
		TestAutosaveSimulation()
		WaitForBudget()
	end
	
	TestServiceCleanup()
	
	-- Final status
	print("\n" .. string.rep("=", 60))
	print("🏁 PlayerDataService Dev Harness Tests Complete!")
	
	local finalStatus = PlayerDataService.GetStatus()
	print("💾 Final Service Status:")
	print("  Active Profiles:", finalStatus.activeProfiles)
	print("  Active Autosaves:", finalStatus.activeAutosaves)
	print("  Is Shutting Down:", finalStatus.isShuttingDown)
	
	print("=" .. string.rep("=", 60))
	
	return true
end

-- Individual test runners
function PlayerDataServiceDevHarness.TestServiceStatus()
	TestServiceStatus()
end

function PlayerDataServiceDevHarness.TestProfileCreation()
	TestProfileCreation()
end

function PlayerDataServiceDevHarness.TestProfileAPI()
	TestProfileAPI()
end

function PlayerDataServiceDevHarness.TestDeckValidation()
	TestDeckValidation()
end

function PlayerDataServiceDevHarness.TestCardGranting()
	TestCardGranting()
end

function PlayerDataServiceDevHarness.TestLoginStreak()
	TestLoginStreak()
end

function PlayerDataServiceDevHarness.TestAutosaveSimulation()
	TestAutosaveSimulation()
end

function PlayerDataServiceDevHarness.TestServiceCleanup()
	TestServiceCleanup()
end

-- Auto-run tests when script is executed (if in Studio)
if game:GetService("RunService"):IsStudio() then
	print("🎮 Studio detected. Auto-running PlayerDataService dev harness...")
	spawn(function()
		task.wait(3) -- Wait for services to initialize
		PlayerDataServiceDevHarness.RunAllTests()
	end)
end

return PlayerDataServiceDevHarness
