--[[
	Assets Manifest - Centralized asset definitions
	
	Provides asset IDs and colors for UI development.
	TODO: Replace placeholder asset IDs with actual content.
]]

local Manifest = {}

-- Card images (TODO: Replace with actual card art)
Manifest.CardImages = {
	-- Legendary cards
	["card_100"] = "rbxassetid://78423585996740",  -- Monkey D. Luffy
	["card_200"] = "rbxassetid://129594750129124",  -- Roronoa Zoro
	["card_800"] = "rbxassetid://95838232303458",  -- Vegeta
	["card_1000"] = "rbxassetid://95259815635405", -- Goku
	
	-- Epic cards
	["card_300"] = "rbxassetid://109391071241644",  -- Rock Lee
	["card_400"] = "rbxassetid://129627997182384",  -- Tsunade
	["card_1200"] = "rbxassetid://129062570319296", -- All Might
	
	-- Rare cards
	["card_500"] = "rbxassetid://114047411638621",  -- Sanji
	["card_900"] = "rbxassetid://107307003564755",  -- Shino Aburame
	["card_1500"] = "rbxassetid://105914633790557", -- Bakugo
	
	-- Uncommon cards
	["card_600"] = "rbxassetid://117487006318467",  -- Tenten
	["card_700"] = "rbxassetid://123184517185097",  -- Koby
	["card_1100"] = "rbxassetid://102339751039385", -- Usopp
	["card_1300"] = "rbxassetid://114677338404508", -- Chopper
	["card_1400"] = "rbxassetid://76533453851792", -- Krillin
	["card_1600"] = "rbxassetid://119952205768312", -- Yamcha
	["card_1700"] = "rbxassetid://125875363703877", -- Midoriya
	["card_1800"] = "rbxassetid://82447764673886", -- Piccolo
}

-- Card images (TODO: Replace with actual card art)
Manifest.CardImagesDisabled = {
	-- Legendary cards
	["card_100"] = "rbxassetid://103328158193462",  -- Monkey D. Luffy
	["card_200"] = "rbxassetid://73595528391131",  -- Roronoa Zoro
	["card_800"] = "rbxassetid://86376646833476",  -- Vegeta
	["card_1000"] = "rbxassetid://101835154423145", -- Goku
	
	-- Epic cards
	["card_300"] = "rbxassetid://97638914176130",  -- Rock Lee
	["card_400"] = "rbxassetid://71898620972133",  -- Tsunade
	["card_1200"] = "rbxassetid://82108859330046", -- All Might
	
	-- Rare cards
	["card_500"] = "rbxassetid://140547037001157",  -- Sanji
	["card_900"] = "rbxassetid://131459926213865",  -- Shino Aburame
	["card_1500"] = "rbxassetid://120103825726197", -- Bakugo
	
	-- Uncommon cards
	["card_600"] = "rbxassetid://130833058606753",  -- Tenten
	["card_700"] = "rbxassetid://118833865011567",  -- Koby
	["card_1100"] = "rbxassetid://85594190253475", -- Usopp
	["card_1300"] = "rbxassetid://95964560683693", -- Chopper
	["card_1400"] = "rbxassetid://88854946101555", -- Krillin
	["card_1600"] = "rbxassetid://70847220149068", -- Yamcha
	["card_1700"] = "rbxassetid://101838142917431", -- Midoriya
	["card_1800"] = "rbxassetid://101009651230755", -- Piccolo
}

-- Class icons (TODO: Replace with actual class icons)
Manifest.ClassIcons = {
	["DPS"] = "rbxassetid://0",     -- TODO: Add DPS class icon
	["Support"] = "rbxassetid://0", -- TODO: Add Support class icon
	["Tank"] = "rbxassetid://0",    -- TODO: Add Tank class icon
}

-- Rarity frames (TODO: Replace with actual frame images)
Manifest.RarityFrames = {
	["Uncommon"] = "rbxassetid://0",     -- TODO: Add Uncommon frame
	["Rare"] = "rbxassetid://0",       -- TODO: Add Rare frame
	["Epic"] = "rbxassetid://0",       -- TODO: Add Epic frame
	["Legendary"] = "rbxassetid://0",  -- TODO: Add Legendary frame
}

-- Rarity colors (base UI colors)
Manifest.RarityColors = {
	["Uncommon"] = Color3.fromHex("7CD226"),     
	["Rare"] = Color3.fromHex("6294F6"),         
	["Epic"] = Color3.fromHex("BF51F6"),         
	["Legendary"] = Color3.fromHex("FBBA38"),    
}

Manifest.RarityColorsDisabled = {
	["Uncommon"] = Color3.fromHex("648643"),     
	["Rare"] = Color3.fromHex("566A92"),         
	["Epic"] = Color3.fromHex("845B99"),         
	["Legendary"] = Color3.fromHex("A9956B"),    
}

-- Rarity gradient colors
Manifest.RarityColorsGradient = {
	["Uncommon"] = Color3.fromHex("004132"),     
	["Rare"] = Color3.fromHex("001A5E"),         
	["Epic"] = Color3.fromHex("5B005D"),         
	["Legendary"] = Color3.fromHex("BE3D1D"),    
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
	Shop = "rbxassetid://98279351247805",
	Deck = "rbxassetid://116603307842496",
	Daily = "rbxassetid://96877636462338",
	Playtime = "rbxassetid://95074985955823",
}

return Manifest
