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
	"card_100",     -- Monkey D. Luffy
	"card_200",     -- Roronoa Zoro
	"card_300",     -- Rock Lee
	"card_500",     -- Sanji
	"card_600",     -- Tenten
	"card_700"      -- Koby
}

-- Cache for loaded profiles
local profileCache = {}

-- Card ID migration mapping (old -> new)
local CARD_ID_MIGRATION = {
	["dps_001"] = "card_100",
	["dps_002"] = "card_500", 
	["dps_003"] = "card_800",
	["dps_004"] = "card_900",
	["support_001"] = "card_600",
	["support_002"] = "card_700",
	["support_003"] = "card_1100",
	["support_004"] = "card_1300",
	["tank_001"] = "card_200",
	["tank_002"] = "card_300",
	["tank_003"] = "card_400",
	["tank_004"] = "card_1200"
}

-- Utility functions
local function GenerateProfileKey(userId)
	return string.format(ProfileManager.KEY_PATTERN:gsub("{userId}", tostring(userId)))
end

-- Migrate old card IDs to new ones
function ProfileManager.MigrateCardIds(profile)
	if not profile or not profile.collection then
		return profile
	end
	
	local migratedCollection = {}
	local migratedDeck = {}
	local hasChanges = false
	
	-- Migrate collection
	for cardId, entry in pairs(profile.collection) do
		local newCardId = CARD_ID_MIGRATION[cardId]
		if newCardId then
			print("🔄 Migrating card: " .. cardId .. " -> " .. newCardId)
			migratedCollection[newCardId] = entry
			hasChanges = true
		else
			-- Keep existing card if no migration needed
			migratedCollection[cardId] = entry
		end
	end
	
	-- Migrate deck
	if profile.deck then
		for i, cardId in ipairs(profile.deck) do
			local newCardId = CARD_ID_MIGRATION[cardId]
			if newCardId then
				print("🔄 Migrating deck card: " .. cardId .. " -> " .. newCardId)
				migratedDeck[i] = newCardId
				hasChanges = true
			else
				migratedDeck[i] = cardId
			end
		end
	end
	
	if hasChanges then
		print("🔄 Card ID migration completed")
		profile.collection = migratedCollection
		profile.deck = migratedDeck
	end
	
	return profile
end

-- Migrate lootbox rarities: "common" -> "uncommon"
function ProfileManager.MigrateLootboxRarities(profile)
	if not profile then
		return profile
	end
	
	local hasChanges = false
	
	-- Migrate lootboxes array
	if profile.lootboxes then
		for _, lootbox in ipairs(profile.lootboxes) do
			if lootbox.rarity == "common" then
				print("🔄 Migrating lootbox rarity: common -> uncommon")
				lootbox.rarity = "uncommon"
				hasChanges = true
			end
		end
	end
	
	-- Migrate pending lootbox
	if profile.pendingLootbox and profile.pendingLootbox.rarity == "common" then
		print("🔄 Migrating pending lootbox rarity: common -> uncommon")
		profile.pendingLootbox.rarity = "uncommon"
		hasChanges = true
	end
	
	if hasChanges then
		print("🔄 Lootbox rarity migration completed")
	end
	
	return profile
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
	-- Use shared DeckValidator (v2: enforces uniqueness, no collection count check, allows 0-6 cards)
	local isValid, errorMessage = DeckValidator.ValidateDeck(deck)
	if not isValid then
		return false, "Deck validation failed: " .. errorMessage
	end
	return true
end

-- Helper function to sort deck by slotNumber and assign to slots 1-6
local function SortDeckBySlotNumber(deckIds)
	if not deckIds or #deckIds == 0 then
		return {}
	end
	
	-- Create array of card data with slotNumber for sorting
	local cardData = {}
	for _, cardId in ipairs(deckIds) do
		local card = CardCatalog.GetCard(cardId)
		if card and card.slotNumber then
			table.insert(cardData, {
				cardId = cardId,
				slotNumber = card.slotNumber
			})
		else
			warn("ProfileManager: Card missing slotNumber:", cardId)
		end
	end
	
	-- Sort by slotNumber (ascending)
	table.sort(cardData, function(a, b)
		return a.slotNumber < b.slotNumber
	end)
	
	-- Create sorted deck array (slots 1-6 filled in order)
	local sortedDeck = {}
	for i = 1, math.min(#cardData, 6) do
		sortedDeck[i] = cardData[i].cardId
	end
	
	return sortedDeck
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
			-- Ensure playerId is a string
			profile.playerId = tostring(profile.playerId)
			-- Also migrate card IDs for v2 profiles with old card IDs
			profile = ProfileManager.MigrateCardIds(profile)
			-- Initialize playtime if missing (for existing v2 profiles)
			if not profile.playtime then
				profile.playtime = {
					totalTime = 0,
					lastSyncTime = os.time(),
					claimedRewards = {}
				}
			end
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
			
			-- Migrate old card IDs to new ones
			migratedProfile = ProfileManager.MigrateCardIds(migratedProfile)
			
			-- Migrate lootbox rarities: "common" -> "uncommon"
			migratedProfile = ProfileManager.MigrateLootboxRarities(migratedProfile)
			
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
			-- Initialize playtime if missing (for existing profiles without playtime data)
			if not profile.playtime then
				profile.playtime = {
					totalTime = 0,
					lastSyncTime = os.time(),
					claimedRewards = {}
				}
			end
			
			-- Initialize daily if missing (for existing profiles without daily data)
			if not profile.daily then
				profile.daily = {
					streak = 0,
					lastLogin = 0
				}
			end
			
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
		return DataStoreWrapper.UpdateAsync(ProfileManager.DATASTORE_NAME, profileKey, function(currentData)
			-- Return the new profile (replaces whatever was there before)
			return profile
		end)
	end)
	
	if success and result then
		-- Update cache only if the save actually succeeded
		-- Note: UpdateAsync returns nil when queued for later, so we check for result
		profileCache[profileKey] = profile
		print("✅ Saved profile for user:", userId)
		return true
	elseif success then
		-- UpdateAsync was queued (returned nil due to budget), still update cache
		-- The write will happen later via ProcessPendingWrites
		profileCache[profileKey] = profile
		warn("⚠️ Profile save queued for later (budget) for user:", userId)
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
	
	-- Sort deck by slotNumber to maintain proper slot assignment
	local sortedDeck = SortDeckBySlotNumber(newDeck)
	
	-- Validate deck against catalog (v2: enforces uniqueness, no collection count check, allows 0-6 cards)
	local isValid, errorMessage = ValidateDeckAgainstCatalog(sortedDeck)
	if not isValid then
		return false, errorMessage
	end
	
	-- Update the deck with sorted order
	profile.deck = sortedDeck
	
	-- Compute and update squad power
	profile.squadPower = ComputeSquadPower(profile)
	
	-- Save the profile
	local saveSuccess = ProfileManager.SaveProfile(userId, profile)
	if not saveSuccess then
		return false, "Failed to save profile"
	end
	
	return true
end

-- Level up a card (v2: atomic persistence)
function ProfileManager.LevelUpCard(userId, cardId, requiredCount, softAmount)
	userId = tostring(userId)
	local profile = ProfileManager.GetCachedProfile(userId)
	
	if not profile then
		return false, "Profile not loaded"
	end
	
	-- Validate card exists in collection
	local collectionEntry = profile.collection[cardId]
	if not collectionEntry then
		return false, "Card not in collection"
	end
	
	-- Validate sufficient resources
	if collectionEntry.count < requiredCount then
		return false, "Insufficient copies"
	end
	
	if profile.currencies.soft < softAmount then
		return false, "Insufficient soft currency"
	end
	
	-- Perform atomic level-up
	collectionEntry.count = collectionEntry.count - requiredCount
	collectionEntry.level = collectionEntry.level + 1
	profile.currencies.soft = profile.currencies.soft - softAmount
	
	-- Fix: If count becomes 0 after leveling up, set it to 1
	-- The leveled-up card itself is still owned (at the new level)
	-- This ensures the card remains available in the player's collection
	if collectionEntry.count <= 0 then
		collectionEntry.count = 1
	end
	
	-- Check if this card is in the active deck and recompute squad power
	local isInDeck = false
	for _, deckCardId in ipairs(profile.deck) do
		if deckCardId == cardId then
			isInDeck = true
			break
		end
	end
	
	if isInDeck then
		profile.squadPower = ComputeSquadPower(profile)
	end
	
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

-- Atomic profile update function
function ProfileManager.UpdateProfile(userId, updateFunction)
	userId = tostring(userId)
	
	-- Load the profile
	local profile = ProfileManager.LoadProfile(userId)
	if not profile then
		return false, "Profile not found"
	end
	
	-- Apply the update function
	local success, result = pcall(updateFunction, profile)
	if not success then
		return false, "Update function failed: " .. tostring(result)
	end
	
	-- If the update function returned a profile, use it
	if result and type(result) == "table" then
		profile = result
	elseif result == nil then
		return false, "Update function returned nil"
	end
	
	-- Ensure playerId is still valid after update
	if not profile.playerId or type(profile.playerId) ~= "string" then
		warn("Profile playerId corrupted during update:", profile.playerId)
		profile.playerId = tostring(userId)
	end
	
	-- Update timestamp
	profile.updatedAt = os.time()
	
	-- Save the updated profile
	local saveSuccess = ProfileManager.SaveProfile(userId, profile)
	if not saveSuccess then
		return false, "Failed to save profile"
	end
	
	return true, profile
end

-- Flush pending DataStore operations
function ProfileManager.Flush()
	DataStoreWrapper.Flush()
end

return ProfileManager
