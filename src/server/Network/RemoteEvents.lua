local RemoteEvents = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Modules
local PlayerDataService = require(game.ServerScriptService:WaitForChild("Services"):WaitForChild("PlayerDataService"))
local MatchService = require(game.ServerScriptService:WaitForChild("Services"):WaitForChild("MatchService"))
local ShopService = require(game.ServerScriptService:WaitForChild("Services"):WaitForChild("ShopService"))
local LootboxService = require(game.ServerScriptService:WaitForChild("Services"):WaitForChild("LootboxService"))
local PlaytimeService = require(game.ServerScriptService:WaitForChild("Services"):WaitForChild("PlaytimeService"))
local DailyService = require(game.ServerScriptService:WaitForChild("Services"):WaitForChild("DailyService"))
local FollowRewardService = require(game.ServerScriptService:WaitForChild("Services"):WaitForChild("FollowRewardService"))
local ProfileSnapshotService = require(game.ServerScriptService:WaitForChild("Services"):WaitForChild("ProfileSnapshotService"))
local ProfileManager = require(game.ServerScriptService:WaitForChild("Persistence"):WaitForChild("ProfileManager"))
local Logger = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Logger"))

-- Network folder and RemoteEvents (created in Init)
local NetworkFolder = nil
local RequestSetDeck = nil
local RequestProfile = nil
local ProfileUpdated = nil
local RequestStartMatch = nil
local RequestLevelUpCard = nil
local OpenLootbox = nil
local RequestLootState = nil
local RequestAddBox = nil
local RequestResolvePendingDiscard = nil
local RequestResolvePendingReplace = nil
local RequestStartUnlock = nil
local RequestSpeedUp = nil
local RequestOpenNow = nil
local RequestCompleteUnlock = nil
local RequestGetShopPacks = nil
local RequestStartPackPurchase = nil
local RequestBuyLootbox = nil
local RequestPlaytimeData = nil
local RequestClaimPlaytimeReward = nil
local RequestDailyData = nil
local RequestClaimDailyReward = nil
local RequestClaimFollowReward = nil
local RequestNPCDeck = nil -- RemoteFunction for NPC deck requests
local RequestClaimBattleReward = nil

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
	},
	RequestLootState = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestAddBox = {
		cooldownSec = 1,
		maxPerMinute = 5
	},
	RequestResolvePendingDiscard = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestResolvePendingReplace = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestStartUnlock = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestSpeedUp = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestOpenNow = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestCompleteUnlock = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestGetShopPacks = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestStartPackPurchase = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestBuyLootbox = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestClearLoot = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestPlaytimeData = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestClaimPlaytimeReward = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestDailyData = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestClaimDailyReward = {
		cooldownSec = 1,
		maxPerMinute = 10
	},
	RequestClaimFollowReward = {
		cooldownSec = 1,
		maxPerMinute = 5
	},
	RequestClaimBattleReward = {
		cooldownSec = 1,
		maxPerMinute = 10
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
			},
			RequestLootState = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestAddBox = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestResolvePendingDiscard = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestResolvePendingReplace = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestStartUnlock = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestSpeedUp = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestOpenNow = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestCompleteUnlock = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestGetShopPacks = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestStartPackPurchase = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestBuyLootbox = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestPlaytimeData = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestClaimPlaytimeReward = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestDailyData = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestClaimDailyReward = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestClaimFollowReward = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			},
			RequestClaimBattleReward = {
				lastRequest = 0,
				requestCount = 0,
				resetTime = os.time() + 60
			}
		}
	end
end

local function CheckRateLimit(player, requestType)
	InitializeRateLimit(player)
	
	-- Ensure the specific request type is initialized (for new request types added later)
	if not playerRateLimits[player][requestType] then
		playerRateLimits[player][requestType] = {
			lastRequest = 0,
			requestCount = 0,
			resetTime = os.time() + 60
		}
	end
	
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

local function SendProfileUpdate(player, overrides, options)
	options = options or {}
	local context = options.context
	if not context or context == "" then
		local ok, inferred = pcall(function()
			return debug.info(2, "n")
		end)
		if ok and inferred and inferred ~= "" then
			context = tostring(inferred)
		else
			context = "unspecified"
		end
	end

	local snapshotOptions = {
		includeCollection = options.includeCollection,
		includeLoginInfo = options.includeLoginInfo,
		includeDaily = options.includeDaily,
		includePlaytime = options.includePlaytime,
	}

	local useSnapshot = options.snapshot ~= false
	local payload
	local snapshotSuccess = false

	if useSnapshot then
		local snapshot, errorCode, errorMessage = ProfileSnapshotService.GetSnapshot(player, snapshotOptions)
		if snapshot then
			payload = snapshot
			snapshotSuccess = true
		else
			payload = {
				error = {
					code = errorCode,
					message = errorMessage,
				},
				updatedAt = os.time(),
			}
			ProfileSnapshotService.LogSnapshotFailure(player, context, errorCode, errorMessage)
		end
	else
		payload = {
			updatedAt = os.time(),
		}
	end

	if overrides then
		for key, value in pairs(overrides) do
			payload[key] = value
		end
	end

	payload.serverNow = os.time()

	if snapshotSuccess or not useSnapshot then
		ProfileSnapshotService.LogSnapshot(player, context, payload)
	end

	if ProfileUpdated then
		ProfileUpdated:FireClient(player, payload)
	end

	return payload, snapshotSuccess
end

local function CreateCollectionSummary(collection)
	return ProfileSnapshotService.CreateCollectionSummary(collection)
end

local function CreateLoginInfo(player)
	return ProfileSnapshotService.CreateLoginInfo(player)
end

local function SendErrorUpdate(player, context, code, message, options)
	options = options or {}
	options.context = context
	if options.snapshot == nil then
		options.snapshot = false
	end
	return SendProfileUpdate(player, {
		error = {
			code = code,
			message = message,
		},
	}, options)
end

local function SendSnapshot(player, context, overrides, options)
	options = options or {}
	options.context = context
	return SendProfileUpdate(player, overrides, options)
end

-- Request handlers

local function HandleRequestSetDeck(player, requestData)
	LogInfo(player, "Processing deck update request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestSetDeck")
	if not canProceed then
		SendErrorUpdate(player, "RequestSetDeck.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Validate request data
	if not requestData or not requestData.deck then
		SendErrorUpdate(player, "RequestSetDeck.invalidRequest", "INVALID_REQUEST", "Missing deck data")
		return
	end
	
	-- Validate deck via PlayerDataService
	local success, setDeckError = PlayerDataService.SetDeck(player, requestData.deck)
	
	if success then
		SendSnapshot(player, "RequestSetDeck.success", nil, {
			includeCollection = true,
		})
		
		LogInfo(player, "Deck updated successfully")
	else
		SendErrorUpdate(player, "RequestSetDeck.failure", "DECK_UPDATE_FAILED", setDeckError)
		
		LogWarning(player, "Deck update failed: %s", setDeckError)
	end
end

local function HandleRequestProfile(player, requestData)
	LogInfo(player, "Processing profile request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestProfile")
	if not canProceed then
		SendErrorUpdate(player, "RequestProfile.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Get profile data via PlayerDataService (with lazy loading)
	local profile, errorCode, profileErrorMessage = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		SendErrorUpdate(player, "RequestProfile.loadFailed", errorCode or "PROFILE_LOAD_FAILED", profileErrorMessage or "Failed to load profile data", {
			snapshot = false,
		})
		
		LogWarning(player, "Failed to load profile data: %s", profileErrorMessage or "Unknown error")
		return
	end
	
	SendSnapshot(player, "RequestProfile.success", nil, {
		includeCollection = true,
		includeLoginInfo = true,
		includeDaily = true,
		includePlaytime = true,
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
	
	-- Extract seed, variant, and partName from request data (optional)
	local matchRequestData = {
		mode = requestData and requestData.mode or "PvE",
		seed = requestData and requestData.seed or nil,
		variant = requestData and requestData.variant or nil,
		partName = requestData and requestData.partName or nil
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
		SendErrorUpdate(player, "RequestLevelUpCard.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Validate request data
	if not requestData or not requestData.cardId then
		SendErrorUpdate(player, "RequestLevelUpCard.invalidRequest", "INVALID_REQUEST", "Missing cardId")
		return
	end
	
	-- Execute level-up via PlayerDataService
	local success, levelError = PlayerDataService.LevelUpCard(player, requestData.cardId)
	
	if success then
		SendSnapshot(player, "RequestLevelUpCard.success", nil, {
			includeCollection = true,
		})
		
		LogInfo(player, "Card %s leveled up successfully", requestData.cardId)
	else
		SendErrorUpdate(player, "RequestLevelUpCard.failure", "LEVEL_UP_FAILED", levelError)
		
		LogWarning(player, "Level-up failed: %s", levelError)
	end
end

-- Lootbox handler functions
local function HandleRequestLootState(player, requestData)
	LogInfo(player, "Processing loot state request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestLootState")
	if not canProceed then
		SendErrorUpdate(player, "RequestLootState.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Ensure profile is available
	local profile, errorCode, loadError = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		SendErrorUpdate(player, "RequestLootState.loadFailed", errorCode or "PROFILE_LOAD_FAILED", loadError or "Failed to load profile data", {
			snapshot = false,
		})
		return
	end
	
	SendSnapshot(player, "RequestLootState.success")
	
	LogInfo(player, "Loot state sent successfully")
end

local function HandleRequestAddBox(player, requestData)
	LogInfo(player, "Processing add box request")
	
	-- Dev gating: Allow in Studio or when explicitly enabled
	if not RunService:IsStudio() then
		SendErrorUpdate(player, "RequestAddBox.forbidden", "FORBIDDEN_DEV_ONLY", "RequestAddBox is only available in Studio for development")
		return
	end
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestAddBox")
	if not canProceed then
		SendErrorUpdate(player, "RequestAddBox.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Validate payload
	if not requestData or not requestData.rarity then
		SendErrorUpdate(player, "RequestAddBox.invalidRequest", "INVALID_REQUEST", "Missing rarity field")
		return
	end
	
	-- Call LootboxService
	local rarity = string.lower(tostring(requestData.rarity))
	local result = LootboxService.TryAddBox(player.UserId, rarity, requestData.source)
	
	if result.ok then
		SendSnapshot(player, "RequestAddBox.success")
		LogInfo(player, "Add box request completed successfully")
	else
		SendErrorUpdate(player, "RequestAddBox.failure", result.error or "INTERNAL", tostring(result.error))
		LogWarning(player, "Add box request failed: %s", tostring(result.error))
	end
end

local function HandleRequestResolvePendingDiscard(player, requestData)
	LogInfo(player, "Processing resolve pending discard request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestResolvePendingDiscard")
	if not canProceed then
		SendErrorUpdate(player, "RequestResolvePendingDiscard.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Call LootboxService
	local result = LootboxService.ResolvePendingDiscard(player.UserId)
	
	if not result.ok then
		SendErrorUpdate(player, "RequestResolvePendingDiscard.failure", result.error or "INTERNAL", tostring(result.error))
		return
	end
	
	SendSnapshot(player, "RequestResolvePendingDiscard.success")
	
	Logger.debug("lootboxes: op=discard userId=%s pending=true->false result=OK", tostring(player.UserId))
	LogInfo(player, "Pending box discarded successfully")
end

local function HandleRequestResolvePendingReplace(player, requestData)
	LogInfo(player, "Processing resolve pending replace request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestResolvePendingReplace")
	if not canProceed then
		SendErrorUpdate(player, "RequestResolvePendingReplace.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Validate payload
	if not requestData or not requestData.slotIndex then
		SendErrorUpdate(player, "RequestResolvePendingReplace.invalidRequest", "INVALID_REQUEST", "Missing slotIndex field")
		return
	end
	
	-- Validate slot index
	if type(requestData.slotIndex) ~= "number" or requestData.slotIndex < 1 or requestData.slotIndex > 4 then
		SendErrorUpdate(player, "RequestResolvePendingReplace.invalidSlot", "INVALID_SLOT", "Invalid slot index: " .. tostring(requestData.slotIndex))
		return
	end
	
	-- Call LootboxService
	local result = LootboxService.ResolvePendingReplace(player.UserId, requestData.slotIndex)
	
	if not result.ok then
		SendErrorUpdate(player, "RequestResolvePendingReplace.failure", result.error or "INTERNAL", tostring(result.error))
		return
	end
	
	SendSnapshot(player, "RequestResolvePendingReplace.success")
	
	Logger.debug("lootboxes: op=replace userId=%s slot=%d pending=true->false result=OK", tostring(player.UserId), requestData.slotIndex)
	LogInfo(player, "Pending box replaced successfully")
end

local function HandleRequestStartUnlock(player, requestData)
	LogInfo(player, "Processing start unlock request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestStartUnlock")
	if not canProceed then
		SendErrorUpdate(player, "RequestStartUnlock.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Validate payload
	if not requestData or not requestData.slotIndex then
		SendErrorUpdate(player, "RequestStartUnlock.invalidRequest", "INVALID_REQUEST", "Missing slotIndex field")
		return
	end
	
	-- Validate slot index
	if type(requestData.slotIndex) ~= "number" or requestData.slotIndex < 1 or requestData.slotIndex > 4 then
		SendErrorUpdate(player, "RequestStartUnlock.invalidSlot", "INVALID_SLOT", "Invalid slot index: " .. tostring(requestData.slotIndex))
		return
	end
	
	-- Call LootboxService
	local result = LootboxService.StartUnlock(player.UserId, requestData.slotIndex, os.time())
	
	if not result.ok then
		SendErrorUpdate(player, "RequestStartUnlock.failure", result.error or "INTERNAL", tostring(result.error))
		return
	end
	
	SendSnapshot(player, "RequestStartUnlock.success")
	
	Logger.debug("lootboxes: op=start userId=%s slot=%d state=Idle->Unlocking result=OK", tostring(player.UserId), requestData.slotIndex)
	LogInfo(player, "Unlock started successfully")
end

local function HandleRequestSpeedUp(player, requestData)
	LogInfo(player, "Processing speed up request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestSpeedUp")
	if not canProceed then
		SendErrorUpdate(player, "RequestSpeedUp.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Validate payload
	if not requestData or not requestData.slotIndex then
		SendErrorUpdate(player, "RequestSpeedUp.invalidRequest", "INVALID_REQUEST", "Missing slotIndex field")
		return
	end
	
	-- Validate slot index
	if type(requestData.slotIndex) ~= "number" or requestData.slotIndex < 1 or requestData.slotIndex > 4 then
		SendErrorUpdate(player, "RequestSpeedUp.invalidSlot", "INVALID_SLOT", "Invalid slot index: " .. tostring(requestData.slotIndex))
		return
	end
	
	-- Call LootboxService
	local result = LootboxService.SpeedUp(player.UserId, requestData.slotIndex, os.time())
	
	if not result.ok then
		SendErrorUpdate(player, "RequestSpeedUp.failure", result.error or "INTERNAL", tostring(result.error))
		return
	end
	
	local overrides = {}
	if result.rewards then
		overrides.rewards = result.rewards
	end
	
	local payload = SendSnapshot(player, "RequestSpeedUp.success", overrides, {
		includeCollection = result.rewards ~= nil,
	})
	
	if result.rewards then
		LogInfo(player, "SpeedUp: Sending rewards - softDelta=%d, hardDelta=%d, card=%s", 
			result.rewards.softDelta or 0, 
			result.rewards.hardDelta or 0,
			result.rewards.card and result.rewards.card.cardId or "none")
	else
		LogWarning(player, "SpeedUp: No rewards in result! This should not happen.")
	end
	
	if payload and payload.lootboxes then
		LogInfo(player, "SpeedUp: Lootboxes after speed-up: %d boxes", #payload.lootboxes)
	end
	
	Logger.debug("lootboxes: op=speedUp userId=%s slot=%d state=Unlocking->Opened result=OK", tostring(player.UserId), requestData.slotIndex)
	LogInfo(player, "Speed up and open completed successfully")
end

local function HandleRequestOpenNow(player, requestData)
	LogInfo(player, "Processing open now request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestOpenNow")
	if not canProceed then
		SendErrorUpdate(player, "RequestOpenNow.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Validate payload
	if not requestData or not requestData.slotIndex then
		SendErrorUpdate(player, "RequestOpenNow.invalidRequest", "INVALID_REQUEST", "Missing slotIndex field")
		return
	end
	
	-- Validate slot index
	if type(requestData.slotIndex) ~= "number" or requestData.slotIndex < 1 or requestData.slotIndex > 4 then
		SendErrorUpdate(player, "RequestOpenNow.invalidSlot", "INVALID_SLOT", "Invalid slot index: " .. tostring(requestData.slotIndex))
		return
	end
	
	-- Call LootboxService
	local result = LootboxService.OpenNow(player.UserId, requestData.slotIndex, os.time())
	
	if not result.ok then
		SendErrorUpdate(player, "RequestOpenNow.failure", result.error or "INTERNAL", tostring(result.error))
		return
	end
	
	local overrides = {}
	if result.rewards then
		overrides.rewards = result.rewards
	end
	
	SendSnapshot(player, "RequestOpenNow.success", overrides, {
		includeCollection = result.rewards ~= nil,
	})
	
	Logger.debug("lootboxes: op=openNow userId=%s slot=%d state=Unlocking->removed result=OK", tostring(player.UserId), requestData.slotIndex)
	LogInfo(player, "Box opened instantly successfully")
end

local function HandleRequestCompleteUnlock(player, requestData)
	LogInfo(player, "Processing complete unlock request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestCompleteUnlock")
	if not canProceed then
		SendErrorUpdate(player, "RequestCompleteUnlock.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Validate payload
	if not requestData or not requestData.slotIndex then
		SendErrorUpdate(player, "RequestCompleteUnlock.invalidRequest", "INVALID_REQUEST", "Missing slotIndex field")
		return
	end
	
	-- Validate slot index
	if type(requestData.slotIndex) ~= "number" or requestData.slotIndex < 1 or requestData.slotIndex > 4 then
		SendErrorUpdate(player, "RequestCompleteUnlock.invalidSlot", "INVALID_SLOT", "Invalid slot index: " .. tostring(requestData.slotIndex))
		return
	end
	
	-- Call LootboxService
	local result = LootboxService.CompleteUnlock(player.UserId, requestData.slotIndex, os.time())
	
	if not result.ok then
		SendErrorUpdate(player, "RequestCompleteUnlock.failure", result.error or "INTERNAL", tostring(result.error))
		return
	end
	
	local overrides = {}
	if result.rewards then
		overrides.rewards = result.rewards
	end
	
	SendSnapshot(player, "RequestCompleteUnlock.success", overrides, {
		includeCollection = result.rewards ~= nil,
	})
	
	Logger.debug("lootboxes: op=complete userId=%s slot=%d state=Unlocking->removed result=OK", tostring(player.UserId), requestData.slotIndex)
	LogInfo(player, "Unlock completed successfully")
end

-- Shop handlers
local function HandleRequestGetShopPacks(player, requestData)
	LogInfo(player, "Processing get shop packs request")
	
	local canProceed, errorMessage = CheckRateLimit(player, "RequestGetShopPacks")
	if not canProceed then
		SendErrorUpdate(player, "RequestGetShopPacks.rateLimited", "RATE_LIMITED", errorMessage, {
			snapshot = false,
		})
		return
	end
	
	local result = ShopService.GetShopPacks()
	
	local payload = {
		shopPacks = result.packs,
		serverNow = os.time()
	}
	
	if not result.ok then
		payload.error = {
			code = result.error,
			message = result.error
		}
	end
	
	ProfileUpdated:FireClient(player, payload)
	
	if result.ok then
		LogInfo(player, "Shop packs retrieved successfully")
	else
		LogWarning(player, "Get shop packs failed: %s", tostring(result.error))
	end
end

local function HandleRequestStartPackPurchase(player, requestData)
	LogInfo(player, "Processing start pack purchase request")
	
	local canProceed, errorMessage = CheckRateLimit(player, "RequestStartPackPurchase")
	if not canProceed then
		SendErrorUpdate(player, "RequestStartPackPurchase.rateLimited", "RATE_LIMITED", errorMessage, {
			snapshot = false,
		})
		return
	end
	
	-- Validate request
	if not requestData or not requestData.packId then
		SendErrorUpdate(player, "RequestStartPackPurchase.invalidRequest", "INVALID_REQUEST", "Missing packId", {
			snapshot = false,
		})
		return
	end
	
	local result = ShopService.ValidatePackPurchase(player.UserId, requestData.packId)
	
	local payload = {
		serverNow = os.time()
	}
	
	if result.ok then
		payload.ok = true
		payload.packId = requestData.packId
		payload.devProductId = result.pack.devProductId
	else
		payload.error = {
			code = result.error,
			message = result.error
		}
	end
	
	ProfileUpdated:FireClient(player, payload)
	
	if result.ok then
		LogInfo(player, "Pack purchase validation successful for pack %s", requestData.packId)
	else
		LogWarning(player, "Start pack purchase failed: %s", tostring(result.error))
	end
end

local function HandleRequestPlaytimeData(player, requestData)
	LogInfo(player, "Processing playtime data request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestPlaytimeData")
	if not canProceed then
		SendErrorUpdate(player, "RequestPlaytimeData.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Ensure playtime data is available
	local playtimeData = PlaytimeService.GetPlaytimeData(player.UserId)
	if not playtimeData then
		SendErrorUpdate(player, "RequestPlaytimeData.loadFailed", "PROFILE_LOAD_FAILED", "Failed to load playtime data")
		return
	end
	
	SendSnapshot(player, "RequestPlaytimeData.success", nil, {
		includePlaytime = true,
	})
	
	LogInfo(player, "Playtime data sent successfully")
end

local function HandleRequestClaimPlaytimeReward(player, requestData)
	LogInfo(player, "Processing claim playtime reward request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestClaimPlaytimeReward")
	if not canProceed then
		SendErrorUpdate(player, "RequestClaimPlaytimeReward.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Validate request
	if not requestData or type(requestData.rewardIndex) ~= "number" then
		SendErrorUpdate(player, "RequestClaimPlaytimeReward.invalidRequest", "INVALID_REQUEST", "Missing or invalid rewardIndex")
		return
	end
	
	-- Claim reward
	local result = PlaytimeService.ClaimPlaytimeReward(player.UserId, requestData.rewardIndex)
	if not result.ok then
		SendErrorUpdate(player, "RequestClaimPlaytimeReward.failure", result.error or "INTERNAL", tostring(result.error))
		LogWarning(player, "Claim playtime reward failed: %s", tostring(result.error))
		return
	end
	
	local overrides = {}
	if result.rewards then
		overrides.rewards = result.rewards
	end
	
	SendSnapshot(player, "RequestClaimPlaytimeReward.success", overrides, {
		includePlaytime = true,
		includeCollection = result.rewards ~= nil,
	})
	
	LogInfo(player, "Playtime reward %d claimed successfully", requestData.rewardIndex)
end

local function HandleRequestDailyData(player, requestData)
	LogInfo(player, "Processing daily data request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestDailyData")
	if not canProceed then
		SendErrorUpdate(player, "RequestDailyData.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Ensure daily data exists
	local dailyData = DailyService.GetDailyData(player.UserId)
	if not dailyData then
		SendErrorUpdate(player, "RequestDailyData.loadFailed", "PROFILE_LOAD_FAILED", "Failed to load daily data")
		return
	end
	
	SendSnapshot(player, "RequestDailyData.success", nil, {
		includeDaily = true,
	})
	
	LogInfo(player, "Daily data sent successfully")
end

local function HandleRequestClaimDailyReward(player, requestData)
	LogInfo(player, "Processing claim daily reward request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestClaimDailyReward")
	if not canProceed then
		SendErrorUpdate(player, "RequestClaimDailyReward.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Validate request
	if not requestData or type(requestData.rewardIndex) ~= "number" then
		SendErrorUpdate(player, "RequestClaimDailyReward.invalidRequest", "INVALID_REQUEST", "Missing or invalid rewardIndex")
		return
	end
	
	-- Claim reward
	local result = DailyService.ClaimDailyReward(player.UserId, requestData.rewardIndex)
	if not result or not result.ok then
		LogWarning(player, "Claim daily reward failed (raw result): %s", game:GetService("HttpService"):JSONEncode(result or { ok = false, error = "nil_result" }))
		SendErrorUpdate(player, "RequestClaimDailyReward.failure", (result and result.error) or "INTERNAL", "Failed to claim daily reward")
		return
	end
	
	local overrides = {}
	if result.rewards then
		overrides.rewards = result.rewards
	end
	
	SendSnapshot(player, "RequestClaimDailyReward.success", overrides, {
		includeDaily = true,
		includeCollection = result.rewards ~= nil,
	})
	
	LogInfo(player, "Daily reward %d claimed successfully", requestData.rewardIndex)
end

local function HandleRequestClaimFollowReward(player)
	LogInfo(player, "Processing follow reward request")

	local canProceed, errorMessage = CheckRateLimit(player, "RequestClaimFollowReward")
	if not canProceed then
		SendErrorUpdate(player, "RequestClaimFollowReward.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end

	local result = FollowRewardService.GrantFollowReward(player)
	if result.ok then
		local overrides = {
			followReward = { status = "granted" },
			rewards = result.rewards,
		}

		SendSnapshot(player, "RequestClaimFollowReward.success", overrides, {
			includeCollection = result.rewards ~= nil,
		})

		LogInfo(player, "Follow reward granted successfully")
	else
		local reason = result.reason or "INTERNAL"
		local overrides = {
			followReward = { status = reason },
		}

		if reason == "NOT_FOLLOWING" then
			LogInfo(player, "Follow reward denied: player has not followed the game")
			print("you are not followed to the game")
		elseif reason == "ALREADY_CLAIMED" then
			LogInfo(player, "Follow reward denied: already claimed")
		else
			LogWarning(player, "Follow reward failed: %s", reason)
		end

		SendSnapshot(player, "RequestClaimFollowReward.failure", overrides)
	end
end

local function HandleRequestBuyLootbox(player, requestData)
	LogInfo(player, "Processing buy lootbox request")
	
	local canProceed, errorMessage = CheckRateLimit(player, "RequestBuyLootbox")
	if not canProceed then
		SendErrorUpdate(player, "RequestBuyLootbox.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Validate request
	if not requestData or not requestData.rarity then
		SendErrorUpdate(player, "RequestBuyLootbox.invalidRequest", "INVALID_REQUEST", "Missing rarity")
		return
	end
	
	local result = ShopService.BuyLootbox(player.UserId, requestData.rarity)
	
	if result.ok then
		local overrides = {}
		if result.rewards then
			overrides.rewards = result.rewards
		end
		
		SendSnapshot(player, "RequestBuyLootbox.success", overrides, {
			includeCollection = result.rewards ~= nil,
		})
		LogInfo(player, "Shop lootbox purchase successful")
	else
		SendErrorUpdate(player, "RequestBuyLootbox.failure", result.error or "INTERNAL", tostring(result.error))
		LogWarning(player, "Shop lootbox purchase failed: %s", tostring(result.error))
	end
	
	if result.ok then
		LogInfo(player, "Lootbox purchase successful: %s for %d hard", requestData.rarity, result.cost)
	else
		LogWarning(player, "Buy lootbox failed: %s", tostring(result.error))
	end
end

local function HandleRequestClaimBattleReward(player, requestData)
	LogInfo(player, "Processing claim battle reward request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestClaimBattleReward")
	if not canProceed then
		SendErrorUpdate(player, "RequestClaimBattleReward.rateLimited", "RATE_LIMITED", errorMessage)
		return
	end
	
	-- Validate payload
	if not requestData or not requestData.rewardType then
		SendErrorUpdate(player, "RequestClaimBattleReward.invalidRequest", "INVALID_REQUEST", "Missing rewardType field")
		return
	end
	
	local rewardType = requestData.rewardType
	if rewardType == "soft" then
		local amount = requestData.amount or 0
		if amount <= 0 then
			SendErrorUpdate(player, "RequestClaimBattleReward.invalidSoftAmount", "INVALID_REQUEST", "Invalid soft currency amount")
			return
		end
		
		local success, errorMsg = ProfileManager.AddCurrency(player.UserId, "soft", amount)
		if not success then
			SendErrorUpdate(player, "RequestClaimBattleReward.softFailure", "INTERNAL", errorMsg or "Failed to grant soft currency")
			return
		end
		
		LogInfo(player, "Soft currency reward granted: %d", amount)
	elseif rewardType == "lootbox" then
		local rarity = requestData.rarity
		if not rarity then
			SendErrorUpdate(player, "RequestClaimBattleReward.missingRarity", "INVALID_REQUEST", "Missing rarity for lootbox reward")
			return
		end
		
		local result = LootboxService.TryAddBox(player.UserId, rarity, "battle_reward")
		if not result.ok then
			SendErrorUpdate(player, "RequestClaimBattleReward.lootboxFailure", result.error or "INTERNAL", "Failed to grant lootbox reward")
			return
		end
		
		LogInfo(player, "Lootbox reward granted: %s", rarity)
	else
		SendErrorUpdate(player, "RequestClaimBattleReward.invalidType", "INVALID_REQUEST", "Invalid reward type: " .. tostring(rewardType))
		return
	end
	
	SendSnapshot(player, "RequestClaimBattleReward.success")
	LogInfo(player, "Battle reward claimed successfully")
end

-- Connection code moved to Init() function

-- Public API for other server modules
RemoteEvents.RequestSetDeck = RequestSetDeck
RemoteEvents.RequestProfile = RequestProfile
RemoteEvents.ProfileUpdated = ProfileUpdated
RemoteEvents.RequestStartMatch = RequestStartMatch
RemoteEvents.RequestLevelUpCard = RequestLevelUpCard
RemoteEvents.OpenLootbox = OpenLootbox
RemoteEvents.RequestLootState = RequestLootState
RemoteEvents.RequestAddBox = RequestAddBox
RemoteEvents.RequestResolvePendingDiscard = RequestResolvePendingDiscard
RemoteEvents.RequestResolvePendingReplace = RequestResolvePendingReplace
RemoteEvents.RequestStartUnlock = RequestStartUnlock
RemoteEvents.RequestSpeedUp = RequestSpeedUp
RemoteEvents.RequestOpenNow = RequestOpenNow
RemoteEvents.RequestCompleteUnlock = RequestCompleteUnlock
RemoteEvents.RequestGetShopPacks = RequestGetShopPacks
RemoteEvents.RequestStartPackPurchase = RequestStartPackPurchase
RemoteEvents.RequestBuyLootbox = RequestBuyLootbox
RemoteEvents.RequestPlaytimeData = RequestPlaytimeData
RemoteEvents.RequestClaimPlaytimeReward = RequestClaimPlaytimeReward
RemoteEvents.RequestDailyData = RequestDailyData
RemoteEvents.RequestClaimDailyReward = RequestClaimDailyReward
RemoteEvents.RequestClaimFollowReward = RequestClaimFollowReward
RemoteEvents.RequestNPCDeck = RequestNPCDeck
RemoteEvents.RequestClaimBattleReward = RequestClaimBattleReward

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
	
	RequestLootState = Instance.new("RemoteEvent")
	RequestLootState.Name = "RequestLootState"
	RequestLootState.Parent = NetworkFolder
	
	RequestAddBox = Instance.new("RemoteEvent")
	RequestAddBox.Name = "RequestAddBox"
	RequestAddBox.Parent = NetworkFolder
	
	RequestResolvePendingDiscard = Instance.new("RemoteEvent")
	RequestResolvePendingDiscard.Name = "RequestResolvePendingDiscard"
	RequestResolvePendingDiscard.Parent = NetworkFolder
	
	RequestResolvePendingReplace = Instance.new("RemoteEvent")
	RequestResolvePendingReplace.Name = "RequestResolvePendingReplace"
	RequestResolvePendingReplace.Parent = NetworkFolder
	
	RequestStartUnlock = Instance.new("RemoteEvent")
	RequestStartUnlock.Name = "RequestStartUnlock"
	RequestStartUnlock.Parent = NetworkFolder
	
	RequestSpeedUp = Instance.new("RemoteEvent")
	RequestSpeedUp.Name = "RequestSpeedUp"
	RequestSpeedUp.Parent = NetworkFolder
	
	RequestOpenNow = Instance.new("RemoteEvent")
	RequestOpenNow.Name = "RequestOpenNow"
	RequestOpenNow.Parent = NetworkFolder
	
	RequestCompleteUnlock = Instance.new("RemoteEvent")
	RequestCompleteUnlock.Name = "RequestCompleteUnlock"
	RequestCompleteUnlock.Parent = NetworkFolder
	
	-- Shop RemoteEvents
	RequestGetShopPacks = Instance.new("RemoteEvent")
	RequestGetShopPacks.Name = "RequestGetShopPacks"
	RequestGetShopPacks.Parent = NetworkFolder
	
	RequestStartPackPurchase = Instance.new("RemoteEvent")
	RequestStartPackPurchase.Name = "RequestStartPackPurchase"
	RequestStartPackPurchase.Parent = NetworkFolder
	
	RequestBuyLootbox = Instance.new("RemoteEvent")
	RequestBuyLootbox.Name = "RequestBuyLootbox"
	RequestBuyLootbox.Parent = NetworkFolder
	
	RequestPlaytimeData = Instance.new("RemoteEvent")
	RequestPlaytimeData.Name = "RequestPlaytimeData"
	RequestPlaytimeData.Parent = NetworkFolder
	
	RequestClaimPlaytimeReward = Instance.new("RemoteEvent")
	RequestClaimPlaytimeReward.Name = "RequestClaimPlaytimeReward"
	RequestClaimPlaytimeReward.Parent = NetworkFolder
	
	RequestDailyData = Instance.new("RemoteEvent")
	RequestDailyData.Name = "RequestDailyData"
	RequestDailyData.Parent = NetworkFolder
	
	RequestClaimDailyReward = Instance.new("RemoteEvent")
	RequestClaimDailyReward.Name = "RequestClaimDailyReward"
	RequestClaimDailyReward.Parent = NetworkFolder

	RequestClaimFollowReward = Instance.new("RemoteEvent")
	RequestClaimFollowReward.Name = "RequestClaimFollowReward"
	RequestClaimFollowReward.Parent = NetworkFolder
	
	-- NPC Deck RemoteFunction
	RequestNPCDeck = Instance.new("RemoteFunction")
	RequestNPCDeck.Name = "RequestNPCDeck"
	RequestNPCDeck.Parent = NetworkFolder
	
	-- Battle Reward Claim RemoteEvent
	RequestClaimBattleReward = Instance.new("RemoteEvent")
	RequestClaimBattleReward.Name = "RequestClaimBattleReward"
	RequestClaimBattleReward.Parent = NetworkFolder
	
	-- Validate rate limit configuration
	local function ValidateRateLimitConfig()
		print("🔒 Rate Limiter Configuration:")
		local remoteEvents = {
			{name = "RequestSetDeck", instance = RequestSetDeck},
			{name = "RequestProfile", instance = RequestProfile},
			{name = "RequestStartMatch", instance = RequestStartMatch},
			{name = "RequestLevelUpCard", instance = RequestLevelUpCard},
			{name = "OpenLootbox", instance = OpenLootbox},
			{name = "RequestLootState", instance = RequestLootState},
			{name = "RequestAddBox", instance = RequestAddBox},
			{name = "RequestResolvePendingDiscard", instance = RequestResolvePendingDiscard},
			{name = "RequestResolvePendingReplace", instance = RequestResolvePendingReplace},
			{name = "RequestStartUnlock", instance = RequestStartUnlock},
			{name = "RequestOpenNow", instance = RequestOpenNow},
			{name = "RequestCompleteUnlock", instance = RequestCompleteUnlock},
			{name = "RequestGetShopPacks", instance = RequestGetShopPacks},
			{name = "RequestStartPackPurchase", instance = RequestStartPackPurchase},
			{name = "RequestBuyLootbox", instance = RequestBuyLootbox},
			{name = "RequestPlaytimeData", instance = RequestPlaytimeData},
			{name = "RequestClaimPlaytimeReward", instance = RequestClaimPlaytimeReward},
			{name = "RequestDailyData", instance = RequestDailyData},
			{name = "RequestClaimDailyReward", instance = RequestClaimDailyReward},
			{name = "RequestClaimFollowReward", instance = RequestClaimFollowReward},
			{name = "RequestClaimBattleReward", instance = RequestClaimBattleReward}
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
	RequestLootState.OnServerEvent:Connect(HandleRequestLootState)
	RequestAddBox.OnServerEvent:Connect(HandleRequestAddBox)
	RequestResolvePendingDiscard.OnServerEvent:Connect(HandleRequestResolvePendingDiscard)
	RequestResolvePendingReplace.OnServerEvent:Connect(HandleRequestResolvePendingReplace)
	RequestStartUnlock.OnServerEvent:Connect(HandleRequestStartUnlock)
	RequestSpeedUp.OnServerEvent:Connect(HandleRequestSpeedUp)
	RequestOpenNow.OnServerEvent:Connect(HandleRequestOpenNow)
	RequestCompleteUnlock.OnServerEvent:Connect(HandleRequestCompleteUnlock)
	RequestGetShopPacks.OnServerEvent:Connect(HandleRequestGetShopPacks)
	RequestStartPackPurchase.OnServerEvent:Connect(HandleRequestStartPackPurchase)
	RequestBuyLootbox.OnServerEvent:Connect(HandleRequestBuyLootbox)
	RequestPlaytimeData.OnServerEvent:Connect(HandleRequestPlaytimeData)
	RequestClaimPlaytimeReward.OnServerEvent:Connect(HandleRequestClaimPlaytimeReward)
	RequestDailyData.OnServerEvent:Connect(HandleRequestDailyData)
	RequestClaimDailyReward.OnServerEvent:Connect(HandleRequestClaimDailyReward)
	RequestClaimFollowReward.OnServerEvent:Connect(HandleRequestClaimFollowReward)
	RequestClaimBattleReward.OnServerEvent:Connect(HandleRequestClaimBattleReward)
	
	-- Initialize PlaytimeService
	PlaytimeService.Init()
	
	-- Track player login for daily rewards
	Players.PlayerAdded:Connect(function(player)
		DailyService.TrackPlayerLogin(player.UserId)
	end)
	
	-- Handle players already in game
	for _, player in ipairs(Players:GetPlayers()) do
		DailyService.TrackPlayerLogin(player.UserId)
	end
	
	-- Player cleanup
	Players.PlayerRemoving:Connect(function(player)
		CleanupRateLimit(player)
	end)
	
	-- Initialize ShopService
	ShopService.Initialize()
	
	-- Setup NPC Deck RemoteFunction handler (also handles Boss decks)
	RequestNPCDeck.OnServerInvoke = function(player, partName)
		LogInfo(player, "Processing deck request for part: %s", partName or "nil")
		
		-- Validate partName
		if not partName or type(partName) ~= "string" then
			LogWarning(player, "Invalid partName for NPC deck request")
			return {
				ok = false,
				error = {
					code = "INVALID_REQUEST",
					message = "Missing or invalid partName"
				}
			}
		end
		
		-- Check if this is NPC mode or Boss mode
		if partName:match("^NPCMode") then
			-- NPC mode: get or generate NPC deck
			local npcDeckData = MatchService.GetOrGenerateNPCDeck(player, partName)
			if not npcDeckData then
				LogWarning(player, "Failed to get NPC deck for part: %s", partName)
				return {
					ok = false,
					error = {
						code = "DECK_GENERATION_FAILED",
						message = "Failed to generate NPC deck"
					}
				}
			end
			
			return {
				ok = true,
				deck = npcDeckData.deck,
				levels = npcDeckData.levels,
				reward = npcDeckData.reward -- Include reward for prep window
			}
		elseif partName:match("^BossMode") then
			-- Boss mode: get boss deck with difficulty info
			local bossDeckInfo = MatchService.GetBossDeckInfo(player, partName)
			if not bossDeckInfo then
				LogWarning(player, "Failed to get boss deck for part: %s", partName)
				return {
					ok = false,
					error = {
						code = "DECK_GENERATION_FAILED",
						message = "Failed to get boss deck"
					}
				}
			end
			
			return {
				ok = true,
				deck = bossDeckInfo.deck,
				levels = bossDeckInfo.levels,
				bossId = bossDeckInfo.bossId,
				difficulty = bossDeckInfo.difficulty,
				reward = bossDeckInfo.reward -- Include hardcoded reward for prep window
			}
		else
			-- Unknown part type
			LogWarning(player, "Unknown part type for deck request: %s", partName)
			return {
				ok = false,
				error = {
					code = "INVALID_REQUEST",
					message = "Unknown part type"
				}
			}
		end
	end
	
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

