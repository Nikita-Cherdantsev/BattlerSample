local RemoteEvents = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Modules
local PlayerDataService = require(game.ServerScriptService:WaitForChild("Services"):WaitForChild("PlayerDataService"))
local MatchService = require(game.ServerScriptService:WaitForChild("Services"):WaitForChild("MatchService"))

-- Network folder and RemoteEvents (created in Init)
local NetworkFolder = nil
local RequestSetDeck = nil
local RequestProfile = nil
local ProfileUpdated = nil
local RequestStartMatch = nil
local RequestLevelUpCard = nil
local OpenLootbox = nil

-- Rate limiting configuration (explicit, module-scoped)
local RATE_LIMITS = {
	RequestSetDeck = {
		cooldownSec = 2,
		maxPerMinute = 5
	},
	RequestProfile = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestStartMatch = {
		cooldownSec = 1,
		maxPerMinute = 5
	},
	RequestLevelUpCard = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	OpenLootbox = {
		cooldownSec = 2,
		maxPerMinute = 5
	}
}

-- Safe default configuration for missing entries
local DEFAULT_RATE_LIMIT = {
	cooldownSec = 1,
	maxPerMinute = 5
}

-- Rate limiting state (module-scoped)
local playerRateLimits = {} -- player -> rate limit data
local rateLimitWarnings = {} -- track warnings to avoid spam

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
			RequestSetDeck = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestProfile = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestStartMatch = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestLevelUpCard = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			OpenLootbox = {
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
	
	-- Get configuration with safe fallback
	local config = RATE_LIMITS[requestType]
	if not config then
		-- Log warning once per request type
		if not rateLimitWarnings[requestType] then
			LogWarning(nil, "No rate limit config for '%s', using defaults", requestType)
			rateLimitWarnings[requestType] = true
		end
		config = DEFAULT_RATE_LIMIT
	end
	
	local now = os.time()
	
	-- Guard against nil timestamps
	if not rateLimit.lastRequest then
		rateLimit.lastRequest = 0
	end
	
	-- Reset counter if minute has passed
	if now >= rateLimit.resetTime then
		rateLimit.requestCount = 0
		rateLimit.resetTime = now + 60
	end
	
	-- Check cooldown
	if now - rateLimit.lastRequest < config.cooldownSec then
		return false, "Request too frequent, please wait"
	end
	
	-- Check request count limit
	if rateLimit.requestCount >= config.maxPerMinute then
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
	-- Add serverNow timestamp to all profile updates (non-breaking)
	payload.serverNow = os.time()
	if ProfileUpdated then
		ProfileUpdated:FireClient(player, payload)
	end
end

local function CreateCollectionSummary(collection)
	local summary = {}
	for cardId, entry in pairs(collection) do
		-- Handle v2 format: {count, level}
		local count = type(entry) == "table" and entry.count or entry
		local level = type(entry) == "table" and entry.level or 1
		
		table.insert(summary, {
			cardId = cardId,
			count = count,
			level = level
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
	local canProceed, errorMessage = CheckRateLimit(player, "RequestSetDeck")
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
	local canProceed, errorMessage = CheckRateLimit(player, "RequestProfile")
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
	
	-- Get profile data via PlayerDataService (with lazy loading)
	local profile, errorCode, errorMessage = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		-- Send error response
		SendProfileUpdate(player, {
			error = {
				code = errorCode or "PROFILE_LOAD_FAILED",
				message = errorMessage or "Failed to load profile data"
			},
			updatedAt = os.time()
		})
		
		LogWarning(player, "Failed to load profile data: %s", errorMessage or "Unknown error")
		return
	end
	
	-- Get collection and login info
	local collection = PlayerDataService.GetCollection(player)
	local loginInfo = CreateLoginInfo(player)
	
	-- Send profile snapshot
	SendProfileUpdate(player, {
		deck = profile.deck,
		collectionSummary = CreateCollectionSummary(collection),
		loginInfo = loginInfo,
		updatedAt = os.time()
	})
	
	LogInfo(player, "Profile sent successfully")
end

local function HandleRequestStartMatch(player, requestData)
	LogInfo(player, "Processing match request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestStartMatch")
	if not canProceed then
		if RequestStartMatch then
			RequestStartMatch:FireClient(player, {
				ok = false,
				error = {
					code = "RATE_LIMITED",
					message = errorMessage
				},
				serverNow = os.time()
			})
		end
		return
	end
	
	-- Extract seed and variant from request data (optional)
	local matchRequestData = {
		mode = requestData and requestData.mode or "PvE",
		seed = requestData and requestData.seed or nil,
		variant = requestData and requestData.variant or nil
	}
	
	-- Execute match via MatchService
	local result = MatchService.ExecuteMatch(player, matchRequestData)
	
	-- Add serverNow timestamp to match response (non-breaking)
	result.serverNow = os.time()
	
	-- Reply on the same event (as per contract)
	if RequestStartMatch then
		RequestStartMatch:FireClient(player, result)
	end
	
	if result.ok then
		LogInfo(player, "Match completed successfully: %s", result.matchId)
	else
		LogWarning(player, "Match failed: %s", result.error.message)
	end
end

local function HandleRequestLevelUpCard(player, requestData)
	LogInfo(player, "Processing level-up request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestLevelUpCard")
	if not canProceed then
		SendProfileUpdate(player, {
			error = {
				code = "RATE_LIMITED",
				message = errorMessage
			},
			serverNow = os.time()
		})
		return
	end
	
	-- Validate request data
	if not requestData or not requestData.cardId then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_REQUEST",
				message = "Missing cardId"
			},
			serverNow = os.time()
		})
		return
	end
	
	-- Execute level-up via PlayerDataService
	local success, errorMessage = PlayerDataService.LevelUpCard(player, requestData.cardId)
	
	if success then
		-- Get updated profile data
		local profile = PlayerDataService.GetProfile(player)
		local collection = PlayerDataService.GetCollection(player)
		
		-- Send success response
		SendProfileUpdate(player, {
			collectionSummary = CreateCollectionSummary(collection),
			currencies = {
				soft = profile.currencies.soft,
				hard = profile.currencies.hard
			},
			squadPower = profile.squadPower,
			updatedAt = os.time(),
			serverNow = os.time()
		})
		
		LogInfo(player, "Card %s leveled up successfully", requestData.cardId)
	else
		-- Send error response
		SendProfileUpdate(player, {
			error = {
				code = "LEVEL_UP_FAILED",
				message = errorMessage
			},
			serverNow = os.time()
		})
		
		LogWarning(player, "Level-up failed: %s", errorMessage)
	end
end

-- Connection code moved to Init() function

-- Public API for other server modules
RemoteEvents.RequestSetDeck = RequestSetDeck
RemoteEvents.RequestProfile = RequestProfile
RemoteEvents.ProfileUpdated = ProfileUpdated
RemoteEvents.RequestStartMatch = RequestStartMatch
RemoteEvents.RequestLevelUpCard = RequestLevelUpCard
RemoteEvents.OpenLootbox = OpenLootbox

-- Init function for bootstrap
function RemoteEvents.Init()
	-- Idempotency check
	if NetworkFolder then
		LogInfo(nil, "RemoteEvents already initialized, skipping")
		return
	end
	
	-- Create Network folder and RemoteEvents
	NetworkFolder = Instance.new("Folder")
	NetworkFolder.Name = "Network"
	NetworkFolder.Parent = ReplicatedStorage
	
	RequestSetDeck = Instance.new("RemoteEvent")
	RequestSetDeck.Name = "RequestSetDeck"
	RequestSetDeck.Parent = NetworkFolder
	
	RequestProfile = Instance.new("RemoteEvent")
	RequestProfile.Name = "RequestProfile"
	RequestProfile.Parent = NetworkFolder
	
	ProfileUpdated = Instance.new("RemoteEvent")
	ProfileUpdated.Name = "ProfileUpdated"
	ProfileUpdated.Parent = NetworkFolder
	
	RequestStartMatch = Instance.new("RemoteEvent")
	RequestStartMatch.Name = "RequestStartMatch"
	RequestStartMatch.Parent = NetworkFolder
	
	RequestLevelUpCard = Instance.new("RemoteEvent")
	RequestLevelUpCard.Name = "RequestLevelUpCard"
	RequestLevelUpCard.Parent = NetworkFolder
	
	OpenLootbox = Instance.new("RemoteEvent")
	OpenLootbox.Name = "OpenLootbox"
	OpenLootbox.Parent = NetworkFolder
	
	-- Validate rate limit configuration
	local function ValidateRateLimitConfig()
		print("🔒 Rate Limiter Configuration:")
		local remoteEvents = {
			{name = "RequestSetDeck", instance = RequestSetDeck},
			{name = "RequestProfile", instance = RequestProfile},
			{name = "RequestStartMatch", instance = RequestStartMatch},
			{name = "RequestLevelUpCard", instance = RequestLevelUpCard},
			{name = "OpenLootbox", instance = OpenLootbox}
		}
		
		for _, event in ipairs(remoteEvents) do
			local config = RATE_LIMITS[event.name]
			if config then
				print(string.format("  ✅ %s: %ds cooldown, %d/min", 
					event.name, config.cooldownSec, config.maxPerMinute))
			else
				warn(string.format("  ⚠️ %s: No config (using defaults)", event.name))
			end
		end
	end
	
	ValidateRateLimitConfig()
	
	-- Connect RemoteEvents to handlers
	RequestSetDeck.OnServerEvent:Connect(HandleRequestSetDeck)
	RequestProfile.OnServerEvent:Connect(HandleRequestProfile)
	RequestStartMatch.OnServerEvent:Connect(HandleRequestStartMatch)
	RequestLevelUpCard.OnServerEvent:Connect(HandleRequestLevelUpCard)
	
	-- Player cleanup
	Players.PlayerRemoving:Connect(function(player)
		CleanupRateLimit(player)
	end)
	
	LogInfo(nil, "RemoteEvents initialized successfully")
end

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

return RemoteEvents

