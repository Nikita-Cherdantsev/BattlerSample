--[[
	Playtime Service
	
	Server-side operations for playtime reward management.
	All operations use atomic UpdateAsync for data consistency.
]]

local PlaytimeService = {}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Modules
local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)
local ProfileSchema = require(script.Parent.Parent.Persistence.ProfileSchema)
local LootboxService = require(script.Parent.LootboxService)
local Logger = require(game.ReplicatedStorage.Modules.Logger)

-- Rewards configuration
local REWARDS_CONFIG = {
	thresholds = {3, 6, 9, 12, 15, 18, 22}, -- minutes
	rewards = {
		[1] = { 
			{type = "Currency", name = "Soft", amount = 50}
		},
		[2] = {
			{type = "Currency", name = "Hard", amount = 7}
		},
		[3] = {
			{type = "Currency", name = "Soft", amount = 150},
			{type = "Currency", name = "Hard", amount = 20}
		},
		[4] = {
			{type = "Currency", name = "Hard", amount = 35},
			{type = "Lootbox", name = "uncommon", amount = 1}
		},
		[5] = {
			{type = "Currency", name = "Soft", amount = 200}
		},
		[6] = {
			{type = "Currency", name = "Soft", amount = 250},
			{type = "Currency", name = "Hard", amount = 67},
			{type = "Lootbox", name = "rare", amount = 1}
		},
		[7] = {
			{type = "Lootbox", name = "rare", amount = 1}
		}
	}
}

-- Player connection time tracking (server-side)
local playerConnectionTimes = {} -- player -> connectionTime (os.time())

-- Error codes
PlaytimeService.ErrorCodes = {
	INVALID_REWARD_INDEX = "INVALID_REWARD_INDEX",
	REWARD_ALREADY_CLAIMED = "REWARD_ALREADY_CLAIMED",
	REWARD_NOT_AVAILABLE = "REWARD_NOT_AVAILABLE",
	INTERNAL = "INTERNAL"
}

-- Calculate current total time including session time
local function CalculateCurrentTotalTime(playtime, userId)
	local currentTotalTime = playtime.totalTime
	local connectionTime = playerConnectionTimes[userId]
	if connectionTime then
		local sessionTime = os.time() - connectionTime
		currentTotalTime = playtime.totalTime + sessionTime
	end
	return currentTotalTime, connectionTime
end

-- Get rewards configuration
function PlaytimeService.GetPlaytimeRewardsConfig()
	return REWARDS_CONFIG
end

-- Get current playtime data for a player
function PlaytimeService.GetPlaytimeData(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	if not profile then
		return nil
	end
	
	local playtime = profile.playtime or {
		totalTime = 0,
		lastSyncTime = os.time(),
		claimedRewards = {}
	}
	
	-- Calculate current total time including session time
	local currentTotalTime, _ = CalculateCurrentTotalTime(playtime, userId)
	
	return {
		totalTime = currentTotalTime,
		claimedRewards = playtime.claimedRewards or {},
		rewardsConfig = REWARDS_CONFIG
	}
end

-- Check if reward index is valid
local function IsValidRewardIndex(rewardIndex)
	return type(rewardIndex) == "number" and rewardIndex >= 1 and rewardIndex <= #REWARDS_CONFIG.thresholds
end

-- Check if reward is already claimed
local function IsRewardClaimed(claimedRewards, rewardIndex)
	for _, claimedIndex in ipairs(claimedRewards) do
		if claimedIndex == rewardIndex then
			return true
		end
	end
	return false
end

-- Check if reward is available (time threshold reached)
local function IsRewardAvailable(totalTime, rewardIndex)
	local threshold = REWARDS_CONFIG.thresholds[rewardIndex]
	if not threshold then
		return false
	end
	
	local currentMinutes = math.floor(totalTime / 60)
	return currentMinutes >= threshold
end

-- Grant lootbox rewards (called after successful profile update)
local function GrantLootboxRewards(userId, rarity)
	local lootboxResult = LootboxService.OpenShopLootbox(userId, rarity, os.time())
	if not lootboxResult or not lootboxResult.ok then
		warn("[PlaytimeService] Failed to open lootbox: " .. tostring(rarity) .. " for user " .. tostring(userId))
		return nil
	end
	return lootboxResult.rewards
end

-- Claim playtime reward
function PlaytimeService.ClaimPlaytimeReward(userId, rewardIndex)
	-- Validate reward index
	if not IsValidRewardIndex(rewardIndex) then
		return { ok = false, error = PlaytimeService.ErrorCodes.INVALID_REWARD_INDEX }
	end
	
	-- Collect lootbox rarities that need to be granted (outside of UpdateProfile)
	local lootboxesToGrant = {}
	
	local success, result = ProfileManager.UpdateProfile(userId, function(profile)
		-- Initialize playtime if missing
		if not profile.playtime then
			profile.playtime = {
				totalTime = 0,
				lastSyncTime = os.time(),
				claimedRewards = {}
			}
		end
		
		local playtime = profile.playtime
		
		-- Calculate current total time including session time
		local currentTotalTime, connectionTime = CalculateCurrentTotalTime(playtime, userId)
		
		-- Check if reward is already claimed
		if IsRewardClaimed(playtime.claimedRewards, rewardIndex) then
			profile._playtimeResult = { ok = false, error = PlaytimeService.ErrorCodes.REWARD_ALREADY_CLAIMED }
			return profile
		end
		
		-- Check if reward is available (time threshold reached)
		if not IsRewardAvailable(currentTotalTime, rewardIndex) then
			profile._playtimeResult = { ok = false, error = PlaytimeService.ErrorCodes.REWARD_NOT_AVAILABLE }
			return profile
		end
		
		-- Update totalTime with session time
		if connectionTime then
			local sessionTime = os.time() - connectionTime
			playtime.totalTime = playtime.totalTime + sessionTime
			playtime.lastSyncTime = os.time()
			playerConnectionTimes[userId] = os.time() -- Reset connection time
		end
		
		-- Get reward config
		local rewardConfig = REWARDS_CONFIG.rewards[rewardIndex]
		if not rewardConfig then
			profile._playtimeResult = { ok = false, error = PlaytimeService.ErrorCodes.INTERNAL }
			return profile
		end
		
		-- Grant currency rewards (can be done inside UpdateProfile)
		for _, reward in ipairs(rewardConfig) do
			if reward.type == "Currency" then
				local currencyName = string.lower(reward.name)
				if currencyName == "soft" or currencyName == "hard" then
					ProfileSchema.AddCurrency(profile, currencyName, reward.amount)
				end
			elseif reward.type == "Lootbox" then
				-- Collect lootbox for granting outside UpdateProfile to avoid nesting
				local rarity = string.lower(reward.name)
				table.insert(lootboxesToGrant, rarity)
			end
		end
		
		-- Mark reward as claimed
		table.insert(playtime.claimedRewards, rewardIndex)
		
		-- If this is the last reward (index 7), reset playtime and claimedRewards
		if #playtime.claimedRewards == 7 then
			playtime.totalTime = 0
			playtime.claimedRewards = {}
			playtime.lastSyncTime = os.time()
			playerConnectionTimes[userId] = os.time() -- Reset connection time
		end
		
		profile._playtimeResult = { ok = true, rewardIndex = rewardIndex, lootboxes = lootboxesToGrant }
		return profile
	end)
	
	-- Grant lootboxes after successful profile update (outside UpdateProfile to avoid nesting)
	local playtimeResult = nil
	if success and result and result._playtimeResult and result._playtimeResult.ok then
		playtimeResult = result._playtimeResult
		
		for _, rarity in ipairs(lootboxesToGrant) do
			local lootboxRewards = GrantLootboxRewards(userId, rarity)
			if lootboxRewards then
				-- Set rewards in the result (typical case: one lootbox per reward)
				playtimeResult.rewards = lootboxRewards
			else
				-- Log error but don't fail the transaction - currency rewards are already granted
				Logger.debug("PlaytimeService: Failed to grant lootbox %s for reward %d (user %d)", 
					rarity, rewardIndex, userId)
			end
		end
	end
	
	if not success then
		return { ok = false, error = PlaytimeService.ErrorCodes.INTERNAL }
	end
	
	-- Return result (excluding internal lootboxes array)
	playtimeResult = playtimeResult or { ok = false, error = PlaytimeService.ErrorCodes.INTERNAL }
	if playtimeResult.ok then
		-- Remove internal lootboxes array from result
		playtimeResult.lootboxes = nil
	end
	
	return playtimeResult
end

-- Track player connection time
function PlaytimeService.TrackPlayerConnection(userId)
	playerConnectionTimes[userId] = os.time()
end

-- Stop tracking player connection time and update profile
function PlaytimeService.StopTrackingPlayerConnection(userId)
	local connectionTime = playerConnectionTimes[userId]
	if not connectionTime then
		return
	end
	
	local sessionTime = os.time() - connectionTime
	playerConnectionTimes[userId] = nil
	
	-- Update profile with session time
	local success, _ = ProfileManager.UpdateProfile(userId, function(profile)
		if not profile.playtime then
			profile.playtime = {
				totalTime = 0,
				lastSyncTime = os.time(),
				claimedRewards = {}
			}
		end
		
		profile.playtime.totalTime = profile.playtime.totalTime + sessionTime
		profile.playtime.lastSyncTime = os.time()
		return profile
	end)
	
	return success
end

-- Initialize service
local isInitialized = false
function PlaytimeService.Init()
	-- Idempotency check
	if isInitialized then
		print("⚠️ PlaytimeService already initialized, skipping")
		return
	end
	
	isInitialized = true
	
	-- Track players on join
	Players.PlayerAdded:Connect(function(player)
		PlaytimeService.TrackPlayerConnection(player.UserId)
	end)
	
	-- Stop tracking and save on leave
	Players.PlayerRemoving:Connect(function(player)
		PlaytimeService.StopTrackingPlayerConnection(player.UserId)
	end)
	
	-- Handle players already in game
	for _, player in ipairs(Players:GetPlayers()) do
		PlaytimeService.TrackPlayerConnection(player.UserId)
	end
	
	print("✅ PlaytimeService initialized")
end

return PlaytimeService

