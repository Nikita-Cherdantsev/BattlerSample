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
local CardStats = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("CardStats"))
local BossDecks = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Boss"):WaitForChild("BossDecks"))

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

-- NPC deck storage: player -> partName -> { deck, levels, seed }
-- Stores generated NPC decks only while prep window is open (cleared when window closes or battle completes)
local npcDecks = {} -- player -> partName -> { deck = {...}, levels = {...}, seed = number }

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
					table.insert(opponentDeck, cardId)
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
								table.insert(opponentDeck, SeededRNG.RandomChoice(rng, availableCards))
							else
								table.insert(opponentDeck, cardId)
							end
						else
							table.insert(opponentDeck, cardId)
						end
					else
						table.insert(opponentDeck, cardId)
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
					table.insert(opponentDeck, cardId)
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
								table.insert(opponentDeck, SeededRNG.RandomChoice(rng, availableCards))
							else
								table.insert(opponentDeck, cardId)
							end
						else
							table.insert(opponentDeck, cardId)
						end
					else
						table.insert(opponentDeck, cardId)
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

-- Generate NPC deck with power matching (±7 power variance)
-- Returns: { deck = {...}, levels = {...} } where deck is array of card IDs and levels is array of card levels
local function GenerateNPCDeck(playerSquadPower, rng)
	-- Target power: player power ± 7
	local powerVariance = SeededRNG.RandomFloat(rng, -3, 3)
	local targetPower = math.max(1, math.floor(playerSquadPower + powerVariance)) -- Ensure at least 1
	
	-- Random deck size (1-6 cards)
	local deckSize = SeededRNG.RandomInt(rng, 1, 6)
	
	-- Get all available cards
	local allCards = {}
	for cardId, _ in pairs(CardCatalog.GetAllCards()) do
		table.insert(allCards, cardId)
	end
	
	if #allCards == 0 then
		warn("[MatchService] No cards available for NPC deck generation")
		return { deck = {}, levels = {} }
	end
	
	-- Generate deck by trying different combinations
	local bestDeck = {}
	local bestLevels = {}
	local bestPowerDiff = math.huge
	local maxAttempts = 100
	
	for attempt = 1, maxAttempts do
		local candidateDeck = {}
		local candidateLevels = {}
		local totalPower = 0
		
		-- Shuffle card pool for this attempt
		local shuffledCards = {}
		for _, cardId in ipairs(allCards) do
			table.insert(shuffledCards, cardId)
		end
		SeededRNG.Shuffle(rng, shuffledCards)
		
		-- Try to build a deck of the target size
		for i = 1, deckSize do
			if i <= #shuffledCards then
				local cardId = shuffledCards[i]
				-- Random level 1-10
				local level = SeededRNG.RandomInt(rng, 1, 10)
				local cardPower = CardStats.ComputeCardPower(cardId, level)
				
				-- Check if adding this card gets us closer to target
				if totalPower + cardPower <= targetPower + 10 then -- Allow some overflow
					table.insert(candidateDeck, cardId)
					table.insert(candidateLevels, level)
					totalPower = totalPower + cardPower
				end
			end
		end
		
		-- Evaluate this candidate
		local powerDiff = math.abs(totalPower - targetPower)
		if powerDiff < bestPowerDiff and #candidateDeck > 0 then
			bestPowerDiff = powerDiff
			bestDeck = candidateDeck
			bestLevels = candidateLevels
			
			-- If we're within ±7, we're good
			if powerDiff <= 3 then
				break
			end
		end
	end
	
	-- If we still don't have a deck, use fallback (just pick random cards)
	if #bestDeck == 0 then
		SeededRNG.Shuffle(rng, allCards)
		for i = 1, math.min(deckSize, #allCards) do
			table.insert(bestDeck, allCards[i])
			table.insert(bestLevels, SeededRNG.RandomInt(rng, 1, 10))
		end
	end
	
	return {
		deck = bestDeck,
		levels = bestLevels
	}
end

-- Generate new NPC deck for a player and part
-- Returns: { deck = {...}, levels = {...}, seed = number } or nil if not NPC mode
local function GenerateNPCDeckForPlayer(player, partName)
	if not partName or not partName:match("^NPCMode") then
		return nil -- Not an NPC part
	end
	
	local profile = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		LogWarning(player, "Failed to load profile for NPC deck generation")
		return nil
	end
	
	-- Get player's squad power
	local playerSquadPower = profile.squadPower or 0
	if playerSquadPower == 0 then
		-- Calculate squad power if not set
		local totalPower = 0
		for _, cardId in ipairs(profile.deck) do
			local cardEntry = profile.collection[cardId]
			local level = cardEntry and cardEntry.level or 1
			totalPower = totalPower + CardStats.ComputeCardPower(cardId, level)
		end
		playerSquadPower = totalPower
	end
	
	-- Generate seed for this part (use current time to ensure freshness)
	local seed = os.time() * 1000 + player.UserId + (os.clock() * 1000) % 1000
	local rng = SeededRNG.New(seed)
	
	-- Generate NPC deck
	local npcDeckData = GenerateNPCDeck(playerSquadPower, rng)
	
	-- Generate reward (for victory): random lootbox (uncommon, rare, epic, or legendary)
	-- Use a separate RNG instance to avoid correlation
	local rewardRNG = SeededRNG.New(seed + 5000)
	local rarities = {"uncommon", "rare", "epic", "legendary"}
	local rarityIndex = SeededRNG.RandomInt(rewardRNG, 1, #rarities)
	local rewardRarity = rarities[rarityIndex]
	
	local reward = {
		type = "lootbox",
		rarity = rewardRarity,
		count = 1
	}
	
	LogInfo(player, "Generated NPC deck for part %s: %d cards, seed %d, reward: %s lootbox", 
		partName, #npcDeckData.deck, seed, rewardRarity)
	
	return {
		deck = npcDeckData.deck,
		levels = npcDeckData.levels,
		seed = seed,
		reward = reward -- Store reward with NPC deck
	}
end

-- Get or generate NPC deck for a player and part
-- Generates new deck when prep window opens, stores it temporarily, reuses for battle
-- Returns: { deck = {...}, levels = {...}, seed = number } or nil if not NPC mode
function MatchService.GetOrGenerateNPCDeck(player, partName)
	if not partName or not partName:match("^NPCMode") then
		return nil -- Not an NPC part
	end
	
	-- Initialize storage for player if needed
	if not npcDecks[player] then
		npcDecks[player] = {}
	end
	
	-- Return existing deck if available (from prep window)
	if npcDecks[player][partName] then
		return npcDecks[player][partName]
	end
	
	-- Generate new NPC deck (when prep window opens)
	local npcDeckData = GenerateNPCDeckForPlayer(player, partName)
	if not npcDeckData then
		return nil
	end
	
	-- Store it temporarily (until battle completes or prep window closes)
	npcDecks[player][partName] = npcDeckData
	
	return npcDeckData
end

-- Clear NPC deck for a player and part (called after battle completes or prep window closes)
function MatchService.ClearNPCDeck(player, partName)
	if npcDecks[player] and npcDecks[player][partName] then
		npcDecks[player][partName] = nil
	end
end

-- Extract boss ID from part name (e.g., "BossMode1Trigger" -> "1")
local function ExtractBossId(partName)
	if not partName or not partName:match("^BossMode") then
		return nil
	end
	-- Extract number from "BossMode" + number + "Trigger"
	local bossId = partName:match("^BossMode(%d+)")
	return bossId
end

-- Get current boss difficulty for a player (defaults to "easy" if not set)
local function GetBossDifficulty(player, bossId)
	local profile = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		LogWarning(player, "Failed to load profile for boss difficulty")
		return "easy"
	end
	
	-- Initialize bossDifficulties if needed
	if not profile.bossDifficulties then
		profile.bossDifficulties = {}
	end
	
	-- Return current difficulty or default to "easy"
	return profile.bossDifficulties[bossId] or "easy"
end

-- Increase boss difficulty after victory (cycles: easy -> normal -> hard -> nightmare -> hell -> easy)
local function IncreaseBossDifficulty(player, bossId)
	local profile = PlayerDataService.EnsureProfileLoaded(player)
	if not profile then
		LogWarning(player, "Failed to load profile for boss difficulty increase")
		return false
	end
	
	-- Initialize bossDifficulties if needed
	if not profile.bossDifficulties then
		profile.bossDifficulties = {}
	end
	
	-- Get current difficulty
	local currentDifficulty = profile.bossDifficulties[bossId] or "easy"
	
	-- Difficulty progression order
	local difficultyOrder = {
		["easy"] = "normal",
		["normal"] = "hard",
		["hard"] = "nightmare",
		["nightmare"] = "hell",
		["hell"] = "easy" -- Cycle back to easy after hell
	}
	
	-- Get next difficulty
	local nextDifficulty = difficultyOrder[currentDifficulty]
	if not nextDifficulty then
		-- Fallback: if current difficulty is invalid, set to normal
		nextDifficulty = "normal"
	end
	
	-- Update difficulty
	profile.bossDifficulties[bossId] = nextDifficulty
	
	-- Save profile
	local ProfileManager = require(game.ServerScriptService:WaitForChild("Persistence"):WaitForChild("ProfileManager"))
	local success = ProfileManager.SaveProfile(player.UserId, profile)
	
	if success then
		LogInfo(player, "Boss %s difficulty increased: %s -> %s", bossId, currentDifficulty, nextDifficulty)
		return true
	else
		LogWarning(player, "Failed to save boss difficulty update")
		return false
	end
end

-- Get boss deck for a specific boss and difficulty
local function GetBossDeck(bossId, difficulty)
	if not bossId then
		return nil
	end
	
	local bossDeckData = BossDecks.GetDeck(bossId, difficulty)
	if not bossDeckData then
		warn(string.format("[MatchService] Boss deck not found: bossId=%s, difficulty=%s", tostring(bossId), tostring(difficulty)))
		return nil
	end
	
	return {
		deck = bossDeckData.deck,
		levels = bossDeckData.levels,
		reward = bossDeckData.reward -- Include hardcoded reward
	}
end

-- Get boss deck and difficulty info for a player
function MatchService.GetBossDeckInfo(player, partName)
	local bossId = ExtractBossId(partName)
	if not bossId then
		return nil -- Not a boss part
	end
	
	local difficulty = GetBossDifficulty(player, bossId)
	local bossDeckData = GetBossDeck(bossId, difficulty)
	
	if not bossDeckData then
		return nil
	end
	
	return {
		bossId = bossId,
		difficulty = difficulty,
		deck = bossDeckData.deck,
		levels = bossDeckData.levels,
		reward = bossDeckData.reward -- Include hardcoded reward for prep window
	}
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
	
	-- Validate deck for battle (must have 1-6 cards)
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
				dh = logEntry.defenderHealth,
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
	local partName = requestData.partName -- Part name for NPC/Boss mode detection
	
	LogInfo(player, "Match request - mode: %s, variant: %s, partName: %s", mode, tostring(variant), tostring(partName))
	
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
	
	-- Determine battle mode and generate/get opponent deck
	local opponentDeck = {}
	local opponentCollection = nil
	local npcDeckData = nil -- Store NPC deck data for reward generation
	
	-- Check if this is NPC mode
	LogInfo(player, "Checking battle mode - partName: %s, match: %s", tostring(partName), tostring(partName and partName:match("^NPCMode")))
	
	if partName and partName:match("^NPCMode") then
		-- NPC mode: use stored NPC deck
		LogInfo(player, "NPC mode detected, getting NPC deck for part: %s", partName)
		npcDeckData = MatchService.GetOrGenerateNPCDeck(player, partName)
		if not npcDeckData then
			LogWarning(player, "Failed to get NPC deck for part %s", partName)
			CleanupPlayerState(player)
			return {
				ok = false,
				error = {
					code = "INTERNAL",
					message = "Failed to generate NPC deck"
				}
			}
		end
		
		opponentDeck = npcDeckData.deck
		
		-- Create opponent collection with levels
		opponentCollection = {}
		for i, cardId in ipairs(opponentDeck) do
			local level = npcDeckData.levels[i] or 1
			opponentCollection[cardId] = {
				count = 1,
				level = level
			}
		end
		
		-- Use stored seed if available, otherwise generate new one
		if npcDeckData.seed then
			serverSeed = npcDeckData.seed
		end
		
		LogInfo(player, "Using NPC deck for part %s: %d cards", partName, #opponentDeck)
	elseif partName and partName:match("^BossMode") then
		-- Boss mode: use hardcoded boss deck based on difficulty
		LogInfo(player, "Boss mode detected, getting boss deck for part: %s", partName)
		local bossDeckInfo = MatchService.GetBossDeckInfo(player, partName)
		if not bossDeckInfo then
			LogWarning(player, "Failed to get boss deck for part %s", partName)
			CleanupPlayerState(player)
			return {
				ok = false,
				error = {
					code = "INTERNAL",
					message = "Failed to get boss deck"
				}
			}
		end
		
		opponentDeck = bossDeckInfo.deck
		
		-- Create opponent collection with levels
		opponentCollection = {}
		for i, cardId in ipairs(opponentDeck) do
			local level = bossDeckInfo.levels[i] or 1
			opponentCollection[cardId] = {
				count = 1,
				level = level
			}
		end
		
		-- Store boss deck info for reward generation (similar to NPC mode)
		npcDeckData = {
			reward = bossDeckInfo.reward -- Store hardcoded boss reward
		}
		
		LogInfo(player, "Using boss deck for part %s (boss %s, difficulty %s): %d cards, reward: %s", 
			partName, bossDeckInfo.bossId, bossDeckInfo.difficulty, #opponentDeck, 
			bossDeckInfo.reward and bossDeckInfo.reward.rarity or "none")
	else
		-- Regular PvE mode: use existing generation logic
		local rng = SeededRNG.New(serverSeed)
		opponentDeck = GenerateOpponentDeck(playerDeck, mode, rng, variant)
	end
	
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
		return CombatEngine.ExecuteBattle(playerDeck, opponentDeck, serverSeed, playerProfile.collection, opponentCollection)
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
	
	-- Extract rival deck levels for client display
	local rivalDeckLevels = nil
	if opponentCollection then
		rivalDeckLevels = {}
		for i, cardId in ipairs(opponentDeck) do
			local cardEntry = opponentCollection[cardId]
			if cardEntry and cardEntry.level then
				rivalDeckLevels[i] = cardEntry.level
			else
				rivalDeckLevels[i] = 1
			end
		end
	end
	
	-- Cleanup player state
	CleanupPlayerState(player)
	
	-- Determine battle outcome
	-- CombatEngine returns "A" for player, "B" for opponent, "Draw" for draw
	local isPlayerVictory = (battleResult.winner == "A")
	
	-- Clear NPC deck after battle completes (win or lose)
	-- This ensures fresh deck generation next time prep window opens
	if partName and partName:match("^NPCMode") then
		MatchService.ClearNPCDeck(player, partName)
	end
	
	-- Increase boss difficulty after victory (boss mode only)
	if isPlayerVictory and partName and partName:match("^BossMode") then
		local bossId = ExtractBossId(partName)
		if bossId then
			IncreaseBossDifficulty(player, bossId)
		end
	end
	
	-- Generate battle rewards based on outcome
	local rewards = nil
	
	if isPlayerVictory then
		-- For NPC mode: use the reward that was generated with the deck (shown in prep window)
		-- For Boss mode: use the hardcoded reward from BossDecks (shown in prep window)
		-- For other modes: generate random reward
		if partName and partName:match("^NPCMode") and npcDeckData and npcDeckData.reward then
			-- Use the reward that was shown in prep window
			rewards = npcDeckData.reward
			LogInfo(player, "Victory reward (NPC from prep window): %s lootbox", rewards.rarity)
		elseif partName and partName:match("^BossMode") and npcDeckData and npcDeckData.reward then
			-- Use the hardcoded boss reward (from BossDecks, shown in prep window)
			rewards = npcDeckData.reward
			LogInfo(player, "Victory reward (Boss hardcoded): %s lootbox x%d", rewards.rarity, rewards.count or 1)
		else
			-- Generate new reward for non-NPC battles
			local rewardRNG = SeededRNG.New(serverSeed + 9999)
			local rarities = {"uncommon", "rare", "epic", "legendary"}
			local rarityIndex = SeededRNG.RandomInt(rewardRNG, 1, #rarities)
			local rewardRarity = rarities[rarityIndex]
			
			rewards = {
				type = "lootbox",
				rarity = rewardRarity,
				count = 1
			}
			
			LogInfo(player, "Victory reward generated: %s lootbox", rewardRarity)
		end
	else
		-- Loss reward: soft currency (10-100)
		local rewardRNG = SeededRNG.New(serverSeed + 9999)
		local softAmount = SeededRNG.RandomInt(rewardRNG, 10, 100)
		
		rewards = {
			type = "soft",
			amount = softAmount
		}
		
		LogInfo(player, "Loss reward generated: %d soft currency", softAmount)
	end
	
	-- Return success response
	return {
		ok = true,
		matchId = matchId,
		seed = serverSeed,
		result = result,
		log = compactLog,
		playerDeck = playerDeck,
		rivalDeck = opponentDeck,
		rivalDeckLevels = rivalDeckLevels, -- Include levels for rival deck display
		rewards = rewards -- Include battle rewards
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
