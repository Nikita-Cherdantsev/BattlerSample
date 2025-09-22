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

-- Test 9: RequestAddBox Network Integration
local function TestRequestAddBoxNetwork()
	print("\n=== Testing RequestAddBox Network Integration ===")
	
	local testUserId = "test_user_network_add"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Test valid rarity (case-insensitive)
	local result1 = LootboxService.TryAddBox(testUserId, "epic", "network_test")
	if result1.ok then
		print("✅ Epic rarity (lowercase) accepted")
	else
		print("❌ Epic rarity (lowercase) failed:", result1.error)
		testResults.requestAddBoxNetwork = false
		return
	end
	
	-- Test valid rarity (uppercase)
	local result2 = LootboxService.TryAddBox(testUserId, "RARE", "network_test")
	if result2.ok then
		print("✅ Rare rarity (uppercase) accepted")
	else
		print("❌ Rare rarity (uppercase) failed:", result2.error)
		testResults.requestAddBoxNetwork = false
		return
	end
	
	-- Test invalid rarity
	local result3 = LootboxService.TryAddBox(testUserId, "common", "network_test")
	if not result3.ok and result3.error == LootboxService.ErrorCodes.INVALID_RARITY then
		print("✅ Invalid rarity correctly rejected")
	else
		print("❌ Invalid rarity should have been rejected:", result3.error)
		testResults.requestAddBoxNetwork = false
		return
	end
	
	-- Test invalid rarity (case variations)
	local result4 = LootboxService.TryAddBox(testUserId, "COMMON", "network_test")
	if not result4.ok and result4.error == LootboxService.ErrorCodes.INVALID_RARITY then
		print("✅ Invalid rarity (uppercase) correctly rejected")
	else
		print("❌ Invalid rarity (uppercase) should have been rejected:", result4.error)
		testResults.requestAddBoxNetwork = false
		return
	end
	
	testResults.requestAddBoxNetwork = true
	print("✅ RequestAddBox network integration test passed")
end

-- Test 10: Pending Discard Flow
local function TestPendingDiscardFlow()
	print("\n=== Testing Pending Discard Flow ===")
	
	local testUserId = "test_user_pending_discard"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Fill to capacity (4 boxes)
	for i = 1, 4 do
		local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.UNCOMMON, "test")
		if not result.ok then
			print("❌ Failed to add box " .. i .. ": " .. (result.error or "unknown"))
			testResults.pendingDiscardFlow = false
			return
		end
	end
	
	-- Add 5th box (should go to pending)
	local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.RARE, "test")
	if not result.ok and result.error == LootboxService.ErrorCodes.BOX_CAPACITY_FULL_PENDING and result.pending then
		print("✅ 5th box correctly set as pending")
	else
		print("❌ 5th box handling failed:", result.error)
		testResults.pendingDiscardFlow = false
		return
	end
	
	-- Verify profile state before discard
	local profile = ProfileManager.GetProfile(testUserId)
	if not profile then
		print("❌ Failed to get profile")
		testResults.pendingDiscardFlow = false
		return
	end
	
	local lootCount = #(profile.lootboxes or {})
	local hasPending = profile.pendingLootbox ~= nil
	
	if lootCount ~= 4 then
		print("❌ Expected 4 lootboxes, got " .. lootCount)
		testResults.pendingDiscardFlow = false
		return
	end
	
	if not hasPending then
		print("❌ Expected pending lootbox")
		testResults.pendingDiscardFlow = false
		return
	end
	
	-- Test discard pending
	local discardResult = LootboxService.ResolvePendingDiscard(testUserId)
	if not discardResult.ok then
		print("❌ Discard pending failed:", discardResult.error)
		testResults.pendingDiscardFlow = false
		return
	end
	
	-- Verify profile state after discard
	local afterProfile = ProfileManager.GetProfile(testUserId)
	if not afterProfile then
		print("❌ Failed to get profile after discard")
		testResults.pendingDiscardFlow = false
		return
	end
	
	local afterLootCount = #(afterProfile.lootboxes or {})
	local afterHasPending = afterProfile.pendingLootbox ~= nil
	
	if afterLootCount ~= 4 then
		print("❌ Expected 4 lootboxes after discard, got " .. afterLootCount)
		testResults.pendingDiscardFlow = false
		return
	end
	
	if afterHasPending then
		print("❌ Expected no pending lootbox after discard")
		testResults.pendingDiscardFlow = false
		return
	end
	
	-- Verify profile invariants are preserved
	if not afterProfile.playerId or not afterProfile.createdAt then
		print("❌ Profile invariants corrupted (playerId or createdAt missing)")
		testResults.pendingDiscardFlow = false
		return
	end
	
	testResults.pendingDiscardFlow = true
	print("✅ Pending discard flow test passed")
end

-- Test 11: Pending Replace Flow
local function TestPendingReplaceFlow()
	print("\n=== Testing Pending Replace Flow ===")
	
	local testUserId = "test_user_pending_replace"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Fill to capacity (4 boxes)
	for i = 1, 4 do
		local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.UNCOMMON, "test")
		if not result.ok then
			print("❌ Failed to add box " .. i .. ": " .. (result.error or "unknown"))
			testResults.pendingReplaceFlow = false
			return
		end
	end
	
	-- Add 5th box (should go to pending)
	local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.RARE, "test")
	if not result.ok and result.error == LootboxService.ErrorCodes.BOX_CAPACITY_FULL_PENDING and result.pending then
		print("✅ 5th box correctly set as pending")
	else
		print("❌ 5th box handling failed:", result.error)
		testResults.pendingReplaceFlow = false
		return
	end
	
	-- Test replace pending (replace slot 1)
	local replaceResult = LootboxService.ResolvePendingReplace(testUserId, 1)
	if not replaceResult.ok then
		print("❌ Replace pending failed:", replaceResult.error)
		testResults.pendingReplaceFlow = false
		return
	end
	
	-- Verify profile state after replace
	local afterProfile = ProfileManager.GetProfile(testUserId)
	if not afterProfile then
		print("❌ Failed to get profile after replace")
		testResults.pendingReplaceFlow = false
		return
	end
	
	local afterLootCount = #(afterProfile.lootboxes or {})
	local afterHasPending = afterProfile.pendingLootbox ~= nil
	
	if afterLootCount ~= 4 then
		print("❌ Expected 4 lootboxes after replace, got " .. afterLootCount)
		testResults.pendingReplaceFlow = false
		return
	end
	
	if afterHasPending then
		print("❌ Expected no pending lootbox after replace")
		testResults.pendingReplaceFlow = false
		return
	end
	
	-- Verify slot 1 was replaced with the pending box
	local slot1Box = afterProfile.lootboxes[1]
	if not slot1Box or slot1Box.rarity ~= BoxTypes.BoxRarity.RARE or slot1Box.state ~= BoxTypes.BoxState.IDLE then
		print("❌ Slot 1 not properly replaced with pending box")
		testResults.pendingReplaceFlow = false
		return
	end
	
	-- Verify profile invariants are preserved
	if not afterProfile.playerId or not afterProfile.createdAt then
		print("❌ Profile invariants corrupted (playerId or createdAt missing)")
		testResults.pendingReplaceFlow = false
		return
	end
	
	testResults.pendingReplaceFlow = true
	print("✅ Pending replace flow test passed")
end

-- Test 12: Open Now Flow
local function TestOpenNowFlow()
	print("\n=== Testing Open Now Flow ===")
	
	local testUserId = "test_user_open_now"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Add a box
	local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.EPIC, "test")
	if not result.ok then
		print("❌ Failed to add box:", result.error)
		testResults.openNowFlow = false
		return
	end
	
	-- Verify box is in Idle state
	local profile = ProfileManager.GetProfile(testUserId)
	if not profile then
		print("❌ Failed to get profile")
		testResults.openNowFlow = false
		return
	end
	
	local lootbox = profile.lootboxes[1]
	if not lootbox or lootbox.state ~= BoxTypes.BoxState.IDLE then
		print("❌ Box not in Idle state")
		testResults.openNowFlow = false
		return
	end
	
	-- Test open now
	local openResult = LootboxService.OpenNow(testUserId, 1, os.time())
	if not openResult.ok then
		print("❌ Open now failed:", openResult.error)
		testResults.openNowFlow = false
		return
	end
	
	-- Verify profile state after open
	local afterProfile = ProfileManager.GetProfile(testUserId)
	if not afterProfile then
		print("❌ Failed to get profile after open")
		testResults.openNowFlow = false
		return
	end
	
	local afterLootCount = #(afterProfile.lootboxes or {})
	
	if afterLootCount ~= 0 then
		print("❌ Expected 0 lootboxes after open, got " .. afterLootCount)
		testResults.openNowFlow = false
		return
	end
	
	-- Verify currencies were updated
	if not afterProfile.currencies or afterProfile.currencies.soft <= 0 then
		print("❌ Soft currency not properly updated")
		testResults.openNowFlow = false
		return
	end
	
	-- Verify profile invariants are preserved
	if not afterProfile.playerId or not afterProfile.createdAt then
		print("❌ Profile invariants corrupted (playerId or createdAt missing)")
		testResults.openNowFlow = false
		return
	end
	
	testResults.openNowFlow = true
	print("✅ Open now flow test passed")
end

-- Test 13: Pending Discard Network Integration
local function TestPendingDiscardNetwork()
	print("\n=== Testing Pending Discard Network Integration ===")
	
	local testUserId = "test_user_pending_discard_network"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Fill to capacity (4 boxes)
	for i = 1, 4 do
		local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.UNCOMMON, "test")
		if not result.ok then
			print("❌ Failed to add box " .. i .. ": " .. (result.error or "unknown"))
			testResults.pendingDiscardNetwork = false
			return
		end
	end
	
	-- Add 5th box (should go to pending)
	local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.RARE, "test")
	if not result.ok and result.error == LootboxService.ErrorCodes.BOX_CAPACITY_FULL_PENDING and result.pending then
		print("✅ 5th box correctly set as pending")
	else
		print("❌ 5th box handling failed:", result.error)
		testResults.pendingDiscardNetwork = false
		return
	end
	
	-- Verify pending state
	local profile = ProfileManager.GetCachedProfile(testUserId)
	if not profile or not profile.pendingLootbox then
		print("❌ Expected pending lootbox")
		testResults.pendingDiscardNetwork = false
		return
	end
	
	-- Test discard pending
	local discardResult = LootboxService.ResolvePendingDiscard(testUserId)
	if not discardResult.ok then
		print("❌ Discard pending failed:", discardResult.error)
		testResults.pendingDiscardNetwork = false
		return
	end
	
	-- Verify pending cleared
	local afterProfile = ProfileManager.GetCachedProfile(testUserId)
	if not afterProfile or afterProfile.pendingLootbox then
		print("❌ Expected no pending lootbox after discard")
		testResults.pendingDiscardNetwork = false
		return
	end
	
	-- Verify loot count unchanged
	local lootCount = #(afterProfile.lootboxes or {})
	if lootCount ~= 4 then
		print("❌ Expected 4 lootboxes after discard, got " .. lootCount)
		testResults.pendingDiscardNetwork = false
		return
	end
	
	testResults.pendingDiscardNetwork = true
	print("✅ Pending discard network integration test passed")
end

-- Test 14: Start/Open Now Network Integration
local function TestStartOpenNowNetwork()
	print("\n=== Testing Start/Open Now Network Integration ===")
	
	local testUserId = "test_user_start_open_network"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Add a box
	local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.EPIC, "test")
	if not result.ok then
		print("❌ Failed to add box:", result.error)
		testResults.startOpenNowNetwork = false
		return
	end
	
	-- Verify box is in Idle state
	local profile = ProfileManager.GetCachedProfile(testUserId)
	if not profile then
		print("❌ Failed to get profile")
		testResults.startOpenNowNetwork = false
		return
	end
	
	local lootbox = profile.lootboxes[1]
	if not lootbox or lootbox.state ~= BoxTypes.BoxState.IDLE then
		print("❌ Box not in Idle state")
		testResults.startOpenNowNetwork = false
		return
	end
	
	-- Test start unlock
	local startResult = LootboxService.StartUnlock(testUserId, 1, os.time())
	if not startResult.ok then
		print("❌ Start unlock failed:", startResult.error)
		testResults.startOpenNowNetwork = false
		return
	end
	
	-- Verify box is now Unlocking
	local afterStartProfile = ProfileManager.GetCachedProfile(testUserId)
	if not afterStartProfile then
		print("❌ Failed to get profile after start")
		testResults.startOpenNowNetwork = false
		return
	end
	
	local afterStartLootbox = afterStartProfile.lootboxes[1]
	if not afterStartLootbox or afterStartLootbox.state ~= BoxTypes.BoxState.UNLOCKING then
		print("❌ Box not in Unlocking state after start")
		testResults.startOpenNowNetwork = false
		return
	end
	
	-- Test open now (should work on Unlocking box)
	local openResult = LootboxService.OpenNow(testUserId, 1, os.time())
	if not openResult.ok then
		print("❌ Open now failed:", openResult.error)
		testResults.startOpenNowNetwork = false
		return
	end
	
	-- Verify box was opened and removed
	local afterOpenProfile = ProfileManager.GetCachedProfile(testUserId)
	if not afterOpenProfile then
		print("❌ Failed to get profile after open")
		testResults.startOpenNowNetwork = false
		return
	end
	
	local afterOpenLootCount = #(afterOpenProfile.lootboxes or {})
	if afterOpenLootCount ~= 0 then
		print("❌ Expected 0 lootboxes after open, got " .. afterOpenLootCount)
		testResults.startOpenNowNetwork = false
		return
	end
	
	-- Verify currencies were updated
	if not afterOpenProfile.currencies or afterOpenProfile.currencies.soft <= 0 then
		print("❌ Soft currency not properly updated")
		testResults.startOpenNowNetwork = false
		return
	end
	
	testResults.startOpenNowNetwork = true
	print("✅ Start/Open now network integration test passed")
end

-- Test 15: Overflow to Pending to Discard Flow
local function TestOverflowToPendingToDiscard()
	print("\n=== Testing Overflow to Pending to Discard Flow ===")
	
	local testUserId = "test_user_overflow_discard"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Fill to capacity (4 boxes)
	for i = 1, 4 do
		local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.UNCOMMON, "test")
		if not result.ok then
			print("❌ Failed to add box " .. i .. ": " .. (result.error or "unknown"))
			testResults.overflowToPendingToDiscard = false
			return
		end
	end
	
	-- Add 5th box (should go to pending with BOX_DECISION_REQUIRED)
	local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.RARE, "test")
	if not result.ok and result.error == LootboxService.ErrorCodes.BOX_DECISION_REQUIRED and result.pending then
		print("✅ 5th box correctly set as pending with BOX_DECISION_REQUIRED")
	else
		print("❌ 5th box handling failed:", result.error)
		testResults.overflowToPendingToDiscard = false
		return
	end
	
	-- Verify pending state
	local profile = ProfileManager.GetCachedProfile(testUserId)
	if not profile or not profile.pendingLootbox then
		print("❌ Expected pending lootbox")
		testResults.overflowToPendingToDiscard = false
		return
	end
	
	-- Test discard pending
	local discardResult = LootboxService.ResolvePendingDiscard(testUserId)
	if not discardResult.ok then
		print("❌ Discard pending failed:", discardResult.error)
		testResults.overflowToPendingToDiscard = false
		return
	end
	
	-- Verify pending cleared and loot count unchanged
	local afterProfile = ProfileManager.GetCachedProfile(testUserId)
	if not afterProfile or afterProfile.pendingLootbox then
		print("❌ Expected no pending lootbox after discard")
		testResults.overflowToPendingToDiscard = false
		return
	end
	
	local lootCount = #(afterProfile.lootboxes or {})
	if lootCount ~= 4 then
		print("❌ Expected 4 lootboxes after discard, got " .. lootCount)
		testResults.overflowToPendingToDiscard = false
		return
	end
	
	testResults.overflowToPendingToDiscard = true
	print("✅ Overflow to pending to discard flow test passed")
end

-- Test 16: Overflow to Pending to Replace Flow
local function TestOverflowToPendingToReplace()
	print("\n=== Testing Overflow to Pending to Replace Flow ===")
	
	local testUserId = "test_user_overflow_replace"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Fill to capacity (4 boxes)
	for i = 1, 4 do
		local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.UNCOMMON, "test")
		if not result.ok then
			print("❌ Failed to add box " .. i .. ": " .. (result.error or "unknown"))
			testResults.overflowToPendingToReplace = false
			return
		end
	end
	
	-- Add 5th box (should go to pending)
	local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.RARE, "test")
	if not result.ok and result.error == LootboxService.ErrorCodes.BOX_DECISION_REQUIRED and result.pending then
		print("✅ 5th box correctly set as pending")
	else
		print("❌ 5th box handling failed:", result.error)
		testResults.overflowToPendingToReplace = false
		return
	end
	
	-- Test replace pending (replace slot 1)
	local replaceResult = LootboxService.ResolvePendingReplace(testUserId, 1)
	if not replaceResult.ok then
		print("❌ Replace pending failed:", replaceResult.error)
		testResults.overflowToPendingToReplace = false
		return
	end
	
	-- Verify slot 1 was replaced and pending cleared
	local afterProfile = ProfileManager.GetCachedProfile(testUserId)
	if not afterProfile or afterProfile.pendingLootbox then
		print("❌ Expected no pending lootbox after replace")
		testResults.overflowToPendingToReplace = false
		return
	end
	
	local slot1Box = afterProfile.lootboxes[1]
	if not slot1Box or slot1Box.rarity ~= BoxTypes.BoxRarity.RARE or slot1Box.state ~= BoxTypes.BoxState.IDLE then
		print("❌ Slot 1 not properly replaced with pending box")
		testResults.overflowToPendingToReplace = false
		return
	end
	
	testResults.overflowToPendingToReplace = true
	print("✅ Overflow to pending to replace flow test passed")
end

-- Test 17: Start to OpenNow Happy Path
local function TestStartToOpenNowHappyPath()
	print("\n=== Testing Start to OpenNow Happy Path ===")
	
	local testUserId = "test_user_start_open_happy"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Add a box
	local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.EPIC, "test")
	if not result.ok then
		print("❌ Failed to add box:", result.error)
		testResults.startToOpenNowHappyPath = false
		return
	end
	
	-- Verify box is in Idle state
	local profile = ProfileManager.GetCachedProfile(testUserId)
	if not profile then
		print("❌ Failed to get profile")
		testResults.startToOpenNowHappyPath = false
		return
	end
	
	local lootbox = profile.lootboxes[1]
	if not lootbox or lootbox.state ~= BoxTypes.BoxState.IDLE then
		print("❌ Box not in Idle state")
		testResults.startToOpenNowHappyPath = false
		return
	end
	
	-- Test start unlock
	local startResult = LootboxService.StartUnlock(testUserId, 1, os.time())
	if not startResult.ok then
		print("❌ Start unlock failed:", startResult.error)
		testResults.startToOpenNowHappyPath = false
		return
	end
	
	-- Verify box is now Unlocking
	local afterStartProfile = ProfileManager.GetCachedProfile(testUserId)
	if not afterStartProfile then
		print("❌ Failed to get profile after start")
		testResults.startToOpenNowHappyPath = false
		return
	end
	
	local afterStartLootbox = afterStartProfile.lootboxes[1]
	if not afterStartLootbox or afterStartLootbox.state ~= BoxTypes.BoxState.UNLOCKING then
		print("❌ Box not in Unlocking state after start")
		testResults.startToOpenNowHappyPath = false
		return
	end
	
	-- Test open now (should work on Unlocking box)
	local openResult = LootboxService.OpenNow(testUserId, 1, os.time())
	if not openResult.ok then
		print("❌ Open now failed:", openResult.error)
		testResults.startToOpenNowHappyPath = false
		return
	end
	
	-- Verify box was opened and removed
	local afterOpenProfile = ProfileManager.GetCachedProfile(testUserId)
	if not afterOpenProfile then
		print("❌ Failed to get profile after open")
		testResults.startToOpenNowHappyPath = false
		return
	end
	
	local afterOpenLootCount = #(afterOpenProfile.lootboxes or {})
	if afterOpenLootCount ~= 0 then
		print("❌ Expected 0 lootboxes after open, got " .. afterOpenLootCount)
		testResults.startToOpenNowHappyPath = false
		return
	end
	
	-- Verify currencies were updated
	if not afterOpenProfile.currencies or afterOpenProfile.currencies.soft <= 0 then
		print("❌ Soft currency not properly updated")
		testResults.startToOpenNowHappyPath = false
		return
	end
	
	testResults.startToOpenNowHappyPath = true
	print("✅ Start to OpenNow happy path test passed")
end

-- Test 18: OpenNow Wrong State
local function TestOpenNowWrongState()
	print("\n=== Testing OpenNow Wrong State ===")
	
	local testUserId = "test_user_opennow_wrong_state"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Add a box (will be Idle)
	local result = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.EPIC, "test")
	if not result.ok then
		print("❌ Failed to add box:", result.error)
		testResults.openNowWrongState = false
		return
	end
	
	-- Test open now on Idle box (should fail)
	local openResult = LootboxService.OpenNow(testUserId, 1, os.time())
	if openResult.ok or openResult.error ~= LootboxService.ErrorCodes.BOX_NOT_UNLOCKING then
		print("❌ OpenNow on Idle should fail with BOX_NOT_UNLOCKING, got:", openResult.error)
		testResults.openNowWrongState = false
		return
	end
	
	print("✅ OpenNow on Idle correctly rejected")
	
	-- Start unlock to make it Unlocking
	local startResult = LootboxService.StartUnlock(testUserId, 1, os.time())
	if not startResult.ok then
		print("❌ Start unlock failed:", startResult.error)
		testResults.openNowWrongState = false
		return
	end
	
	-- Complete unlock to make it Ready (if that state exists)
	-- For now, let's test that OpenNow works on Unlocking
	local openResult2 = LootboxService.OpenNow(testUserId, 1, os.time())
	if not openResult2.ok then
		print("❌ OpenNow on Unlocking should work, got:", openResult2.error)
		testResults.openNowWrongState = false
		return
	end
	
	print("✅ OpenNow on Unlocking correctly worked")
	
	testResults.openNowWrongState = true
	print("✅ OpenNow wrong state test passed")
end

-- Test 19: StartUnlock Single Unlock Rule
local function TestStartUnlockSingleUnlockRule()
	print("\n=== Testing StartUnlock Single Unlock Rule ===")
	
	local testUserId = "test_user_single_unlock"
	
	-- Clean up any existing profile
	ProfileManager.DeleteProfile(testUserId)
	
	-- Add two boxes
	local result1 = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.EPIC, "test")
	local result2 = LootboxService.TryAddBox(testUserId, BoxTypes.BoxRarity.RARE, "test")
	
	if not result1.ok or not result2.ok then
		print("❌ Failed to add boxes:", result1.error, result2.error)
		testResults.startUnlockSingleUnlockRule = false
		return
	end
	
	-- Start unlock on first box
	local startResult1 = LootboxService.StartUnlock(testUserId, 1, os.time())
	if not startResult1.ok then
		print("❌ Start unlock 1 failed:", startResult1.error)
		testResults.startUnlockSingleUnlockRule = false
		return
	end
	
	-- Try to start unlock on second box (should fail)
	local startResult2 = LootboxService.StartUnlock(testUserId, 2, os.time())
	if startResult2.ok or startResult2.error ~= LootboxService.ErrorCodes.BOX_ALREADY_UNLOCKING then
		print("❌ Start unlock 2 should fail with BOX_ALREADY_UNLOCKING, got:", startResult2.error)
		testResults.startUnlockSingleUnlockRule = false
		return
	end
	
	print("✅ Second start unlock correctly rejected")
	
	testResults.startUnlockSingleUnlockRule = true
	print("✅ StartUnlock single unlock rule test passed")
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
	TestRequestAddBoxNetwork()
	TestPendingDiscardFlow()
	TestPendingReplaceFlow()
	TestOpenNowFlow()
	TestPendingDiscardNetwork()
	TestStartOpenNowNetwork()
	TestOverflowToPendingToDiscard()
	TestOverflowToPendingToReplace()
	TestStartToOpenNowHappyPath()
	TestOpenNowWrongState()
	TestStartUnlockSingleUnlockRule()
	
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
		"test_user_opennow",
		"test_user_network_add",
		"test_user_pending_discard",
		"test_user_pending_replace",
		"test_user_open_now",
		"test_user_pending_discard_network",
		"test_user_start_open_network",
		"test_user_overflow_discard",
		"test_user_overflow_replace",
		"test_user_start_open_happy",
		"test_user_opennow_wrong_state",
		"test_user_single_unlock"
	}
	
	for _, userId in ipairs(testUsers) do
		ProfileManager.DeleteProfile(userId)
	end
	
	return passedTests == totalTests
end

return LootboxDevHarness
