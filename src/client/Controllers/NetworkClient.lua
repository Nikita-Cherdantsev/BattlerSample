--[[
	NetworkClient - Client-side RemoteEvent wrapper
	
	Provides a clean API for communicating with the server,
	including debouncing, error handling, and time synchronization.
]]

local NetworkClient = {}

-- Config
local Config = require(script.Parent.Parent.Config)

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
local RequestSpeedUp = Network:WaitForChild("RequestSpeedUp")
local RequestOpenNow = Network:WaitForChild("RequestOpenNow")
local RequestCompleteUnlock = Network:WaitForChild("RequestCompleteUnlock")
local RequestGetShopPacks = Network:WaitForChild("RequestGetShopPacks")
local RequestStartPackPurchase = Network:WaitForChild("RequestStartPackPurchase")
local RequestBuyLootbox = Network:WaitForChild("RequestBuyLootbox")
local RequestPlaytimeData = Network:WaitForChild("RequestPlaytimeData")
local RequestClaimPlaytimeReward = Network:WaitForChild("RequestClaimPlaytimeReward")

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
local lastGetShopPacksRequest = 0
local lastStartPackPurchaseRequest = 0
local lastBuyLootboxRequest = 0
local lastPlaytimeDataRequest = 0
local lastClaimPlaytimeRewardRequest = 0
local DEBOUNCE_MS = 300

-- Utility functions
local function log(message, ...)
	-- Optional: Enable for debugging
	-- print(string.format("[NetworkClient] %s", string.format(message, ...)))
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
	if not deckIds or #deckIds > 6 then
		return false, "Invalid deck: must have between 0 and 6 cards"
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
	return lastServerNow
end

-- Get current client time (approximate)
function NetworkClient.getClientTime()
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

-- Request speed up
function NetworkClient.requestSpeedUp(slotIndex)
	if not slotIndex or type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 4 then
		return false, "Invalid slot index"
	end
	
	if debounce(lastOpenNowRequest) then
		log("Debouncing speed up request")
		return false, "Request too frequent, please wait"
	end
	
	lastOpenNowRequest = os.time()
	
	log("Requesting speed up: slot %d", slotIndex)
	RequestSpeedUp:FireServer({slotIndex = slotIndex})
	
	return true
end

-- Request open now
function NetworkClient.requestOpenNow(slotIndex)
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

-- Shop methods
function NetworkClient.requestGetShopPacks()
	if debounce(lastGetShopPacksRequest) then
		log("Debouncing get shop packs request")
		return false, "Request too frequent, please wait"
	end
	
	lastGetShopPacksRequest = tick() * 1000
	log("Requesting shop packs")
	RequestGetShopPacks:FireServer({})
	
	return true
end

function NetworkClient.requestStartPackPurchase(packId)
	if not packId or type(packId) ~= "string" then
		return false, "Invalid pack ID"
	end
	
	if debounce(lastStartPackPurchaseRequest) then
		log("Debouncing start pack purchase request")
		return false, "Request too frequent, please wait"
	end
	
	lastStartPackPurchaseRequest = tick() * 1000
	log("Requesting start pack purchase: %s", packId)
	RequestStartPackPurchase:FireServer({packId = packId})
	
	return true
end

function NetworkClient.requestBuyLootbox(rarity)
	if not rarity or type(rarity) ~= "string" then
		return false, "Invalid rarity"
	end
	
	if debounce(lastBuyLootboxRequest) then
		log("Debouncing buy lootbox request")
		return false, "Request too frequent, please wait"
	end
	
	lastBuyLootboxRequest = tick() * 1000
	log("Requesting buy lootbox: %s", rarity)
	RequestBuyLootbox:FireServer({rarity = rarity})
	
	return true
end

-- Playtime methods
function NetworkClient.requestPlaytimeData()
	if debounce(lastPlaytimeDataRequest) then
		log("Debouncing playtime data request")
		return false, "Request too frequent, please wait"
	end
	
	lastPlaytimeDataRequest = tick() * 1000
	log("Requesting playtime data")
	RequestPlaytimeData:FireServer({})
	
	return true
end

function NetworkClient.requestClaimPlaytimeReward(rewardIndex)
	if not rewardIndex or type(rewardIndex) ~= "number" or rewardIndex < 1 or rewardIndex > 7 then
		return false, "Invalid reward index"
	end
	
	if debounce(lastClaimPlaytimeRewardRequest) then
		log("Debouncing claim playtime reward request")
		return false, "Request too frequent, please wait"
	end
	
	lastClaimPlaytimeRewardRequest = tick() * 1000
	log("Requesting claim playtime reward: %d", rewardIndex)
	RequestClaimPlaytimeReward:FireServer({rewardIndex = rewardIndex})
	
	return true
end

-- Check if any request is currently in flight
function NetworkClient.isBusy()
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
		   (now - lastCompleteUnlockRequest < recentThreshold) or
		   (now - lastGetShopPacksRequest < recentThreshold) or
		   (now - lastStartPackPurchaseRequest < recentThreshold) or
		   (now - lastBuyLootboxRequest < recentThreshold) or
		   (now - lastPlaytimeDataRequest < recentThreshold) or
		   (now - lastClaimPlaytimeRewardRequest < recentThreshold)
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
	lastGetShopPacksRequest = 0
	lastStartPackPurchaseRequest = 0
	lastBuyLootboxRequest = 0
	lastPlaytimeDataRequest = 0
	lastClaimPlaytimeRewardRequest = 0
	
	log("NetworkClient reinitialized")
end

return NetworkClient
