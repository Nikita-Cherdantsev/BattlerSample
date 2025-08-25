local Utilities = {}

Utilities.Audio = require(script.Audio)
Utilities.ButtonHandler = require(script.FrameOpening)
Utilities.ButtonAnimations = require(script.ButtonAnimations)
Utilities.Dropdown = require(script.Dropdown)
Utilities.Icons = require(script.Icons)
Utilities.Particles = require(script.Particles)
Utilities.Popup = require(script.Popup)
Utilities.Short = require(script.Short)
Utilities.Tween = require(script.Tween)
Utilities.TweenUI = require(script.TweenUI)
Utilities.Typewrite = require(script.Typewrite)

-- Card Battler MVP Modules (v2)
Utilities.CardCatalog = require(script.Cards.CardCatalog)
Utilities.CardLevels = require(script.Cards.CardLevels)
Utilities.CardStats = require(script.Cards.CardStats)
Utilities.DeckValidator = require(script.Cards.DeckValidator)
Utilities.SeededRNG = require(script.RNG.SeededRNG)
Utilities.CombatTypes = require(script.Combat.CombatTypes)
Utilities.CombatUtils = require(script.Combat.CombatUtils)
Utilities.GameConstants = require(script.Constants.GameConstants)
Utilities.UIConstants = require(script.Constants.UIConstants)
Utilities.SelfCheck = require(script.SelfCheck)

-- UI Integration Modules
Utilities.Types = require(script.Types)
Utilities.ErrorMap = require(script.ErrorMap)
Utilities.BoardLayout = require(script.BoardLayout)
Utilities.TimeUtils = require(script.TimeUtils)

-- Assets
Utilities.Assets = {
	Manifest = require(script.Assets.Manifest),
	Resolver = require(script.Assets.Resolver)
}

return Utilities
