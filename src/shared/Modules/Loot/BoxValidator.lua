--[[
	Lootbox Validator
	
	Validates lootbox invariants and data integrity.
	Used before and after atomic operations to ensure consistency.
]]

local BoxValidator = {}

local BoxTypes = require(script.Parent.BoxTypes)

-- Validate a single lootbox entry
function BoxValidator.ValidateBox(box)
	if not box then
		return false, "Box is nil"
	end
	
	-- Required fields
	if not box.id or type(box.id) ~= "string" then
		return false, "Invalid box id"
	end
	
	if not BoxTypes.IsValidRarity(box.rarity) then
		return false, "Invalid box rarity: " .. tostring(box.rarity)
	end
	
	if not BoxTypes.IsValidState(box.state) then
		return false, "Invalid box state: " .. tostring(box.state)
	end
	
	-- State-specific validation
	if box.state == BoxTypes.BoxState.IDLE then
		-- Idle boxes should not have timing fields
		if box.startedAt or box.unlocksAt then
			return false, "Idle box should not have timing fields"
		end
	elseif box.state == BoxTypes.BoxState.UNLOCKING then
		-- Unlocking boxes must have timing fields
		if not box.startedAt or not box.unlocksAt then
			return false, "Unlocking box missing timing fields"
		end
		
		if type(box.startedAt) ~= "number" or type(box.unlocksAt) ~= "number" then
			return false, "Invalid timing field types"
		end
		
		if box.unlocksAt <= box.startedAt then
			return false, "unlocksAt must be after startedAt"
		end
		
		-- Check duration matches rarity
		local expectedDuration = BoxTypes.GetDuration(box.rarity)
		local actualDuration = box.unlocksAt - box.startedAt
		if math.abs(actualDuration - expectedDuration) > 1 then -- Allow 1 second tolerance
			return false, "Duration mismatch for rarity " .. box.rarity
		end
	elseif box.state == BoxTypes.BoxState.READY then
		-- Ready boxes must have timing fields
		if not box.startedAt or not box.unlocksAt then
			return false, "Ready box missing timing fields"
		end
		
		if type(box.startedAt) ~= "number" or type(box.unlocksAt) ~= "number" then
			return false, "Invalid timing field types"
		end
	elseif box.state == BoxTypes.BoxState.CONSUMED then
		-- Consumed boxes should not have timing fields
		if box.startedAt or box.unlocksAt then
			return false, "Consumed box should not have timing fields"
		end
	end
	
	-- Seed validation (required for all states except consumed)
	if box.state ~= BoxTypes.BoxState.CONSUMED then
		if not box.seed or type(box.seed) ~= "number" then
			return false, "Box missing or invalid seed"
		end
		
		if box.seed < 1 or box.seed > 2147483647 then
			return false, "Seed out of valid range"
		end
	end
	
	-- Optional source field validation
	if box.source and type(box.source) ~= "string" then
		return false, "Invalid source field type"
	end
	
	return true, nil
end

-- Validate the entire lootboxes array
function BoxValidator.ValidateLootboxes(lootboxes)
	if not lootboxes then
		return false, "Lootboxes is nil"
	end
	
	if type(lootboxes) ~= "table" then
		return false, "Lootboxes is not a table"
	end
	
	-- Check slot count
	local slotCount = 0
	for i = 1, BoxTypes.MAX_SLOTS do
		if lootboxes[i] then
			slotCount = slotCount + 1
		end
	end
	
	if slotCount > BoxTypes.MAX_SLOTS then
		return false, "Too many lootbox slots: " .. slotCount
	end
	
	-- Check for gaps in array (should be compact)
	local foundGap = false
	for i = 1, BoxTypes.MAX_SLOTS do
		if lootboxes[i] then
			if foundGap then
				return false, "Gap found in lootboxes array"
			end
		else
			foundGap = true
		end
	end
	
	-- Validate each box
	local unlockingCount = 0
	for i = 1, BoxTypes.MAX_SLOTS do
		if lootboxes[i] then
			local isValid, errorMsg = BoxValidator.ValidateBox(lootboxes[i])
			if not isValid then
				return false, "Box at slot " .. i .. ": " .. errorMsg
			end
			
			-- Count unlocking boxes
			if lootboxes[i].state == BoxTypes.BoxState.UNLOCKING then
				unlockingCount = unlockingCount + 1
			end
		end
	end
	
	-- At most one box can be unlocking
	if unlockingCount > 1 then
		return false, "Multiple boxes unlocking: " .. unlockingCount
	end
	
	return true, nil
end

-- Validate pending lootbox
function BoxValidator.ValidatePendingBox(pendingBox)
	if pendingBox == nil then
		return true, nil -- nil is valid (no pending box)
	end
	
	if type(pendingBox) ~= "table" then
		return false, "Pending box is not a table"
	end
	
	-- Required fields
	if not pendingBox.id or type(pendingBox.id) ~= "string" then
		return false, "Invalid pending box id"
	end
	
	if not BoxTypes.IsValidRarity(pendingBox.rarity) then
		return false, "Invalid pending box rarity: " .. tostring(pendingBox.rarity)
	end
	
	if not pendingBox.seed or type(pendingBox.seed) ~= "number" then
		return false, "Pending box missing or invalid seed"
	end
	
	if pendingBox.seed < 1 or pendingBox.seed > 2147483647 then
		return false, "Pending box seed out of valid range"
	end
	
	-- Optional source field validation
	if pendingBox.source and type(pendingBox.source) ~= "string" then
		return false, "Invalid pending box source field type"
	end
	
	-- Pending boxes should not have state or timing fields
	if pendingBox.state or pendingBox.startedAt or pendingBox.unlocksAt then
		return false, "Pending box should not have state or timing fields"
	end
	
	return true, nil
end

-- Validate slot index
function BoxValidator.ValidateSlotIndex(slotIndex)
	if type(slotIndex) ~= "number" then
		return false, "Slot index must be a number"
	end
	
	if slotIndex < 1 or slotIndex > BoxTypes.MAX_SLOTS then
		return false, "Slot index out of range: " .. slotIndex
	end
	
	return true, nil
end

-- Validate entire lootbox profile structure
function BoxValidator.ValidateProfile(lootboxes, pendingBox)
	-- Validate lootboxes array
	local isValid, errorMsg = BoxValidator.ValidateLootboxes(lootboxes)
	if not isValid then
		return false, "Lootboxes validation failed: " .. errorMsg
	end
	
	-- Validate pending box
	local isValidPending, errorMsgPending = BoxValidator.ValidatePendingBox(pendingBox)
	if not isValidPending then
		return false, "Pending box validation failed: " .. errorMsgPending
	end
	
	return true, nil
end

return BoxValidator
