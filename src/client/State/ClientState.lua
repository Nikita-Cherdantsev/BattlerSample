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
	isLeveling = false,      -- boolean
	isLootOpInFlight = false, -- boolean
	lastError = nil,         -- { code: string, message: string }?
}

local profileReady = false
local profileReadyEvent = Instance.new("BindableEvent")

-- Subscribers
local subscribers = {}

-- Utility functions
local function notifySubscribers()
	for _, callback in pairs(subscribers) do
		callback(state)
	end
end

local function log(message, ...)
	local args = {...}
	for i, arg in ipairs(args) do
		args[i] = tostring(arg)
	end
	
	-- Use pcall to safely format the message
	local success, formattedMessage = pcall(string.format, message, table.unpack(args))
	if success then
		print(string.format("[ClientState] %s", formattedMessage))
	else
		-- Fallback: just print the message and args separately
		print(string.format("[ClientState] %s", message))
		for i, arg in ipairs(args) do
			print(string.format("  Arg %d: %s", i, arg))
		end
	end
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
		-- Clear loading flags on error
		state.isSavingDeck = false
		state.isLeveling = false
		log("Profile update error: %s", payload.error.message)
		return
	end
	
	-- Clear any previous errors and loading flags on success
	ClientState.setLastError(nil)
	state.isSavingDeck = false
	state.isLeveling = false
	state.isLootOpInFlight = false
	
	-- Update server time
	if payload.serverNow then
		state.serverNow = payload.serverNow
	end
	
	-- Update profile data (merge with existing if available)
	if payload.deck or payload.collectionSummary or payload.loginInfo or payload.squadPower or payload.lootboxes or payload.pendingLootbox or payload.currencies or payload.playtime then
		-- Create or update profile
		local didCreateProfile = false
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
				lootboxes = {},
				playtime = {
					totalTime = 0,
					lastSyncTime = 0,
					claimedRewards = {}
				}
			}
			didCreateProfile = true
		end
		
		-- Update deck
		if payload.deck then
			state.profile.deck = payload.deck
		end
		
		-- Update collection
		if payload.collectionSummary then
			-- Ensure collection exists
			if not state.profile.collection then
				state.profile.collection = {}
			end
			
			-- Merge collection updates (collectionSummary is a partial update)
			for _, card in ipairs(payload.collectionSummary) do
				if card.cardId then
					state.profile.collection[card.cardId] = {
						count = card.count or 0,
						level = card.level or 1
					}
				end
			end
			
			log("Collection updated: %d cards in summary", #payload.collectionSummary)
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
		
		-- Update pending lootbox
		if payload.pendingLootbox ~= nil then
			state.profile.pendingLootbox = payload.pendingLootbox
		end
		
		-- Update currencies
		if payload.currencies then
			state.profile.currencies = payload.currencies
		end

		-- Update playtime
		if payload.playtime then
			state.profile.playtime = payload.playtime
		end
		
		local collectionSize = 0
		if state.profile.collection then
			for _ in pairs(state.profile.collection) do
				collectionSize = collectionSize + 1
			end
		end
		
		log("Profile updated: deck=%d cards, squadPower=%.3f, lootboxes=%d, collection=%d cards", 
			#state.profile.deck, state.profile.squadPower, #state.profile.lootboxes, collectionSize)
		
		if not profileReady and state.profile then
			profileReady = true
			profileReadyEvent:Fire(state.profile)
		end
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

-- Set leveling state
function ClientState.setIsLeveling(isLeveling)
	state.isLeveling = isLeveling
	log("Leveling: %s", tostring(isLeveling))
	notifySubscribers()
end

-- Set last error
function ClientState.setLastError(error)
	state.lastError = error
	if error then
		log("Error set: %s - %s", tostring(error.code), tostring(error.message))
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

-- Set lootbox operation in flight state
function ClientState.setIsLootBusy(isBusy)
	state.isLootOpInFlight = isBusy
	log("Loot operation busy: %s", tostring(isBusy))
	notifySubscribers()
end

-- Get lootbox operation state
function ClientState.isLootBusy()
	return state.isLootOpInFlight
end

function ClientState.isProfileReady()
	return profileReady
end

function ClientState.onProfileReady(callback)
	if profileReady then
		task.spawn(callback, state.profile)
		return function() end
	end
	local connection = profileReadyEvent.Event:Connect(callback)
	return function()
		if connection.Connected then
			connection:Disconnect()
		end
	end
end

function ClientState.waitForProfile(timeoutSeconds)
	if profileReady then
		return state.profile
	end
	
	if timeoutSeconds and timeoutSeconds > 0 then
		local profileResult = nil
		local completed = false
		local connection
		
		connection = profileReadyEvent.Event:Connect(function(profile)
			profileResult = profile
			completed = true
		end)
		
		local elapsed = 0
		local step = 0.1
		while not completed and elapsed < timeoutSeconds do
			elapsed = elapsed + step
			task.wait(step)
		end
		
		if connection and connection.Connected then
			connection:Disconnect()
		end
		
		return profileResult or state.profile
	end
	
	local ok, profile = pcall(function()
		return profileReadyEvent.Event:Wait()
	end)
	
	if ok then
		return profile or state.profile
	end
	
	return state.profile
end

return ClientState
