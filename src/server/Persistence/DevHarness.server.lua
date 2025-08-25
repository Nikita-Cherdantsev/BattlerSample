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
local MOCK_USER_ID = "dev_harness_test_user" -- Isolated test user ID
local TEST_DELAY = 2 -- Seconds between operations to respect Studio budgets

-- Utility functions
local function LogInfo(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("[PersistenceHarness] %s", formattedMessage))
end

local function LogSuccess(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("✅ [PersistenceHarness] %s", formattedMessage))
end

local function LogError(message, ...)
	local formattedMessage = string.format(message, ...)
	warn(string.format("❌ [PersistenceHarness] %s", formattedMessage))
end

local function LogWarning(message, ...)
	local formattedMessage = string.format(message, ...)
	warn(string.format("⚠️ [PersistenceHarness] %s", formattedMessage))
end

local function CheckStudioAccess()
	local success, _ = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	
	if not success then
		LogWarning("Studio Access to API Services is disabled!")
		LogInfo("   Enable it in Game Settings > Security to test DataStore operations.")
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
		for cardId, entry in pairs(profile.collection) do
			-- Handle v2 format: {count, level}
			local count = type(entry) == "table" and entry.count or entry
			local level = type(entry) == "table" and entry.level or 1
			print("  " .. cardId .. ": " .. count .. " (L" .. level .. ")")
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

-- Test state tracking
local testBaseline = {} -- Track baseline values for delta checks

-- Test functions
local function TestDataStoreWrapper()
	LogInfo("🧪 Testing DataStoreWrapper...")
	
	-- Test GetDataStore
	local success, dataStore = pcall(function()
		return DataStoreWrapper.GetDataStore("test_store")
	end)
	
	if success then
		LogSuccess("GetDataStore successful")
	else
		LogError("GetDataStore failed: %s", dataStore)
	end
	
	-- Test status
	local status = DataStoreWrapper.GetStatus()
	LogInfo("DataStoreWrapper Status: %d pending writes", status.pendingWrites)
end

local function TestProfileSchema()
	LogInfo("🧪 Testing ProfileSchema...")
	
	-- Test profile creation
	local profile = ProfileSchema.CreateProfile(MOCK_USER_ID)
	if profile then
		LogSuccess("Profile creation successful")
		
		-- Test validation
		local isValid, errorMessage = ProfileSchema.ValidateProfile(profile)
		if isValid then
			LogSuccess("Profile validation successful")
		else
			LogError("Profile validation failed: %s", errorMessage)
		end
		
		-- Test profile stats
		local stats = ProfileSchema.GetProfileStats(profile)
		if stats then
			LogSuccess("Profile stats generated: %d total cards", stats.totalCards)
		else
			LogError("Profile stats generation failed")
		end
	else
		LogError("Profile creation failed")
	end
end

local function TestProfileManager()
	LogInfo("🧪 Testing ProfileManager...")
	
	-- Clear any existing test data
	ProfileManager.ClearCache(MOCK_USER_ID)
	LogInfo("Cleared existing test data for: %s", MOCK_USER_ID)
	
	-- Test profile loading (should create new profile)
	LogInfo("Loading profile for user: %s", MOCK_USER_ID)
	local profile = ProfileManager.LoadProfile(MOCK_USER_ID)
	
	if profile then
		LogSuccess("Profile loaded/created successfully")
		PrintProfile(profile, "Initial Profile")
		
		-- Store baseline values for delta checks (v2 format)
		testBaseline.softCurrency = profile.currencies.soft
		testBaseline.loginStreak = profile.loginStreak
		local dps002Entry = profile.collection["dps_002"]
		testBaseline.dps002Count = dps002Entry and dps002Entry.count or 0
		LogInfo("📊 Baseline values stored for delta checks")
		
		-- Test profile stats
		local stats = ProfileManager.GetProfileStats(MOCK_USER_ID)
		if stats then
			LogInfo("📊 Profile Stats: %d unique cards, %d total cards", stats.uniqueCards, stats.totalCards)
		end
		
		-- Test cache status
		local cacheStatus = ProfileManager.GetCacheStatus()
		LogInfo("💾 Cache Status: %d cached profiles", cacheStatus.cachedProfiles)
		
		return profile
	else
		LogError("Profile loading failed")
		return nil
	end
end

local function TestProfileMutations(profile)
	if not profile then
		LogError("Cannot test mutations without profile")
		return
	end
	
	LogInfo("🧪 Testing Profile Mutations...")
	
	-- Test adding cards
	LogInfo("Adding cards to collection...")
	WaitForBudget()
	
	local success = ProfileManager.AddCardsToCollection(MOCK_USER_ID, "dps_002", 2)
	if success then
		LogSuccess("Added 2x dps_002 to collection")
	else
		LogError("Failed to add cards")
	end
	
	-- Add support_002 for deck update test
	WaitForBudget()
	success = ProfileManager.AddCardsToCollection(MOCK_USER_ID, "support_002", 1)
	if success then
		LogSuccess("Added 1x support_002 to collection")
	else
		LogError("Failed to add support_002")
	end
	
	-- Test adding currency
	LogInfo("Adding soft currency...")
	WaitForBudget()
	
	success = ProfileManager.AddCurrency(MOCK_USER_ID, "soft", 500)
	if success then
		LogSuccess("Added 500 soft currency")
	else
		LogError("Failed to add currency")
	end
	
	-- Test updating login streak
	LogInfo("Updating login streak...")
	WaitForBudget()
	
	success = ProfileManager.UpdateLoginStreak(MOCK_USER_ID, true)
	if success then
		LogSuccess("Incremented login streak")
	else
		LogError("Failed to update login streak")
	end
	
	-- Test deck update
	LogInfo("Updating deck...")
	WaitForBudget()
	
	local newDeck = {"dps_002", "support_002", "tank_001", "dps_001", "support_001", "tank_002"}
	success = ProfileManager.UpdateDeck(MOCK_USER_ID, newDeck)
	if success then
		LogSuccess("Updated deck successfully")
	else
		LogError("Failed to update deck")
	end
end

local function TestProfileReadback()
	LogInfo("🧪 Testing Profile Readback...")
	
	-- Force save and flush to ensure persistence
	LogInfo("Forcing save and flush...")
	ProfileManager.ForceSave(MOCK_USER_ID)
	DataStoreWrapper.Flush()
	WaitForBudget()
	
	-- Clear cache to force reload from DataStore
	ProfileManager.ClearCache(MOCK_USER_ID)
	LogInfo("Cleared profile cache")
	
	-- Reload profile
	WaitForBudget()
	LogInfo("Reloading profile from DataStore...")
	local reloadedProfile = ProfileManager.LoadProfile(MOCK_USER_ID)
	
	if reloadedProfile then
		LogSuccess("Profile reloaded successfully")
		PrintProfile(reloadedProfile, "Reloaded Profile")
		
		-- Compare with baseline values using deltas
		local expectedSoftCurrency = testBaseline.softCurrency + 500
		if reloadedProfile.currencies.soft == expectedSoftCurrency then
			LogSuccess("Soft currency persisted correctly: %d (baseline +500)", reloadedProfile.currencies.soft)
		else
			LogError("Soft currency mismatch. Expected: %d, Got: %d", expectedSoftCurrency, reloadedProfile.currencies.soft)
		end
		
		local expectedLoginStreak = testBaseline.loginStreak + 1
		if reloadedProfile.loginStreak == expectedLoginStreak then
			LogSuccess("Login streak persisted correctly: %d (baseline +1)", reloadedProfile.loginStreak)
		else
			LogError("Login streak mismatch. Expected: %d, Got: %d", expectedLoginStreak, reloadedProfile.loginStreak)
		end
		
		-- Check if new cards were added (v2 format)
		local expectedDps002Count = testBaseline.dps002Count + 2
		local dps002Entry = reloadedProfile.collection["dps_002"]
		local actualCount = dps002Entry and dps002Entry.count or 0
		if actualCount == expectedDps002Count then
			LogSuccess("New cards persisted correctly: dps_002 x%d (baseline +2)", expectedDps002Count)
		else
			LogError("New cards not persisted correctly. Expected: %d, Got: %d", expectedDps002Count, actualCount)
		end
		
	else
		LogError("Profile reload failed")
	end
end

local function TestErrorHandling()
	LogInfo("🧪 Testing Error Handling...")
	
	-- Test invalid deck update
	LogInfo("Testing invalid deck update...")
	WaitForBudget()
	
	local invalidDeck = {"invalid_card", "dps_001", "support_001", "tank_001", "dps_002", "support_002"}
	local success, errorMessage = ProfileManager.UpdateDeck(MOCK_USER_ID, invalidDeck)
	
	if not success then
		LogSuccess("Invalid deck correctly rejected: %s", errorMessage)
	else
		LogError("Invalid deck was incorrectly accepted")
	end
	
	-- Test deck with insufficient cards
	LogInfo("Testing deck with insufficient cards...")
	WaitForBudget()
	
	local insufficientDeck = {"dps_003", "dps_003", "dps_003", "dps_003", "dps_003", "dps_003"}
	success, errorMessage = ProfileManager.UpdateDeck(MOCK_USER_ID, insufficientDeck)
	
	if not success then
		LogSuccess("Insufficient cards correctly rejected: %s", errorMessage)
	else
		LogError("Insufficient cards was incorrectly accepted")
	end
end

-- Main test runner
function DevHarness.RunAllTests()
	LogInfo("🚀 Starting Persistence Dev Harness Tests")
	print("=" .. string.rep("=", 60))
	
	-- Check Studio access first
	if not CheckStudioAccess() then
		LogWarning("⏭️  Skipping DataStore tests due to Studio access restrictions.")
		LogInfo("   Enable 'Studio Access to API Services' in Game Settings > Security")
		LogInfo("   Then run the tests again.")
		return false
	end
	
	LogSuccess("Studio access confirmed. Proceeding with tests...")
	
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
	LogInfo("🏁 Dev Harness Tests Complete!")
	
	local cacheStatus = ProfileManager.GetCacheStatus()
	LogInfo("💾 Final Cache Status: %d cached profiles", cacheStatus.cachedProfiles)
	
	local dataStoreStatus = DataStoreWrapper.GetStatus()
	LogInfo("📊 DataStore Status: %d pending writes", dataStoreStatus.pendingWrites)
	
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
	LogInfo("🎮 Studio detected. Auto-running persistence dev harness...")
	spawn(function()
		task.wait(5) -- Wait for services to initialize and other harnesses
		DevHarness.RunAllTests()
	end)
end

return DevHarness
