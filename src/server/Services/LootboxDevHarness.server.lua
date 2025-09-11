--[[
	Lootbox Development Harness
	
	Comprehensive self-checks for the lootbox system.
	Tests all invariants, overflow flow, and reward math.
]]

local LootboxDevHarness = {}

local LootboxService = require(script.Parent.LootboxService)
local BoxTypes = require(game.ReplicatedStorage.Modules.Loot.BoxTypes)
local BoxDropTables = require(game.ReplicatedStorage.Modules.Loot.BoxDropTables)
local BoxValidator = require(game.ReplicatedStorage.Modules.Loot.BoxValidator)
local ShopPacksCatalog = require(game.ReplicatedStorage.Modules.Shop.ShopPacksCatalog)
local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)

-- Test results tracking
local testResults = {}

-- Test 1: Capacity and Pending Flow
local function TestCapacityAndPending()
	print("\n=== Testing Capacity and Pending Flow ===")
	
	local testUserId = "test_user_capacity"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Test adding boxes up to capacity
	for i = 1, 4 do
		local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.UNCOMMON, "test")
		if result.ok then
			print("✅ Added box " .. i .. " to slot")
		else
			print("❌ Failed to add box " .. i .. ": " .. (result.error or "unknown"))
			testResults.capacityAndPending = false
			return
		end
	end
	
	-- Test 5th box goes to pending
	local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.RARE, "test")
	if not result.ok and result.error == LootboxService.ErrorCodes.BOX_CAPACITY_FULL_PENDING and result.pending then
		print("✅ 5th box correctly set as pending")
	else
		print("❌ 5th box handling failed:", result.error)
		testResults.capacityAndPending = false
		return
	end
	
	-- Test 6th box while pending requires decision
	local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.EPIC, "test")
	if not result.ok and result.error == LootboxService.ErrorCodes.BOX_DECISION_REQUIRED then
		print("✅ 6th box correctly requires decision")
	else
		print("❌ 6th box handling failed:", result.error)
		testResults.capacityAndPending = false
		return
	end
	
	testResults.capacityAndPending = true
end

-- Test 2: Resolve Pending Discard
local function TestResolvePendingDiscard()
	print("\n=== Testing Resolve Pending Discard ===")
	
	local testUserId = "test_user_discard"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Fill capacity and create pending
	for i = 1, 4 do
		LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.UNCOMMON, "test")
	end
	local pendingResult = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.RARE, "test")
	
	if not pendingResult.pending then
		print("❌ Failed to create pending box")
		testResults.resolvePendingDiscard = false
		return
	end
	
	-- Discard pending
	local result = LootboxService.ResolvePendingDiscard(testUserId)
	if result.ok then
		print("✅ Successfully discarded pending box")
		
		-- Verify we can add another box
		local addResult = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.EPIC, "test")
		if addResult.ok then
			print("✅ Can add new box after discard")
		else
			print("❌ Cannot add new box after discard:", addResult.error)
			testResults.resolvePendingDiscard = false
			return
		end
	else
		print("❌ Failed to discard pending box:", result.error)
		testResults.resolvePendingDiscard = false
		return
	end
	
	testResults.resolvePendingDiscard = true
end

-- Test 3: Resolve Pending Replace
local function TestResolvePendingReplace()
	print("\n=== Testing Resolve Pending Replace ===")
	
	local testUserId = "test_user_replace"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Fill capacity and create pending
	for i = 1, 4 do
		LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.UNCOMMON, "test")
	end
	local pendingResult = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.RARE, "test")
	
	if not pendingResult.pending then
		print("❌ Failed to create pending box")
		testResults.resolvePendingReplace = false
		return
	end
	
	-- Replace slot 2
	local result = LootboxService.ResolvePendingReplace(testUserId, 2)
	if result.ok then
		print("✅ Successfully replaced slot 2 with pending box")
		
		-- Verify pending is cleared
		local addResult = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.EPIC, "test")
		if addResult.pending then
			print("✅ Pending cleared, new box goes to pending")
		else
			print("❌ Pending not cleared properly")
			testResults.resolvePendingReplace = false
			return
		end
	else
		print("❌ Failed to replace pending box:", result.error)
		testResults.resolvePendingReplace = false
		return
	end
	
	testResults.resolvePendingReplace = true
end

-- Test 4: Start Unlock
local function TestStartUnlock()
	print("\n=== Testing Start Unlock ===")
	
	local testUserId = "test_user_unlock"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Add a box
	local addResult = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.UNCOMMON, "test")
	if not addResult.ok then
		print("❌ Failed to add box for unlock test")
		testResults.startUnlock = false
		return
	end
	
	-- Start unlocking
	local result = LootboxService.StartUnlock(testUserId, 1, os.time())
	if result.ok then
		print("✅ Successfully started unlock")
		
		-- Try to start another unlock (should fail)
		local addResult2 = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.RARE, "test")
		if addResult2.ok then
			local result2 = LootboxService.StartUnlock(testUserId, 2, os.time())
			if not result2.ok and result2.error == LootboxService.ErrorCodes.BOX_ALREADY_UNLOCKING then
				print("✅ Correctly rejected second unlock")
			else
				print("❌ Failed to reject second unlock:", result2.error)
				testResults.startUnlock = false
				return
			end
		end
	else
		print("❌ Failed to start unlock:", result.error)
		testResults.startUnlock = false
		return
	end
	
	testResults.startUnlock = true
end

-- Test 5: Complete Unlock
local function TestCompleteUnlock()
	print("\n=== Testing Complete Unlock ===")
	
	local testUserId = "test_user_complete"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Add a box and start unlocking
	local addResult = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.UNCOMMON, "test")
	if not addResult.ok then
		print("❌ Failed to add box for complete test")
		testResults.completeUnlock = false
		return
	end
	
	local startResult = LootboxService.StartUnlock(testUserId, 1, os.time())
	if not startResult.ok then
		print("❌ Failed to start unlock for complete test")
		testResults.completeUnlock = false
		return
	end
	
	-- Try to complete before time (should fail)
	local result = LootboxService.CompleteUnlock(testUserId, 1, os.time())
	if not result.ok and result.error == LootboxService.ErrorCodes.BOX_TIME_NOT_REACHED then
		print("✅ Correctly rejected early completion")
	else
		print("❌ Failed to reject early completion:", result.error)
		testResults.completeUnlock = false
		return
	end
	
	-- Complete after time
	local futureTime = os.time() + BoxTypes.GetDuration(BoxTypes.BoxRarity.UNCOMMON) + 1
	local result2 = LootboxService.CompleteUnlock(testUserId, 1, futureTime)
	if result2.ok and result2.rewards then
		print("✅ Successfully completed unlock with rewards")
		print("  Soft currency:", result2.rewards.softDelta)
		print("  Hard currency:", result2.rewards.hardDelta)
		print("  Card:", result2.rewards.card.cardId, "x" .. result2.rewards.card.copies)
	else
		print("❌ Failed to complete unlock:", result2.error)
		testResults.completeUnlock = false
		return
	end
	
	testResults.completeUnlock = true
end

-- Test 6: Open Now
local function TestOpenNow()
	print("\n=== Testing Open Now ===")
	
	local testUserId = "test_user_opennow"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Add a box
	local addResult = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.UNCOMMON, "test")
	if not addResult.ok then
		print("❌ Failed to add box for open now test")
		testResults.openNow = false
		return
	end
	
	-- Give player hard currency
	ProfileManager.UpdateProfile(testUserId, function(profile)
		profile.currencies.hard = 100
		return profile
	end)
	
	-- Open instantly
	local result = LootboxService.OpenNow(testUserId, 1, os.time())
	if result.ok and result.rewards and result.instantCost then
		print("✅ Successfully opened instantly")
		print("  Cost:", result.instantCost, "hard currency")
		print("  Soft currency:", result.rewards.softDelta)
		print("  Hard currency:", result.rewards.hardDelta)
		print("  Card:", result.rewards.card.cardId, "x" .. result.rewards.card.copies)
	else
		print("❌ Failed to open instantly:", result.error)
		testResults.openNow = false
		return
	end
	
	testResults.openNow = true
end

-- Test 7: Rewards Validity
local function TestRewardsValidity()
	print("\n=== Testing Rewards Validity ===")
	
	-- Test drop table probabilities
	local isValid = BoxDropTables.ValidateProbabilities()
	if isValid then
		print("✅ Drop table probabilities are valid")
	else
		print("❌ Drop table probabilities are invalid")
		testResults.rewardsValidity = false
		return
	end
	
	-- Test reward ranges
	for rarity, _ in pairs(BoxTypes.BoxRarity) do
		local table = BoxDropTables.GetTable(BoxTypes.BoxRarity[rarity])
		
		-- Check soft range
		if table.softRange.min >= table.softRange.max then
			print("❌ Invalid soft range for " .. rarity)
			testResults.rewardsValidity = false
			return
		end
		
		-- Check character rewards
		for _, reward in ipairs(table.characterRewards) do
			if reward.copiesRange.min > reward.copiesRange.max then
				print("❌ Invalid copies range for " .. rarity .. " -> " .. reward.rarity)
				testResults.rewardsValidity = false
				return
			end
		end
	end
	
	print("✅ All reward ranges are valid")
	testResults.rewardsValidity = true
end

-- Test 8: Validator Invariants
local function TestValidatorInvariants()
	print("\n=== Testing Validator Invariants ===")
	
	-- Test valid lootbox
	local validBox = {
		id = "test_box",
		rarity = BoxTypes.BoxRarity.UNCOMMON,
		state = BoxTypes.BoxRarity.IDLE,
		seed = 12345
	}
	
	local isValid, errorMsg = BoxValidator.ValidateBox(validBox)
	if isValid then
		print("✅ Valid box passes validation")
	else
		print("❌ Valid box failed validation:", errorMsg)
		testResults.validatorInvariants = false
		return
	end
	
	-- Test invalid box
	local invalidBox = {
		id = "test_box",
		rarity = "invalid",
		state = BoxTypes.BoxRarity.IDLE,
		seed = 12345
	}
	
	local isValid2, errorMsg2 = BoxValidator.ValidateBox(invalidBox)
	if not isValid2 then
		print("✅ Invalid box correctly rejected:", errorMsg2)
	else
		print("❌ Invalid box incorrectly accepted")
		testResults.validatorInvariants = false
		return
	end
	
	testResults.validatorInvariants = true
end

-- Test 9: Shop Packs Catalog
local function TestShopPacksCatalog()
	print("\n=== Testing Shop Packs Catalog ===")
	
	-- Test getting all packs
	local packs = ShopPacksCatalog.AllPacks()
	if #packs == 6 then
		print("✅ All 6 packs retrieved")
	else
		print("❌ Expected 6 packs, got", #packs)
		testResults.shopPacksCatalog = false
		return
	end
	
	-- Test pack validation
	local validPack = ShopPacksCatalog.GetPack("M")
	if validPack and validPack.hardAmount == 330 and validPack.robuxPrice == 100 then
		print("✅ Pack M retrieved correctly")
	else
		print("❌ Pack M retrieval failed")
		testResults.shopPacksCatalog = false
		return
	end
	
	-- Test invalid pack
	local invalidPack = ShopPacksCatalog.GetPack("INVALID")
	if not invalidPack then
		print("✅ Invalid pack correctly rejected")
	else
		print("❌ Invalid pack incorrectly accepted")
		testResults.shopPacksCatalog = false
		return
	end
	
	testResults.shopPacksCatalog = true
end

-- Main test runner
function LootboxDevHarness.RunAllTests()
	print("🎁 Starting Lootbox System Tests...")
	
	-- Reset test results
	testResults = {}
	
	-- Run all tests
	TestCapacityAndPending()
	TestResolvePendingDiscard()
	TestResolvePendingReplace()
	TestStartUnlock()
	TestCompleteUnlock()
	TestOpenNow()
	TestRewardsValidity()
	TestValidatorInvariants()
	TestShopPacksCatalog()
	
	-- Summary
	print("\n==================================")
	print("📊 Lootbox Test Results Summary:")
	
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
	
	print("\n🎯 Overall:", passedTests .. "/" .. totalTests, "tests passed")
	
	if passedTests == totalTests then
		print("🎉 All lootbox tests passed!")
	else
		print("⚠️  Some lootbox tests failed!")
	end
	
	-- Clean up test profiles
	local testUsers = {
		"test_user_capacity",
		"test_user_discard", 
		"test_user_replace",
		"test_user_unlock",
		"test_user_complete",
		"test_user_opennow"
	}
	
	for _, userId in ipairs(testUsers) do
		ProfileManager.DeleteProfile(userId)
	end
	
	return passedTests == totalTests
end

return LootboxDevHarness
