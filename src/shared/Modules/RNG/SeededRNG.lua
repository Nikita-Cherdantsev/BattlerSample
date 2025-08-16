local SeededRNG = {}

-- Simple but effective linear congruential generator
-- Using constants from Numerical Recipes
local A = 1664525
local C = 1013904223
local M = 2^32

-- RNG state
local function CreateRNG(seed)
	return {
		seed = seed or os.time(),
		sequence = 0
	}
end

-- Generate next random number in sequence
local function NextRandom(rng)
	rng.seed = (A * rng.seed + C) % M
	rng.sequence = rng.sequence + 1
	return rng.seed / M -- Returns value between 0 and 1
end

-- Public functions

-- Create a new RNG instance with a seed
function SeededRNG.New(seed)
	return CreateRNG(seed)
end

-- Get a random integer between min and max (inclusive)
function SeededRNG.RandomInt(rng, min, max)
	if not rng then
		error("RNG instance required")
	end
	
	if min > max then
		min, max = max, min
	end
	
	local range = max - min + 1
	local randomValue = NextRandom(rng)
	return min + math.floor(randomValue * range)
end

-- Get a random float between min and max
function SeededRNG.RandomFloat(rng, min, max)
	if not rng then
		error("RNG instance required")
	end
	
	if min > max then
		min, max = max, min
	end
	
	local randomValue = NextRandom(rng)
	return min + (randomValue * (max - min))
end

-- Get a random boolean with given probability (0.0 to 1.0)
function SeededRNG.RandomBool(rng, probability)
	if not rng then
		error("RNG instance required")
	end
	
	probability = probability or 0.5
	local randomValue = NextRandom(rng)
	return randomValue < probability
end

-- Pick a random element from an array
function SeededRNG.RandomChoice(rng, array)
	if not rng then
		error("RNG instance required")
	end
	
	if not array or #array == 0 then
		error("Array must not be empty")
	end
	
	local index = SeededRNG.RandomInt(rng, 1, #array)
	return array[index]
end

-- Shuffle an array using Fisher-Yates algorithm
function SeededRNG.Shuffle(rng, array)
	if not rng then
		error("RNG instance required")
	end
	
	if not array then
		error("Array required")
	end
	
	-- Create a copy to avoid modifying original
	local shuffled = {}
	for i = 1, #array do
		shuffled[i] = array[i]
	end
	
	-- Fisher-Yates shuffle
	for i = #shuffled, 2, -1 do
		local j = SeededRNG.RandomInt(rng, 1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	
	return shuffled
end

-- Get current RNG state (for debugging/replay)
function SeededRNG.GetState(rng)
	if not rng then
		error("RNG instance required")
	end
	
	return {
		seed = rng.seed,
		sequence = rng.sequence
	}
end

-- Set RNG state (for replay scenarios)
function SeededRNG.SetState(rng, state)
	if not rng then
		error("RNG instance required")
	end
	
	if not state or not state.seed or not state.sequence then
		error("Invalid state format")
	end
	
	rng.seed = state.seed
	rng.sequence = state.sequence
end

-- Reset RNG to initial seed
function SeededRNG.Reset(rng)
	if not rng then
		error("RNG instance required")
	end
	
	rng.sequence = 0
end

return SeededRNG
