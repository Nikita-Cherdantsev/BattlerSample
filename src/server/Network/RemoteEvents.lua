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
			currencies = profile.currencies,
			squadPower = profile.squadPower,
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
	
	-- Get daily data for initial profile load
	local dailyData = DailyService.GetDailyData(player.UserId)
	
	-- Prepare payload
	local payload = {
		deck = profile.deck,
		collectionSummary = CreateCollectionSummary(collection),
		loginInfo = loginInfo,
		lootboxes = profile.lootboxes or {},
		pendingLootbox = profile.pendingLootbox,
		currencies = profile.currencies or { soft = 0, hard = 0 },
		squadPower = profile.squadPower,
		updatedAt = os.time()
	}
	
	-- Include daily data if available
	if dailyData then
		payload.daily = {
			streak = dailyData.streak,
			lastLogin = dailyData.lastLogin,
			currentDay = dailyData.currentDay,
			isClaimed = dailyData.isClaimed,
			rewardsConfig = dailyData.rewardsConfig
		}
	end
	
	-- Send profile snapshot (including lootboxes, currencies, and daily data)
	SendProfileUpdate(player, payload)
	
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

-- Lootbox handler functions
local function HandleRequestLootState(player, requestData)
	LogInfo(player, "Processing loot state request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestLootState")
	if not canProceed then
		SendProfileUpdate(player, {
			error = {
				code = "RATE_LIMITED",
				message = errorMessage
			}
		})
		return
	end
	
	-- Get profile data
	local profile, errorCode, errorMessage = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		SendProfileUpdate(player, {
			error = {
				code = errorCode or "PROFILE_LOAD_FAILED",
				message = errorMessage or "Failed to load profile data"
			}
		})
		return
	end
	
	-- Send lootbox state
	SendProfileUpdate(player, {
		lootboxes = profile.lootboxes,
		pendingLootbox = profile.pendingLootbox,
		currencies = profile.currencies
	})
	
	LogInfo(player, "Loot state sent successfully")
end

local function HandleRequestAddBox(player, requestData)
	LogInfo(player, "Processing add box request")
	
	-- Dev gating: Allow in Studio or when explicitly enabled
	if not RunService:IsStudio() then
		SendProfileUpdate(player, {
			error = {
				code = "FORBIDDEN_DEV_ONLY",
				message = "RequestAddBox is only available in Studio for development"
			}
		})
		return
	end
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestAddBox")
	if not canProceed then
		SendProfileUpdate(player, {
			error = {
				code = "RATE_LIMITED",
				message = errorMessage
			}
		})
		return
	end
	
	-- Validate payload
	if not requestData or not requestData.rarity then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_REQUEST",
				message = "Missing rarity field"
			}
		})
		return
	end
	
	-- Call LootboxService
	local rarity = string.lower(tostring(requestData.rarity))
	local result = LootboxService.TryAddBox(player.UserId, rarity, requestData.source)
	
	-- Get updated profile
	local profile, _, _ = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		SendProfileUpdate(player, {
			error = {
				code = "INTERNAL",
				message = "Failed to load updated profile"
			}
		})
		return
	end
	
	-- Send response
	local payload = {
		lootboxes = profile.lootboxes,
		pendingLootbox = profile.pendingLootbox
	}
	
	if not result.ok then
		payload.error = {
			code = result.error,
			message = result.error
		}
	end
	
	SendProfileUpdate(player, payload)
	
	if result.ok then
		LogInfo(player, "Add box request completed successfully")
	else
		LogWarning(player, "Add box request failed: %s", tostring(result.error))
	end
end

local function HandleRequestResolvePendingDiscard(player, requestData)
	LogInfo(player, "Processing resolve pending discard request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestResolvePendingDiscard")
	if not canProceed then
		SendProfileUpdate(player, {
			error = {
				code = "RATE_LIMITED",
				message = errorMessage
			}
		})
		return
	end
	
	-- Call LootboxService
	local result = LootboxService.ResolvePendingDiscard(player.UserId)
	
	if not result.ok then
		-- Send error without loot state
		SendProfileUpdate(player, {
			error = {
				code = result.error,
				message = result.error
			}
		})
		return
	end
	
	-- Get updated profile for success case
	local profile, _, _ = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		SendProfileUpdate(player, {
			error = {
				code = "INTERNAL",
				message = "Failed to load updated profile"
			}
		})
		return
	end
	
	-- Send success response with loot state
	SendProfileUpdate(player, {
		lootboxes = profile.lootboxes,
		pendingLootbox = profile.pendingLootbox,
		currencies = profile.currencies
	})
	
	Logger.debug("lootboxes: op=discard userId=%s pending=true->false result=OK", tostring(player.UserId))
	LogInfo(player, "Pending box discarded successfully")
end

local function HandleRequestResolvePendingReplace(player, requestData)
	LogInfo(player, "Processing resolve pending replace request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestResolvePendingReplace")
	if not canProceed then
		SendProfileUpdate(player, {
			error = {
				code = "RATE_LIMITED",
				message = errorMessage
			}
		})
		return
	end
	
	-- Validate payload
	if not requestData or not requestData.slotIndex then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_REQUEST",
				message = "Missing slotIndex field"
			}
		})
		return
	end
	
	-- Validate slot index
	if type(requestData.slotIndex) ~= "number" or requestData.slotIndex < 1 or requestData.slotIndex > 4 then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_SLOT",
				message = "Invalid slot index: " .. tostring(requestData.slotIndex)
			}
		})
		return
	end
	
	-- Call LootboxService
	local result = LootboxService.ResolvePendingReplace(player.UserId, requestData.slotIndex)
	
	if not result.ok then
		-- Send error without loot state
		SendProfileUpdate(player, {
			error = {
				code = result.error,
				message = result.error
			}
		})
		return
	end
	
	-- Get updated profile for success case
	local profile, _, _ = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		SendProfileUpdate(player, {
			error = {
				code = "INTERNAL",
				message = "Failed to load updated profile"
			}
		})
		return
	end
	
	-- Send success response with loot state
	SendProfileUpdate(player, {
		lootboxes = profile.lootboxes,
		pendingLootbox = profile.pendingLootbox,
		currencies = profile.currencies
	})
	
	Logger.debug("lootboxes: op=replace userId=%s slot=%d pending=true->false result=OK", tostring(player.UserId), requestData.slotIndex)
	LogInfo(player, "Pending box replaced successfully")
end

local function HandleRequestStartUnlock(player, requestData)
	LogInfo(player, "Processing start unlock request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestStartUnlock")
	if not canProceed then
		SendProfileUpdate(player, {
			error = {
				code = "RATE_LIMITED",
				message = errorMessage
			}
		})
		return
	end
	
	-- Validate payload
	if not requestData or not requestData.slotIndex then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_REQUEST",
				message = "Missing slotIndex field"
			}
		})
		return
	end
	
	-- Validate slot index
	if type(requestData.slotIndex) ~= "number" or requestData.slotIndex < 1 or requestData.slotIndex > 4 then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_SLOT",
				message = "Invalid slot index: " .. tostring(requestData.slotIndex)
			}
		})
		return
	end
	
	-- Call LootboxService
	local result = LootboxService.StartUnlock(player.UserId, requestData.slotIndex, os.time())
	
	if not result.ok then
		-- Send error without loot state
		SendProfileUpdate(player, {
			error = {
				code = result.error,
				message = result.error
			}
		})
		return
	end
	
	-- Get updated profile for success case
	local profile, _, _ = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		SendProfileUpdate(player, {
			error = {
				code = "INTERNAL",
				message = "Failed to load updated profile"
			}
		})
		return
	end
	
	-- Send success response with loot state
	SendProfileUpdate(player, {
		lootboxes = profile.lootboxes,
		pendingLootbox = profile.pendingLootbox,
		currencies = profile.currencies
	})
	
	Logger.debug("lootboxes: op=start userId=%s slot=%d state=Idle->Unlocking result=OK", tostring(player.UserId), requestData.slotIndex)
	LogInfo(player, "Unlock started successfully")
end

local function HandleRequestSpeedUp(player, requestData)
	LogInfo(player, "Processing speed up request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestSpeedUp")
	if not canProceed then
		SendProfileUpdate(player, {
			error = {
				code = "RATE_LIMITED",
				message = errorMessage
			}
		})
		return
	end
	
	-- Validate payload
	if not requestData or not requestData.slotIndex then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_REQUEST",
				message = "Missing slotIndex field"
			}
		})
		return
	end
	
	-- Validate slot index
	if type(requestData.slotIndex) ~= "number" or requestData.slotIndex < 1 or requestData.slotIndex > 4 then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_SLOT",
				message = "Invalid slot index: " .. tostring(requestData.slotIndex)
			}
		})
		return
	end
	
	-- Call LootboxService
	local result = LootboxService.SpeedUp(player.UserId, requestData.slotIndex, os.time())
	
	if not result.ok then
		-- Send error without loot state
		SendProfileUpdate(player, {
			error = {
				code = result.error,
				message = result.error
			}
		})
		return
	end
	
	-- Get updated profile for success case
	local profile, _, _ = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		SendProfileUpdate(player, {
			error = {
				code = "INTERNAL",
				message = "Failed to load updated profile"
			}
		})
		return
	end
	
	-- Send success response with loot state, currencies, rewards, and collection summary
	local payload = {
		lootboxes = profile.lootboxes,
		pendingLootbox = profile.pendingLootbox,
		currencies = profile.currencies
	}
	
	if result.rewards then
		-- Include rewards and collection summary
		payload.rewards = result.rewards
		local collection = PlayerDataService.GetCollection(player)
		payload.collectionSummary = CreateCollectionSummary(collection)
		LogInfo(player, "SpeedUp: Sending rewards - softDelta=%d, hardDelta=%d, card=%s", 
			result.rewards.softDelta or 0, 
			result.rewards.hardDelta or 0,
			result.rewards.card and result.rewards.card.cardId or "none")
	else
		LogWarning(player, "SpeedUp: No rewards in result! This should not happen.")
	end
	
	LogInfo(player, "SpeedUp: Lootboxes after speed-up: %d boxes", #profile.lootboxes)
	
	SendProfileUpdate(player, payload)
	
	Logger.debug("lootboxes: op=speedUp userId=%s slot=%d state=Unlocking->Opened result=OK", tostring(player.UserId), requestData.slotIndex)
	LogInfo(player, "Speed up and open completed successfully")
end

local function HandleRequestOpenNow(player, requestData)
	LogInfo(player, "Processing open now request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestOpenNow")
	if not canProceed then
		SendProfileUpdate(player, {
			error = {
				code = "RATE_LIMITED",
				message = errorMessage
			}
		})
		return
	end
	
	-- Validate payload
	if not requestData or not requestData.slotIndex then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_REQUEST",
				message = "Missing slotIndex field"
			}
		})
		return
	end
	
	-- Validate slot index
	if type(requestData.slotIndex) ~= "number" or requestData.slotIndex < 1 or requestData.slotIndex > 4 then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_SLOT",
				message = "Invalid slot index: " .. tostring(requestData.slotIndex)
			}
		})
		return
	end
	
	-- Call LootboxService
	local result = LootboxService.OpenNow(player.UserId, requestData.slotIndex, os.time())
	
	if not result.ok then
		-- Send error without loot state
		SendProfileUpdate(player, {
			error = {
				code = result.error,
				message = result.error
			}
		})
		return
	end
	
	-- Get updated profile for success case
	local profile, _, _ = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		SendProfileUpdate(player, {
			error = {
				code = "INTERNAL",
				message = "Failed to load updated profile"
			}
		})
		return
	end
	
	-- Send success response with loot state and currencies
	local payload = {
		lootboxes = profile.lootboxes,
		pendingLootbox = profile.pendingLootbox,
		currencies = profile.currencies
	}
	
	if result.rewards then
		-- Include rewards and collection summary
		payload.rewards = result.rewards
		local collection = PlayerDataService.GetCollection(player)
		payload.collectionSummary = CreateCollectionSummary(collection)
	end
	
	SendProfileUpdate(player, payload)
	
	Logger.debug("lootboxes: op=openNow userId=%s slot=%d state=Unlocking->removed result=OK", tostring(player.UserId), requestData.slotIndex)
	LogInfo(player, "Box opened instantly successfully")
end

local function HandleRequestCompleteUnlock(player, requestData)
	LogInfo(player, "Processing complete unlock request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestCompleteUnlock")
	if not canProceed then
		SendProfileUpdate(player, {
			error = {
				code = "RATE_LIMITED",
				message = errorMessage
			}
		})
		return
	end
	
	-- Validate payload
	if not requestData or not requestData.slotIndex then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_REQUEST",
				message = "Missing slotIndex field"
			}
		})
		return
	end
	
	-- Validate slot index
	if type(requestData.slotIndex) ~= "number" or requestData.slotIndex < 1 or requestData.slotIndex > 4 then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_SLOT",
				message = "Invalid slot index: " .. tostring(requestData.slotIndex)
			}
		})
		return
	end
	
	-- Call LootboxService
	local result = LootboxService.CompleteUnlock(player.UserId, requestData.slotIndex, os.time())
	
	if not result.ok then
		-- Send error without loot state
		SendProfileUpdate(player, {
			error = {
				code = result.error,
				message = result.error
			}
		})
		return
	end
	
	-- Get updated profile for success case
	local profile, _, _ = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		SendProfileUpdate(player, {
			error = {
				code = "INTERNAL",
				message = "Failed to load updated profile"
			}
		})
		return
	end
	
	-- Send success response with loot state and currencies
	local payload = {
		lootboxes = profile.lootboxes,
		pendingLootbox = profile.pendingLootbox,
		currencies = profile.currencies
	}
	
	if result.rewards then
		-- Include rewards and collection summary
		payload.rewards = result.rewards
		local collection = PlayerDataService.GetCollection(player)
		payload.collectionSummary = CreateCollectionSummary(collection)
	end
	
	SendProfileUpdate(player, payload)
	
	Logger.debug("lootboxes: op=complete userId=%s slot=%d state=Unlocking->removed result=OK", tostring(player.UserId), requestData.slotIndex)
	LogInfo(player, "Unlock completed successfully")
end

-- Shop handlers
local function HandleRequestGetShopPacks(player, requestData)
	LogInfo(player, "Processing get shop packs request")
	
	local canProceed, errorMessage = CheckRateLimit(player, "RequestGetShopPacks")
	if not canProceed then
		SendProfileUpdate(player, {
			error = { code = "RATE_LIMITED", message = errorMessage },
			serverNow = os.time()
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
		SendProfileUpdate(player, {
			error = { code = "RATE_LIMITED", message = errorMessage },
			serverNow = os.time()
		})
		return
	end
	
	-- Validate request
	if not requestData or not requestData.packId then
		SendProfileUpdate(player, {
			error = { code = "INVALID_REQUEST", message = "Missing packId" },
			serverNow = os.time()
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
		SendProfileUpdate(player, {
			error = {
				code = "RATE_LIMITED",
				message = errorMessage
			},
			serverNow = os.time()
		})
		return
	end
	
	-- Get playtime data
	local playtimeData = PlaytimeService.GetPlaytimeData(player.UserId)
	if not playtimeData then
		SendProfileUpdate(player, {
			error = {
				code = "PROFILE_LOAD_FAILED",
				message = "Failed to load playtime data"
			},
			serverNow = os.time()
		})
		return
	end
	
	-- Send playtime data
	SendProfileUpdate(player, {
		playtime = {
			totalTime = playtimeData.totalTime,
			claimedRewards = playtimeData.claimedRewards,
			rewardsConfig = playtimeData.rewardsConfig
		},
		serverNow = os.time()
	})
	
	LogInfo(player, "Playtime data sent successfully")
end

local function HandleRequestClaimPlaytimeReward(player, requestData)
	LogInfo(player, "Processing claim playtime reward request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestClaimPlaytimeReward")
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
	
	-- Validate request
	if not requestData or type(requestData.rewardIndex) ~= "number" then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_REQUEST",
				message = "Missing or invalid rewardIndex"
			},
			serverNow = os.time()
		})
		return
	end
	
	-- Claim reward
	local result = PlaytimeService.ClaimPlaytimeReward(player.UserId, requestData.rewardIndex)
	
	-- Get updated profile
	local profile = PlayerDataService.GetProfile(player)
	local payload = {
		currencies = profile and profile.currencies or {},
		lootboxes = profile and profile.lootboxes or {},
		pendingLootbox = profile and profile.pendingLootbox or nil,
		serverNow = os.time()
	}
	
	if result.ok then
		-- Include rewards and collection summary if lootbox was opened
		if result.rewards then
			payload.rewards = result.rewards
			local collection = PlayerDataService.GetCollection(player)
			if collection then
				payload.collectionSummary = CreateCollectionSummary(collection)
			end
		end
		
		-- Include updated playtime data
		local playtimeData = PlaytimeService.GetPlaytimeData(player.UserId)
		if playtimeData then
			payload.playtime = {
				totalTime = playtimeData.totalTime,
				claimedRewards = playtimeData.claimedRewards,
				rewardsConfig = playtimeData.rewardsConfig
			}
		end
		
		LogInfo(player, "Playtime reward %d claimed successfully", requestData.rewardIndex)
	else
		payload.error = {
			code = result.error,
			message = result.error
		}
		LogWarning(player, "Claim playtime reward failed: %s", tostring(result.error))
	end
	
	SendProfileUpdate(player, payload)
end

local function HandleRequestDailyData(player, requestData)
	LogInfo(player, "Processing daily data request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestDailyData")
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
	
	-- Get daily data
	local dailyData = DailyService.GetDailyData(player.UserId)
	if not dailyData then
		SendProfileUpdate(player, {
			error = {
				code = "PROFILE_LOAD_FAILED",
				message = "Failed to load daily data"
			},
			serverNow = os.time()
		})
		return
	end
	
	-- Send daily data
	SendProfileUpdate(player, {
		daily = {
			streak = dailyData.streak,
			lastLogin = dailyData.lastLogin,
			currentDay = dailyData.currentDay,
			isClaimed = dailyData.isClaimed,
			rewardsConfig = dailyData.rewardsConfig
		},
		serverNow = os.time()
	})
	
	LogInfo(player, "Daily data sent successfully")
end

local function HandleRequestClaimDailyReward(player, requestData)
	LogInfo(player, "Processing claim daily reward request")
	
	-- Rate limiting
	local canProceed, errorMessage = CheckRateLimit(player, "RequestClaimDailyReward")
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
	
	-- Validate request
	if not requestData or type(requestData.rewardIndex) ~= "number" then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_REQUEST",
				message = "Missing or invalid rewardIndex"
			},
			serverNow = os.time()
		})
		return
	end
	
	-- Claim reward
	local result = DailyService.ClaimDailyReward(player.UserId, requestData.rewardIndex)
	
	-- Get updated profile
	local profile = PlayerDataService.GetProfile(player)
	local payload = {
		currencies = profile and profile.currencies or {},
		lootboxes = profile and profile.lootboxes or {},
		pendingLootbox = profile and profile.pendingLootbox or nil,
		serverNow = os.time()
	}
	
	if result.ok then
		-- Include rewards and collection summary if lootbox was opened
		if result.rewards then
			payload.rewards = result.rewards
			local collection = PlayerDataService.GetCollection(player)
			if collection then
				payload.collectionSummary = CreateCollectionSummary(collection)
			end
		end
		
		-- Include updated daily data
		local dailyData = DailyService.GetDailyData(player.UserId)
		if dailyData then
			payload.daily = {
				streak = dailyData.streak,
				lastLogin = dailyData.lastLogin,
				currentDay = dailyData.currentDay,
				isClaimed = dailyData.isClaimed,
				rewardsConfig = dailyData.rewardsConfig
			}
		end
		
		LogInfo(player, "Daily reward %d claimed successfully", requestData.rewardIndex)
	else
		payload.error = {
			code = result.error,
			message = result.error
		}
		LogWarning(player, "Claim daily reward failed: %s", tostring(result.error))
	end
	
	SendProfileUpdate(player, payload)
end

local function HandleRequestBuyLootbox(player, requestData)
	LogInfo(player, "Processing buy lootbox request")
	
	local canProceed, errorMessage = CheckRateLimit(player, "RequestBuyLootbox")
	if not canProceed then
		SendProfileUpdate(player, {
			error = { code = "RATE_LIMITED", message = errorMessage },
			serverNow = os.time()
		})
		return
	end
	
	-- Validate request
	if not requestData or not requestData.rarity then
		SendProfileUpdate(player, {
			error = { code = "INVALID_REQUEST", message = "Missing rarity" },
			serverNow = os.time()
		})
		return
	end
	
	local result = ShopService.BuyLootbox(player.UserId, requestData.rarity)
	
	-- Get updated profile for response
	local profile = PlayerDataService.GetProfile(player)
	local payload = {
		currencies = profile and profile.currencies or {},
		lootboxes = profile and profile.lootboxes or {},
		pendingLootbox = profile and profile.pendingLootbox or nil,
		serverNow = os.time()
	}
	
	if result.ok then
		-- Include rewards and collection summary for successful purchase
		if result.rewards then
			payload.rewards = result.rewards
			local collection = PlayerDataService.GetCollection(player)
			payload.collectionSummary = CreateCollectionSummary(collection)
		end
		LogInfo(player, "Shop lootbox purchase successful")
	else
		payload.error = {
			code = result.error,
			message = result.error
		}
		LogWarning(player, "Shop lootbox purchase failed: %s", tostring(result.error))
	end
	
	SendProfileUpdate(player, payload)
	
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
		SendProfileUpdate(player, {
			error = {
				code = "RATE_LIMITED",
				message = errorMessage
			},
			serverNow = os.time()
		})
		return
	end
	
	-- Validate payload
	if not requestData or not requestData.rewardType then
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_REQUEST",
				message = "Missing rewardType field"
			},
			serverNow = os.time()
		})
		return
	end
	
	-- Get updated profile
	local profile, _, _ = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		SendProfileUpdate(player, {
			error = {
				code = "INTERNAL",
				message = "Failed to load profile"
			},
			serverNow = os.time()
		})
		return
	end
	
	local payload = {
		currencies = profile.currencies,
		lootboxes = profile.lootboxes,
		pendingLootbox = profile.pendingLootbox,
		serverNow = os.time()
	}
	
	if requestData.rewardType == "soft" then
		-- Grant soft currency
		local amount = requestData.amount or 0
		if amount <= 0 then
			SendProfileUpdate(player, {
				error = {
					code = "INVALID_REQUEST",
					message = "Invalid soft currency amount"
				},
				serverNow = os.time()
			})
			return
		end
		
		-- Use ProfileManager to add currency
		local success, errorMsg = ProfileManager.AddCurrency(player.UserId, "soft", amount)
		if success then
			-- Reload profile to get updated currencies
			profile, _, _ = PlayerDataService.EnsureProfileLoaded(player)
			if profile then
				payload.currencies = profile.currencies
			end
			LogInfo(player, "Soft currency reward granted: %d", amount)
		else
			SendProfileUpdate(player, {
				error = {
					code = "INTERNAL",
					message = errorMsg or "Failed to grant soft currency"
				},
				serverNow = os.time()
			})
			return
		end
	elseif requestData.rewardType == "lootbox" then
		-- Grant lootbox
		local rarity = requestData.rarity
		if not rarity then
			SendProfileUpdate(player, {
				error = {
					code = "INVALID_REQUEST",
					message = "Missing rarity for lootbox reward"
				},
				serverNow = os.time()
			})
			return
		end
		
		-- Check if player has free slot
		local lootboxCount = 0
		for i = 1, 4 do
			if profile.lootboxes[i] then
				lootboxCount = lootboxCount + 1
			end
		end
		
		if lootboxCount >= 4 then
			-- No free slot - this shouldn't happen if client checked, but handle it
			SendProfileUpdate(player, {
				error = {
					code = "NO_FREE_SLOT",
					message = "No free lootbox slot available"
				},
				serverNow = os.time()
			})
			return
		end
		
		-- Add lootbox using LootboxService
		local result = LootboxService.TryAddBox(player.UserId, rarity, "battle_reward")
		if result.ok then
			-- Reload profile to get updated lootboxes
			profile, _, _ = PlayerDataService.EnsureProfileLoaded(player)
			if profile then
				payload.lootboxes = profile.lootboxes
				payload.pendingLootbox = profile.pendingLootbox
			end
			LogInfo(player, "Lootbox reward granted: %s", rarity)
		else
			SendProfileUpdate(player, {
				error = {
					code = result.error or "INTERNAL",
					message = "Failed to grant lootbox reward"
				},
				serverNow = os.time()
			})
			return
		end
	else
		SendProfileUpdate(player, {
			error = {
				code = "INVALID_REQUEST",
				message = "Invalid reward type: " .. tostring(requestData.rewardType)
			},
			serverNow = os.time()
		})
		return
	end
	
	-- Send success response
	SendProfileUpdate(player, payload)
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

