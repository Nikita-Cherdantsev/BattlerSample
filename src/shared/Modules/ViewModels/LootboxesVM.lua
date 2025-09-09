--[[
	LootboxesVM - View Model for lootbox UI data
	
	Transforms raw profile state into UI-ready data structures.
	Pure, deterministic, and free of Roblox dependencies.
]]

local LootboxesVM = {}

local Utilities = require(script.Parent.Parent.Utilities)
local BoxTypes = Utilities.BoxTypes

-- Build lootbox view model from profile state
function LootboxesVM.build(profileState)
	if not profileState then
		return {
			slots = {},
			pending = nil,
			canResolvePending = false,
			summary = {
				total = 0,
				byRarity = {},
				byState = {},
				unlockingCount = 0
			}
		}
	end
	
	local now = os.time()
	local lootboxes = profileState.lootboxes or {}
	local pendingLootbox = profileState.pendingLootbox
	local currencies = profileState.currencies or { soft = 0, hard = 0 }
	
	-- Build slots array (1-4)
	local slots = {}
	for i = 1, 4 do
		local lootbox = lootboxes[i]
		if lootbox then
			local rarity = lootbox.rarity
			local state = lootbox.state
			local totalDuration = BoxTypes.GetDuration(rarity)
			local remainingTime = 0
			
			-- Calculate remaining time
			if state == "idle" then
				remainingTime = totalDuration
			elseif state == "unlocking" and lootbox.unlocksAt then
				remainingTime = math.max(0, lootbox.unlocksAt - now)
			end
			
			-- Calculate instant open cost
			local instantCost = BoxTypes.ComputeInstantOpenCost(rarity, remainingTime, totalDuration)
			
			-- Determine capabilities
			local canStart = (state == "idle")
			local canOpenNow = (state == "idle" or state == "unlocking") and currencies.hard >= instantCost
			local isUnlocking = (state == "unlocking")
			
			slots[i] = {
				slotIndex = i,
				id = lootbox.id,
				rarity = rarity,
				state = state,
				startedAt = lootbox.startedAt,
				unlocksAt = lootbox.unlocksAt,
				remaining = remainingTime,
				total = totalDuration,
				canStart = canStart,
				canOpenNow = canOpenNow,
				instantCost = instantCost,
				isUnlocking = isUnlocking
			}
		else
			slots[i] = {
				slotIndex = i,
				id = nil,
				rarity = nil,
				state = "empty",
				startedAt = nil,
				unlocksAt = nil,
				remaining = 0,
				total = 0,
				canStart = false,
				canOpenNow = false,
				instantCost = 0,
				isUnlocking = false
			}
		end
	end
	
	-- Build pending info
	local pending = nil
	if pendingLootbox then
		pending = {
			id = pendingLootbox.id,
			rarity = pendingLootbox.rarity
		}
	end
	
	-- Determine if can resolve pending
	local canResolvePending = (pendingLootbox ~= nil)
	
	-- Build summary
	local summary = {
		total = #lootboxes,
		byRarity = {},
		byState = {},
		unlockingCount = 0
	}
	
	-- Initialize counters
	local rarities = {"uncommon", "rare", "epic", "legendary"}
	local states = {"idle", "unlocking", "ready", "consumed"}
	
	for _, rarity in ipairs(rarities) do
		summary.byRarity[rarity] = 0
	end
	
	for _, state in ipairs(states) do
		summary.byState[state] = 0
	end
	
	-- Count lootboxes
	for _, lootbox in ipairs(lootboxes) do
		summary.byRarity[lootbox.rarity] = (summary.byRarity[lootbox.rarity] or 0) + 1
		summary.byState[lootbox.state] = (summary.byState[lootbox.state] or 0) + 1
		
		if lootbox.state == "unlocking" then
			summary.unlockingCount = summary.unlockingCount + 1
		end
	end
	
	return {
		slots = slots,
		pending = pending,
		canResolvePending = canResolvePending,
		summary = summary
	}
end

-- Helper function to get slot by index
function LootboxesVM.getSlot(vm, slotIndex)
	if not vm or not vm.slots then
		return nil
	end
	return vm.slots[slotIndex]
end

-- Helper function to check if any slot is unlocking
function LootboxesVM.hasUnlocking(vm)
	if not vm or not vm.summary then
		return false
	end
	return vm.summary.unlockingCount > 0
end

-- Helper function to get first idle slot
function LootboxesVM.getFirstIdleSlot(vm)
	if not vm or not vm.slots then
		return nil
	end
	
	for i = 1, 4 do
		local slot = vm.slots[i]
		if slot and slot.state == "idle" then
			return slot
		end
	end
	
	return nil
end

-- Helper function to get first unlocking slot
function LootboxesVM.getFirstUnlockingSlot(vm)
	if not vm or not vm.slots then
		return nil
	end
	
	for i = 1, 4 do
		local slot = vm.slots[i]
		if slot and slot.state == "unlocking" then
			return slot
		end
	end
	
	return nil
end

-- Helper function to get first ready slot
function LootboxesVM.getFirstReadySlot(vm)
	if not vm or not vm.slots then
		return nil
	end
	
	for i = 1, 4 do
		local slot = vm.slots[i]
		if slot and slot.state == "ready" then
			return slot
		end
	end
	
	return nil
end

return LootboxesVM
