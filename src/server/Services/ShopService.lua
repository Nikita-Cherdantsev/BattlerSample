--[[
	ShopService
	
	Handles Developer Product purchases and lootbox purchases for hard currency.
	Integrates with MarketplaceService.ProcessReceipt for Robux transactions.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local ShopService = {}

-- Dependencies
local ShopPacksCatalog = require(game.ReplicatedStorage.Modules.Shop.ShopPacksCatalog)
local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)
local LootboxService = require(script.Parent.LootboxService)
local BoxTypes = require(game.ReplicatedStorage.Modules.Loot.BoxTypes)

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
		warn(string.format("[ShopService] Receipt %s already processed for player %d", purchaseId, playerId))
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
			
			-- Credit hard currency
			profile.currencies.hard = (profile.currencies.hard or 0) + pack.hardAmount
			profile.updatedAt = os.time()
			
			return profile
		end)
	end)
	
	if not success or not result then
		warn(string.format("[ShopService] Failed to credit %d hard currency for player %d: %s", 
			pack.hardAmount, playerId, tostring(result)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- Mark receipt as processed
	processedReceipts[purchaseId] = {
		playerId = playerId,
		productId = productId,
		packId = pack.id,
		hardAmount = pack.hardAmount,
		processedAt = os.time()
	}
	
	print(string.format("[ShopService] Processed receipt %s: player %d received %d hard currency from pack %s", 
		purchaseId, playerId, pack.hardAmount, pack.id))
	
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Get shop packs for client
function ShopService.GetShopPacks()
	local packs = {}
	for _, pack in pairs(ShopPacksCatalog.Packs) do
		table.insert(packs, {
			id = pack.id,
			hardAmount = pack.hardAmount,
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
	-- Validate rarity
	if not BoxTypes.StoreHardCost[rarity] then
		return { ok = false, error = ShopService.ErrorCodes.INVALID_REQUEST }
	end
	
	local cost = BoxTypes.StoreHardCost[rarity]
	
	-- Load profile
	local profile = ProfileManager.GetProfile(playerId)
	if not profile then
		return { ok = false, error = ShopService.ErrorCodes.INTERNAL }
	end
	
	-- Check hard currency
	if (profile.currencies.hard or 0) < cost then
		return { ok = false, error = ShopService.ErrorCodes.INSUFFICIENT_HARD }
	end
	
	-- Try to add lootbox (handles capacity/overflow automatically)
	local addResult = LootboxService.TryAddBox(playerId, rarity, "shop_purchase")
	if not addResult.ok then
		if addResult.error == LootboxService.ErrorCodes.BOX_CAPACITY_FULL_PENDING then
			return { ok = false, error = ShopService.ErrorCodes.LOOTBOX_CAPACITY_FULL }
		end
		return { ok = false, error = addResult.error }
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
	
	print(string.format("[ShopService] Player %d bought %s lootbox for %d hard currency", 
		playerId, rarity, cost))
	
	return { ok = true, cost = cost }
end

-- Initialize MarketplaceService receipt processing
function ShopService.Initialize()
	MarketplaceService.ProcessReceipt = ShopService.ProcessReceipt
	print("[ShopService] Initialized with MarketplaceService.ProcessReceipt")
	
	-- Check for live product IDs and warn if none found
	local hasLiveProducts = ShopPacksCatalog.hasLiveProductIds()
	if not hasLiveProducts then
		warn("[ShopService] WARNING: No live Developer Product IDs found in ShopPacksCatalog!")
		warn("[ShopService] All packs have devProductId = nil - update ShopPacksCatalog.lua with real ProductIds")
		warn("[ShopService] Pack purchase buttons will be disabled until ProductIds are set")
	else
		print("[ShopService] Live Developer Product IDs detected - shop is production ready")
	end
end

return ShopService
