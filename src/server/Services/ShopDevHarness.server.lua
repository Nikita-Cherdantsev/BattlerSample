--[[
	ShopDevHarness
	
	Tests the ShopService functionality including Developer Product processing
	and lootbox purchases for hard currency.
]]

local ShopDevHarness = {}

-- Dependencies
local ShopService = require(script.Parent.ShopService)
local ShopPacksCatalog = require(game.ReplicatedStorage.Modules.Shop.ShopPacksCatalog)
local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)
local BoxTypes = require(game.ReplicatedStorage.Modules.Loot.BoxTypes)

-- Test user ID (mock player)
local testUserId = 12345

-- Test pack purchase flow
function ShopDevHarness.TestPackPurchase()
	print("🧪 Testing pack purchase flow...")
	
	-- Test pack validation
	local result = ShopService.ValidatePackPurchase(testUserId, "M")
	if not result.ok then
		print("❌ Pack validation failed:", result.error)
		return false
	end
	
	print("✅ Pack validation successful for pack M")
	
	-- Test invalid pack
	local invalidResult = ShopService.ValidatePackPurchase(testUserId, "INVALID")
	if invalidResult.ok then
		print("❌ Invalid pack validation should have failed")
		return false
	end
	
	print("✅ Invalid pack correctly rejected")
	return true
end

-- Test lootbox purchase flow
function ShopDevHarness.TestLootboxPurchase()
	print("🧪 Testing lootbox purchase flow...")
	
	-- Ensure test profile exists
	local profile = ProfileManager.GetProfile(testUserId)
	if not profile then
		print("❌ Test profile not found")
		return false
	end
	
	-- Give test user some hard currency
	profile.currencies.hard = 1000
	ProfileManager.SaveProfile(testUserId, profile)
	
	-- Test uncommon lootbox purchase
	local result = ShopService.BuyLootbox(testUserId, "uncommon")
	if not result.ok then
		print("❌ Uncommon lootbox purchase failed:", result.error)
		return false
	end
	
	print("✅ Uncommon lootbox purchase successful, cost:", result.cost)
	
	-- Test insufficient currency
	local profile2 = ProfileManager.GetProfile(testUserId)
	profile2.currencies.hard = 0
	ProfileManager.SaveProfile(testUserId, profile2)
	
	local insufficientResult = ShopService.BuyLootbox(testUserId, "rare")
	if insufficientResult.ok then
		print("❌ Insufficient currency purchase should have failed")
		return false
	end
	
	print("✅ Insufficient currency correctly rejected")
	return true
end

-- Test ProcessReceipt idempotency
function ShopDevHarness.TestProcessReceiptIdempotency()
	print("🧪 Testing ProcessReceipt idempotency...")
	
	-- Create mock receipt info
	local receiptInfo = {
		ProductId = 123456789, -- Mock product ID
		PlayerId = testUserId,
		PurchaseId = "test_purchase_" .. os.time()
	}
	
	-- First process should succeed
	local result1 = ShopService.ProcessReceipt(receiptInfo)
	if result1 ~= Enum.ProductPurchaseDecision.NotProcessedYet then
		print("❌ First receipt processing should return NotProcessedYet (no matching product)")
		return false
	end
	
	print("✅ First receipt processing correctly returned NotProcessedYet")
	
	-- Second process with same PurchaseId should also return NotProcessedYet
	local result2 = ShopService.ProcessReceipt(receiptInfo)
	if result2 ~= Enum.ProductPurchaseDecision.NotProcessedYet then
		print("❌ Second receipt processing should return NotProcessedYet")
		return false
	end
	
	print("✅ Second receipt processing correctly returned NotProcessedYet")
	return true
end

-- Test shop packs retrieval
function ShopDevHarness.TestGetShopPacks()
	print("🧪 Testing shop packs retrieval...")
	
	local result = ShopService.GetShopPacks()
	if not result.ok then
		print("❌ Get shop packs failed:", result.error)
		return false
	end
	
	if not result.packs or #result.packs == 0 then
		print("❌ No packs returned")
		return false
	end
	
	print("✅ Shop packs retrieved successfully, count:", #result.packs)
	
	-- Verify pack structure
	for _, pack in ipairs(result.packs) do
		if not pack.id or not pack.hardAmount or not pack.robuxPrice then
			print("❌ Invalid pack structure:", pack)
			return false
		end
	end
	
	print("✅ All packs have valid structure")
	return true
end

-- Test pack availability checking
function ShopDevHarness.TestPackAvailability()
	print("🧪 Testing pack availability...")
	
	-- Test HasDevProductId function
	local hasDevProduct = ShopPacksCatalog.HasDevProductId("M")
	if hasDevProduct then
		print("❌ Pack M should not have devProductId (it's nil)")
		return false
	end
	
	print("✅ Pack M correctly identified as unavailable")
	
	-- Test GetAvailablePacks function
	local availablePacks = ShopPacksCatalog.GetAvailablePacks()
	if #availablePacks > 0 then
		print("❌ No packs should be available (all devProductIds are nil)")
		return false
	end
	
	print("✅ No packs available (as expected)")
	return true
end

-- Test error codes
function ShopDevHarness.TestErrorCodes()
	print("🧪 Testing error codes...")
	
	-- Test invalid rarity
	local result = ShopService.BuyLootbox(testUserId, "invalid_rarity")
	if result.ok then
		print("❌ Invalid rarity should have failed")
		return false
	end
	
	if result.error ~= ShopService.ErrorCodes.INVALID_REQUEST then
		print("❌ Wrong error code for invalid rarity:", result.error)
		return false
	end
	
	print("✅ Invalid rarity correctly rejected with INVALID_REQUEST")
	return true
end

-- Run all tests
function ShopDevHarness.RunAllTests()
	print("🚀 Running ShopDevHarness tests...")
	
	local tests = {
		{"Pack Purchase Flow", ShopDevHarness.TestPackPurchase},
		{"Lootbox Purchase Flow", ShopDevHarness.TestLootboxPurchase},
		{"ProcessReceipt Idempotency", ShopDevHarness.TestProcessReceiptIdempotency},
		{"Get Shop Packs", ShopDevHarness.TestGetShopPacks},
		{"Pack Availability", ShopDevHarness.TestPackAvailability},
		{"Error Codes", ShopDevHarness.TestErrorCodes}
	}
	
	local passed = 0
	local total = #tests
	
	for _, test in ipairs(tests) do
		local testName, testFunc = test[1], test[2]
		print(string.format("\n📋 Running: %s", testName))
		
		local success = testFunc()
		if success then
			print(string.format("✅ PASS: %s", testName))
			passed = passed + 1
		else
			print(string.format("❌ FAIL: %s", testName))
		end
	end
	
	print(string.format("\n🏁 ShopDevHarness Results: %d/%d tests passed", passed, total))
	
	if passed == total then
		print("🎉 All shop tests passed!")
	else
		print("⚠️ Some shop tests failed!")
	end
	
	return passed == total
end

-- Auto-run in Studio
if game:GetService("RunService"):IsStudio() then
	task.wait(2) -- Wait for other services to initialize
	print("🎮 Studio detected. Auto-running ShopDevHarness...")
	ShopDevHarness.RunAllTests()
end

return ShopDevHarness
