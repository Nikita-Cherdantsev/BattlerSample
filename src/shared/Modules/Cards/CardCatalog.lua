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
-- NOTE: Catalog historically calls this helper with an extra, unused argument in some places.
-- Keep varargs to avoid Luau linter warnings without changing runtime behavior.
local function CreateCard(id, name, rarity, class, baseStats, slotNumber, growth, description, passive, specialBox, ...)
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
	}, 100, "", nil, { CardCatalog.Rarities.ONEPIECE }),
	
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
	}, 200, "", nil, { CardCatalog.Rarities.ONEPIECE }),
	
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
	}, 300, ""),
	
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
	}, 400, ""),
	
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
	}, 500, "", { CardCatalog.Rarities.ONEPIECE }),
	
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
	}, 600, ""),
	
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
		}, 700, "", nil, { CardCatalog.Rarities.ONEPIECE }),
	
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
		}, 800, ""),

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
		}, 900, ""),

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
		}, 1000, ""),

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
		}, 1100, "", { CardCatalog.Rarities.ONEPIECE }),

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
		}, 1200, ""),

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
		}, 1300, "", nil, { CardCatalog.Rarities.ONEPIECE }),

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
		}, 1400, ""),

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
		}, 1500, ""),

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
		}, 1600, ""),

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
		}, 1700, ""),

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
		}, 1800, ""),

	-- 2026-01 content drop: new cards (no passives yet; stats only)
	-- IMPORTANT: slotNumber controls board ordering (lower = earlier/front).
	-- Tanks are placed earlier, DPS mid, Supports later.

	["card_30"] = CreateCard("card_30", "Desert King", CardCatalog.Rarities.EPIC, CardCatalog.Classes.TANK, { -- Gaara
		atk = 1,
		hp = 7,
		defence = 1
	}, 30, {
		[2] = { atk = 1, hp = 1, defence = 0 },
		[3] = { atk = 0, hp = 0, defence = 1 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 0, hp = 1, defence = 0 },
		[6] = { atk = 1, hp = 0, defence = 1 },
		[7] = { atk = 0, hp = 2, defence = 0 },
		[8] = { atk = 0, hp = 2, defence = 0 },
		[9] = { atk = 0, hp = 1, defence = 0 },
		[10] = { atk = 0, hp = 1, defence = 1 }
	}, 30, "Unbreakable tank/control archetype (no abilities yet)."),

	["card_230"] = CreateCard("card_230", "Endless Will", CardCatalog.Rarities.LEGENDARY, CardCatalog.Classes.DPS, { -- Naruto
		atk = 7,
		hp = 6,
		defence = 1
	}, 230, {
		[2] = { atk = 1, hp = 1, defence = 0 },
		[3] = { atk = 1, hp = 1, defence = 0 },
		[4] = { atk = 1, hp = 0, defence = 1 },
		[5] = { atk = 1, hp = 1, defence = 0 },
		[6] = { atk = 1, hp = 1, defence = 0 },
		[7] = { atk = 1, hp = 0, defence = 1 },
		[8] = { atk = 1, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 1, defence = 0 },
		[10] = { atk = 1, hp = 1, defence = 1 }
	}, 230, "Legendary bruiser DPS archetype (no abilities yet)."),

	["card_330"] = CreateCard("card_330", "Future Sight", CardCatalog.Rarities.EPIC, CardCatalog.Classes.DPS, { -- Charlotte Katakuri
		atk = 3,
		hp = 7,
		defence = 1
	}, 330, {
		[2] = { atk = 1, hp = 1, defence = 0 },
		[3] = { atk = 0, hp = 1, defence = 1 },
		[4] = { atk = 1, hp = 1, defence = 0 },
		[5] = { atk = 0, hp = 1, defence = 0 },
		[6] = { atk = 0, hp = 2, defence = 0 },
		[7] = { atk = 1, hp = 0, defence = 0 },
		[8] = { atk = 0, hp = 2, defence = 1 },
		[9] = { atk = 0, hp = 1, defence = 0 },
		[10] = { atk = 1, hp = 1, defence = 0 }
	}, 330, "Elite bruiser DPS archetype (no abilities yet).", nil, { CardCatalog.Rarities.ONEPIECE }),

	["card_550"] = CreateCard("card_550", "Eternal Vengeance", CardCatalog.Rarities.LEGENDARY, CardCatalog.Classes.DPS, { -- Sasuke
		atk = 8,
		hp = 4,
		defence = 0
	}, 550, {
		[2] = { atk = 1, hp = 1, defence = 0 },
		[3] = { atk = 1, hp = 0, defence = 0 },
		[4] = { atk = 1, hp = 0, defence = 0 },
		[5] = { atk = 1, hp = 1, defence = 0 },
		[6] = { atk = 1, hp = 0, defence = 0 },
		[7] = { atk = 1, hp = 0, defence = 0 },
		[8] = { atk = 1, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 1, defence = 0 },
		[10] = { atk = 2, hp = 0, defence = 0 }
	}, 550, "Legendary assassin DPS archetype (no abilities yet)."),

	["card_570"] = CreateCard("card_570", "Strongest Blade", CardCatalog.Rarities.LEGENDARY, CardCatalog.Classes.DPS, { -- Levi Ackerman
		atk = 7,
		hp = 5,
		defence = 0
	}, 570, {
		[2] = { atk = 1, hp = 0, defence = 0 },
		[3] = { atk = 1, hp = 1, defence = 0 },
		[4] = { atk = 1, hp = 0, defence = 0 },
		[5] = { atk = 1, hp = 1, defence = 0 },
		[6] = { atk = 1, hp = 0, defence = 0 },
		[7] = { atk = 1, hp = 1, defence = 0 },
		[8] = { atk = 1, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 1, defence = 0 },
		[10] = { atk = 2, hp = 1, defence = 0 }
	}, 570, "Legendary melee DPS archetype (no abilities yet)."),

	["card_440"] = CreateCard("card_440", "Lightning Assassin", CardCatalog.Rarities.EPIC, CardCatalog.Classes.DPS, { -- Killua
		atk = 4,
		hp = 3,
		defence = 0
	}, 440, {
		[2] = { atk = 1, hp = 0, defence = 0 }, 
		[3] = { atk = 1, hp = 1, defence = 0 },
		[4] = { atk = 1, hp = 0, defence = 0 },
		[5] = { atk = 1, hp = 0, defence = 0 },
		[6] = { atk = 1, hp = 1, defence = 0 },
		[7] = { atk = 1, hp = 0, defence = 0 },
		[8] = { atk = 1, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 0, defence = 0 },
		[10] = { atk = 2, hp = 2, defence = 0 }
	}, 440, "Epic assassin DPS archetype (no abilities yet)."),

	["card_460"] = CreateCard("card_460", "Shadow Monarch", CardCatalog.Rarities.EPIC, CardCatalog.Classes.DPS, { -- Sung Jin-Woo
		atk = 4,
		hp = 4,
		defence = 0
	}, 460, {
		[2] = { atk = 0, hp = 1, defence = 0 },
		[3] = { atk = 1, hp = 0, defence = 0 },
		[4] = { atk = 1, hp = 1, defence = 0 },
		[5] = { atk = 0, hp = 1, defence = 0 },
		[6] = { atk = 1, hp = 0, defence = 0 },
		[7] = { atk = 1, hp = 1, defence = 0 },
		[8] = { atk = 1, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 1, defence = 0 },
		[10] = { atk = 1, hp = 1, defence = 0 }
	}, 460, "Epic scaling DPS archetype (no abilities yet)."),

	["card_480"] = CreateCard("card_480", "Deadeye Scout", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.DPS, { -- Sasha Blouse
		atk = 1,
		hp = 2,
		defence = 0
	}, 480, {
		[2] = { atk = 1, hp = 0, defence = 0 },
		[3] = { atk = 0, hp = 1, defence = 0 },
		[4] = { atk = 1, hp = 0, defence = 0 },
		[5] = { atk = 0, hp = 1, defence = 0 },
		[6] = { atk = 1, hp = 0, defence = 0 },
		[7] = { atk = 0, hp = 1, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 0, defence = 0 },
		[10] = { atk = 0, hp = 1, defence = 0 }
	}, 480, "Uncommon ranged DPS archetype (no abilities yet)."),

	["card_1130"] = CreateCard("card_1130", "Soul Swordsman", CardCatalog.Rarities.RARE, CardCatalog.Classes.DPS, { -- Brook
		atk = 3,
		hp = 3,
		defence = 0
	}, 1130, {
		[2] = { atk = 0, hp = 1, defence = 0 },
		[3] = { atk = 1, hp = 0, defence = 0 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 1, hp = 0, defence = 0 },
		[6] = { atk = 0, hp = 1, defence = 0 },
		[7] = { atk = 1, hp = 0, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 1, defence = 0 },
		[10] = { atk = 2, hp = 1, defence = 0 }
	}, 1130, "Rare DPS/control archetype (no abilities yet).", nil, { CardCatalog.Rarities.ONEPIECE }),

	["card_340"] = CreateCard("card_340", "Combat Medic", CardCatalog.Rarities.RARE, CardCatalog.Classes.SUPPORT, { -- Leorio
		atk = 1,
		hp = 5,
		defence = 1
	}, 340, {
		[2] = { atk = 0, hp = 1, defence = 0 },
		[3] = { atk = 1, hp = 0, defence = 0 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 0, hp = 1, defence = 0 },
		[6] = { atk = 1, hp = 0, defence = 1 },
		[7] = { atk = 0, hp = 1, defence = 0 },
		[8] = { atk = 1, hp = 0, defence = 0 },
		[9] = { atk = 0, hp = 0, defence = 1 },
		[10] = { atk = 1, hp = 0, defence = 0 }
	}, 340, "Rare support/bruiser archetype (no abilities yet)."),

	["card_260"] = CreateCard("card_260", "Weather Witch", CardCatalog.Rarities.RARE, CardCatalog.Classes.SUPPORT, { -- Nami
		atk = 1,
		hp = 4,
		defence = 1
	}, 260, {
		[2] = { atk = 0, hp = 1, defence = 0 },
		[3] = { atk = 0, hp = 1, defence = 1 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 0, hp = 1, defence = 0 },
		[6] = { atk = 0, hp = 0, defence = 1 },
		[7] = { atk = 0, hp = 1, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 1, defence = 0 },
		[10] = { atk = 0, hp = 1, defence = 1 }
	}, 260, "Rare support/control archetype (no abilities yet).", nil, { CardCatalog.Rarities.ONEPIECE }),

	["card_290"] = CreateCard("card_290", "Thousand Hands", CardCatalog.Rarities.RARE, CardCatalog.Classes.SUPPORT, { -- Nico Robin
		atk = 2,
		hp = 4,
		defence = 1
	}, 290, {
		[2] = { atk = 0, hp = 1, defence = 0 },
		[3] = { atk = 0, hp = 1, defence = 1 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 0, hp = 0, defence = 1 },
		[6] = { atk = 0, hp = 1, defence = 0 },
		[7] = { atk = 1, hp = 0, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 0, hp = 1, defence = 1 },
		[10] = { atk = 1, hp = 0, defence = 0 }
	}, 290, "Rare control/support archetype (no abilities yet).", nil, { CardCatalog.Rarities.ONEPIECE }),

	["card_420"] = CreateCard("card_420", "Master Strategist", CardCatalog.Rarities.UNCOMMON, CardCatalog.Classes.SUPPORT, { -- Armin Arlert
		atk = 1,
		hp = 3,
		defence = 0
	}, 420, {
		[2] = { atk = 0, hp = 1, defence = 1 },
		[3] = { atk = 0, hp = 1, defence = 0 },
		[4] = { atk = 0, hp = 1, defence = 0 },
		[5] = { atk = 0, hp = 1, defence = 0 },
		[6] = { atk = 0, hp = 1, defence = 1 },
		[7] = { atk = 0, hp = 1, defence = 0 },
		[8] = { atk = 0, hp = 1, defence = 0 },
		[9] = { atk = 1, hp = 0, defence = 0 },
		[10] = { atk = 0, hp = 0, defence = 1 }
	}, 420, "Uncommon support/control archetype (no abilities yet).")
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
