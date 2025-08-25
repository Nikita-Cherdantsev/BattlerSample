--[[
	Error Mapping for UI Integration
	
	This module provides mapping from error codes to user-facing messages
	and helper functions for consistent error handling across client and server.
]]

local ErrorMap = {}

-- Error code to user message mapping
local ERROR_MESSAGES = {
	-- Rate limiting
	RATE_LIMITED = {
		title = "Too Many Requests",
		message = "Please wait a moment before trying again."
	},
	
	-- Request validation
	INVALID_REQUEST = {
		title = "Invalid Request",
		message = "The request format is not valid."
	},
	
	-- Profile and deck errors
	DECK_UPDATE_FAILED = {
		title = "Deck Update Failed",
		message = "Unable to update your deck. Please try again."
	},
	PROFILE_LOAD_FAILED = {
		title = "Profile Error",
		message = "Unable to load your profile. Please reconnect."
	},
	NO_DECK = {
		title = "No Deck",
		message = "You need to create a deck before playing."
	},
	INVALID_DECK = {
		title = "Invalid Deck",
		message = "Your deck is not valid. Please check your cards."
	},
	
	-- Match errors
	BUSY = {
		title = "Already in Match",
		message = "You are already in a match. Please wait for it to finish."
	},
	
	-- Generic errors
	INTERNAL = {
		title = "Server Error",
		message = "An unexpected error occurred. Please try again."
	},
	
	-- Card errors
	CARD_NOT_FOUND = {
		title = "Card Not Found",
		message = "One or more cards in your deck are not available."
	},
	INSUFFICIENT_CARDS = {
		title = "Insufficient Cards",
		message = "You don't have enough copies of some cards."
	},
	
	-- Lootbox errors
	LOOTBOX_NOT_FOUND = {
		title = "Lootbox Not Found",
		message = "The requested lootbox is not available."
	},
	LOOTBOX_ALREADY_OPENING = {
		title = "Already Opening",
		message = "This lootbox is already being opened."
	}
}

-- Convert error code to user-facing message
function ErrorMap.toUserMessage(code, fallbackMessage)
	local errorInfo = ERROR_MESSAGES[code]
	
	if errorInfo then
		return {
			title = errorInfo.title,
			message = errorInfo.message
		}
	else
		-- Return fallback or generic error
		return {
			title = "Error",
			message = fallbackMessage or "An unexpected error occurred."
		}
	end
end

-- Get all available error codes (for debugging/testing)
function ErrorMap.getAvailableCodes()
	local codes = {}
	for code, _ in pairs(ERROR_MESSAGES) do
		table.insert(codes, code)
	end
	table.sort(codes)
	return codes
end

-- Export the error messages table for direct access if needed
ErrorMap.Messages = ERROR_MESSAGES

return ErrorMap
