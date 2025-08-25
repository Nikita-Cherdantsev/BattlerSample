--[[
	Time Utilities for UI Integration
	
	This module provides time-related helpers and constants
	used by both client and server for consistent time handling.
]]

local TimeUtils = {}

-- Get current Unix timestamp
-- On server: wraps os.time()
-- On client: can be used to hold last known server time
function TimeUtils.nowUnix()
	return os.time()
end

-- Convert minutes to seconds
function TimeUtils.seconds(minutes)
	return minutes * 60
end

-- Clamp a number between min and max values
function TimeUtils.clamp(n, min, max)
	return math.max(min, math.min(max, n))
end

-- Lootbox unlocking durations (in seconds)
TimeUtils.lootboxDurations = {
	Common = TimeUtils.seconds(20),     -- 20 minutes
	Rare = TimeUtils.seconds(60),       -- 60 minutes (1 hour)
	Epic = TimeUtils.seconds(240),      -- 240 minutes (4 hours)
	Legendary = TimeUtils.seconds(480)  -- 480 minutes (8 hours)
}

-- Format duration as human-readable string
function TimeUtils.formatDuration(seconds)
	if seconds < 60 then
		return string.format("%ds", seconds)
	elseif seconds < 3600 then
		local minutes = math.floor(seconds / 60)
		return string.format("%dm", minutes)
	else
		local hours = math.floor(seconds / 3600)
		local minutes = math.floor((seconds % 3600) / 60)
		if minutes > 0 then
			return string.format("%dh %dm", hours, minutes)
		else
			return string.format("%dh", hours)
		end
	end
end

-- Get time remaining until target timestamp
function TimeUtils.getTimeRemaining(targetTimestamp)
	local now = TimeUtils.nowUnix()
	local remaining = targetTimestamp - now
	return math.max(0, remaining)
end

-- Check if a timestamp is in the past
function TimeUtils.isExpired(timestamp)
	return TimeUtils.nowUnix() > timestamp
end

-- Get lootbox duration for a rarity
function TimeUtils.getLootboxDuration(rarity)
	return TimeUtils.lootboxDurations[rarity] or TimeUtils.lootboxDurations.Common
end

-- Calculate lootbox end time from start time and rarity
function TimeUtils.calculateLootboxEndTime(startTime, rarity)
	local duration = TimeUtils.getLootboxDuration(rarity)
	return startTime + duration
end

return TimeUtils
