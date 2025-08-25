--[[
	Board Layout Helper for UI Integration
	
	This module provides canonical helpers for the 3×2 grid layout
	and slot math used by the UI for consistent rendering.
	
	Visual Layout (3×2 grid):
	Row1: slots 5 3 1
	Row2: slots 6 4 2
	
	Turn Order: Fixed order 1,2,3,4,5,6 (slot 1 acts first)
]]

local BoardLayout = {}

-- Fixed turn order (slot 1 acts first)
function BoardLayout.SLOT_ORDER()
	return {1, 2, 3, 4, 5, 6}
end

-- Convert deck to grid layout for UI rendering
-- Returns stable list: { {slot=1,row=1,col=3}, {slot=2,row=2,col=3}, ... }
function BoardLayout.gridForDeck(deckIds)
	if not deckIds or #deckIds ~= 6 then
		error("Deck must have exactly 6 cards")
	end
	
	-- Visual mapping for 3×2 grid:
	-- Row1: slots 5 3 1  (columns: 1, 2, 3)
	-- Row2: slots 6 4 2  (columns: 1, 2, 3)
	local gridMapping = {
		[1] = {row = 1, col = 3}, -- slot 1: row 1, col 3
		[2] = {row = 2, col = 3}, -- slot 2: row 2, col 3
		[3] = {row = 1, col = 2}, -- slot 3: row 1, col 2
		[4] = {row = 2, col = 2}, -- slot 4: row 2, col 2
		[5] = {row = 1, col = 1}, -- slot 5: row 1, col 1
		[6] = {row = 2, col = 1}  -- slot 6: row 2, col 1
	}
	
	local grid = {}
	for slotIndex, cardId in ipairs(deckIds) do
		local mapping = gridMapping[slotIndex]
		if mapping then
			table.insert(grid, {
				slot = slotIndex,
				row = mapping.row,
				col = mapping.col,
				cardId = cardId
			})
		end
	end
	
	return grid
end

-- Get opposite slot (currently returns same slot for v2 targeting)
-- This helper is kept for future changes even if it's identity now
function BoardLayout.oppositeSlot(slot)
	if not BoardLayout.isValidSlot(slot) then
		error("Invalid slot: " .. tostring(slot))
	end
	
	-- v2: Same-index targeting (1↔1, 2↔2, ..., 6↔6)
	return slot
end

-- Validate slot number
function BoardLayout.isValidSlot(slot)
	return type(slot) == "number" and slot >= 1 and slot <= 6
end

-- Get slot position in grid (row, col)
function BoardLayout.getSlotPosition(slot)
	if not BoardLayout.isValidSlot(slot) then
		return nil
	end
	
	local gridMapping = {
		[1] = {row = 1, col = 3},
		[2] = {row = 2, col = 3},
		[3] = {row = 1, col = 2},
		[4] = {row = 2, col = 2},
		[5] = {row = 1, col = 1},
		[6] = {row = 2, col = 1}
	}
	
	return gridMapping[slot]
end

-- Get all slots in a specific row
function BoardLayout.getSlotsInRow(row)
	if row == 1 then
		return {5, 3, 1} -- Row 1: slots 5, 3, 1
	elseif row == 2 then
		return {6, 4, 2} -- Row 2: slots 6, 4, 2
	else
		return {}
	end
end

-- Get all slots in a specific column
function BoardLayout.getSlotsInColumn(col)
	if col == 1 then
		return {5, 6} -- Column 1: slots 5, 6
	elseif col == 2 then
		return {3, 4} -- Column 2: slots 3, 4
	elseif col == 3 then
		return {1, 2} -- Column 3: slots 1, 2
	else
		return {}
	end
end

return BoardLayout
