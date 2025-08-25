--[[
	UI Integration Types and Constants
	
	This module provides shared type definitions and constant enums
	used by both client and server for consistent data handling.
]]

local Types = {}

-- Rarity enum
Types.Rarity = {
	Common = "Common",
	Rare = "Rare", 
	Epic = "Epic",
	Legendary = "Legendary"
}

-- Class enum
Types.Class = {
	DPS = "DPS",
	Support = "Support",
	Tank = "Tank"
}

-- Lootbox state enum
Types.LootboxState = {
	Idle = "idle",
	Unlocking = "unlocking",
	Ready = "ready"
}

-- Collection entry type (v2 format)
-- CollectionEntry = { count: number, level: number }
Types.CollectionEntry = {} -- Type only, no runtime validation

-- Deck type (6 unique cardIds)
-- Deck = { string, string, string, string, string, string }
Types.Deck = {} -- Type only, no runtime validation

-- Lootbox entry type
-- LootboxEntry = { 
--   id: string, 
--   rarity: Rarity, 
--   state: LootboxState, 
--   acquiredAt: number, 
--   startedAt: number?, 
--   endsAt: number? 
-- }
Types.LootboxEntry = {} -- Type only, no runtime validation

-- Profile v2 type
-- ProfileV2 = {
--   version: number,
--   playerId: string,
--   createdAt: number,
--   lastLoginAt: number,
--   loginStreak: number,
--   collection: { [string]: CollectionEntry },
--   deck: Deck,
--   currencies: { soft: number?, hard: number? },
--   favoriteLastSeen: number?,
--   tutorialStep: number,
--   squadPower: number,
--   lootboxes: { LootboxEntry }
-- }
Types.ProfileV2 = {} -- Type only, no runtime validation

-- Network payload types (types only, no runtime validation)
-- ProfileUpdatedPayload = { 
--   deck: Deck?, 
--   collectionSummary: any?, 
--   loginInfo: any?, 
--   squadPower: number?, 
--   lootboxes: { LootboxEntry }?, 
--   updatedAt: number?, 
--   serverNow: number?, 
--   error: { code: string, message: string }? 
-- }
Types.ProfileUpdatedPayload = {} -- Type only, no runtime validation

-- MatchResponse = { 
--   ok: boolean, 
--   matchId: string?, 
--   seed: number|string?, 
--   result: any?, 
--   log: any?, 
--   serverNow: number?, 
--   error: { code: string, message: string }? 
-- }
Types.MatchResponse = {} -- Type only, no runtime validation

return Types
