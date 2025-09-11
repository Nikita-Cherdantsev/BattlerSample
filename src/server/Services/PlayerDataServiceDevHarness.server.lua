-- PlayerDataServiceDevHarness.server.lua
-- Development-only testing harness for PlayerDataService
-- Run this in Studio to test the complete player lifecycle and API

local PlayerDataServiceDevHarness = {}

-- Services
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

-- Modules
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

-- Configuration
local TEST_DELAY = 3 -- Seconds between operations to respect Studio budgets
local MOCK_PLAYER_NAME = "PDS_TestPlayer"
local MOCK_USER_ID = 999998 + math.floor(os.time() % 1000) -- Ensures unique ID each test run

-- Mock player for testing
local MockPlayer = {}
MockPlayer.Name = MOCK_PLAYER_NAME
MockPlayer.UserId = MOCK_USER_ID

-- Utility functions
local function LogInfo(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("[PDSHarness] %s", formattedMessage))
end

local function LogSuccess(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("✅ [PDSHarness] %s", formattedMessage))
end

local function LogError(message, ...)
	local formattedMessage = string.format(message, ...)
	warn(string.format("❌ [PDSHarness] %s", formattedMessage))
end

local function LogWarning(message, ...)
	local formattedMessage = string.format(message, ...)
	warn(string.format("⚠️ [PDSHarness] %s", formattedMessage))
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

local function assertDelta(cardId, expectedDelta, currentCount, baselineCounts)
	local base = baselineCounts[cardId] or 0
	local gotDelta = currentCount - base
	if gotDelta ~= expectedDelta then
		LogError("  %s: +%d  ❌ Count mismatch. Expected: %d, Got: %d",
			cardId, gotDelta, expectedDelta, gotDelta)
		return false
	end
	LogInfo("  %s: +%d  ✅", cardId, gotDelta)
	return true
end

-- Test state tracking
local testBaseline = {} -- Track baseline values for delta checks

-- Test functions
local function TestServiceStatus()
	LogInfo("🧪 Testing Service Status...")
	
	local status = PlayerDataService.GetStatus()
	LogSuccess("Service Status:")
	LogInfo("  Active Profiles: %d", status.activeProfiles)
	LogInfo("  Active Autosaves: %d", status.activeAutosaves)
	LogInfo("  Is Shutting Down: %s", tostring(status.isShuttingDown))
	LogInfo("  Autosave Interval: %d seconds", status.autosaveInterval)
end

local function TestProfileCreation()
	LogInfo("🧪 Testing Profile Creation...")
	LogInfo("Using unique test user ID: %d", MockPlayer.UserId)
	
	-- Clear any existing test data
	PlayerDataService.ClearCache(MockPlayer.UserId)
	LogInfo("Cleared existing test data for: %d", MockPlayer.UserId)
	
	-- Simulate player join
	LogInfo("Simulating player join...")
	
	-- Get initial profile (should be nil)
	local initialProfile = PlayerDataService.GetProfile(MockPlayer)
	if not initialProfile then
		LogSuccess("Initial profile correctly nil")
	else
		LogError("Initial profile should be nil")
		return false
	end
	
	-- Use PlayerDataService to load the profile (this ensures proper cache management)
	LogInfo("Loading profile for mock player via PlayerDataService...")
	local profile = PlayerDataService.EnsureProfileLoaded(MockPlayer)
	
	if profile then
		LogSuccess("Profile loaded/created successfully")
		LogInfo("  Player ID: %s", profile.playerId)
		LogInfo("  Created: %s", os.date("%Y-%m-%d %H:%M:%S", profile.createdAt))
		-- Count collection size manually
		local collectionSize = 0
		for _ in pairs(profile.collection) do
			collectionSize = collectionSize + 1
		end
		LogInfo("  Collection size: %d", collectionSize)
		LogInfo("  Deck size: %d", #profile.deck)
		LogInfo("  Login streak: %d", profile.loginStreak or 0)
		
		-- Debug: Show what's actually in the collection (v2 format)
		LogInfo("  Starter collection contents:")
		for cardId, entry in pairs(profile.collection) do
			-- Handle v2 format: {count, level}
			local count = type(entry) == "table" and entry.count or entry
			local level = type(entry) == "table" and entry.level or 1
			LogInfo("    %s: %d (L%d)", cardId, count, level)
		end
		
		PrintProfile(profile, "Created Profile")
		return true
	else
		LogError("Profile creation failed")
		return false
	end
end

local function TestProfileAPI()
	LogInfo("🧪 Testing Profile API...")
	
	-- Ensure profile is loaded
	LogInfo("Ensuring profile is loaded...")
	local profile = PlayerDataService.EnsureProfileLoaded(MockPlayer)
	if not profile then
		LogError("Cannot test API without profile")
		return false
	end
	
	LogSuccess("Profile loaded successfully")
	
	-- Store baseline values for delta checks
	testBaseline.softCurrency = profile.currencies.soft
	testBaseline.loginStreak = profile.loginStreak
	-- Store baseline for all cards that will be granted
			local card500Entry = profile.collection["card_500"]
		testBaseline.card500Count = card500Entry and card500Entry.count or 0
	local card600Entry = profile.collection["card_600"]
	testBaseline.card600Count = card600Entry and card600Entry.count or 0
	local card700Entry = profile.collection["card_700"]
	testBaseline.card700Count = card700Entry and card700Entry.count or 0
	LogInfo("📊 Baseline values stored for delta checks")
	
	-- Test collection access
	local collection = PlayerDataService.GetCollection(MockPlayer)
	if collection then
		LogSuccess("Collection accessed successfully")
		-- Count unique card types
		local uniqueCards = 0
		for _ in pairs(collection) do
			uniqueCards = uniqueCards + 1
		end
		LogInfo("  Unique cards: %d", uniqueCards)
	else
		LogError("Collection access failed")
	end
	
	-- Test login info
	local loginInfo = PlayerDataService.GetLoginInfo(MockPlayer)
	if loginInfo then
		LogSuccess("Login info accessed successfully")
		LogInfo("  Last Login: %s", os.date("%Y-%m-%d %H:%M:%S", loginInfo.lastLoginAt))
		LogInfo("  Login Streak: %d", loginInfo.loginStreak)
	else
		LogError("Login info access failed")
	end
	
	return true
end

local function TestDeckValidation()
	LogInfo("🧪 Testing Deck Validation...")
	
	-- Test valid deck (v2: no duplicates allowed)
	local validDeck = {"card_100", "card_200", "card_300", "card_500", "card_600", "card_700"}
	LogInfo("Testing valid deck...")
	WaitForBudget()
	
	local success, errorMessage = PlayerDataService.SetDeck(MockPlayer, validDeck)
	if success then
		LogSuccess("Valid deck accepted")
	else
		LogError("Valid deck rejected: %s", errorMessage)
		return false
	end
	
	-- Test invalid deck (wrong size)
	local invalidDeck1 = {"card_100", "card_200"}
	LogInfo("Testing invalid deck (wrong size)...")
	WaitForBudget()
	
	success, errorMessage = PlayerDataService.SetDeck(MockPlayer, invalidDeck1)
	if not success then
		LogSuccess("Invalid deck correctly rejected: %s", errorMessage)
	else
		LogError("Invalid deck incorrectly accepted")
		return false
	end
	
	-- Test invalid deck (unknown card)
	local invalidDeck2 = {"invalid_card", "card_100", "card_200", "card_300", "card_500", "card_600"}
	LogInfo("Testing invalid deck (unknown card)...")
	WaitForBudget()
	
	success, errorMessage = PlayerDataService.SetDeck(MockPlayer, invalidDeck2)
	if not success then
		LogSuccess("Invalid deck correctly rejected: %s", errorMessage)
	else
		LogError("Invalid deck incorrectly accepted")
		return false
	end
	
	-- Test deck with insufficient cards
	local insufficientDeck = {"dps_003", "dps_003", "dps_003", "dps_003", "dps_003", "dps_003"}
	LogInfo("Testing deck with insufficient cards...")
	WaitForBudget()
	
	success, errorMessage = PlayerDataService.SetDeck(MockPlayer, insufficientDeck)
	if not success then
		LogSuccess("Insufficient cards correctly rejected: %s", errorMessage)
	else
		LogError("Insufficient cards incorrectly accepted")
		return false
	end
	
	return true
end

local function TestCardGranting()
	LogInfo("🧪 Testing Card Granting...")
	
	-- Clear cache and reload profile to get clean state
	PlayerDataService.ClearCache(MockPlayer.UserId)
	local profile = PlayerDataService.EnsureProfileLoaded(MockPlayer)
	if not profile then
		LogError("Cannot test card granting without profile")
		return false
	end
	
	-- Get current baseline from the fresh profile (v2 format)
	local 	baselineCounts = {
		["card_500"] = (profile.collection["card_500"] and profile.collection["card_500"].count) or 0,
		["card_600"] = (profile.collection["card_600"] and profile.collection["card_600"].count) or 0,
		["card_700"] = (profile.collection["card_700"] and profile.collection["card_700"].count) or 0
	}
	LogInfo("Baseline counts: card_500=%d, card_600=%d, card_700=%d", 
		baselineCounts["card_500"], baselineCounts["card_600"], baselineCounts["card_700"])
	
	-- Debug: Show what's in the collection before granting (v2 format)
	LogInfo("Collection before granting:")
	for cardId, entry in pairs(profile.collection) do
		local count = type(entry) == "table" and entry.count or entry
		local level = type(entry) == "table" and entry.level or 1
		LogInfo("  %s: %d (L%d)", cardId, count, level)
	end
	
	-- Grant some cards
	local rewards = {
		["card_500"] = 2,
		["card_600"] = 1,
		["card_700"] = 1
	}
	
	LogInfo("Granting cards: %s", table.concat({rewards["card_500"] .. "x card_500", rewards["card_600"] .. "x card_600", rewards["card_700"] .. "x card_700"}, ", "))
	WaitForBudget()
	
			local success, grantedCards = PlayerDataService.GrantCards(MockPlayer, rewards)
	if success then
		LogSuccess("Cards granted successfully")
		for cardId, count in pairs(grantedCards) do
			LogInfo("  %s: +%d", cardId, count)
		end
		
		-- Debug: Show what's in the collection immediately after granting (v2 format)
		profile = PlayerDataService.GetProfile(MockPlayer)
		LogInfo("Collection immediately after granting:")
		for cardId, entry in pairs(profile.collection) do
			local count = type(entry) == "table" and entry.count or entry
			local level = type(entry) == "table" and entry.level or 1
			LogInfo("  %s: %d (L%d)", cardId, count, level)
		end
		
		-- Force save and wait for persistence
		PlayerDataService.ForceSave(MockPlayer)
		WaitForBudget()
		
		-- Read fresh values after save
		profile = PlayerDataService.GetProfile(MockPlayer)
		local coll = profile.collection or {}
		
		-- Debug: Show what's in the collection after save (v2 format)
		LogInfo("Collection after save:")
		for cardId, entry in pairs(coll) do
			local count = type(entry) == "table" and entry.count or entry
			local level = type(entry) == "table" and entry.level or 1
			LogInfo("  %s: %d (L%d)", cardId, count, level)
		end
		
		-- Verify collection was updated using delta assertions (v2 format)
		LogSuccess("Collection updated:")
		local okAll = true
		local card700Count = (coll["card_700"] and coll["card_700"].count) or 0
		local card600Count = (coll["card_600"] and coll["card_600"].count) or 0
		local card500Count = (coll["card_500"] and coll["card_500"].count) or 0
		okAll = assertDelta("card_700", 1, card700Count, baselineCounts) and okAll
		okAll = assertDelta("card_600", 1, card600Count, baselineCounts) and okAll
		okAll = assertDelta("card_500", 2, card500Count, baselineCounts) and okAll
		
		if not okAll then
			LogError("Some card count assertions failed")
			return false
		end
	else
		LogError("Card granting failed: %s", grantedCards)
		return false
	end
	
	-- Test invalid rewards
	local invalidRewards = {
		["invalid_card"] = 1,
		["card_100"] = -1
	}
	
	LogInfo("Testing invalid rewards...")
	WaitForBudget()
	
	success, errorMessage = PlayerDataService.GrantCards(MockPlayer, invalidRewards)
	if not success then
		LogSuccess("Invalid rewards correctly rejected: %s", errorMessage)
	else
		LogError("Invalid rewards incorrectly accepted")
		return false
	end
	
	return true
end

local function TestLoginStreak()
	LogInfo("🧪 Testing Login Streak...")
	
	-- Clear any existing profile to get a clean state
	PlayerDataService.ClearCache(MockPlayer.UserId)
	
	-- Ensure profile is loaded fresh
	local profile = PlayerDataService.EnsureProfileLoaded(MockPlayer)
	if not profile then
		LogError("Cannot test login streak without profile")
		return false
	end
	
	-- Get current login streak
	local loginInfo = PlayerDataService.GetLoginInfo(MockPlayer)
	if not loginInfo then
		LogError("Cannot test login streak without login info")
		return false
	end
	
	local before = loginInfo.loginStreak or 0
	LogInfo("Initial login streak: %d", before)
	
	-- Debug: Show the profile's meta information
	local profile = PlayerDataService.GetProfile(MockPlayer)
	if profile and profile.meta then
		LogInfo("Profile meta info:")
		LogInfo("  lastStreakBumpDate: %s", profile.meta.lastStreakBumpDate or "nil")
		LogInfo("  profile created: %s", os.date("!%Y-%m-%d", profile.createdAt))
		LogInfo("  today (UTC): %s", os.date("!%Y-%m-%d"))
	else
		LogWarning("No profile or meta info found")
	end
	
	-- Bump login streak
	LogInfo("Bumping login streak...")
	WaitForBudget()
	
	local success, newStreak = PlayerDataService.BumpLoginStreak(MockPlayer)
	if success then
		LogSuccess("Login streak bumped successfully to: %d", newStreak)
		
		-- Force a save to ensure persistence
		PlayerDataService.ForceSave(MockPlayer)
		WaitForBudget()
		
		-- Verify streak was incremented by exactly 1
		local finalLoginInfo = PlayerDataService.GetLoginInfo(MockPlayer)
		local finalStreak = finalLoginInfo and finalLoginInfo.loginStreak or 0
		local delta = finalStreak - before
		
		LogInfo("Final verification: before=%d, after=%d, delta=%d", before, finalStreak, delta)
		
		if delta == 1 then
			LogSuccess("Login streak incremented correctly: %d (baseline +1)", finalStreak)
		else
			LogError("Login streak not incremented correctly. Expected: +1, Got: +%d", delta)
			LogError("This might be due to automatic daily login logic. Check if profile was created on a different day.")
			return false
		end
	else
		LogError("Failed to bump login streak")
		return false
	end
	
	return true
end

local function TestAutosaveSimulation()
	LogInfo("🧪 Testing Autosave Simulation...")
	
	-- Force a save to test persistence
	LogInfo("Forcing profile save...")
	WaitForBudget()
	
	local success = PlayerDataService.ForceSave(MockPlayer)
	if success then
		LogSuccess("Profile saved successfully")
	else
		LogError("Profile save failed")
		return false
	end
	
	-- Test profile readback
	LogInfo("Testing profile readback...")
	WaitForBudget()
	
	local profile = PlayerDataService.GetProfile(MockPlayer)
	if profile then
		LogSuccess("Profile readback successful")
		PrintProfile(profile, "Current Profile")
	else
		LogError("Profile readback failed")
		return false
	end
	
	return true
end

local function TestServiceCleanup()
	LogInfo("🧪 Testing Service Cleanup...")
	
	-- Simulate player leaving
	LogInfo("Simulating player leave...")
	
	-- Get final status
	local finalStatus = PlayerDataService.GetStatus()
	LogInfo("Final Service Status:")
	LogInfo("  Active Profiles: %d", finalStatus.activeProfiles)
	LogInfo("  Active Autosaves: %d", finalStatus.activeAutosaves)
	
	-- Note: We can't fully test PlayerRemoving without actual player objects
	-- But we can verify the service is in a clean state
	
	LogSuccess("Service cleanup test completed")
	return true
end

-- Main test runner
function PlayerDataServiceDevHarness.RunAllTests()
	LogInfo("🚀 Starting PlayerDataService Dev Harness Tests")
	LogInfo("🎯 Test User ID: %d (unique for this run)", MockPlayer.UserId)
	print("=" .. string.rep("=", 60))
	
	-- Check Studio access first
	if not CheckStudioAccess() then
		LogWarning("⏭️  Skipping DataStore tests due to Studio access restrictions.")
		LogInfo("   Enable 'Studio Access to API Services' in Game Settings > Security")
		LogInfo("   Then run the tests again.")
		return false
	end
	
	LogSuccess("Studio access confirmed. Proceeding with tests...")
	
	-- Clear any existing state before starting tests
	LogInfo("🧹 Clearing any existing test state...")
	PlayerDataService.ClearCache(MockPlayer.UserId)
	WaitForBudget()
	
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
	
	-- Clean up test data
	LogInfo("🧹 Cleaning up test data...")
	PlayerDataService.ClearCache(MockPlayer.UserId)
	LogSuccess("Test data cleaned up")
	
	-- Final status
	print("\n" .. string.rep("=", 60))
	LogInfo("🏁 PlayerDataService Dev Harness Tests Complete!")
	
	local finalStatus = PlayerDataService.GetStatus()
	LogInfo("💾 Final Service Status:")
	LogInfo("  Active Profiles: %d", finalStatus.activeProfiles)
	LogInfo("  Active Autosaves: %d", finalStatus.activeAutosaves)
	LogInfo("  Is Shutting Down: %s", tostring(finalStatus.isShuttingDown))
	
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
	LogInfo("🎮 Studio detected. Auto-running PlayerDataService dev harness...")
	local isRunning = false
	spawn(function()
		task.wait(8) -- Wait for services to initialize and other harnesses
		if not isRunning then
			isRunning = true
			LogInfo("🚀 Starting PlayerDataService dev harness (guard: %s)", tostring(isRunning))
			PlayerDataServiceDevHarness.RunAllTests()
			isRunning = false
			LogInfo("🏁 PlayerDataService dev harness completed (guard: %s)", tostring(isRunning))
		else
			LogWarning("⏭️  PlayerDataService dev harness already running, skipping...")
		end
	end)
end

return PlayerDataServiceDevHarness
