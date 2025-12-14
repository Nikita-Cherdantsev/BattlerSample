--[[
	Shop Packs Catalog
	
	Defines hard currency packs available for purchase with Robux.
	Domain-only implementation (no purchase flow yet).
]]

local ShopPacksCatalog = {}

-- Hard currency pack data
ShopPacksCatalog.Packs = {
	["S"] = {
		id = "S",
		hardAmount = 20,
		robuxPrice = 9,
		devProductId = 3455684189,
		additionalHard = 0 -- UI bonus display only
	},
	["M"] = {
		id = "M", 
		hardAmount = 91,
		robuxPrice = 35,
		devProductId = 3455684392,
		additionalHard = 9 -- UI bonus display only
	},
	["L"] = {
		id = "L",
		hardAmount = 300,
		robuxPrice = 99,
		--devProductId = 3400864901, -- DEV productId for testing
		devProductId = 3455685050, -- PROD productId
		additionalHard = 30 -- UI bonus display only
	},
	["XL"] = {
		id = "XL",
		hardAmount = 700,
		robuxPrice = 200,
		devProductId = 3455685309,
		additionalHard = 140 -- UI bonus display only
	},
	["XXL"] = {
		id = "XXL",
		hardAmount = 1500,
		robuxPrice = 400,
		devProductId = 3455685485,
		additionalHard = 450 -- UI bonus display only
	},
	["XXXL"] = {
		id = "XXXL",
		hardAmount = 3500,
		robuxPrice = 800,
		devProductId = 3455686076,
		additionalHard = 1400 -- UI bonus display only
	}
}

-- Get a specific pack by ID
function ShopPacksCatalog.GetPack(packId)
	return ShopPacksCatalog.Packs[packId]
end

-- Get all available packs
function ShopPacksCatalog.AllPacks()
	local packs = {}
	for _, pack in pairs(ShopPacksCatalog.Packs) do
		table.insert(packs, pack)
	end
	
	-- Sort by hard amount (ascending)
	table.sort(packs, function(a, b)
		return a.hardAmount < b.hardAmount
	end)
	
	return packs
end

-- Get packs sorted by value (hard currency per Robux)
function ShopPacksCatalog.GetPacksByValue()
	local packs = ShopPacksCatalog.AllPacks()
	
	-- Calculate value for each pack
	for _, pack in ipairs(packs) do
		pack.value = pack.hardAmount / pack.robuxPrice
	end
	
	-- Sort by value (descending)
	table.sort(packs, function(a, b)
		return a.value > b.value
	end)
	
	return packs
end

-- Validate pack ID
function ShopPacksCatalog.IsValidPackId(packId)
	return ShopPacksCatalog.Packs[packId] ~= nil
end

-- Check if pack has a valid devProductId
function ShopPacksCatalog.HasDevProductId(packId)
	local pack = ShopPacksCatalog.GetPack(packId)
	return pack and pack.devProductId ~= nil
end

-- Get packs that are available for purchase (have devProductId)
function ShopPacksCatalog.GetAvailablePacks()
	local availablePacks = {}
	for _, pack in pairs(ShopPacksCatalog.Packs) do
		if pack.devProductId then
			table.insert(availablePacks, pack)
		end
	end
	
	-- Sort by hard amount (ascending)
	table.sort(availablePacks, function(a, b)
		return a.hardAmount < b.hardAmount
	end)
	
	return availablePacks
end

-- Get pack with best value (highest hard currency per Robux)
function ShopPacksCatalog.GetBestValuePack()
	local packsByValue = ShopPacksCatalog.GetPacksByValue()
	return packsByValue[1] -- First pack has best value
end

-- Get pack with worst value (lowest hard currency per Robux)
function ShopPacksCatalog.GetWorstValuePack()
	local packsByValue = ShopPacksCatalog.GetPacksByValue()
	return packsByValue[#packsByValue] -- Last pack has worst value
end

-- Check if any packs have live product IDs (for production readiness)
function ShopPacksCatalog.hasLiveProductIds()
	for _, pack in pairs(ShopPacksCatalog.Packs) do
		if pack.devProductId and pack.devProductId ~= nil then
			return true
		end
	end
	return false
end

-- Get pack by Developer Product ID (for receipt processing)
function ShopPacksCatalog.getPackByProductId(productId)
	for _, pack in pairs(ShopPacksCatalog.Packs) do
		if pack.devProductId == productId then
			return pack
		end
	end
	return nil
end

-- Calculate total hard currency for multiple packs
function ShopPacksCatalog.CalculateTotalHard(packIds)
	local total = 0
	for _, packId in ipairs(packIds) do
		local pack = ShopPacksCatalog.GetPack(packId)
		if pack then
			total = total + pack.hardAmount
		end
	end
	return total
end

-- Calculate total Robux cost for multiple packs
function ShopPacksCatalog.CalculateTotalRobux(packIds)
	local total = 0
	for _, packId in ipairs(packIds) do
		local pack = ShopPacksCatalog.GetPack(packId)
		if pack then
			total = total + pack.robuxPrice
		end
	end
	return total
end

return ShopPacksCatalog
