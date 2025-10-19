local MatchService = {}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Modules
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local CombatEngine = require(script.Parent:WaitForChild("CombatEngine"))
local DeckValidator = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("DeckValidator"))
local SeededRNG = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RNG"):WaitForChild("SeededRNG"))
local CardCatalog = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("CardCatalog"))

-- Configuration
local RATE_LIMIT = {
	COOLDOWN = 1, -- seconds between match requests
	MAX_REQUESTS = 5 -- max requests per minute
}

local MAX_ROUNDS = 50 -- Maximum battle rounds

-- Studio-only: keep the BUSY window long enough for the concurrency test
local TEST_BUSY_DELAY_SEC = 0.75 -- was ~0.2; use 0.75s

-- Dev mode detection
local IS_DEV_MODE = RunService:IsStudio()

-- Test mode tracking (Studio-only)
local testModeUsers = {} -- Set of userIds in test mode (bypasses rate limits)

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
					local card = CardCatalog.GetCard(cardId)
					if card then
						local sameClassCards = CardCatalog.GetCardsByClass(card.class)
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
			return {"card_500", "card_800", "card_900", "card_500", "card_800", "card_900"}
		end
	},
	
	-- Defensive opponent
	DEFENSIVE = {
		name = "Defensive Opponent", 
		description = "High health, low damage",
		generateDeck = function(playerDeck, rng)
			return {"card_200", "card_400", "card_600", "card_200", "card_400", "card_600"}
		end
	},
	
	-- Balanced opponent
	BALANCED = {
		name = "Balanced Opponent",
		description = "Mixed composition",
		generateDeck = function(playerDeck, rng)
			return {"card_100", "card_200", "card_300", "card_500", "card_600", "card_700"}
		end
	}
}

-- Dev-mode PvE opponents (for Studio development)
local DEV_PVE_OPPONENTS = {
	-- Mirror variant with controlled substitutions (0-10%)
	MIRROR = {
		name = "Dev Mirror",
		description = "Your deck with 0-10% substitutions",
		generateDeck = function(playerDeck, rng)
			local opponentDeck = {}
			for i, cardId in ipairs(playerDeck) do
				-- 90-100% chance to use same card (controlled variance)
				if SeededRNG.RandomFloat(rng, 0, 1) < 0.95 then
					opponentDeck[i] = cardId
				else
					-- Find a balanced substitute
					local card = CardCatalog.GetCard(cardId)
					if card then
						local sameClassCards = CardCatalog.GetCardsByClass(card.class)
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
	
	-- Balanced composition for longer matches
	BALANCED = {
		name = "Dev Balanced",
		description = "Balanced composition for longer matches",
		generateDeck = function(playerDeck, rng)
			-- Create a balanced deck with 2 DPS, 2 Support, 2 Tank
			local balancedCards = {
				"card_100", "card_500",  -- 2 DPS
				"card_600", "card_700",  -- 2 Support  
				"card_200", "card_300"   -- 2 Tank
			}
			
			-- Shuffle the balanced composition
			local shuffled = {}
			for _, cardId in ipairs(balancedCards) do
				table.insert(shuffled, cardId)
			end
			SeededRNG.Shuffle(rng, shuffled)
			
			return shuffled
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

-- Test mode functions (Studio-only)
local function EnableTestMode(player)
	if not IS_DEV_MODE then
		return false, "Test mode only available in Studio"
	end
	testModeUsers[player.UserId] = true
	return true
end

local function DisableTestMode(player)
	if not IS_DEV_MODE then
		return false, "Test mode only available in Studio"
	end
	testModeUsers[player.UserId] = nil
	return true
end

-- Test delay function (Studio-only)
local function TestDelay(seconds)
	if not IS_DEV_MODE then
		return
	end
	task.wait(seconds or 0.1)
end

local function CheckRateLimit(player)
	InitializePlayerState(player)
	local state = playerMatchState[player]
	local now = os.time()
	
	-- Check if player is already in a match (concurrency guard)
	if state.isInMatch then
		return false, "BUSY", "Player already in match"
	end
	
	-- Skip rate limiting for test mode users
	if testModeUsers[player.UserId] then
		-- Still set isInMatch to prevent concurrent matches
		state.isInMatch = true
		return true
	end
	
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

local function SelectPvEOpponent(playerDeck, rng, variant)
	-- Use dev-mode opponents in Studio, production opponents otherwise
	local opponents = IS_DEV_MODE and DEV_PVE_OPPONENTS or PVE_OPPONENTS
	
	-- If variant is specified and exists, use it
	if variant and opponents[variant] then
		LogInfo(nil, "Using PvE variant: %s", opponents[variant].name)
		return opponents[variant]
	end
	
	-- In dev mode, default to BALANCED if no variant specified
	if IS_DEV_MODE and not variant then
		LogInfo(nil, "Dev mode: defaulting to BALANCED variant")
		return opponents.BALANCED
	end
	
	-- Otherwise, randomly select from available opponents
	local opponentKeys = {}
	for key, _ in pairs(opponents) do
		table.insert(opponentKeys, key)
	end
	
	local selectedKey = SeededRNG.RandomChoice(rng, opponentKeys)
	LogInfo(nil, "Selected PvE opponent: %s", opponents[selectedKey].name)
	return opponents[selectedKey]
end

local function GenerateOpponentDeck(playerDeck, mode, rng, variant)
	if mode == "PvE" then
		-- Select PvE opponent and generate deck
		local opponent = SelectPvEOpponent(playerDeck, rng, variant)
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
	-- Get player's profile (with lazy loading)
	local profile = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		LogWarning(player, "Profile loading failed")
		return false, "NO_DECK", "Player profile not found"
	end
	
	LogInfo(player, "Profile loaded successfully, deck size: %d", profile.deck and #profile.deck or 0)
	
	-- Check if player has a deck
	if not profile.deck or #profile.deck == 0 then
		LogWarning(player, "Player has no active deck")
		return false, "NO_DECK", "Player has no active deck"
	end
	
	-- Validate deck for battle (must have exactly 6 cards)
	local isValid, errorMessage = DeckValidator.ValidateDeckForBattle(profile.deck)
	if not isValid then
		LogWarning(player, "Deck validation failed: %s", errorMessage)
		return false, "INVALID_DECK", "Invalid deck: " .. errorMessage
	end
	
	LogInfo(player, "Deck validation passed, returning profile")
	
	-- v2: No collection ownership validation - deck composition is independent of ownership
	
	return true, profile.deck, profile
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
	local variant = requestData.variant -- Optional variant selector
	
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
	
	-- Validate variant if provided
	if variant and mode == "PvE" then
		local validVariants = IS_DEV_MODE and {"Mirror", "Balanced"} or {"MIRROR_VARIANT", "AGGRESSIVE", "DEFENSIVE", "BALANCED"}
		local isValidVariant = false
		for _, validVariant in ipairs(validVariants) do
			if variant == validVariant then
				isValidVariant = true
				break
			end
		end
		
		if not isValidVariant then
			LogWarning(player, "Invalid PvE variant: %s", variant)
			CleanupPlayerState(player)
			return {
				ok = false,
				error = {
					code = "INVALID_REQUEST",
					message = "Invalid PvE variant"
				}
			}
		end
	end
	
	-- Validate and load player deck
	local deckValid, deckOrError, playerProfile = ValidatePlayerDeck(player)
	LogInfo(player, "ValidatePlayerDeck returned: valid=%s, deck=%s, profile=%s", 
		tostring(deckValid), tostring(type(deckOrError)), tostring(type(playerProfile)))
	
	-- Debug: Check what we actually got
	if deckValid then
		LogInfo(player, "Success case: deckValid=%s, deckOrError=%s, playerProfile=%s", 
			tostring(deckValid), tostring(type(deckOrError)), tostring(type(playerProfile)))
	else
		LogInfo(player, "Error case: deckValid=%s, deckOrError=%s, playerProfile=%s", 
			tostring(deckValid), tostring(deckOrError), tostring(type(playerProfile)))
	end
	
	if not deckValid then
		LogWarning(player, "Deck validation failed: %s", deckOrError)
		CleanupPlayerState(player)
		return {
			ok = false,
			error = {
				code = "DECK_VALIDATION_FAILED",
				message = deckOrError
			}
		}
	end
	
	local playerDeck = deckOrError
	
	-- Generate match ID and handle seed
	local matchId = GenerateMatchId()
	local serverSeed = requestData.seed or GenerateServerSeed(player, matchId)
	
	LogInfo(player, "Starting match %s with seed %d", matchId, serverSeed)
	
	-- Create RNG for opponent generation
	local rng = SeededRNG.New(serverSeed)
	
	-- Generate opponent deck
	local opponentDeck = GenerateOpponentDeck(playerDeck, mode, rng, variant)
	
	-- Stretch the BUSY window before the battle (Studio-only, test mode)
	if RunService:IsStudio() and testModeUsers[player.UserId] and TEST_BUSY_DELAY_SEC > 0 then
		task.wait(TEST_BUSY_DELAY_SEC)
	end
	
	-- Execute battle with collections for proper level computation
	if not playerProfile then
		LogError(player, "Player profile is nil - this should not happen")
		CleanupPlayerState(player)
		return {
			ok = false,
			error = {
				code = "INTERNAL",
				message = "Player profile not available"
			}
		}
	end
	
	LogInfo(player, "Player profile collection: %s", playerProfile.collection and "present" or "nil")
	if playerProfile.collection then
		local count = 0
		for _ in pairs(playerProfile.collection) do
			count = count + 1
		end
		LogInfo(player, "Collection size: %d cards", count)
	end
	
	local success, battleResult = pcall(function()
		return CombatEngine.ExecuteBattle(playerDeck, opponentDeck, serverSeed, playerProfile.collection, nil)
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
	
	-- Get battle statistics
	local battleStats = CombatEngine.GetBattleStats(battleResult)
	
	-- Create response payload with real stats
	local result = {
		winner = battleResult.winner,
		rounds = battleResult.rounds,
		survivorsA = #battleResult.survivorsA,
		survivorsB = #battleResult.survivorsB,
		totalActions = battleStats.totalActions,
		totalDamage = battleStats.totalDamage,
		totalKOs = battleStats.totalKOs
	}
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

-- Test mode functions (Studio-only)
function MatchService.EnableTestMode(player)
	return EnableTestMode(player)
end

function MatchService.DisableTestMode(player)
	return DisableTestMode(player)
end

-- Init function for bootstrap
function MatchService.Init()
	-- Idempotency check
	if playerMatchState ~= nil then
		LogInfo(nil, "MatchService already initialized, skipping")
		return
	end
	
	-- Player cleanup
	Players.PlayerRemoving:Connect(function(player)
		playerMatchState[player] = nil
	end)
	
	LogInfo(nil, "MatchService initialized successfully")
end

return MatchService
