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
local Logger = require(game.ReplicatedStorage.Modules.Logger)

-- Error codes
ShopService.ErrorCodes = {
	INVALID_REQUEST = "INVALID_REQUEST",
	PACK_NOT_AVAILABLE = "PACK_NOT_AVAILABLE",
	INSUFFICIENT_HARD = "INSUFFICIENT_HARD",
	LOOTBOX_CAPACITY_FULL = "LOOTBOX_CAPACITY_FULL",
	INTERNAL = "INTERNAL"
}

-- Receipt ledger to prevent double-crediting
local processedReceipts = {}

-- Regional prices (per player, fetched once on join)
-- Format: regionalPrices[userId] = { packId -> price }
local regionalPrices = {}

local function generateReceiptKey(receiptInfo)
	if receiptInfo.PurchaseId and receiptInfo.PurchaseId ~= "" then
		return receiptInfo.PurchaseId
	else
		return string.format("%d_%d", receiptInfo.PlayerId, receiptInfo.ProductId)
	end
end

-- Process Developer Product receipt
function ShopService.ProcessReceipt(receiptInfo)
	local productId = receiptInfo.ProductId
	local playerId = receiptInfo.PlayerId
	local robuxSpent = receiptInfo.CurrencySpent or 0
	local purchaseId = generateReceiptKey(receiptInfo)
	
	-- Check if receipt already processed
	if processedReceipts[purchaseId] then
		-- Roblox may resend receipts until we acknowledge them; if we already
		-- handled this purchase just confirm it so the platform doesn't retry.
		return Enum.ProductPurchaseDecision.PurchaseGranted
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
			local amountSpent = robuxSpent
			if amountSpent <= 0 then
				amountSpent = pack.robuxPrice or 0
			end
			profile.totalRobuxSpent = (profile.totalRobuxSpent or 0) + amountSpent
			-- NOTE: updatedAt is set by ProfileManager.UpdateProfile, don't set it here
			
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

-- Fetch regional prices for all packs (async, called once per player session)
function ShopService.FetchRegionalPricesForPlayer(player)
	if not player then
		return
	end
	
	local userId = player.UserId
	
	-- Check if already fetched
	if regionalPrices[userId] then
		return -- Already fetched, no need to fetch again
	end
	
	-- Fetch product info for all packs (async, non-blocking)
	task.spawn(function()
		local prices = {}
		local allPacks = ShopPacksCatalog.AllPacks()
		
		for _, pack in ipairs(allPacks) do
			if pack.devProductId then
				local success, productInfo = pcall(function()
					return MarketplaceService:GetProductInfo(pack.devProductId, Enum.InfoType.Product)
				end)
				
				if success and productInfo then
					-- Use PriceInRobux if available (regional pricing)
					-- Fall back to hardcoded price if not available
					prices[pack.id] = productInfo.PriceInRobux or pack.robuxPrice
				else
					-- Fall back to hardcoded price on error
					prices[pack.id] = pack.robuxPrice
				end
			else
				-- No product ID, use hardcoded price
				prices[pack.id] = pack.robuxPrice
			end
		end
		
		-- Store prices for this player
		regionalPrices[userId] = prices
		
		Logger.info("Fetched regional prices for player %d", userId)
	end)
end

-- Get shop packs for client (with regional pricing)
function ShopService.GetShopPacks(player)
	local packs = {}
	
	-- Get stored regional prices (fetched once when player joined)
	local playerPrices = player and regionalPrices[player.UserId] or nil
	
	for _, pack in pairs(ShopPacksCatalog.Packs) do
		-- Use regional price if available, otherwise fall back to hardcoded price
		local price = pack.robuxPrice
		if playerPrices and playerPrices[pack.id] then
			price = playerPrices[pack.id]
		end
		
		table.insert(packs, {
			id = pack.id,
			hardAmount = pack.hardAmount,
			additionalHard = pack.additionalHard or 0,
			robuxPrice = price, -- Regional price or fallback
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
			-- NOTE: updatedAt is set by ProfileManager.UpdateProfile, don't set it here
			
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

-- Clean up regional prices when player leaves
local function onPlayerRemoving(player)
	if player then
		regionalPrices[player.UserId] = nil
	end
end

-- Initialize MarketplaceService receipt processing
function ShopService.Initialize()
	MarketplaceService.ProcessReceipt = ShopService.ProcessReceipt
	Logger.info("ShopService initialized with MarketplaceService.ProcessReceipt")
	
	-- Clean up price cache when players leave
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
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
