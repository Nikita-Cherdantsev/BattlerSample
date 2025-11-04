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
		-- Auto-repair expired unlocking boxes first
		-- Also repair boxes that are UNLOCKING but invalid (no unlocksAt)
		for i = 1, BoxTypes.MAX_SLOTS do
			local box = profile.lootboxes[i]
			if box and box.state == BoxTypes.BoxState.UNLOCKING then
				if box.unlocksAt then
					if box.unlocksAt <= serverNow then
						-- Timer expired, transition to Ready state
						box.state = BoxTypes.BoxState.READY
					end
				else
					-- Invalid state: UNLOCKING without unlocksAt - auto-repair to READY
					box.state = BoxTypes.BoxState.READY
				end
			end
		end
		
		-- Validate profile before modification (after auto-repair)
		local isValid, errorMsg = BoxValidator.ValidateProfile(profile.lootboxes, profile.pendingLootbox)
		if not isValid then
			error("Profile validation failed: " .. errorMsg)
		end
		
		local lootbox = profile.lootboxes[slotIndex]
		if not lootbox then
			profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.INVALID_SLOT }
			return preserveProfileInvariants(profile, userId)
		end
		
		-- Handle Consumed state (shouldn't exist, but provide clear error)
		if lootbox.state == BoxTypes.BoxState.CONSUMED then
			profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.INVALID_STATE, message = "Lootbox was already consumed" }
			return preserveProfileInvariants(profile, userId)
		end
		
		-- Handle Ready state: box is ready to open, not unlock
		if lootbox.state == BoxTypes.BoxState.READY then
			profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.INVALID_STATE, message = "Lootbox is ready to open, use CompleteUnlock instead" }
			return preserveProfileInvariants(profile, userId)
		end
		
		-- Handle Unlocking state: check if timer expired or if it's still active
		if lootbox.state == BoxTypes.BoxState.UNLOCKING then
			if not lootbox.unlocksAt then
				-- Invalid state: UNLOCKING without unlocksAt - treat as ready to open
				lootbox.state = BoxTypes.BoxState.READY
				profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.INVALID_STATE, message = "Lootbox is ready to open, use CompleteUnlock instead" }
				return preserveProfileInvariants(profile, userId)
			elseif lootbox.unlocksAt <= serverNow then
				-- Timer expired but wasn't caught by auto-repair (shouldn't happen, but handle gracefully)
				-- Auto-repair it now
				lootbox.state = BoxTypes.BoxState.READY
				profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.INVALID_STATE, message = "Lootbox is ready to open, use CompleteUnlock instead" }
				return preserveProfileInvariants(profile, userId)
			else
				-- Timer still active - box is already unlocking
				profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.BOX_ALREADY_UNLOCKING, message = "Lootbox is already unlocking" }
				return preserveProfileInvariants(profile, userId)
			end
		end
		
		-- StartUnlock only works on Idle boxes
		if lootbox.state ~= BoxTypes.BoxState.IDLE then
			profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.INVALID_STATE, message = "Lootbox is in " .. tostring(lootbox.state) .. " state, expected Idle" }
			return preserveProfileInvariants(profile, userId)
		end
		
		-- Check if any other box is actively unlocking (timer still running)
		-- Only count boxes that are actually unlocking with an active timer (not expired)
		-- Skip the box we're trying to unlock (slotIndex)
		-- After auto-repair, re-check all boxes to ensure expired ones are fixed
		for i = 1, BoxTypes.MAX_SLOTS do
			if i ~= slotIndex then
				local otherBox = profile.lootboxes[i]
				if otherBox and otherBox.state == BoxTypes.BoxState.UNLOCKING then
					if otherBox.unlocksAt then
						-- If timer expired, auto-repair it to READY state
						if otherBox.unlocksAt <= serverNow then
							otherBox.state = BoxTypes.BoxState.READY
							-- Log auto-repair for debugging
							print(string.format("[LootboxService.StartUnlock] Auto-repaired expired UNLOCKING box at slot %d (expired at %d, now %d)", i, otherBox.unlocksAt, serverNow))
						else
							-- Timer still running - another box is actively unlocking
							local errorMsg = string.format("Box at slot %d is still unlocking (expires at %d, now %d, remaining: %d seconds)", i, otherBox.unlocksAt, serverNow, otherBox.unlocksAt - serverNow)
							print("[LootboxService.StartUnlock] " .. errorMsg)
							profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.BOX_ALREADY_UNLOCKING, message = errorMsg }
							return preserveProfileInvariants(profile, userId)
						end
					else
						-- Invalid state: UNLOCKING without unlocksAt - auto-repair to READY
						otherBox.state = BoxTypes.BoxState.READY
						print(string.format("[LootboxService.StartUnlock] Auto-repaired invalid UNLOCKING box at slot %d (no unlocksAt)", i))
					end
				end
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
		-- Idempotency: if box already opened/removed, return success (no-op)
		if not lootbox then
			profile._lootboxResult = { ok = true, rewards = nil, message = "Box already opened" }
			return preserveProfileInvariants(profile, userId)
		end
		
		if lootbox.state ~= BoxTypes.BoxState.UNLOCKING and lootbox.state ~= BoxTypes.BoxState.READY then
			profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.BOX_BAD_STATE }
			return preserveProfileInvariants(profile, userId)
		end
		
		-- Auto-repair: if timer expired, transition to Ready state
		if lootbox.state == BoxTypes.BoxState.UNLOCKING and lootbox.unlocksAt and serverNow >= lootbox.unlocksAt then
			lootbox.state = BoxTypes.BoxState.READY
		end
		
		-- Check if enough time has passed (for Unlocking boxes)
		if lootbox.state == BoxTypes.BoxState.UNLOCKING and serverNow < lootbox.unlocksAt then
			profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.BOX_TIME_NOT_REACHED }
			return preserveProfileInvariants(profile, userId)
		end
		
		-- Roll rewards using stored seed
		local rng = SeededRNG.New(lootbox.seed)
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
				print("🎁 [LootboxService.CompleteUnlock] Added", copies, "copies to existing card:", cardId, "-> new count:", profile.collection[cardId].count)
			else
				profile.collection[cardId] = { count = copies, level = 1 }
				print("🎁 [LootboxService.CompleteUnlock] NEW CARD unlocked:", cardId, "with", copies, "copies")
			end
			
			-- Debug: Show all cards in collection
			local collectionCount = 0
			for _ in pairs(profile.collection) do
				collectionCount = collectionCount + 1
			end
			print("🎁 [LootboxService.CompleteUnlock] Total unique cards in collection:", collectionCount)
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
		-- Idempotency: if box already opened/removed, return success (no-op)
		if not lootbox then
			profile._lootboxResult = { ok = true, rewards = nil, instantCost = 0, message = "Box already opened" }
			return preserveProfileInvariants(profile, userId)
		end
		
		-- OpenNow works on Unlocking or Ready boxes
		if lootbox.state ~= BoxTypes.BoxState.UNLOCKING and lootbox.state ~= BoxTypes.BoxState.READY then
			profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.BOX_NOT_UNLOCKING }
			return preserveProfileInvariants(profile, userId)
		end
		
		-- Auto-repair: if timer expired, transition to Ready state
		if lootbox.state == BoxTypes.BoxState.UNLOCKING and lootbox.unlocksAt and serverNow >= lootbox.unlocksAt then
			lootbox.state = BoxTypes.BoxState.READY
		end
		
		-- Calculate cost based on state and remaining time
		-- Server is authoritative: only charge if timer is still running
		local instantCost = 0
		if lootbox.state == BoxTypes.BoxState.UNLOCKING then
			-- Only charge if timer is still running (speed-up/instant open)
			local totalDuration = BoxTypes.GetDuration(lootbox.rarity)
			local remainingTime = math.max(0, lootbox.unlocksAt - serverNow)
			
			-- If timer has expired, cost is 0 (shouldn't happen after auto-repair, but safety check)
			if remainingTime <= 0 then
				instantCost = 0
			else
				-- Calculate speed-up cost for remaining time
				instantCost = BoxTypes.ComputeInstantOpenCost(lootbox.rarity, remainingTime, totalDuration)
				
				-- Check if player has enough hard currency
				if profile.currencies.hard < instantCost then
					profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.INSUFFICIENT_HARD }
					return preserveProfileInvariants(profile, userId)
				end
				
				-- Deduct hard currency only when charging
				profile.currencies.hard = profile.currencies.hard - instantCost
			end
		elseif lootbox.state == BoxTypes.BoxState.READY then
			-- Timer completed: no cost
			instantCost = 0
		end
		
		-- Roll rewards using stored seed
		local rng = SeededRNG.New(lootbox.seed)
		local rewards = BoxRoller.RollRewards(rng, lootbox.rarity)

		rewards.rarity = lootbox.rarity
		
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
				print("🎁 [LootboxService.OpenNow] Added", copies, "copies to existing card:", cardId, "-> new count:", profile.collection[cardId].count)
			else
				profile.collection[cardId] = { count = copies, level = 1 }
				print("🎁 [LootboxService.OpenNow] NEW CARD unlocked:", cardId, "with", copies, "copies")
			end
			
			-- Debug: Show all cards in collection
			local collectionCount = 0
			for _ in pairs(profile.collection) do
				collectionCount = collectionCount + 1
			end
			print("🎁 [LootboxService.OpenNow] Total unique cards in collection:", collectionCount)
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

--- Open a shop-purchased lootbox immediately (creates temporary lootbox, opens it, grants rewards)
function LootboxService.OpenShopLootbox(userId, rarity, serverNow)
	-- Validate rarity (rarity should already be lowercase from client)
	local validRarities = {
		[BoxTypes.BoxRarity.UNCOMMON] = true,
		[BoxTypes.BoxRarity.RARE] = true,
		[BoxTypes.BoxRarity.EPIC] = true,
		[BoxTypes.BoxRarity.LEGENDARY] = true
	}
	if not validRarities[rarity] then
		return { ok = false, error = LootboxService.ErrorCodes.INVALID_RARITY }
	end
	
	local success, result = ProfileManager.UpdateProfile(userId, function(profile)
		-- Create a temporary lootbox with the specified rarity
		local lootbox = {
			id = BoxRoller.GenerateBoxId(),
			rarity = rarity,
			state = BoxTypes.BoxState.READY, -- Ready to open immediately
			seed = BoxRoller.GenerateSeed(),
			startedAt = serverNow,
			unlocksAt = serverNow -- Already unlocked
		}
		
		-- Roll rewards using the lootbox's seed
		local rng = SeededRNG.New(lootbox.seed)
		local rewards = BoxRoller.RollRewards(rng, lootbox.rarity)
		
		rewards.rarity = lootbox.rarity

		-- Grant rewards directly
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
				print("🎁 [LootboxService.OpenShopLootbox] Added", copies, "copies to existing card:", cardId, "-> new count:", profile.collection[cardId].count)
			else
				profile.collection[cardId] = { count = copies, level = 1 }
				print("🎁 [LootboxService.OpenShopLootbox] NEW CARD unlocked:", cardId, "with", copies, "copies")
			end
			
			-- Debug: Show all cards in collection
			local collectionCount = 0
			for _ in pairs(profile.collection) do
				collectionCount = collectionCount + 1
			end
			print("🎁 [LootboxService.OpenShopLootbox] Total unique cards in collection:", collectionCount)
		end
		
		-- Preserve profile invariants
		profile = preserveProfileInvariants(profile, userId)
		
		-- Return the rewards for logging
		profile._lootboxResult = { ok = true, rewards = rewards, instantCost = 0 }
		return profile
	end)
	
	if not success then
		return { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
	end
	
	return result._lootboxResult or { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
end

--- Speed up unlocking (complete timer and make lootbox ready)
function LootboxService.SpeedUp(userId, slotIndex, serverNow)
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
		
		-- SpeedUp only works on Unlocking boxes
		if lootbox.state ~= BoxTypes.BoxState.UNLOCKING then
			profile._lootboxResult = { ok = false, error = LootboxService.ErrorCodes.BOX_NOT_UNLOCKING }
			return preserveProfileInvariants(profile, userId)
		end
		
		-- Calculate instant speed up cost
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
		local rng = SeededRNG.New(lootbox.seed)
		local rewards = BoxRoller.RollRewards(rng, lootbox.rarity)
		
		if not rewards then
			error("BoxRoller.RollRewards returned nil for rarity: " .. tostring(lootbox.rarity))
		end
		
		rewards.rarity = lootbox.rarity
		
		print("🎁 [LootboxService.SpeedUp] Rewards rolled - softDelta:", rewards.softDelta, "hardDelta:", rewards.hardDelta, "card:", rewards.card and rewards.card.cardId or "none")
		
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
				print("🎁 [LootboxService.SpeedUp] Added", copies, "copies to existing card:", cardId, "-> new count:", profile.collection[cardId].count)
			else
				profile.collection[cardId] = { count = copies, level = 1 }
				print("🎁 [LootboxService.SpeedUp] NEW CARD unlocked:", cardId, "with", copies, "copies")
			end
			
			-- Debug: Show all cards in collection
			local collectionCount = 0
			for _ in pairs(profile.collection) do
				collectionCount = collectionCount + 1
			end
			print("🎁 [LootboxService.SpeedUp] Total unique cards in collection:", collectionCount)
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
		print("❌ [LootboxService.SpeedUp] ProfileManager.UpdateProfile failed:", result)
		return { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
	end
	
	return result._lootboxResult or { ok = false, error = LootboxService.ErrorCodes.INTERNAL }
end

return LootboxService
