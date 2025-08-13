local ProfileSchema = {}

-- Profile version
ProfileSchema.VERSION = "v1"

-- Profile structure definition
ProfileSchema.Profile = {
	-- Basic player information
	playerId = "",           -- Roblox UserId (string)
	createdAt = 0,           -- Unix timestamp when profile was created
	lastLoginAt = 0,         -- Unix timestamp of last login
	loginStreak = 0,         -- Consecutive login days (for DailyHandler integration)
	
	-- Card collection (map: cardId -> count)
	collection = {},
	
	-- Active deck (exactly 6 card IDs)
	deck = {},
	
	-- Optional currencies
	currencies = {
		soft = 0,             -- Soft currency (earned in-game)
		hard = 0              -- Hard currency (premium/Robux)
	}
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
	
	-- Check collection
	if not profile.collection or type(profile.collection) ~= "table" then
		return false, "Invalid collection"
	end
	
	-- Check deck
	if not profile.deck or type(profile.deck) ~= "table" then
		return false, "Invalid deck"
	end
	
	if #profile.deck ~= 6 then
		return false, "Deck must contain exactly 6 cards"
	end
	
	-- Validate each card in deck
	for i, cardId in ipairs(profile.deck) do
		if type(cardId) ~= "string" or cardId == "" then
			return false, "Invalid card ID at position " .. i
		end
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
	
	return true, nil
end

-- Create a new profile with defaults
function ProfileSchema.CreateProfile(playerId)
	local now = os.time()
	
	local profile = {
		playerId = tostring(playerId),
		createdAt = now,
		lastLoginAt = now,
		loginStreak = 0,
		collection = {},
		deck = {},
		currencies = {
			soft = 1000,  -- Starting soft currency
			hard = 0      -- No starting hard currency
		}
	}
	
	return profile
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

-- Add cards to collection
function ProfileSchema.AddCardsToCollection(profile, cardId, count)
	if not profile or not profile.collection then
		return false
	end
	
	count = count or 1
	profile.collection[cardId] = (profile.collection[cardId] or 0) + count
	return true
end

-- Remove cards from collection
function ProfileSchema.RemoveCardsFromCollection(profile, cardId, count)
	if not profile or not profile.collection then
		return false
	end
	
	count = count or 1
	local currentCount = profile.collection[cardId] or 0
	
	if currentCount < count then
		return false, "Not enough cards to remove"
	end
	
	profile.collection[cardId] = currentCount - count
	
	-- Remove entry if count reaches 0
	if profile.collection[cardId] <= 0 then
		profile.collection[cardId] = nil
	end
	
	return true
end

-- Check if player has enough cards for a deck
function ProfileSchema.HasEnoughCardsForDeck(profile, deck)
	if not profile or not profile.collection or not deck then
		return false
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
			return false, "Not enough " .. cardId .. " (need " .. needed .. ", have " .. available .. ")"
		end
	end
	
	return true
end

-- Update deck (with validation)
function ProfileSchema.UpdateDeck(profile, newDeck)
	if not profile then
		return false, "Profile is nil"
	end
	
	if not newDeck or type(newDeck) ~= "table" or #newDeck ~= 6 then
		return false, "Deck must contain exactly 6 cards"
	end
	
	-- Check if player has the cards
	local hasEnough, errorMessage = ProfileSchema.HasEnoughCardsForDeck(profile, newDeck)
	if not hasEnough then
		return false, errorMessage
	end
	
	-- Update the deck
	profile.deck = newDeck
	return true
end

-- Add currency
function ProfileSchema.AddCurrency(profile, currencyType, amount)
	if not profile or not profile.currencies then
		return false
	end
	
	if currencyType == "soft" or currencyType == "hard" then
		profile.currencies[currencyType] = profile.currencies[currencyType] + amount
		return true
	end
	
	return false, "Invalid currency type"
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

-- Get profile statistics
function ProfileSchema.GetProfileStats(profile)
	if not profile then
		return nil
	end
	
	local totalCards = 0
	for _, count in pairs(profile.collection) do
		totalCards = totalCards + count
	end
	
	local uniqueCards = 0
	for _ in pairs(profile.collection) do
		uniqueCards = uniqueCards + 1
	end
	
	return {
		totalCards = totalCards,
		uniqueCards = uniqueCards,
		deckSize = #profile.deck,
		loginStreak = profile.loginStreak,
		softCurrency = profile.currencies.soft,
		hardCurrency = profile.currencies.hard,
		daysSinceCreation = math.floor((os.time() - profile.createdAt) / 86400)
	}
end

-- Schema migration hooks (for future versions)
ProfileSchema.MigrationHooks = {
	-- Example migration from v1 to v2
	-- ["v2"] = function(profile)
	--     -- Add new fields, transform data, etc.
	--     profile.newField = "default_value"
	--     return profile
	-- end
}

return ProfileSchema
