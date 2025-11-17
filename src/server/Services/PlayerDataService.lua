local PlayerDataService = {}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Modules
local ProfileManager = require(game.ServerScriptService:WaitForChild("Persistence"):WaitForChild("ProfileManager"))
local ProfileSchema = require(game.ServerScriptService:WaitForChild("Persistence"):WaitForChild("ProfileSchema"))
local DeckValidator = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("DeckValidator"))
local CardCatalog = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("CardCatalog"))
local CardLevels = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("CardLevels"))
local CardStats = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("CardStats"))

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

local function RoundToDecimals(value, decimals)
	if type(value) ~= "number" then
		return 0
	end
	decimals = decimals or 0
	local multiplier = 10 ^ decimals
	return math.floor(value * multiplier + 0.5) / multiplier
end

local function ValidateDeck(deck)
	-- Use shared DeckValidator (v2: enforces uniqueness, no collection count check)
	local isValid, errorMessage = DeckValidator.ValidateDeck(deck)
	if not isValid then
		return false, "Deck validation failed: " .. errorMessage
	end
	return true
end

-- Note: Starter deck assignment removed - players now start with empty deck

local function SafeSaveProfile(player)
	if not player then
		return false, "No player specified"
	end
	
	-- Use ProfileManager as single source of truth
	local profile = ProfileManager.GetCachedProfile(player.UserId)
	if not profile then
		-- Try to load if not cached
		profile = ProfileManager.LoadProfile(player.UserId)
		if not profile then
			LogWarning(player, "No profile to save")
			return false, "No profile to save"
		end
	end
	
	local success = ProfileManager.SaveProfile(player.UserId, profile)
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
		while player and not isShuttingDown do
			task.wait(AUTOSAVE_INTERVAL)
			
			if not player then
				break
			end
			
			-- Check if profile still exists in ProfileManager cache
			local profile = ProfileManager.GetCachedProfile(player.UserId)
			if not profile then
				-- Profile not loaded, stop autosave
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
	
	-- Update profile with current player info and login time atomically
	local success, updatedProfile = ProfileManager.UpdateProfile(player.UserId, function(profile)
		profile.playerId = tostring(player.UserId)
		ProfileSchema.UpdateLoginTime(profile)
		return profile
	end)
	
	if success and updatedProfile then
		-- Sync local cache with updated profile
		playerProfiles[player] = updatedProfile
		LogInfo(player, "Saved profile for user: %d", player.UserId)
	else
		LogWarning(player, "Failed to save profile for user: %d", player.UserId)
	end
	
	-- Note: No longer assigning starter deck - players start with empty deck
	
	-- Start autosave
	StartAutosave(player)
	
	-- Fetch regional prices for shop (async, non-blocking)
	local ShopService = require(script.Parent.ShopService)
	if ShopService and ShopService.FetchRegionalPricesForPlayer then
		ShopService.FetchRegionalPricesForPlayer(player)
	end
	
	-- Get final profile for logging (use updated profile if available)
	local finalProfile = updatedProfile or profile
	local stats = ProfileManager.GetProfileStats(player.UserId)
	LogInfo(player, "Profile loaded successfully. Collection: %d unique cards, Deck: %d cards", 
		stats and stats.uniqueCards or 0, finalProfile and #finalProfile.deck or 0)
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
	
	-- CRITICAL: Get profile from ProfileManager (single source of truth) to ensure latest data
	local profile = ProfileManager.GetCachedProfile(player.UserId)
	if not profile then
		-- Fallback to playerProfiles if GetCachedProfile returns nil
		profile = playerProfiles[player]
		if not profile then
			return nil
		end
	end
	
	-- Return a copy to prevent external modification
	return {
		playerId = profile.playerId,
		createdAt = profile.createdAt,
		lastLoginAt = profile.lastLoginAt,
		loginStreak = profile.loginStreak,
		collection = profile.collection and (function()
			local cloned = {}
			for k, v in pairs(profile.collection) do
				cloned[k] = v
			end
			return cloned
		end)() or {},
		deck = profile.deck and (function()
			local cloned = {}
			for i, v in ipairs(profile.deck) do
				cloned[i] = v
			end
			return cloned
		end)() or {},
		currencies = {
			soft = profile.currencies.soft,
			hard = profile.currencies.hard
		},
		favoriteLastSeen = profile.favoriteLastSeen,
		tutorialStep = profile.tutorialStep,
		squadPower = profile.squadPower,
		lootboxes = profile.lootboxes and (function()
			local cloned = {}
			for i, v in ipairs(profile.lootboxes) do
				cloned[i] = v
			end
			return cloned
		end)() or {}
	}
end

-- Set player deck (v2: no collection count validation)
function PlayerDataService.SetDeck(player, deckIds)
	if not player or not playerProfiles[player] then
		return false, "Player profile not loaded"
	end
	
	-- Validate deck structure (v2: enforces uniqueness, no collection count check)
	local isValid, errorMessage = ValidateDeck(deckIds)
	if not isValid then
		return false, errorMessage
	end
	
	-- Update deck atomically (ProfileManager handles squad power computation)
	local success = ProfileManager.UpdateDeck(player.UserId, deckIds)
	if success then
		-- Sync local cache with ProfileManager (single source of truth)
		local updatedProfile = ProfileManager.GetCachedProfile(player.UserId)
		if updatedProfile then
			playerProfiles[player] = updatedProfile
			LogInfo(player, "Deck updated successfully, squad power: %.1f", updatedProfile.squadPower)
		else
			LogWarning(player, "Failed to get updated profile after deck update")
		end
		return true
	else
		LogWarning(player, "Failed to update deck")
		return false, "Failed to persist deck"
	end
end

-- Level up a card (v2: atomic persistence, squad power recomputation)
function PlayerDataService.LevelUpCard(player, cardId)
	if not player or not playerProfiles[player] then
		return false, "Player profile not loaded"
	end
	
	-- CRITICAL: Get profile from ProfileManager (single source of truth) instead of playerProfiles
	-- This ensures we always use the latest data, especially after GrantCards operations
	local profile = ProfileManager.GetCachedProfile(player.UserId)
	if not profile then
		-- Fallback to playerProfiles if GetCachedProfile returns nil
		profile = playerProfiles[player]
		if not profile then
			return false, "Player profile not loaded"
		end
	end
	
	-- Validation 1: Card exists in catalog
	local card = CardCatalog.GetCard(cardId)
	if not card then
		return false, "Card ID not found in catalog: " .. tostring(cardId)
	end
	
	-- Validation 2: Player owns this card
	local collectionEntry = profile.collection[cardId]
	if not collectionEntry then
		return false, "CARD_NOT_OWNED"
	end
	
	-- Validation 3: Current level < 7
	if collectionEntry.level >= CardLevels.MAX_LEVEL then
		return false, "LEVEL_MAXED"
	end
	
	-- Validation 4: Check next level cost
	local nextLevel = collectionEntry.level + 1
	local cost = CardLevels.GetLevelCost(nextLevel, card.rarity)
	if not cost then
		return false, "Invalid level cost for level " .. nextLevel
	end
	
	-- Validation 5: Sufficient copies
	if collectionEntry.count < cost.requiredCount then
		return false, "INSUFFICIENT_COPIES"
	end
	
	-- Validation 6: Sufficient soft currency
	if profile.currencies.soft < cost.softAmount then
		return false, "INSUFFICIENT_SOFT"
	end
	
	-- Perform atomic level-up via ProfileManager
	local success = ProfileManager.LevelUpCard(player.UserId, cardId, cost.requiredCount, cost.softAmount)
	if success then
		-- Sync local cache with ProfileManager (single source of truth)
		local updatedProfile = ProfileManager.GetCachedProfile(player.UserId)
		if not updatedProfile then
			return false, "Failed to refresh profile after level-up"
		end
		playerProfiles[player] = updatedProfile
		
		LogInfo(player, "Card %s leveled up to level %d (cost: %d copies, %d soft)", 
			cardId, updatedProfile.collection[cardId].level, cost.requiredCount, cost.softAmount)
		return true
	else
		LogWarning(player, "Failed to persist level-up for card %s", cardId)
		return false, "INTERNAL"
	end
end

-- Grant cards to player (v2 format)
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
		-- Sync local cache with ProfileManager (single source of truth)
		local updatedProfile = ProfileManager.GetCachedProfile(player.UserId)
		if updatedProfile then
			playerProfiles[player] = updatedProfile
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

-- Get player collection (v2 format)
function PlayerDataService.GetCollection(player)
	if not player or not playerProfiles[player] then
		return nil
	end
	
	-- CRITICAL: Get profile from ProfileManager (single source of truth) to ensure latest data
	local profile = ProfileManager.GetCachedProfile(player.UserId)
	if not profile then
		-- Fallback to playerProfiles if GetCachedProfile returns nil
		profile = playerProfiles[player]
		if not profile then
			return nil
		end
	end
	
	-- Return a copy to prevent external modification
	local collection = profile.collection
	local copy = {}
	for k, v in pairs(collection) do
		copy[k] = v
	end
	return copy
end

-- Get login information
function PlayerDataService.GetLoginInfo(player)
	if not player or not playerProfiles[player] then
		return nil
	end
	
	-- CRITICAL: Get profile from ProfileManager (single source of truth) to ensure latest data
	local profile = ProfileManager.GetCachedProfile(player.UserId)
	if not profile then
		-- Fallback to playerProfiles if GetCachedProfile returns nil
		profile = playerProfiles[player]
		if not profile then
			return nil
		end
	end
	return {
		lastLoginAt = profile.lastLoginAt,
		loginStreak = profile.loginStreak
	}
end

-- Helper function to get today's date key in UTC
local function todayKeyUTC()
	return os.date("!%Y-%m-%d")
end

-- Bump login streak (v2: simplified logic without meta field)
function PlayerDataService.BumpLoginStreak(player)
	if not player then
		return false, "Player not specified"
	end
	
	-- Use ProfileManager as single source of truth
	local profile = ProfileManager.GetCachedProfile(player.UserId)
	if not profile then
		profile = ProfileManager.LoadProfile(player.UserId)
		if not profile then
			return false, "Player profile not loaded"
		end
	end
	
	local today = todayKeyUTC()
	
	LogInfo(player, "BumpLoginStreak called. Current streak: %d, last bump date: %s", 
		profile.loginStreak or 0, profile.favoriteLastSeen and os.date("!%Y-%m-%d", profile.favoriteLastSeen) or "never")
	
	-- Check if already bumped today (using favoriteLastSeen as a proxy for last bump date)
	if profile.favoriteLastSeen then
		local lastBumpDate = os.date("!%Y-%m-%d", profile.favoriteLastSeen)
		if lastBumpDate == today then
			LogInfo(player, "Login streak already bumped today: %d", profile.loginStreak or 0)
			return true, profile.loginStreak
		end
	end
	
	-- Use atomic UpdateProfile to ensure consistency
	local oldStreak = profile.loginStreak or 0
	local success, updatedProfile = ProfileManager.UpdateProfile(player.UserId, function(profile)
		profile.loginStreak = (profile.loginStreak or 0) + 1
		profile.favoriteLastSeen = os.time() -- Use current time as last bump date
		return profile
	end)
	
	if success and updatedProfile then
		-- Sync local cache
		playerProfiles[player] = updatedProfile
		LogInfo(player, "Streak updated: %d -> %d, date set to: %s", oldStreak, updatedProfile.loginStreak, today)
		LogInfo(player, "Login streak bumped to %d and saved successfully", updatedProfile.loginStreak)
		return true, updatedProfile.loginStreak
	else
		LogWarning(player, "Failed to save profile after streak bump")
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
	
	-- Note: Login time update and save is handled in OnPlayerAdded
	-- Don't duplicate save here to avoid race conditions with cross-server sync
	
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
