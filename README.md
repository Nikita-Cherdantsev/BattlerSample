# Card Battler MVP - v2

A server-authoritative card battler game built in Roblox with deterministic combat, server-side persistence, and a minimal network surface.

## 🎯 Architecture Overview

### Core Principles
- **Server-Authoritative**: All critical game logic runs on the server
- **Deterministic Combat**: Same inputs always produce same results
- **Minimal Network Surface**: Only 2 RemoteEvents for MVP
- **Robust Persistence**: DataStore wrapper with retries and budget awareness

### Network Surface (MVP)
- `RequestStartMatch` - Start a battle simulation
- `OpenLootbox` - Open lootboxes (placeholder for future)

## 📊 Profile Schema v2

### Structure
```lua
{
  playerId = "string",           -- Roblox UserId
  createdAt = number,            -- Unix timestamp
  lastLoginAt = number,          -- Unix timestamp
  loginStreak = number,          -- Consecutive login days
  
  -- v2: Card collection with levels
  collection = {
    [cardId] = {
      count = number,            -- Number of copies owned
      level = number             -- Current level (1-7)
    }
  },
  
  deck = {cardId1, cardId2, ...}, -- Exactly 6 unique card IDs
  currencies = {soft = number, hard = number},
  
  -- v2: New fields
  favoriteLastSeen = number?,    -- Unix seconds of last "Like" bonus
  tutorialStep = number,         -- Tutorial progress (default 0)
  squadPower = number,           -- Computed power of current deck
  
  -- v2: Lootboxes (max 4, max 1 "unlocking")
  lootboxes = {
    {
      id = "string",
      rarity = "Common"|"Rare"|"Epic"|"Legendary",
      state = "idle"|"unlocking"|"ready",
      acquiredAt = number,
      startedAt = number?,
      endsAt = number?
    }
  }
}
```

### Migration (v1 → v2)
- Collection format: `{cardId: count}` → `{cardId: {count, level}}`
- All v1 cards start at level 1
- New fields added with defaults
- Lootboxes start empty

## 🃏 Card System v2

### Card Structure
```lua
{
  id = "string",
  name = "string",
  rarity = "common"|"rare"|"epic"|"legendary",
  class = "dps"|"support"|"tank",
  baseStats = {
    attack = number,    -- Level 1 base stats
    health = number,
    defence = number
  },
  slotNumber = number,  -- v2: Unique priority for deck ordering
  description = "string", -- v2: Card description
  passive = "string?"   -- Placeholder for future effects
}
```

### Leveling System
- **Max Level**: 7
- **Level Costs**:
  - L1→L2: 10 copies + 12,000 soft currency
  - L2→L3: 20 copies + 50,000 soft currency
  - L3→L4: 40 copies + 200,000 soft currency
  - L4→L5: 80 copies + 500,000 soft currency
  - L5→L6: 160 copies + 800,000 soft currency
  - L6→L7: 320 copies + 1,200,000 soft currency

- **Stat Increments** (per level, from L2):
  - ATK: +2
  - HP: +10
  - Defence: +2

### Power Calculation
```lua
power = floor((atk + defence + hp) / 3)
```

## 🎮 Combat System v2

### Turn Order
- **Fixed Order**: 1 → 2 → 3 → 4 → 5 → 6 (slot-based)
- Dead units skip their turn
- No speed-based ordering (deprecated)

### Targeting
- **Primary**: Same slot index on enemy board (1↔1, 2↔2, etc.)
- **Fallback**: Nearest living enemy by absolute index distance
- **Tie-breaker**: Lower slot index

### Damage Model (50% Defence Soak)
```lua
-- While defence > 0:
soak = floor(0.5 * incoming_damage)
if defence >= soak:
  defence -= soak
  hp -= (incoming_damage - soak)
else:
  soaked = defence
  defence = 0
  hp -= (incoming_damage - soaked)

-- If defence == 0:
hp -= incoming_damage
```

### Board Layout
```
Visual: [5] [3] [1]
        [6] [4] [2]

Slots assigned by slotNumber order:
- Lowest slotNumber → slot 1
- Highest slotNumber → slot 6
```

## 🎯 Deck System v2

### Validation Rules
- Exactly 6 cards
- All card IDs must exist in catalog
- **No duplicates allowed** (v2 change)
- **No collection count validation** (v2 change)

### Board Mapping
- Cards ordered by `slotNumber` (ascending)
- Assigned to slots 1-6 in that order
- Stable and deterministic

### Squad Power
- Computed when deck is set
- Sum of `computePower(currentStats)` for all 6 cards
- Uses current levels from collection
- Defaults to level 1 if card not in collection

## 🧪 Testing

### Self-Check Tests
```lua
-- Run all tests
local SelfCheck = require(game.ReplicatedStorage.Modules.SelfCheck)
SelfCheck.RunAllTests()
```

### Dev Harnesses
- **Persistence**: `src/server/Persistence/DevHarness.server.lua`
- **PlayerDataService**: `src/server/Services/PlayerDataServiceDevHarness.server.lua`
- **MatchService**: `src/server/Services/MatchServiceDevHarness.server.lua`
- **CombatEngine**: `src/server/Services/CombatEngineDevHarness.server.lua`
- **Client**: `src/client/MatchTestHarness.client.lua`

## 🔧 Development

### Key Modules
- **CardLevels**: Level progression and costs
- **CardStats**: Stat computation and power calculation
- **CombatEngine**: Deterministic battle simulation
- **ProfileManager**: DataStore persistence with v2 migration
- **PlayerDataService**: High-level player data management
- **MatchService**: Battle orchestration

### Public Helpers
- `CardStats.ComputeStats(cardId, level)` → `{atk, hp, defence}`
- `CardStats.ComputePower(stats)` → `number`
- `CardLevels.GetLevelCost(level)` → `{requiredCount, softAmount}`
- `CardLevels.CanLevelUp(cardId, currentLevel, count, currency)` → `boolean, error`

### Customization Points
- **Per-card level increments**: Add `levelIncrements` field to CardCatalog entries
- **Lootbox business logic**: Implement in future iterations
- **Passive effects**: Add to CombatEngine.ApplyPassiveEffects

## 🚀 Getting Started

1. **Setup**: Ensure Rojo is configured for the project
2. **Test**: Run `SelfCheck.RunAllTests()` to verify all systems
3. **Dev**: Use dev harnesses for isolated testing
4. **Play**: Start a match via `RequestStartMatch` RemoteEvent

## 📝 Notes

- **Speed field deprecated**: MVP uses fixed turn order
- **Collection count validation removed**: Deck composition independent of ownership
- **Lootboxes**: Schema ready, business logic pending
- **Migration**: v1 profiles automatically upgraded to v2
- **Determinism**: All combat outcomes are predictable given same seed
