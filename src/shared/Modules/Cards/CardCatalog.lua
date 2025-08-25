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
	-- Common cards
	["dps_001"] = CreateCard("dps_001", "Recruit Fighter", CardCatalog.Rarities.COMMON, CardCatalog.Classes.DPS, {
		attack = 3,
		health = 4,
		defence = 1
	}, 10, "A basic fighter with balanced stats."),
	
	["support_001"] = CreateCard("support_001", "Novice Healer", CardCatalog.Rarities.COMMON, CardCatalog.Classes.SUPPORT, {
		attack = 2,
		health = 5,
		defence = 2
	}, 20, "A beginner healer with defensive capabilities."),
	
	-- Rare cards
	["tank_001"] = CreateCard("tank_001", "Iron Guard", CardCatalog.Rarities.RARE, CardCatalog.Classes.TANK, {
		attack = 2,
		health = 6,
		defence = 3
	}, 30, "A sturdy defender with high health and defence."),
	
	["dps_002"] = CreateCard("dps_002", "Veteran Warrior", CardCatalog.Rarities.RARE, CardCatalog.Classes.DPS, {
		attack = 5,
		health = 5,
		defence = 2
	}, 40, "An experienced warrior with high attack power."),
	
	["support_002"] = CreateCard("support_002", "Battle Cleric", CardCatalog.Rarities.RARE, CardCatalog.Classes.SUPPORT, {
		attack = 3,
		health = 4,
		defence = 3
	}, 50, "A combat-ready cleric with balanced abilities."),
	
	-- Epic cards
	["dps_003"] = CreateCard("dps_003", "Elite Berserker", CardCatalog.Rarities.EPIC, CardCatalog.Classes.DPS, {
		attack = 7,
		health = 4,
		defence = 1
	}, 60, "A powerful berserker with devastating attacks.", "placeholder_passive"),
	
	["tank_002"] = CreateCard("tank_002", "Steel Defender", CardCatalog.Rarities.EPIC, CardCatalog.Classes.TANK, {
		attack = 3,
		health = 8,
		defence = 4
	}, 70, "An elite defender with exceptional durability.", "placeholder_passive"),
	
	-- Legendary cards
	["dps_004"] = CreateCard("dps_004", "Champion Warlord", CardCatalog.Rarities.LEGENDARY, CardCatalog.Classes.DPS, {
		attack = 8,
		health = 7,
		defence = 3
	}, 80, "A legendary warrior with unmatched combat prowess.", "placeholder_passive")
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
