local CardCatalog = {}

-- Rarity definitions
CardCatalog.Rarities = {
	COMMON = "common",
	UNCOMMON = "uncommon", 
	RARE = "rare",
	EPIC = "epic",
	LEGENDARY = "legendary"
}

-- Class/Role definitions
CardCatalog.Classes = {
	WARRIOR = "warrior",
	MAGE = "mage",
	HEALER = "healer",
	TANK = "tank",
	SUPPORT = "support"
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

-- Initial catalog with 8 example cards
CardCatalog.Cards = {
	-- Common cards
	["warrior_001"] = CreateCard("warrior_001", "Recruit Warrior", CardCatalog.Rarities.COMMON, CardCatalog.Classes.WARRIOR, {
		attack = 3,
		health = 4,
		speed = 2
	}),
	
	["mage_001"] = CreateCard("mage_001", "Apprentice Mage", CardCatalog.Rarities.COMMON, CardCatalog.Classes.MAGE, {
		attack = 4,
		health = 2,
		speed = 3
	}),
	
	-- Uncommon cards
	["healer_001"] = CreateCard("healer_001", "Novice Healer", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.HEALER, {
		attack = 2,
		health = 5,
		speed = 2
	}, "placeholder_passive"),
	
	["tank_001"] = CreateCard("tank_001", "Iron Guard", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.TANK, {
		attack = 2,
		health = 6,
		speed = 1
	}),
	
	-- Rare cards
	["warrior_002"] = CreateCard("warrior_002", "Veteran Fighter", CardCatalog.Rarities.RARE, CardCatalog.Classes.WARRIOR, {
		attack = 5,
		health = 5,
		speed = 3
	}, "placeholder_passive"),
	
	["mage_002"] = CreateCard("mage_002", "Battle Sorcerer", CardCatalog.Rarities.RARE, CardCatalog.Classes.MAGE, {
		attack = 6,
		health = 3,
		speed = 4
	}),
	
	-- Epic cards
	["support_001"] = CreateCard("support_001", "Tactical Commander", CardCatalog.Rarities.EPIC, CardCatalog.Classes.SUPPORT, {
		attack = 3,
		health = 4,
		speed = 5
	}, "placeholder_passive"),
	
	-- Legendary cards
	["warrior_003"] = CreateCard("warrior_003", "Champion Warlord", CardCatalog.Rarities.LEGENDARY, CardCatalog.Classes.WARRIOR, {
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
