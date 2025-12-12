local ProfileSchema = {}

-- Profile version
ProfileSchema.VERSION = "v2"

-- Lootbox duration constants (in seconds)
ProfileSchema.LootboxDurations = {
	Uncommon = 7 * 60,     -- 7 minutes
	Rare = 30 * 60,        -- 30 minutes
	Epic = 120 * 60,       -- 120 minutes
	Legendary = 240 * 60   -- 240 minutes
}

-- Profile structure definition (v2)
ProfileSchema.Profile = {
	-- Basic player information
	playerId = "",           -- Roblox UserId (string)
	createdAt = 0,           -- Unix timestamp when profile was created
	lastLoginAt = 0,         -- Unix timestamp of last login
	loginStreak = 0,         -- Consecutive login days (for DailyHandler integration)
	
	-- Card collection (map: cardId -> { count: number, level: number })
	collection = {}, 
	
	-- Active deck (exactly 6 card IDs, no duplicates)
	deck = {},
	
	-- Optional currencies
	currencies = {
		soft = 0,             -- Soft currency (earned in-game)
		hard = 0              -- Hard currency (premium/Robux)
	},
	
	-- New v2 fields
	favoriteLastSeen = nil,  -- Unix seconds when player last claimed "Like" bonus (optional)
	tutorialStep = 0,        -- Tutorial progress (default 0)
	squadPower = 0,          -- Computed power of current deck
	npcWins = 0,             -- Total PvE (NPC) victories
	totalRobuxSpent = 0,     -- Lifetime Robux spent in shop (developer products)
	followRewardClaimed = false, -- Whether the follow reward has been claimed
	
	-- Boss difficulties (map: bossId -> difficulty string)
	-- Example: bossDifficulties["1"] = "easy" (for BossMode1Trigger)
	-- Difficulty levels: "easy", "normal", "hard", "nightmare", "hell"
	bossDifficulties = {},
	bossWins = {},           -- Map bossId -> victories
	
	-- Lootboxes (array of LootboxEntry, max 4, max 1 "Unlocking")
	lootboxes = {},
	
	-- Pending lootbox (when capacity is full)
	pendingLootbox = nil,
	
	-- Playtime data
	playtime = {
		totalTime = 0,           
		lastSyncTime = 0,         
		claimedRewards = {}       
	},
	
	-- Daily bonus data
	daily = {
		streak = 0,              -- Consecutive login days (0-7, resets if missed a day)
		lastLogin = 0            -- Unix timestamp of last login date
	},
	
	-- Promo codes tracking (map: code -> true)
	redeemedCodes = {},          -- Tracks which promo codes have been redeemed by the player
	
	-- Pending battle rewards (unclaimed rewards from battles)
	-- Format: { {type = "soft", amount = number}, {type = "lootbox", rarity = string} }
	pendingBattleRewards = {}    -- Array of unclaimed battle rewards
}

-- Lootbox entry structure
ProfileSchema.LootboxEntry = {
	id = "",                 -- Unique lootbox ID
	rarity = "",            -- "uncommon", "rare", "epic", "legendary"
	state = "",             -- "Idle", "Unlocking", "Ready", "Consumed"
	startedAt = nil,        -- Unix timestamp when unlocking started (optional)
	unlocksAt = nil,        -- Unix timestamp when unlocking ends (optional)
	seed = 0,               -- Seed for deterministic reward generation
	source = nil            -- Optional source identifier (optional)
}

-- Validation functions
function ProfileSchema.ValidateProfile(profile)
	if not profile then
		return false, "Profile is nil"
	end
	
	-- Check required fields
	if not profile.playerId or type(profile.playerId) ~= "string" then
		return false, "Invalid playerId"
	end
	
	if not profile.createdAt or type(profile.createdAt) ~= "number" then
		return false, "Invalid createdAt timestamp"
	end
	
	if not profile.lastLoginAt or type(profile.lastLoginAt) ~= "number" then
		return false, "Invalid lastLoginAt timestamp"
	end
	
	if not profile.loginStreak or type(profile.loginStreak) ~= "number" then
		return false, "Invalid loginStreak"
	end
	
	-- Check collection (v2: cardId -> { count, level })
	if not profile.collection or type(profile.collection) ~= "table" then
		return false, "Invalid collection"
	end
	
	-- Validate collection entries
	for cardId, entry in pairs(profile.collection) do
		if type(cardId) ~= "string" then
			return false, "Invalid card ID in collection"
		end
		
		if type(entry) ~= "table" then
			return false, "Invalid collection entry for " .. cardId
		end
		
		if type(entry.count) ~= "number" or entry.count < 0 then
			return false, "Invalid count for " .. cardId
		end
		
		if type(entry.level) ~= "number" or entry.level < 1 then
			return false, "Invalid level for " .. cardId
		end
	end
	
	-- Check deck
	if not profile.deck or type(profile.deck) ~= "table" then
		return false, "Invalid deck"
	end
	
	if #profile.deck > 6 then
		return false, "Deck cannot contain more than 6 cards"
	end
	
	-- Validate each card in deck
	for i, cardId in ipairs(profile.deck) do
		if type(cardId) ~= "string" or cardId == "" then
			return false, "Invalid card ID at position " .. i
		end
	end
	
	-- Check for duplicates in deck
	local seenCards = {}
	for i, cardId in ipairs(profile.deck) do
		if seenCards[cardId] then
			return false, "Duplicate card ID in deck: " .. cardId
		end
		seenCards[cardId] = true
	end
	
	-- Check currencies
	if not profile.currencies or type(profile.currencies) ~= "table" then
		return false, "Invalid currencies"
	end
	
	if type(profile.currencies.soft) ~= "number" then
		return false, "Invalid soft currency"
	end
	
	if type(profile.currencies.hard) ~= "number" then
		return false, "Invalid hard currency"
	end
	
	-- Check v2 fields
	if profile.favoriteLastSeen ~= nil and type(profile.favoriteLastSeen) ~= "number" then
		return false, "Invalid favoriteLastSeen"
	end
	
	if type(profile.tutorialStep) ~= "number" then
		return false, "Invalid tutorialStep"
	end
	
	if type(profile.squadPower) ~= "number" then
		return false, "Invalid squadPower"
	end

	if type(profile.npcWins) ~= "number" then
		return false, "Invalid npcWins"
	end

	if type(profile.totalRobuxSpent) ~= "number" then
		return false, "Invalid totalRobuxSpent"
	end

	if profile.followRewardClaimed ~= nil and type(profile.followRewardClaimed) ~= "boolean" then
		return false, "Invalid followRewardClaimed"
	end
	
	-- Check bossDifficulties (v2 field)
	if profile.bossDifficulties ~= nil then
		if type(profile.bossDifficulties) ~= "table" then
			return false, "Invalid bossDifficulties (must be table)"
		end
		
		-- Validate each boss difficulty entry
		for bossId, difficulty in pairs(profile.bossDifficulties) do
			if type(bossId) ~= "string" then
				return false, "Invalid boss ID in bossDifficulties"
			end
			if type(difficulty) ~= "string" then
				return false, "Invalid difficulty for boss " .. bossId
			end
			-- Validate difficulty value
			local validDifficulties = {
				["easy"] = true,
				["normal"] = true,
				["hard"] = true,
				["nightmare"] = true,
				["hell"] = true
			}
			if not validDifficulties[difficulty] then
				return false, "Invalid difficulty level '" .. difficulty .. "' for boss " .. bossId
			end
		end
	end

	if profile.bossWins ~= nil then
		if type(profile.bossWins) ~= "table" then
			return false, "Invalid bossWins (must be table)"
		end

		for bossId, wins in pairs(profile.bossWins) do
			if type(bossId) ~= "string" then
				return false, "Invalid boss ID in bossWins"
			end
			if type(wins) ~= "number" or wins < 0 then
				return false, "Invalid wins value for boss " .. bossId
			end
		end
	end
	
	-- Check lootboxes
	if not profile.lootboxes or type(profile.lootboxes) ~= "table" then
		return false, "Invalid lootboxes"
	end
	
	-- Check lootbox count (up to 4 slots)
	local lootboxCount = 0
	for i = 1, 4 do
		if profile.lootboxes[i] then
			lootboxCount = lootboxCount + 1
		end
	end
	
	if lootboxCount > 4 then
		return false, "Too many lootboxes (max 4)"
	end
	
	-- Validate lootbox entries
	local unlockingCount = 0
	for i = 1, 4 do
		local lootbox = profile.lootboxes[i]
		if lootbox then
			if type(lootbox) ~= "table" then
				return false, "Invalid lootbox entry at slot " .. i
			end
			
			if type(lootbox.id) ~= "string" or lootbox.id == "" then
				return false, "Invalid lootbox ID at slot " .. i
			end
			
			if not ProfileSchema.IsValidLootboxRarity(lootbox.rarity) then
				return false, "Invalid lootbox rarity at slot " .. i
			end
			
			if not ProfileSchema.IsValidLootboxState(lootbox.state) then
				return false, "Invalid lootbox state at slot " .. i
			end
			
			if type(lootbox.seed) ~= "number" then
				return false, "Invalid lootbox seed at slot " .. i
			end
			
			if lootbox.startedAt ~= nil and type(lootbox.startedAt) ~= "number" then
				return false, "Invalid lootbox startedAt at slot " .. i
			end
			
			if lootbox.unlocksAt ~= nil and type(lootbox.unlocksAt) ~= "number" then
				return false, "Invalid lootbox unlocksAt at slot " .. i
			end
			
			if lootbox.source ~= nil and type(lootbox.source) ~= "string" then
				return false, "Invalid lootbox source at slot " .. i
			end
			
			-- Count actively unlocking lootboxes (timer still running)
			-- Note: We allow multiple "Unlocking" state lootboxes in profile,
			-- but business logic in StartUnlock prevents starting new unlocks
			if lootbox.state == "Unlocking" and lootbox.unlocksAt and lootbox.unlocksAt > os.time() then
				unlockingCount = unlockingCount + 1
			end
		end
	end
	
	if unlockingCount > 1 then
		return false, "Too many unlocking lootboxes (max 1)"
	end
	
	-- Check playtime data
	if not profile.playtime or type(profile.playtime) ~= "table" then
		return false, "Invalid playtime data"
	end
	
	if type(profile.playtime.totalTime) ~= "number" or profile.playtime.totalTime < 0 then
		return false, "Invalid playtime totalTime"
	end
	
	if type(profile.playtime.lastSyncTime) ~= "number" or profile.playtime.lastSyncTime < 0 then
		return false, "Invalid playtime lastSyncTime"
	end
	
	if not profile.playtime.claimedRewards or type(profile.playtime.claimedRewards) ~= "table" then
		return false, "Invalid playtime claimedRewards"
	end
	
	-- Validate claimedRewards array
	for i, rewardIndex in ipairs(profile.playtime.claimedRewards) do
		if type(rewardIndex) ~= "number" or rewardIndex < 1 or rewardIndex > 7 then
			return false, "Invalid claimedReward index at position " .. i
		end
	end
	
	-- Check daily data
	if not profile.daily or type(profile.daily) ~= "table" then
		return false, "Invalid daily data"
	end
	
	if type(profile.daily.streak) ~= "number" or profile.daily.streak < 0 or profile.daily.streak > 7 then
		return false, "Invalid daily streak"
	end
	
	if type(profile.daily.lastLogin) ~= "number" or profile.daily.lastLogin < 0 then
		return false, "Invalid daily lastLogin"
	end
	
	-- Check pending lootbox
	if profile.pendingLootbox ~= nil then
		if type(profile.pendingLootbox) ~= "table" then
			return false, "Invalid pending lootbox type"
		end
		
		if type(profile.pendingLootbox.id) ~= "string" or profile.pendingLootbox.id == "" then
			return false, "Invalid pending lootbox ID"
		end
		
		if not ProfileSchema.IsValidLootboxRarity(profile.pendingLootbox.rarity) then
			return false, "Invalid pending lootbox rarity"
		end
		
		if type(profile.pendingLootbox.seed) ~= "number" then
			return false, "Invalid pending lootbox seed"
		end
		
		if profile.pendingLootbox.source ~= nil and type(profile.pendingLootbox.source) ~= "string" then
			return false, "Invalid pending lootbox source"
		end
		
		-- Pending lootbox should not have state or timing fields
		if profile.pendingLootbox.state or profile.pendingLootbox.startedAt or profile.pendingLootbox.unlocksAt then
			return false, "Pending lootbox should not have state or timing fields"
		end
	end
	
	-- Check pending battle rewards
	if profile.pendingBattleRewards ~= nil then
		if type(profile.pendingBattleRewards) ~= "table" then
			return false, "Invalid pendingBattleRewards (must be table)"
		end
		
		-- Limit to prevent excessive accumulation
		if #profile.pendingBattleRewards > 50 then
			return false, "Too many pending battle rewards (max 50)"
		end
		
		for i, reward in ipairs(profile.pendingBattleRewards) do
			if type(reward) ~= "table" then
				return false, "Invalid reward at index " .. i
			end
			
			if not reward.type then
				return false, "Missing reward type at index " .. i
			end
			
			if reward.type == "soft" then
				if type(reward.amount) ~= "number" or reward.amount <= 0 then
					return false, "Invalid soft reward amount at index " .. i
				end
			elseif reward.type == "lootbox" then
				if not reward.rarity or not ProfileSchema.IsValidLootboxRarity(reward.rarity) then
					return false, "Invalid lootbox rarity at index " .. i
				end
			else
				return false, "Invalid reward type '" .. tostring(reward.type) .. "' at index " .. i
			end
		end
	end
	
	return true, nil
end

-- Validate lootbox rarity
function ProfileSchema.IsValidLootboxRarity(rarity)
	return rarity == "uncommon" or rarity == "rare" or rarity == "epic" or rarity == "legendary" or rarity == "onepiece" or rarity == "beginner"
end

-- Validate lootbox state
function ProfileSchema.IsValidLootboxState(state)
	return state == "Idle" or state == "Unlocking" or state == "Ready" or state == "Consumed"
end

-- Create a new profile with defaults (v2)
function ProfileSchema.CreateProfile(playerId)
	local now = os.time()
	
	-- Starter collection: only card_600 x1 and card_1800 x1
	local starterCollection = {
		["card_600"] = { count = 1, level = 1 },
		["card_1800"] = { count = 1, level = 1 }
	}
	
	-- Starter deck: add the starter cards to the deck
	local starterDeck = {
		"card_600",
		"card_1800"
	}
	
	local profile = {
		playerId = tostring(playerId),
		createdAt = now,
		lastLoginAt = now,
		loginStreak = 0,
		collection = starterCollection,
		deck = starterDeck,  -- Starter deck with card_600 and card_1800
		currencies = {
			soft = 100,  -- Starting soft currency
			hard = 150   -- Starting hard currency
		},
		favoriteLastSeen = nil,
		tutorialStep = 0,
		squadPower = 0,  -- Will be computed when deck is set
		lootboxes = {},
		playtime = {
			totalTime = 0,
			lastSyncTime = now,
			claimedRewards = {}
		},
		daily = {
			streak = 0,
			lastLogin = 0
		},
		followRewardClaimed = false,
		bossWins = {},
		npcWins = 0,
		totalRobuxSpent = 0,
		pendingBattleRewards = {}
	}
	
	return profile
end

-- Migrate v1 profile to v2
function ProfileSchema.MigrateV1ToV2(v1Profile)
	if not v1Profile then
		return nil, "No profile to migrate"
	end
	
	local v2Profile = {
		playerId = v1Profile.playerId,
		createdAt = v1Profile.createdAt,
		lastLoginAt = v1Profile.lastLoginAt,
		loginStreak = v1Profile.loginStreak,
		deck = v1Profile.deck,
		currencies = v1Profile.currencies,
		favoriteLastSeen = nil,
		tutorialStep = 0,
		squadPower = 0,
		lootboxes = {},
		playtime = {
			totalTime = 0,
			lastSyncTime = os.time(),
			claimedRewards = {}
		},
		daily = {
			streak = 0,
			lastLogin = 0
		},
		redeemedCodes = {},  -- Initialize promo codes tracking
		followRewardClaimed = v1Profile.followRewardClaimed or false,
		bossWins = v1Profile.bossWins or {},
		npcWins = v1Profile.npcWins or 0,
		totalRobuxSpent = v1Profile.totalRobuxSpent or 0,
		pendingBattleRewards = {}
	}
	
	-- Migrate collection from v1 format to v2 format
	v2Profile.collection = {}
	for cardId, count in pairs(v1Profile.collection or {}) do
		v2Profile.collection[cardId] = {
			count = count,
			level = 1  -- All v1 cards start at level 1
		}
	end
	
	return v2Profile
end

-- Update profile timestamps
function ProfileSchema.UpdateLoginTime(profile)
	if not profile then
		return false
	end
	
	profile.lastLoginAt = os.time()
	return true
end

-- Increment login streak
function ProfileSchema.IncrementLoginStreak(profile)
	if not profile then
		return false
	end
	
	profile.loginStreak = profile.loginStreak + 1
	return true
end

-- Reset login streak (for missed days)
function ProfileSchema.ResetLoginStreak(profile)
	if not profile then
		return false
	end
	
	profile.loginStreak = 0
	return true
end

-- Add cards to collection (v2 format)
function ProfileSchema.AddCardsToCollection(profile, cardId, count)
	if not profile or not profile.collection then
		return false
	end
	
	count = count or 1
	
	-- Initialize card entry if it doesn't exist
	if not profile.collection[cardId] then
		profile.collection[cardId] = { count = 0, level = 1 }
	end
	
	profile.collection[cardId].count = profile.collection[cardId].count + count
	return true
end

-- Remove cards from collection (v2 format)
function ProfileSchema.RemoveCardsFromCollection(profile, cardId, count)
	if not profile or not profile.collection then
		return false
	end
	
	count = count or 1
	local cardEntry = profile.collection[cardId]
	
	if not cardEntry then
		return false, "Card not in collection"
	end
	
	if cardEntry.count < count then
		return false, "Not enough cards to remove"
	end
	
	cardEntry.count = cardEntry.count - count
	
	-- Remove entry if count reaches 0
	if cardEntry.count <= 0 then
		profile.collection[cardId] = nil
	end
	
	return true
end

-- Update deck (v2: no collection count validation, enforces uniqueness)
function ProfileSchema.UpdateDeck(profile, newDeck)
	if not profile then
		return false, "Profile is nil"
	end
	
	-- Allow decks with 1-6 cards
	if not newDeck or type(newDeck) ~= "table" or #newDeck == 0 then
		return false, "Deck must contain at least 1 card"
	end
	if #newDeck > 6 then
		return false, "Deck must contain at most 6 cards"
	end
	
	-- Check for duplicates
	local seenCards = {}
	for i, cardId in ipairs(newDeck) do
		if type(cardId) ~= "string" or cardId == "" then
			return false, "Invalid card ID at position " .. i
		end
		
		if seenCards[cardId] then
			return false, "Duplicate card ID in deck: " .. cardId
		end
		seenCards[cardId] = true
	end
	
	-- Update the deck
	profile.deck = newDeck
	return true
end

-- Add currency
function ProfileSchema.AddCurrency(profile, currencyType, amount)
	if not profile or not profile.currencies then
		return false, "Profile missing currencies table"
	end
	
	if currencyType ~= "soft" and currencyType ~= "hard" then
		return false, "Invalid currency type"
	end
	
	if type(amount) ~= "number" then
		return false, "Invalid currency amount"
	end
	
	if type(profile.currencies[currencyType]) ~= "number" then
		profile.currencies[currencyType] = 0
	end
	
	profile.currencies[currencyType] = profile.currencies[currencyType] + amount
	return true
end

-- Remove currency (with validation)
function ProfileSchema.RemoveCurrency(profile, currencyType, amount)
	if not profile or not profile.currencies then
		return false
	end
	
	if currencyType == "soft" or currencyType == "hard" then
		local current = profile.currencies[currencyType]
		if current < amount then
			return false, "Not enough " .. currencyType .. " currency"
		end
		
		profile.currencies[currencyType] = current - amount
		return true
	end
	
	return false, "Invalid currency type"
end

-- Get profile statistics (v2)
function ProfileSchema.GetProfileStats(profile)
	if not profile then
		return nil
	end
	
	local totalCards = 0
	local totalLevels = 0
	for _, entry in pairs(profile.collection) do
		totalCards = totalCards + entry.count
		totalLevels = totalLevels + entry.level
	end
	
	local uniqueCards = 0
	for _ in pairs(profile.collection) do
		uniqueCards = uniqueCards + 1
	end
	
	return {
		totalCards = totalCards,
		uniqueCards = uniqueCards,
		totalLevels = totalLevels,
		deckSize = #profile.deck,
		loginStreak = profile.loginStreak,
		softCurrency = profile.currencies.soft,
		hardCurrency = profile.currencies.hard,
		squadPower = profile.squadPower,
		tutorialStep = profile.tutorialStep,
		lootboxCount = #profile.lootboxes,
		daysSinceCreation = math.floor((os.time() - profile.createdAt) / 86400)
	}
end

-- Schema migration hooks (for future versions)
ProfileSchema.MigrationHooks = {
	["v2"] = function(profile)
		-- Migrate v1 to v2
		return ProfileSchema.MigrateV1ToV2(profile)
	end
}

return ProfileSchema
