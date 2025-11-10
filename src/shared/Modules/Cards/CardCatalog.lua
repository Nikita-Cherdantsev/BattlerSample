local CardCatalog = {}

-- Rarity definitions (canon set)
-- Note: These must match BoxTypes.BoxRarity exactly
CardCatalog.Rarities = {
	UNCOMMON = "uncommon",
	RARE = "rare",
	EPIC = "epic",
	LEGENDARY = "legendary",
	ONEPIECE = "onepiece"
}

-- Class/Role definitions (canon set)
CardCatalog.Classes = {
	DPS = "dps",
	SUPPORT = "support",
	TANK = "tank"
}

-- Base card template
local function CreateCard(id, name, rarity, class, baseStats, slotNumber, growth, description, passive, specialBox)
	-- Use provided growth table or create default if none provided
	if not growth then
		growth = {}
		for level = 2, 10 do
			growth[level] = {
				atk = 0,
				hp = 0,
				defence = 0
			}
		end
	end
	
	return {
		id = id,
		name = name,
		rarity = rarity,
		class = class,
		base = baseStats or {
			atk = 0,
			hp = 0,
			defence = 0
		},
		growth = growth,
		slotNumber = slotNumber or 999,  -- Default high value for sorting
		description = description or "A mysterious card.",
		passive = passive or nil,
		specialBox = specialBox or nil
	}
end

-- Initial catalog with 8 example cards (updated for v2 schema)
CardCatalog.Cards = {
	["card_100"] = CreateCard("card_100", "Rubber King", CardCatalog.Rarities.LEGENDARY, CardCatalog.Classes.DPS, { -- Luffy
		atk = 1,
		hp = 3,
		defence = 4
	}, 100, {
		[2] = { atk = 1, hp = 1, defence = 1 },
		[3] = { atk = 1, hp = 0, defence = 0 },
		[4] = { atk = 0, hp = 1, defence = 1 },
		[5] = { atk = 1, hp = 1, defence = 0 },
		[6] = { atk = 1, hp = 0, defence = 1 },
		[7] = { atk = 1, hp = 1, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 1 },
		[9] = { atk = 1, hp = 0, defence = 0 },
		[10] = { atk = 1, hp = 1, defence = 1 }
	}, 10, "", nil, { CardCatalog.Rarities.ONEPIECE }),
	
	["card_200"] = CreateCard("card_200", "Blade Demon", CardCatalog.Rarities.LEGENDARY, CardCatalog.Classes.TANK, { -- Zoro
		atk = 1,
		hp = 10,
		defence = 2
	}, 200, {
		[2] = { atk = 0, hp = 1, defence = 1 },
		[3] = { atk = 1, hp = 1, defence = 0 },
		[4] = { atk = 0, hp = 1, defence = 1 },
		[5] = { atk = 0, hp = 1, defence = 0 },
		[6] = { atk = 1, hp = 2, defence = 1 },
		[7] = { atk = 0, hp = 1, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 1 },
		[9] = { atk = 1, hp = 1, defence = 0 },
		[10] = { atk = 0, hp = 1, defence = 1 }
	}, 20, "", nil, { CardCatalog.Rarities.ONEPIECE }),
	
	["card_300"] = CreateCard("card_300", "Iron Lotus", CardCatalog.Rarities.EPIC, CardCatalog.Classes.DPS, { -- Rock Lee
		atk = 2,
		hp = 4,
		defence = 2
	}, 300, {
		[2] = { atk = 1, hp = 1, defence = 0 },
		[3] = { atk = 0, hp = 0, defence = 1 },
		[4] = { atk = 1, hp = 1, defence = 0 },
		[5] = { atk = 0, hp = 0, defence = 1 },
		[6] = { atk = 1, hp = 1, defence = 0 },
		[7] = { atk = 0, hp = 0, defence = 1 },
		[8] = { atk = 1, hp = 1, defence = 0 },
		[9] = { atk = 0, hp = 0, defence = 1 },
		[10] = { atk = 1, hp = 1, defence = 1 }
	}, 30, ""),
	
	["card_400"] = CreateCard("card_400", "Fist Goddess", CardCatalog.Rarities.EPIC, CardCatalog.Classes.TANK, { -- Tsunade
		atk = 0,
		hp = 8,
		defence = 1
	}, 400, {
		[2] = { atk = 0, hp = 1, defence = 1 },
		[3] = { atk = 0, hp = 1, defence = 1 },
		[4] = { atk = 0, hp = 1, defence = 1 },
		[5] = { atk = 0, hp = 0, defence = 1 },
		[6] = { atk = 0, hp = 1, defence = 0 },
		[7] = { atk = 0, hp = 0, defence = 1 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 0, hp = 0, defence = 1 },
		[10] = { atk = 0, hp = 1, defence = 0 }
	}, 40, ""),
	
	["card_500"] = CreateCard("card_500", "Flame Chef", CardCatalog.Rarities.RARE, CardCatalog.Classes.DPS, { -- Sanji
		atk = 2,
		hp = 3,
		defence = 1
	}, 500, {
		[2] = { atk = 0, hp = 1, defence = 0 },
		[3] = { atk = 1, hp = 0, defence = 1 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 0, hp = 0, defence = 1 },
		[6] = { atk = 1, hp = 1, defence = 0 },
		[7] = { atk = 0, hp = 0, defence = 1 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 0, defence = 1 },
		[10] = { atk = 0, hp = 1, defence = 0 }
	}, 50, "", { CardCatalog.Rarities.ONEPIECE }),
	
	["card_600"] = CreateCard("card_600", "Weapon Fury", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.SUPPORT, { -- Tenten
		atk = 0,
		hp = 2,
		defence = 1
	}, 600, {
		[2] = { atk = 0, hp = 1, defence = 0 },
		[3] = { atk = 0, hp = 0, defence = 1 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 0, hp = 1, defence = 0 },
		[6] = { atk = 0, hp = 0, defence = 1 },
		[7] = { atk = 0, hp = 1, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 0, hp = 0, defence = 1 },
		[10] = { atk = 0, hp = 1, defence = 0 }
	}, 60, ""),
	
	["card_700"] = CreateCard("card_700", "Sea Striver", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.SUPPORT, { -- Koby
		atk = 1,
		hp = 1,
		defence = 1
	}, 700, {
		[2] = { atk = 1, hp = 0, defence = 0 },
		[3] = { atk = 0, hp = 1, defence = 0 },
		[4] = { atk = 0, hp = 0, defence = 1 },
		[5] = { atk = 1, hp = 0, defence = 0 },
		[6] = { atk = 0, hp = 1, defence = 0 },
		[7] = { atk = 0, hp = 0, defence = 1 },
		[8] = { atk = 1, hp = 0, defence = 0 },
		[9] = { atk = 0, hp = 1, defence = 0 },
		[10] = { atk = 0, hp = 0, defence = 1 }
		}, 70, "", nil, { CardCatalog.Rarities.ONEPIECE }),
	
	["card_800"] = CreateCard("card_800", "Prince of Wrath", CardCatalog.Rarities.LEGENDARY, CardCatalog.Classes.DPS, { -- Vegeta
		atk = 6,
		hp = 8,
		defence = 0
	}, 800, {
		[2] = { atk = 1, hp = 1, defence = 0 },
		[3] = { atk = 1, hp = 1, defence = 0 },
		[4] = { atk = 1, hp = 1, defence = 0 },
		[5] = { atk = 1, hp = 1, defence = 0 },
		[6] = { atk = 0, hp = 2, defence = 0 },
		[7] = { atk = 1, hp = 1, defence = 0 },
		[8] = { atk = 1, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 1, defence = 0 },
		[10] = { atk = 1, hp = 1, defence = 0 }
		}, 80, ""),

	["card_900"] = CreateCard("card_900", "Insect Master", CardCatalog.Rarities.RARE, CardCatalog.Classes.DPS, { -- Shino Aburame
		atk = 1,
		hp = 4,
		defence = 0
	}, 900, {
		[2] = { atk = 0, hp = 1, defence = 0 },
		[3] = { atk = 1, hp = 1, defence = 0 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 0, hp = 1, defence = 0 },
		[6] = { atk = 1, hp = 0, defence = 0 },
		[7] = { atk = 1, hp = 1, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 1, defence = 0 },
		[10] = { atk = 0, hp = 1, defence = 0 }
		}, 90, ""),

	["card_1000"] = CreateCard("card_1000", "Divine Fighter", CardCatalog.Rarities.LEGENDARY, CardCatalog.Classes.DPS, { -- Goku
		atk = 9,
		hp = 4,
		defence = 0
	}, 1000, {
		[2] = { atk = 1, hp = 1, defence = 0 },
		[3] = { atk = 1, hp = 1, defence = 0 },
		[4] = { atk = 1, hp = 1, defence = 0 },
		[5] = { atk = 1, hp = 1, defence = 0 },
		[6] = { atk = 1, hp = 1, defence = 0 },
		[7] = { atk = 1, hp = 1, defence = 0 },
		[8] = { atk = 1, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 1, defence = 0 },
		[10] = { atk = 1, hp = 1, defence = 0 }
		}, 100, ""),

	["card_1100"] = CreateCard("card_1100", "Deception Ace", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.SUPPORT, { -- Usopp
		atk = 1,
		hp = 3,
		defence = 0
	}, 1100, {
		[2] = { atk = 0, hp = 1, defence = 0 },
		[3] = { atk = 1, hp = 0, defence = 0 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 0, hp = 1, defence = 0 },
		[6] = { atk = 1, hp = 0, defence = 0 },
		[7] = { atk = 0, hp = 1, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 0, defence = 0 },
		[10] = { atk = 0, hp = 1, defence = 0 }
		}, 110, "", { CardCatalog.Rarities.ONEPIECE }),

	["card_1200"] = CreateCard("card_1200", "Symbol of Peace", CardCatalog.Rarities.EPIC, CardCatalog.Classes.DPS, { -- All Might
		atk = 5,
		hp = 3,
		defence = 0
	}, 1200, {
		[2] = { atk = 1, hp = 1, defence = 0 },
		[3] = { atk = 1, hp = 0, defence = 0 },
		[4] = { atk = 1, hp = 1, defence = 0 },
		[5] = { atk = 1, hp = 1, defence = 0 },
		[6] = { atk = 0, hp = 0, defence = 1 },
		[7] = { atk = 1, hp = 1, defence = 0 },
		[8] = { atk = 1, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 0, defence = 0 },
		[10] = { atk = 1, hp = 1, defence = 0 }
		}, 120, ""),

	["card_1300"] = CreateCard("card_1300", "Beast Doctor", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.SUPPORT, { -- Chopper
		atk = 1,
		hp = 2,
		defence = 0
	}, 1300, {
		[2] = { atk = 0, hp = 1, defence = 0 },
		[3] = { atk = 1, hp = 0, defence = 0 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 0, hp = 1, defence = 0 },
		[6] = { atk = 1, hp = 0, defence = 0 },
		[7] = { atk = 0, hp = 1, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 0, defence = 0 },
		[10] = { atk = 0, hp = 1, defence = 0 }
		}, 130, "", nil, { CardCatalog.Rarities.ONEPIECE }),

	["card_1400"] = CreateCard("card_1400", "Solar Strike", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.SUPPORT, { -- Krillin
		atk = 1,
		hp = 2,
		defence = 0
	}, 1400, {
		[2] = { atk = 1, hp = 0, defence = 0 },
		[3] = { atk = 1, hp = 0, defence = 0 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 1, hp = 0, defence = 0 },
		[6] = { atk = 1, hp = 0, defence = 0 },
		[7] = { atk = 1, hp = 0, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 0, defence = 0 },
		[10] = { atk = 1, hp = 0, defence = 0 }
		}, 140, ""),

	["card_1500"] = CreateCard("card_1500", "Blast Pulse", CardCatalog.Rarities.RARE, CardCatalog.Classes.DPS, { -- Bakugo
		atk = 4,
		hp = 2,
		defence = 0
	}, 1500, {
		[2] = { atk = 1, hp = 1, defence = 0 },
		[3] = { atk = 1, hp = 0, defence = 0 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 1, hp = 0, defence = 0 },
		[6] = { atk = 1, hp = 1, defence = 0 },
		[7] = { atk = 1, hp = 0, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 0, defence = 0 },
		[10] = { atk = 1, hp = 1, defence = 0 }
		}, 150, ""),

	["card_1600"] = CreateCard("card_1600", "Desert Wolf", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.DPS, { -- Yamcha
		atk = 0,
		hp = 1,
		defence = 0
	}, 1600, {
		[2] = { atk = 0, hp = 1, defence = 0 },
		[3] = { atk = 0, hp = 1, defence = 0 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 0, hp = 1, defence = 0 },
		[6] = { atk = 0, hp = 1, defence = 0 },
		[7] = { atk = 0, hp = 1, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 0, hp = 1, defence = 0 },
		[10] = { atk = 0, hp = 1, defence = 0 }
		}, 160, ""),

	["card_1700"] = CreateCard("card_1700", "Power Heir", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.DPS, { -- Midoriya
		atk = 1,
		hp = 1,
		defence = 0
	}, 1700, {
		[2] = { atk = 0, hp = 1, defence = 0 },
		[3] = { atk = 1, hp = 0, defence = 0 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 1, hp = 0, defence = 0 },
		[6] = { atk = 0, hp = 1, defence = 0 },
		[7] = { atk = 1, hp = 0, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 0, defence = 0 },
		[10] = { atk = 0, hp = 1, defence = 0 }
		}, 170, ""),

	["card_1800"] = CreateCard("card_1800", "Emerald Monk", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.SUPPORT, { -- Piccolo
		atk = 3,
		hp = 1,
		defence = 0
	}, 1800, {
		[2] = { atk = 1, hp = 0, defence = 0 },
		[3] = { atk = 0, hp = 1, defence = 0 },
		[4] = { atk = 1, hp = 0, defence = 0 },
		[5] = { atk = 1, hp = 0, defence = 0 },
		[6] = { atk = 0, hp = 1, defence = 0 },
		[7] = { atk = 1, hp = 0, defence = 0 },
		[8] = { atk = 1, hp = 0, defence = 0 },
		[9] = { atk = 0, hp = 1, defence = 0 },
		[10] = { atk = 1, hp = 0, defence = 0 }
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
		if card.specialBox then 
			for i = 1, #card.specialBox do
				if card.specialBox[i] == rarity then
					table.insert(cards, card)
				end
			end
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
