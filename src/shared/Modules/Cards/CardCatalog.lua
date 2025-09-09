local CardCatalog = {}

-- Rarity definitions (canon set)
CardCatalog.Rarities = {
	UNCOMMON = "uncommon",
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
local function CreateCard(id, name, rarity, class, baseStats, slotNumber, description, passive)
	return {
		id = id,
		name = name,
		rarity = rarity,
		class = class,
		baseStats = baseStats or {
			attack = 0,
			health = 0,
			defence = 0
		},
		slotNumber = slotNumber or 999,  -- Default high value for sorting
		description = description or "A mysterious card.",
		passive = passive or nil
	}
end

-- Initial catalog with 8 example cards (updated for v2 schema)
CardCatalog.Cards = {
	["card_100"] = CreateCard("card_100", "Monkey D. Luffy", CardCatalog.Rarities.LEGENDARY, CardCatalog.Classes.DPS, {
		attack = 1,
		health = 3,
		defence = 4
	}, 10, ""),
	
	["card_200"] = CreateCard("card_200", "Roronoa Zoro", CardCatalog.Rarities.LEGENDARY, CardCatalog.Classes.TANK, {
		attack = 1,
		health = 10,
		defence = 2
	}, 20, ""),
	
	["card_300"] = CreateCard("card_300", "Sasuke Uchiha", CardCatalog.Rarities.EPIC, CardCatalog.Classes.DPS, {
		attack = 2,
		health = 4,
		defence = 2
	}, 30, ""),
	
	["card_400"] = CreateCard("card_400", "Gaara", CardCatalog.Rarities.EPIC, CardCatalog.Classes.TANK, {
		attack = 0,
		health = 8,
		defence = 1
	}, 40, ""),
	
	["card_500"] = CreateCard("card_500", "Sanji", CardCatalog.Rarities.RARE, CardCatalog.Classes.DPS, {
		attack = 2,
		health = 3,
		defence = 1
	}, 50, ""),
	
	["card_600"] = CreateCard("card_600", "Tenten", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.SUPPORT, {
		attack = 0,
		health = 2,
		defence = 1
	}, 60, ""),
	
	["card_700"] = CreateCard("card_700", "Koby", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.SUPPORT, {
		attack = 1,
		health = 1,
		defence = 1
	}, 70, ""),
	
	["card_800"] = CreateCard("card_800", "Vegeta", CardCatalog.Rarities.LEGENDARY, CardCatalog.Classes.DPS, {
		attack = 6,
		health = 8,
		defence = 0
	}, 80, ""),

	["card_900"] = CreateCard("card_900", "Rock Lee", CardCatalog.Rarities.RARE, CardCatalog.Classes.DPS, {
		attack = 1,
		health = 4,
		defence = 0
	}, 90, ""),

	["card_1000"] = CreateCard("card_1000", "Goku", CardCatalog.Rarities.LEGENDARY, CardCatalog.Classes.DPS, {
		attack = 9,
		health = 4,
		defence = 0
	}, 100, ""),

	["card_1100"] = CreateCard("card_1100", "Usopp", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.SUPPORT, {
		attack = 1,
		health = 3,
		defence = 0
	}, 110, ""),

	["card_1200"] = CreateCard("card_1200", "All Might", CardCatalog.Rarities.EPIC, CardCatalog.Classes.DPS, {
		attack = 5,
		health = 3,
		defence = 0
	}, 120, ""),

	["card_1300"] = CreateCard("card_1300", "Chopper", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.SUPPORT, {
		attack = 1,
		health = 2,
		defence = 0
	}, 130, ""),

	["card_1400"] = CreateCard("card_1400", "Krillin", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.SUPPORT, {
		attack = 1,
		health = 2,
		defence = 0
	}, 140, ""),

	["card_1500"] = CreateCard("card_1500", "Bakugo", CardCatalog.Rarities.RARE, CardCatalog.Classes.DPS, {
		attack = 4,
		health = 2,
		defence = 0
	}, 150, ""),

	["card_1600"] = CreateCard("card_1600", "Yamcha", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.DPS, {
		attack = 0,
		health = 1,
		defence = 0
	}, 160, ""),

	["card_1700"] = CreateCard("card_1700", "Midoriya", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.DPS, {
		attack = 1,
		health = 1,
		defence = 0
	}, 170, ""),

	["card_1800"] = CreateCard("card_1800", "Piccolo", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.SUPPORT, {
		attack = 3,
		health = 1,
		defence = 0
	}, 180, "")
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

-- Get cards sorted by slotNumber (for deck ordering)
function CardCatalog.GetCardsSortedBySlot()
	local cards = {}
	for id, card in pairs(CardCatalog.Cards) do
		table.insert(cards, card)
	end
	
	table.sort(cards, function(a, b)
		return a.slotNumber < b.slotNumber
	end)
	
	return cards
end

return CardCatalog
