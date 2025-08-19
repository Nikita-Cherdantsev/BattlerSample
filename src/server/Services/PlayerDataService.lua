local PlayerDataService = {}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Modules
local ProfileManager = require(game.ServerScriptService:WaitForChild("Persistence"):WaitForChild("ProfileManager"))
local ProfileSchema = require(game.ServerScriptService:WaitForChild("Persistence"):WaitForChild("ProfileSchema"))
local DeckValidator = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("DeckValidator"))
local CardCatalog = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("CardCatalog"))

-- Configuration
local AUTOSAVE_INTERVAL = 300 -- 5 minutes in seconds
local MAX_AUTOSAVE_RETRIES = 3
local AUTOSAVE_BACKOFF_BASE = 2 -- seconds

-- State
local playerProfiles = {} -- player -> profile mapping
local autosaveTasks = {} -- player -> autosave task
local isShuttingDown = false

-- Forward declarations
local StartAutosave
local StopAutosave

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

local function AssignStarterDeckIfNeeded(profile, userId)
	if profile.deck and #profile.deck == 6 then
		return true -- Already has valid deck
	end
	
	LogInfo(nil, "Assigning starter deck for user %d", userId)
	
	-- Use the default deck from ProfileManager
	local success = ProfileManager.UpdateDeck(userId, ProfileManager.DEFAULT_DECK)
	if success then
		profile.deck = ProfileManager.DEFAULT_DECK
		LogInfo(nil, "Assigned starter deck: %s", table.concat(ProfileManager.DEFAULT_DECK, ", "))
		return true
	else
		LogWarning(nil, "Failed to assign starter deck for user %d", userId)
		return false
	end
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

StartAutosave = function(player)
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

StopAutosave = function(player)
	if autosaveTasks[player] then
		autosaveTasks[player] = nil
	end
end

-- Player lifecycle handlers
local function OnPlayerAdded(player)
	LogInfo(player, "Player joined, loading profile...")
	
	-- Load or create profile with retries
	local profile = nil
	local retryCount = 0
	local maxRetries = 3
	
	while not profile and retryCount < maxRetries do
		profile = ProfileManager.LoadProfile(player.UserId)
		if not profile then
			retryCount = retryCount + 1
			if retryCount < maxRetries then
				LogWarning(player, "Failed to load profile, retrying (%d/%d)...", retryCount, maxRetries)
				task.wait(1) -- Wait 1 second before retry
			else
				LogError(player, "Failed to load/create profile after %d attempts", maxRetries)
				return
			end
		end
	end
	
	-- Store profile reference
	playerProfiles[player] = profile
	
	-- Update profile with current player info
	profile.playerId = tostring(player.UserId)
	
	-- Update login time and persist
	ProfileSchema.UpdateLoginTime(profile)
	local saveSuccess = ProfileManager.SaveProfile(player.UserId, profile)
	if saveSuccess then
		LogInfo(player, "Saved profile for user: %d", player.UserId)
	else
		LogWarning(player, "Failed to save profile for user: %d", player.UserId)
	end
	
	-- Ensure valid default deck if missing
	AssignStarterDeckIfNeeded(profile, player.UserId)
	
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
			grantedCards[cardId] = delta
		else
			success = false
			LogWarning(player, "Failed to grant %d %s", delta, cardId)
		end
	end
	
	if success then
		-- Reload profile from DataStore to ensure local cache is in sync
		-- We need to force a reload because the cached profile was modified in-place
		local reloadedProfile = ProfileManager.LoadProfile(player.UserId)
		if reloadedProfile then
			playerProfiles[player] = reloadedProfile
		end
		
		-- Count granted card types
		local grantedCount = 0
		for _ in pairs(grantedCards) do
			grantedCount = grantedCount + 1
		end
		LogInfo(player, "Granted %d card types successfully", grantedCount)
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

-- Helper function to get today's date key in UTC
local function todayKeyUTC()
	return os.date("!%Y-%m-%d")
end

-- Bump login streak (for DailyHandler integration)
function PlayerDataService.BumpLoginStreak(player)
	if not player or not playerProfiles[player] then
		return false, "Player profile not loaded"
	end
	
	local profile = playerProfiles[player]
	profile.meta = profile.meta or {}
	local today = todayKeyUTC()
	
	LogInfo(player, "BumpLoginStreak called. Current streak: %d, last bump date: %s", 
		profile.loginStreak or 0, profile.meta.lastStreakBumpDate or "never")
	
	if profile.meta.lastStreakBumpDate == today then
		LogInfo(player, "Login streak already bumped today: %d", profile.loginStreak or 0)
		return true, profile.loginStreak
	end
	
	-- Update the streak directly in our local cache
	local oldStreak = profile.loginStreak or 0
	profile.loginStreak = oldStreak + 1
	profile.meta.lastStreakBumpDate = today
	
	LogInfo(player, "Streak updated: %d -> %d, date set to: %s", oldStreak, profile.loginStreak, today)
	
	-- Save the profile to persist the changes
	local saveSuccess = ProfileManager.SaveProfile(player.UserId, profile)
	if saveSuccess then
		LogInfo(player, "Login streak bumped to %d and saved successfully", profile.loginStreak)
		return true, profile.loginStreak
	else
		LogWarning(player, "Failed to save profile after streak bump")
		-- Revert the change since save failed
		profile.loginStreak = profile.loginStreak - 1
		profile.meta.lastStreakBumpDate = nil
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

-- Clear profile from cache (test-only, Studio only)
function PlayerDataService.ClearCache(userId)
	if not game:GetService("RunService"):IsStudio() then
		warn("ClearCache is only available in Studio")
		return false
	end
	
	userId = tostring(userId)
	
	-- Clear from ProfileManager cache
	ProfileManager.ClearCache(userId)
	
	-- Clear from PlayerDataService cache
	for player, profile in pairs(playerProfiles) do
		if profile and profile.playerId == userId then
			playerProfiles[player] = nil
		end
	end
	
	return true
end

-- Ensure profile is loaded (lazy-load for remotes)
function PlayerDataService.EnsureProfileLoaded(player)
	if not player then
		return nil, "PROFILE_LOAD_FAILED", "No player specified"
	end
	
	-- Check if already cached
	if playerProfiles[player] then
		return playerProfiles[player]
	end
	
	-- Attempt lazy load
	LogInfo(player, "Lazy loading profile...")
	local profile = ProfileManager.LoadProfile(player.UserId)
	if not profile then
		LogWarning(player, "Failed to lazy load profile")
		return nil, "PROFILE_LOAD_FAILED", "Failed to load profile data"
	end
	
	-- Cache the profile
	playerProfiles[player] = profile
	
	-- Update profile with current player info
	profile.playerId = tostring(player.UserId)
	
	-- Update login time and persist
	ProfileSchema.UpdateLoginTime(profile)
	local saveSuccess = ProfileManager.SaveProfile(player.UserId, profile)
	if saveSuccess then
		LogInfo(player, "Saved profile for user: %d", player.UserId)
	else
		LogWarning(player, "Failed to save profile for user: %d", player.UserId)
	end
	
	-- Ensure valid default deck if missing
	AssignStarterDeckIfNeeded(profile, player.UserId)
	
	-- Start autosave if not already running
	if not autosaveTasks[player] then
		StartAutosave(player)
	end
	
	LogInfo(player, "Profile lazy loaded successfully")
	return profile
end

-- Initialize service
function PlayerDataService.Init()
	-- Idempotency check
	if isShuttingDown ~= nil then
		LogInfo(nil, "PlayerDataService already initialized, skipping")
		return
	end
	
	-- Initialize state
	isShuttingDown = false
	
	LogInfo(nil, "Initializing PlayerDataService...")
	
	-- Connect to player events
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
	
	-- Connect to shutdown event
	game:BindToClose(OnBindToClose)
	
	-- Handle players already present (Studio timing quirk)
	for _, player in ipairs(Players:GetPlayers()) do
		OnPlayerAdded(player)
	end
	
	LogInfo(nil, "PlayerDataService initialized successfully")
end

-- Initialization moved to ServerBootstrap

return PlayerDataService
