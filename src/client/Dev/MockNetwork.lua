--[[
	MockNetwork - Drop-in replacement for NetworkClient
	
	Provides the same API as NetworkClient but uses MockData
	to simulate server responses for UI development without a server.
]]

local MockData = require(script.Parent.MockData)
local Config = require(script.Parent.Parent.Config)
local Utilities = require(script.Parent.Parent.Utilities)
local Types = Utilities.Types



local MockNetwork = {}

-- State
local profileSubscribers = {}
local currentProfile = nil
local lastServerNow = 0

-- Utility functions
local function log(message, ...)
	if Config.DEBUG_LOGS then
		print(string.format("[MockNetwork] %s", string.format(message, ...)))
	end
end

local function delay(ms)
	ms = ms or Config.MOCK_SETTINGS.NETWORK_LATENCY_MS
	task.wait(ms / 1000)
end

local function emitProfileUpdate(payload)
	lastServerNow = payload.serverNow or os.time()
	
	for _, callback in pairs(profileSubscribers) do
		task.spawn(function()
			callback(payload)
		end)
	end
end

-- Public API (matches NetworkClient interface)

-- Request profile from mock server
function MockNetwork.requestProfile()
	log("Requesting profile (mock)")
	
	delay(Config.MOCK_SETTINGS.PROFILE_UPDATE_DELAY_MS)
	
	-- Create mock profile
	currentProfile = MockData.makeProfileSnapshot()
	local payload = MockData.makeProfileUpdatedPayload(currentProfile)
	
	log("Profile requested successfully (mock)")
	emitProfileUpdate(payload)
end

-- Request deck update
function MockNetwork.requestSetDeck(deckIds)
	if not deckIds or #deckIds ~= 6 then
		log("Invalid deck: must have exactly 6 cards")
		return false, "Invalid deck: must have exactly 6 cards"
	end
	
	log("Requesting deck update (mock): %s", table.concat(deckIds, ", "))
	
	-- Validate deck using client-side validator
	local isValid, errorMessage = Utilities.DeckValidator.ValidateDeck(deckIds)
	if not isValid then
		log("Deck validation failed: %s", errorMessage)
		return false, errorMessage
	end
	
	delay(Config.MOCK_SETTINGS.PROFILE_UPDATE_DELAY_MS)
	
	-- Update current profile
	if currentProfile then
		currentProfile.deck = deckIds
		
		-- Recompute squad power (simplified for client)
		currentProfile.squadPower = 0
		for _, cardId in ipairs(deckIds) do
			-- Simple power calculation (same as in MockData)
			local basePower = 100
			local rarityBonus = {
				[Types.Rarity.Common] = 0,
				[Types.Rarity.Rare] = 50,
				[Types.Rarity.Epic] = 150,
				[Types.Rarity.Legendary] = 300
			}
			-- Get rarity from collection or use Common as default
			local rarity = Types.Rarity.Common
			if currentProfile.collection[cardId] then
				-- For now, assign rarity based on card ID pattern
				if string.find(cardId, "Legendary") then
					rarity = Types.Rarity.Legendary
				elseif string.find(cardId, "Epic") then
					rarity = Types.Rarity.Epic
				elseif string.find(cardId, "Rare") then
					rarity = Types.Rarity.Rare
				end
			end
			currentProfile.squadPower = currentProfile.squadPower + basePower + (rarityBonus[rarity] or 0)
		end
		
		-- Emit profile update
		local payload = MockData.makeProfileUpdatedPayload(currentProfile)
		log("Deck updated successfully (mock)")
		emitProfileUpdate(payload)
	else
		log("No profile available for deck update")
		return false, "No profile available"
	end
	
	return true
end

-- Request match start
function MockNetwork.requestStartMatch(opts)
	opts = opts or {}
	local mode = opts.mode or "PvE"
	
	log("Requesting match start (mock): mode=%s", mode)
	
	delay(Config.MOCK_SETTINGS.MATCH_RESPONSE_DELAY_MS)
	
	-- Simulate match response
	local response = MockData.makeMatchResponse(true)
	log("Match started successfully (mock): %s", response.matchId)
	
	-- Return response (in real NetworkClient this would be handled differently)
	return response
end

-- Request card level-up
function MockNetwork.requestLevelUpCard(cardId)
	if not cardId or type(cardId) ~= "string" then
		local payload = MockData.makeErrorResponse("INVALID_REQUEST", "Invalid card ID")
		emitProfileUpdate(payload)
		return false, "Invalid card ID"
	end
	
	log("Requesting level-up for card (mock): %s", cardId)
	
	delay(Config.MOCK_SETTINGS.PROFILE_UPDATE_DELAY_MS)
	
	if not currentProfile then
		local payload = MockData.makeErrorResponse("INTERNAL", "No profile available")
		emitProfileUpdate(payload)
		return false, "No profile available"
	end
	
	-- Validation 1: Card exists in catalog
	local card = Utilities.CardCatalog.GetCard(cardId)
	if not card then
		local payload = MockData.makeErrorResponse("INVALID_REQUEST", "Card ID not found in catalog: " .. cardId)
		emitProfileUpdate(payload)
		return false, "Card ID not found in catalog: " .. cardId
	end
	
	-- Validation 2: Player owns this card
	local entry = currentProfile.collection[cardId]
	if not entry then
		local payload = MockData.makeErrorResponse("CARD_NOT_OWNED", "Card not found in collection")
		emitProfileUpdate(payload)
		return false, "CARD_NOT_OWNED"
	end
	
	-- Validation 3: Current level < 7
	if entry.level >= Utilities.CardLevels.MAX_LEVEL then
		local payload = MockData.makeErrorResponse("LEVEL_MAXED", "Card is already at maximum level")
		emitProfileUpdate(payload)
		return false, "LEVEL_MAXED"
	end
	
	-- Validation 4: Check next level cost
	local nextLevel = entry.level + 1
	local cost = Utilities.CardLevels.GetLevelCost(nextLevel)
	if not cost then
		local payload = MockData.makeErrorResponse("INTERNAL", "Invalid level cost for level " .. nextLevel)
		emitProfileUpdate(payload)
		return false, "Invalid level cost for level " .. nextLevel
	end
	
	-- Validation 5: Sufficient copies
	if entry.count < cost.requiredCount then
		local payload = MockData.makeErrorResponse("INSUFFICIENT_COPIES", "Need " .. cost.requiredCount .. " copies (have " .. entry.count .. ")")
		emitProfileUpdate(payload)
		return false, "INSUFFICIENT_COPIES"
	end
	
	-- Validation 6: Sufficient soft currency
	if currentProfile.currencies.soft < cost.softAmount then
		local payload = MockData.makeErrorResponse("INSUFFICIENT_SOFT", "Need " .. cost.softAmount .. " soft currency (have " .. currentProfile.currencies.soft .. ")")
		emitProfileUpdate(payload)
		return false, "INSUFFICIENT_SOFT"
	end
	
	-- Perform atomic level-up (mirror server behavior)
	entry.count = entry.count - cost.requiredCount
	entry.level = entry.level + 1
	currentProfile.currencies.soft = currentProfile.currencies.soft - cost.softAmount
	
	-- Check if this card is in the active deck and recompute squad power
	local isInDeck = false
	for _, deckCardId in ipairs(currentProfile.deck) do
		if deckCardId == cardId then
			isInDeck = true
			break
		end
	end
	
	if isInDeck then
		-- Recompute squad power (simplified for mocks)
		local totalPower = 0
		for _, deckCardId in ipairs(currentProfile.deck) do
			local deckEntry = currentProfile.collection[deckCardId]
			if deckEntry then
				local stats = Utilities.CardStats.ComputeStats(deckCardId, deckEntry.level)
				totalPower = totalPower + Utilities.CardStats.ComputePower(stats)
			end
		end
		currentProfile.squadPower = totalPower
	end
	
	-- Emit profile update with server-like payload structure
	local payload = MockData.makeProfileUpdatedPayload(currentProfile)
	log("Card %s leveled up successfully (mock) to level %d (cost: %d copies, %d soft)", 
		cardId, entry.level, cost.requiredCount, cost.softAmount)
	emitProfileUpdate(payload)
	
	return true
end

-- Subscribe to profile updates
function MockNetwork.onProfileUpdated(callback)
	local id = tostring(callback)
	profileSubscribers[id] = callback
	
	log("Profile subscriber added (mock)")
	
	-- Return a connection-like object
	return {
		Disconnect = function()
			profileSubscribers[id] = nil
			log("Profile subscriber removed (mock)")
		end
	}
end

-- Subscribe to profile updates (one-time)
function MockNetwork.onceProfile(callback)
	local connection
	connection = MockNetwork.onProfileUpdated(function(payload)
		callback(payload)
		connection:Disconnect()
	end)
	
	return connection
end

-- Get last known server time
function MockNetwork.getServerNow()
	return lastServerNow
end

-- Get current client time (approximate)
function MockNetwork.getClientTime()
	if lastServerNow == 0 then
		return os.time()
	end
	
	-- Estimate current time based on last server time
	local timeSinceLastUpdate = os.time() - lastServerNow
	return lastServerNow + timeSinceLastUpdate
end

-- Check if any request is currently in flight (mock always returns false)
function MockNetwork.isBusy()
	return false  -- Mock network is always available
end

-- Mock-specific methods

-- Get current mock profile
function MockNetwork.getCurrentProfile()
	return currentProfile
end

-- Set mock profile (for testing)
function MockNetwork.setMockProfile(profile)
	currentProfile = profile
	if profile then
		local payload = MockData.makeProfileUpdatedPayload(profile)
		emitProfileUpdate(payload)
	end
end

-- Simulate error response
function MockNetwork.simulateError(errorCode, message)
	log("Simulating error: %s - %s", errorCode, message)
	
	delay(Config.MOCK_SETTINGS.PROFILE_UPDATE_DELAY_MS)
	
	local errorPayload = {
		error = {
			code = errorCode or "INTERNAL",
			message = message or "An unexpected error occurred"
		},
		serverNow = os.time()
	}
	
	emitProfileUpdate(errorPayload)
end

-- Simulate rate limiting
function MockNetwork.simulateRateLimit()
	MockNetwork.simulateError("RATE_LIMITED", "Request too frequent, please wait")
end

-- Reset mock state
function MockNetwork.reset()
	currentProfile = nil
	lastServerNow = 0
	profileSubscribers = {}
	log("Mock network reset")
end

return MockNetwork
