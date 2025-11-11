local FollowRewardService = {}

local HttpService = game:GetService("HttpService")
local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)
local LootboxService = require(script.Parent.LootboxService)
local BoxTypes = require(game.ReplicatedStorage.Modules.Loot.BoxTypes)

local universeId = game.GameId

local FOLLOW_CHECK_URL_TEMPLATE = "https://games.roblox.com/v1/games/%d/favorites/users/%d"

local function checkGameFollowed(userId)
	if not HttpService.HttpEnabled then
		warn("[FollowRewardService] HttpService.HttpEnabled is false")
		return false, "HTTP_DISABLED"
	end

	local url = string.format(FOLLOW_CHECK_URL_TEMPLATE, universeId, userId)
	local success, response = pcall(function()
		return HttpService:GetAsync(url)
	end)

	if not success then
		return false, "HTTP_ERROR"
	end

	local decoded = nil
	local ok, decodeErr = pcall(function()
		decoded = HttpService:JSONDecode(response)
	end)
	if not ok then
		return false, "JSON_ERROR"
	end

	if decoded then
		if decoded.isFavorited ~= nil then
			return decoded.isFavorited == true, nil
		end
		if decoded.isFollowing ~= nil then
			return decoded.isFollowing == true, nil
		end
		if decoded.isFavorite ~= nil then
			return decoded.isFavorite == true, nil
		end
	end

	return false, nil
end

function FollowRewardService.GrantFollowReward(player)
	if not player or not player.UserId then
		return { ok = false, reason = "INVALID_PLAYER" }
	end

	local userId = player.UserId
	local isFollowing, followReason = checkGameFollowed(userId)

	if not isFollowing then
		return { ok = false, reason = followReason or "NOT_FOLLOWING" }
	end

	local serverNow = os.time()
	local success, result = ProfileManager.UpdateProfile(userId, function(profile)
		profile.followRewardClaimed = profile.followRewardClaimed or false

		if profile.followRewardClaimed then
			profile._followReward = { ok = false, error = "ALREADY_CLAIMED" }
			return profile
		end

		profile.followRewardClaimed = true
		profile._followReward = { ok = true }
		return profile
	end)

	if not success then
		return { ok = false, reason = "INTERNAL" }
	end

	local followResult = result._followReward or { ok = false, error = "INTERNAL" }

	if not followResult.ok then
		return { ok = false, reason = followResult.error }
	end

	local rewardResult = LootboxService.OpenShopLootbox(userId, BoxTypes.BoxRarity.UNCOMMON, serverNow)

	if not rewardResult.ok then
		ProfileManager.UpdateProfile(userId, function(profile)
			profile.followRewardClaimed = false
			return profile
		end)
		return { ok = false, reason = rewardResult.error or "INTERNAL" }
	end

	return { ok = true, rewards = rewardResult.rewards }
end

return FollowRewardService

