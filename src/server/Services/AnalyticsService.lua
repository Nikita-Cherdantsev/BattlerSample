--[[
	Analytics Service
	
	Server-side service for tracking Roblox Funnel Events.
	Handles event debouncing, admin filtering, and event configuration.
]]

local AnalyticsService = {}

local RobloxAnalytics = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)

-- Configuration
local ANALYTICS_CONFIG = {
	enabled = true,
	adminUserIds = {
		-- Add admin UserIds here to exclude them from analytics
		-- Example: 123456789, 987654321
	},
	
	-- All events use the same funnel name to group them together
	funnelName = "GameEvents",
	
	-- Step numbers for each event type (must be unique)
	-- IMPORTANT: Step is NOT the order of events in a funnel - it's just a unique identifier
	-- for each event type. Since we're using a single funnel for all events, each event type
	-- needs a unique step number to differentiate them in analytics.
	-- 
	-- Example: If a player does CardUpgraded (step 3) and then LootboxOpened (step 2),
	-- both events will appear in the "GameEvents" funnel with their respective step numbers.
	-- The step number doesn't imply order - it's just a label for the event type.
	events = {
		DailyRewardClaimed = {
			step = 1,  -- Unique identifier for this event type in the funnel
			customFields = {"reward_id"},
			debounceMs = 100
		},
		LootboxOpened = {
			step = 2,  -- Unique identifier for this event type in the funnel
			customFields = {"lootbox_type", "free_lootbox"},
			debounceMs = 100
		},
		CardUpgraded = {
			step = 3,  -- Unique identifier for this event type in the funnel
			customFields = {"card_id", "new_level"},
			debounceMs = 100
		},
		PlaytimeRewardClaimed = {
			step = 4,  -- Unique identifier for this event type in the funnel
			customFields = {"milestone_id"},
			debounceMs = 100
		}
	}
}

-- Debounce tracking: eventName -> userId -> lastSentTimestamp
local debounceCache = {}

-- Session tracking: userId -> funnelSessionId (one session per player per server)
-- This ensures all events from a player in the same game session share the same funnelSessionId
-- Using game.JobId ensures automatic uniqueness across different servers
-- Format: "userId_JobId" - automatically unique per server, no need to clear on rejoin
local playerSessions = {}

-- Session start timestamps (seconds) to compute session duration for custom fields
-- userId -> os.time() when the player joined the server
local sessionStartTimes = {}

-- Check if player is admin
local function IsAdmin(userId)
	if not ANALYTICS_CONFIG.adminUserIds then
		return false
	end
	
	for _, adminId in ipairs(ANALYTICS_CONFIG.adminUserIds) do
		if userId == adminId then
			return true
		end
	end
	return false
end

-- Check if event should be sent (debounce check)
local function ShouldSendEvent(eventName, userId)
	if not ANALYTICS_CONFIG.enabled then
		return false
	end
	
	-- Check if admin
	if IsAdmin(userId) then
		return false
	end
	
	-- Check debounce
	local eventConfig = ANALYTICS_CONFIG.events[eventName]
	if not eventConfig then
		return false
	end
	
	local now = tick() * 1000 -- Convert to milliseconds
	local cacheKey = eventName .. "_" .. tostring(userId)
	local lastSent = debounceCache[cacheKey]
	
	if lastSent and (now - lastSent) < eventConfig.debounceMs then
		return false -- Too soon, skip
	end
	
	-- Update debounce cache
	debounceCache[cacheKey] = now
	
	-- Cleanup old entries periodically (keep cache size manageable)
	-- Check cache size every 100th call to avoid overhead
	local cleanupCounter = (debounceCache._cleanupCounter or 0) + 1
	debounceCache._cleanupCounter = cleanupCounter
	
	if cleanupCounter >= 100 then
		debounceCache._cleanupCounter = 0
		local entryCount = 0
		for _ in pairs(debounceCache) do
			entryCount = entryCount + 1
		end
		-- If cache has more than 1000 entries, clear it
		if entryCount > 1000 then
			debounceCache = {}
		end
	end
	
	return true
end

-- Normalize currency type to the canonical names used in analytics
-- Accepts "hard"/"soft"/"Gold"/"Energy" (case-insensitive) and returns "Gold" or "Energy"
local function normalizeCurrencyType(currencyType)
	if not currencyType then
		return nil
	end
	local lowered = string.lower(tostring(currencyType))
	if lowered == "hard" or lowered == "gold" then
		return "Gold"
	end
	if lowered == "soft" or lowered == "energy" then
		return "Energy"
	end
	return nil
end

-- Build economy custom fields (PlayTimeMinutes, SessionTimeMinutes, CollectionPower)
-- profile is optional but recommended for accurate totals (expects playtime.totalTime and squadPower)
function AnalyticsService.BuildEconomyCustomFields(userId, profile)
	local playtimeMinutes = nil
	local sessionMinutes = nil
	local collectionPower = nil

	local now = os.time()
	
	-- Используем sessionStartTimes из AnalyticsService для SessionTimeMinutes
	local sessionStart = sessionStartTimes[userId]
	if sessionStart then
		sessionMinutes = math.max(0, math.floor((now - sessionStart) / 60))
	end

	-- Для PlayTimeMinutes используем ту же логику, что и лидерборд
	-- Сначала пытаемся получить накопленное время из DataStore лидерборда
	-- Если недоступно, используем PlaytimeService.GetPlaytimeData
	if profile and profile.playtime then
		local totalSeconds = 0
		
		-- Пытаемся получить накопленное время из DataStore лидерборда (как в лидерборде)
		local success, dataStoreValue = pcall(function()
			local DataStoreService = game:GetService("DataStoreService")
			local dataStore = DataStoreService:GetOrderedDataStore("GlobalLeaderboard_TotalPlaytimeSeconds")
			return dataStore:GetAsync(userId)
		end)
		
		if success and dataStoreValue and type(dataStoreValue) == "number" and dataStoreValue > 0 then
			-- Используем накопленное время из DataStore (как в лидерборде)
			totalSeconds = dataStoreValue
		else
			-- Fallback: используем PlaytimeService.GetPlaytimeData (текущее время + сессия)
			local playtimeSuccess, playtimeData = pcall(function()
				local PlaytimeService = require(script.Parent.PlaytimeService)
				return PlaytimeService.GetPlaytimeData(userId)
			end)
			
			if playtimeSuccess and playtimeData and playtimeData.totalTime then
				totalSeconds = playtimeData.totalTime
			else
				-- Последний fallback: используем логику из профиля + текущая сессия
				local baseSeconds = profile.playtime.totalTime or 0
				if sessionStart then
					totalSeconds = baseSeconds + (now - sessionStart)
				else
					totalSeconds = baseSeconds
				end
			end
		end
		
		playtimeMinutes = math.max(0, math.floor(totalSeconds / 60))
	end

	if profile and type(profile.squadPower) == "number" then
		collectionPower = profile.squadPower
	end

	local fieldsToSend = {}
	local customFieldEnums = {
		Enum.AnalyticsCustomFieldKeys.CustomField01,
		Enum.AnalyticsCustomFieldKeys.CustomField02,
		Enum.AnalyticsCustomFieldKeys.CustomField03
	}

	local orderedValues = { playtimeMinutes, sessionMinutes, collectionPower }
	for index, value in ipairs(orderedValues) do
		if value ~= nil then
			local enumKey = customFieldEnums[index]
			if enumKey then
				fieldsToSend[enumKey.Name] = tostring(value)
			end
		end
	end

	return fieldsToSend
end

-- Public helper to expose session start for other modules (read-only)
function AnalyticsService.GetSessionStartTime(userId)
	return sessionStartTimes[userId]
end

-- Log Roblox Economy Event with optional custom fields
-- flowType: Enum.AnalyticsEconomyFlowType (or string "Source"/"Sink")
-- currencyType: "Gold" or "Energy" (accepts hard/soft aliases)
-- amount: number (positive)
-- balanceAfterTransaction: automatically calculated from profile (balance after the transaction)
-- transactionType: always "Gameplay" for now (Enum.AnalyticsEconomyTransactionType.Gameplay.Name)
-- itemSku: optional string identifier (e.g., Lootbox_rare, Gold_S)
-- customFields: optional map with CustomField01/02/03 keys (string values) using Enum.AnalyticsCustomFieldKeys
function AnalyticsService.LogEconomyEvent(params)
	if not params then
		return
	end

	local userId = params.userId
	if not userId or IsAdmin(userId) then
		return
	end

	if not ANALYTICS_CONFIG.enabled then
		return
	end

	local flowType = params.flowType
	if type(flowType) == "string" then
		local lowered = string.lower(flowType)
		if lowered == "source" then
			flowType = Enum.AnalyticsEconomyFlowType.Source
		elseif lowered == "sink" then
			flowType = Enum.AnalyticsEconomyFlowType.Sink
		end
	end

	if flowType ~= Enum.AnalyticsEconomyFlowType.Source and flowType ~= Enum.AnalyticsEconomyFlowType.Sink then
		warn(string.format("[AnalyticsService] Invalid flowType for economy event: %s", tostring(params.flowType)))
		return
	end

	local currencyType = normalizeCurrencyType(params.currencyType)
	if not currencyType then
		warn(string.format("[AnalyticsService] Invalid currencyType for economy event: %s", tostring(params.currencyType)))
		return
	end

	local amount = tonumber(params.amount) or 0
	if amount <= 0 then
		-- Ignore zero/negative changes
		return
	end

	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end

	-- Получаем баланс ПОСЛЕ транзакции (обязательный параметр!)
	local profile = ProfileManager.GetCachedProfile(userId)
	if not profile then
		warn(string.format("[AnalyticsService] Cannot get balance - profile not loaded for userId %s", tostring(userId)))
		return
	end

	local balanceAfterTransaction = 0
	if currencyType == "Gold" then
		balanceAfterTransaction = profile.currencies and profile.currencies.hard or 0
	elseif currencyType == "Energy" then
		balanceAfterTransaction = profile.currencies and profile.currencies.soft or 0
	end

	-- Всегда используем Gameplay для всех событий (пока один тип для всех)
	local transactionType = Enum.AnalyticsEconomyTransactionType.Gameplay.Value

	local itemSku = params.itemSku
	if itemSku ~= nil and type(itemSku) ~= "string" then
		itemSku = tostring(itemSku)
	end

	-- Получаем customFields из params или строим автоматически
	local customFields = params.customFields
	if not customFields then
		-- Если не переданы, строим автоматически
		customFields = AnalyticsService.BuildEconomyCustomFields(userId, profile)
	end

	-- Debug: логируем все параметры перед отправкой
	print(string.format("[AnalyticsService] 🔍 DEBUG LogEconomyEvent | userId=%s | flowType=%s | currencyType=%s | amount=%s | balanceAfter=%s | transactionType=%s (type: %s) | itemSku=%s | customFields=%s",
		tostring(userId),
		tostring(flowType),
		tostring(currencyType),
		tostring(amount),
		tostring(balanceAfterTransaction),
		tostring(transactionType), type(transactionType),
		tostring(itemSku),
		HttpService:JSONEncode(customFields)
	))

	local success, errorMsg = pcall(function()
		-- Правильный порядок параметров согласно официальной документации:
		-- 1. player
		-- 2. flowType (Enum)
		-- 3. currencyType (string)
		-- 4. amount (number)
		-- 5. balanceAfterTransaction (number) - ОБЯЗАТЕЛЬНЫЙ!
		-- 6. transactionType (string - .Name)
		-- 7. itemSku (string, optional)
		-- 8. customFields (table, optional)
		RobloxAnalytics:LogEconomyEvent(
			player,
			flowType,
			currencyType,
			amount,
			balanceAfterTransaction,
			transactionType,
			itemSku,
			customFields
		)
	end)

	if not success then
		warn(string.format("[AnalyticsService] ❌ Failed to send economy event for userId %s: %s", tostring(userId), tostring(errorMsg)))
	else
		print(string.format("[AnalyticsService] ✅ Economy event sent | userId=%s | flow=%s | currency=%s | amount=%s | balanceAfter=%s | transactionType=%s | sku=%s | fields=%s",
			tostring(userId),
			tostring(flowType),
			tostring(currencyType),
			tostring(amount),
			tostring(balanceAfterTransaction),
			tostring(transactionType),
			tostring(itemSku),
			HttpService:JSONEncode(customFields)))
	end
end

-- Send funnel event to Roblox Analytics
function AnalyticsService.SendEvent(eventName, userId, customFields)
	if not ShouldSendEvent(eventName, userId) then
		return
	end
	
	local eventConfig = ANALYTICS_CONFIG.events[eventName]
	if not eventConfig then
		warn(string.format("[AnalyticsService] Unknown event: %s", eventName))
		return
	end
	
	-- Validate custom fields count (max 3)
	-- Roblox requires using Enum.AnalyticsCustomFieldKeys for custom field keys
	-- CustomField01, CustomField02, CustomField03 are the only valid keys
	local fieldsToSend = {}
	local fieldNames = eventConfig.customFields or {}
	
	-- Map of index to Enum key
	local customFieldEnums = {
		Enum.AnalyticsCustomFieldKeys.CustomField01,
		Enum.AnalyticsCustomFieldKeys.CustomField02,
		Enum.AnalyticsCustomFieldKeys.CustomField03
	}
	
	for i, fieldName in ipairs(fieldNames) do
		if i > 3 then
			break -- Max 3 custom fields
		end
		local value = customFields and customFields[fieldName]
		if value ~= nil then
			-- Use Enum.AnalyticsCustomFieldKeys for keys (CustomField01, CustomField02, CustomField03)
			-- IMPORTANT: Values must be strings
			local customFieldEnum = customFieldEnums[i]
			if customFieldEnum then
				-- Use the Enum's Name property as the key
				fieldsToSend[customFieldEnum.Name] = tostring(value)
			end
		else
			-- Log missing field for debugging
			print(string.format("[AnalyticsService] WARNING: Missing custom field '%s' for event %s", fieldName, eventName))
		end
	end
	
	-- Send event via Roblox AnalyticsService
	-- Get player object for LogFunnelStepEvent
	-- Player check moved to before session creation (see above)
	
	-- Debug: Log what we're about to send
	print("========================================")
	print(string.format("[AnalyticsService] EVENT: %s", eventName))
	print(string.format("[AnalyticsService] userId: %s", tostring(userId)))
	print(string.format("[AnalyticsService] step: %d", eventConfig.step))
	print(string.format("[AnalyticsService] Received customFields (raw): %s", HttpService:JSONEncode(customFields or {})))
	print(string.format("[AnalyticsService] Expected fieldNames: %s", HttpService:JSONEncode(fieldNames)))
	
	-- Show field mapping (using Enum keys for display)
	local customFieldEnums = {
		Enum.AnalyticsCustomFieldKeys.CustomField01,
		Enum.AnalyticsCustomFieldKeys.CustomField02,
		Enum.AnalyticsCustomFieldKeys.CustomField03
	}
	for i, fieldName in ipairs(fieldNames) do
		if i > 3 then break end
		local value = customFields and customFields[fieldName]
		local customFieldEnum = customFieldEnums[i]
		local customFieldKey = customFieldEnum and customFieldEnum.Name or ("CustomField0" .. tostring(i))
		print(string.format("[AnalyticsService]   Mapping: %s -> %s = %s (raw value: %s, type: %s)", 
			fieldName, customFieldKey, tostring(value or "nil"), tostring(value or "nil"), type(value)))
	end
	
	print(string.format("[AnalyticsService] fieldsToSend (final): %s", HttpService:JSONEncode(fieldsToSend)))
	local fieldCount = 0
	for k, v in pairs(fieldsToSend) do
		fieldCount = fieldCount + 1
		print(string.format("[AnalyticsService]   Final field %d: %s = %s (type: %s)", fieldCount, tostring(k), tostring(v), type(v)))
	end
	print(string.format("[AnalyticsService] Total fields to send: %d", fieldCount))
	print("========================================")
	
	-- Get or create session ID for this player (before pcall so we can use it in logging)
	-- All events from the same player session share the same funnelSessionId
	-- IMPORTANT: Verify player still exists before creating/reusing session
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		warn(string.format("[AnalyticsService] ⚠️  Cannot create session - player %s not found (may have left)", 
			tostring(userId)))
		return
	end
	
	-- Generate session ID based on userId + JobId
	-- This automatically ensures:
	-- 1. Different servers = different sessionId (different JobId)
	-- 2. Rejoin on same server = new sessionId (PlayerAdded clears old, creates new)
	-- 3. Same player, same server, no rejoin = same sessionId (cached)
	local funnelSessionId = playerSessions[userId]
	if not funnelSessionId then
		-- First event from this player on this server - create session ID
		-- Format: "userId_JobId" - unique per player per server
		funnelSessionId = tostring(userId) .. "_" .. game.JobId
		playerSessions[userId] = funnelSessionId
		print(string.format("[AnalyticsService] ✅ Created NEW session for userId %s (player: %s, server: %s): %s", 
			tostring(userId), player.Name, game.JobId, funnelSessionId))
	else
		print(string.format("[AnalyticsService] ♻️  Reusing EXISTING session for userId %s (player: %s): %s", 
			tostring(userId), player.Name, funnelSessionId))
	end
	
	local funnelName = ANALYTICS_CONFIG.funnelName or "GameEvents"
	local step = eventConfig.step or 1
	local stepName = eventName
	
	local success, errorMsg = pcall(function()
		-- Use LogFunnelStepEvent for Funnel Events
		-- All events use the same funnelName to group them in one funnel
		-- All events from the same player session share the same funnelSessionId
		-- Different event types use different step numbers
		-- stepName describes the specific event type
		-- customFields provide additional filtering data
		
		-- LogFunnelStepEvent signature:
		-- LogFunnelStepEvent(player, funnelName, funnelSessionId, step, stepName, customFields?)
		-- customFields must be a dictionary/table with string keys and string values
		
		print(string.format("[AnalyticsService] Sending event: funnelName=%s, funnelSessionId=%s, step=%d, stepName=%s", 
			funnelName, funnelSessionId, step, stepName))
		
		-- Always pass customFields, even if empty (Roblox handles empty tables)
		RobloxAnalytics:LogFunnelStepEvent(
			player,
			funnelName,  -- Same for all events - groups them in one funnel
			funnelSessionId,  -- Same for all events from same player session
			step,  -- Different for each event type (1, 2, 3, 4)
			stepName,  -- Event name (DailyRewardClaimed, LootboxOpened, etc.)
			fieldsToSend  -- Custom fields for filtering (custom_field_1, custom_field_2, custom_field_3)
		)
	end)
	
	-- Debug logging (can be removed after testing)
	if success then
		-- Count active sessions and players for statistics
		local activeSessionsCount = 0
		for _ in pairs(playerSessions) do
			activeSessionsCount = activeSessionsCount + 1
		end
		local activePlayersCount = #Players:GetPlayers()
		
		print(string.format("[AnalyticsService] ✅ Event sent: %s | userId: %s | sessionId: %s | step: %d", 
			eventName, tostring(userId), funnelSessionId, step))
		print(string.format("[AnalyticsService] 📊 Stats: Active sessions: %d | Active players: %d | Custom fields: %s", 
			activeSessionsCount, activePlayersCount, HttpService:JSONEncode(fieldsToSend)))
		
		-- Warning if we have more sessions than players (should not happen)
		if activeSessionsCount > activePlayersCount then
			warn(string.format("[AnalyticsService] ⚠️  WARNING: More sessions (%d) than active players (%d)! This should not happen.", 
				activeSessionsCount, activePlayersCount))
		end
	else
		warn(string.format("[AnalyticsService] ❌ Failed to send event %s for userId %s: %s", 
			eventName, tostring(userId), tostring(errorMsg)))
	end
end

-- Convenience functions for each event type
function AnalyticsService.TrackDailyRewardClaimed(userId, rewardId)
	AnalyticsService.SendEvent("DailyRewardClaimed", userId, {
		reward_id = rewardId
	})
end

function AnalyticsService.TrackLootboxOpened(userId, lootboxType, source)
	-- Determine if lootbox is free (1) or purchased (0)
	-- free_lootbox = 1: HUD, playtime rewards, daily rewards, battle rewards, starter, etc.
	-- free_lootbox = 0: purchased in shop
	local freeLootbox = 1 -- Default to free (most lootboxes are free)
	if source == "shop" then
		freeLootbox = 0 -- Purchased in shop
	end
	
	AnalyticsService.SendEvent("LootboxOpened", userId, {
		lootbox_type = lootboxType,
		free_lootbox = freeLootbox
	})
end

function AnalyticsService.TrackCardUpgraded(userId, cardId, newLevel)
	AnalyticsService.SendEvent("CardUpgraded", userId, {
		card_id = cardId,
		new_level = newLevel
	})
end

function AnalyticsService.TrackPlaytimeRewardClaimed(userId, milestoneId)
	AnalyticsService.SendEvent("PlaytimeRewardClaimed", userId, {
		milestone_id = milestoneId
	})
end

-- Initialize AnalyticsService - track player sessions
local isInitialized = false

function AnalyticsService.Init()
	if isInitialized then
		return
	end
	
	isInitialized = true
	
	-- Create session when player joins
	Players.PlayerAdded:Connect(function(player)
		local userId = player.UserId
		sessionStartTimes[userId] = os.time()
		-- IMPORTANT: Clear any existing session for this userId (in case of rejoin)
		-- This ensures that if a player rejoins, they get a fresh session
		-- Even though JobId-based sessionId would be the same on rejoin, we clear it
		-- to ensure a fresh session starts (in case of edge cases or server restart)
		if playerSessions[userId] then
			print(string.format("[AnalyticsService] ⚠️  Player %s rejoined - clearing old session: %s", 
				tostring(userId), playerSessions[userId]))
			playerSessions[userId] = nil
		end
		-- Session will be created on first event using userId + JobId
		-- This ensures we only track sessions where players actually perform actions
	end)
	
	-- Clear session when player leaves
	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		if playerSessions[userId] then
			print(string.format("[AnalyticsService] 🚪 Player %s left, clearing session: %s", 
				tostring(userId), playerSessions[userId]))
			playerSessions[userId] = nil
		end
		sessionStartTimes[userId] = nil
	end)
	
	-- Handle players already in game (in case of server restart)
	for _, player in ipairs(Players:GetPlayers()) do
		local userId = player.UserId
		sessionStartTimes[userId] = sessionStartTimes[userId] or os.time()
		if playerSessions[userId] then
			print(string.format("[AnalyticsService] ⚠️  Clearing existing session for player already in game: %s", 
				tostring(userId)))
			playerSessions[userId] = nil
		end
	end
	
	print("✅ AnalyticsService initialized")
end

return AnalyticsService

