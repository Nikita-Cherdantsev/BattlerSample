-- DevHarness.server.lua
-- Development-only testing harness for persistence system
-- Run this in Studio to test DataStore operations safely

local DevHarness = {}

-- Services
local DataStoreService = game:GetService("DataStoreService")

-- Modules
local DataStoreWrapper = require(script.Parent:WaitForChild("DataStoreWrapper"))
local ProfileSchema = require(script.Parent:WaitForChild("ProfileSchema"))
local ProfileManager = require(script.Parent:WaitForChild("ProfileManager"))

-- Configuration
local MOCK_USER_ID = "0" -- Test user ID
local TEST_DELAY = 2 -- Seconds between operations to respect Studio budgets

-- Utility functions
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

-- Test functions
local function TestDataStoreWrapper()
	print("\n🧪 Testing DataStoreWrapper...")
	
	-- Test GetDataStore
	local success, dataStore = pcall(function()
		return DataStoreWrapper.GetDataStore("test_store")
	end)
	
	if success then
		print("✅ GetDataStore successful")
	else
		print("❌ GetDataStore failed:", dataStore)
	end
	
	-- Test status
	local status = DataStoreWrapper.GetStatus()
	print("DataStoreWrapper Status:", status.pendingWrites, "pending writes")
end

local function TestProfileSchema()
	print("\n🧪 Testing ProfileSchema...")
	
	-- Test profile creation
	local profile = ProfileSchema.CreateProfile(MOCK_USER_ID)
	if profile then
		print("✅ Profile creation successful")
		
		-- Test validation
		local isValid, errorMessage = ProfileSchema.ValidateProfile(profile)
		if isValid then
			print("✅ Profile validation successful")
		else
			print("❌ Profile validation failed:", errorMessage)
		end
		
		-- Test profile stats
		local stats = ProfileSchema.GetProfileStats(profile)
		if stats then
			print("✅ Profile stats generated:", stats.totalCards, "total cards")
		else
			print("❌ Profile stats generation failed")
		end
	else
		print("❌ Profile creation failed")
	end
end

local function TestProfileManager()
	print("\n🧪 Testing ProfileManager...")
	
	-- Test profile loading (should create new profile)
	print("Loading profile for user:", MOCK_USER_ID)
	local profile = ProfileManager.LoadProfile(MOCK_USER_ID)
	
	if profile then
		print("✅ Profile loaded/created successfully")
		PrintProfile(profile, "Initial Profile")
		
		-- Test profile stats
		local stats = ProfileManager.GetProfileStats(MOCK_USER_ID)
		if stats then
			print("📊 Profile Stats:", stats.uniqueCards, "unique cards,", stats.totalCards, "total cards")
		end
		
		-- Test cache status
		local cacheStatus = ProfileManager.GetCacheStatus()
		print("💾 Cache Status:", cacheStatus.cachedProfiles, "cached profiles")
		
		return profile
	else
		print("❌ Profile loading failed")
		return nil
	end
end

local function TestProfileMutations(profile)
	if not profile then
		print("❌ Cannot test mutations without profile")
		return
	end
	
	print("\n🧪 Testing Profile Mutations...")
	
	-- Test adding cards
	print("Adding cards to collection...")
	WaitForBudget()
	
	local success = ProfileManager.AddCardsToCollection(MOCK_USER_ID, "dps_002", 2)
	if success then
		print("✅ Added 2x dps_002 to collection")
	else
		print("❌ Failed to add cards")
	end
	
	-- Test adding currency
	print("Adding soft currency...")
	WaitForBudget()
	
	success = ProfileManager.AddCurrency(MOCK_USER_ID, "soft", 500)
	if success then
		print("✅ Added 500 soft currency")
	else
		print("❌ Failed to add currency")
	end
	
	-- Test updating login streak
	print("Updating login streak...")
	WaitForBudget()
	
	success = ProfileManager.UpdateLoginStreak(MOCK_USER_ID, true)
	if success then
		print("✅ Incremented login streak")
	else
		print("❌ Failed to update login streak")
	end
	
	-- Test deck update
	print("Updating deck...")
	WaitForBudget()
	
	local newDeck = {"dps_002", "support_002", "tank_001", "dps_001", "support_001", "tank_001"}
	success = ProfileManager.UpdateDeck(MOCK_USER_ID, newDeck)
	if success then
		print("✅ Updated deck successfully")
	else
		print("❌ Failed to update deck")
	end
end

local function TestProfileReadback()
	print("\n🧪 Testing Profile Readback...")
	
	-- Clear cache to force reload from DataStore
	ProfileManager.ClearCache(MOCK_USER_ID)
	print("Cleared profile cache")
	
	-- Reload profile
	WaitForBudget()
	print("Reloading profile from DataStore...")
	local reloadedProfile = ProfileManager.LoadProfile(MOCK_USER_ID)
	
	if reloadedProfile then
		print("✅ Profile reloaded successfully")
		PrintProfile(reloadedProfile, "Reloaded Profile")
		
		-- Compare with expected values
		local expectedSoftCurrency = 1500 -- 1000 (default) + 500 (added)
		if reloadedProfile.currencies.soft == expectedSoftCurrency then
			print("✅ Soft currency persisted correctly:", reloadedProfile.currencies.soft)
		else
			print("❌ Soft currency mismatch. Expected:", expectedSoftCurrency, "Got:", reloadedProfile.currencies.soft)
		end
		
		local expectedLoginStreak = 1 -- 0 (default) + 1 (incremented)
		if reloadedProfile.loginStreak == expectedLoginStreak then
			print("✅ Login streak persisted correctly:", reloadedProfile.loginStreak)
		else
			print("❌ Login streak mismatch. Expected:", expectedLoginStreak, "Got:", reloadedProfile.loginStreak)
		end
		
		-- Check if new cards were added
		if reloadedProfile.collection["dps_002"] == 2 then
			print("✅ New cards persisted correctly: dps_002 x2")
		else
			print("❌ New cards not persisted correctly")
		end
		
	else
		print("❌ Profile reload failed")
	end
end

local function TestErrorHandling()
	print("\n🧪 Testing Error Handling...")
	
	-- Test invalid deck update
	print("Testing invalid deck update...")
	WaitForBudget()
	
	local invalidDeck = {"invalid_card", "dps_001", "support_001", "tank_001", "dps_001", "support_001"}
	local success, errorMessage = ProfileManager.UpdateDeck(MOCK_USER_ID, invalidDeck)
	
	if not success then
		print("✅ Invalid deck correctly rejected:", errorMessage)
	else
		print("❌ Invalid deck was incorrectly accepted")
	end
	
	-- Test deck with insufficient cards
	print("Testing deck with insufficient cards...")
	WaitForBudget()
	
	local insufficientDeck = {"dps_003", "dps_003", "dps_003", "dps_003", "dps_003", "dps_003"}
	success, errorMessage = ProfileManager.UpdateDeck(MOCK_USER_ID, insufficientDeck)
	
	if not success then
		print("✅ Insufficient cards correctly rejected:", errorMessage)
	else
		print("❌ Insufficient cards was incorrectly accepted")
	end
end

-- Main test runner
function DevHarness.RunAllTests()
	print("🚀 Starting Persistence Dev Harness Tests")
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
	TestDataStoreWrapper()
	WaitForBudget()
	
	TestProfileSchema()
	WaitForBudget()
	
	local profile = TestProfileManager()
	WaitForBudget()
	
	if profile then
		TestProfileMutations(profile)
		WaitForBudget()
		
		TestProfileReadback()
		WaitForBudget()
		
		TestErrorHandling()
	end
	
	-- Final status
	print("\n" .. string.rep("=", 60))
	print("🏁 Dev Harness Tests Complete!")
	
	local cacheStatus = ProfileManager.GetCacheStatus()
	print("💾 Final Cache Status:", cacheStatus.cachedProfiles, "cached profiles")
	
	local dataStoreStatus = DataStoreWrapper.GetStatus()
	print("📊 DataStore Status:", dataStoreStatus.pendingWrites, "pending writes")
	
	print("=" .. string.rep("=", 60))
	
	return true
end

-- Individual test runners
function DevHarness.TestDataStoreWrapper()
	TestDataStoreWrapper()
end

function DevHarness.TestProfileSchema()
	TestProfileSchema()
end

function DevHarness.TestProfileManager()
	TestProfileManager()
end

function DevHarness.TestProfileMutations()
	local profile = ProfileManager.GetCachedProfile(MOCK_USER_ID)
	TestProfileMutations(profile)
end

function DevHarness.TestProfileReadback()
	TestProfileReadback()
end

function DevHarness.TestErrorHandling()
	TestErrorHandling()
end

-- Auto-run tests when script is executed (if in Studio)
if game:GetService("RunService"):IsStudio() then
	print("🎮 Studio detected. Auto-running persistence dev harness...")
	spawn(function()
		task.wait(2) -- Wait for services to initialize
		DevHarness.RunAllTests()
	end)
end

return DevHarness
