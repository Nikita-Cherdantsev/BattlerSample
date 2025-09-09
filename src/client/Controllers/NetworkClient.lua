--[[
	NetworkClient - Client-side RemoteEvent wrapper
	
	Provides a clean API for communicating with the server,
	including debouncing, error handling, and time synchronization.
]]

local NetworkClient = {}

-- Config
local Config = require(script.Parent.Parent.Config)

local MockNetwork = require(script.Parent.Parent.Dev.MockNetwork)

-- Debug flag
local DEBUG = Config.DEBUG_LOGS

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Client modules
local Utilities = require(script.Parent.Parent.Utilities)
local Types = Utilities.Types
local ErrorMap = Utilities.ErrorMap

-- RemoteEvents
local Network = ReplicatedStorage:WaitForChild("Network")
local RequestProfile = Network:WaitForChild("RequestProfile")
local ProfileUpdated = Network:WaitForChild("ProfileUpdated")
local RequestSetDeck = Network:WaitForChild("RequestSetDeck")
local RequestStartMatch = Network:WaitForChild("RequestStartMatch")
local RequestLevelUpCard = Network:WaitForChild("RequestLevelUpCard")
local RequestLootState = Network:WaitForChild("RequestLootState")
local RequestAddBox = Network:WaitForChild("RequestAddBox")
local RequestResolvePendingDiscard = Network:WaitForChild("RequestResolvePendingDiscard")
local RequestResolvePendingReplace = Network:WaitForChild("RequestResolvePendingReplace")
local RequestStartUnlock = Network:WaitForChild("RequestStartUnlock")
local RequestOpenNow = Network:WaitForChild("RequestOpenNow")
local RequestCompleteUnlock = Network:WaitForChild("RequestCompleteUnlock")

-- State
local lastServerNow = 0
local lastProfileRequest = 0
local lastSetDeckRequest = 0
local lastLevelUpRequest = 0
local lastLootStateRequest = 0
local lastAddBoxRequest = 0
local lastResolvePendingDiscardRequest = 0
local lastResolvePendingReplaceRequest = 0
local lastStartUnlockRequest = 0
local lastOpenNowRequest = 0
local lastCompleteUnlockRequest = 0
local DEBOUNCE_MS = 300

-- Utility functions
local function log(message, ...)
	if DEBUG then
		print(string.format("[NetworkClient] %s", string.format(message, ...)))
	end
end

local function debounce(lastRequestTime)
	local now = tick() * 1000
	if now - lastRequestTime < DEBOUNCE_MS then
		return true
	end
	return false
end

-- Public API

-- Request profile from server
function NetworkClient.requestProfile()
	if Config.USE_MOCKS then
		return MockNetwork.requestProfile()
	end
	
	if debounce(lastProfileRequest) then
		log("Debouncing profile request")
		return
	end
	
	lastProfileRequest = tick() * 1000
	log("Requesting profile")
	RequestProfile:FireServer({})
end

-- Request deck update
function NetworkClient.requestSetDeck(deckIds)
	if Config.USE_MOCKS then
		return MockNetwork.requestSetDeck(deckIds)
	end
	
	if not deckIds or #deckIds ~= 6 then
		return false, "Invalid deck: must have exactly 6 cards"
	end
	
	if debounce(lastSetDeckRequest) then
		log("Debouncing deck update request")
		return false, "Request too frequent, please wait"
	end
	
	lastSetDeckRequest = tick() * 1000
	log("Requesting deck update: %s", table.concat(deckIds, ", "))
	RequestSetDeck:FireServer({deck = deckIds})
	
	return true
end

-- Request match start
function NetworkClient.requestStartMatch(opts)
	if Config.USE_MOCKS then
		return MockNetwork.requestStartMatch(opts)
	end
	
	opts = opts or {}
	local requestData = {
		mode = opts.mode or "PvE",
		seed = opts.seed,
		variant = opts.variant
	}
	
	log("Requesting match start: mode=%s", requestData.mode)
	RequestStartMatch:FireServer(requestData)
end

-- Request card level-up
function NetworkClient.requestLevelUpCard(cardId)
	if Config.USE_MOCKS then
		return MockNetwork.requestLevelUpCard(cardId)
	end
	
	if not cardId or type(cardId) ~= "string" then
		return false, "Invalid card ID"
	end
	
	if debounce(lastLevelUpRequest) then
		log("Debouncing level-up request")
		return false, "Request too frequent, please wait"
	end
	
	lastLevelUpRequest = tick() * 1000
	log("Requesting level-up for card: %s", cardId)
	RequestLevelUpCard:FireServer({cardId = cardId})
	
	return true
end

-- Subscribe to profile updates
function NetworkClient.onProfileUpdated(callback)
	if Config.USE_MOCKS then
		return MockNetwork.onProfileUpdated(callback)
	end
	
	return ProfileUpdated.OnClientEvent:Connect(function(payload)
		-- Update server time
		if payload.serverNow then
			lastServerNow = payload.serverNow
		end
		
		-- Normalize error handling
		if payload.error then
			local userMessage = ErrorMap.toUserMessage(payload.error.code, payload.error.message)
			log("Profile update error: %s - %s", userMessage.title, userMessage.message)
		else
			log("Profile updated successfully")
		end
		
		callback(payload)
	end)
end

-- Subscribe to profile updates (one-time)
function NetworkClient.onceProfile(callback)
	if Config.USE_MOCKS then
		return MockNetwork.onceProfile(callback)
	end
	
	local connection
	connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
		-- Update server time
		if payload.serverNow then
			lastServerNow = payload.serverNow
		end
		
		-- Normalize error handling
		if payload.error then
			local userMessage = ErrorMap.toUserMessage(payload.error.code, payload.error.message)
			log("Profile update error: %s - %s", userMessage.title, userMessage.message)
		else
			log("Profile snapshot received")
		end
		
		callback(payload)
		connection:Disconnect()
	end)
end

-- Get last known server time
function NetworkClient.getServerNow()
	if Config.USE_MOCKS then
		return MockNetwork.getServerNow()
	end
	return lastServerNow
end

-- Get current client time (approximate)
function NetworkClient.getClientTime()
	if Config.USE_MOCKS then
		return MockNetwork.getClientTime()
	end
	
	if lastServerNow == 0 then
		return os.time()
	end
	
	-- Estimate current time based on last server time
	local timeSinceLastUpdate = os.time() - lastServerNow
	return lastServerNow + timeSinceLastUpdate
end

-- Lootbox methods

-- Request loot state from server
function NetworkClient.requestLootState()
	if Config.USE_MOCKS then
		return MockNetwork.requestLootState()
	end
	
	if debounce(lastLootStateRequest) then
		log("Debouncing loot state request")
		return false, "Request too frequent, please wait"
	end
	
	lastLootStateRequest = tick() * 1000
	log("Requesting loot state")
	RequestLootState:FireServer({})
	
	return true
end

-- Request add box (dev/test only)
function NetworkClient.requestAddBox(rarity, source)
	if Config.USE_MOCKS then
		return MockNetwork.requestAddBox(rarity, source)
	end
	
	if not rarity or type(rarity) ~= "string" then
		return false, "Invalid rarity"
	end
	
	if debounce(lastAddBoxRequest) then
		log("Debouncing add box request")
		return false, "Request too frequent, please wait"
	end
	
	lastAddBoxRequest = tick() * 1000
	log("Requesting add box: %s", rarity)
	RequestAddBox:FireServer({rarity = rarity, source = source})
	
	return true
end

-- Request resolve pending discard
function NetworkClient.requestResolvePendingDiscard()
	if Config.USE_MOCKS then
		return MockNetwork.requestResolvePendingDiscard()
	end
	
	if debounce(lastResolvePendingDiscardRequest) then
		log("Debouncing resolve pending discard request")
		return false, "Request too frequent, please wait"
	end
	
	lastResolvePendingDiscardRequest = tick() * 1000
	log("Requesting resolve pending discard")
	RequestResolvePendingDiscard:FireServer({})
	
	return true
end

-- Request resolve pending replace
function NetworkClient.requestResolvePendingReplace(slotIndex)
	if Config.USE_MOCKS then
		return MockNetwork.requestResolvePendingReplace(slotIndex)
	end
	
	if not slotIndex or type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 4 then
		return false, "Invalid slot index"
	end
	
	if debounce(lastResolvePendingReplaceRequest) then
		log("Debouncing resolve pending replace request")
		return false, "Request too frequent, please wait"
	end
	
	lastResolvePendingReplaceRequest = tick() * 1000
	log("Requesting resolve pending replace: slot %d", slotIndex)
	RequestResolvePendingReplace:FireServer({slotIndex = slotIndex})
	
	return true
end

-- Request start unlock
function NetworkClient.requestStartUnlock(slotIndex)
	if Config.USE_MOCKS then
		return MockNetwork.requestStartUnlock(slotIndex)
	end
	
	if not slotIndex or type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 4 then
		return false, "Invalid slot index"
	end
	
	if debounce(lastStartUnlockRequest) then
		log("Debouncing start unlock request")
		return false, "Request too frequent, please wait"
	end
	
	lastStartUnlockRequest = tick() * 1000
	log("Requesting start unlock: slot %d", slotIndex)
	RequestStartUnlock:FireServer({slotIndex = slotIndex})
	
	return true
end

-- Request open now
function NetworkClient.requestOpenNow(slotIndex)
	if Config.USE_MOCKS then
		return MockNetwork.requestOpenNow(slotIndex)
	end
	
	if not slotIndex or type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 4 then
		return false, "Invalid slot index"
	end
	
	if debounce(lastOpenNowRequest) then
		log("Debouncing open now request")
		return false, "Request too frequent, please wait"
	end
	
	lastOpenNowRequest = tick() * 1000
	log("Requesting open now: slot %d", slotIndex)
	RequestOpenNow:FireServer({slotIndex = slotIndex})
	
	return true
end

-- Request complete unlock
function NetworkClient.requestCompleteUnlock(slotIndex)
	if Config.USE_MOCKS then
		return MockNetwork.requestCompleteUnlock(slotIndex)
	end
	
	if not slotIndex or type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 4 then
		return false, "Invalid slot index"
	end
	
	if debounce(lastCompleteUnlockRequest) then
		log("Debouncing complete unlock request")
		return false, "Request too frequent, please wait"
	end
	
	lastCompleteUnlockRequest = tick() * 1000
	log("Requesting complete unlock: slot %d", slotIndex)
	RequestCompleteUnlock:FireServer({slotIndex = slotIndex})
	
	return true
end

-- Check if any request is currently in flight
function NetworkClient.isBusy()
	if Config.USE_MOCKS then
		return MockNetwork.isBusy()
	end
	
	local now = tick() * 1000
	local recentThreshold = DEBOUNCE_MS * 2  -- Consider busy if request was made within 2x debounce time
	
	return (now - lastProfileRequest < recentThreshold) or
		   (now - lastSetDeckRequest < recentThreshold) or
		   (now - lastLevelUpRequest < recentThreshold) or
		   (now - lastLootStateRequest < recentThreshold) or
		   (now - lastAddBoxRequest < recentThreshold) or
		   (now - lastResolvePendingDiscardRequest < recentThreshold) or
		   (now - lastResolvePendingReplaceRequest < recentThreshold) or
		   (now - lastStartUnlockRequest < recentThreshold) or
		   (now - lastOpenNowRequest < recentThreshold) or
		   (now - lastCompleteUnlockRequest < recentThreshold)
end

-- Reinitialize NetworkClient (for mock toggle)
function NetworkClient.reinitialize()
	log("Reinitializing NetworkClient")
	
	-- Reset state
	lastServerNow = 0
	lastProfileRequest = 0
	lastSetDeckRequest = 0
	lastLevelUpRequest = 0
	lastLootStateRequest = 0
	lastAddBoxRequest = 0
	lastResolvePendingDiscardRequest = 0
	lastResolvePendingReplaceRequest = 0
	lastStartUnlockRequest = 0
	lastOpenNowRequest = 0
	lastCompleteUnlockRequest = 0
	
	-- Reset mock network if using mocks
	if Config.USE_MOCKS then
		MockNetwork.reset()
	end
	
	log("NetworkClient reinitialized")
end

return NetworkClient
