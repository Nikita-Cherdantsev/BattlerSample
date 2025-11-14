local FollowRewardService = {}

local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)
local LootboxService = require(script.Parent.LootboxService)
local BoxTypes = require(game.ReplicatedStorage.Modules.Loot.BoxTypes)

-- Configure the Group ID of the community/group that players should join
local COMMUNITY_GROUP_ID = 469178835

local function checkPlayerInGroup(player)
	if not player then
		return false, "INVALID_PLAYER"
	end

	if not COMMUNITY_GROUP_ID or COMMUNITY_GROUP_ID == 0 then
		return false, "GROUP_ID_NOT_CONFIGURED"
	end

	-- Check if player is in the group
	local isInGroup = player:IsInGroup(COMMUNITY_GROUP_ID)
	if not isInGroup then
		return false, "NOT_IN_GROUP"
	end

	return true, nil
end

function FollowRewardService.GrantFollowReward(player)
	if not player or not player.UserId then
		return { ok = false, reason = "INVALID_PLAYER" }
	end

	local userId = player.UserId

	-- First check if player is in the community group (no profile access needed)
	local isInGroup, groupReason = checkPlayerInGroup(player)
	if not isInGroup then
		return { ok = false, reason = groupReason or "NOT_IN_GROUP" }
	end

	-- Check if already claimed using profile (read-only check, LoadProfile doesn't save)
	local profile = ProfileManager.LoadProfile(userId)
	if profile and profile.followRewardClaimed == true then
		return { ok = false, reason = "ALREADY_CLAIMED" }
	end

	-- Only update profile when we're actually granting the reward
	local serverNow = os.time()
	local success, updatedProfile = ProfileManager.UpdateProfile(userId, function(profile)
		-- Double-check in case it was claimed between cache check and update
		if profile.followRewardClaimed == true then
			return profile -- Return unchanged profile
		end

		-- Set the flag to prevent double-claiming
		profile.followRewardClaimed = true
		return profile
	end)

	if not success then
		return { ok = false, reason = "INTERNAL" }
	end

	-- Double-check after update (in case another request claimed it simultaneously)
	if updatedProfile.followRewardClaimed ~= true then
		-- This shouldn't happen, but handle it gracefully
		warn(string.format("[FollowRewardService] Profile update didn't set followRewardClaimed for user %d", userId))
		return { ok = false, reason = "INTERNAL" }
	end

	-- Grant the reward
	local rewardResult = LootboxService.OpenShopLootbox(userId, BoxTypes.BoxRarity.UNCOMMON, serverNow)

	if not rewardResult.ok then
		-- Rollback: unset the flag if reward grant failed
		ProfileManager.UpdateProfile(userId, function(profile)
			profile.followRewardClaimed = false
			return profile
		end)
		return { ok = false, reason = rewardResult.error or "INTERNAL" }
	end

	return { ok = true, rewards = rewardResult.rewards }
end

return FollowRewardService

