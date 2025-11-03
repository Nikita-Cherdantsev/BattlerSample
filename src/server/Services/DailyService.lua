--[[
	Daily Service
	
	Server-side operations for daily reward management.
	All operations use atomic UpdateAsync for data consistency.
]]

local DailyService = {}

-- Services
local Players = game:GetService("Players")

-- Modules
local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)
local ProfileSchema = require(script.Parent.Parent.Persistence.ProfileSchema)
local LootboxService = require(script.Parent.LootboxService)
local Logger = require(game.ReplicatedStorage.Modules.Logger)

-- Rewards configuration
local REWARDS_CONFIG = {
	[1] = { 
		{type = "Currency", name = "Soft", amount = 225}
	},
	[2] = {
		{type = "Currency", name = "Hard", amount = 20}
	},
	[3] = {
		{type = "Lootbox", name = "uncommon", amount = 1}
	},
	[4] = {
		{type = "Currency", name = "Soft", amount = 375}
	},
	[5] = {
		{type = "Currency", name = "Hard", amount = 40}
	},
	[6] = {
		{type = "Lootbox", name = "rare", amount = 1}
	},
	[7] = {
		{type = "Currency", name = "Soft", amount = 450},
		{type = "Lootbox", name = "epic", amount = 1}
	}
}

-- Helper function to get current day as Unix timestamp (start of day)
local function GetCurrentDayTimestamp()
	local now = os.time()
	-- Get start of day (midnight) in UTC
	-- This ensures consistent day boundaries regardless of timezone
	local daySeconds = 86400 -- 24 hours in seconds
	local dayStart = math.floor(now / daySeconds) * daySeconds
	return dayStart
end

-- Helper function to check if a timestamp is from a different day
local function IsDifferentDay(timestamp1, timestamp2)
	local day1 = math.floor(timestamp1 / 86400)
	local day2 = math.floor(timestamp2 / 86400)
	return day1 ~= day2
end

-- Error codes
DailyService.ErrorCodes = {
	INVALID_REWARD_INDEX = "INVALID_REWARD_INDEX",
	REWARD_ALREADY_CLAIMED = "REWARD_ALREADY_CLAIMED",
	REWARD_NOT_AVAILABLE = "REWARD_NOT_AVAILABLE",
	STREAK_NOT_READY = "STREAK_NOT_READY",
	INTERNAL = "INTERNAL"
}

-- Get rewards configuration
function DailyService.GetDailyRewardsConfig()
	return REWARDS_CONFIG
end

-- Get current daily data for a player
function DailyService.GetDailyData(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	if not profile then
		return nil
	end
	
	local daily = profile.daily or {
		streak = 0,
		lastLogin = 0
	}
	
	local currentDay = GetCurrentDayTimestamp()
	local lastLoginDay = daily.lastLogin
	
	-- Check if it's a new day and update streak if needed
	local streak = daily.streak
	local lastLogin = daily.lastLogin
	
	-- If last login was today, streak is valid
	-- If last login was yesterday, increment streak
	-- If last login was more than 1 day ago, reset streak
	if lastLoginDay > 0 then
		local daysSinceLastLogin = math.floor((currentDay - lastLoginDay) / 86400)
		if daysSinceLastLogin == 0 then
			-- Same day, streak is valid
		elseif daysSinceLastLogin == 1 then
			-- Yesterday, streak should increment (but we don't modify here, only in ClaimDailyReward)
		else
			-- More than 1 day ago, streak should reset
			streak = 0
		end
	end
	
	-- Determine current reward day
	-- The current day should be based on what reward was last claimed, not on what's next
	-- If streak is 7, it means we just completed day 7, so current day is still 7 (until next day)
	-- If streak is 1-6, it means we're on that day
	-- If streak is 0 and lastLogin is today, it means we haven't claimed yet today
	local currentRewardDay = 1
	
	-- Check if reward for current day is already claimed
	local isClaimed = false
	if not IsDifferentDay(lastLoginDay, currentDay) and lastLoginDay > 0 then
		-- If last login was today, check if we've already claimed
		-- We consider the reward claimed if lastLogin was set today and streak indicates we already claimed
		-- Note: streak can be 1-7 (day number) or 7 (just completed day 7)
		-- If streak is 0 and lastLogin is today, it means first login today (not claimed yet)
		-- If streak > 0 and lastLogin is today, it means we already claimed today's reward
		isClaimed = (streak > 0)
		
		-- If reward is claimed today, current day is the day we claimed (streak value)
		-- If streak is 7, we're on day 7
		-- If streak is 1-6, we're on that day
		if isClaimed then
			if streak == 7 then
				currentRewardDay = 7
			elseif streak >= 1 and streak <= 6 then
				currentRewardDay = streak
			end
		else
			-- Not claimed yet today - show the day we should claim
			-- If streak is 0, it's day 1
			-- If streak is 1-6, next day is streak + 1
			if streak == 0 then
				currentRewardDay = 1
			elseif streak >= 1 and streak <= 6 then
				currentRewardDay = streak + 1
			elseif streak == 7 then
				-- After completing day 7, next day is day 1
				currentRewardDay = 1
			end
		end
	else
		-- Different day or first login - determine next reward day
		if streak == 7 then
			-- After completing day 7, next day is day 1
			currentRewardDay = 1
		elseif streak >= 0 and streak < 7 then
			-- Normal progression: day = streak + 1
			currentRewardDay = streak + 1
		end
	end
	
	return {
		streak = streak,
		lastLogin = lastLogin,
		currentDay = currentRewardDay,
		isClaimed = isClaimed,
		rewardsConfig = REWARDS_CONFIG
	}
end

-- Check if reward index is valid
local function IsValidRewardIndex(rewardIndex)
	return type(rewardIndex) == "number" and rewardIndex >= 1 and rewardIndex <= 7
end

-- Grant lootbox rewards (called after successful profile update)
local function GrantLootboxRewards(userId, rarity)
	local lootboxResult = LootboxService.OpenShopLootbox(userId, rarity, os.time())
	if not lootboxResult or not lootboxResult.ok then
		warn("[DailyService] Failed to open lootbox: " .. tostring(rarity) .. " for user " .. tostring(userId))
		return nil
	end
	return lootboxResult.rewards
end

-- Claim daily reward
function DailyService.ClaimDailyReward(userId, rewardIndex)
	-- Validate reward index
	if not IsValidRewardIndex(rewardIndex) then
		return { ok = false, error = DailyService.ErrorCodes.INVALID_REWARD_INDEX }
	end
	
	local currentDay = GetCurrentDayTimestamp()
	local lootboxesToGrant = {}
	
	local success, result = ProfileManager.UpdateProfile(userId, function(profile)
		-- Initialize daily if missing
		if not profile.daily then
			profile.daily = {
				streak = 0,
				lastLogin = 0
			}
		end
		
		local daily = profile.daily
		local lastLoginDay = daily.lastLogin
		
		-- Calculate expected streak based on last login
		local expectedStreak = daily.streak
		local wasDay7 = (daily.streak == 7)
		
		if lastLoginDay > 0 then
			local daysSinceLastLogin = math.floor((currentDay - lastLoginDay) / 86400)
			if daysSinceLastLogin == 1 then
				-- Yesterday - increment streak, but if it was day 7, reset to 0
				if wasDay7 then
					expectedStreak = 0 -- Reset to 0 after completing day 7
				else
					expectedStreak = daily.streak + 1
				end
			elseif daysSinceLastLogin > 1 then
				-- More than 1 day ago - reset streak
				expectedStreak = 0
			end
			-- daysSinceLastLogin == 0 means same day (already logged in today)
		else
			-- First time login
			expectedStreak = 0
		end
		
		-- Normalize streak (0-6, cycles after 7)
		-- Note: streak of 7 is only temporary, gets reset to 0 after claiming day 7
		if expectedStreak > 7 then
			expectedStreak = 0 -- Safety check
		end
		
		-- Check if reward is already claimed today
		if not IsDifferentDay(lastLoginDay, currentDay) and daily.streak > 0 then
			profile._dailyResult = { ok = false, error = DailyService.ErrorCodes.REWARD_ALREADY_CLAIMED }
			return profile
		end
		
		-- Calculate expected reward day (streak + 1)
		local expectedRewardDay = expectedStreak + 1
		
		-- Check if the requested reward index matches expected day
		if rewardIndex ~= expectedRewardDay then
			profile._dailyResult = { ok = false, error = DailyService.ErrorCodes.REWARD_NOT_AVAILABLE }
			return profile
		end
		
		-- Get reward config
		local rewardConfig = REWARDS_CONFIG[rewardIndex]
		if not rewardConfig then
			profile._dailyResult = { ok = false, error = DailyService.ErrorCodes.INTERNAL }
			return profile
		end
		
		-- Grant currency rewards
		for _, reward in ipairs(rewardConfig) do
			if reward.type == "Currency" then
				local currencyName = string.lower(reward.name)
				if currencyName == "soft" or currencyName == "hard" then
					ProfileSchema.AddCurrency(profile, currencyName, reward.amount)
				end
			elseif reward.type == "Lootbox" then
				-- Collect lootbox for granting outside UpdateProfile
				local rarity = string.lower(reward.name)
				table.insert(lootboxesToGrant, rarity)
			end
		end
		
		-- Update streak and lastLogin
		-- After claiming day 7, set streak to 7 (will be used to detect it was day 7 in next claim)
		-- For days 1-6, set streak to the day number
		if expectedRewardDay == 7 then
			daily.streak = 7 -- Mark that we completed day 7
		else
			daily.streak = expectedRewardDay
		end
		daily.lastLogin = currentDay
		
		profile._dailyResult = { ok = true, rewardIndex = rewardIndex, lootboxes = lootboxesToGrant, streak = daily.streak }
		return profile
	end)
	
	-- Grant lootboxes after successful profile update
	local dailyResult = nil
	if success and result and result._dailyResult and result._dailyResult.ok then
		dailyResult = result._dailyResult
		
		-- Collect all lootbox rewards (in case there are multiple lootboxes in one day, e.g., day 7)
		local allLootboxRewards = {}
		for _, rarity in ipairs(lootboxesToGrant) do
			local lootboxRewards = GrantLootboxRewards(userId, rarity)
			if lootboxRewards then
				-- Accumulate rewards (typically one lootbox per reward, but day 7 has 2 rewards: 1 currency + 1 lootbox)
				-- For now, we store the last one (most common case is 1 lootbox per reward)
				-- In the future, could be extended to handle multiple separately
				dailyResult.rewards = lootboxRewards
				table.insert(allLootboxRewards, {rarity = rarity, rewards = lootboxRewards})
			else
				Logger.debug("DailyService: Failed to grant lootbox %s for reward %d (user %d)", 
					rarity, rewardIndex, userId)
			end
		end
		
		-- Store all lootbox rewards for debugging (if multiple)
		if #allLootboxRewards > 1 then
			Logger.debug("DailyService: Granted %d lootboxes for reward %d (user %d)", 
				#allLootboxRewards, rewardIndex, userId)
		end
	end
	
	if not success then
		return { ok = false, error = DailyService.ErrorCodes.INTERNAL }
	end
	
	-- Return result (excluding internal lootboxes array)
	dailyResult = dailyResult or { ok = false, error = DailyService.ErrorCodes.INTERNAL }
	if dailyResult.ok then
		dailyResult.lootboxes = nil
	end
	
	return dailyResult
end

-- Track player login (call when player joins)
function DailyService.TrackPlayerLogin(userId)
	local currentDay = GetCurrentDayTimestamp()
	
	-- Update lastLogin timestamp (but don't modify streak here, only in ClaimDailyReward)
	local success, _ = ProfileManager.UpdateProfile(userId, function(profile)
		if not profile.daily then
			profile.daily = {
				streak = 0,
				lastLogin = 0
			}
		end
		
		-- Only update lastLogin if it's a different day (to avoid overwriting if already updated)
		if IsDifferentDay(profile.daily.lastLogin, currentDay) then
			-- Check if streak should be reset or incremented
			local daysSinceLastLogin = 0
			if profile.daily.lastLogin > 0 then
				daysSinceLastLogin = math.floor((currentDay - profile.daily.lastLogin) / 86400)
			end
			
			if daysSinceLastLogin > 1 then
				-- More than 1 day ago - reset streak
				profile.daily.streak = 0
			elseif daysSinceLastLogin == 1 then
				-- Yesterday - streak will be incremented when claiming
				-- Don't modify streak here
			end
			-- If daysSinceLastLogin == 0, it's the same day, don't update
			
			-- Update lastLogin to current day
			profile.daily.lastLogin = currentDay
		end
		
		return profile
	end)
	
	return success
end

return DailyService

