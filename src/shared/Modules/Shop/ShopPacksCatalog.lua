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
		hardAmount = 100,
		robuxPrice = 40
	},
	["M"] = {
		id = "M", 
		hardAmount = 330,
		robuxPrice = 100
	},
	["L"] = {
		id = "L",
		hardAmount = 840,
		robuxPrice = 200
	},
	["XL"] = {
		id = "XL",
		hardAmount = 1950,
		robuxPrice = 400
	},
	["XXL"] = {
		id = "XXL",
		hardAmount = 4900,
		robuxPrice = 800
	},
	["XXXL"] = {
		id = "XXXL",
		hardAmount = 12000,
		robuxPrice = 1500
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
