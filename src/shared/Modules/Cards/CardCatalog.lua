local CardCatalog = {}

-- Rarity definitions (canon set)
CardCatalog.Rarities = {
	COMMON = "common",
	RARE = "rare",
	EPIC = "epic",
	LEGENDARY = "legendary"
}

-- Class/Role definitions (canon set)
CardCatalog.Classes = {
	DPS = "dps",
	SUPPORT = "support",
	TANK = "tank"
}

-- Base card template
local function CreateCard(id, name, rarity, class, baseStats, passive)
	return {
		id = id,
		name = name,
		rarity = rarity,
		class = class,
		baseStats = baseStats or {
			attack = 0,
			health = 0,
			speed = 0
		},
		passive = passive or nil
	}
end

-- Initial catalog with 8 example cards (updated for canon enums)
CardCatalog.Cards = {
	-- Common cards
	["dps_001"] = CreateCard("dps_001", "Recruit Fighter", CardCatalog.Rarities.COMMON, CardCatalog.Classes.DPS, {
		attack = 3,
		health = 4,
		speed = 2
	}),
	
	["support_001"] = CreateCard("support_001", "Novice Healer", CardCatalog.Rarities.COMMON, CardCatalog.Classes.SUPPORT, {
		attack = 2,
		health = 5,
		speed = 2
	}),
	
	-- Rare cards
	["tank_001"] = CreateCard("tank_001", "Iron Guard", CardCatalog.Rarities.RARE, CardCatalog.Classes.TANK, {
		attack = 2,
		health = 6,
		speed = 1
	}),
	
	["dps_002"] = CreateCard("dps_002", "Veteran Warrior", CardCatalog.Rarities.RARE, CardCatalog.Classes.DPS, {
		attack = 5,
		health = 5,
		speed = 3
	}),
	
	["support_002"] = CreateCard("support_002", "Battle Cleric", CardCatalog.Rarities.RARE, CardCatalog.Classes.SUPPORT, {
		attack = 3,
		health = 4,
		speed = 4
	}),
	
	-- Epic cards
	["dps_003"] = CreateCard("dps_003", "Elite Berserker", CardCatalog.Rarities.EPIC, CardCatalog.Classes.DPS, {
		attack = 7,
		health = 4,
		speed = 5
	}, "placeholder_passive"),
	
	["tank_002"] = CreateCard("tank_002", "Steel Defender", CardCatalog.Rarities.EPIC, CardCatalog.Classes.TANK, {
		attack = 3,
		health = 8,
		speed = 2
	}, "placeholder_passive"),
	
	-- Legendary cards
	["dps_004"] = CreateCard("dps_004", "Champion Warlord", CardCatalog.Rarities.LEGENDARY, CardCatalog.Classes.DPS, {
		attack = 8,
		health = 7,
		speed = 4
	}, "placeholder_passive")
}

-- Public functions
function CardCatalog.GetCard(cardId)
	return CardCatalog.Cards[cardId]
end

function CardCatalog.GetAllCards()
	return CardCatalog.Cards
end

function CardCatalog.GetCardsByRarity(rarity)
	local cards = {}
	for id, card in pairs(CardCatalog.Cards) do
		if card.rarity == rarity then
			table.insert(cards, card)
		end
	end
	return cards
end

function CardCatalog.GetCardsByClass(class)
	local cards = {}
	for id, card in pairs(CardCatalog.Cards) do
		if card.class == class then
			table.insert(cards, card)
		end
	end
	return cards
end

function CardCatalog.IsValidCardId(cardId)
	return CardCatalog.Cards[cardId] ~= nil
end

return CardCatalog
