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
		{type = "Lootbox", name = "uncommon", amount = 1}
	},
	[2] = {
		{type = "Currency", name = "Hard", amount = 20}
	},
	[3] = {
		{type = "Lootbox", name = "rare", amount = 1}
	},
	[4] = {
		{type = "Currency", name = "Hard", amount = 40}
	},
	[5] = {
		{type = "Currency", name = "Hard", amount = 40}
	},
	[6] = {
		{type = "Lootbox", name = "epic", amount = 1}
	},
	[7] = {
		{type = "Currency", name = "Hard", amount = 100},
		{type = "Lootbox", name = "legendary", amount = 1}
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
	-- Logic matches the provided code: canClaimBonus equivalent
	local streak = daily.streak
	local lastLogin = daily.lastLogin
	
	-- Calculate days since last login
	local daysSinceLastLogin = 0
	if lastLoginDay > 0 then
		daysSinceLastLogin = math.floor((currentDay - lastLoginDay) / 86400)
	end
	
	-- Check if reward for current day is already claimed
	-- According to provided code: daysSince == 0 means already claimed today
	local isClaimed = false
	if daysSinceLastLogin == 0 and lastLoginDay > 0 then
		-- Same day as last login - already claimed today
		isClaimed = true
	end
	
	-- Determine current reward day based on streak
	-- If claimed today, show the day we're on (streak value)
	-- If not claimed, show the next day to claim (streak + 1, wrapping from 7 to 1)
	local currentRewardDay = 1
	if isClaimed then
		-- Already claimed today - show current day (streak value)
		if streak >= 1 and streak <= 7 then
			currentRewardDay = streak
		else
			currentRewardDay = 1
		end
	else
		-- Not claimed yet - show next day to claim
		if streak == 0 then
			-- First time or reset - day 1
			currentRewardDay = 1
		elseif streak >= 1 and streak < 7 then
			-- Normal progression: next day
			currentRewardDay = streak + 1
		elseif streak == 7 then
			-- After completing day 7, wrap to day 1
			currentRewardDay = 1
		else
			-- Safety fallback
			currentRewardDay = 1
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
		
		-- Check if reward is already claimed today (equivalent to canClaimBonus check)
		-- According to provided code: daysSince == 0 means already claimed today
		if lastLoginDay > 0 then
			local daysSinceLastLogin = math.floor((currentDay - lastLoginDay) / 86400)
			if daysSinceLastLogin == 0 then
				-- Same day - already claimed today, cannot claim again
				profile._dailyResult = { ok = false, error = DailyService.ErrorCodes.REWARD_ALREADY_CLAIMED }
				return profile
			end
		end
		
		-- Calculate new streak based on last login
		-- Logic matches provided code: if daysMissed > 1, reset streak to 0
		local streak = daily.streak
		local daysMissed = 0
		if lastLoginDay > 0 then
			daysMissed = math.floor((currentDay - lastLoginDay) / 86400)
		end
		
		-- Reset streak if more than 1 day missed
		if daysMissed > 1 then
			streak = 0 -- reset
		end
		
		-- Increment streak (matches provided code: streak = streak + 1)
		streak = streak + 1
		
		-- Wrap streak if more than 7 (matches provided code: if streak > 7 then streak = 1)
		if streak > 7 then
			streak = 1
		end
		
		-- Calculate expected reward day (should match the streak we're about to set)
		local expectedRewardDay = streak
		
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
		
		-- Update streak and lastLogin (matches provided code)
		daily.streak = streak
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
-- Note: This only initializes daily data if missing. 
-- lastLogin is updated only when claiming rewards, not on login.
-- This matches the provided code where lastLogin is only set on claim.
function DailyService.TrackPlayerLogin(userId)
	-- Initialize daily data if missing (but don't modify lastLogin or streak)
	local success, _ = ProfileManager.UpdateProfile(userId, function(profile)
		if not profile.daily then
			profile.daily = {
				streak = 0,
				lastLogin = 0
			}
		end
		-- Don't update lastLogin here - it should only be updated when claiming rewards
		-- This ensures that isClaimed logic works correctly
		return profile
	end)
	
	return success
end

return DailyService

