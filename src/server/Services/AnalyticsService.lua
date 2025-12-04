--[[
	Analytics Service
	
	Server-side service for tracking Roblox Funnel Events.
	Handles event debouncing, admin filtering, and event configuration.
]]

local AnalyticsService = {}

local RobloxAnalytics = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- Configuration
local ANALYTICS_CONFIG = {
	enabled = true,
	adminUserIds = {
		-- Add admin UserIds here to exclude them from analytics
		-- Example: 123456789, 987654321
	},
	
	events = {
		DailyRewardClaimed = {
			customFields = {"reward_id"},
			debounceMs = 100
		},
		LootboxOpened = {
			customFields = {"lootbox_type", "free_lootbox"},
			debounceMs = 100
		},
		CardUpgraded = {
			customFields = {"card_id", "new_level"},
			debounceMs = 100
		},
		PlaytimeRewardClaimed = {
			customFields = {"milestone_id"},
			debounceMs = 100
		}
	}
}

-- Debounce tracking: eventName -> userId -> lastSentTimestamp
local debounceCache = {}

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
	-- Roblox expects custom fields as custom_field_1, custom_field_2, custom_field_3
	local fieldsToSend = {}
	local fieldNames = eventConfig.customFields or {}
	
	for i, fieldName in ipairs(fieldNames) do
		if i > 3 then
			break -- Max 3 custom fields
		end
		local value = customFields and customFields[fieldName]
		if value ~= nil then
			-- Use custom_field_1, custom_field_2, custom_field_3 as keys
			local customFieldKey = "custom_field_" .. tostring(i)
			fieldsToSend[customFieldKey] = tostring(value)
		end
	end
	
	-- Send event via Roblox AnalyticsService
	-- Get player object for LogFunnelStepEvent
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		warn(string.format("[AnalyticsService] Player not found for userId %s, skipping event %s", 
			tostring(userId), eventName))
		return
	end
	
	-- Debug: Log what we're about to send
	print(string.format("[AnalyticsService] Preparing to send: %s, userId: %s", eventName, tostring(userId)))
	print(string.format("[AnalyticsService] Received customFields: %s", HttpService:JSONEncode(customFields or {})))
	print(string.format("[AnalyticsService] Expected fieldNames: %s", HttpService:JSONEncode(fieldNames)))
	print(string.format("[AnalyticsService] fieldsToSend after processing: %s", HttpService:JSONEncode(fieldsToSend)))
	local fieldCount = 0
	for k, v in pairs(fieldsToSend) do
		fieldCount = fieldCount + 1
		print(string.format("[AnalyticsService]   Field %d: %s = %s (type: %s)", fieldCount, tostring(k), tostring(v), type(v)))
	end
	print(string.format("[AnalyticsService] Total fields to send: %d", fieldCount))
	
	local success, errorMsg = pcall(function()
		-- Use LogFunnelStepEvent for recurring Funnel Events
		-- Each event is treated as a single-step funnel with its own session
		-- funnelName = eventName (groups all instances of this event type)
		-- funnelSessionId = unique GUID for each event instance
		-- step = 1 (each event is a single step)
		-- stepName = eventName (describes the step)
		-- customFields = optional table with custom data for filtering
		local funnelSessionId = HttpService:GenerateGUID() -- Generate unique session ID for this event
		
		-- LogFunnelStepEvent signature:
		-- LogFunnelStepEvent(player, funnelName, funnelSessionId, step, stepName, customFields?)
		-- Note: customFields must be a dictionary/table, not nil
		if next(fieldsToSend) == nil then
			-- Empty table - don't pass it (might cause issues)
			RobloxAnalytics:LogFunnelStepEvent(
				player,
				eventName,
				funnelSessionId,
				1,
				eventName
			)
		else
			RobloxAnalytics:LogFunnelStepEvent(
				player,
				eventName,  -- funnelName: groups all instances of this event type together
				funnelSessionId,  -- unique session ID for this specific event instance
				1,  -- step: always 1 since each event is a single-step funnel
				eventName,  -- stepName: description of this step
				fieldsToSend  -- customFields: optional table for filtering/breakdown
			)
		end
	end)
	
	-- Debug logging (can be removed after testing)
	if success then
		print(string.format("[AnalyticsService] Event sent successfully: %s, userId: %s, fields: %s", 
			eventName, tostring(userId), HttpService:JSONEncode(fieldsToSend)))
	else
		warn(string.format("[AnalyticsService] Failed to send event %s for userId %s: %s", 
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

return AnalyticsService

