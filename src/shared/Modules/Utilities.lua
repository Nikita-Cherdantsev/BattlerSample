local Utilities = {}

-- Safe require function
local function safeRequire(modulePath, fallback)
	local success, module = pcall(require, modulePath)
	if success then
		return module
	else
		if fallback then
			return fallback
		end
		-- Return a stub module that won't crash
		return {
			-- Add common methods that might be called
			GetAllCards = function() return {} end,
			ValidateDeck = function() return true, "Stub validator" end,
			GetCardStats = function() return {} end,
			-- Add any other methods that might be needed
		}
	end
end

-- UI Utilities (safe to require on both client and server)
Utilities.Audio = safeRequire(script.Audio)
Utilities.Blur = safeRequire(script.Blur)
Utilities.ButtonHandler = safeRequire(script.FrameOpening)
Utilities.ButtonAnimations = safeRequire(script.ButtonAnimations)
Utilities.Dropdown = safeRequire(script.Dropdown)
Utilities.Icons = safeRequire(script.Icons)
Utilities.Particles = safeRequire(script.Particles)
Utilities.Popup = safeRequire(script.Popup)
Utilities.Short = safeRequire(script.Short)
Utilities.Tween = safeRequire(script.Tween)
Utilities.TweenUI = safeRequire(script.TweenUI)
Utilities.Typewrite = safeRequire(script.Typewrite)

-- Card Battler MVP Modules (v2) - may not be available on client
-- Use absolute path to avoid module loading issues
local Cards = script.Parent:FindFirstChild("Cards")
if Cards then
	Utilities.CardCatalog = safeRequire(Cards.CardCatalog)
	Utilities.CardLevels = safeRequire(Cards.CardLevels)
	Utilities.CardStats = safeRequire(Cards.CardStats)
	Utilities.DeckValidator = safeRequire(Cards.DeckValidator)
else
	-- Fallback if Cards folder not found
	Utilities.CardCatalog = { GetAllCards = function() return {} end }
	Utilities.CardLevels = { GetLevel = function() return 1 end }
	Utilities.CardStats = { GetStats = function() return {} end }
	Utilities.DeckValidator = { ValidateDeck = function() return true, "Stub validator" end }
end
Utilities.SeededRNG = safeRequire(script.Parent.RNG.SeededRNG)
Utilities.CombatTypes = safeRequire(script.Parent.Combat.CombatTypes)
Utilities.CombatUtils = safeRequire(script.Parent.Combat.CombatUtils)
Utilities.GameConstants = safeRequire(script.Parent.Constants.GameConstants)
Utilities.UIConstants = safeRequire(script.Parent.Constants.UIConstants)
Utilities.SelfCheck = safeRequire(script.Parent.SelfCheck)

-- UI Integration Modules (safe to require on both client and server)
Utilities.Types = safeRequire(script.Parent.Types)
Utilities.ErrorMap = safeRequire(script.Parent.ErrorMap)
Utilities.BoardLayout = safeRequire(script.Parent.BoardLayout)
Utilities.TimeUtils = safeRequire(script.Parent.TimeUtils)

-- Assets (safe to require on both client and server)
Utilities.Assets = {
	Manifest = safeRequire(script.Parent.Assets.Manifest),
	Resolver = safeRequire(script.Parent.Assets.Resolver)
}

-- Lootbox System Modules (safe to require on both client and server)
Utilities.BoxTypes = safeRequire(script.Parent.Loot.BoxTypes)
Utilities.BoxDropTables = safeRequire(script.Parent.Loot.BoxDropTables)
Utilities.BoxRoller = safeRequire(script.Parent.Loot.BoxRoller)
Utilities.BoxValidator = safeRequire(script.Parent.Loot.BoxValidator)

-- Shop System Modules (safe to require on both client and server)
Utilities.ShopPacksCatalog = safeRequire(script.Parent.Shop.ShopPacksCatalog)

return Utilities
