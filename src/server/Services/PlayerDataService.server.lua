local PlayerDataService = {}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Modules
local ProfileManager = require(game.ServerScriptService.Persistence.ProfileManager)
local DeckValidator = require(game.ReplicatedStorage.Modules.Cards.DeckValidator)
local CardCatalog = require(game.ReplicatedStorage.Modules.Cards.CardCatalog)

-- Configuration
local AUTOSAVE_INTERVAL = 300 -- 5 minutes in seconds
local MAX_AUTOSAVE_RETRIES = 3
local AUTOSAVE_BACKOFF_BASE = 2 -- seconds

-- State
local playerProfiles = {} -- player -> profile mapping
local autosaveTasks = {} -- player -> autosave task
local isShuttingDown = false

-- Utility functions
local function LogInfo(player, message, ...)
	local playerName = player and player.Name or "Unknown"
	local formattedMessage = string.format(message, ...)
	print(string.format("[PlayerDataService] %s: %s", playerName, formattedMessage))
end

local function LogWarning(player, message, ...)
	local playerName = player and player.Name or "Unknown"
	local formattedMessage = string.format(message, ...)
	warn(string.format("[PlayerDataService] %s: %s", playerName, formattedMessage))
end

local function LogError(player, message, ...)
	local playerName = player and player.Name or "Unknown"
	local formattedMessage = string.format(message, ...)
	error(string.format("[PlayerDataService] %s: %s", playerName, formattedMessage))
end

local function ValidateDeck(deck)
	-- Use shared DeckValidator
	local isValid, errorMessage = DeckValidator.ValidateDeck(deck)
	if not isValid then
		return false, "Deck validation failed: " .. errorMessage
	end
	return true
end

local function CheckCollectionOwnership(player, deck)
	local profile = playerProfiles[player]
	if not profile then
		return false, "Player profile not loaded"
	end
	
	-- Count cards needed
	local cardCounts = {}
	for _, cardId in ipairs(deck) do
		cardCounts[cardId] = (cardCounts[cardId] or 0) + 1
	end
	
	-- Check if collection has enough
	for cardId, needed in pairs(cardCounts) do
		local available = profile.collection[cardId] or 0
		if available < needed then
			return false, string.format("Not enough %s (need %d, have %d)", cardId, needed, available)
		end
	end
	
	return true
end

local function SafeSaveProfile(player)
	if not player or not playerProfiles[player] then
		return false, "No profile to save"
	end
	
	local success = ProfileManager.SaveProfile(player.UserId, playerProfiles[player])
	if success then
		LogInfo(player, "Profile saved successfully")
		return true
	else
		LogWarning(player, "Failed to save profile")
		return false
	end
end

local function StartAutosave(player)
	if autosaveTasks[player] then
		return -- Already running
	end
	
	autosaveTasks[player] = spawn(function()
		while player and playerProfiles[player] and not isShuttingDown do
			task.wait(AUTOSAVE_INTERVAL)
			
			if not player or not playerProfiles[player] then
				break
			end
			
			-- Attempt autosave with exponential backoff
			local retryCount = 0
			local success = false
			
			while retryCount < MAX_AUTOSAVE_RETRIES and not success do
				success = SafeSaveProfile(player)
				
				if not success then
					retryCount = retryCount + 1
					if retryCount < MAX_AUTOSAVE_RETRIES then
						local delay = AUTOSAVE_BACKOFF_BASE * (2 ^ (retryCount - 1))
						LogWarning(player, "Autosave failed, retrying in %d seconds (attempt %d/%d)", delay, retryCount + 1, MAX_AUTOSAVE_RETRIES)
						task.wait(delay)
					end
				end
			end
			
			if not success then
				LogWarning(player, "Autosave failed after %d attempts", MAX_AUTOSAVE_RETRIES)
			end
		end
	end)
end

local function StopAutosave(player)
	if autosaveTasks[player] then
		autosaveTasks[player] = nil
	end
end

-- Player lifecycle handlers
local function OnPlayerAdded(player)
	LogInfo(player, "Player joined, loading profile...")
	
	-- Load or create profile
	local profile = ProfileManager.LoadProfile(player.UserId)
	if not profile then
		LogError(player, "Failed to load/create profile")
		return
	end
	
	-- Store profile reference
	playerProfiles[player] = profile
	
	-- Update profile with current player info
	profile.playerId = tostring(player.UserId)
	ProfileManager.UpdateLoginTime(player.UserId)
	
	-- Ensure valid default deck if missing
	if not profile.deck or #profile.deck ~= 6 then
		LogInfo(player, "Initializing default deck...")
		local success = ProfileManager.UpdateDeck(player.UserId, ProfileManager.DEFAULT_DECK)
		if success then
			profile.deck = ProfileManager.DEFAULT_DECK
			LogInfo(player, "Default deck initialized")
		else
			LogWarning(player, "Failed to initialize default deck")
		end
	end
	
	-- Start autosave
	StartAutosave(player)
	
	LogInfo(player, "Profile loaded successfully. Collection: %d unique cards, Deck: %d cards", 
		ProfileManager.GetProfileStats(player.UserId).uniqueCards, #profile.deck)
end

local function OnPlayerRemoving(player)
	LogInfo(player, "Player leaving, saving profile...")
	
	-- Stop autosave
	StopAutosave(player)
	
	-- Attempt final save
	local success = SafeSaveProfile(player)
	if success then
		LogInfo(player, "Final save completed")
	else
		LogWarning(player, "Final save failed")
	end
	
	-- Clean up
	playerProfiles[player] = nil
end

local function OnBindToClose()
	LogInfo(nil, "Server shutting down, flushing all profiles...")
	isShuttingDown = true
	
	-- Stop all autosave tasks
	for player in pairs(autosaveTasks) do
		StopAutosave(player)
	end
	
	-- Save all profiles
	local savedCount = 0
	local failedCount = 0
	
	for player, profile in pairs(playerProfiles) do
		if player then
			local success = SafeSaveProfile(player)
			if success then
				savedCount = savedCount + 1
			else
				failedCount = failedCount + 1
			end
		end
	end
	
	LogInfo(nil, "Shutdown save complete: %d successful, %d failed", savedCount, failedCount)
	
	-- Flush pending DataStore operations
	ProfileManager.Flush()
	LogInfo(nil, "DataStore flush completed")
end

-- Public API

-- Get player profile (read-only snapshot)
function PlayerDataService.GetProfile(player)
	if not player or not playerProfiles[player] then
		return nil
	end
	
	-- Return a copy to prevent external modification
	local profile = playerProfiles[player]
	return {
		playerId = profile.playerId,
		createdAt = profile.createdAt,
		lastLoginAt = profile.lastLoginAt,
		loginStreak = profile.loginStreak,
		collection = table.clone(profile.collection),
		deck = table.clone(profile.deck),
		currencies = {
			soft = profile.currencies.soft,
			hard = profile.currencies.hard
		}
	}
end

-- Set player deck
function PlayerDataService.SetDeck(player, deckIds)
	if not player or not playerProfiles[player] then
		return false, "Player profile not loaded"
	end
	
	-- Validate deck structure
	local isValid, errorMessage = ValidateDeck(deckIds)
	if not isValid then
		return false, errorMessage
	end
	
	-- Check collection ownership
	local hasCards, errorMessage = CheckCollectionOwnership(player, deckIds)
	if not hasCards then
		return false, errorMessage
	end
	
	-- Update deck atomically
	local success = ProfileManager.UpdateDeck(player.UserId, deckIds)
	if success then
		-- Update local copy
		playerProfiles[player].deck = table.clone(deckIds)
		LogInfo(player, "Deck updated successfully")
		return true
	else
		LogWarning(player, "Failed to update deck")
		return false, "Failed to persist deck"
	end
end

-- Grant cards to player
function PlayerDataService.GrantCards(player, rewards)
	if not player or not playerProfiles[player] then
		return false, "Player profile not loaded"
	end
	
	if not rewards or type(rewards) ~= "table" then
		return false, "Invalid rewards format"
	end
	
	-- Validate all card IDs exist in catalog
	for cardId, delta in pairs(rewards) do
		if not CardCatalog.IsValidCardId(cardId) then
			return false, "Invalid card ID: " .. cardId
		end
		
		if type(delta) ~= "number" or delta <= 0 then
			return false, "Invalid card count for " .. cardId .. ": " .. tostring(delta)
		end
	end
	
	-- Grant cards atomically
	local success = true
	local grantedCards = {}
	
	for cardId, delta in pairs(rewards) do
		local cardSuccess = ProfileManager.AddCardsToCollection(player.UserId, cardId, delta)
		if cardSuccess then
			-- Update local copy
			playerProfiles[player].collection[cardId] = (playerProfiles[player].collection[cardId] or 0) + delta
			grantedCards[cardId] = delta
		else
			success = false
			LogWarning(player, "Failed to grant %d %s", delta, cardId)
		end
	end
	
	if success then
		LogInfo(player, "Granted %d card types successfully", #grantedCards)
		return true, grantedCards
	else
		LogWarning(player, "Partial card grant failure")
		return false, "Some cards failed to grant"
	end
end

-- Get player collection
function PlayerDataService.GetCollection(player)
	if not player or not playerProfiles[player] then
		return nil
	end
	
	-- Return a copy to prevent external modification
	return table.clone(playerProfiles[player].collection)
end

-- Get login information
function PlayerDataService.GetLoginInfo(player)
	if not player or not playerProfiles[player] then
		return nil
	end
	
	local profile = playerProfiles[player]
	return {
		lastLoginAt = profile.lastLoginAt,
		loginStreak = profile.loginStreak
	}
end

-- Bump login streak (for DailyHandler integration)
function PlayerDataService.BumpLoginStreak(player)
	if not player or not playerProfiles[player] then
		return false, "Player profile not loaded"
	end
	
	local success = ProfileManager.UpdateLoginStreak(player.UserId, true)
	if success then
		playerProfiles[player].loginStreak = playerProfiles[player].loginStreak + 1
		LogInfo(player, "Login streak bumped to %d", playerProfiles[player].loginStreak)
		return true
	else
		LogWarning(player, "Failed to bump login streak")
		return false
	end
end

-- Get service status
function PlayerDataService.GetStatus()
	local activeProfiles = 0
	local activeAutosaves = 0
	
	for _ in pairs(playerProfiles) do
		activeProfiles = activeProfiles + 1
	end
	
	for _ in pairs(autosaveTasks) do
		activeAutosaves = activeAutosaves + 1
	end
	
	return {
		activeProfiles = activeProfiles,
		activeAutosaves = activeAutosaves,
		isShuttingDown = isShuttingDown,
		autosaveInterval = AUTOSAVE_INTERVAL
	}
end

-- Manual save (for testing/debugging)
function PlayerDataService.ForceSave(player)
	if not player then
		return false, "No player specified"
	end
	
	return SafeSaveProfile(player)
end

-- Initialize service
function PlayerDataService.Init()
	LogInfo(nil, "Initializing PlayerDataService...")
	
	-- Connect to player events
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
	
	-- Connect to shutdown event
	game:BindToClose(OnBindToClose)
	
	LogInfo(nil, "PlayerDataService initialized successfully")
end

-- Auto-initialize when script runs
PlayerDataService.Init()

return PlayerDataService
