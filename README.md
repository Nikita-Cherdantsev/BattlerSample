# BattlerSample - Anime Card Battler MVP

A server-authoritative, deterministic card battler game built on Roblox with a 3×2 board layout. Features profile management, card collection, deck building, and turn-based combat with fixed turn order and same-index targeting. The system includes offline development capabilities through mocks, comprehensive testing harnesses, and a client-side integration layer ready for UI development.

## Table of Contents

- [At a Glance](#at-a-glance)
- [Repository Structure](#repository-structure)
- [Runtime Architecture](#runtime-architecture)
- [Data & Persistence](#data--persistence)
- [Cards, Levels, Deck, Combat](#cards-levels-deck-combat)
- [Networking Surface](#networking-surface)
- [Client Integration Layer](#client-integration-layer)
- [Testing & Dev Harnesses](#testing--dev-harnesses)
- [Build & Dev Environment](#build--dev-environment)
- [Performance & Security Notes](#performance--security-notes)
- [Roadmap](#roadmap)
- [Glossary](#glossary)

## At a Glance

**MVP Features Implemented:**
- ✅ Profile system with v2 schema (collection, deck, currencies, lootboxes)
- ✅ Card catalog with 8 cards (4 rarities, 3 classes, slot-based ordering)
- ✅ Deck validation (6 unique cards, slot mapping by slotNumber)
- ✅ Deterministic combat engine (fixed turn order, same-index targeting, defence soak)
- ✅ Network layer with rate limiting and concurrency guards
- ✅ Client-side integration (NetworkClient, ClientState, ViewModels)
- ✅ Offline development (mocks, dev panel, comprehensive testing)
- ✅ DataStore persistence with v1→v2 migration

## Repository Structure

```
BattlerSample/
├── src/
│   ├── server/                    # Server-side logic and services
│   │   ├── Services/              # Core game services (MatchService, PlayerDataService)
│   │   ├── Persistence/           # DataStore layer and profile management
│   │   └── Network/               # RemoteEvent definitions and rate limiting
│   ├── shared/                    # Shared modules used by both client and server
│   │   └── Modules/               # Core game logic (Cards, Combat, Utilities)
│   └── client/                    # Client-side integration and UI foundations
│       ├── Controllers/           # NetworkClient wrapper over RemoteEvents
│       ├── State/                 # ClientState store and selectors
│       ├── Dev/                   # Development tools (DevPanel, mocks, harnesses)
│       └── Config.lua             # Client-side feature flags
├── docs/                          # Detailed documentation and guides
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
- **Combat**: Integer math with 50% defence soak damage reduction

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
- **Level Range**: 1-7 (MAX_LEVEL)
- **Cost Model**: `requiredCount` cards + `softAmount` currency per level
- **Increments**: Per-level stat bonuses defined in `CardStats.DefaultIncrements`

### CardStats

**Computation:**
```lua
-- Get stats for a card at specific level
local stats = CardStats.ComputeStats(cardId, level)
-- Returns: { attack, health, defence } with level bonuses applied

-- Compute power rating
local power = CardStats.ComputePower(stats)
-- Returns: weighted combination of stats for deck power calculation
```

**Customization Hook**: Per-card, per-level increments can be adjusted in `CardStats.DefaultIncrements`

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
- **Damage**: `attack - (defence * 0.5)` with integer math
- **Defence Soak**: 50% damage reduction from defence stat
- **Round Cap**: Maximum 50 rounds to prevent infinite battles
- **Draw Rules**: Survivor count determines winner

## Networking Surface

### RemoteEvents

**Profile Management:**
- **`RequestProfile`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestSetDeck`** (C→S) → **`ProfileUpdated`** (S→C)

**Match System:**
- **`RequestStartMatch`** (C→S) → **Response on same event** (S→C)

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

### Rate Limiting & Guards

**Per-Endpoint Limits:**
- **RequestSetDeck**: 2s cooldown, 5/minute
- **RequestProfile**: 1s cooldown, 10/minute  
- **RequestStartMatch**: 1s cooldown, 5/minute

**Concurrency Guards:**
- **Per-Player State**: `isInMatch` flag prevents overlapping matches
- **Studio Testing**: Extended busy window (0.75s) for deterministic testing

### Error Codes

| Code | Meaning |
|------|---------|
| `RATE_LIMITED` | Request frequency exceeded |
| `INVALID_REQUEST` | Malformed request payload |
| `DECK_UPDATE_FAILED` | Deck validation failed |
| `PROFILE_LOAD_FAILED` | Profile data corruption |
| `NO_DECK` | Player has no active deck |
| `INVALID_DECK` | Deck violates rules (duplicates, wrong size) |
| `BUSY` | Player already in match |
| `INTERNAL` | Server-side error |

## Client Integration Layer

**Reference**: See [docs/ui_integration.md](docs/ui_integration.md) for complete UI integration guide.

**Core Components:**
- **NetworkClient**: Unified interface for mock/real server communication
- **ClientState**: Centralized state store with subscription system
- **Selectors**: Pure functions for data extraction and transformation
- **ViewModels**: UI-ready data structures (CardVM, DeckVM, ProfileVM)

**Key Features:**
- **Time Sync**: `serverNow` for accurate timers and lootbox countdowns
- **Grid Layout**: `BoardLayout.gridForDeck()` for 3×2 board rendering
- **Assets**: Centralized manifest and resolver for consistent UI styling
- **Configuration**: Feature flags for development vs production

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

## Testing & Dev Harnesses

### Self-Checks

**Run in Studio Console:**
```lua
local Utilities = require(game:GetService("ReplicatedStorage").Modules.Utilities)
Utilities.SelfCheck.RunAllTests()
```

**Validates**: Card catalog consistency, deck validation rules, combat mechanics, time utilities

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

### Client-Side Testing

**NetworkTest** (`src/client/NetworkTest.client.lua`):
- **Purpose**: Test client-server communication
- **Run**: `NetworkTest.RunAllTests()` in Studio console
- **Tests**: Profile requests, deck updates, match requests, error handling

**VMHarness** (`src/client/Dev/VMHarness.client.lua`):
- **Purpose**: Test ViewModels and client state
- **Run**: Automatically on client start
- **Tests**: ProfileVM building, deck rendering, squad power calculation

**DevPanel** (`src/client/Dev/DevPanel.client.lua`):
- **Purpose**: Runtime testing UI
- **Enable**: `Config.SHOW_DEV_PANEL = true`
- **Features**: Profile refresh, sample deck, PvE match, mock toggle

### Coverage Status

**✅ Covered:**
- Core game mechanics (combat, deck validation, persistence)
- Network layer (rate limiting, concurrency, error handling)
- Client integration (state management, ViewModels, mocks)
- Profile system (creation, migration, validation)

**❌ Not Covered:**
- UI unit tests (no UI framework yet)
- Lootbox business logic (unlocking, opening)
- Card level-up mechanics
- Tutorial flow implementation

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
Config.USE_MOCKS = true         -- Offline development
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

## Roadmap

**Planned Features (Not Yet Implemented):**

- [ ] **Card Level-Up Endpoint**: Server endpoint for upgrading card levels
- [ ] **Lootbox Mechanics**: Open/start unlocking business logic
- [ ] **Store System**: Currency spending and card purchases
- [ ] **Tutorial Flow**: Step-by-step onboarding experience
- [ ] **PvP Matchmaking**: Player vs player battle system
- [ ] **Daily Rewards**: Login streak bonuses and daily quests
- [ ] **Achievement System**: Progress tracking and rewards
- [ ] **Social Features**: Friends, guilds, leaderboards

**Current Focus:**
- ✅ **Core Systems**: Profile, cards, combat, networking
- ✅ **Client Layer**: Integration tools and development environment
- 🔄 **UI Foundation**: Ready for UI engineer to build interfaces
- ⏳ **Game Features**: Level-up, lootboxes, progression systems

## Glossary

**Core Game Terms:**
- **Card**: Individual unit with stats, rarity, class, and slot number
- **Deck**: Collection of exactly 6 unique cards for battle
- **Slot Number**: Integer (10-80) determining deck→slot mapping order
- **Squad Power**: Computed metric representing deck strength
- **Defence Soak**: 50% damage reduction from defence stat in combat
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
---
---

# Спецификация проекта (Russian language version)

Ниже — сводный документ по текущей кодовой базе: архитектура, данные, модули, сети, клиентская интеграция, тесты и «как запускать». Он склеивает то, что уже зафиксировано в README и UI-гайде, добавляет пояснения и устраняет мелкие разрывы между документами.

## 1) Цель и обзор

Игра — **детерминированный аниме card-battler** на сетке 3×2. Сервер — единственный источник правды: расчёт боя, валидации, персист. Клиент — рендер и ввод. Уже реализовано: профиль v2, каталог карт, уровни и статы, валидация дек, детерминированный бой, матч-сервис, минимальные RemoteEvents, клиентская интеграция (NetworkClient/ClientState/VM), моки, дев-панель.&#x20;

**Детерминизм:** фиксированный порядок ходов по слотам (1→6), таргетинг «тот же индекс → ближайшая живая цель (tie → меньший индекс)», 50% soak в защиту (целочисленная арифметика). Во все серверные ответы добавлен `serverNow` для синхронизации таймеров. &#x20;

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
* **CardLevels**: ур. 1–7; для каждого уровня задаются `requiredCount`, `softAmount`.&#x20;
* **CardStats**: вычисляет эффективные статы карточки с учётом уровня; `power` = функция (`atk/hp/defence`), используется для `squadPower`.&#x20;
* **DeckValidator**: принимает **ровно 6 уникальных** id; маппинг к слотам (1..6) по возрастанию `slotNumber`; клиент может визуализировать сетку через BoardLayout. &#x20;
* **CombatEngine**: ходят слоты 1→6; таргет «тот же индекс», иначе ближайший живой (tie → меньший индекс); **defence soak 50%** (shield-подобная механика); кап по раундам, ничьи — корректно обрабатываются.&#x20;

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

**Рейт-лимиты и конкуренция:** token-bucket и флаг «занят» на игрока (например, при матчах) уже описаны и реализованы.&#x20;

**Коды ошибок** (канонический набор в документации): `RATE_LIMITED`, `INVALID_REQUEST`, `DECK_UPDATE_FAILED`, `PROFILE_LOAD_FAILED`, `NO_DECK`, `INVALID_DECK`, `BUSY`, `INTERNAL`, + клиентский ErrorMap покрывает и карточные/моковые варианты. &#x20;

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
* **Defence soak** — 50% входящего урона уходит в «щит».&#x20;
* **squadPower** — сумма `power` карт из активной деки.&#x20;
* **serverNow** — метка времени сервера в каждом ответе/ивенте.&#x20;
