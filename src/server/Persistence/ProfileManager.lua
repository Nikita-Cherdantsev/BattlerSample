local ProfileManager = {}

-- Services
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")

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
ProfileManager.MEMORYSTORE_NAME = "profile_versions"
ProfileManager.MESSAGING_TOPIC = "profile_updates"

-- Safe default deck (using existing catalog IDs, no duplicates)
ProfileManager.DEFAULT_DECK = {
	"card_100",     -- Monkey D. Luffy
	"card_200",     -- Roronoa Zoro
	"card_300",     -- Rock Lee
	"card_500",     -- Sanji
	"card_600",     -- Tenten
	"card_700"      -- Koby
}

-- Cache for loaded profiles with version tracking
local profileCache = {}  -- profileKey -> {profile = {...}, version = timestamp}
local memoryStore = nil
local messageSubscription = nil
local serverId = HttpService:GenerateGUID(false)  -- Unique ID for this server instance

-- Utility functions (must be defined before InitializeSyncServices for use in callbacks)
local function GenerateProfileKey(userId)
	return string.format(ProfileManager.KEY_PATTERN:gsub("{userId}", tostring(userId)))
end

-- Initialize MemoryStore and MessagingService
local function InitializeSyncServices()
	-- Initialize MemoryStore
	local success, store = pcall(function()
		return MemoryStoreService:GetSortedMap(ProfileManager.MEMORYSTORE_NAME)
	end)
	
	if success and store then
		memoryStore = store
		print("✅ MemoryStore initialized for profile synchronization")
	else
		warn("⚠️ Failed to initialize MemoryStore:", store)
	end
	
	-- Subscribe to profile update messages
	local success2, subscription = pcall(function()
		return MessagingService:SubscribeAsync(ProfileManager.MESSAGING_TOPIC, function(message)
			local data = message.Data
			if data and data.userId and data.version and data.serverId ~= serverId then
				-- Profile was updated on another server
				local profileKey = GenerateProfileKey(data.userId)
				local cached = profileCache[profileKey]
				
				if cached and cached.version and cached.version < data.version then
					-- Our cached version is outdated, invalidate it
					print("🔄 Profile outdated for user:", data.userId, "cached version:", cached.version, "new version:", data.version)
					profileCache[profileKey] = nil
				end
			end
		end)
	end)
	
	if success2 and subscription then
		messageSubscription = subscription
		print("✅ MessagingService subscription initialized for profile synchronization")
	else
		warn("⚠️ Failed to subscribe to MessagingService:", subscription)
	end
end

-- Initialize on module load
InitializeSyncServices()

local function RoundToDecimals(value, decimals)
	if type(value) ~= "number" then
		return 0
	end
	decimals = decimals or 0
	local multiplier = 10 ^ decimals
	return math.floor(value * multiplier + 0.5) / multiplier
end

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

-- Get profile version from MemoryStore (returns timestamp or nil)
local function GetProfileVersion(userId)
	if not memoryStore then
		return nil
	end
	
	local profileKey = GenerateProfileKey(userId)
	local success, version = pcall(function()
		local result = memoryStore:GetAsync(profileKey)
		return result and result.version
	end)
	
	if success then
		return version
	end
	return nil
end

-- Update profile version in MemoryStore
local function UpdateProfileVersion(userId, version)
	if not memoryStore then
		return false
	end
	
	local profileKey = GenerateProfileKey(userId)
	local success = pcall(function()
		memoryStore:SetAsync(profileKey, {
			version = version,
			serverId = serverId,
			updatedAt = os.time()
		}, 3600)  -- TTL: 1 hour
	end)
	
	return success
end

-- Broadcast profile update to other servers
local function BroadcastProfileUpdate(userId, version)
	if not messageSubscription then
		return false
	end
	
	local success = pcall(function()
		MessagingService:PublishAsync(ProfileManager.MESSAGING_TOPIC, {
			userId = tostring(userId),
			version = version,
			serverId = serverId,
			timestamp = os.time()
		})
	end)
	
	return success
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
	
	return RoundToDecimals(totalPower, 1)
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

-- Load a player profile (always gets latest version from DataStore)
function ProfileManager.LoadProfile(userId)
	userId = tostring(userId)
	local profileKey = GenerateProfileKey(userId)
	
	-- Get latest version from MemoryStore
	local latestVersion = GetProfileVersion(userId)
	local currentTimestamp = os.time()
	
	-- Check cache - but only use it if version matches or cache is newer
	-- CRITICAL: If MemoryStore is not available or version is unknown, always reload from DataStore
	local cached = profileCache[profileKey]
	if cached then
		-- Only use cache if we can verify it's up-to-date
		if memoryStore and latestVersion then
			-- MemoryStore is working and we have version info - check if cache is valid
			if cached.version and cached.version >= latestVersion then
				-- Cache is still valid
				return cached.profile
			else
				-- Cache is outdated, clear it
				print("🔄 Cache outdated for user:", userId, "cached version:", cached.version, "latest version:", latestVersion, "reloading from DataStore")
				profileCache[profileKey] = nil
			end
		else
			-- MemoryStore not available or version unknown - cannot trust cache, reload from DataStore
			-- This ensures we always get the latest version from DataStore
			if not memoryStore then
				print("🔄 MemoryStore not available, forcing DataStore reload for user:", userId)
			else
				print("🔄 Version unknown in MemoryStore, forcing DataStore reload for user:", userId)
			end
			profileCache[profileKey] = nil
		end
	end
	
	-- Try to load from DataStore (always get fresh data)
	local success, profile = pcall(function()
		return DataStoreWrapper.GetAsync(ProfileManager.DATASTORE_NAME, profileKey)
	end)
	
	if success and profile then
		-- Migrate if needed
		profile = MigrateProfileIfNeeded(profile)

		if profile then
			if type(profile.totalRobuxSpent) ~= "number" then
				profile.totalRobuxSpent = 0
			end
			if type(profile.npcWins) ~= "number" then
				profile.npcWins = 0
			end
			if type(profile.followRewardClaimed) ~= "boolean" then
				profile.followRewardClaimed = false
			end
			if type(profile.bossWins) ~= "table" then
				profile.bossWins = {}
			end
		end
		
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
			
			-- Use updatedAt as version if available, otherwise use current timestamp
			local profileVersion = profile.updatedAt or currentTimestamp
			
			-- Cache the profile with version
			profileCache[profileKey] = {
				profile = profile,
				version = profileVersion
			}
			
			-- Update MemoryStore with this version (if it's newer)
			if not latestVersion or profileVersion > latestVersion then
				UpdateProfileVersion(userId, profileVersion)
			end
			
			print("✅ Loaded profile for user:", userId, "version:", profileVersion)
			return profile
		else
			warn("❌ Loaded profile for user", userId, "is invalid, creating new one")
		end
	end
	
	-- Create new profile if loading failed or profile was invalid
	local newProfile = ProfileSchema.CreateProfile(userId)
	
	-- Grant beginner lootbox to new players (add directly to profile before saving)
	local BoxTypes = require(game.ReplicatedStorage.Modules.Loot.BoxTypes)
	local BoxRoller = require(game.ReplicatedStorage.Modules.Loot.BoxRoller)
	
	-- Ensure lootboxes array exists
	if not newProfile.lootboxes then
		newProfile.lootboxes = {}
	end
	
	-- Add beginner lootbox to first slot (already ready to open)
	local now = os.time()
	local beginnerBox = {
		id = BoxRoller.GenerateBoxId(),
		rarity = BoxTypes.BoxRarity.BEGINNER,
		state = BoxTypes.BoxState.READY,  -- Ready to open immediately
		seed = BoxRoller.GenerateSeed(),
		source = "starter",
		startedAt = now,
		unlocksAt = now  -- Already unlocked
	}
	newProfile.lootboxes[1] = beginnerBox
	print("✅ Granted beginner lootbox (ready to open) to new player:", userId)
	
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
	
	-- Cache the new profile with version
	local newVersion = newProfile.updatedAt or currentTimestamp
	profileCache[profileKey] = {
		profile = newProfile,
		version = newVersion
	}
	
	-- Update MemoryStore with new version
	UpdateProfileVersion(userId, newVersion)
	
	print("✅ Created new profile for user:", userId, "version:", newVersion)
	
	return newProfile
end

-- Save a player profile (with cross-server synchronization)
function ProfileManager.SaveProfile(userId, profile)
	userId = tostring(userId)
	local profileKey = GenerateProfileKey(userId)
	
	-- Validate profile before saving
	if not IsProfileValid(profile) then
		warn("Cannot save invalid profile for user:", userId)
		return false
	end
	
	-- NOTE: UpdateLoginTime should NOT be called here
	-- It should only be called explicitly when player joins (OnPlayerAdded)
	-- Calling it here would update lastLoginAt on every save (including autosave)
	
	-- Update timestamp for version tracking
	local currentTimestamp = os.time()
	profile.updatedAt = currentTimestamp
	
	-- CRITICAL: Get latest version from MemoryStore BEFORE calling UpdateAsync
	-- We cannot call MemoryStore inside the updateFunction callback (it causes "Callbacks cannot yield" error)
	local latestVersion = GetProfileVersion(userId)
	
	-- Save to DataStore with version-aware update
	local success, result = pcall(function()
		return DataStoreWrapper.UpdateAsync(ProfileManager.DATASTORE_NAME, profileKey, function(currentData)
			-- CRITICAL: Do NOT call GetProfileVersion or any yielding operations here!
			-- The callback function cannot yield, so we use the latestVersion captured before UpdateAsync
			-- NOTE: For pending writes, latestVersion may be outdated, but currentData.updatedAt is always accurate
			
			-- Determine the actual latest version from both sources
			-- CRITICAL: Always prioritize currentData.updatedAt as it's the source of truth from DataStore
			-- This ensures that even for pending writes executed later, we check the actual saved version
			local actualLatestVersion = currentTimestamp
			if currentData and currentData.updatedAt then
				-- DataStore has the actual saved version - this is the most reliable source
				-- This is especially important for pending writes that execute later
				actualLatestVersion = currentData.updatedAt
			end
			-- If MemoryStore has a newer version (captured before UpdateAsync), use it
			-- NOTE: This may be outdated for pending writes, but currentData.updatedAt takes priority
			if latestVersion and latestVersion > actualLatestVersion then
				actualLatestVersion = latestVersion
			end
			
			-- If we're trying to save an older version, keep the newer one
			if actualLatestVersion > currentTimestamp then
				warn("⚠️ Attempted to save older version for user:", userId, 
					"currentTimestamp:", currentTimestamp, 
					"actualLatestVersion:", actualLatestVersion,
					"currentData.updatedAt:", currentData and currentData.updatedAt or "nil",
					"MemoryStore version:", latestVersion or "nil",
					"keeping newer version")
				-- If currentData exists, return it; otherwise return nil to keep existing data
				if currentData then
					return currentData
				else
					-- Return nil to keep existing data in DataStore (UpdateAsync will preserve it)
					return nil
				end
			end
			
			-- Return the new profile (replaces whatever was there before)
			return profile
		end)
	end)
	
	if success and result then
		-- Update was successful
		local savedVersion = result.updatedAt or currentTimestamp
		
		-- Check if we actually saved our version or if a newer version was kept
		if result.updatedAt and result.updatedAt > currentTimestamp then
			-- A newer version was kept (we tried to save older version)
			-- Update cache with the newer version that was saved
			profileCache[profileKey] = {
				profile = result,
				version = savedVersion
			}
			-- Don't update MemoryStore or broadcast - the version is already known
			warn("⚠️ Kept newer version for user:", userId, "version:", savedVersion)
			return true
		end
		
		-- Our version was saved successfully
		-- Update cache with saved version
		profileCache[profileKey] = {
			profile = result,
			version = savedVersion
		}
		
		-- Update MemoryStore with new version
		UpdateProfileVersion(userId, savedVersion)
		
		-- Broadcast update to other servers
		BroadcastProfileUpdate(userId, savedVersion)
		
		print("✅ Saved profile for user:", userId, "version:", savedVersion)
		return true
	elseif success then
		-- UpdateAsync was queued (returned nil due to budget)
		-- NOTE: MemoryStore and MessagingService are NOT updated here because the write hasn't completed yet
		-- The updateFunction will check for newer versions when it executes via ProcessPendingWrites
		-- This is a limitation: if the server shuts down before pending write completes, sync won't happen
		-- However, the next server to load the profile will get the latest version from DataStore
		profileCache[profileKey] = {
			profile = profile,
			version = currentTimestamp
		}
		warn("⚠️ Profile save queued for later (budget) for user:", userId, 
			"- sync services will update when write completes")
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
	local cached = profileCache[profileKey]
	return cached and cached.profile or nil
end

-- Update deck with validation (v2: no collection count validation)
function ProfileManager.UpdateDeck(userId, newDeck)
	userId = tostring(userId)
	
	-- Sort deck by slotNumber to maintain proper slot assignment
	local sortedDeck = SortDeckBySlotNumber(newDeck)
	
	-- Validate deck against catalog (v2: enforces uniqueness, no collection count check, allows 0-6 cards)
	local isValid, errorMessage = ValidateDeckAgainstCatalog(sortedDeck)
	if not isValid then
		return false, errorMessage
	end
	
	-- Update deck atomically using UpdateProfile
	local success, updatedProfile = ProfileManager.UpdateProfile(userId, function(profile)
		-- Update the deck with sorted order
		profile.deck = sortedDeck
		
		-- Compute and update squad power
		profile.squadPower = ComputeSquadPower(profile)
		
		return profile
	end)
	
	if not success then
		return false, "Failed to save profile"
	end
	
	return true
end

-- Level up a card (v2: atomic persistence)
function ProfileManager.LevelUpCard(userId, cardId, requiredCount, softAmount)
	userId = tostring(userId)
	
	-- Pre-validate using cached profile (for early error detection)
	local cachedProfile = ProfileManager.GetCachedProfile(userId)
	if not cachedProfile then
		return false, "Profile not loaded"
	end
	
	-- Validate card exists in collection
	local collectionEntry = cachedProfile.collection[cardId]
	if not collectionEntry then
		return false, "Card not in collection"
	end
	
	-- Validate sufficient resources
	if collectionEntry.count < requiredCount then
		return false, "Insufficient copies"
	end
	
	if cachedProfile.currencies.soft < softAmount then
		return false, "Insufficient soft currency"
	end
	
	-- Check if card is in deck (for squad power recomputation)
	local isInDeck = false
	for _, deckCardId in ipairs(cachedProfile.deck) do
		if deckCardId == cardId then
			isInDeck = true
			break
		end
	end
	
	-- Perform atomic level-up using UpdateProfile
	local success, updatedProfile = ProfileManager.UpdateProfile(userId, function(profile)
		-- Re-validate in atomic context (profile might have changed)
		local entry = profile.collection[cardId]
		if not entry then
			error("Card not in collection")
		end
		
		if entry.count < requiredCount then
			error("Insufficient copies")
		end
		
		if profile.currencies.soft < softAmount then
			error("Insufficient soft currency")
		end
		
		-- Perform level-up
		entry.count = entry.count - requiredCount
		entry.level = entry.level + 1
		profile.currencies.soft = profile.currencies.soft - softAmount
		
		-- Fix: If count becomes 0 after leveling up, set it to 1
		if entry.count <= 0 then
			entry.count = 1
		end
		
		-- Recompute squad power if card is in deck
		local cardInDeck = false
		for _, deckCardId in ipairs(profile.deck) do
			if deckCardId == cardId then
				cardInDeck = true
				break
			end
		end
		
		if cardInDeck then
			profile.squadPower = ComputeSquadPower(profile)
		end
		
		return profile
	end)
	
	if not success then
		return false, "Failed to save profile"
	end
	
	return true
end

-- Add cards to collection (v2 format)
function ProfileManager.AddCardsToCollection(userId, cardId, count)
	userId = tostring(userId)
	
	-- Validate card ID exists in catalog
	if not CardCatalog.IsValidCardId(cardId) then
		return false, "Invalid card ID: " .. cardId
	end
	
	-- Add cards atomically using UpdateProfile
	local success, updatedProfile = ProfileManager.UpdateProfile(userId, function(profile)
		local addSuccess = ProfileSchema.AddCardsToCollection(profile, cardId, count)
		if not addSuccess then
			error("Failed to add cards to collection")
		end
		return profile
	end)
	
	if not success then
		return false, "Failed to save profile"
	end
	
	return true
end

-- Remove cards from collection (v2 format)
function ProfileManager.RemoveCardsFromCollection(userId, cardId, count)
	userId = tostring(userId)
	
	-- Remove cards atomically using UpdateProfile
	local success, updatedProfile = ProfileManager.UpdateProfile(userId, function(profile)
		local removeSuccess, errorMessage = ProfileSchema.RemoveCardsFromCollection(profile, cardId, count)
		if not removeSuccess then
			error(errorMessage or "Failed to remove cards from collection")
		end
		return profile
	end)
	
	if not success then
		return false, "Failed to save profile"
	end
	
	return true
end

-- Update login streak
function ProfileManager.UpdateLoginStreak(userId, increment)
	userId = tostring(userId)
	
	-- Update login streak atomically using UpdateProfile
	local success, updatedProfile = ProfileManager.UpdateProfile(userId, function(profile)
		if increment then
			ProfileSchema.IncrementLoginStreak(profile)
		else
			ProfileSchema.ResetLoginStreak(profile)
		end
		return profile
	end)
	
	if not success then
		return false, "Failed to save profile"
	end
	
	return true
end

-- Add currency
function ProfileManager.AddCurrency(userId, currencyType, amount)
	userId = tostring(userId)
	
	-- Add currency atomically using UpdateProfile
	local success, updatedProfile = ProfileManager.UpdateProfile(userId, function(profile)
		local addSuccess, errorMessage = ProfileSchema.AddCurrency(profile, currencyType, amount)
		if not addSuccess then
			error(errorMessage or "Failed to add currency")
		end
		return profile
	end)
	
	if not success then
		return false, "Failed to save profile"
	end
	
	return true
end

-- Remove currency
function ProfileManager.RemoveCurrency(userId, currencyType, amount)
	userId = tostring(userId)
	
	-- Remove currency atomically using UpdateProfile
	local success, updatedProfile = ProfileManager.UpdateProfile(userId, function(profile)
		local removeSuccess, errorMessage = ProfileSchema.RemoveCurrency(profile, currencyType, amount)
		if not removeSuccess then
			error(errorMessage or "Failed to remove currency")
		end
		return profile
	end)
	
	if not success then
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
-- WARNING: This bypasses version checking and may overwrite newer data from other servers
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
	
	warn("⚠️ ForceSave: Bypassing version checks - may overwrite newer data from other servers")
	return ProfileManager.SaveProfile(userId, profile)
end

-- Atomic profile update function
function ProfileManager.UpdateProfile(userId, updateFunction)
	userId = tostring(userId)
	
	-- Load the profile (always gets latest)
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
