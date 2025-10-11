--[[
	Lootbox Service
	
	Server-side atomic operations for lootbox management.
	All operations use atomic UpdateAsync for data consistency.
]]

local LootboxService = {}

local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)
local BoxTypes = require(game.ReplicatedStorage.Modules.Loot.BoxTypes)
local BoxRoller = require(game.ReplicatedStorage.Modules.Loot.BoxRoller)
local BoxValidator = require(game.ReplicatedStorage.Modules.Loot.BoxValidator)
local SeededRNG = require(game.ReplicatedStorage.Modules.RNG.SeededRNG)
local CardCatalog = require(game.ReplicatedStorage.Modules.Cards.CardCatalog)
local Logger = require(game.ReplicatedStorage.Modules.Logger)

-- Helper function to preserve profile invariants
local function preserveProfileInvariants(profile, userId)
	profile.updatedAt = os.time()
	profile.playerId = tostring(userId)
	profile.schemaVersion = profile.schemaVersion or 1
	
	-- Ensure createdAt is valid
	if not profile.createdAt or type(profile.createdAt) ~= "number" or profile.createdAt <= 0 then
		profile.createdAt = os.time()
	end
	
	return profile
end

-- Error codes
LootboxService.ErrorCodes = {
	BOX_DECISION_REQUIRED = "BOX_DECISION_REQUIRED",
	BOX_ALREADY_UNLOCKING = "BOX_ALREADY_UNLOCKING",
	BOX_NOT_UNLOCKING = "BOX_NOT_UNLOCKING",
	BOX_BAD_STATE = "BOX_BAD_STATE",
	BOX_TIME_NOT_REACHED = "BOX_TIME_NOT_REACHED",
	INVALID_RARITY = "INVALID_RARITY",
	INVALID_SLOT = "INVALID_SLOT",
	INVALID_STATE = "INVALID_STATE",
	INSUFFICIENT_HARD = "INSUFFICIENT_HARD",
	INTERNAL = "INTERNAL"
}

-- Try to add a lootbox to the player's profile
function LootboxService.TryAddBox(userId, rarity, source)
	if not BoxTypes.IsValidRarity(rarity) then
		return { ok = false, error = LootboxService.ErrorCodes.INVALID_RARITY }
	end
	
	local success, result = ProfileManager.UpdateProfile(userId, function(profile)
		-- Validate profile before modification
		local isValid, errorMsg = BoxValidator.ValidateProfile(profile.lootboxes, profile.pendingLootbox)
		if not isValid then
			error("Profile validation failed: " .. errorMsg)
		end
		
		-- Count current lootboxes
		local lootboxCount = 0
		for i = 1, BoxTypes.MAX_SLOTS do
			if profile.lootboxes[i] then
				lootboxCount = lootboxCount + 1
			end
		end
		
		-- If capacity available, add to next slot
		if lootboxCount < BoxTypes.MAX_SLOTS then
			local newBox = {
				id = BoxRoller.GenerateBoxId(),
				rarity = rarity,
				state = BoxTypes.BoxState.IDLE,
				seed = BoxRoller.GenerateSeed(),
				source = source
			}
			
			-- Find next available slot
			for i = 1, BoxTypes.MAX_SLOTS do
				if not profile.lootboxes[i] then
					profile.lootboxes[i] = newBox
					break
				end
			end
			
			-- Store the result for later return
			profile._lootboxResult = { ok = true, box = newBox }
			return preserveProfileInvariants(profile, userId)
		end
		
		-- If capacity full and no pending box, set pending
		if not profile.pendingLootbox then
			profile.pendingLootbox = {
				id = BoxRoller.GenerateBoxId(),
				rarity = rarity,
				seed = BoxRoller.GenerateSeed(),
				source = source
			}
			
			-- Store the result for later return
			profile._lootboxResult = { 
				ok = false, 
				error = LootboxService.ErrorCodes.BOX_DECISION_REQUIRED,
				pending = true,
				pendingBox = profile.pendingLootbox
			}
			return profile
		end
		
		-- If capacity full and pending exists, require decision
		profile._lootboxResult = { 
			ok = false, 
			error = LootboxService.ErrorCodes.BOX_DECISION_REQUIRED 
		}
		return preserveProfileInvariants(profile, userId)
	end)
	
	if not success then
		return { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
	end
	
	-- Return the stored result from the profile
	return result._lootboxResult or { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
end

-- Resolve pending box by discarding it
function LootboxService.ResolvePendingDiscard(userId)
	-- Log before state
	local beforeProfile = ProfileManager.GetCachedProfile(userId)
	local beforeLootCount = beforeProfile and #(beforeProfile.lootboxes or {}) or 0
	local beforePending = beforeProfile and beforeProfile.pendingLootbox ~= nil or false
	
	local success, result = ProfileManager.UpdateProfile(userId, function(profile)
		-- Validate profile before modification
		local isValid, errorMsg = BoxValidator.ValidateProfile(profile.lootboxes, profile.pendingLootbox)
		if not isValid then
			error("Profile validation failed: " .. errorMsg)
		end
		
		if not profile.pendingLootbox then
			error("No pending lootbox to discard")
		end
		
		profile.pendingLootbox = nil
		profile.updatedAt = os.time()
		profile._lootboxResult = { ok = true }
		return preserveProfileInvariants(profile, userId)
	end)
	
	if not success then
		Logger.debug("lootboxes: count=%d->%d, pending=%s->%s, op=discard userId=%s result=ERROR:INTERNAL", 
			beforeLootCount, beforeLootCount, tostring(beforePending), tostring(beforePending), tostring(userId))
		return { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
	end
	
	-- Log after state
	local afterLootCount = result and #(result.lootboxes or {}) or 0
	local afterPending = result and result.pendingLootbox ~= nil or false
	local resultCode = result._lootboxResult and (result._lootboxResult.ok and "OK" or ("ERROR:" .. (result._lootboxResult.error or "UNKNOWN"))) or "ERROR:UNKNOWN"
	
	Logger.debug("lootboxes: count=%d->%d, pending=%s->%s, op=discard userId=%s result=%s", 
		beforeLootCount, afterLootCount, tostring(beforePending), tostring(afterPending), tostring(userId), resultCode)
	
	return result._lootboxResult or { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
end

-- Resolve pending box by replacing a slot
function LootboxService.ResolvePendingReplace(userId, slotIndex)
	-- Validate slot index
	local isValidSlot, errorMsg = BoxValidator.ValidateSlotIndex(slotIndex)
	if not isValidSlot then
		return { ok = false, error = LootboxService.ErrorCodes.INVALID_SLOT }
	end
	
	local success, result = ProfileManager.UpdateProfile(userId, function(profile)
		-- Validate profile before modification
		local isValid, errorMsg = BoxValidator.ValidateProfile(profile.lootboxes, profile.pendingLootbox)
		if not isValid then
			error("Profile validation failed: " .. errorMsg)
		end
		
		if not profile.pendingLootbox then
			error("No pending lootbox to replace")
		end
		
		if not profile.lootboxes[slotIndex] then
			error("No lootbox at slot " .. slotIndex .. " to replace")
		end
		
		-- Replace the slot with pending box (as Idle state)
		local pendingBox = profile.pendingLootbox
		profile.lootboxes[slotIndex] = {
			id = pendingBox.id,
			rarity = pendingBox.rarity,
			state = BoxTypes.BoxState.IDLE,
			seed = pendingBox.seed,
			source = pendingBox.source
		}
		
		profile.pendingLootbox = nil
		profile.updatedAt = os.time()
		profile._lootboxResult = { ok = true, replacedBox = profile.lootboxes[slotIndex] }
		return preserveProfileInvariants(profile, userId)
	end)
	
	if not success then
		return { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
	end
	
	return result._lootboxResult or { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
end

-- Start unlocking a lootbox
function LootboxService.StartUnlock(userId, slotIndex, serverNow)
	-- Validate slot index
	local isValidSlot, errorMsg = BoxValidator.ValidateSlotIndex(slotIndex)
	if not isValidSlot then
		return { ok = false, error = LootboxService.ErrorCodes.INVALID_SLOT }
	end
	
	local success, result = ProfileManager.UpdateProfile(userId, function(profile)
		-- Validate profile before modification
		local isValid, errorMsg = BoxValidator.ValidateProfile(profile.lootboxes, profile.pendingLootbox)
		if not isValid then
			error("Profile validation failed: " .. errorMsg)
		end
		
		local lootbox = profile.lootboxes[slotIndex]
		if not lootbox then
			error("No lootbox at slot " .. slotIndex)
		end
		
		-- StartUnlock only works on Idle boxes
		if lootbox.state ~= BoxTypes.BoxState.IDLE then
			profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.INVALID_STATE }
			return preserveProfileInvariants(profile, userId)
		end
		
		-- Check if any other box is unlocking
		for i = 1, BoxTypes.MAX_SLOTS do
			if profile.lootboxes[i] and profile.lootboxes[i].state == BoxTypes.BoxState.UNLOCKING then
				profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.BOX_ALREADY_UNLOCKING }
				return preserveProfileInvariants(profile, userId)
			end
		end
		
		-- Start unlocking
		local duration = BoxTypes.GetDuration(lootbox.rarity)
		lootbox.state = BoxTypes.BoxState.UNLOCKING
		lootbox.startedAt = serverNow
		lootbox.unlocksAt = serverNow + duration
		
		profile.updatedAt = os.time()
		profile._lootboxResult = { ok = true, lootbox = lootbox }
		return preserveProfileInvariants(profile, userId)
	end)
	
	if not success then
		return { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
	end
	
	return result._lootboxResult or { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
end

-- Complete unlocking a lootbox (roll rewards and free slot)
function LootboxService.CompleteUnlock(userId, slotIndex, serverNow)
	-- Validate slot index
	local isValidSlot, errorMsg = BoxValidator.ValidateSlotIndex(slotIndex)
	if not isValidSlot then
		return { ok = false, error = LootboxService.ErrorCodes.INVALID_SLOT }
	end
	
	local success, result = ProfileManager.UpdateProfile(userId, function(profile)
		-- Validate profile before modification
		local isValid, errorMsg = BoxValidator.ValidateProfile(profile.lootboxes, profile.pendingLootbox)
		if not isValid then
			error("Profile validation failed: " .. errorMsg)
		end
		
		local lootbox = profile.lootboxes[slotIndex]
		if not lootbox then
			error("No lootbox at slot " .. slotIndex)
		end
		
		if lootbox.state ~= BoxTypes.BoxState.UNLOCKING and lootbox.state ~= BoxTypes.BoxState.READY then
			return { ok = false, error = LootboxService.ErrorCodes.BOX_BAD_STATE }
		end
		
		-- Check if enough time has passed
		if lootbox.state == BoxTypes.BoxState.UNLOCKING and serverNow < lootbox.unlocksAt then
			return { ok = false, error = LootboxService.ErrorCodes.BOX_TIME_NOT_REACHED }
		end
		
		-- Roll rewards using stored seed
		local rng = SeededRNG.new(lootbox.seed)
		local rewards = BoxRoller.RollRewards(rng, lootbox.rarity)
		
		-- Grant rewards
		profile.currencies.soft = profile.currencies.soft + rewards.softDelta
		if rewards.hardDelta > 0 then
			profile.currencies.hard = profile.currencies.hard + rewards.hardDelta
		end
		
		-- Grant card copies
		if rewards.card then
			local cardId = rewards.card.cardId
			local copies = rewards.card.copies
			
			if profile.collection[cardId] then
				profile.collection[cardId].count = profile.collection[cardId].count + copies
			else
				profile.collection[cardId] = { count = copies, level = 1 }
			end
		end
		
		-- Free the slot (remove the lootbox)
		profile.lootboxes[slotIndex] = nil
		
		-- Compact the array (shift remaining boxes to fill gaps)
		local compacted = {}
		local index = 1
		for i = 1, BoxTypes.MAX_SLOTS do
			if profile.lootboxes[i] then
				compacted[index] = profile.lootboxes[i]
				index = index + 1
			end
		end
		profile.lootboxes = compacted
		profile.updatedAt = os.time()
		profile._lootboxResult = { ok = true, rewards = rewards }
		return preserveProfileInvariants(profile, userId)
	end)
	
	if not success then
		return { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
	end
	
	return result._lootboxResult or { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
end

-- Open lootbox instantly with hard currency
function LootboxService.OpenNow(userId, slotIndex, serverNow)
	-- Validate slot index
	local isValidSlot, errorMsg = BoxValidator.ValidateSlotIndex(slotIndex)
	if not isValidSlot then
		return { ok = false, error = LootboxService.ErrorCodes.INVALID_SLOT }
	end
	
	local success, result = ProfileManager.UpdateProfile(userId, function(profile)
		-- Validate profile before modification
		local isValid, errorMsg = BoxValidator.ValidateProfile(profile.lootboxes, profile.pendingLootbox)
		if not isValid then
			error("Profile validation failed: " .. errorMsg)
		end
		
		local lootbox = profile.lootboxes[slotIndex]
		if not lootbox then
			error("No lootbox at slot " .. slotIndex)
		end
		
		-- OpenNow only works on Unlocking boxes
		if lootbox.state ~= BoxTypes.BoxState.UNLOCKING then
			profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.BOX_NOT_UNLOCKING }
			return preserveProfileInvariants(profile, userId)
		end
		
		-- Calculate instant open cost (only for Unlocking boxes)
		local totalDuration = BoxTypes.GetDuration(lootbox.rarity)
		local remainingTime = math.max(0, lootbox.unlocksAt - serverNow)
		
		local instantCost = BoxTypes.ComputeInstantOpenCost(lootbox.rarity, remainingTime, totalDuration)
		
		-- Check if player has enough hard currency
		if profile.currencies.hard < instantCost then
			profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.INSUFFICIENT_HARD }
			return preserveProfileInvariants(profile, userId)
		end
		
		-- Deduct hard currency
		profile.currencies.hard = profile.currencies.hard - instantCost
		
		-- Roll rewards using stored seed
		local rng = SeededRNG.new(lootbox.seed)
		local rewards = BoxRoller.RollRewards(rng, lootbox.rarity)
		
		-- Grant rewards
		profile.currencies.soft = profile.currencies.soft + rewards.softDelta
		if rewards.hardDelta > 0 then
			profile.currencies.hard = profile.currencies.hard + rewards.hardDelta
		end
		
		-- Grant card copies
		if rewards.card then
			local cardId = rewards.card.cardId
			local copies = rewards.card.copies
			
			if profile.collection[cardId] then
				profile.collection[cardId].count = profile.collection[cardId].count + copies
			else
				profile.collection[cardId] = { count = copies, level = 1 }
			end
		end
		
		-- Free the slot (remove the lootbox)
		profile.lootboxes[slotIndex] = nil
		
		-- Compact the array (shift remaining boxes to fill gaps)
		local compacted = {}
		local index = 1
		for i = 1, BoxTypes.MAX_SLOTS do
			if profile.lootboxes[i] then
				compacted[index] = profile.lootboxes[i]
				index = index + 1
			end
		end
		profile.lootboxes = compacted
		
		-- Preserve profile invariants
		profile = preserveProfileInvariants(profile, userId)
		
		profile._lootboxResult = { ok = true, rewards = rewards, instantCost = instantCost }
		return profile
	end)
	
	if not success then
		return { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
	end
	
	return result._lootboxResult or { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
end

return LootboxService
