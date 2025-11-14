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
local RequestDailyData = Network:WaitForChild("RequestDailyData")
local RequestClaimDailyReward = Network:WaitForChild("RequestClaimDailyReward")
local RequestClaimBattleReward = Network:WaitForChild("RequestClaimBattleReward")

-- State
local lastServerNow = 0

-- Utility functions
local function log(message, ...)
	-- Optional: Enable for debugging
	-- print(string.format("[NetworkClient] %s", string.format(message, ...)))
end

-- Public API

-- Request profile from server
function NetworkClient.requestProfile()
	log("Requesting profile")
	RequestProfile:FireServer({})
end

-- Request deck update
function NetworkClient.requestSetDeck(deckIds)
	if not deckIds or #deckIds > 6 then
		return false, "Invalid deck: must have between 0 and 6 cards"
	end
	
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
		variant = opts.variant,
		partName = opts.partName -- Include part name for NPC/Boss mode detection
	}
	
	log("Requesting match start: mode=%s, partName=%s", requestData.mode, tostring(requestData.partName))
	RequestStartMatch:FireServer(requestData)
end

-- Set match result callback
function NetworkClient.setMatchResultCallback(callback)
	NetworkClient.onMatchResult = callback
end

-- Listen for match results
RequestStartMatch.OnClientEvent:Connect(function(response)
	log("Received match result: ok=%s", tostring(response.ok))
	print("🔍 NetworkClient: Match result received:", response)
	
	-- Notify BattlePrepHandler of the response
	if NetworkClient.onMatchResult then
		print("🔍 NetworkClient: Calling match result callback")
		NetworkClient.onMatchResult(response)
	else
		warn("NetworkClient: No match result callback set")
	end
end)

-- Request card level-up
function NetworkClient.requestLevelUpCard(cardId)
	if not cardId or type(cardId) ~= "string" then
		return false, "Invalid card ID"
	end
	
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
	log("Requesting loot state")
	RequestLootState:FireServer({})
	
	return true
end

-- Request add box (dev/test only)
function NetworkClient.requestAddBox(rarity, source)
	if not rarity or type(rarity) ~= "string" then
		return false, "Invalid rarity"
	end
	
	log("Requesting add box: %s", rarity)
	RequestAddBox:FireServer({rarity = rarity, source = source})
	
	return true
end

-- Request resolve pending discard
function NetworkClient.requestResolvePendingDiscard()
	log("Requesting resolve pending discard")
	RequestResolvePendingDiscard:FireServer({})
	
	return true
end

-- Request resolve pending replace
function NetworkClient.requestResolvePendingReplace(slotIndex)
	if not slotIndex or type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 4 then
		return false, "Invalid slot index"
	end
	
	log("Requesting resolve pending replace: slot %d", slotIndex)
	RequestResolvePendingReplace:FireServer({slotIndex = slotIndex})
	
	return true
end

-- Request start unlock
function NetworkClient.requestStartUnlock(slotIndex)
	if not slotIndex or type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 4 then
		return false, "Invalid slot index"
	end
	
	log("Requesting start unlock: slot %d", slotIndex)
	RequestStartUnlock:FireServer({slotIndex = slotIndex})
	
	return true
end

-- Request speed up
function NetworkClient.requestSpeedUp(slotIndex)
	if not slotIndex or type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 4 then
		return false, "Invalid slot index"
	end
	
	log("Requesting speed up: slot %d", slotIndex)
	RequestSpeedUp:FireServer({slotIndex = slotIndex})
	
	return true
end

-- Request open now
function NetworkClient.requestOpenNow(slotIndex)
	if not slotIndex or type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 4 then
		return false, "Invalid slot index"
	end
	
	log("Requesting open now: slot %d", slotIndex)
	RequestOpenNow:FireServer({slotIndex = slotIndex})
	
	return true
end

-- Request claim battle reward
function NetworkClient.requestClaimBattleReward(requestData)
	if not requestData or not requestData.rewardType then
		return false, "Invalid request data"
	end
	
	log("Requesting claim battle reward: type=%s", requestData.rewardType)
	RequestClaimBattleReward:FireServer(requestData)
	
	return true
end

-- Request complete unlock
function NetworkClient.requestCompleteUnlock(slotIndex)
	if not slotIndex or type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 4 then
		return false, "Invalid slot index"
	end
	
	log("Requesting complete unlock: slot %d", slotIndex)
	RequestCompleteUnlock:FireServer({slotIndex = slotIndex})
	
	return true
end

-- Shop methods
function NetworkClient.requestGetShopPacks()
	log("Requesting shop packs")
	RequestGetShopPacks:FireServer({})
	
	return true
end

function NetworkClient.requestStartPackPurchase(packId)
	if not packId or type(packId) ~= "string" then
		return false, "Invalid pack ID"
	end
	
	log("Requesting start pack purchase: %s", packId)
	RequestStartPackPurchase:FireServer({packId = packId})
	
	return true
end

function NetworkClient.requestBuyLootbox(rarity)
	if not rarity or type(rarity) ~= "string" then
		return false, "Invalid rarity"
	end
	
	log("Requesting buy lootbox: %s", rarity)
	RequestBuyLootbox:FireServer({rarity = rarity})
	
	return true
end

-- Playtime methods
function NetworkClient.requestPlaytimeData()
	log("Requesting playtime data")
	RequestPlaytimeData:FireServer({})
	
	return true
end

function NetworkClient.requestClaimPlaytimeReward(rewardIndex)
	if not rewardIndex or type(rewardIndex) ~= "number" or rewardIndex < 1 or rewardIndex > 7 then
		return false, "Invalid reward index"
	end
	
	log("Requesting claim playtime reward: %d", rewardIndex)
	RequestClaimPlaytimeReward:FireServer({rewardIndex = rewardIndex})
	
	return true
end

-- Daily methods
function NetworkClient.requestDailyData()
	log("Requesting daily data")
	RequestDailyData:FireServer({})
	
	return true
end

function NetworkClient.requestClaimDailyReward(rewardIndex)
	if not rewardIndex or type(rewardIndex) ~= "number" or rewardIndex < 1 or rewardIndex > 7 then
		return false, "Invalid reward index"
	end
	
	log("Requesting claim daily reward: %d", rewardIndex)
	RequestClaimDailyReward:FireServer({rewardIndex = rewardIndex})
	
	return true
end

-- Check if any request is currently in flight (always returns false now - no rate limiting)
function NetworkClient.isBusy()
	return false
end

-- Reinitialize NetworkClient (for mock toggle)
function NetworkClient.reinitialize()
	log("Reinitializing NetworkClient")
	
	-- Reset state
	lastServerNow = 0
	
	log("NetworkClient reinitialized")
end

return NetworkClient
