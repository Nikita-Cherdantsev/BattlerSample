--[[
	Playtime Service
	
	Server-side operations for playtime reward management.
	All operations use atomic UpdateAsync for data consistency.
]]

local PlaytimeService = {}

-- Services
local Players = game:GetService("Players")

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

local playerConnectionTimes = {}
local playerRewardAvailability = {}
local playerRewardTimers = {}

local RemoteEvents = nil
local ProfileSnapshotService = nil

local function GetNotificationModules()
	if not RemoteEvents then
		RemoteEvents = require(game.ServerScriptService.Network.RemoteEvents)
		ProfileSnapshotService = require(game.ServerScriptService.Services.ProfileSnapshotService)
	end
	return RemoteEvents, ProfileSnapshotService
end

PlaytimeService.ErrorCodes = {
	INVALID_REWARD_INDEX = "INVALID_REWARD_INDEX",
	REWARD_ALREADY_CLAIMED = "REWARD_ALREADY_CLAIMED",
	REWARD_NOT_AVAILABLE = "REWARD_NOT_AVAILABLE",
	INTERNAL = "INTERNAL"
}

local function CalculateCurrentTotalTime(playtime, userId)
	local currentTotalTime = playtime.totalTime
	local connectionTime = playerConnectionTimes[userId]
	if connectionTime then
		local sessionTime = os.time() - connectionTime
		currentTotalTime = playtime.totalTime + sessionTime
	end
	return currentTotalTime, connectionTime
end

local function IsRewardClaimed(claimedRewards, rewardIndex)
	for _, claimedIndex in ipairs(claimedRewards) do
		if claimedIndex == rewardIndex then
			return true
		end
	end
	return false
end

function PlaytimeService.GetPlaytimeRewardsConfig()
	return REWARDS_CONFIG
end

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
	
	local currentTotalTime, _ = CalculateCurrentTotalTime(playtime, userId)
	
	local nextRewardTimeSeconds = nil
	local currentMinutes = math.floor(currentTotalTime / 60)
	local hasAvailableReward = false
	
	for i = 1, #REWARDS_CONFIG.thresholds do
		local threshold = REWARDS_CONFIG.thresholds[i]
		if threshold and not IsRewardClaimed(playtime.claimedRewards or {}, i) then
			if currentMinutes >= threshold then
				hasAvailableReward = true
			else
				local rewardTimeSeconds = threshold * 60
				local timeUntilReward = rewardTimeSeconds - currentTotalTime
				
				if timeUntilReward > 0 and (not nextRewardTimeSeconds or timeUntilReward < nextRewardTimeSeconds) then
					nextRewardTimeSeconds = timeUntilReward
				end
			end
		end
	end
	
	return {
		totalTime = currentTotalTime,
		claimedRewards = playtime.claimedRewards or {},
		rewardsConfig = REWARDS_CONFIG,
		nextRewardTimeSeconds = nextRewardTimeSeconds,
		hasAvailableReward = hasAvailableReward
	}
end

local function IsValidRewardIndex(rewardIndex)
	return type(rewardIndex) == "number" and rewardIndex >= 1 and rewardIndex <= #REWARDS_CONFIG.thresholds
end

local function IsRewardAvailable(totalTime, rewardIndex)
	local threshold = REWARDS_CONFIG.thresholds[rewardIndex]
	if not threshold then
		return false
	end
	
	local currentMinutes = math.floor(totalTime / 60)
	return currentMinutes >= threshold
end

local function GrantLootboxRewards(userId, rarity)
	local lootboxResult = LootboxService.OpenShopLootbox(userId, rarity, os.time())
	if not lootboxResult or not lootboxResult.ok then
		warn("[PlaytimeService] Failed to open lootbox: " .. tostring(rarity) .. " for user " .. tostring(userId))
		return nil
	end
	return lootboxResult.rewards
end

local function CancelPlayerTimers(userId)
	local timers = playerRewardTimers[userId]
	if not timers then
		return
	end
	
	for rewardIndex, timer in pairs(timers) do
		if timer then
			task.cancel(timer)
		end
	end
	
	playerRewardTimers[userId] = nil
end

local function NotifyPlayerRewardAvailability(player, userId)
	local RemoteEvents, ProfileSnapshotService = GetNotificationModules()
	
	local snapshot = ProfileSnapshotService.GetSnapshot(player, {
		includePlaytime = true
	})
	
	if snapshot then
		RemoteEvents.SendProfileUpdate(player, snapshot)
	end
end

local function SetupPlayerRewardTimers(player, userId)
	CancelPlayerTimers(userId)
	
	local playtimeData = PlaytimeService.GetPlaytimeData(userId)
	if not playtimeData then
		return
	end
	
	local profile = ProfileManager.GetCachedProfile(userId)
	if not profile then
		return
	end
	
	local playtime = profile.playtime or {
		totalTime = 0,
		lastSyncTime = os.time(),
		claimedRewards = {}
	}
	
	local currentTotalTime, _ = CalculateCurrentTotalTime(playtime, userId)
	local currentMinutes = math.floor(currentTotalTime / 60)
	
	local nextRewardIndex = nil
	local nextRewardTimeSeconds = nil
	
	for i = 1, #REWARDS_CONFIG.thresholds do
		local threshold = REWARDS_CONFIG.thresholds[i]
		if threshold and not IsRewardClaimed(playtime.claimedRewards or {}, i) then
			local rewardTimeSeconds = threshold * 60
			local timeUntilReward = rewardTimeSeconds - currentTotalTime
			
			if currentMinutes >= threshold then
				local currentAvailability = playerRewardAvailability[userId]
				if not currentAvailability or not currentAvailability.hasAvailableReward then
					playerRewardAvailability[userId] = {
						hasAvailableReward = true,
						nextRewardTimeSeconds = nil
					}
					NotifyPlayerRewardAvailability(player, userId)
				end
			elseif timeUntilReward > 0 then
				if not nextRewardTimeSeconds or timeUntilReward < nextRewardTimeSeconds then
					nextRewardIndex = i
					nextRewardTimeSeconds = timeUntilReward
				end
			end
		end
	end
	
	if nextRewardIndex and nextRewardTimeSeconds then
		if not playerRewardTimers[userId] then
			playerRewardTimers[userId] = {}
		end
		
		local waitTime = math.max(0.5, nextRewardTimeSeconds + 0.5)
		
		playerRewardAvailability[userId] = {
			hasAvailableReward = false,
			nextRewardTimeSeconds = nextRewardTimeSeconds
		}
		
		local timer = task.spawn(function()
			task.wait(waitTime)
			
			local currentPlayer = Players:GetPlayerByUserId(userId)
			if not currentPlayer then
				return
			end
			
			local playtimeDataNow = PlaytimeService.GetPlaytimeData(userId)
			if not playtimeDataNow then
				return
			end
			
			playerRewardAvailability[userId] = {
				hasAvailableReward = playtimeDataNow.hasAvailableReward,
				nextRewardTimeSeconds = playtimeDataNow.nextRewardTimeSeconds
			}
			
			NotifyPlayerRewardAvailability(currentPlayer, userId)
			
			if playerRewardTimers[userId] and playerRewardTimers[userId][nextRewardIndex] then
				playerRewardTimers[userId][nextRewardIndex] = nil
			end
			
			SetupPlayerRewardTimers(currentPlayer, userId)
		end)
		
		playerRewardTimers[userId][nextRewardIndex] = timer
	end
end

function PlaytimeService.ClaimPlaytimeReward(userId, rewardIndex)
	if not IsValidRewardIndex(rewardIndex) then
		return { ok = false, error = PlaytimeService.ErrorCodes.INVALID_REWARD_INDEX }
	end
	
	local lootboxesToGrant = {}
	
	local success, result = ProfileManager.UpdateProfile(userId, function(profile)
		if not profile.playtime then
			profile.playtime = {
				totalTime = 0,
				lastSyncTime = os.time(),
				claimedRewards = {}
			}
		end
		
		local playtime = profile.playtime
		
		local currentTotalTime, connectionTime = CalculateCurrentTotalTime(playtime, userId)
		
		if IsRewardClaimed(playtime.claimedRewards, rewardIndex) then
			profile._playtimeResult = { ok = false, error = PlaytimeService.ErrorCodes.REWARD_ALREADY_CLAIMED }
			return profile
		end
		
		if not IsRewardAvailable(currentTotalTime, rewardIndex) then
			profile._playtimeResult = { ok = false, error = PlaytimeService.ErrorCodes.REWARD_NOT_AVAILABLE }
			return profile
		end
		
		if connectionTime then
			local sessionTime = os.time() - connectionTime
			playtime.totalTime = playtime.totalTime + sessionTime
			playtime.lastSyncTime = os.time()
			playerConnectionTimes[userId] = os.time()
		end
		
		local rewardConfig = REWARDS_CONFIG.rewards[rewardIndex]
		if not rewardConfig then
			profile._playtimeResult = { ok = false, error = PlaytimeService.ErrorCodes.INTERNAL }
			return profile
		end
		
		for _, reward in ipairs(rewardConfig) do
			if reward.type == "Currency" then
				local currencyName = string.lower(reward.name)
				if currencyName == "soft" or currencyName == "hard" then
					ProfileSchema.AddCurrency(profile, currencyName, reward.amount)
				end
			elseif reward.type == "Lootbox" then
				local rarity = string.lower(reward.name)
				table.insert(lootboxesToGrant, rarity)
			end
		end
		
		table.insert(playtime.claimedRewards, rewardIndex)
		
		if #playtime.claimedRewards == 7 then
			playtime.totalTime = 0
			playtime.claimedRewards = {}
			playtime.lastSyncTime = os.time()
			playerConnectionTimes[userId] = os.time()
		end
		
		profile._playtimeResult = { ok = true, rewardIndex = rewardIndex, lootboxes = lootboxesToGrant }
		return profile
	end)
	
	local playtimeResult = nil
	if success and result and result._playtimeResult and result._playtimeResult.ok then
		playtimeResult = result._playtimeResult
		
		for _, rarity in ipairs(lootboxesToGrant) do
			local lootboxRewards = GrantLootboxRewards(userId, rarity)
			if lootboxRewards then
				playtimeResult.rewards = lootboxRewards
			else
				Logger.debug("PlaytimeService: Failed to grant lootbox %s for reward %d (user %d)", 
					rarity, rewardIndex, userId)
			end
		end
	end
	
	if not success then
		return { ok = false, error = PlaytimeService.ErrorCodes.INTERNAL }
	end
	
	local player = Players:GetPlayerByUserId(userId)
	if player and playtimeResult and playtimeResult.ok then
		SetupPlayerRewardTimers(player, userId)
	end
	
	playtimeResult = playtimeResult or { ok = false, error = PlaytimeService.ErrorCodes.INTERNAL }
	if playtimeResult.ok then
		playtimeResult.lootboxes = nil
	end
	
	return playtimeResult
end

function PlaytimeService.TrackPlayerConnection(userId)
	playerConnectionTimes[userId] = os.time()
	
	local player = Players:GetPlayerByUserId(userId)
	if player then
		SetupPlayerRewardTimers(player, userId)
	end
end

function PlaytimeService.StopTrackingPlayerConnection(userId)
	local connectionTime = playerConnectionTimes[userId]
	if not connectionTime then
		return
	end
	
	CancelPlayerTimers(userId)
	playerRewardAvailability[userId] = nil
	
	local sessionTime = os.time() - connectionTime
	playerConnectionTimes[userId] = nil
	
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

local isInitialized = false

function PlaytimeService.Init()
	if isInitialized then
		print("⚠️ PlaytimeService already initialized, skipping")
		return
	end
	
	isInitialized = true
	
	Players.PlayerAdded:Connect(function(player)
		PlaytimeService.TrackPlayerConnection(player.UserId)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		PlaytimeService.StopTrackingPlayerConnection(player.UserId)
	end)
	
	for _, player in ipairs(Players:GetPlayers()) do
		PlaytimeService.TrackPlayerConnection(player.UserId)
	end
	
	print("✅ PlaytimeService initialized")
end

function PlaytimeService.CheckAndNotifyPlayer(player)
	SetupPlayerRewardTimers(player, player.UserId)
	return true
end

return PlaytimeService

