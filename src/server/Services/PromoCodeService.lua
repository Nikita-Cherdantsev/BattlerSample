--[[
	Promo Code Service
	
	Server-side service for validating and redeeming promo codes.
	Codes are stored in a configuration table.
]]

local PromoCodeService = {}

local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)
local ProfileSchema = require(script.Parent.Parent.Persistence.ProfileSchema)
local LootboxService = require(script.Parent.LootboxService)
local BoxTypes = require(game.ReplicatedStorage.Modules.Loot.BoxTypes)
local CardCatalog = require(game.ReplicatedStorage.Modules.Cards.CardCatalog)
local Logger = require(game.ReplicatedStorage.Modules.Logger)

-- Promo codes configuration
-- Each code can have one reward
local PROMO_CODES = {
	--[[["DEV_SOFT"] = {
		rewards = {
			{ type = "soft", amount = 100 }
		}
	},
	["DEV_HARD"] = {
		rewards = {
			{ type = "hard", amount = 50 }
		}
	},
	["DEV_UNCOMMON"] = {
		rewards = {
			{ type = "lootbox", rarity = "uncommon" }
		}
	},
	["DEV_RARE"] = {
		rewards = {
			{ type = "lootbox", rarity = "rare" }
		}
	},
	["DEV_EPIC"] = {
		rewards = {
			{ type = "lootbox", rarity = "epic" }
		}
	},
	["DEV_LEGENDARY"] = {
		rewards = {
			{ type = "lootbox", rarity = "legendary" }
		}
	},	
	["DEV_ONEPIECE"] = {
		rewards = {
			{ type = "lootbox", rarity = "onepiece" }
		}
	},
	["DEV_CARD100"] = {
		rewards = {
			{ type = "card", cardId = "card_100", copies = 3 }
		}
	},
	["DEV_CARD1800"] = {
		rewards = {
			{ type = "card", cardId = "card_1800", copies = 6 }
		}
	},]]
	-- 
	["BETA"] = {
		rewards = {
			{ type = "lootbox", rarity = "epic" }
		}
	},
	["GOLD"] = {
		rewards = {
			{ type = "hard", amount = 50 }
		}
	},
}

-- Error codes
PromoCodeService.ErrorCodes = {
	CODE_NOT_FOUND = "CODE_NOT_FOUND",
	ALREADY_REDEEMED = "ALREADY_REDEEMED",
	INVALID_CODE = "INVALID_CODE",
	INVALID_REWARD = "INVALID_REWARD",
	INTERNAL = "INTERNAL"
}

-- Normalize code (uppercase, trim whitespace)
local function normalizeCode(code)
	if not code or type(code) ~= "string" then
		return nil
	end
	return string.upper(string.gsub(code, "^%s*(.-)%s*$", "%1"))
end

local function GrantLootboxRewards(userId, rarity)
	local lootboxResult = LootboxService.OpenShopLootbox(userId, rarity, os.time())
	if not lootboxResult or not lootboxResult.ok then
		Logger.debug("PromoCodeService: Failed to open lootbox %s for user %d", rarity, userId)
		return nil
	end
	return lootboxResult.rewards
end

-- Redeem a promo code for a player
function PromoCodeService.RedeemCode(userId, code)
	if not userId or userId <= 0 then
		return { ok = false, error = PromoCodeService.ErrorCodes.INVALID_CODE }
	end
	
	-- Normalize code
	local normalizedCode = normalizeCode(code)
	if not normalizedCode or normalizedCode == "" then
		return { ok = false, error = PromoCodeService.ErrorCodes.INVALID_CODE }
	end
	
	-- Check if code exists
	local codeConfig = PROMO_CODES[normalizedCode]
	if not codeConfig then
		return { ok = false, error = PromoCodeService.ErrorCodes.CODE_NOT_FOUND }
	end
	
	-- Check if code has direct card rewards (before UpdateProfile)
	local hasDirectCards = false
	for _, reward in ipairs(codeConfig.rewards) do
		if reward.type == "card" then
			hasDirectCards = true
			break
		end
	end
	
	-- Redeem code atomically
	local lootboxesToGrant = {}
	
	local success, result = ProfileManager.UpdateProfile(userId, function(profile)
		-- Ensure redeemedCodes exists
		profile.redeemedCodes = profile.redeemedCodes or {}
		
		-- Double-check if already redeemed (race condition protection)
		if profile.redeemedCodes[normalizedCode] then
			profile._promoCodeResult = { ok = false, error = PromoCodeService.ErrorCodes.ALREADY_REDEEMED }
			return profile
		end
		
		-- Grant all rewards
		for _, reward in ipairs(codeConfig.rewards) do
			if reward.type == "hard" then
				local amount = reward.amount or 0
				if amount > 0 then
					local success = ProfileSchema.AddCurrency(profile, "hard", amount)
					if not success then
						profile._promoCodeResult = { ok = false, error = PromoCodeService.ErrorCodes.INVALID_REWARD, message = "Failed to add hard currency" }
						return profile
					end
				end
			elseif reward.type == "soft" then
				local amount = reward.amount or 0
				if amount > 0 then
					local success = ProfileSchema.AddCurrency(profile, "soft", amount)
					if not success then
						profile._promoCodeResult = { ok = false, error = PromoCodeService.ErrorCodes.INVALID_REWARD, message = "Failed to add soft currency" }
						return profile
					end
				end
			elseif reward.type == "lootbox" then
				local rarity = reward.rarity
				if not rarity then
					profile._promoCodeResult = { ok = false, error = PromoCodeService.ErrorCodes.INVALID_REWARD, message = "Missing rarity for lootbox reward" }
					return profile
				end
				
				-- Normalize rarity to lowercase
				rarity = string.lower(rarity)
				
				-- Validate rarity
				if not BoxTypes.IsValidRarity(rarity) then
					profile._promoCodeResult = { ok = false, error = PromoCodeService.ErrorCodes.INVALID_REWARD, message = "Invalid lootbox rarity: " .. tostring(rarity) }
					return profile
				end
				
				table.insert(lootboxesToGrant, rarity)
			elseif reward.type == "card" then
				local cardId = reward.cardId
				local copies = reward.copies or 1
				
				if not cardId or type(cardId) ~= "string" then
					profile._promoCodeResult = { ok = false, error = PromoCodeService.ErrorCodes.INVALID_REWARD, message = "Invalid card ID" }
					return profile
				end
				
				-- Validate card exists in catalog
				if not CardCatalog.IsValidCardId(cardId) then
					profile._promoCodeResult = { ok = false, error = PromoCodeService.ErrorCodes.INVALID_REWARD, message = "Card not found in catalog: " .. cardId }
					return profile
				end
				
				-- Grant card copies using ProfileSchema
				local success = ProfileSchema.AddCardsToCollection(profile, cardId, copies)
				if not success then
					profile._promoCodeResult = { ok = false, error = PromoCodeService.ErrorCodes.INVALID_REWARD, message = "Failed to add cards to collection" }
					return profile
				end
			else
				profile._promoCodeResult = { ok = false, error = PromoCodeService.ErrorCodes.INVALID_REWARD, message = "Unknown reward type: " .. tostring(reward.type) }
				return profile
			end
		end
		
		-- Mark code as redeemed
		profile.redeemedCodes[normalizedCode] = true
		
		-- Preserve profile invariants
		profile.playerId = tostring(userId)
		profile.schemaVersion = profile.schemaVersion or 1
		if not profile.createdAt or type(profile.createdAt) ~= "number" or profile.createdAt <= 0 then
			profile.createdAt = os.time()
		end
		
		profile._promoCodeResult = {
			ok = true,
			code = normalizedCode,
			lootboxes = lootboxesToGrant,
			hasCards = hasDirectCards
		}
		
		warn("CODE REDEEMED: " .. normalizedCode)
		return profile
	end)
	
	local promoCodeResult = nil
	if success and result and result._promoCodeResult then
		promoCodeResult = result._promoCodeResult
		
		-- Grant lootboxes only if redemption was successful
		if promoCodeResult.ok then
			for _, rarity in ipairs(lootboxesToGrant) do
				local lootboxRewards = GrantLootboxRewards(userId, rarity)
				if lootboxRewards then
					promoCodeResult.rewards = lootboxRewards
				else
					Logger.debug("PromoCodeService: Failed to grant lootbox %s for code %s (user %d)", 
						rarity, normalizedCode, userId)
				end
			end
		end
	end
	
	if not success then
		return { ok = false, error = PromoCodeService.ErrorCodes.INTERNAL }
	end
	
	promoCodeResult = promoCodeResult or { ok = false, error = PromoCodeService.ErrorCodes.INTERNAL }
	if promoCodeResult.ok then
		promoCodeResult.lootboxes = nil
	end
	
	return promoCodeResult
end

return PromoCodeService

