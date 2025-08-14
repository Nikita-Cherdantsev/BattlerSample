local MatchService = {}

-- Services
local Players = game:GetService("Players")

-- Modules
local PlayerDataService = require(script.Parent.PlayerDataService)
local CombatEngine = require(script.Parent.CombatEngine)
local DeckValidator = require(game.ReplicatedStorage.Modules.Cards.DeckValidator)
local SeededRNG = require(game.ReplicatedStorage.Modules.RNG.SeededRNG)

-- Configuration
local RATE_LIMIT = {
	COOLDOWN = 1, -- seconds between match requests
	MAX_REQUESTS = 5 -- max requests per minute
}

local MAX_ROUNDS = 50 -- Maximum battle rounds

-- Match state tracking
local playerMatchState = {} -- player -> { lastRequest, requestCount, resetTime, isInMatch }
local matchCounter = 0 -- For generating unique match IDs

-- PvE opponent presets (small set for MVP)
local PVE_OPPONENTS = {
	-- Mirror opponent with slight stat variance
	MIRROR_VARIANT = {
		name = "Mirror Variant",
		description = "Your deck with slight modifications",
		generateDeck = function(playerDeck, rng)
			local opponentDeck = {}
			for i, cardId in ipairs(playerDeck) do
				-- 80% chance to use same card, 20% chance to use a variant
				if SeededRNG.RandomFloat(rng, 0, 1) < 0.8 then
					opponentDeck[i] = cardId
				else
					-- Simple variant: try to find a card of same class
					local card = require(game.ReplicatedStorage.Modules.Cards.CardCatalog).GetCard(cardId)
					if card then
						local sameClassCards = require(game.ReplicatedStorage.Modules.Cards.CardCatalog).GetCardsByClass(card.class)
						if #sameClassCards > 1 then
							-- Pick a different card of same class
							local availableCards = {}
							for _, variantCard in ipairs(sameClassCards) do
								if variantCard.id ~= cardId then
									table.insert(availableCards, variantCard.id)
								end
							end
							if #availableCards > 0 then
								opponentDeck[i] = SeededRNG.RandomChoice(rng, availableCards)
							else
								opponentDeck[i] = cardId
							end
						else
							opponentDeck[i] = cardId
						end
					else
						opponentDeck[i] = cardId
					end
				end
			end
			return opponentDeck
		end
	},
	
	-- Aggressive opponent
	AGGRESSIVE = {
		name = "Aggressive Opponent",
		description = "High damage, low health",
		generateDeck = function(playerDeck, rng)
			return {"dps_002", "dps_003", "dps_004", "dps_002", "dps_003", "dps_004"}
		end
	},
	
	-- Defensive opponent
	DEFENSIVE = {
		name = "Defensive Opponent", 
		description = "High health, low damage",
		generateDeck = function(playerDeck, rng)
			return {"tank_001", "tank_002", "support_001", "tank_001", "tank_002", "support_001"}
		end
	},
	
	-- Balanced opponent
	BALANCED = {
		name = "Balanced Opponent",
		description = "Mixed composition",
		generateDeck = function(playerDeck, rng)
			return {"dps_001", "support_001", "tank_001", "dps_002", "support_002", "tank_002"}
		end
	}
}

-- Utility functions
local function LogInfo(player, message, ...)
	local playerName = player and player.Name or "Unknown"
	local formattedMessage = string.format(message, ...)
	print(string.format("[MatchService] %s: %s", playerName, formattedMessage))
end

local function LogWarning(player, message, ...)
	local playerName = player and player.Name or "Unknown"
	local formattedMessage = string.format(message, ...)
	warn(string.format("[MatchService] %s: %s", playerName, formattedMessage))
end

local function LogError(player, message, ...)
	local playerName = player and player.Name or "Unknown"
	local formattedMessage = string.format(message, ...)
	error(string.format("[MatchService] %s: %s", playerName, formattedMessage))
end

local function InitializePlayerState(player)
	if not playerMatchState[player] then
		playerMatchState[player] = {
			lastRequest = 0,
			requestCount = 0,
			resetTime = os.time() + 60,
			isInMatch = false
		}
	end
end

local function CheckRateLimit(player)
	InitializePlayerState(player)
	local state = playerMatchState[player]
	local now = os.time()
	
	-- Reset counter if minute has passed
	if now >= state.resetTime then
		state.requestCount = 0
		state.resetTime = now + 60
	end
	
	-- Check cooldown
	if now - state.lastRequest < RATE_LIMIT.COOLDOWN then
		return false, "RATE_LIMITED", "Request too frequent, please wait"
	end
	
	-- Check request count limit
	if state.requestCount >= RATE_LIMIT.MAX_REQUESTS then
		return false, "RATE_LIMITED", "Too many requests, please wait"
	end
	
	-- Check if player is already in a match
	if state.isInMatch then
		return false, "BUSY", "Player already in match"
	end
	
	-- Update rate limit state
	state.lastRequest = now
	state.requestCount = state.requestCount + 1
	state.isInMatch = true
	
	return true
end

local function CleanupPlayerState(player)
	if playerMatchState[player] then
		playerMatchState[player].isInMatch = false
	end
end

local function GenerateMatchId()
	matchCounter = matchCounter + 1
	return string.format("match_%d_%d", os.time(), matchCounter)
end

local function GenerateServerSeed(player, matchId)
	-- Generate deterministic seed from player ID, match ID, and current time
	local seedString = string.format("%d_%s_%d", player.UserId, matchId, os.time())
	local seed = 0
	
	-- Simple hash function for the seed string
	for i = 1, #seedString do
		seed = ((seed * 31) + string.byte(seedString, i)) % 0x7FFFFFFF
	end
	
	return seed
end

local function SelectPvEOpponent(playerDeck, rng)
	-- For MVP, randomly select from available opponents
	local opponentKeys = {}
	for key, _ in pairs(PVE_OPPONENTS) do
		table.insert(opponentKeys, key)
	end
	
	local selectedKey = SeededRNG.RandomChoice(rng, opponentKeys)
	return PVE_OPPONENTS[selectedKey]
end

local function GenerateOpponentDeck(playerDeck, mode, rng)
	if mode == "PvE" then
		-- Select PvE opponent and generate deck
		local opponent = SelectPvEOpponent(playerDeck, rng)
		return opponent.generateDeck(playerDeck, rng)
	else
		-- PvP: mirror the player's deck for now
		-- In a real implementation, this would load another player's deck
		local mirrorDeck = {}
		for i, cardId in ipairs(playerDeck) do
			mirrorDeck[i] = cardId
		end
		return mirrorDeck
	end
end

local function ValidatePlayerDeck(player)
	-- Get player's profile
	local profile = PlayerDataService.GetProfile(player)
	if not profile then
		return false, "NO_DECK", "Player profile not found"
	end
	
	-- Check if player has a deck
	if not profile.deck or #profile.deck == 0 then
		return false, "NO_DECK", "Player has no active deck"
	end
	
	-- Validate deck using shared tooling
	local isValid, errorMessage = DeckValidator.ValidateDeck(profile.deck)
	if not isValid then
		return false, "INVALID_DECK", "Invalid deck: " .. errorMessage
	end
	
	-- Check if player owns all cards in deck
	local collection = PlayerDataService.GetCollection(player)
	if collection then
		for _, cardId in ipairs(profile.deck) do
			local count = collection[cardId] or 0
			if count < 1 then
				return false, "INVALID_DECK", "Player does not own card: " .. cardId
			end
		end
	end
	
	return true, profile.deck
end

local function CreateCompactLog(battleResult)
	-- Create a compact version of the battle log for network transmission
	local compactLog = {}
	
	for _, logEntry in ipairs(battleResult.battleLog) do
		if logEntry.type == "attack" then
			table.insert(compactLog, {
				t = "a", -- attack
				r = logEntry.round,
				as = logEntry.attackerSlot,
				ap = logEntry.attackerPlayer,
				ds = logEntry.defenderSlot,
				dp = logEntry.defenderPlayer,
				d = logEntry.damage,
				k = logEntry.defenderKO
			})
		elseif logEntry.type == "round_start" then
			table.insert(compactLog, {
				t = "r", -- round
				r = logEntry.round
			})
		end
	end
	
	return compactLog
end

local function CreateMatchResult(battleResult, matchId, seed)
	-- Create the match result payload
	return {
		winner = battleResult.winner,
		rounds = battleResult.rounds,
		survivorsA = #battleResult.survivorsA,
		survivorsB = #battleResult.survivorsB,
		totalActions = 0,
		totalDamage = 0,
		totalKOs = 0
	}
end

-- Main match execution function
function MatchService.ExecuteMatch(player, requestData)
	LogInfo(player, "Processing match request")
	
	-- Rate limiting and concurrency check
	local canProceed, errorCode, errorMessage = CheckRateLimit(player)
	if not canProceed then
		LogWarning(player, "Match request rejected: %s", errorMessage)
		return {
			ok = false,
			error = {
				code = errorCode,
				message = errorMessage
			}
		}
	end
	
	-- Validate request data
	local mode = requestData.mode or "PvE"
	if mode ~= "PvE" and mode ~= "PvP" then
		LogWarning(player, "Invalid match mode: %s", mode)
		CleanupPlayerState(player)
		return {
			ok = false,
			error = {
				code = "INVALID_REQUEST",
				message = "Invalid match mode"
			}
		}
	end
	
	-- Validate and load player deck
	local deckValid, deckOrError, deckErrorMessage = ValidatePlayerDeck(player)
	if not deckValid then
		LogWarning(player, "Deck validation failed: %s", deckErrorMessage)
		CleanupPlayerState(player)
		return {
			ok = false,
			error = {
				code = deckOrError,
				message = deckErrorMessage
			}
		}
	end
	
	local playerDeck = deckOrError
	
	-- Generate match ID and server seed
	local matchId = GenerateMatchId()
	local serverSeed = GenerateServerSeed(player, matchId)
	
	LogInfo(player, "Starting match %s with seed %d", matchId, serverSeed)
	
	-- Create RNG for opponent generation
	local rng = SeededRNG.New(serverSeed)
	
	-- Generate opponent deck
	local opponentDeck = GenerateOpponentDeck(playerDeck, mode, rng)
	
	-- Execute battle
	local success, battleResult = pcall(function()
		return CombatEngine.ExecuteBattle(playerDeck, opponentDeck, serverSeed)
	end)
	
	if not success then
		LogError(player, "Battle execution failed: %s", battleResult)
		CleanupPlayerState(player)
		return {
			ok = false,
			error = {
				code = "INTERNAL",
				message = "Battle execution failed"
			}
		}
	end
	
	-- Validate battle result
	local isValid, validationError = CombatEngine.ValidateBattleResult(battleResult)
	if not isValid then
		LogError(player, "Battle result validation failed: %s", validationError)
		CleanupPlayerState(player)
		return {
			ok = false,
			error = {
				code = "INTERNAL",
				message = "Battle result validation failed"
			}
		}
	end
	
	-- Create response payload
	local result = CreateMatchResult(battleResult, matchId, serverSeed)
	local compactLog = CreateCompactLog(battleResult)
	
	LogInfo(player, "Match %s completed. Winner: %s, Rounds: %d", 
		matchId, battleResult.winner, battleResult.rounds)
	
	-- Cleanup player state
	CleanupPlayerState(player)
	
	-- Return success response
	return {
		ok = true,
		matchId = matchId,
		seed = serverSeed,
		result = result,
		log = compactLog
	}
end

-- Player cleanup
Players.PlayerRemoving:Connect(function(player)
	playerMatchState[player] = nil
end)

-- Public API for other modules
function MatchService.GetPlayerStatus(player)
	if not playerMatchState[player] then
		return {
			isInMatch = false,
			lastRequest = 0,
			requestCount = 0
		}
	end
	
	return {
		isInMatch = playerMatchState[player].isInMatch,
		lastRequest = playerMatchState[player].lastRequest,
		requestCount = playerMatchState[player].requestCount
	}
end

function MatchService.ForceCleanup(player)
	CleanupPlayerState(player)
end

LogInfo(nil, "MatchService initialized successfully")

return MatchService
