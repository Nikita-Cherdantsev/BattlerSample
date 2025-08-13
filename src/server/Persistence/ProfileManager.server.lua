local ProfileManager = {}

-- Services
local DataStoreService = game:GetService("DataStoreService")

-- Modules
local DataStoreWrapper = require(script.Parent.DataStoreWrapper)
local ProfileSchema = require(script.Parent.ProfileSchema)

-- Import shared modules for deck validation
local DeckValidator = require(game.ReplicatedStorage.Modules.Cards.DeckValidator)
local CardCatalog = require(game.ReplicatedStorage.Modules.Cards.CardCatalog)

-- Configuration
ProfileManager.DATASTORE_NAME = "anime_battler_profile"
ProfileManager.KEY_PATTERN = "player_{userId}_v1"

-- Safe default deck (using existing catalog IDs)
ProfileManager.DEFAULT_DECK = {
	"dps_001",      -- Recruit Fighter
	"support_001",  -- Novice Healer
	"tank_001",     -- Iron Guard
	"dps_001",      -- Recruit Fighter (duplicate)
	"support_001",  -- Novice Healer (duplicate)
	"tank_001"      -- Iron Guard (duplicate)
}

-- Cache for loaded profiles
local profileCache = {}

-- Utility functions
local function GenerateProfileKey(userId)
	return string.format(ProfileManager.KEY_PATTERN:gsub("{userId}", tostring(userId)))
end

local function IsProfileValid(profile)
	local isValid, errorMessage = ProfileSchema.ValidateProfile(profile)
	if not isValid then
		warn("Invalid profile:", errorMessage)
		return false
	end
	return true
end

local function ValidateDeckAgainstCatalog(deck)
	-- Use shared DeckValidator
	local isValid, errorMessage = DeckValidator.ValidateDeck(deck)
	if not isValid then
		return false, "Deck validation failed: " .. errorMessage
	end
	return true
end

-- Public API

-- Load a player profile
function ProfileManager.LoadProfile(userId)
	userId = tostring(userId)
	local profileKey = GenerateProfileKey(userId)
	
	-- Check cache first
	if profileCache[profileKey] then
		return profileCache[profileKey]
	end
	
	-- Try to load from DataStore
	local success, profile = pcall(function()
		return DataStoreWrapper.GetAsync(ProfileManager.DATASTORE_NAME, profileKey)
	end)
	
	if success and profile then
		-- Validate loaded profile
		if IsProfileValid(profile) then
			profileCache[profileKey] = profile
			print("✅ Loaded profile for user:", userId)
			return profile
		else
			warn("❌ Loaded profile for user", userId, "is invalid, creating new one")
		end
	end
	
	-- Create new profile if loading failed or profile was invalid
	local newProfile = ProfileSchema.CreateProfile(userId)
	
	-- Initialize with default deck and some starter cards
	newProfile.deck = ProfileManager.DEFAULT_DECK
	
	-- Add starter cards to collection
	for _, cardId in ipairs(ProfileManager.DEFAULT_DECK) do
		ProfileSchema.AddCardsToCollection(newProfile, cardId, 1)
	end
	
	-- Validate the new profile
	if not IsProfileValid(newProfile) then
		error("Failed to create valid default profile for user: " .. userId)
	end
	
	-- Save the new profile
	local saveSuccess = ProfileManager.SaveProfile(userId, newProfile)
	if not saveSuccess then
		warn("Failed to save new profile for user:", userId)
	end
	
	-- Cache the new profile
	profileCache[profileKey] = newProfile
	print("✅ Created new profile for user:", userId)
	
	return newProfile
end

-- Save a player profile
function ProfileManager.SaveProfile(userId, profile)
	userId = tostring(userId)
	local profileKey = GenerateProfileKey(userId)
	
	-- Validate profile before saving
	if not IsProfileValid(profile) then
		warn("Cannot save invalid profile for user:", userId)
		return false
	end
	
	-- Update last login time
	ProfileSchema.UpdateLoginTime(profile)
	
	-- Save to DataStore
	local success, result = pcall(function()
		return DataStoreWrapper.UpdateAsync(ProfileManager.DATASTORE_NAME, profileKey, function()
			return profile
		end)
	end)
	
	if success then
		-- Update cache
		profileCache[profileKey] = profile
		print("✅ Saved profile for user:", userId)
		return true
	else
		warn("❌ Failed to save profile for user:", userId, "Error:", result)
		return false
	end
end

-- Get profile from cache (doesn't load from DataStore)
function ProfileManager.GetCachedProfile(userId)
	userId = tostring(userId)
	local profileKey = GenerateProfileKey(userId)
	return profileCache[profileKey]
end

-- Update deck with validation
function ProfileManager.UpdateDeck(userId, newDeck)
	userId = tostring(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	
	if not profile then
		return false, "Profile not loaded"
	end
	
	-- Validate deck against catalog
	local isValid, errorMessage = ValidateDeckAgainstCatalog(newDeck)
	if not isValid then
		return false, errorMessage
	end
	
	-- Check if player has the cards
	local hasEnough, errorMessage = ProfileSchema.HasEnoughCardsForDeck(profile, newDeck)
	if not hasEnough then
		return false, errorMessage
	end
	
	-- Update the deck
	profile.deck = newDeck
	
	-- Save the profile
	local saveSuccess = ProfileManager.SaveProfile(userId, profile)
	if not saveSuccess then
		return false, "Failed to save profile"
	end
	
	return true
end

-- Add cards to collection
function ProfileManager.AddCardsToCollection(userId, cardId, count)
	userId = tostring(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	
	if not profile then
		return false, "Profile not loaded"
	end
	
	-- Validate card ID exists in catalog
	if not CardCatalog.IsValidCardId(cardId) then
		return false, "Invalid card ID: " .. cardId
	end
	
	-- Add cards
	local success = ProfileSchema.AddCardsToCollection(profile, cardId, count)
	if not success then
		return false, "Failed to add cards to collection"
	end
	
	-- Save the profile
	local saveSuccess = ProfileManager.SaveProfile(userId, profile)
	if not saveSuccess then
		return false, "Failed to save profile"
	end
	
	return true
end

-- Remove cards from collection
function ProfileManager.RemoveCardsFromCollection(userId, cardId, count)
	userId = tostring(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	
	if not profile then
		return false, "Profile not loaded"
	end
	
	-- Remove cards
	local success, errorMessage = ProfileSchema.RemoveCardsFromCollection(profile, cardId, count)
	if not success then
		return false, errorMessage
	end
	
	-- Save the profile
	local saveSuccess = ProfileManager.SaveProfile(userId, profile)
	if not saveSuccess then
		return false, "Failed to save profile"
	end
	
	return true
end

-- Update login streak
function ProfileManager.UpdateLoginStreak(userId, increment)
	userId = tostring(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	
	if not profile then
		return false, "Profile not loaded"
	end
	
	if increment then
		ProfileSchema.IncrementLoginStreak(profile)
	else
		ProfileSchema.ResetLoginStreak(profile)
	end
	
	-- Save the profile
	local saveSuccess = ProfileManager.SaveProfile(userId, profile)
	if not saveSuccess then
		return false, "Failed to save profile"
	end
	
	return true
end

-- Add currency
function ProfileManager.AddCurrency(userId, currencyType, amount)
	userId = tostring(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	
	if not profile then
		return false, "Profile not loaded"
	end
	
	-- Add currency
	local success, errorMessage = ProfileSchema.AddCurrency(profile, currencyType, amount)
	if not success then
		return false, errorMessage
	end
	
	-- Save the profile
	local saveSuccess = ProfileManager.SaveProfile(userId, profile)
	if not saveSuccess then
		return false, "Failed to save profile"
	end
	
	return true
end

-- Remove currency
function ProfileManager.RemoveCurrency(userId, currencyType, amount)
	userId = tostring(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	
	if not profile then
		return false, "Profile not loaded"
	end
	
	-- Remove currency
	local success, errorMessage = ProfileSchema.RemoveCurrency(profile, currencyType, amount)
	if not success then
		return false, errorMessage
	end
	
	-- Save the profile
	local saveSuccess = ProfileManager.SaveProfile(userId, profile)
	if not saveSuccess then
		return false, "Failed to save profile"
	end
	
	return true
end

-- Get profile statistics
function ProfileManager.GetProfileStats(userId)
	userId = tostring(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	
	if not profile then
		return nil
	end
	
	return ProfileSchema.GetProfileStats(profile)
end

-- Clear profile from cache
function ProfileManager.ClearCache(userId)
	userId = tostring(userId)
	local profileKey = GenerateProfileKey(userId)
	profileCache[profileKey] = nil
end

-- Get cache status
function ProfileManager.GetCacheStatus()
	local cachedProfiles = 0
	for _ in pairs(profileCache) do
		cachedProfiles = cachedProfiles + 1
	end
	
	return {
		cachedProfiles = cachedProfiles,
		datastoreName = ProfileManager.DATASTORE_NAME,
		keyPattern = ProfileManager.KEY_PATTERN
	}
end

-- Flush pending DataStore operations
function ProfileManager.Flush()
	DataStoreWrapper.Flush()
end

return ProfileManager
