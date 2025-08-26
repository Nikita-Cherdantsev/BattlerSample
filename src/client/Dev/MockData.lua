--[[
	MockData - Pure data builders for server payload simulation
	
	Provides functions to create mock server payloads that match
	the current v2 data shapes for UI development without a server.
]]

local Utilities = require(script.Parent.Parent.Utilities)
local Types = Utilities.Types
local TimeUtils = Utilities.TimeUtils

-- Use card data from Utilities
local CLIENT_CARD_DATA = Utilities.CardCatalog.GetAllCards()

local MockData = {}

-- Get valid card IDs from client card data
local function getValidCardIds()
	local cardIds = {}
	for cardId, _ in pairs(CLIENT_CARD_DATA) do
		table.insert(cardIds, cardId)
	end
	table.sort(cardIds) -- Ensure consistent ordering
	return cardIds
end

-- Create a mock profile snapshot
function MockData.makeProfileSnapshot()
	local validCardIds = getValidCardIds()
	
	-- Create a sample deck with 6 unique cards
	local deck = {}
	local usedCards = {}
	
	for i = 1, 6 do
		if i <= #validCardIds then
			table.insert(deck, validCardIds[i])
			usedCards[validCardIds[i]] = true
		end
	end
	
	-- Create collection with various cards and levels
	local collection = {}
	for i, cardId in ipairs(validCardIds) do
		local count = math.random(1, 10)
		local level = math.random(1, 7)
		
		collection[cardId] = {
			count = count,
			level = level
		}
	end
	
	-- Compute squad power (simplified for client)
	local squadPower = 0
	for _, cardId in ipairs(deck) do
		local card = CLIENT_CARD_DATA[cardId]
		if card then
			-- Simple power calculation: base + rarity bonus
			local basePower = 100
			local rarityBonus = {
				[Types.Rarity.Common] = 0,
				[Types.Rarity.Rare] = 50,
				[Types.Rarity.Epic] = 150,
				[Types.Rarity.Legendary] = 300
			}
			squadPower = squadPower + basePower + (rarityBonus[card.rarity] or 0)
		end
	end
	
	-- Create lootboxes
	local lootboxes = {
		{
			id = "mock_lootbox_1",
			rarity = Types.Rarity.Common,
			state = Types.LootboxState.Idle,
			acquiredAt = TimeUtils.nowUnix() - 3600, -- 1 hour ago
			startedAt = nil,
			endsAt = nil
		},
		{
			id = "mock_lootbox_2",
			rarity = Types.Rarity.Rare,
			state = Types.LootboxState.Unlocking,
			acquiredAt = TimeUtils.nowUnix() - 1800, -- 30 minutes ago
			startedAt = TimeUtils.nowUnix() - 1800,
			endsAt = TimeUtils.nowUnix() + TimeUtils.lootboxDurations.Rare -- Will be ready in 1 hour
		}
	}
	
	-- Create profile
	local profile = {
		version = 2,
		playerId = "mock_player_123",
		createdAt = TimeUtils.nowUnix() - 86400, -- 1 day ago
		lastLoginAt = TimeUtils.nowUnix(),
		loginStreak = 5,
		collection = collection,
		deck = deck,
		currencies = {
			soft = 5000,
			hard = 100
		},
		favoriteLastSeen = TimeUtils.nowUnix() - 3600,
		tutorialStep = 3,
		squadPower = squadPower,
		lootboxes = lootboxes
	}
	
	return profile
end

-- Create a profile updated payload
function MockData.makeProfileUpdatedPayload(profile)
	profile = profile or MockData.makeProfileSnapshot()
	
	-- Create collection summary
	local collectionSummary = {}
	for cardId, entry in pairs(profile.collection) do
		table.insert(collectionSummary, {
			cardId = cardId,
			count = entry.count,
			level = entry.level
		})
	end
	
	-- Create login info
	local loginInfo = {
		lastLoginAt = profile.lastLoginAt,
		loginStreak = profile.loginStreak
	}
	
	return {
		deck = profile.deck,
		collectionSummary = collectionSummary,
		loginInfo = loginInfo,
		squadPower = profile.squadPower,
		lootboxes = profile.lootboxes,
		updatedAt = TimeUtils.nowUnix(),
		serverNow = TimeUtils.nowUnix()
	}
end

-- Create a match response
function MockData.makeMatchResponse(ok)
	if not ok then
		return {
			ok = false,
			error = {
				code = "BUSY",
				message = "Player already in match"
			},
			serverNow = TimeUtils.nowUnix()
		}
	end
	
	-- Create deterministic match result
	local matchId = "mock_match_" .. TimeUtils.nowUnix()
	local seed = 12345
	
	-- Create battle log
	local battleLog = {
		{type = "round_start", round = 1},
		{type = "attack", round = 1, attackerSlot = 1, defenderSlot = 1, damage = 5},
		{type = "attack", round = 1, attackerSlot = 2, defenderSlot = 2, damage = 3},
		{type = "attack", round = 1, attackerSlot = 3, defenderSlot = 3, damage = 4},
		{type = "round_start", round = 2},
		{type = "attack", round = 2, attackerSlot = 1, defenderSlot = 1, damage = 5},
		{type = "attack", round = 2, attackerSlot = 2, defenderSlot = 2, damage = 3},
		{type = "round_start", round = 3},
		{type = "attack", round = 3, attackerSlot = 1, defenderSlot = 1, damage = 5},
		{type = "round_start", round = 4},
		{type = "attack", round = 4, attackerSlot = 1, defenderSlot = 1, damage = 5}
	}
	
	-- Create match result
	local result = {
		winner = "A",
		rounds = 4,
		survivorsA = 6,
		survivorsB = 0,
		totalActions = 10,
		totalDamage = 40,
		totalKOs = 6,
		totalDefenceReduced = 8
	}
	
	return {
		ok = true,
		matchId = matchId,
		seed = seed,
		result = result,
		log = battleLog,
		serverNow = TimeUtils.nowUnix()
	}
end

-- Create an error response
function MockData.makeErrorResponse(errorCode, message)
	return {
		ok = false,
		error = {
			code = errorCode or "INTERNAL",
			message = message or "An unexpected error occurred"
		},
		serverNow = TimeUtils.nowUnix()
	}
end

-- Create a rate limited response
function MockData.makeRateLimitedResponse()
	return MockData.makeErrorResponse("RATE_LIMITED", "Request too frequent, please wait")
end

-- Create a profile load failed response
function MockData.makeProfileLoadFailedResponse()
	return MockData.makeErrorResponse("PROFILE_LOAD_FAILED", "Failed to load profile data")
end

return MockData
