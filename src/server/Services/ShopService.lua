--[[
	ShopService
	
	Handles Developer Product purchases and lootbox purchases for hard currency.
	Integrates with MarketplaceService.ProcessReceipt for Robux transactions.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ShopService = {}

-- Dependencies
local ShopPacksCatalog = require(game.ReplicatedStorage.Modules.Shop.ShopPacksCatalog)
local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)
local LootboxService = require(script.Parent.LootboxService)
local BoxTypes = require(game.ReplicatedStorage.Modules.Loot.BoxTypes)
local Logger = require(game.ReplicatedStorage.Modules.Logger)

-- Error codes
ShopService.ErrorCodes = {
	INVALID_REQUEST = "INVALID_REQUEST",
	RATE_LIMITED = "RATE_LIMITED",
	PACK_NOT_AVAILABLE = "PACK_NOT_AVAILABLE",
	INSUFFICIENT_HARD = "INSUFFICIENT_HARD",
	LOOTBOX_CAPACITY_FULL = "LOOTBOX_CAPACITY_FULL",
	INTERNAL = "INTERNAL"
}

-- Receipt ledger to prevent double-crediting
local processedReceipts = {}

-- Process Developer Product receipt
function ShopService.ProcessReceipt(receiptInfo)
	local productId = receiptInfo.ProductId
	local playerId = receiptInfo.PlayerId
	local purchaseId = receiptInfo.PurchaseId
	
	-- Check if receipt already processed
	if processedReceipts[purchaseId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- Find pack by productId using helper function
	local pack = ShopPacksCatalog.getPackByProductId(productId)
	
	if not pack then
		warn(string.format("[ShopService] Unknown productId %d for player %d", productId, playerId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- Atomically credit hard currency
	local success, result = pcall(function()
		return ProfileManager.UpdateProfile(playerId, function(profile)
			if not profile then
				return nil, "Profile not found"
			end
			
			-- Credit hard currency (base + bonus)
			local totalHard = pack.hardAmount + (pack.additionalHard or 0)
			local oldHard = profile.currencies.hard or 0
			profile.currencies.hard = oldHard + totalHard
			profile.totalRobuxSpent = (profile.totalRobuxSpent or 0) + (pack.robuxPrice or 0)
			profile.updatedAt = os.time()
			
			return profile
		end)
	end)
	
	local totalHard = pack.hardAmount + (pack.additionalHard or 0)
	
	if not success or not result then
		warn(string.format("[ShopService] Failed to credit %d hard currency for player %d: %s", 
			totalHard, playerId, tostring(result)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- Mark receipt as processed
	processedReceipts[purchaseId] = {
		playerId = playerId,
		productId = productId,
		packId = pack.id,
		hardAmount = totalHard,
		processedAt = os.time()
	}
	
	-- Get the new total from the updated profile
	local updatedProfile = ProfileManager.GetCachedProfile(playerId)
	local newTotal = 0
	
	if updatedProfile and updatedProfile.currencies and updatedProfile.currencies.hard then
		newTotal = updatedProfile.currencies.hard
	else
		-- Fallback: calculate new total manually
		newTotal = totalHard -- At least show what was added
	end
	
	print("💰 Pack purchased: " .. pack.id .. " | Added: " .. totalHard .. " hard currency | New total: " .. newTotal)
	
	Logger.shopPurchase(playerId, pack.id, newTotal - totalHard, totalHard, newTotal)
	
	-- Send ProfileUpdated event to client to update currency display
	local Players = game:GetService("Players")
	local player = Players:GetPlayerByUserId(playerId)
	if player then
		local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
		ProfileUpdated:FireClient(player, {
			currencies = updatedProfile.currencies,
			serverNow = os.time()
		})
	end
	
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ShopService.ProcessPackPurchaseForStudio(playerId, pack)
	if not RunService:IsStudio() then
		return
	end
	
	if not pack or not pack.devProductId then
		warn("[ShopService] Cannot simulate pack purchase in Studio: missing pack or devProductId")
		return
	end
	
	local purchaseId = string.format("DEV_%d_%d_%d", playerId, pack.devProductId, os.time())
	local receipt = {
		ProductId = pack.devProductId,
		PlayerId = playerId,
		PurchaseId = purchaseId
	}
	
	ShopService.ProcessReceipt(receipt)
end

-- Get shop packs for client
function ShopService.GetShopPacks()
	local packs = {}
	for _, pack in pairs(ShopPacksCatalog.Packs) do
		table.insert(packs, {
			id = pack.id,
			hardAmount = pack.hardAmount,
			additionalHard = pack.additionalHard or 0,
			robuxPrice = pack.robuxPrice,
			hasDevProductId = pack.devProductId ~= nil
		})
	end
	
	-- Sort by hard amount (ascending)
	table.sort(packs, function(a, b)
		return a.hardAmount < b.hardAmount
	end)
	
	return { ok = true, packs = packs }
end

-- Validate pack purchase request
function ShopService.ValidatePackPurchase(playerId, packId)
	-- Validate pack exists and has devProductId
	local pack = ShopPacksCatalog.GetPack(packId)
	if not pack then
		return { ok = false, error = ShopService.ErrorCodes.PACK_NOT_AVAILABLE }
	end
	
	if not pack.devProductId then
		return { ok = false, error = ShopService.ErrorCodes.PACK_NOT_AVAILABLE }
	end
	
	return { ok = true, pack = pack }
end

-- Buy lootbox with hard currency
function ShopService.BuyLootbox(playerId, rarity)
	print("🔍 [ShopService.BuyLootbox] Received rarity:", rarity, "type:", type(rarity))
	
	-- Validate rarity
	if not BoxTypes.StoreHardCost[rarity] then
		print("❌ [ShopService.BuyLootbox] Invalid rarity:", rarity, "Available rarities:", BoxTypes.StoreHardCost)
		return { ok = false, error = ShopService.ErrorCodes.INVALID_REQUEST }
	end
	
	local cost = BoxTypes.StoreHardCost[rarity]
	print("✅ [ShopService.BuyLootbox] Valid rarity:", rarity, "cost:", cost)
	
	-- Load profile
	local profile = ProfileManager.LoadProfile(playerId)
	if not profile then
		return { ok = false, error = ShopService.ErrorCodes.INTERNAL }
	end
	
	-- Check hard currency
	if (profile.currencies.hard or 0) < cost then
		return { ok = false, error = ShopService.ErrorCodes.INSUFFICIENT_HARD }
	end
	
	-- Open lootbox immediately instead of adding to stack
	-- This provides instant gratification for shop purchases
	local openResult = LootboxService.OpenShopLootbox(playerId, rarity, os.time())
	if not openResult.ok then
		return { ok = false, error = openResult.error }
	end
	
	-- Atomically deduct hard currency and update profile
	local success, result = pcall(function()
		return ProfileManager.UpdateProfile(playerId, function(profile)
			if not profile then
				return nil, "Profile not found"
			end
			
			-- Deduct hard currency
			profile.currencies.hard = (profile.currencies.hard or 0) - cost
			profile.updatedAt = os.time()
			
			return profile
		end)
	end)
	
	if not success or not result then
		warn(string.format("[ShopService] Failed to deduct %d hard currency for player %d: %s", 
			cost, playerId, tostring(result)))
		return { ok = false, error = ShopService.ErrorCodes.INTERNAL }
	end
	
	Logger.debug("Player %d bought %s lootbox for %d hard currency", playerId, rarity, cost)
	
	return { ok = true, cost = cost, rewards = openResult.rewards }
end

-- Initialize MarketplaceService receipt processing
function ShopService.Initialize()
	MarketplaceService.ProcessReceipt = ShopService.ProcessReceipt
	Logger.info("ShopService initialized with MarketplaceService.ProcessReceipt")
	
	-- Check for live product IDs and warn if none found
	local hasLiveProducts = ShopPacksCatalog.hasLiveProductIds()
	if not hasLiveProducts then
		warn("[ShopService] WARNING: No live Developer Product IDs found in ShopPacksCatalog!")
		warn("[ShopService] All packs have devProductId = nil - update ShopPacksCatalog.lua with real ProductIds")
		Logger.warn("Pack purchase buttons will be disabled until ProductIds are set")
	else
		Logger.info("Live Developer Product IDs detected - shop is production ready")
	end
end

return ShopService
