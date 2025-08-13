local RemoteEvents = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Modules
local PlayerDataService = require(game.ServerScriptService.Services.PlayerDataService)

-- Create RemoteEvents under ReplicatedStorage/Network
local NetworkFolder = Instance.new("Folder")
NetworkFolder.Name = "Network"
NetworkFolder.Parent = ReplicatedStorage

-- Remote Events
local RequestSetDeck = Instance.new("RemoteEvent")
RequestSetDeck.Name = "RequestSetDeck"
RequestSetDeck.Parent = NetworkFolder

local RequestProfile = Instance.new("RemoteEvent")
RequestProfile.Name = "RequestProfile"
RequestProfile.Name = "RequestProfile"
RequestProfile.Parent = NetworkFolder

local ProfileUpdated = Instance.new("RemoteEvent")
ProfileUpdated.Name = "ProfileUpdated"
ProfileUpdated.Parent = NetworkFolder

-- Rate limiting configuration
local RATE_LIMIT = {
	REQUEST_SET_DECK = {
		COOLDOWN = 2, -- seconds between deck update requests
		MAX_REQUESTS = 5 -- max requests per minute
	},
	REQUEST_PROFILE = {
		COOLDOWN = 1, -- seconds between profile requests
		MAX_REQUESTS = 10 -- max requests per minute
	}
}

-- Rate limiting state
local playerRateLimits = {} -- player -> rate limit data

-- Utility functions
local function LogInfo(player, message, ...)
	local playerName = player and player.Name or "Unknown"
	local formattedMessage = string.format(message, ...)
	print(string.format("[RemoteEvents] %s: %s", playerName, formattedMessage))
end

local function LogWarning(player, message, ...)
	local playerName = player and player.Name or "Unknown"
	local formattedMessage = string.format(message, ...)
	warn(string.format("[RemoteEvents] %s: %s", playerName, formattedMessage))
end

local function LogError(player, message, ...)
	local playerName = player and player.Name or "Unknown"
	local formattedMessage = string.format(message, ...)
	error(string.format("[RemoteEvents] %s: %s", playerName, formattedMessage))
end

local function InitializeRateLimit(player)
	if not playerRateLimits[player] then
		playerRateLimits[player] = {
			requestSetDeck = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			requestProfile = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			}
		}
	end
end

local function CheckRateLimit(player, requestType)
	InitializeRateLimit(player)
	local rateLimit = playerRateLimits[player][requestType]
	local config = RATE_LIMIT[requestType:upper()]
	
	local now = os.time()
	
	-- Reset counter if minute has passed
	if now >= rateLimit.resetTime then
		rateLimit.requestCount = 0
		rateLimit.resetTime = now + 60
	end
	
	-- Check cooldown
	if now - rateLimit.lastRequest < config.COOLDOWN then
		return false, "Request too frequent, please wait"
	end
	
	-- Check request count limit
	if rateLimit.requestCount >= config.MAX_REQUESTS then
		return false, "Too many requests, please wait"
	end
	
	-- Update rate limit state
	rateLimit.lastRequest = now
	rateLimit.requestCount = rateLimit.requestCount + 1
	
	return true
end

local function CleanupRateLimit(player)
	playerRateLimits[player] = nil
end

local function SendProfileUpdate(player, payload)
	ProfileUpdated:FireClient(player, payload)
end

local function CreateCollectionSummary(collection)
	local summary = {}
	for cardId, count in pairs(collection) do
		table.insert(summary, {
			cardId = cardId,
			count = count
		})
	end
	return summary
end

local function CreateLoginInfo(player)
	local loginInfo = PlayerDataService.GetLoginInfo(player)
	if loginInfo then
		return {
			lastLoginAt = loginInfo.lastLoginAt,
			loginStreak = loginInfo.loginStreak
		}
	end
	return nil
end

-- Request handlers

local function HandleRequestSetDeck(player, requestData)
	LogInfo(player, "Processing deck update request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "requestSetDeck")
	if not canProceed then
		SendProfileUpdate(player, {
			error = {
				code = "RATE_LIMITED",
				message = errorMessage
			},
			updatedAt = os.time()
		})
		return
	end
	
	-- Validate request data
	if not requestData or not requestData.deck then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_REQUEST",
				message = "Missing deck data"
			},
			updatedAt = os.time()
		})
		return
	end
	
	-- Validate deck via PlayerDataService
	local success, errorMessage = PlayerDataService.SetDeck(player, requestData.deck)
	
	if success then
		-- Get updated profile data
		local profile = PlayerDataService.GetProfile(player)
		local collection = PlayerDataService.GetCollection(player)
		
		-- Send success response
		SendProfileUpdate(player, {
			deck = profile.deck,
			collectionSummary = CreateCollectionSummary(collection),
			updatedAt = os.time()
		})
		
		LogInfo(player, "Deck updated successfully")
	else
		-- Send error response
		SendProfileUpdate(player, {
			error = {
				code = "DECK_UPDATE_FAILED",
				message = errorMessage
			},
			updatedAt = os.time()
		})
		
		LogWarning(player, "Deck update failed: %s", errorMessage)
	end
end

local function HandleRequestProfile(player, requestData)
	LogInfo(player, "Processing profile request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "requestProfile")
	if not canProceed then
		SendProfileUpdate(player, {
			error = {
				code = "RATE_LIMITED",
				message = errorMessage
			},
			updatedAt = os.time()
		})
		return
	end
	
	-- Get profile data via PlayerDataService
	local profile = PlayerDataService.GetProfile(player)
	local collection = PlayerDataService.GetCollection(player)
	local loginInfo = CreateLoginInfo(player)
	
	if profile and collection and loginInfo then
		-- Send profile snapshot
		SendProfileUpdate(player, {
			deck = profile.deck,
			collectionSummary = CreateCollectionSummary(collection),
			loginInfo = loginInfo,
			updatedAt = os.time()
		})
		
		LogInfo(player, "Profile sent successfully")
	else
		-- Send error response
		SendProfileUpdate(player, {
			error = {
				code = "PROFILE_LOAD_FAILED",
				message = "Failed to load profile data"
			},
			updatedAt = os.time()
		})
		
		LogWarning(player, "Failed to load profile data")
	end
end

-- Connect RemoteEvents to handlers
RequestSetDeck.OnServerEvent:Connect(HandleRequestSetDeck)
RequestProfile.OnServerEvent:Connect(HandleRequestProfile)

-- Player cleanup
Players.PlayerRemoving:Connect(function(player)
	CleanupRateLimit(player)
end)

-- Public API for other server modules
RemoteEvents.RequestSetDeck = RequestSetDeck
RemoteEvents.RequestProfile = RequestProfile
RemoteEvents.ProfileUpdated = ProfileUpdated

-- Utility functions for other modules
function RemoteEvents.SendProfileUpdate(player, payload)
	SendProfileUpdate(player, payload)
end

function RemoteEvents.GetRateLimitStatus(player)
	if not playerRateLimits[player] then
		return nil
	end
	
	local status = {}
	for requestType, data in pairs(playerRateLimits[player]) do
		status[requestType] = {
			lastRequest = data.lastRequest,
			requestCount = data.requestCount,
			resetTime = data.resetTime
		}
	end
	
	return status
end

LogInfo(nil, "RemoteEvents initialized successfully")

return RemoteEvents
