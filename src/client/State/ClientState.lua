--[[
	ClientState - Centralized client state management
	
	Maintains a single source of truth for client-side state,
	including profile data, server time, and UI state.
]]

local ClientState = {}

-- State
local state = {
	profile = nil,           -- Types.ProfileV2?
	serverNow = 0,           -- number?
	isSavingDeck = false,    -- boolean
	lastError = nil,         -- { code: string, message: string }?
}

-- Subscribers
local subscribers = {}

-- Utility functions
local function notifySubscribers()
	for _, callback in pairs(subscribers) do
		callback(state)
	end
end

local function log(message, ...)
	print(string.format("[ClientState] %s", string.format(message, ...)))
end

-- Public API

-- Initialize ClientState with NetworkClient
function ClientState.init(networkClient)
	log("Initializing ClientState")
	
	-- Subscribe to profile updates
	networkClient.onProfileUpdated(function(payload)
		ClientState.applyProfileUpdate(payload)
	end)
	
	log("ClientState initialized")
end

-- Apply profile update from server
function ClientState.applyProfileUpdate(payload)
	if payload.error then
		-- Handle error
		ClientState.setLastError({
			code = payload.error.code,
			message = payload.error.message
		})
		log("Profile update error: %s", payload.error.message)
		return
	end
	
	-- Clear any previous errors
	ClientState.setLastError(nil)
	
	-- Update server time
	if payload.serverNow then
		state.serverNow = payload.serverNow
	end
	
	-- Update profile data (merge with existing if available)
	if payload.deck or payload.collectionSummary or payload.loginInfo or payload.squadPower or payload.lootboxes then
		-- Create or update profile
		if not state.profile then
			state.profile = {
				version = 2,
				playerId = "",
				createdAt = 0,
				lastLoginAt = 0,
				loginStreak = 0,
				collection = {},
				deck = {},
				currencies = { soft = 0, hard = 0 },
				favoriteLastSeen = 0,
				tutorialStep = 0,
				squadPower = 0,
				lootboxes = {}
			}
		end
		
		-- Update deck
		if payload.deck then
			state.profile.deck = payload.deck
		end
		
		-- Update collection
		if payload.collectionSummary then
			for _, card in ipairs(payload.collectionSummary) do
				state.profile.collection[card.cardId] = {
					count = card.count,
					level = card.level
				}
			end
		end
		
		-- Update login info
		if payload.loginInfo then
			state.profile.lastLoginAt = payload.loginInfo.lastLoginAt
			state.profile.loginStreak = payload.loginInfo.loginStreak
		end
		
		-- Update squad power
		if payload.squadPower then
			state.profile.squadPower = payload.squadPower
		end
		
		-- Update lootboxes
		if payload.lootboxes then
			state.profile.lootboxes = payload.lootboxes
		end
		
		log("Profile updated: deck=%d cards, squadPower=%d", #state.profile.deck, state.profile.squadPower)
	end
	
	-- Update timestamp
	if payload.updatedAt then
		state.profile.lastLoginAt = payload.updatedAt
	end
	
	notifySubscribers()
end

-- Set saving deck state
function ClientState.setSavingDeck(isSaving)
	state.isSavingDeck = isSaving
	log("Saving deck: %s", tostring(isSaving))
	notifySubscribers()
end

-- Set last error
function ClientState.setLastError(error)
	state.lastError = error
	if error then
		log("Error set: %s - %s", error.code, error.message)
	else
		log("Error cleared")
	end
	notifySubscribers()
end

-- Get current state (readonly snapshot)
function ClientState.getState()
	return state
end

-- Subscribe to state changes
function ClientState.subscribe(callback)
	local id = tostring(callback)
	subscribers[id] = callback
	return function()
		subscribers[id] = nil
	end
end

-- Get specific state values
function ClientState.getProfile()
	return state.profile
end

function ClientState.getServerNow()
	return state.serverNow
end

function ClientState.isSavingDeck()
	return state.isSavingDeck
end

function ClientState.getLastError()
	return state.lastError
end

return ClientState
