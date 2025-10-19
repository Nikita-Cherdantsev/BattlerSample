local DeckValidator = {}

local CardCatalog = require(script.Parent.CardCatalog)

-- Board layout constants
DeckValidator.BOARD_WIDTH = 3
DeckValidator.BOARD_HEIGHT = 2
DeckValidator.TOTAL_SLOTS = DeckValidator.BOARD_WIDTH * DeckValidator.BOARD_HEIGHT

-- Board slot indexing (1-based for consistency)
-- Visual layout: [5] [3] [1]
--                [6] [4] [2]
-- Slots are assigned by slotNumber order: lowest slotNumber → slot 1, highest → slot 6
DeckValidator.BoardSlots = {
	TOP_LEFT = 1,
	TOP_CENTER = 2,
	TOP_RIGHT = 3,
	BOTTOM_LEFT = 4,
	BOTTOM_CENTER = 5,
	BOTTOM_RIGHT = 6
}

-- Validation errors
DeckValidator.Errors = {
	INVALID_SIZE = "Deck must contain between 0 and 6 cards",
	UNKNOWN_CARD = "Card ID not found in catalog: %s",
	INVALID_CARD_ID = "Invalid card ID format: %s",
	DUPLICATE_CARD = "Duplicate card ID in deck: %s"
}

-- Validate deck composition (v2 rules)
function DeckValidator.ValidateDeck(deck)
	-- Check deck size (allow 0-6 cards for deck management, but require exactly 6 for battles)
	if not deck or #deck > DeckValidator.TOTAL_SLOTS then
		return false, DeckValidator.Errors.INVALID_SIZE
	end
	
	-- Check for duplicates and validate each card ID
	local seenCards = {}
	for i, cardId in ipairs(deck) do
		if type(cardId) ~= "string" or cardId == "" then
			return false, string.format(DeckValidator.Errors.INVALID_CARD_ID, tostring(cardId))
		end
		
		if not CardCatalog.IsValidCardId(cardId) then
			return false, string.format(DeckValidator.Errors.UNKNOWN_CARD, cardId)
		end
		
		-- Check for duplicates
		if seenCards[cardId] then
			return false, string.format(DeckValidator.Errors.DUPLICATE_CARD, cardId)
		end
		seenCards[cardId] = true
	end
	
	return true, nil
end

-- Validate deck for battles (requires exactly 6 cards)
function DeckValidator.ValidateDeckForBattle(deck)
	-- Check deck size (must be exactly 6 for battles)
	if not deck or #deck ~= DeckValidator.TOTAL_SLOTS then
		return false, "Deck must contain exactly 6 cards for battles"
	end
	
	-- Use the same validation logic as regular deck validation
	return DeckValidator.ValidateDeck(deck)
end

-- Map validated deck to board layout by slotNumber order
function DeckValidator.MapDeckToBoard(deck)
	local isValid, errorMessage = DeckValidator.ValidateDeckForBattle(deck)
	if not isValid then
		error("Cannot map invalid deck: " .. errorMessage)
	end
	
	-- Create array of card data with slotNumber for sorting
	local cardData = {}
	for i, cardId in ipairs(deck) do
		local card = CardCatalog.GetCard(cardId)
		if not card then
			error("Card not found in catalog: " .. cardId)
		end
		if not card.slotNumber then
			error("Card missing slotNumber: " .. cardId)
		end
		if type(card.slotNumber) ~= "number" then
			error("Card slotNumber is not a number: " .. cardId .. " (type: " .. type(card.slotNumber) .. ", value: " .. tostring(card.slotNumber) .. ")")
		end
		table.insert(cardData, {
			cardId = cardId,
			card = card,
			slotNumber = card.slotNumber
		})
	end
	
	-- Sort by slotNumber (ascending)
	table.sort(cardData, function(a, b)
		-- Additional safety check
		if not a.slotNumber or not b.slotNumber then
			error("Invalid slotNumber in deck validation: a=" .. tostring(a.slotNumber) .. ", b=" .. tostring(b.slotNumber))
		end
		if type(a.slotNumber) ~= "number" or type(b.slotNumber) ~= "number" then
			error("slotNumber must be a number: a=" .. tostring(a.slotNumber) .. " (type: " .. type(a.slotNumber) .. "), b=" .. tostring(b.slotNumber) .. " (type: " .. type(b.slotNumber) .. ")")
		end
		return a.slotNumber < b.slotNumber
	end)
	
	-- Map to board slots 1-6
	local board = {}
	for i = 1, #cardData do
		local slotIndex = i  -- 1-based indexing
		local data = cardData[i]
		
		board[slotIndex] = {
			slotIndex = slotIndex,
			cardId = data.cardId,
			card = data.card,
			position = {
				row = math.floor((slotIndex - 1) / DeckValidator.BOARD_WIDTH),
				col = (slotIndex - 1) % DeckValidator.BOARD_WIDTH
			}
		}
	end
	
	return board
end

-- Get board slot information
function DeckValidator.GetSlotInfo(slotIndex)
	if slotIndex < 1 or slotIndex > DeckValidator.TOTAL_SLOTS then
		return nil
	end
	
	return {
		slotIndex = slotIndex,
		position = {
			row = math.floor((slotIndex - 1) / DeckValidator.BOARD_WIDTH),
			col = (slotIndex - 1) % DeckValidator.BOARD_WIDTH
		},
		adjacentSlots = DeckValidator.GetAdjacentSlots(slotIndex)
	}
end

-- Get adjacent slots for a given slot
function DeckValidator.GetAdjacentSlots(slotIndex)
	local adjacent = {}
	local row = math.floor((slotIndex - 1) / DeckValidator.BOARD_WIDTH)
	local col = (slotIndex - 1) % DeckValidator.BOARD_WIDTH
	
	-- Check all 8 possible adjacent positions
	local directions = {
		{-1, -1}, {-1, 0}, {-1, 1},
		{0, -1},           {0, 1},
		{1, -1},  {1, 0},  {1, 1}
	}
	
	for _, direction in ipairs(directions) do
		local newRow = row + direction[1]
		local newCol = col + direction[2]
		
		if newRow >= 0 and newRow < DeckValidator.BOARD_HEIGHT and
		   newCol >= 0 and newCol < DeckValidator.BOARD_WIDTH then
			local adjacentSlot = newRow * DeckValidator.BOARD_WIDTH + newCol + 1
			table.insert(adjacent, adjacentSlot)
		end
	end
	
	return adjacent
end

-- Utility function to check if two slots are adjacent
function DeckValidator.AreSlotsAdjacent(slot1, slot2)
	local adjacent = DeckValidator.GetAdjacentSlots(slot1)
	for _, slot in ipairs(adjacent) do
		if slot == slot2 then
			return true
		end
	end
	return false
end

return DeckValidator
