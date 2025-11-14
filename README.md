# BattlerSample - Anime Card Battler MVP

A server-authoritative, deterministic card battler game built on Roblox with a 3×2 board layout. Features profile management, card collection, deck building, and turn-based combat with fixed turn order and same-index targeting. The system includes offline development capabilities through mocks, comprehensive testing harnesses, and a client-side integration layer ready for UI development.

## Table of Contents

- [At a Glance](#at-a-glance)
- [Repository Structure](#repository-structure)
- [Runtime Architecture](#runtime-architecture)
- [Data & Persistence](#data--persistence)
- [Cards, Levels, Deck, Combat](#cards-levels-deck-combat)
- [Level-Up System](#level-up-system)
- [Collection Surface](#collection-surface)
- [Packs & Lootboxes](#packs--lootboxes)
- [Networking Surface](#networking-surface)
- [Client Integration Layer](#client-integration-layer)
- [Testing & Dev Harnesses](#testing--dev-harnesses)
- [Build & Dev Environment](#build--dev-environment)
- [Performance & Security Notes](#performance--security-notes)
- [What Changed in This Release](#what-changed-in-this-release)
- [Roadmap](#roadmap)
- [Glossary](#glossary)

## At a Glance

**MVP Features Implemented:**
- ✅ Profile system with v2 schema (collection, deck, currencies, lootboxes, squadPower)
- ✅ Card catalog with 8 cards (4 rarities, 3 classes, slot-based ordering)
- ✅ Card level-up system (1-10 levels, per-card growth tables, atomic persistence, squad power recomputation)
- ✅ Collection surface (unified catalog+ownership selector, CardVM handles unowned safely)
- ✅ Deck validation (6 unique cards, slot mapping by slotNumber)
- ✅ Deterministic combat engine (fixed turn order, same-index targeting, armor pool defence)
- ✅ Complete lootbox system (4-slot capacity, deterministic rewards, overflow handling, atomic operations)
- ✅ Shop integration (Developer Product packs + hard currency lootbox purchases)
- ✅ Network layer with rate limiting and concurrency guards (16 endpoints total)
- ✅ Client-side integration (NetworkClient, ClientState, ViewModels, LootboxesVM, ShopHandler)
- ✅ Offline development (mocks, dev panel, comprehensive testing)
- ✅ DataStore persistence with v1→v2 migration and atomic UpdateAsync operations

## Repository Structure

```
BattlerSample/
├── src/
│   ├── server/                    # Server-side logic and services
│   │   ├── Services/              # Core game services
│   │   │   ├── CombatEngine.lua
│   │   │   ├── MatchService.lua
│   │   │   ├── PlayerDataService.lua
│   │   │   ├── LootboxService.lua
│   │   │   ├── ShopService.lua
│   │   │   └── *DevHarness.server.lua  # Testing harnesses
│   │   ├── Persistence/           # DataStore layer and profile management
│   │   │   ├── DataStoreWrapper.lua
│   │   │   ├── ProfileSchema.lua
│   │   │   └── ProfileManager.lua
│   │   └── Network/               # RemoteEvent definitions and rate limiting
│   │       └── RemoteEvents.lua
│   ├── shared/                    # Shared modules used by both client and server
│   │   └── Modules/               # Core game logic and utilities
│   │       ├── Cards/             # CardCatalog, CardLevels, CardStats, DeckValidator
│   │       ├── Combat/            # CombatTypes, CombatUtils
│   │       ├── Loot/              # BoxTypes, BoxDropTables, BoxRoller, BoxValidator
│   │       ├── Shop/              # ShopPacksCatalog
│   │       ├── ViewModels/        # CardVM, DeckVM, ProfileVM, LootboxesVM
│   │       ├── Assets/            # Manifest, Resolver
│   │       ├── Constants/         # GameConstants, UIConstants
│   │       ├── RNG/               # SeededRNG
│   │       ├── UtilitiesModuleScripts/  # UI utilities (TweenUI, Blur, etc.)
│   │       ├── BoardLayout.lua
│   │       ├── ErrorMap.lua
│   │       ├── SelfCheck.lua
│   │       ├── TimeUtils.lua
│   │       ├── Types.lua
│   │       └── Utilities.lua
│   └── client/                    # Client-side integration and UI foundations
│       ├── Controllers/           # NetworkClient wrapper over RemoteEvents
│       │   └── NetworkClient.lua
│       ├── State/                 # ClientState store and selectors
│       │   ├── ClientState.lua
│       │   └── selectors.lua
│       ├── Dev/                   # Development tools
│       │   ├── DevPanel.client.lua
│       │   ├── MockData.lua
│       │   ├── MockNetwork.lua
│       │   └── VMHarness.client.lua
│       ├── Config.lua             # Client-side feature flags
│       ├── NetworkTest.client.lua
│       ├── MatchTestHarness.client.lua
│       └── Utilities.lua
├── docs/                          # Detailed documentation and guides
│   └── ui_integration.md          # Complete UI integration guide
└── default.project.json           # Rojo project configuration
```

**Directory Purposes:**
- **`src/server/`**: Server-authoritative game logic, persistence, and network endpoints
- **`src/shared/`**: Deterministic game rules, card data, and combat mechanics
- **`src/client/`**: UI integration layer, offline development tools, and state management
- **`docs/`**: Comprehensive guides for UI integration and development

## Runtime Architecture

**Trust Boundaries:**
- **Server**: Authoritative for all game state, combat outcomes, and data persistence
- **Client**: UI-only; receives validated data and sends user actions
- **Shared**: Deterministic game rules that both client and server can compute

**Data Flow:**
```
Client UI ←→ ClientState ←→ NetworkClient ←→ RemoteEvents ←→ Services ←→ Persistence
                ↑              ↑                ↑              ↑          ↑
            ViewModels    MockNetwork      Rate Limiting   Combat    DataStore
```

**Determinism Guarantees:**
- **Turn Order**: Fixed sequence 1→2→3→4→5→6 (slot-based)
- **Targeting**: Same-index priority, nearest living fallback, lower index tiebreaker
- **RNG**: Seeded random number generation for reproducible combat outcomes
- **Combat**: Integer math with armour pool damage reduction (defence depletes first, residual to HP)

## Data & Persistence

### Profile Schema v2

```lua
Profile = {
    -- Core identity
    playerId = string,           -- Roblox UserId
    createdAt = number,          -- Unix timestamp
    lastLoginAt = number,        -- Unix timestamp
    loginStreak = number,        -- Consecutive login days
    
    -- Card system
    collection = {               -- cardId -> { count: number, level: number }
        ["dps_001"] = { count = 2, level = 1 },
        ["tank_001"] = { count = 1, level = 3 }
    },
    deck = {string, string, string, string, string, string}, -- 6 unique cardIds
    
    -- Progression
    currencies = { soft = number, hard = number },
    favoriteLastSeen = number?,  -- Unix timestamp
    tutorialStep = number,       -- Tutorial progress (0+)
    squadPower = number,         -- Computed deck power
    
    -- Lootboxes
    lootboxes = {                -- Array of LootboxEntry, max 4, max 1 "unlocking"
        {
            id = string,
            rarity = "common"|"rare"|"epic"|"legendary",
            state = "idle"|"unlocking"|"ready",
            acquiredAt = number,
            startedAt = number?,  -- When unlocking began
            endsAt = number?      -- When unlocking completes
        }
    }
}
```

**Persistence Details:**
- **DataStore**: Named `"v2"` with exponential backoff retry logic
- **Autosave**: On profile changes with `BindToClose` safety
- **Key Pattern**: `"profile_" .. playerId` for isolation
- **Validation**: Structural constraints only (no business logic validation on write)
- **Atomic Operations**: All mutations use `UpdateAsync` for atomic resource deduction and state updates
- **Squad Power**: Automatically recomputed when upgraded card is in active deck
- **Receipt Ledger**: Idempotent purchase processing with `PurchaseId` tracking
- **Array Compaction**: Lootbox arrays are packed after operations to maintain consistency

**v1→v2 Migration:**
- **Collection Format**: `count: number` → `{ count: number, level: number }`
- **New Fields**: `favoriteLastSeen`, `tutorialStep`, `squadPower`, `lootboxes`
- **Safe Defaults**: Missing fields get sensible defaults, existing data preserved
- **Automatic**: Runs on profile load, idempotent for multiple runs

## Cards, Levels, Deck, Combat

### CardCatalog

**Metadata Structure:**
```lua
Card = {
    id = string,                 -- Unique identifier (e.g., "dps_001")
    name = string,               -- Display name
    rarity = "common"|"rare"|"epic"|"legendary",
    class = "dps"|"support"|"tank",
    baseStats = {                -- Level 1 stats
        attack = number,
        health = number,
        defence = number
    },
    slotNumber = number,         -- Ordering for deck→slot mapping
    description = string,        -- Flavor text
    passive = string?            -- Future passive ability placeholder
}
```

**Available Cards (8 total):**
- **Common**: `dps_001` (slot 10), `support_001` (slot 20)
- **Rare**: `tank_001` (slot 30), `dps_002` (slot 40), `support_002` (slot 50)
- **Epic**: `dps_003` (slot 60), `tank_002` (slot 70)
- **Legendary**: `dps_004` (slot 80)

### CardLevels

**Progression System:**
- **Level Range**: 1-10 (MAX_LEVEL)
- **Cost Model**: `requiredCount` cards + `softAmount` currency per level
- **Growth System**: Per-card growth tables with base stats + level-specific deltas

### CardStats

**Computation:**
```lua
-- Get stats for a card at specific level
local stats = CardStats.ComputeStats(cardId, level)
-- Returns: { atk, hp, defence } with per-card growth applied

-- Compute power rating
local power = CardStats.ComputePower(stats)
-- Returns: weighted combination of stats for deck power calculation
```

**Growth System**: Each card has `base` stats and per-level `growth` deltas (levels 2-10). Designers can edit growth values in `CardCatalog` entries.

### DeckValidator

**Rules:**
- **Size**: Exactly 6 cards (no more, no less)
- **Uniqueness**: All card IDs must be unique (no duplicates)
- **Ownership**: No collection count validation (v2 rule)

**Slot Mapping:**
```lua
-- Cards are assigned to slots 1-6 by ascending slotNumber
deck = {"dps_001", "support_001", "tank_001"}  -- slotNumbers: 10, 20, 30
-- Maps to: slot 1 = dps_001, slot 2 = support_001, slot 3 = tank_001
```

### Board Layout

**3×2 Grid Visualization:**
```
Row 1: [5] [3] [1]    -- Slots 5, 3, 1 (left to right)
Row 2: [6] [4] [2]    -- Slots 6, 4, 2 (left to right)
```

**Canonical Helpers:**
- `BoardLayout.gridForDeck(deckIds)` → `{{slot=1, row=1, col=3}, ...}`
- `BoardLayout.oppositeSlot(slot)` → same slot (identity for now)
- `BoardLayout.isValidSlot(slot)` → `1 <= slot <= 6`

### CombatEngine

**Turn System:**
- **Order**: Fixed sequence 1→2→3→4→5→6 (slot-based)
- **Actions**: Each unit attacks once per turn in order

**Targeting Rules:**
1. **Primary**: Target unit in same slot index
2. **Fallback**: If same slot dead, target nearest living unit
3. **Tiebreaker**: If multiple equidistant, choose lower slot number

**Combat Mechanics:**
- **Armor Pool**: Defence acts as a depleting armor pool; residual damage reduces HP
- **Damage Flow**: Defence depletes first, then HP takes remaining damage
- **No Soak**: Defence does not reduce incoming damage by percentage
- **Round Cap**: Maximum 50 rounds to prevent infinite battles
- **Draw Rules**: Survivor count determines winner
- **Deterministic**: Seeded RNG ensures reproducible combat outcomes

## Level-Up System

### Card Progression
- **Level Range**: 1-10 (MAX_LEVEL = 10)
- **Cost Model**: `requiredCount` cards + `softAmount` currency per level
- **Growth System**: Per-card growth tables with base stats + level-specific deltas (levels 2-10)
- **Atomic Operations**: Level-up mutations use `UpdateAsync` for atomic resource deduction and level increment
- **Squad Power**: Automatically recomputed when upgraded card is in active deck

### Server Implementation
- **Endpoint**: `RequestLevelUpCard` RemoteEvent with rate limiting (1s cooldown, 10/minute)
- **Validation**: Card ownership, level limits, resource availability
- **Error Codes**: `CARD_NOT_OWNED`, `LEVEL_MAXED`, `INSUFFICIENT_COPIES`, `INSUFFICIENT_SOFT`
- **Persistence**: Atomic `UpdateAsync` operations prevent race conditions

### Client Integration
- **NetworkClient**: `requestLevelUpCard(cardId)` method with mock parity
- **ClientState**: `isLeveling` flag for UI loading states
- **Selectors**: `selectCanLevelUp()`, `selectUpgradeableCards()` for UI logic
- **CardVM**: Upgradeability fields (`canLevelUp`, `requiredCount`, `softAmount`, `shortfallCount`, `shortfallSoft`)
- **DevPanel**: "Level Up First Upgradeable" button for testing

### Testing
- **LevelUpDevHarness**: Server-side validation with comprehensive error case coverage
- **VMHarness**: Console commands (`LevelUpFirstUpgradeable()`, `LevelUp(cardId)`, `PrintUpgradeableCards()`)
- **Mock System**: Full validation and error code parity with real server

## Collection Surface

### Unified Collection System
- **Catalog Integration**: Shows all cards in catalog with ownership overlay
- **Ownership Data**: `owned` flag with level/count/stats for owned cards, placeholder data for unowned
- **Safe Handling**: CardVM handles unowned cards gracefully without crashes
- **DevPanel Integration**: "Print Collection Summary" button for diagnostic information

### Collection Features
- **Sorting Options**: By name, rarity, level, power, slotNumber
- **Filtering**: Owned only, rarity/class filters, search terms
- **Grouping**: By rarity or class for organized display
- **Statistics**: Coverage percentage, rarity breakdown, top power cards

### UI Integration
- **Selectors**: `selectUnifiedCollection()` with filtering and sorting options
- **ViewModels**: `CardVM.buildFromUnifiedCollection()` for UI-ready data structures
- **Styling**: Different visual treatment for owned vs unowned cards
- **Cross-Reference**: See [Collection View section](docs/ui_integration.md#collection-view) for detailed implementation

## Packs & Lootboxes

### Shop Hard-Currency Packs

**Pack Catalog (Complete Implementation):**
| Pack | Hard Amount | Bonus Hard | Total Credit | Price (Robux) | Dev Product ID |
| ---: | ----------: | ---------: | -----------: | ------------: | -------------: |
|    S |         100 |          0 |          100 |            40 |    3400863964 |
|    M |         330 |          0 |          330 |           100 |    3400864205 |
|    L |         840 |          0 |          840 |           200 |    3400864901 |
|   XL |        1950 |          0 |         1950 |           400 |    3400865038 |
|  XXL |        4900 |          0 |         4900 |           800 |    3400865167 |
| XXXL |       12000 |          0 |        12000 |          1500 |    3400865325 |

**Note:** The `additionalHard` field allows UI to display bonus amounts (currently 0 for all packs). Server credits `hardAmount + additionalHard` to player.

**API:**
```lua
local pack = ShopPacksCatalog.GetPack("M")  -- Returns {id="M", hardAmount=330, additionalHard=0, robuxPrice=100, devProductId=3400864205}
local allPacks = ShopPacksCatalog.AllPacks()  -- Returns sorted array
local availablePacks = ShopPacksCatalog.GetAvailablePacks()  -- Only packs with devProductId
local bestValue = ShopPacksCatalog.GetBestValuePack()  -- Highest hard/Robux ratio
local hasLiveIds = ShopPacksCatalog.hasLiveProductIds()  -- Check if any packs have real IDs
```

**Purchase Flow:**
- **Client**: `NetworkClient.requestStartPackPurchase(packId)` → Server validates → Client prompts `MarketplaceService:PromptProductPurchase`
- **Server**: `MarketplaceService.ProcessReceipt` → Atomic currency credit → `ProfileUpdated` with hard currency
- **Idempotency**: Receipt ledger prevents double-crediting same `PurchaseId`

### Lootboxes

**Rarities & Durations:**
- **Uncommon**: 7 minutes, Store: 7 hard, Instant: 4 base
- **Rare**: 30 minutes, Store: 22 hard, Instant: 11 base  
- **Epic**: 120 minutes, Store: 55 hard, Instant: 27 base
- **Legendary**: 240 minutes, Store: 100 hard, Instant: 50 base

**Note:** Lootbox rarities are uncommon, rare, epic, legendary (no "common" rarity exists).

**Hard Currency Purchase:**
- **Client**: `NetworkClient.requestBuyLootbox(rarity)` → Server validates and deducts hard currency
- **Server**: Atomic `UpdateAsync` for currency deduction + lootbox addition
- **Overflow Handling**: Automatic `pendingLootbox` creation when slots are full
- **ProfileUpdated**: Returns updated currencies, lootboxes, and pending state

**Capacity & States:**
- **Slots**: Up to 4 lootboxes per profile
- **States**: `Idle` → `Unlocking` → `Ready` → `Consumed`
- **Constraint**: At most 1 box in `Unlocking` state
- **Instant Open**: Pro-rata cost = `ceil(baseCost * (remaining / total))`

**Overflow Decision Flow:**
When capacity is full and a new box is awarded:
1. **New box** → `pendingLootbox` (staged as Idle)
2. **Player decision** (no UI yet):
   - **Discard**: Drop the pending box
   - **Replace**: Replace any slot with pending box (warning: replacing Unlocking box loses progress)

**Deterministic Rewards:**
- **Seed-based**: Each box stores a `seed` for consistent reward generation
- **Character Rewards**: Exactly 1 character card per box with rarity distribution
- **Currency Rewards**: Soft currency + optional hard currency (Epic/Legendary only)

**Reward Tables:**
- **Uncommon**: 80-120 soft, 0 hard, 80% Uncommon/15% Rare/4% Epic/1% Legendary
- **Rare**: 140-200 soft, 0 hard, 85% Rare/12% Epic/3% Legendary  
- **Epic**: 220-320 soft, 9% chance +1-29 hard (random), 90% Epic/10% Legendary
- **Legendary**: 350-450 soft, 12% chance +1-77 hard (random), 100% Legendary

**Server API (Atomic Operations):**
```lua
-- Add box (handles overflow automatically)
local result = LootboxService.TryAddBox(userId, rarity, source?)

-- Overflow resolution
LootboxService.ResolvePendingDiscard(userId)
LootboxService.ResolvePendingReplace(userId, slotIndex)

-- Unlock flow
LootboxService.StartUnlock(userId, slotIndex, serverNow)
LootboxService.CompleteUnlock(userId, slotIndex, serverNow)

-- Instant open
LootboxService.OpenNow(userId, slotIndex, serverNow)
```

### Complete Implementation

**Server Services:**
- **LootboxService**: Complete domain logic with atomic operations (`TryAddBox`, `ResolvePendingDiscard/Replace`, `StartUnlock`, `CompleteUnlock`, `OpenNow`)
- **Atomic Persistence**: All operations use `UpdateAsync` for consistency
- **Overflow Handling**: Automatic pending lootbox management with player decision flow
- **Reward System**: Deterministic seed-based rewards with character cards + currencies

**Client Integration:**
- **NetworkClient**: All 7 lootbox endpoints with mock parity
- **ClientState**: Lootbox state management with `serverNow` time sync
- **LootboxesVM**: UI-ready view model with slot data, timers, and capabilities
- **DevPanel**: Complete testing interface for all lootbox operations

**Networking Surface:**

**RemoteEvents (Client → Server):**
- **`RequestLootState`** `{}` → **`ProfileUpdated`** with `lootboxes` + `pendingLootbox`
- **`RequestAddBox`** `{rarity, source?}` → **`ProfileUpdated`** (handles overflow automatically)
- **`RequestResolvePendingDiscard`** `{}` → **`ProfileUpdated`** (clears pending)
- **`RequestResolvePendingReplace`** `{slotIndex}` → **`ProfileUpdated`** (replaces slot)
- **`RequestStartUnlock`** `{slotIndex}` → **`ProfileUpdated`** (starts timer)
- **`RequestOpenNow`** `{slotIndex}` → **`ProfileUpdated`** (instant open with cost)
- **`RequestCompleteUnlock`** `{slotIndex}` → **`ProfileUpdated`** (complete timer)

**ProfileUpdated Payload (Server → Client):**
```lua
{
  serverNow: number,            -- Always included for timers
  lootboxes = {                 -- Packed array 1..N (no holes)
    { id, rarity, state, startedAt?, unlocksAt?, seed?, source? },
    -- ...
  },
  pendingLootbox = { id, rarity, seed, source? } | nil,
  currencies = { soft, hard },  -- When changed
  collectionSummary = {         -- When rewards granted
    { cardId, count, level }
  },
  shopPacks = {                 -- When RequestGetShopPacks
    { id, hardAmount, additionalHard, robuxPrice, hasDevProductId }
  }?,
  error = { code, message? } | nil
}
```

**Array Compaction:** After `CompleteUnlock` or `OpenNow`, slots are removed and array is packed (no `Consumed` state kept).

**Testing:**
- **LootboxDevHarness**: 9 test suites covering capacity, overflow, unlock mechanics, reward validation, shop packs
- **ShopDevHarness**: 6 test suites covering pack validation, lootbox purchases, ProcessReceipt idempotency, error codes
- **DevPanel**: Complete UI testing for all operations including shop purchases
- **Mock System**: Full validation and error code parity with real server

## Shop Integration

### Developer Product Packs

**Pack Purchase Flow:**
```
Client → RequestStartPackPurchase → Server validates pack → 
Client prompts MarketplaceService → ProcessReceipt → 
ProfileUpdated with hard currency credit
```

**Pack Configuration:**
- **Placeholder Setup**: All packs have `devProductId` set with real ProductIds
- **Production Setup**: ProductIds are already configured in `ShopPacksCatalog.lua`
- **Availability Check**: `ShopPacksCatalog.HasDevProductId(packId)` returns `true` for configured packs

**Server Implementation:**
- **ShopService**: Handles `MarketplaceService.ProcessReceipt` integration
- **Idempotency**: Receipt ledger prevents double-crediting same `PurchaseId`
- **Atomic Operations**: `UpdateAsync` ensures currency credit consistency
- **Error Handling**: `NotProcessedYet` for unknown products, `PurchaseGranted` for successful processing

### Lootbox Purchase System

**Hard Currency Costs:**
- **Uncommon**: 7 hard currency
- **Rare**: 22 hard currency  
- **Epic**: 55 hard currency
- **Legendary**: 100 hard currency

**Purchase Flow:**
- **Validation**: Rarity check, profile loaded, sufficient hard currency
- **Capacity Handling**: Automatic overflow to `pendingLootbox` if slots full
- **Atomic Operations**: Hard currency deduction + lootbox addition in single `UpdateAsync`
- **ProfileUpdated**: Returns updated currencies, lootboxes, and pending state

### Client Integration

**NetworkClient Methods:**
- **`requestGetShopPacks()`**: Retrieve available packs with `hasDevProductId` flags
- **`requestStartPackPurchase(packId)`**: Validate pack and return `devProductId` for MarketplaceService
- **`requestBuyLootbox(rarity)`**: Purchase lootbox with hard currency

**Mock System:**
- **Pack Purchases**: Immediate hard currency credit (simulates ProcessReceipt)
- **Lootbox Purchases**: Full server logic simulation including overflow handling
- **Error Simulation**: All shop error codes with realistic validation

**ShopHandler Integration:**
- **Button Binding**: Automatic detection of pack/lootbox buttons via naming convention
- **Loading States**: Button disable during processing with visual feedback
- **Error Display**: `ErrorMap` integration for user-friendly error messages
- **Defensive Design**: Graceful handling of missing UI elements

### Error Codes

| Code | Meaning | User Message |
|------|---------|--------------|
| `PACK_NOT_AVAILABLE` | Pack has no devProductId or unknown packId | "This pack is not available for purchase" |
| `INSUFFICIENT_HARD` | Not enough hard currency for lootbox | "You don't have enough hard currency for this purchase" |
| `LOOTBOX_CAPACITY_FULL` | Direct buy when overflow and no pending resolution | "Your lootbox slots are full. Please resolve pending lootboxes first" |

### Development Setup

**Where to Set devProductId:**
```lua
-- In src/shared/Modules/Shop/ShopPacksCatalog.lua
["M"] = {
    id = "M", 
    hardAmount = 330,
    robuxPrice = 100,
    devProductId = 3400864205 -- Real ProductId from Roblox Creator Dashboard
}
```

**Testing with DevPanel:**
- **Mock Mode**: "Shop: Buy Pack [S/M/L] (Mock)" buttons for instant testing
- **Live Mode**: "Shop: Fetch Packs" to see availability, "Shop: Buy Lootbox [Rarity]" for hard currency purchases
- **Status Display**: Shows current hard/soft currency and lootbox slot count



## Networking Surface

### RemoteEvents

**Profile Management:**
- **`RequestProfile`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestSetDeck`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestLevelUpCard`** (C→S) → **`ProfileUpdated`** (S→C)

**Match System:**
- **`RequestStartMatch`** (C→S) → **Response on same event** (S→C)

**Lootbox System:**
- **`RequestLootState`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestAddBox`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestResolvePendingDiscard`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestResolvePendingReplace`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestStartUnlock`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestOpenNow`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestCompleteUnlock`** (C→S) → **`ProfileUpdated`** (S→C)

**Shop System:**
- **`RequestGetShopPacks`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestStartPackPurchase`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestBuyLootbox`** (C→S) → **`ProfileUpdated`** (S→C)

**Legacy System:**
- **`OpenLootbox`** (C→S) → **`ProfileUpdated`** (S→C) - Deprecated, use RequestOpenNow

### Payload Schemas

**ProfileUpdated Payload:**
```lua
{
    deck = {string, string, string, string, string, string}?,
    collectionSummary = {
        {cardId = string, count = number, level = number},
        -- ... more cards
    }?,
    loginInfo = {
        lastLoginAt = number,
        loginStreak = number
    }?,
    squadPower = number?,
    lootboxes = {LootboxEntry}?,
    updatedAt = number?,
    serverNow = number,           -- Server timestamp for time sync
    error = {code = string, message = string}?  -- Only on errors
}
```

**Match Response Payload:**
```lua
{
    ok = boolean,
    matchId = string?,
    seed = number|string?,
    result = {
        winner = "A"|"B",
        rounds = number,
        survivorsA = number,
        survivorsB = number,
        totalActions = number,
        totalDamage = number,
        totalKOs = number,
        totalDefenceReduced = number
    }?,
    log = {BattleLogEntry}?,
    serverNow = number,           -- Server timestamp for time sync
    error = {code = string, message = string}?  -- Only on errors
}
```

### Concurrency Guards
- **Per-Player State**: `isInMatch` flag prevents overlapping matches
- **Studio Testing**: Extended busy window (0.75s) for deterministic testing

### Error Codes

| Code | Meaning |
|------|---------|
| `INVALID_REQUEST` | Malformed request payload |
| `DECK_UPDATE_FAILED` | Deck validation failed |
| `PROFILE_LOAD_FAILED` | Profile data corruption |
| `NO_DECK` | Player has no active deck |
| `INVALID_DECK` | Deck violates rules (duplicates, wrong size) |
| `BUSY` | Player already in match |
| `CARD_NOT_OWNED` | Card not found in collection |
| `LEVEL_MAXED` | Card already at maximum level |
| `INSUFFICIENT_COPIES` | Not enough card copies for level-up |
| `INSUFFICIENT_SOFT` | Not enough soft currency for level-up |
| `BOX_CAPACITY_FULL_PENDING` | Lootbox capacity full, pending lootbox exists |
| `BOX_DECISION_REQUIRED` | Must choose discard or replace for pending lootbox |
| `BOX_ALREADY_UNLOCKING` | Another lootbox is already unlocking |
| `BOX_BAD_STATE` | Invalid operation for current lootbox state |
| `BOX_TIME_NOT_REACHED` | Lootbox timer hasn't finished yet |
| `INSUFFICIENT_HARD` | Not enough hard currency for instant open |
| `PACK_NOT_AVAILABLE` | Pack has no devProductId or unknown packId |
| `LOOTBOX_CAPACITY_FULL` | Direct buy when overflow and no pending resolution |
| `INTERNAL` | Server-side error |

## Client Integration Layer

**Reference**: See [docs/ui_integration.md](docs/ui_integration.md) for complete UI integration guide including combat mechanics and defence semantics.

**Core Components:**
- **NetworkClient**: Unified interface for mock/real server communication with all 16 endpoints
- **ClientState**: Centralized state store with subscription system (`isLeveling`, `lastError`, `serverNow`)
- **Selectors**: Pure functions for data extraction and transformation (upgradeability computation, lootbox timers)
- **ViewModels**: UI-ready data structures (CardVM, DeckVM, ProfileVM, LootboxesVM)

**Key Features:**
- **Time Sync**: `serverNow` for accurate timers and lootbox countdowns
- **Grid Layout**: `BoardLayout.gridForDeck()` for 3×2 board rendering
- **Assets**: Centralized manifest and resolver for consistent UI styling
- **Configuration**: Feature flags for development vs production
- **Level-Up Flow**: Complete UI integration guide in [Level-Up Flow section](docs/ui_integration.md#level-up-flow)
- **Shop Integration**: Complete UI integration guide in [Shop UI section](docs/ui_integration.md#shop-ui)
- **Lootbox Management**: Complete UI integration guide in [Lootboxes UI section](docs/ui_integration.md#lootboxes-ui)
- **Collection Surface**: Complete UI integration guide in [Collection View section](docs/ui_integration.md#collection-view)

**Quickstart Example:**
```lua
local ClientState = require(script.Parent.Parent.State.ClientState)
local ProfileVM = require(game:GetService("ReplicatedStorage").Modules.ViewModels.ProfileVM)

-- Subscribe to state changes
ClientState.subscribe(function(state)
    if state.profile then
        -- Build UI-ready data
        local vm = ProfileVM.build(state.profile)
        
        -- Render deck grid
        for _, slot in ipairs(vm.deckVM.slots) do
            print(string.format("Slot %d: %s (Level %d, Power %d)", 
                slot.slot, slot.card.id, slot.card.level, slot.card.power))
        end
        
        -- Show squad power
        print("Squad Power:", vm.squadPower)
    end
end)
```

**Development Tools:**
- **Config Flags**: `USE_MOCKS`, `SHOW_DEV_PANEL`, `DEBUG_LOGS`, `AUTO_REQUEST_PROFILE`
- **Mock System**: Offline development with realistic data and validation
- **Dev Panel**: Runtime testing UI with mock toggle and sample actions

## Logging & Debugging

### Structured Logging System

**Logger Module** (`src/shared/Modules/Logger.lua`):
- **Debug Flag**: Controlled by `Logger.EnableDebug()` / `Logger.DisableDebug()`
- **Structured Logs**: Single-line, consistent format for key events
- **Shop Events**: `SHOP_PURCHASE user=<uid> pack=<id> hardBefore=<n> add=<base+bonus> hardAfter=<n>`
- **Lootbox Events**: `LOOT_ADD`, `LOOT_START`, `LOOT_OPEN_NOW`, `LOOT_COMPLETE`, `LOOT_PENDING_*`
- **Loot State**: `LOOT_STATE user=<uid> slots=<n> unlocking=<slot|none> remain=<sec|0> pending=<bool>`

**DevPanel Integration:**
- **Loot State Summary**: "Loot: State Summary" button shows detailed lootbox status
- **Debug Toggle**: Enable/disable structured logging for development
- **Event Tracking**: Monitor shop purchases and lootbox operations in real-time

**Log Format Examples:**
```
SHOP_PURCHASE user=12345 pack=M hardBefore=1000 add=330 hardAfter=1330
LOOT_ADD user=12345 rarity=epic overflow=false slots=3
LOOT_START user=12345 slot=1 rarity=epic start=1640995200 unlocksAt=1640996400 remain=1200
LOOT_OPEN_NOW user=12345 slot=1 cost=27 remainBefore=600 rewards=soft=250,hard=15,cards=1xdps_003
LOOT_COMPLETE user=12345 slot=1 rewards=soft=250,hard=15,cards=1xdps_003
LOOT_STATE user=12345 slots=4 unlocking=1 remain=600 pending=false
```

## Testing & Dev Harnesses

### Self-Checks

**Run in Studio Console:**
```lua
local Utilities = require(game:GetService("ReplicatedStorage").Modules.Utilities)
Utilities.SelfCheck.RunAllTests()
```

**Validates**: Card catalog consistency, deck validation rules, combat mechanics, time utilities

**Armor Pool Tests**: Comprehensive combat validation including full absorb (damage ≤ defence), partial absorb (damage > defence), exact match scenarios, overkill cases, edge conditions (0/1 damage), and combat invariants (dead units cannot act, survivors have HP > 0)

### Dev Harnesses

**CombatEngineDevHarness** (`src/server/Services/CombatEngineDevHarness.server.lua`):
- **Purpose**: Test combat determinism and targeting rules
- **Run**: Automatically on server start
- **Tests**: Turn order, targeting fallbacks, damage calculations, seeded RNG

**MatchServiceDevHarness** (`src/server/Services/MatchServiceDevHarness.server.lua`):
- **Purpose**: Test match execution and rate limiting
- **Run**: Automatically on server start  
- **Tests**: Concurrency guards, rate limiting, invalid request handling

**PersistenceDevHarness** (`src/server/Persistence/DevHarness.server.lua`):
- **Purpose**: Test profile persistence and migration
- **Run**: Automatically on server start
- **Tests**: Profile creation, v1→v2 migration, deck updates, autosave

**PlayerDataServiceDevHarness** (`src/server/Services/PlayerDataServiceDevHarness.server.lua`):
- **Purpose**: Test player data operations and login streak logic
- **Run**: Automatically on server start
- **Tests**: Card granting, login streak bumps, profile validation

**LevelUpDevHarness** (`src/server/Services/LevelUpDevHarness.server.lua`):
- **Purpose**: Test card level-up functionality and validation
- **Run**: Automatically on server start
- **Tests**: Happy path level-up, validation errors, rate limiting, squad power recomputation

**LootboxDevHarness** (`src/server/Services/LootboxDevHarness.server.lua`):
- **Purpose**: Test complete lootbox system functionality and overflow handling
- **Run**: Automatically on server start
- **Tests**: 9 test suites covering capacity/pending flow, overflow resolution (discard/replace), unlock mechanics, reward validation, shop packs, instant open, timer completion

**ShopDevHarness** (`src/server/Services/ShopDevHarness.server.lua`):
- **Purpose**: Test shop system functionality including Developer Product processing and lootbox purchases
- **Run**: Automatically on server start
- **Tests**: 6 test suites covering pack validation, lootbox purchases, ProcessReceipt idempotency, shop packs retrieval, pack availability, error codes

### Client-Side Testing

**NetworkTest** (`src/client/NetworkTest.client.lua`):
- **Purpose**: Test client-server communication
- **Run**: `NetworkTest.RunAllTests()` in Studio console
- **Tests**: Profile requests, deck updates, match requests, error handling

**VMHarness** (`src/client/Dev/VMHarness.client.lua`):
- **Purpose**: Test ViewModels and client state
- **Run**: Automatically on client start
- **Tests**: ProfileVM building, deck rendering, squad power calculation
- **Level-Up Commands**: `VMHarness.LevelUpFirstUpgradeable()`, `VMHarness.LevelUp(cardId)`, `VMHarness.PrintUpgradeableCards()`

**DevPanel** (`src/client/Dev/DevPanel.client.lua`):
- **Purpose**: Runtime testing UI
- **Enable**: `Config.SHOW_DEV_PANEL = true`
- **Features**: Profile refresh, sample deck, PvE match, level-up testing, collection summary, complete lootbox operations (refresh, add, start unlock, complete, open now, resolve pending), shop operations (fetch packs, buy lootboxes, mock pack purchases), mock toggle

### Coverage Status

**✅ Covered:**
- Core game mechanics (combat, deck validation, persistence)
- Network layer (rate limiting, concurrency, error handling)
- Client integration (state management, ViewModels, mocks)
- Profile system (creation, migration, validation)
- Card level-up system (server endpoints, client integration, testing)
- Complete lootbox system (server services, client integration, overflow handling)
- Collection surface (unified catalog+ownership, selectors, ViewModels)
- Shop integration (Developer Product packs, lootbox purchases, ProcessReceipt integration)
- All 16 RemoteEvents with comprehensive rate limiting
- Atomic UpdateAsync operations for all mutations

**❌ Not Covered:**
- UI unit tests (no UI framework yet)
- Tutorial flow implementation
- PvP matchmaking system

## Build & Dev Environment

### Requirements

**Tools:**
- **Roblox Studio**: Latest version with Studio Access to API Services enabled
- **Rojo**: Project sync tool for development workflow
- **Cursor**: Recommended IDE with Rojo integration

**Studio Settings:**
- **API Services**: Enable "Studio Access to API Services" for DataStore testing
- **Run Mode**: Server + Client for full testing

### Development Workflow

**First Run:**
1. **Sync Project**: `rojo serve` in project directory
2. **Studio**: Open `test-build.rbxlx` and sync with Rojo
3. **Enable Dev Mode**: Set `Config.USE_MOCKS = true` and `Config.SHOW_DEV_PANEL = true`
4. **Test**: Run game, verify dev panel appears, test mock functionality
5. **Level-Up Testing**: Use "Level Up First Upgradeable" button in DevPanel for one-click testing

**Rojo Commands:**
```bash
rojo serve          # Start sync server
rojo build          # Build standalone .rbxlx
rojo upload         # Upload to Roblox (requires auth)
```

### Logging & Debugging

**Config Toggles:**
```lua
-- In src/client/Config.lua
Config.DEBUG_LOGS = true        -- Verbose client logging
Config.USE_MOCKS = true         -- Offline development (mock payloads match server shape including serverNow)
Config.SHOW_DEV_PANEL = true    -- Development UI
```

**Where to Look:**
- **Server Output**: Studio console for service logs and errors
- **Client Output**: Player console for client-side debugging
- **Dev Panel**: Runtime status and testing tools
- **Self-Checks**: Comprehensive validation on startup

## Performance & Security Notes

**DataStore Considerations:**
- **Budget Awareness**: Exponential backoff on failures, no overlapping writes per player
- **Autosave Strategy**: Save on changes, `BindToClose` safety, retry logic
- **Migration Safety**: v1→v2 migration is idempotent and safe to run multiple times

**Security Principles:**
- **Server Authority**: All game state changes validated server-side
- **Client Validation**: Client-side validation for UX, server re-validates everything
- **Rate Limiting**: Per-player, per-endpoint limits prevent abuse
- **Input Sanitization**: All client inputs validated before processing

**Performance Choices:**
- **Compact Payloads**: Battle logs use minimal data structures
- **Efficient Targeting**: Same-index priority reduces computation
- **Fixed Turn Order**: Eliminates need for complex turn calculation
- **Integer Math**: Combat calculations use integer arithmetic for consistency

## What Changed in This Release

### Lootbox State Casing Standardization
- **State strings now use TitleCase**: `"Idle"`, `"Unlocking"`, `"Ready"`, `"Consumed"` (was lowercase)
- **Consistent across entire pipeline**: Server, client, UI, and documentation all use same casing
- **Client detection fixed**: `box.state == "Idle"` now works correctly for finding available slots
- **Breaking change**: Update any client code that checks `box.state == "idle"` to use `"Idle"`

### Lootbox Flow Standardization
- **Overflow error standardized**: 5th box overflow now consistently returns `BOX_DECISION_REQUIRED` and sets `pendingLootbox`
- **OpenNow preconditions enforced**: Only works on `"Unlocking"` state, returns `BOX_NOT_UNLOCKING` for others
- **Single unlock rule**: Only one lootbox can be unlocking at a time, returns `BOX_ALREADY_UNLOCKING` for violations
- **Enhanced error codes**: Added `INVALID_SLOT`, `INVALID_STATE` for better error handling
- **Structured logging**: All lootbox operations now include clear operation context and state transitions
- **Error-only payloads**: Handlers send error-only payloads on failure (no `lootboxes` slice), full slices on success
- **Dev-only reset**: Added `RequestClearLoot` endpoint for deterministic Studio testing

**Combat Defence Update:**
- ✅ **Armor Pool Model**: Defence now acts as depleting armor pool instead of 50% soak
- ✅ **Simplified Mechanics**: Damage depletes defence first, residual reduces HP
- ✅ **Comprehensive Testing**: 10 new self-check cases covering all armor scenarios
- ✅ **Documentation**: Updated README combat mechanics and glossary sections

**Level-Up System:**
- ✅ **Server Implementation**: `RequestLevelUpCard` RemoteEvent with atomic persistence and squad power recomputation
- ✅ **Client Integration**: `NetworkClient.requestLevelUpCard()`, `ClientState.isLeveling`, upgradeability selectors
- ✅ **ViewModels**: CardVM with level-up fields (`canLevelUp`, `requiredCount`, `softAmount`, `shortfallCount`, `shortfallSoft`)
- ✅ **Mock Parity**: MockNetwork mirrors server validation, error codes, and payload structure
- ✅ **Dev Tools**: DevPanel "Level Up First Upgradeable" button, VMHarness console commands
- ✅ **Documentation**: Complete Level-Up Flow section in [docs/ui_integration.md](docs/ui_integration.md)
- ✅ **Testing**: LevelUpDevHarness server-side validation, comprehensive error case coverage

**Collection Surface:**
- ✅ **Unified Catalog**: Shows all cards in catalog with ownership overlay
- ✅ **Safe Handling**: CardVM handles unowned cards gracefully without crashes
- ✅ **DevPanel Integration**: "Print Collection Summary" button for diagnostic information
- ✅ **Selectors**: `selectUnifiedCollection()` with filtering and sorting options
- ✅ **ViewModels**: `CardVM.buildFromUnifiedCollection()` for UI-ready data structures
- ✅ **Documentation**: Complete Collection View section in [docs/ui_integration.md](docs/ui_integration.md)

**Complete Lootbox System:**
- ✅ **Server Services**: LootboxService with atomic operations (`TryAddBox`, `ResolvePendingDiscard/Replace`, `StartUnlock`, `CompleteUnlock`, `OpenNow`)
- ✅ **Atomic Persistence**: All operations use `UpdateAsync` for consistency
- ✅ **Overflow Handling**: Automatic pending lootbox management with player decision flow
- ✅ **Reward System**: Deterministic seed-based rewards with character cards + currencies
- ✅ **Client Integration**: NetworkClient with all 7 endpoints, ClientState management, LootboxesVM
- ✅ **DevPanel Integration**: Complete testing interface for all lootbox operations
- ✅ **Testing**: LootboxDevHarness with 9 test suites covering all scenarios
- ✅ **Documentation**: Complete Lootboxes UI section in [docs/ui_integration.md](docs/ui_integration.md)

**Shop Integration:**
- ✅ **Developer Product Packs**: Complete integration with `MarketplaceService.ProcessReceipt`
- ✅ **Pack Configuration**: Real `devProductId` values configured for all 6 packs (S-XXXL)
- ✅ **Idempotency**: Receipt ledger prevents double-crediting same purchases
- ✅ **Lootbox Purchases**: Hard currency purchases with automatic overflow handling
- ✅ **Client Integration**: NetworkClient methods, MockNetwork simulation, ShopHandler button binding
- ✅ **DevPanel Integration**: Complete shop testing interface with mock/live mode support
- ✅ **Testing**: ShopDevHarness with 6 test suites covering all shop functionality
- ✅ **Error Handling**: Shop-specific error codes with user-friendly messages

**Networking Surface:**
- ✅ **16 Total Endpoints**: Complete coverage of all game systems
- ✅ **Rate Limiting**: Comprehensive rate limits for all endpoints
- ✅ **Error Codes**: Complete error code coverage for all operations
- ✅ **Payload Schemas**: Updated ProfileUpdated payload with all data slices and `serverNow`

**Profile System v2:**
- ✅ **Atomic Operations**: All mutations use `UpdateAsync` for consistency
- ✅ **Receipt Ledger**: Idempotent purchase processing with `PurchaseId` tracking
- ✅ **Array Compaction**: Lootbox arrays are packed after operations
- ✅ **Migration**: Safe v1→v2 migration with data preservation

## Roadmap

**Planned Features (Not Yet Implemented):**

- [ ] **Card Store**: Direct card purchases with hard currency
- [ ] **Tutorial Flow**: Step-by-step onboarding experience
- [ ] **PvP Matchmaking**: Player vs player battle system
- [ ] **Daily Rewards**: Login streak bonuses and daily quests
- [ ] **Achievement System**: Progress tracking and rewards
- [ ] **Social Features**: Friends, guilds, leaderboards

**Current Focus:**
- ✅ **Core Systems**: Profile, cards, combat, networking
- ✅ **Client Layer**: Integration tools and development environment
- ✅ **Level-Up System**: Complete server and client implementation
- ✅ **Lootbox System**: Complete server and client implementation
- ✅ **Collection Surface**: Unified catalog with ownership overlay
- ✅ **Shop Integration**: Developer Product packs and lootbox purchases
- 🔄 **UI Foundation**: Ready for UI engineer to build interfaces
- ⏳ **Game Features**: Store system, tutorial flow, PvP matchmaking

## Glossary

**Core Game Terms:**
- **Card**: Individual unit with stats, rarity, class, and slot number
- **Deck**: Collection of exactly 6 unique cards for battle
- **Slot Number**: Integer (10-80) determining deck→slot mapping order
- **Squad Power**: Computed metric representing deck strength
- **Armor Pool**: Defence acts as depleting armor pool; residual damage reduces HP (no soak)
- **Same-Index Targeting**: Combat targeting priority (same slot first)

**System Terms:**
- **Profile**: Complete player data including collection, deck, and progression
- **Collection**: Map of owned cards with count and level information
- **Lootbox States**: `idle` (unopened), `unlocking` (in progress), `ready` (can open)
- **Server Now**: Server timestamp included in network payloads for time sync
- **Rate Limiting**: Per-player, per-endpoint request frequency controls
- **Concurrency Guard**: Prevents overlapping operations (e.g., multiple matches)

**Development Terms:**
- **Mock System**: Offline development environment simulating server behavior
- **ViewModels**: UI-ready data structures built from raw profile data
- **Selectors**: Pure functions for extracting and transforming state data
- **Dev Harness**: Automated testing system for validating game mechanics

---

**For UI Engineers**: Start with [docs/ui_integration.md](docs/ui_integration.md) for detailed integration guides and examples.

**For Game Developers**: Focus on `src/shared/Modules/` for core game logic and `src/server/Services/` for server architecture.

**For New Team Members**: Run the self-checks first, then explore the dev harnesses to understand the system behavior.

---

## What Changed in This Release

**Card Level-Up System:**
- ✅ **Server Implementation**: `RequestLevelUpCard` RemoteEvent with atomic persistence and squad power recomputation
- ✅ **Client Integration**: `NetworkClient.requestLevelUpCard()`, `ClientState.isLeveling`, upgradeability selectors
- ✅ **ViewModels**: CardVM with level-up fields (`canLevelUp`, `requiredCount`, `softAmount`, `shortfallCount`, `shortfallSoft`)
- ✅ **Mock Parity**: MockNetwork mirrors server validation, error codes, and payload structure
- ✅ **Dev Tools**: DevPanel "Level Up First Upgradeable" button, VMHarness console commands
- ✅ **Documentation**: Complete Level-Up Flow section in [docs/ui_integration.md](docs/ui_integration.md)
- ✅ **Testing**: LevelUpDevHarness server-side validation, comprehensive error case coverage

**Combat Defence Update:**
- ✅ **Armor Pool Model**: Defence now acts as depleting armor pool instead of 50% soak
- ✅ **Simplified Mechanics**: Damage depletes defence first, residual reduces HP
- ✅ **Comprehensive Testing**: 10 new self-check cases covering all armor scenarios
- ✅ **Documentation**: Updated README combat mechanics and glossary sections

**Shop & Lootbox System:**
- ✅ **Shop Packs**: Hard currency packs (S-XXXL) with Robux pricing (domain-only)
- ✅ **Lootbox System**: 4-slot capacity, deterministic rewards, overflow decision flow
- ✅ **Atomic Operations**: Server-side helpers for add/start/complete/open with validation
- ✅ **Comprehensive Testing**: LootboxDevHarness with 9 test suites covering all scenarios
- ✅ **Documentation**: Complete Packs & Lootboxes section with API examples

**Lootbox Naming Cleanup:**
- ✅ **Rarity Standardization**: Replaced all "common" lootbox references with "uncommon"
- ✅ **Profile Migration**: Automatic v1→v2 migration for old profiles with "common" lootboxes
- ✅ **Self-Check Test**: Added migration validation test in SelfCheck module
- ✅ **Documentation**: Updated all references to reflect uncommon/rare/epic/legendary only

**Shop Pack Enhancements:**
- ✅ **AdditionalHard Field**: Added `additionalHard` field to pack entries for UI bonus display
- ✅ **Server Crediting**: Pack purchases now credit `hardAmount + additionalHard` to player
- ✅ **Network Updates**: `RequestGetShopPacks` includes `additionalHard` in payload
- ✅ **Mock Parity**: MockNetwork updated to include `additionalHard` and credit base+bonus
- ✅ **Documentation**: Updated README with new pack table format and API examples

**Lootbox Hard-Currency Drops:**
- ✅ **Epic Lootboxes**: 9% chance for 1-29 hard currency (random range)
- ✅ **Legendary Lootboxes**: 12% chance for 1-77 hard currency (random range)
- ✅ **Deterministic RNG**: Uses SeededRNG for consistent results across sessions
- ✅ **Self-Check Tests**: Added comprehensive range validation tests
- ✅ **Documentation**: Updated reward tables with new chance/range mechanics

**Structured Logging System:**
- ✅ **Logger Module**: New centralized logging with debug flag control
- ✅ **Structured Events**: Single-line logs for shop purchases and lootbox operations
- ✅ **DevPanel Integration**: "Loot: State Summary" button for detailed lootbox status
- ✅ **Noise Reduction**: Cleaned up verbose prints across Shop/Lootbox/Network services
- ✅ **Event Tracking**: Real-time monitoring of key game events during development

---
---
---

# Спецификация проекта (Russian language version)

Ниже — сводный документ по текущей кодовой базе: архитектура, данные, модули, сети, клиентская интеграция, тесты и «как запускать». Он склеивает то, что уже зафиксировано в README и UI-гайде, добавляет пояснения и устраняет мелкие разрывы между документами.

## 1) Цель и обзор

Игра — **детерминированный аниме card-battler** на сетке 3×2. Сервер — единственный источник правды: расчёт боя, валидации, персист. Клиент — рендер и ввод. Уже реализовано: профиль v2, каталог карт, уровни и статы, валидация дек, детерминированный бой, матч-сервис, минимальные RemoteEvents, клиентская интеграция (NetworkClient/ClientState/VM), моки, дев-панель.&#x20;

**Детерминизм:** фиксированный порядок ходов по слотам (1→6), таргетинг «тот же индекс → ближайшая живая цель (tie → меньший индекс)», armour pool в защиту (целочисленная арифметика). Во все серверные ответы добавлен `serverNow` для синхронизации таймеров. &#x20;

## 2) Структура репозитория (Rojo)

Ключевые узлы (по **default.project.json**):

* **ReplicatedStorage/Modules**: общие модули (Cards, Combat, RNG, Constants, Utilities, ViewModels, BoardLayout, Types, TimeUtils, ErrorMap, Assets).&#x20;
* **ServerScriptService/Services**: CombatEngine, MatchService, PlayerDataService + dev-harness’ы.&#x20;
* **ServerScriptService/Persistence**: DataStoreWrapper, ProfileSchema, ProfileManager, DevHarness.&#x20;
* **ServerScriptService/Network**: RemoteEvents.&#x20;
* **StarterPlayer/StarterPlayerScripts**: Controllers (NetworkClient), State (ClientState, selectors), Dev (VMHarness, DevPanel, MockNetwork, MockData), Config.&#x20;

## 3) Рантайм-архитектура и границы доверия

```
Client UI  ──(RemoteEvents)──► Server Services ──► Persistence (DataStore)
   ▲                    │
   └──────(ProfileUpdated / match response with serverNow)──────┘
```

* **Сервер-авторитет**: расчёты боя, прогресс, валидации, RNG — только на сервере. Клиент не оказывает влияния на результат.&#x20;
* **Синхронизация времени**: каждое серверное событие/ответ содержит `serverNow` → клиент строит таймеры без рассинхрона.&#x20;

## 4) Данные и персист

**Профиль v2** (ключевые поля):

* `playerId`, `createdAt`, `lastLoginAt`, `loginStreak`
* `collection`: `{ [cardId]: { count: number, level: number } }`
* `deck`: массив **ровно 6 уникальных** `cardId`
* `currencies`: как минимум `soft` (и др. при необходимости)
* `favoriteLastSeen`, `tutorialStep`, `squadPower`
* `lootboxes`: фиксированная ёмкость (до 4), структурная валидация, без бизнес-логики открытия на этом этапе
* Автосейв, `BindToClose`, ретраи на фейлах — уже настроено.&#x20;

**Миграция v1→v2**: прозрачная, идемпотентная; deck становится 6 уникальных карт; коллекция — map из `{count, level}`.&#x20;

## 5) Карты, уровни, деки, бой

* **CardCatalog**: `id`, `name`, `rarity`, `class`, `description`, `slotNumber`, базовые статы (`atk/hp/defence`). Слоты виз. раскладки: `5 3 1 / 6 4 2` (UI). Позиции и порядок ходов определяются **только** сервером по `slotNumber`.&#x20;
* **CardLevels**: ур. 1–10; для каждого уровня задаются `requiredCount`, `softAmount`.&#x20;
* **CardStats**: вычисляет эффективные статы карточки с учётом уровня; `power` = функция (`atk/hp/defence`), используется для `squadPower`.&#x20;
* **DeckValidator**: принимает **ровно 6 уникальных** id; маппинг к слотам (1..6) по возрастанию `slotNumber`; клиент может визуализировать сетку через BoardLayout. &#x20;
* **CombatEngine**: ходят слоты 1→6; таргет «тот же индекс», иначе ближайший живой (tie → меньший индекс); **armour pool** (defence depletes first, residual to HP); кап по раундам, ничьи — корректно обрабатываются.&#x20;

## 6) Сетевой слой (RemoteEvents)

**Существующие контракты:**

* `RequestProfile` (C→S) → **`ProfileUpdated`** (S→C)
* `RequestSetDeck` (C→S) → **`ProfileUpdated`** (S→C)
* `RequestStartMatch` (C→S) → **ответ на том же ивенте** (S→C)
  Пейлоады содержат `serverNow`.&#x20;

**`ProfileUpdated` (S→C):**

```lua
{
  deck = {string×6}, -- уникальные карты
  collectionSummary = { {cardId, count, level}, ... },
  loginInfo = { lastLoginAt, loginStreak },
  squadPower = number,
  lootboxes = { {id, rarity, state, acquiredAt, startedAt?, endsAt?}, ... },
  updatedAt = number,
  serverNow = number,
  error = { code, message }? -- при ошибке
}
```



**Match response** (успех/ошибка) — тоже с `serverNow`; лог боя — компактный.&#x20;

**Конкуренция:** флаг «занят» на игрока (например, при матчах) уже описан и реализован.&#x20;

**Коды ошибок** (канонический набор в документации): `INVALID_REQUEST`, `DECK_UPDATE_FAILED`, `PROFILE_LOAD_FAILED`, `NO_DECK`, `INVALID_DECK`, `BUSY`, `INTERNAL`, + клиентский ErrorMap покрывает и карточные/моковые варианты. &#x20;

## 7) Клиентская интеграция (слой для UI)

Опорный документ — **UI Integration Guide** (актуальная версия в `docs/ui_integration.md`). Там описаны:

* **NetworkClient** (ModuleScript в `StarterPlayerScripts/Controllers`): `requestProfile()`, `requestSetDeck(deckIds)`, `requestStartMatch(opts)`, подписки `onProfileUpdated/onceProfile`, дебаунс, нормализация ошибок, time-sync.&#x20;
* **ClientState** (`State/ClientState.lua`), **selectors.lua** (чистые селекторы), **ViewModels** (`ReplicatedStorage/Modules/ViewModels`: CardVM/DeckVM/ProfileVM) — возвращают структуры «готовые к рендеру». Примеры использования и сортировки коллекции — в гайде.&#x20;
* **BoardLayout**: `gridForDeck()` для сетки `5 3 1 / 6 4 2`; фиксированный `SLOT_ORDER() = {1..6}`.&#x20;
* **TimeUtils** и `serverNow` во всех пейлоадах — для таймеров лутбоксов.&#x20;

## 8) Ассеты, моки, дев-панель

* **Assets Manifest/Resolver**: централизованные ID картинок, рамок по редкости, иконок классов, цветов UI; безопасные фоллбеки.&#x20;
* **Config.lua**: `USE_MOCKS`, `SHOW_DEV_PANEL`, `DEBUG_LOGS`, `AUTO_REQUEST_PROFILE`.&#x20;
* **MockNetwork/MockData**: оффлайн-режим с совместимыми пейлоадами (включая `serverNow`), симуляцией задержек и ошибок. Переключение онлайн/оффлайн — из дев-панели.&#x20;
* **DevPanel**: панель с кнопками (Refresh Profile, Set Sample Deck, Start PvE, Toggle Mocks) + статус (serverNow, squadPower, Mock ON/OFF).&#x20;

## 9) Тесты и дев-харнессы

**SelfCheck** (shared) — быстрый интеграционный прогон: каталог карт, валидация деки, боёвка, утилиты времени.
Запуск:

```lua
local Utilities = require(game:GetService("ReplicatedStorage").Modules.Utilities)
Utilities.SelfCheck.RunAllTests()
```



**Server harnesses** (автозапускаемые): CombatEngineDevHarness, MatchServiceDevHarness, Persistence DevHarness, PlayerDataServiceDevHarness — проверяют детерминизм, таргетинг, рейт-лимиты/конкуренцию, миграции/сейвы. Пути и включённость видны в Rojo-дереве.&#x20;

**Client harnesses**:

* `NetworkTest.client.lua` — базовые сетевые сценарии, ручной запуск.
* `Dev/VMHarness.client.lua` — печать профиля/коллекции/деки, анализ состава, рандомная дека.
* `Dev/DevPanel.client.lua` — панель действий в рантайме.&#x20;

**Покрытие сейчас:** ядро механик, сеть, персист, клиентская интеграция, миграции — покрыты; **не покрыто**: бизнес-логика лутбоксов, Level-Up эндпоинт, полноценные UI-юнит-тесты.&#x20;

## 10) Быстрый старт (Studio)

1. **Rojo serve** → открыть проект в Studio, синк.
2. В `src/client/Config.lua` для оффлайна → `USE_MOCKS=true`, `SHOW_DEV_PANEL=true`, `AUTO_REQUEST_PROFILE=true`.
3. Запустить игру: панель появится влево-сверху; тесты — из панели и/или через VMHarness/NetworkTest.&#x20;

## 11) Дорожная карта (по состоянию на README)

Планируемые, **ещё не реализованные** фичи: серверный эндпоинт level-up, механики лутбоксов, магазин, туториал, PvP-матчмейкинг, дейлики/ачивки, социальные функции. **Текущий фокус** — ядро систем и клиентский слой; UI-фундаменты готовы для интеграции.&#x20;

## 12) Глоссарий (сжатый)

* **Deck** — 6 уникальных `cardId`.
* **slotNumber** — упорядочивает карты в слоты 1..6; визуально сетка `5 3 1 / 6 4 2`.&#x20;
* **Armor pool** — defence действует как истощаемый щит; остаточный урон идёт в HP.&#x20;
* **squadPower** — сумма `power` карт из активной деки.&#x20;
* **serverNow** — метка времени сервера в каждом ответе/ивенте.&#x20;
* **Shop Integration** — полная интеграция с Developer Products и покупка лутбоксов за hard currency.
* **Lootbox System** — 4-слотная система с overflow handling и детерминированными наградами (uncommon/rare/epic/legendary).
* **Level-Up System** — система прокачки карт 1-10 уровней с атомарными операциями.
* **Hard Currency Drops** — Epic лутбоксы: 9% шанс 1-29 hard, Legendary: 12% шанс 1-77 hard.
* **Structured Logging** — централизованная система логирования с debug-флагом для ключевых событий.
