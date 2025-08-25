local ProfileManager = {}

-- Services
local DataStoreService = game:GetService("DataStoreService")

-- Modules
local DataStoreWrapper = require(script.Parent:WaitForChild("DataStoreWrapper"))
local ProfileSchema = require(script.Parent:WaitForChild("ProfileSchema"))

-- Import shared modules for deck validation and squad power computation
local DeckValidator = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("DeckValidator"))
local CardCatalog = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("CardCatalog"))
local CardStats = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Cards"):WaitForChild("CardStats"))

-- Configuration
ProfileManager.DATASTORE_NAME = "anime_battler_profile"
ProfileManager.KEY_PATTERN = "player_{userId}_v2"  -- Updated to v2

-- Safe default deck (using existing catalog IDs, no duplicates)
ProfileManager.DEFAULT_DECK = {
	"dps_001",      -- Recruit Fighter
	"support_001",  -- Novice Healer
	"tank_001",     -- Iron Guard
	"dps_002",      -- Veteran Warrior
	"support_002",  -- Battle Cleric
	"tank_002"      -- Steel Defender
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
	-- Use shared DeckValidator (v2: enforces uniqueness, no collection count check)
	local isValid, errorMessage = DeckValidator.ValidateDeck(deck)
	if not isValid then
		return false, "Deck validation failed: " .. errorMessage
	end
	return true
end

-- Compute squad power from deck and collection levels
local function ComputeSquadPower(profile)
	local totalPower = 0
	
	for _, cardId in ipairs(profile.deck) do
		-- Get card level from collection (default to 1 if not found)
		local cardEntry = profile.collection[cardId]
		local level = cardEntry and cardEntry.level or 1
		
		-- Compute power for this card at its current level
		local cardPower = CardStats.ComputeCardPower(cardId, level)
		totalPower = totalPower + cardPower
	end
	
	return totalPower
end

-- Migrate profile if needed
local function MigrateProfileIfNeeded(profile)
	-- Check if profile needs migration
	-- Also check if it's already v2 format but missing version field
	local needsMigration = not profile.version or profile.version == "v1"
	
	-- If no version but has v2 fields, it's already v2
	if not profile.version and profile.collection then
		local hasV2Format = false
		for cardId, entry in pairs(profile.collection) do
			if type(entry) == "table" and entry.count and entry.level then
				hasV2Format = true
				break
			end
		end
		
		if hasV2Format then
			print("🔄 Profile missing version field but has v2 format, adding version")
			profile.version = "v2"
			return profile
		end
	end
	
	if needsMigration then
		print("🔄 Migrating profile from v1 to v2")
		
		-- Debug: Log the original profile collection
		if profile.collection then
			print("Original collection:")
			for cardId, count in pairs(profile.collection) do
				print("  " .. cardId .. ": " .. tostring(count))
			end
		end
		
		local migratedProfile = ProfileSchema.MigrateV1ToV2(profile)
		if migratedProfile then
			migratedProfile.version = "v2"
			
			-- Debug: Log the migrated profile collection
			if migratedProfile.collection then
				print("Migrated collection:")
				for cardId, entry in pairs(migratedProfile.collection) do
					print("  " .. cardId .. ": count=" .. tostring(entry.count) .. ", level=" .. tostring(entry.level))
				end
			end
			
			return migratedProfile
		else
			warn("❌ Failed to migrate profile from v1 to v2")
			return nil
		end
	end
	
	return profile
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
		-- Migrate if needed
		profile = MigrateProfileIfNeeded(profile)
		
		-- Validate loaded profile
		if profile and IsProfileValid(profile) then
			-- Compute squad power if not set
			if profile.squadPower == 0 then
				profile.squadPower = ComputeSquadPower(profile)
			end
			
			profileCache[profileKey] = profile
			print("✅ Loaded profile for user:", userId)
			return profile
		else
			warn("❌ Loaded profile for user", userId, "is invalid, creating new one")
		end
	end
	
	-- Create new profile if loading failed or profile was invalid
	local newProfile = ProfileSchema.CreateProfile(userId)
	
	-- Initialize with default deck
	newProfile.deck = ProfileManager.DEFAULT_DECK
	
	-- Add starter cards to collection (v2 format)
	for _, cardId in ipairs(ProfileManager.DEFAULT_DECK) do
		ProfileSchema.AddCardsToCollection(newProfile, cardId, 1)
	end
	
	-- Compute initial squad power
	newProfile.squadPower = ComputeSquadPower(newProfile)
	
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

-- Update deck with validation (v2: no collection count validation)
function ProfileManager.UpdateDeck(userId, newDeck)
	userId = tostring(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	
	if not profile then
		return false, "Profile not loaded"
	end
	
	-- Validate deck against catalog (v2: enforces uniqueness, no collection count check)
	local isValid, errorMessage = ValidateDeckAgainstCatalog(newDeck)
	if not isValid then
		return false, errorMessage
	end
	
	-- Update the deck
	profile.deck = newDeck
	
	-- Compute and update squad power
	profile.squadPower = ComputeSquadPower(profile)
	
	-- Save the profile
	local saveSuccess = ProfileManager.SaveProfile(userId, profile)
	if not saveSuccess then
		return false, "Failed to save profile"
	end
	
	return true
end

-- Add cards to collection (v2 format)
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

-- Remove cards from collection (v2 format)
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

-- Force save a profile (test-only, Studio only)
function ProfileManager.ForceSave(userId)
	if not game:GetService("RunService"):IsStudio() then
		warn("ForceSave is only available in Studio")
		return false
	end
	
	userId = tostring(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	
	if not profile then
		return false, "Profile not loaded"
	end
	
	return ProfileManager.SaveProfile(userId, profile)
end

-- Flush pending DataStore operations
function ProfileManager.Flush()
	DataStoreWrapper.Flush()
end

return ProfileManager
