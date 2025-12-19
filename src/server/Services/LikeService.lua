--[[
	Like Service
	
	Server-side operations for checking game votes and favorites.
]]

local LikeService = {}

-- Services
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)

-- Constants
local UNIVERSE_ID = 9166746635
local REWARD_CHECK_TIME_WINDOW = 120  -- 2 minutes in seconds

-- Reward configuration
local REWARD_CONFIG = {
	cardId = "card_100",  -- Card ID from CardCatalog
	amount = 1            -- Number of cards to grant
}

-- Get votes for the game
local function getVotes(universeId)
	local response = HttpService:GetAsync(
		`https://games.roproxy.com/v1/games/{universeId}/votes`
	)
	return HttpService:JSONDecode(response)
end

-- Check if game is in user's favorites
local function isInFavorites(userId, universeId)
	local response = HttpService:GetAsync(
		`https://games.roproxy.com/v2/users/{userId}/favorite/games`
	)
	local data = HttpService:JSONDecode(response)

	for _, gameData in ipairs(data.data or {}) do
		if gameData.id == universeId then
			return true
		end
	end

	return false
end

-- Check game info (votes and favorites)
function LikeService.CheckGameInfo(player)
	local userId = player.UserId

	-- Get gamevotes
	local okVotes, votesOrError = pcall(getVotes, UNIVERSE_ID)
	if okVotes then
		print("👍 Upvotes:", votesOrError.upVotes)
		print("👎 Downvotes:", votesOrError.downVotes)
	else
		warn("Error [VOTES]:", votesOrError)
	end

	-- Check favorites
	local okFav, favOrError = pcall(isInFavorites, userId, UNIVERSE_ID)
	if okFav then
		print("In favorites:", favOrError)
	else
		warn("Error [FAVORITES]:", favOrError)
	end
	
	return {
		ok = true,
		votes = okVotes and votesOrError or nil,
		inFavorites = okFav and favOrError or nil,
		votesError = okVotes and nil or tostring(votesOrError),
		favoritesError = okFav and nil or tostring(favOrError)
	}
end

-- Get reward configuration
function LikeService.GetRewardConfig()
	return REWARD_CONFIG
end

-- Get reward check time window constant
function LikeService.GetRewardCheckTimeWindow()
	return REWARD_CHECK_TIME_WINDOW
end

-- Check if player is eligible for like reward
function LikeService.CheckRewardEligibility(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	if not profile then
		profile = ProfileManager.LoadProfile(userId)
	end
	
	if not profile then
		return { ok = false, eligible = false, reason = "PROFILE_NOT_FOUND" }
	end
	
	-- Initialize likeReward if missing
	if not profile.likeReward then
		profile.likeReward = {
			lastRequest = nil,
			claimed = false,
			eligible = false
		}
	end
	
	-- If already claimed, not eligible
	if profile.likeReward.claimed then
		return { ok = true, eligible = false, reason = "ALREADY_CLAIMED" }
	end
	
	-- Calculate eligibility based on old lastRequest and current lastLoginAt
	local eligible = false
	local reason = "NO_REQUEST"
	
	-- If no lastRequest, not eligible yet
	if not profile.likeReward.lastRequest then
		eligible = false
		reason = "NO_REQUEST"
	else
		-- Check if lastRequest (from previous session) was within time window of current lastLoginAt
		-- This means player opened window, liked game, and restarted within 2 minutes
		local currentTime = os.time()
		local timeSinceLogin = currentTime - profile.lastLoginAt
		local timeSinceRequest = currentTime - profile.likeReward.lastRequest
		
		-- Check if request was made within 2 minutes of login
		local timeWindowValid = timeSinceRequest <= REWARD_CHECK_TIME_WINDOW and timeSinceLogin <= REWARD_CHECK_TIME_WINDOW
		
		if timeWindowValid then
			-- Also check if game is in player's favorites
			local okFav, inFavorites = pcall(isInFavorites, userId, UNIVERSE_ID)
			if okFav and inFavorites then
				eligible = true
			else
				eligible = false
				reason = "NOT_IN_FAVORITES"
			end
		else
			eligible = false
			reason = "TIME_WINDOW_EXPIRED"
		end
	end
	
	-- Cache the result in profile
	profile.likeReward.eligible = eligible
	
	-- Save cached eligibility to profile
	ProfileManager.UpdateProfile(userId, function(p)
		if not p.likeReward then
			p.likeReward = {
				lastRequest = nil,
				claimed = false,
				eligible = false
			}
		end
		p.likeReward.eligible = eligible
		return p
	end)
	
	return { ok = true, eligible = eligible, reason = eligible and nil or reason }
end

-- Record window open timestamp (for next session check)
function LikeService.RecordWindowOpen(userId)
	local success, updatedProfile = ProfileManager.UpdateProfile(userId, function(profile)
		if not profile.likeReward then
			profile.likeReward = {
				lastRequest = nil,
				claimed = false,
				eligible = false
			}
		end
		
		-- Only update lastRequest if reward not claimed
		-- This lastRequest will be used in NEXT session to check eligibility
		if not profile.likeReward.claimed then
			profile.likeReward.lastRequest = os.time()
			-- Do NOT recalculate eligible here - it's checked only at game start
		end
		
		return profile
	end)
	
	return success
end

-- Claim like reward (uses cached eligibility from game start)
function LikeService.ClaimReward(userId)
	local ProfileSchema = require(script.Parent.Parent.Persistence.ProfileSchema)
	
	-- Get profile
	local profile = ProfileManager.GetCachedProfile(userId)
	if not profile then
		profile = ProfileManager.LoadProfile(userId)
	end
	
	if not profile then
		return { ok = false, error = "PROFILE_NOT_FOUND" }
	end
	
	-- Initialize likeReward if missing
	if not profile.likeReward then
		profile.likeReward = {
			lastRequest = nil,
			claimed = false,
			eligible = false
		}
	end
	
	-- Use cached eligibility (checked at game start, no need to check again)
	if not profile.likeReward.eligible then
		return { ok = false, error = "NOT_ELIGIBLE" }
	end
	
	-- If already claimed, not eligible
	if profile.likeReward.claimed then
		return { ok = false, error = "ALREADY_CLAIMED" }
	end
	
	-- Grant reward and mark as claimed
	local success, updatedProfile = ProfileManager.UpdateProfile(userId, function(profile)
		if not profile.likeReward then
			profile.likeReward = {
				lastRequest = nil,
				claimed = false,
				eligible = false
			}
		end
		
		-- Mark as claimed and clear eligibility
		profile.likeReward.claimed = true
		profile.likeReward.eligible = false
		
		-- Grant card reward
		ProfileSchema.AddCardsToCollection(profile, REWARD_CONFIG.cardId, REWARD_CONFIG.amount)
		
		return profile
	end)
	
	if success then
		return { ok = true, cardId = REWARD_CONFIG.cardId, amount = REWARD_CONFIG.amount }
	else
		return { ok = false, error = "UPDATE_FAILED" }
	end
end

return LikeService

