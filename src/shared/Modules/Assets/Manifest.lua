--[[
	Assets Manifest - Centralized asset definitions
	
	Provides asset IDs and colors for UI development.
	TODO: Replace placeholder asset IDs with actual content.
]]

local Manifest = {}

-- Card images (TODO: Replace with actual card art)
Manifest.CardImages = {
	-- DPS cards
	["dps_001"] = "rbxassetid://0", -- TODO: Add dps_001 card art
	["dps_002"] = "rbxassetid://0", -- TODO: Add dps_002 card art
	["dps_003"] = "rbxassetid://0", -- TODO: Add dps_003 card art
	["dps_004"] = "rbxassetid://0", -- TODO: Add dps_004 card art
	["dps_005"] = "rbxassetid://0", -- TODO: Add dps_005 card art
	
	-- Support cards
	["support_001"] = "rbxassetid://0", -- TODO: Add support_001 card art
	["support_002"] = "rbxassetid://0", -- TODO: Add support_002 card art
	["support_003"] = "rbxassetid://0", -- TODO: Add support_003 card art
	["support_004"] = "rbxassetid://0", -- TODO: Add support_004 card art
	["support_005"] = "rbxassetid://0", -- TODO: Add support_005 card art
	
	-- Tank cards
	["tank_001"] = "rbxassetid://0", -- TODO: Add tank_001 card art
	["tank_002"] = "rbxassetid://0", -- TODO: Add tank_002 card art
	["tank_003"] = "rbxassetid://0", -- TODO: Add tank_003 card art
	["tank_004"] = "rbxassetid://0", -- TODO: Add tank_004 card art
	["tank_005"] = "rbxassetid://0", -- TODO: Add tank_005 card art
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
	["Common"] = Color3.fromRGB(150, 150, 150),     -- Gray
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

return Manifest
