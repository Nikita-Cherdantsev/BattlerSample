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
Utilities.CardCatalog = safeRequire(script.Cards.CardCatalog)
Utilities.CardLevels = safeRequire(script.Cards.CardLevels)
Utilities.CardStats = safeRequire(script.Cards.CardStats)
Utilities.DeckValidator = safeRequire(script.Cards.DeckValidator)
Utilities.SeededRNG = safeRequire(script.RNG.SeededRNG)
Utilities.CombatTypes = safeRequire(script.Combat.CombatTypes)
Utilities.CombatUtils = safeRequire(script.Combat.CombatUtils)
Utilities.GameConstants = safeRequire(script.Constants.GameConstants)
Utilities.UIConstants = safeRequire(script.Constants.UIConstants)
Utilities.SelfCheck = safeRequire(script.SelfCheck)

-- UI Integration Modules (safe to require on both client and server)
Utilities.Types = safeRequire(script.Types)
Utilities.ErrorMap = safeRequire(script.ErrorMap)
Utilities.BoardLayout = safeRequire(script.BoardLayout)
Utilities.TimeUtils = safeRequire(script.TimeUtils)

-- Assets (safe to require on both client and server)
Utilities.Assets = {
	Manifest = safeRequire(script.Assets.Manifest),
	Resolver = safeRequire(script.Assets.Resolver)
}

return Utilities
