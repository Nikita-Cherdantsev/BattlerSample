local FollowRewardService = {}

local HttpService = game:GetService("HttpService")
local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)
local LootboxService = require(script.Parent.LootboxService)
local BoxTypes = require(game.ReplicatedStorage.Modules.Loot.BoxTypes)

local universeIdCache = nil
local universeIdFetchAttempted = false

local FOLLOW_CHECK_URL_TEMPLATE = "https://games.roblox.com/v1/games/%d/favorites/users/%d"
local FOLLOW_CHECK_URL_QUERY_TEMPLATE = "https://games.roblox.com/v1/games/%d/favorites/users?userId=%d"
local PLACE_TO_UNIVERSE_URL_TEMPLATE = "https://apis.roblox.com/universes/v1/places/%d/universe"

local function getUniverseId()
	if universeIdCache and universeIdCache ~= 0 then
		return universeIdCache
	end

	if game.GameId and game.GameId ~= 0 then
		universeIdCache = game.GameId
		return universeIdCache
	end

	if universeIdFetchAttempted then
		return universeIdCache
	end

	universeIdFetchAttempted = true

	local placeId = game.PlaceId
	if not placeId or placeId == 0 then
		return nil
	end

	if not HttpService.HttpEnabled then
		return nil
	end

	local url = string.format(PLACE_TO_UNIVERSE_URL_TEMPLATE, placeId)
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = {
				["Cache-Control"] = "no-cache"
			}
		})
	end)

	if success and response.Success then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		if ok and decoded and decoded.universeId then
			universeIdCache = decoded.universeId
		end
	end

	return universeIdCache
end

local function checkGameFollowed(userId)
	if not HttpService.HttpEnabled then
		return false, "HTTP_DISABLED"
	end

	local universeId = getUniverseId()
	if not universeId or universeId == 0 then
		return false, "UNIVERSE_ID_UNKNOWN"
	end

	local url = string.format(FOLLOW_CHECK_URL_TEMPLATE, universeId, userId)
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = {
				["Cache-Control"] = "no-cache"
			}
		})
	end)

	if not success then
		local responseMessage = tostring(response)
		warn(string.format("[FollowRewardService] HTTP request failed for %s: %s", url, responseMessage))
		if responseMessage:find("not allowed to access") then
			return false, "HTTP_FORBIDDEN"
		end
		return false, "HTTP_ERROR"
	end

	if not response.Success then
		warn(string.format("[FollowRewardService] HTTP request failed (status %s) body=%s", tostring(response.StatusCode), tostring(response.Body)))
		local altUrl = string.format(FOLLOW_CHECK_URL_QUERY_TEMPLATE, universeId, userId)
		local altSuccess, altResponse = pcall(function()
			return HttpService:RequestAsync({
				Url = altUrl,
				Method = "GET",
				Headers = {
					["Cache-Control"] = "no-cache"
				}
			})
		end)

		if altSuccess and altResponse.Success then
			response = altResponse
		else
			if altSuccess then
				warn(string.format("[FollowRewardService] Alternate HTTP request failed (status %s) body=%s", tostring(altResponse.StatusCode), tostring(altResponse.Body)))
				if tostring(altResponse.Body):find("not allowed to access") then
					return false, "HTTP_FORBIDDEN"
				end
				return false, string.format("HTTP_ERROR_%s", tostring(altResponse.StatusCode))
			else
				local altMessage = tostring(altResponse)
				warn(string.format("[FollowRewardService] Alternate HTTP request failed for %s: %s", altUrl, altMessage))
				if altMessage:find("not allowed to access") then
					return false, "HTTP_FORBIDDEN"
				end
				return false, "HTTP_ERROR"
			end
		end
	end

	local decoded = nil
	local ok, decodeErr = pcall(function()
		decoded = HttpService:JSONDecode(response.Body)
	end)
	if not ok then
		warn(string.format("[FollowRewardService] JSON decode failed: %s", tostring(decodeErr)))
		return false, "JSON_ERROR"
	end

	if decoded then
		if decoded.isFavorited ~= nil then
			return decoded.isFavorited == true, nil
		end
		if decoded.isFavorite ~= nil then
			return decoded.isFavorite == true, nil
		end
		if decoded.isFollowing ~= nil then
			return decoded.isFollowing == true, nil
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

