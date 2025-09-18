--[[
	Assets Manifest - Centralized asset definitions
	
	Provides asset IDs and colors for UI development.
	TODO: Replace placeholder asset IDs with actual content.
]]

local Manifest = {}

-- Card images (TODO: Replace with actual card art)
Manifest.CardImages = {
	-- Legendary cards
	["card_100"] = "rbxassetid://0",  -- Monkey D. Luffy
	["card_200"] = "rbxassetid://0",  -- Roronoa Zoro
	["card_800"] = "rbxassetid://0",  -- Vegeta
	["card_1000"] = "rbxassetid://0", -- Goku
	
	-- Epic cards
	["card_300"] = "rbxassetid://0",  -- Rock Lee
	["card_400"] = "rbxassetid://0",  -- Tsunade
	["card_1200"] = "rbxassetid://0", -- All Might
	
	-- Rare cards
	["card_500"] = "rbxassetid://0",  -- Sanji
	["card_900"] = "rbxassetid://0",  -- Shino Aburame
	["card_1500"] = "rbxassetid://0", -- Bakugo
	
	-- Uncommon cards
	["card_600"] = "rbxassetid://0",  -- Tenten
	["card_700"] = "rbxassetid://0",  -- Koby
	["card_1100"] = "rbxassetid://0", -- Usopp
	["card_1300"] = "rbxassetid://0", -- Chopper
	["card_1400"] = "rbxassetid://0", -- Krillin
	["card_1600"] = "rbxassetid://0", -- Yamcha
	["card_1700"] = "rbxassetid://0", -- Midoriya
	["card_1800"] = "rbxassetid://0", -- Piccolo
}

-- Class icons (TODO: Replace with actual class icons)
Manifest.ClassIcons = {
	["DPS"] = "rbxassetid://0",     -- TODO: Add DPS class icon
	["Support"] = "rbxassetid://0", -- TODO: Add Support class icon
	["Tank"] = "rbxassetid://0",    -- TODO: Add Tank class icon
}

-- Rarity frames (TODO: Replace with actual frame images)
Manifest.RarityFrames = {
	["Common"] = "rbxassetid://0",     -- TODO: Add Common frame
	["Rare"] = "rbxassetid://0",       -- TODO: Add Rare frame
	["Epic"] = "rbxassetid://0",       -- TODO: Add Epic frame
	["Legendary"] = "rbxassetid://0",  -- TODO: Add Legendary frame
}

-- Rarity colors (base UI colors)
Manifest.RarityColors = {
	["Uncommon"] = Color3.fromRGB(150, 150, 150),     -- Gray
	["Rare"] = Color3.fromRGB(0, 150, 255),         -- Blue
	["Epic"] = Color3.fromRGB(150, 0, 255),         -- Purple
	["Legendary"] = Color3.fromRGB(255, 150, 0),    -- Orange
}

-- Placeholder assets (fallbacks)
Manifest.Placeholder = {
	card = "rbxassetid://0",   -- TODO: Add placeholder card image
	icon = "rbxassetid://0",   -- TODO: Add placeholder icon
	frame = "rbxassetid://0",  -- TODO: Add placeholder frame
}

-- UI Colors
Manifest.UIColors = {
	-- Background colors
	background = Color3.fromRGB(40, 40, 40),
	cardBackground = Color3.fromRGB(60, 60, 60),
	panelBackground = Color3.fromRGB(50, 50, 50),
	
	-- Text colors
	textPrimary = Color3.fromRGB(255, 255, 255),
	textSecondary = Color3.fromRGB(200, 200, 200),
	textMuted = Color3.fromRGB(150, 150, 150),
	
	-- Accent colors
	accent = Color3.fromRGB(0, 150, 255),
	success = Color3.fromRGB(0, 200, 100),
	warning = Color3.fromRGB(255, 200, 0),
	error = Color3.fromRGB(255, 100, 100),
	
	-- Border colors
	border = Color3.fromRGB(80, 80, 80),
	borderHover = Color3.fromRGB(120, 120, 120),
}

-- Button colors
Manifest.ButtonColors = {
	normal = Color3.fromRGB(80, 80, 80),
	hover = Color3.fromRGB(100, 100, 100),
	pressed = Color3.fromRGB(60, 60, 60),
	disabled = Color3.fromRGB(50, 50, 50),
}

-- Currency assets
Manifest.Currency = {
	Soft = {
		Big = "rbxassetid://89868675992699",
		Small = "rbxassetid://89868675992699",
		Default = "rbxassetid://89868675992699",
	},
	Hard = {
		Big = "rbxassetid://119227133814721",
		Small = "rbxassetid://119227133814721",
		Default = "rbxassetid://119227133814721",
	}
}

-- Lootbox assets
Manifest.Lootbox = {
	Uncommon = "rbxassetid://120779810734215",
	Rare = "rbxassetid://98806708559504",
	Epic = "rbxassetid://105047250692120",
	Legendary = "rbxassetid://84532524924272",
}

-- Pattern assets
Manifest.Pattern = {
	Black = "rbxassetid://93175509252476",
	White = "rbxassetid://129772965319979",
}

-- HUD button assets
Manifest.HUDIcon = {
	Shop = "rbxassetid://0",
	Deck = "rbxassetid://0",
	Daily = "rbxassetid://0",
	Playtime = "rbxassetid://0",
}

return Manifest
