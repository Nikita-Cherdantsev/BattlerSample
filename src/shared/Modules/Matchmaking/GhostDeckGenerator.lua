--[[
	GhostDeckGenerator

	Generates an "artificial" opponent deck (ghost deck) that roughly matches
	the player's deck strength and level band, reusing the same idea as NPC deck
	generation in MatchService but without depending on server services (no require cycles).
]]

local GhostDeckGenerator = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardCatalog = require(ReplicatedStorage.Modules.Cards.CardCatalog)
local CardStats = require(ReplicatedStorage.Modules.Cards.CardStats)
local SeededRNG = require(ReplicatedStorage.Modules.RNG.SeededRNG)
local Types = require(ReplicatedStorage.Modules.Types)

local function roundToDecimals(x, decimals)
	local m = 10 ^ (decimals or 0)
	return math.floor(x * m + 0.5) / m
end

local function computeDeckStrength(deck, levels)
	local total = 0
	for i, cardId in ipairs(deck) do
		local level = levels[i] or 1
		level = math.max(1, math.min(level, Types.MAX_LEVEL))
		total = total + CardStats.ComputeCardPower(cardId, level)
	end
	return total
end

local function computeDeckMeta(deck, levels)
	local size = #deck
	local totalLevel = 0
	for i = 1, size do
		totalLevel += (levels[i] or 1)
	end
	local avgLevel = (size > 0) and (totalLevel / size) or 1
	return {
		size = size,
		averageLevel = avgLevel,
		strength = roundToDecimals(computeDeckStrength(deck, levels), 1),
	}
end

-- Generate a ghost deck snapshot-like payload.
-- Inputs:
-- - playerDeck: dense array of cardIds (1..N)
-- - playerLevels: dense array of levels aligned with playerDeck indices
-- - seed: number used for deterministic RNG
-- - cfg: table with tuning values:
--   minStrengthMult, maxStrengthMult, sizeVariance, attempts,
--   levelVarianceMin, levelVarianceMax
function GhostDeckGenerator.Generate(playerDeck, playerLevels, seed, cfg)
	cfg = cfg or {}

	local deckMeta = computeDeckMeta(playerDeck or {}, playerLevels or {})
	local targetStrength = math.max(1, deckMeta.strength or 1)

	local minStrength = targetStrength * (cfg.minStrengthMult or 0.65)
	local maxStrength = targetStrength * (cfg.maxStrengthMult or 1.35)

	local sizeVar = math.max(0, math.floor(cfg.sizeVariance or 3))
	local minSize = math.max(1, math.min(6, (deckMeta.size or 1) - sizeVar))
	local maxSize = math.max(1, math.min(6, (deckMeta.size or 1) + sizeVar))
	if minSize > maxSize then
		minSize, maxSize = maxSize, minSize
	end

	local baseLevel = math.clamp(math.floor((deckMeta.averageLevel or 1) + 0.5), 1, Types.MAX_LEVEL)
	local levelVarMin = math.max(0, math.floor(cfg.levelVarianceMin or 1))
	local levelVarMax = math.max(levelVarMin, math.floor(cfg.levelVarianceMax or 4))

	-- Full card pool (all cards).
	local cardPool = {}
	for cardId, _ in pairs(CardCatalog.GetAllCards()) do
		table.insert(cardPool, cardId)
	end
	if #cardPool == 0 then
		return {
			deck = {},
			levels = {},
			strength = 0,
		}
	end

	local rng = SeededRNG.New(seed)
	local attempts = math.max(50, math.floor(cfg.attempts or 250))

	local matchingCandidates = {}
	local bestCandidate = nil
	local bestDiff = math.huge

	for _ = 1, attempts do
		local deckSize = SeededRNG.RandomInt(rng, minSize, maxSize)
		deckSize = math.clamp(deckSize, 1, #cardPool)

		local candidateDeck = {}
		local candidateLevels = {}

		-- Pick unique cards by sampling without replacement.
		local availableCards = {}
		for idx, cardId in ipairs(cardPool) do
			availableCards[idx] = cardId
		end

		for slot = 1, deckSize do
			if #availableCards == 0 then
				break
			end
			local pickIndex = SeededRNG.RandomInt(rng, 1, #availableCards)
			local cardId = availableCards[pickIndex]
			table.remove(availableCards, pickIndex)

			candidateDeck[slot] = cardId

			local variance = SeededRNG.RandomInt(rng, levelVarMin, levelVarMax)
			local minLevel = math.max(1, baseLevel - variance)
			local maxLevel = math.min(Types.MAX_LEVEL, baseLevel + variance)
			local level = SeededRNG.RandomInt(rng, minLevel, maxLevel)
			candidateLevels[slot] = level
		end

		if #candidateDeck == deckSize then
			local strengthRaw = computeDeckStrength(candidateDeck, candidateLevels)
			local strengthRounded = roundToDecimals(strengthRaw, 1)
			local diff = math.abs(strengthRaw - targetStrength)

			if strengthRaw >= minStrength and strengthRaw <= maxStrength then
				table.insert(matchingCandidates, {
					deck = candidateDeck,
					levels = candidateLevels,
					strength = strengthRounded,
				})
			elseif diff < bestDiff then
				bestDiff = diff
				bestCandidate = {
					deck = candidateDeck,
					levels = candidateLevels,
					strength = strengthRounded,
				}
			end
		end
	end

	local chosen = nil
	if #matchingCandidates > 0 then
		local idx = SeededRNG.RandomInt(rng, 1, #matchingCandidates)
		chosen = matchingCandidates[idx]
	else
		chosen = bestCandidate
	end

	if not chosen or type(chosen.deck) ~= "table" or #chosen.deck == 0 then
		-- Final fallback: mirror player's deck (prevents empty matches).
		local fallbackDeck = {}
		local fallbackLevels = {}
		for i, cardId in ipairs(playerDeck or {}) do
			fallbackDeck[i] = cardId
			fallbackLevels[i] = playerLevels and playerLevels[i] or baseLevel
		end
		return {
			deck = fallbackDeck,
			levels = fallbackLevels,
			strength = roundToDecimals(targetStrength, 1),
		}
	end

	return chosen
end

return GhostDeckGenerator

