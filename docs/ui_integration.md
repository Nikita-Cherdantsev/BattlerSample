# UI Integration Guide

This document provides the essential information for integrating the UI with the Card Battler server.

## Table of Contents

- [RemoteEvents Overview](#remoteevents-overview)
- [Payload Fields](#payload-fields)
- [Assets Manifest](#assets-manifest)
- [Config Flags](#config-flags)
- [Mock Layer](#mock-layer)
- [Shared Modules](#shared-modules)
- [Deck Rendering](#deck-rendering)
- [Error Handling](#error-handling)
- [Time Synchronization](#time-synchronization)
- [Client Integration Layer](#client-integration-layer)
- [Level-Up Flow](#level-up-flow)
- [Collection View](#collection-view)
- [Dev Harness](#dev-harness)
- [Assets](#assets)
- [Configuration Flags](#configuration-flags)
- [Mocks](#mocks)
- [Dev Panel](#dev-panel)
- [Client-Side Architecture](#client-side-architecture)
- [Troubleshooting](#troubleshooting)
- [Lootboxes UI](#lootboxes-ui)
- [Shop UI](#shop-ui)
- [Deck Uniqueness and Ordering](#deck-uniqueness-and-ordering)

## RemoteEvents Overview

The server communicates with clients through these key RemoteEvents:

### 1. Profile Management
- **`RequestProfile`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestSetDeck`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestLevelUpCard`** (C→S) → **`ProfileUpdated`** (S→C)

### 2. Match System
- **`RequestStartMatch`** (C→S) → **Response on same event** (S→C)

### 3. Lootbox System
- **`RequestLootState`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestAddBox`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestResolvePendingDiscard`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestResolvePendingReplace`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestStartUnlock`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestOpenNow`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestCompleteUnlock`** (C→S) → **`ProfileUpdated`** (S→C)

## Payload Fields

### ProfileUpdated Payload
```lua
{
  deck = {string, string, string, string, string, string}, -- 6 unique cardIds
  collectionSummary = {
    {cardId = string, count = number, level = number},
    -- ... more cards
  },
  loginInfo = {
    lastLoginAt = number,
    loginStreak = number
  },
  squadPower = number,
  lootboxes = {
    {id = string, rarity = string, state = string, acquiredAt = number, startedAt = number?, unlocksAt = number?, seed = string?, source = string?},
    -- ... more lootboxes
  },
  pendingLootbox = {id = string, rarity = string, seed = string?, source = string?} | nil,
  currencies = {soft = number, hard = number}, -- When changed
  updatedAt = number,
  serverNow = number, -- Server timestamp for time sync
  error = {code = string, message = string}? -- Only present on errors
}
```

### Match Response Payload
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
  log = {
    {type = string, round = number, attackerSlot = number, defenderSlot = number, damage = number, ...},
    -- ... more log entries
  }?,
  serverNow = number, -- NEW: Server timestamp for time sync
  error = {code = string, message = string}? -- Only present on errors
}
```

## Assets Manifest

The UI uses a centralized assets manifest for consistent styling and easy asset management:

### Accessing Assets

```lua
local Utilities = require(game:GetService("ReplicatedStorage").Modules.Utilities)
local Assets = Utilities.Assets

-- Get asset IDs
local cardImage = Assets.Resolver.getCardImage("dps_001")
local classIcon = Assets.Resolver.getClassIcon("DPS")
local rarityFrame = Assets.Resolver.getRarityFrame("Rare")
local rarityColor = Assets.Resolver.getRarityColor("Epic")
```

### Available Assets

- **Card Images**: `Assets.Manifest.CardImages[cardId]` - Card artwork
- **Class Icons**: `Assets.Manifest.ClassIcons[class]` - DPS/Support/Tank icons
- **Rarity Frames**: `Assets.Manifest.RarityFrames[rarity]` - Card frame borders
- **Rarity Colors**: `Assets.Manifest.RarityColors[rarity]` - Color3 values for UI
- **Placeholder Assets**: Fallback assets when real content is missing

### Adding New Assets

1. Add asset ID to `Assets.Manifest.CardImages[newCardId]`
2. Add corresponding entry in `Assets.Resolver.getCardImage()`
3. Assets automatically fall back to placeholders if missing

## Config Flags

Client-side configuration for development and debugging:

### Available Flags

```lua
-- In src/client/Config.lua
Config.USE_MOCKS = false        -- Route networking through mocks
Config.SHOW_DEV_PANEL = true    -- Show dev panel UI
Config.DEBUG_LOGS = false       -- Enable verbose logging
Config.AUTO_REQUEST_PROFILE = true  -- Auto-request profile on startup
```

### Recommended Settings

**Development:**
```lua
Config.USE_MOCKS = true
Config.SHOW_DEV_PANEL = true
Config.DEBUG_LOGS = true
Config.AUTO_REQUEST_PROFILE = true
```

**Production:**
```lua
Config.USE_MOCKS = false
Config.SHOW_DEV_PANEL = false
Config.DEBUG_LOGS = false
Config.AUTO_REQUEST_PROFILE = true
```

## Mock Layer

The mock system provides offline development capabilities without requiring a running server:

### Enabling Mocks

```lua
-- Set in Config.lua
Config.USE_MOCKS = true
```

### Mock Features

- **Profile Simulation**: Realistic profile data with 8 valid cards
- **Deck Validation**: Client-side validation matching server logic
- **Network Latency**: Simulated network delays for realistic testing
- **Error Simulation**: All error codes from ErrorMap
- **Time Synchronization**: Mock server timestamps for lootboxes

### Mock Data Structure

The mock system uses exactly the same card data as the server:
- **8 Valid Cards**: `dps_001`, `support_001`, `tank_001`, `dps_002`, `support_002`, `dps_003`, `tank_002`, `dps_004`
- **Rarity Values**: `"common"`, `"rare"`, `"epic"`, `"legendary"` (lowercase)
- **Class Values**: `"dps"`, `"support"`, `"tank"` (lowercase)
- **Slot Numbers**: 10, 20, 30, 40, 50, 60, 70, 80

### Switching Between Mocks and Real Server

```lua
-- Toggle at runtime via Dev Panel
-- Or change Config.USE_MOCKS and restart

-- The system automatically:
-- 1. Cleans up existing subscriptions
-- 2. Reinitializes NetworkClient and ClientState
-- 3. Immediately requests fresh profile data
```

## Shared Modules

Import the shared modules from `ReplicatedStorage.Modules.Utilities`:

```lua
local Utilities = require(game:GetService("ReplicatedStorage").Modules.Utilities)
local Types = Utilities.Types
local ErrorMap = Utilities.ErrorMap
local BoardLayout = Utilities.BoardLayout
local TimeUtils = Utilities.TimeUtils
```

### Types.lua
Provides type definitions and constant enums:

```lua
-- Enums
Types.Rarity.Common, Types.Rarity.Rare, Types.Rarity.Epic, Types.Rarity.Legendary
Types.Class.DPS, Types.Class.Support, Types.Class.Tank
Types.LootboxState.Idle, Types.LootboxState.Unlocking, Types.LootboxState.Ready

-- Type definitions (for reference)
-- CollectionEntry = { count: number, level: number }
-- Deck = { string, string, string, string, string, string } -- 6 unique cardIds
-- ProfileV2 = { version, playerId, createdAt, lastLoginAt, loginStreak, collection, deck, currencies, ... }
```

### ErrorMap.lua
Maps error codes to user-facing messages:

```lua
local userMessage = ErrorMap.toUserMessage("RATE_LIMITED")
-- Returns: { title = "Too Many Requests", message = "Please wait a moment before trying again." }

-- Available error codes:
-- RATE_LIMITED, INVALID_REQUEST, DECK_UPDATE_FAILED, PROFILE_LOAD_FAILED
-- NO_DECK, INVALID_DECK, BUSY, INTERNAL, CARD_NOT_FOUND, INSUFFICIENT_CARDS
-- LOOTBOX_NOT_FOUND, LOOTBOX_ALREADY_OPENING
```

### BoardLayout.lua
Provides helpers for the 3×2 grid layout:

```lua
-- Visual Layout (3×2 grid):
-- Row1: slots 5 3 1
-- Row2: slots 6 4 2

-- Convert deck to grid for UI rendering
local grid = BoardLayout.gridForDeck(deckIds)
-- Returns: { {slot=1,row=1,col=3,cardId="dps_001"}, {slot=2,row=2,col=3,cardId="support_001"}, ... }

-- Fixed turn order (slot 1 acts first)
local turnOrder = BoardLayout.SLOT_ORDER() -- {1, 2, 3, 4, 5, 6}

-- Get slot position
local pos = BoardLayout.getSlotPosition(1) -- {row = 1, col = 3}

-- Validate slot
local isValid = BoardLayout.isValidSlot(3) -- true
```

### TimeUtils.lua
Provides time utilities and lootbox durations:

```lua
-- Get current server time
local now = TimeUtils.nowUnix()

-- Lootbox durations
local commonDuration = TimeUtils.lootboxDurations.Common -- 1200 seconds (20 minutes)

-- Format duration
local formatted = TimeUtils.formatDuration(3661) -- "1h 1m"

-- Calculate time remaining
local remaining = TimeUtils.getTimeRemaining(endTimestamp)
```

## Deck Rendering

### Grid Layout
Use `BoardLayout.gridForDeck()` to convert a deck into a grid layout:

```lua
local deck = {"dps_001", "support_001", "tank_001", "dps_002", "support_002", "tank_002"}
local grid = BoardLayout.gridForDeck(deck)

-- Render each card at its grid position
for _, card in ipairs(grid) do
  -- card.slot = 1-6 (turn order)
  -- card.row = 1-2 (visual row)
  -- card.col = 1-3 (visual column)
  -- card.cardId = "dps_001"
  renderCard(card.cardId, card.row, card.col)
end
```

### Deck Order
The deck order is derived by `slotNumber` on the server. When building a deck preview, sort catalog entries by `slotNumber` to match the server's ordering.

### Turn Order
Slots act in fixed order: 1, 2, 3, 4, 5, 6 (slot 1 acts first).

## Error Handling

Use `ErrorMap.toUserMessage()` to convert server error codes to user-friendly messages:

```lua
-- Handle server response
local response = RemoteEvent.OnServerEvent:Connect(function(payload)
  if payload.error then
    local userMessage = ErrorMap.toUserMessage(payload.error.code, payload.error.message)
    showErrorDialog(userMessage.title, userMessage.message)
  end
end)
```

## Time Synchronization

The server now includes `serverNow` in all responses for time synchronization:

```lua
-- Store last known server time
local lastServerTime = 0

-- Update on each response
local function updateServerTime(payload)
  if payload.serverNow then
    lastServerTime = payload.serverNow
  end
end

-- Use for client-side time calculations
local function getClientTime()
  return lastServerTime + (os.time() - lastServerTime)
end
```

## Client Integration Layer

The client integration layer provides a clean, reliable interface for UI development with minimal domain knowledge required.

### NetworkClient

```lua
local NetworkClient = require(script.Parent.Parent.Controllers.NetworkClient)

-- Request profile from server
NetworkClient.requestProfile()

-- Request deck update
local success, error = NetworkClient.requestSetDeck({"dps_001", "support_001", "tank_001", "dps_002", "support_002", "tank_002"})
if not success then
    print("Deck update failed:", error)
end

-- Request match start
NetworkClient.requestStartMatch({mode = "PvE", seed = 12345})

-- Subscribe to profile updates
NetworkClient.onProfileUpdated(function(payload)
    if payload.error then
        local userMessage = ErrorMap.toUserMessage(payload.error.code)
        showError(userMessage.title, userMessage.message)
        return
    end
    
    -- Handle successful profile update
    updateUI(payload)
end)

-- Get server time
local serverNow = NetworkClient.getServerNow()
```

### ClientState

```lua
local ClientState = require(script.Parent.Parent.State.ClientState)

-- Initialize with NetworkClient
ClientState.init(NetworkClient)

-- Subscribe to state changes
ClientState.subscribe(function(state)
    if state.profile then
        -- Profile data available
        local deckIds = state.profile.deck
        local collection = state.profile.collection
        local squadPower = state.profile.squadPower
    end
    
    if state.lastError then
        -- Handle error
        showError(state.lastError.code, state.lastError.message)
    end
end)

-- Get current state
local state = ClientState.getState()
```

### Selectors

```lua
local selectors = require(script.Parent.Parent.State.selectors)

-- Extract specific data from state
local deckIds = selectors.selectDeckIds(state)
local collection = selectors.selectCollectionMap(state)
local currencies = selectors.selectCurrencies(state)
local lootboxes = selectors.selectLootboxes(state)
local serverNow = selectors.selectServerNow(state)

-- Get collection as sorted list
local sortedCollection = selectors.selectCollectionAsList(state, {sortBy = "rarity"})
-- sortBy options: "name", "rarity", "level", "slotNumber"
```

### ViewModels

#### CardVM

```lua
local CardVM = require(ReplicatedStorage.Modules.ViewModels.CardVM)

-- Build card view model
local cardVM = CardVM.build("dps_001", {count = 5, level = 3})
-- Returns: {id, name, rarity, class, level, stats, power, slotNumber, description, ...}
-- Note: stats are computed using per-card growth tables (base + level-specific deltas)

-- Build multiple cards
local cardVMs = CardVM.buildMultiple({"dps_001", "support_001"}, collection)

-- Build entire collection
local collectionVMs = CardVM.buildCollection(profile.collection)
```

#### DeckVM

```lua
local DeckVM = require(ReplicatedStorage.Modules.ViewModels.DeckVM)

-- Build deck view model
local deckVM = DeckVM.build(deckIds, collection)
-- Returns: {slots, squadPower, cardIds, ...}

-- Get slot by index
local slot1 = DeckVM.getSlot(deckVM, 1)
-- Returns: {slot = 1, row = 1, col = 3, card = CardVM}

-- Get deck composition
local composition = DeckVM.getComposition(deckVM)
-- Returns: {classes = {DPS = 2, Support = 2, Tank = 2}, rarities = {...}}
```

#### ProfileVM

```lua
local ProfileVM = require(ReplicatedStorage.Modules.ViewModels.ProfileVM)

-- Build profile view model
local profileVM = ProfileVM.build(profile, serverNow)
-- Returns: {deckVM, collectionVM, lootboxes, currencies, loginInfo, squadPower, ...}

-- Get collection sorted
local sortedCollection = ProfileVM.getCollectionSorted(profileVM, "power")
-- sortBy options: "name", "rarity", "level", "power", "slotNumber"

-- Get cards by class
local dpsCards = ProfileVM.getCardsByClass(profileVM, Types.Class.DPS)

-- Get unlocking lootboxes with remaining time
local unlocking = ProfileVM.getUnlockingLootboxes(profileVM)
-- Each lootbox has: {entry, remaining, formattedRemaining}
```

### Complete Integration Example

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkClient = require(script.Parent.Parent.Controllers.NetworkClient)
local ClientState = require(script.Parent.Parent.State.ClientState)
local ProfileVM = require(ReplicatedStorage.Modules.ViewModels.ProfileVM)

-- Initialize
ClientState.init(NetworkClient)

-- Subscribe to state changes
ClientState.subscribe(function(state)
    if state.profile then
        -- Build profile view model
        local profileVM = ProfileVM.buildFromState(state)
        
        -- Update UI
        updateDeckGrid(profileVM.deckVM.slots)
        updateCollection(profileVM.collectionVM)
        updateLootboxes(profileVM.lootboxes)
        updateCurrencies(profileVM.currencies)
        updateSquadPower(profileVM.squadPower)
    end
end)

-- Request initial data
NetworkClient.requestProfile()
```

## Level-Up Flow

The Level-Up system allows players to upgrade their cards by spending copies and soft currency. This section covers the complete flow from UI rendering to server communication.

### Reading Upgradeability

Use selectors to determine if a card can be leveled up:

```lua
local selectors = require(script.Parent.Parent.State.selectors)

-- Check if a specific card can be leveled up
local canLevelUp = selectors.selectCanLevelUp(state, "card_100")
if canLevelUp.can then
    print(string.format("Can level up to level %d", canLevelUp.nextLevel))
    print(string.format("Cost: %d copies, %d soft currency", 
        canLevelUp.requiredCount, canLevelUp.softAmount))
else
    print("Cannot level up:", canLevelUp.reason)
    if canLevelUp.shortfallCount > 0 then
        print(string.format("Need %d more copies", canLevelUp.shortfallCount))
    end
    if canLevelUp.shortfallSoft > 0 then
        print(string.format("Need %d more soft currency", canLevelUp.shortfallSoft))
    end
end

-- Get all upgradeable cards
local upgradeableCards = selectors.selectUpgradeableCards(state)
for _, card in ipairs(upgradeableCards) do
    print(string.format("%s: Level %d → %d (cost: %d copies, %d soft)", 
        card.cardId, card.currentLevel, card.nextLevel, 
        card.requiredCount, card.softAmount))
end
```

### Using CardVM for UI

CardVM provides upgrade-related fields for easy UI integration:

```lua
local CardVM = require(game.ReplicatedStorage.Modules.ViewModels.CardVM)

-- Build card view model with upgrade info
local cardVM = CardVM.build("card_100", collectionEntry, profileState)

-- UI can directly use these fields:
if cardVM.canLevelUp then
    upgradeButton.Visible = true
    upgradeButton.Text = string.format("Level Up (%d copies, %d soft)", 
        cardVM.requiredCount, cardVM.softAmount)
else
    upgradeButton.Visible = false
    -- Show reason why can't level up
    if cardVM.upgradeReason == "LEVEL_MAXED" then
        reasonLabel.Text = "Max Level Reached"
    elseif cardVM.upgradeReason == "INSUFFICIENT_COPIES" then
        reasonLabel.Text = string.format("Need %d more copies", cardVM.shortfallCount)
    elseif cardVM.upgradeReason == "INSUFFICIENT_SOFT" then
        reasonLabel.Text = string.format("Need %d more soft currency", cardVM.shortfallSoft)
    end
end
```

### Triggering Level-Up

Use NetworkClient to request a level-up:

```lua
local NetworkClient = require(script.Parent.Parent.Controllers.NetworkClient)

-- Request level-up for a specific card
local success, errorMessage = NetworkClient.requestLevelUpCard("card_100")
if not success then
    print("Level-up request failed:", errorMessage)
end

-- Check if any request is in flight
if NetworkClient.isBusy() then
    print("Request in progress, please wait...")
end
```

### Handling Responses

Listen for ProfileUpdated events to refresh UI state:

```lua
local ClientState = require(script.Parent.Parent.State.ClientState)

-- Subscribe to state changes
ClientState.subscribe(function(state)
    if state.isLeveling then
        -- Show loading state
        upgradeButton.Text = "Leveling Up..."
        upgradeButton.Active = false
    elseif state.lastError then
        -- Handle error
        local errorMap = require(game.ReplicatedStorage.Modules.Utilities.ErrorMap)
        local userMessage = errorMap.toUserMessage(state.lastError.code, state.lastError.message)
        print("Level-up failed:", userMessage.title, "-", userMessage.message)
        
        -- Re-enable button
        upgradeButton.Active = true
    else
        -- Success or idle state
        upgradeButton.Active = true
        -- Refresh card display with new level/stats
        refreshCardDisplay()
    end
end)
```

### Error Codes

The following error codes can be returned from level-up requests:

| Code | Meaning | User Message |
|------|---------|--------------|
| `INVALID_REQUEST` | Malformed request | "Invalid request" |
| `CARD_NOT_OWNED` | Card not in collection | "Card not found in collection" |
| `LEVEL_MAXED` | Card already at max level | "Card is already at maximum level" |
| `INSUFFICIENT_COPIES` | Not enough card copies | "Need X more copies" |
| `INSUFFICIENT_SOFT` | Not enough soft currency | "Need X more soft currency" |
| `RATE_LIMITED` | Too many requests | "Please wait before trying again" |
| `INTERNAL` | Server error | "An error occurred, please try again" |

Use ErrorMap to convert codes to user-friendly messages:

```lua
local ErrorMap = require(game.ReplicatedStorage.Modules.Utilities.ErrorMap)
local userMessage = ErrorMap.toUserMessage(errorCode, fallbackMessage)
errorLabel.Text = userMessage.message
```

### Time Synchronization

Always use `serverNow` from ProfileUpdated payloads for consistent timing:

```lua
-- In ProfileUpdated handler
if payload.serverNow then
    -- Update local time reference
    local timeDiff = payload.serverNow - os.time()
    -- Use for countdown timers, etc.
end
```

### Complete Level-Up Button Example

```lua
local function createLevelUpButton(cardId, cardVM)
    local button = Instance.new("TextButton")
    button.Text = "Level Up"
    button.Size = UDim2.new(0, 100, 0, 30)
    
    local function updateButton()
        if cardVM.canLevelUp then
            button.Visible = true
            button.Active = true
            button.Text = string.format("Level Up (%d copies, %d soft)", 
                cardVM.requiredCount, cardVM.softAmount)
        else
            button.Visible = false
        end
    end
    
    button.MouseButton1Click:Connect(function()
        if not NetworkClient.isBusy() then
            NetworkClient.requestLevelUpCard(cardId)
        end
    end)
    
    -- Update button when card data changes
    updateButton()
    return button
end
```

## Collection View

The Collection View provides a unified interface for displaying all cards in the catalog with ownership overlay. This enables building a comprehensive collection screen that shows both owned and unowned cards.

### Getting the Unified Collection

Use the `selectUnifiedCollection` selector to get all catalog cards with ownership data:

```lua
local selectors = require(script.Parent.Parent.State.selectors)
local state = ClientState.getState()

-- Get all cards with ownership overlay
local unifiedCollection = selectors.selectUnifiedCollection(state)

-- Apply filters and sorting
local ownedOnly = selectors.selectUnifiedCollection(state, {
    ownedOnly = true,
    sortBy = "power"
})

-- Search and filter
local searchResults = selectors.selectUnifiedCollection(state, {
    searchTerm = "fighter",
    rarityIn = {"rare", "epic"},
    sortBy = "rarity"
})
```

### Collection Data Structure

Each card in the unified collection has this structure:

```lua
{
    cardId = "card_100",
    name = "Recruit Fighter",
    rarity = "common",
    class = "dps", 
    slotNumber = 10,
    description = "A basic fighter with balanced stats.",
    owned = true,  -- Ownership flag
    
    -- Only present when owned = true:
    level = 3,
    count = 25,
    stats = { atk = 15, hp = 20, defence = 7 },
    power = 42
}
```

### Building ViewModels

Pass unified collection data through `CardVM.buildFromUnifiedCollection`:

```lua
local CardVM = require(game.ReplicatedStorage.Modules.ViewModels.CardVM)

-- Build VMs from unified collection
local vms = CardVM.buildFromUnifiedCollection(unifiedCollection, state)

-- Each VM will have the same structure as above, plus upgradeability fields
for _, vm in ipairs(vms) do
    if vm.owned then
        -- Show full card with stats, level, power
        print(string.format("%s (Lv.%d) - %d power", vm.name, vm.level, vm.power))
    else
        -- Show greyed out card without stats
        print(string.format("%s (Not Owned)", vm.name))
    end
end
```

### UI Implementation Example

```lua
-- In your Collection screen UI
local function renderCollectionCard(vm)
    local cardFrame = createCardFrame()
    
    -- Always show basic info
    cardFrame.NameLabel.Text = vm.name
    cardFrame.RarityLabel.Text = string.upper(vm.rarity)
    cardFrame.ClassLabel.Text = string.upper(vm.class)
    
    if vm.owned then
        -- Show owned card with full data
        cardFrame.LevelLabel.Text = "Lv." .. vm.level
        cardFrame.CountLabel.Text = "x" .. vm.count
        cardFrame.PowerLabel.Text = vm.power .. " power"
        cardFrame.StatsLabel.Text = string.format("ATK:%d HP:%d DEF:%d", 
            vm.stats.atk, vm.stats.hp, vm.stats.defence)
        
        -- Normal styling
        cardFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        cardFrame.TextColor3 = Color3.fromRGB(0, 0, 0)
    else
        -- Show unowned card (greyed out)
        cardFrame.LevelLabel.Text = "???"
        cardFrame.CountLabel.Text = "???"
        cardFrame.PowerLabel.Text = "???"
        cardFrame.StatsLabel.Text = "ATK:??? HP:??? DEF:???"
        
        -- Greyed styling
        cardFrame.BackgroundColor3 = Color3.fromRGB(128, 128, 128)
        cardFrame.TextColor3 = Color3.fromRGB(200, 200, 200)
    end
end
```

### Sorting and Grouping

The unified collection supports various sorting and grouping options:

```lua
-- Sort by different criteria
local byRarity = selectors.selectUnifiedCollection(state, { sortBy = "rarity" })
local byPower = selectors.selectUnifiedCollection(state, { sortBy = "power" })
local byName = selectors.selectUnifiedCollection(state, { sortBy = "name" })

-- Group by rarity or class
local groupedByRarity = selectors.selectUnifiedCollection(state, { 
    groupBy = "rarity" 
})
-- Returns: { {groupKey = "legendary", items = {...}}, {groupKey = "epic", items = {...}}, ... }

-- Filter options
local ownedOnly = selectors.selectUnifiedCollection(state, { ownedOnly = true })
local rareAndEpic = selectors.selectUnifiedCollection(state, { 
    rarityIn = {"rare", "epic"} 
})
local dpsOnly = selectors.selectUnifiedCollection(state, { 
    classIn = {"dps"} 
})
local searchResults = selectors.selectUnifiedCollection(state, { 
    searchTerm = "fighter" 
})
```

### Collection Summary

Use the DevPanel "Print Collection Summary" button to get diagnostic information about the collection, including:
- Total catalog size and owned count
- Coverage percentage
- Rarity breakdown (owned/total per rarity)
- Top power cards among owned
- Notable unowned cards

## Dev Harness

The `VMHarness` provides console-only testing of the client integration layer:

```lua
local VMHarness = require(script.Parent.Parent.Dev.VMHarness)

-- Print profile summary
VMHarness.PrintProfile()

-- Set random deck
VMHarness.SetDeckRandom()

-- Print collection sorted by power
VMHarness.PrintCollection("power")

-- Print deck analysis
VMHarness.PrintDeckAnalysis()

-- Print profile statistics
VMHarness.PrintStats()

-- Level-Up specific commands
VMHarness.LevelUpFirstUpgradeable()  -- Level up first available card
VMHarness.LevelUp("card_100")        -- Level up specific card
VMHarness.PrintUpgradeableCards()   -- Show all upgradeable cards
```

### How to Test Level-Up (Mocks)

1. **Enable dev flags** in `Config.lua`:
   ```lua
   Config.USE_MOCKS = true
   Config.SHOW_DEV_PANEL = true
   ```

2. **Start the game** in Studio and wait for the Dev Panel to appear

3. **Click "Refresh Profile"** to load initial data

4. **Click "Level Up First Upgradeable"** to test the level-up flow

5. **Observe console output** for before/after stats:
   - Card level and power changes
   - Squad power updates (if card is in deck)
   - Resource consumption (copies and soft currency)
   - Error messages (if any) via ErrorMap

6. **Test error cases** by trying to level up cards that:
   - Are already at max level (7)
   - Don't have enough copies
   - Don't have enough soft currency
   - Are not in the collection

The mock system provides the same validation and error codes as the real server, making it perfect for UI development and testing.

## Assets

The `Assets` module provides centralized asset management for UI development:

```lua
local Assets = Utilities.Assets

-- Get card images
local cardImage = Assets.Resolver.getCardImage("dps_001")
local classIcon = Assets.Resolver.getClassIcon("DPS")
local rarityFrame = Assets.Resolver.getRarityFrame("Rare")
local rarityColor = Assets.Resolver.getRarityColor("Epic")

-- Get UI colors
local backgroundColor = Assets.Resolver.getUIColor("background")
local buttonColor = Assets.Resolver.getButtonColor("hover")
```

### Adding New Assets

1. **Card Art**: Add entries to `Assets.Manifest.CardImages`
2. **Class Icons**: Add entries to `Assets.Manifest.ClassIcons`
3. **Rarity Frames**: Add entries to `Assets.Manifest.RarityFrames`
4. **Colors**: Add entries to `Assets.Manifest.RarityColors` or `Assets.Manifest.UIColors`

All assets have fallbacks to prevent crashes when assets are missing.

## Configuration Flags

The `Config` module controls various development features:

```lua
local Config = require(script.Parent.Parent.Config)

-- Mock Configuration
Config.USE_MOCKS = false  -- Use mock data instead of real server
Config.SHOW_DEV_PANEL = true  -- Show dev panel UI
Config.DEBUG_LOGS = false  -- Enable verbose logging
Config.AUTO_REQUEST_PROFILE = true  -- Auto-request profile on startup
```

### Recommended Settings

**Development:**
- `USE_MOCKS = true` - Work offline with mock data
- `SHOW_DEV_PANEL = true` - Access dev tools
- `DEBUG_LOGS = true` - See detailed logs

**Production:**
- `USE_MOCKS = false` - Use real server
- `SHOW_DEV_PANEL = false` - Hide dev tools
- `DEBUG_LOGS = false` - Minimal logging

## Mocks

The mock system allows UI development without a server:

### Enabling Mocks

```lua
-- In Config.lua
Config.USE_MOCKS = true
```

### What's Simulated

- **Profile Data**: Complete v2 profile with collection, deck, lootboxes
- **Network Latency**: Configurable delays (150ms default)
- **Error Responses**: Rate limiting, validation errors
- **Match Results**: Deterministic battle outcomes

### Mock Data Features

- **Realistic Profiles**: Uses actual card catalog and validation
- **Time-based Lootboxes**: Unlocking lootboxes with real timestamps
- **Squad Power**: Computed using real CardStats logic
- **Error Simulation**: All error codes from ErrorMap

### Limitations

- No real server persistence
- No multiplayer features
- No real-time updates from other players
- Mock data resets on script restart

## Dev Panel

The Dev Panel provides a minimal UI for testing common flows during development:

### Enabling the Dev Panel

```lua
-- In src/client/Config.lua
Config.SHOW_DEV_PANEL = true
```

### Panel Features

**Available Actions:**
1. **Refresh Profile** - Request fresh profile data from server/mocks
2. **Set Sample Deck** - Automatically create a valid 6-card deck using available cards
3. **Start PvE** - Initiate a PvE match request
4. **Toggle Mocks** - Switch between mock and real server at runtime

**Status Display:**
- **Server Time**: Last known server timestamp
- **Squad Power**: Current deck's computed power
- **Mock Status**: Shows "ON" or "OFF" for current mode

### Using the Dev Panel

1. **Enable in Config**: Set `Config.SHOW_DEV_PANEL = true`
2. **Run in Studio**: Panel appears automatically in top-left corner
3. **Test Flows**: Click buttons to test different client-server interactions
4. **Switch Modes**: Use "Toggle Mocks" to test offline/online functionality
5. **Monitor Status**: Watch status updates in real-time

### Panel Behavior

- **Auto-Initialization**: Creates UI automatically when enabled
- **Non-Intrusive**: Small, collapsible panel that doesn't interfere with gameplay
- **Runtime Toggle**: Mocks can be enabled/disabled without restarting
- **Status Updates**: Real-time updates based on ClientState changes

## Client-Side Architecture

The client-side system is designed for maximum developer ergonomics with offline development capabilities:

### File Structure

```
src/client/
├── Config.lua                    -- Configuration flags
├── Utilities.lua                 -- Client-side utilities (ModuleScript)
├── Controllers/
│   └── NetworkClient.lua         -- Network client (ModuleScript)
├── Dev/
│   ├── DevPanel.client.lua       -- Dev panel UI (LocalScript)
│   ├── MockData.lua              -- Mock data generators (ModuleScript)
│   ├── MockNetwork.lua           -- Mock network layer (ModuleScript)
│   └── VMHarness.client.lua      -- View model testing (LocalScript)
└── State/
    ├── ClientState.client.lua    -- State management (LocalScript)
    └── selectors.lua             -- State selectors (ModuleScript)
```

### Module Types

- **`.lua` files**: Become `ModuleScript` objects (can be required)
- **`.client.lua` files**: Become `LocalScript` objects (run on client)
- **`.server.lua` files**: Become `Script` objects (run on server)

### Key Components

**NetworkClient**: Unified interface for both mock and real server communication
**MockSystem**: Drop-in replacement for server networking during development
**ClientState**: Centralized state management with subscription system
**DevPanel**: Runtime development tools for testing and debugging

## Troubleshooting

### If UI Shows Nothing

Check these items in order:

1. **Config Settings**:
   ```lua
   Config.USE_MOCKS = true  -- For offline development
   Config.AUTO_REQUEST_PROFILE = true  -- Auto-load data
   Config.SHOW_DEV_PANEL = true  -- Show dev tools
   ```

2. **Listeners Attached**:
   ```lua
   ClientState.subscribe(function(state)
       if state.profile then
           -- Update UI here
       end
   end)
   ```

3. **Server Time Present**:
   ```lua
   local serverNow = NetworkClient.getServerNow()
   if serverNow > 0 then
       -- Server time is available
   end
   ```

4. **Mock Data Available**:
   ```lua
   if Config.USE_MOCKS then
       -- Check mock network state
       local mockProfile = MockNetwork.getCurrentProfile()
   end
   ```

### Common Issues

- **No Profile Data**: Check `AUTO_REQUEST_PROFILE` and network connectivity
- **Mock Not Working**: Verify `USE_MOCKS = true` and mock initialization
- **Dev Panel Missing**: Check `SHOW_DEV_PANEL = true` and PlayerGui permissions
- **Assets Not Loading**: Verify asset IDs in `Assets.Manifest` and fallback handling

### Recent Fixes (Today's Updates)

**File Extension Issues:**
- **Problem**: `.client.lua` files become `LocalScript` objects that can't be required
- **Solution**: Use `.lua` for modules that need to be required, `.client.lua` for execution scripts
- **Result**: All require statements now work correctly

**Path Resolution:**
- **Problem**: Incorrect relative paths between client modules
- **Solution**: Fixed all require paths to use correct folder navigation
- **Result**: No more "Utilities is not a valid member" errors

**Card Data Mismatch:**
- **Problem**: Client mock system used card IDs that don't exist on server
- **Solution**: Updated client card data to match exactly what server has
- **Result**: "Set Sample Deck" button now works without validation errors

**Data Format Consistency:**
- **Problem**: Client and server used different case for rarity/class values
- **Solution**: Standardized on lowercase values (`"common"`, `"dps"`, etc.)
- **Result**: Seamless integration between mock and real server modes

## Lootboxes UI

The lootbox system provides a complete client-side integration for managing lootbox operations, timers, and rewards. This section covers how to build lootbox UI using the provided state management and view models.

### Subscribing to Lootbox State

Use ClientState to subscribe to lootbox data changes:

```lua
local ClientState = require(script.Parent.Parent.State.ClientState)
local LootboxesVM = require(game.ReplicatedStorage.Modules.ViewModels.LootboxesVM)

-- Subscribe to state changes
ClientState.subscribe(function(state)
    if state.profile then
        -- Build lootbox view model
        local lootboxVM = LootboxesVM.build(state.profile)
        
        -- Update UI with lootbox data
        updateLootboxSlots(lootboxVM.slots)
        updatePendingLootbox(lootboxVM.pending)
        updateLootboxSummary(lootboxVM.summary)
    end
end)
```

### Building LootboxesVM

The LootboxesVM transforms raw profile data into UI-ready structures:

```lua
local LootboxesVM = require(game.ReplicatedStorage.Modules.ViewModels.LootboxesVM)

-- Build view model from profile state
local lootboxVM = LootboxesVM.build(profileState)

-- Access slot data
for i = 1, 4 do
    local slot = lootboxVM.slots[i]
    if slot.id then
        -- Slot has a lootbox
        print(string.format("Slot %d: %s %s (%s)", 
            slot.slotIndex, slot.rarity, slot.state, slot.id))
        
        -- Check capabilities
        if slot.canStart then
            print("  Can start unlocking")
        end
        if slot.canOpenNow then
            print(string.format("  Can open now for %d hard currency", slot.instantCost))
        end
        if slot.isUnlocking then
            print(string.format("  Unlocking: %d seconds remaining", slot.remaining))
        end
    else
        -- Empty slot
        print(string.format("Slot %d: Empty", slot.slotIndex))
    end
end

-- Check pending lootbox
if lootboxVM.pending then
    print(string.format("Pending: %s %s", lootboxVM.pending.rarity, lootboxVM.pending.id))
    print("Can resolve pending:", lootboxVM.canResolvePending)
end

-- Get summary statistics
local summary = lootboxVM.summary
print(string.format("Total: %d, Unlocking: %d", summary.total, summary.unlockingCount))
```

### Rendering Timers

Use `serverNow` + `unlocksAt` for accurate countdown timers without polling the server:

```lua
local function updateLootboxTimer(slot)
    if slot.state == "Unlocking" and slot.unlocksAt then
        local now = os.time() -- Use client time for UI updates
        local remaining = math.max(0, slot.unlocksAt - now)
        
        if remaining > 0 then
            -- Show countdown
            local minutes = math.floor(remaining / 60)
            local seconds = remaining % 60
            timerLabel.Text = string.format("%02d:%02d", minutes, seconds)
            
            -- Update every second
            task.wait(1)
            updateLootboxTimer(slot) -- Recursive update
        else
            -- Timer finished, lootbox is ready
            timerLabel.Text = "Ready!"
            slot.state = "ready" -- Update local state
        end
    end
end
```

### Button Enable/Disable Logic

Use VM fields to determine button states:

```lua
local function updateLootboxButtons(slot)
    -- Start unlock button
    if slot.canStart then
        startButton.Visible = true
        startButton.Active = true
        startButton.Text = "Start Unlock"
    else
        startButton.Visible = false
    end
    
    -- Open now button
    if slot.canOpenNow then
        openNowButton.Visible = true
        openNowButton.Active = true
        openNowButton.Text = string.format("Open Now (%d)", slot.instantCost)
    else
        openNowButton.Visible = false
    end
    
    -- Complete unlock button
    if slot.state == "ready" then
        completeButton.Visible = true
        completeButton.Active = true
        completeButton.Text = "Open"
    else
        completeButton.Visible = false
    end
end
```

### Network Operations

Use NetworkClient for all lootbox operations:

```lua
local NetworkClient = require(script.Parent.Parent.Controllers.NetworkClient)

-- Request lootbox state
NetworkClient.requestLootState()

-- Start unlocking a lootbox
local success, error = NetworkClient.requestStartUnlock(slotIndex)
if not success then
    print("Start unlock failed:", error)
end

-- Complete unlock (when timer finishes)
NetworkClient.requestCompleteUnlock(slotIndex)

-- Open instantly (with hard currency cost)
NetworkClient.requestOpenNow(slotIndex)

-- Handle pending lootbox overflow
NetworkClient.requestResolvePendingDiscard() -- Discard pending
NetworkClient.requestResolvePendingReplace(slotIndex) -- Replace existing slot
```

### Error Handling

Use ErrorMap for consistent error handling:

```lua
local ErrorMap = require(game.ReplicatedStorage.Modules.Utilities.ErrorMap)

-- Handle ProfileUpdated responses
NetworkClient.onProfileUpdated(function(payload)
    if payload.error then
        local userMessage = ErrorMap.toUserMessage(payload.error.code, payload.error.message)
        
        -- Show error to user
        showErrorDialog(userMessage.title, userMessage.message)
        
        -- Common lootbox error codes:
        -- BOX_CAPACITY_FULL_PENDING - Need to resolve pending lootbox
        -- BOX_DECISION_REQUIRED - Must choose discard or replace
        -- BOX_ALREADY_UNLOCKING - Another box is already unlocking
        -- BOX_BAD_STATE - Invalid operation for current state
        -- BOX_TIME_NOT_REACHED - Timer hasn't finished yet
        -- INSUFFICIENT_HARD - Not enough hard currency for instant open
    end
end)
```

### Common Flows

#### Adding a Lootbox (Dev/Test Only)

```lua
-- Only available when Config.USE_MOCKS or Config.DEBUG_LOGS is true
if Config.USE_MOCKS or Config.DEBUG_LOGS then
    NetworkClient.requestAddBox("rare", "dev_panel")
end
```

#### Overflow Resolution Flow

```lua
-- When capacity is full and a new box is awarded
if lootboxVM.canResolvePending then
    -- Show decision UI
    showOverflowDialog(function(choice)
        if choice == "discard" then
            NetworkClient.requestResolvePendingDiscard()
        elseif choice == "replace" then
            -- Let user select which slot to replace
            showSlotSelectionDialog(function(slotIndex)
                NetworkClient.requestResolvePendingReplace(slotIndex)
            end)
        end
    end)
end
```

#### Complete Lootbox Flow

```lua
-- 1. Start unlocking
NetworkClient.requestStartUnlock(slotIndex)

-- 2. Wait for timer (client-side countdown)
-- Timer updates happen automatically via LootboxesVM

-- 3. Complete when ready
if slot.state == "ready" then
    NetworkClient.requestCompleteUnlock(slotIndex)
end

-- 4. Handle rewards in ProfileUpdated
-- payload.collectionSummary contains new cards
-- payload.currencies contains updated currency amounts
```

### Hard Currency Drops

Epic and Legendary lootboxes have a chance to drop hard currency:

**Epic Lootboxes:**
- 9% chance to drop 1-29 hard currency (random amount)
- Use `SeededRNG` for deterministic results

**Legendary Lootboxes:**
- 12% chance to drop 1-77 hard currency (random amount)
- Use `SeededRNG` for deterministic results

**UI Display:**
```lua
-- Show potential hard currency drops in lootbox preview
local function updateLootboxPreview(rarity)
    if rarity == "epic" then
        previewLabel.Text = "Epic Lootbox\n9% chance for 1-29 hard currency"
    elseif rarity == "legendary" then
        previewLabel.Text = "Legendary Lootbox\n12% chance for 1-77 hard currency"
    else
        previewLabel.Text = string.format("%s Lootbox", string.upper(rarity))
    end
end
```

### Array Compaction

The lootbox array is automatically compacted after operations:

```lua
-- Before: [box1, box2, box3, box4]
-- After opening box2: [box1, box3, box4] (no holes)

-- UI should handle this by rebuilding the entire slot list
-- rather than trying to track individual slot changes
local function rebuildLootboxUI(lootboxVM)
    -- Clear all slots
    for i = 1, 4 do
        clearSlot(i)
    end
    
    -- Rebuild from compacted array
    for i = 1, #lootboxVM.slots do
        local slot = lootboxVM.slots[i]
        if slot.id then
            renderSlot(i, slot)
        end
    end
end
```

### Rate Limiting

All lootbox operations are rate-limited on the server:

```lua
-- Check if any request is in flight
if NetworkClient.isBusy() then
    print("Request in progress, please wait...")
    return
end

-- Rate limits (per endpoint):
-- RequestLootState: 1s cooldown, 10/min
-- RequestAddBox: 1s cooldown, 5/min
-- RequestResolvePending*: 1s cooldown, 10/min
-- RequestStartUnlock/CompleteUnlock/OpenNow: 1s cooldown, 10/min
```

### Testing with DevPanel

The DevPanel provides buttons for testing all lootbox operations:

1. **Enable dev panel** in Config: `Config.SHOW_DEV_PANEL = true`
2. **Use mock mode** for offline testing: `Config.USE_MOCKS = true`
3. **Test operations**:
   - "Loot: Refresh" - Get current state
   - "Loot: Add [Rarity]" - Add test lootboxes (mock only)
   - "Loot: Start Unlock (slot 1)" - Start unlocking
   - "Loot: Complete (slot 1)" - Complete unlock
   - "Loot: Open Now (slot 1)" - Instant open
   - "Loot: Resolve Pending (Discard/Replace)" - Handle overflow

### Complete Lootbox UI Example

```lua
local function createLootboxUI()
    local lootboxFrame = createLootboxFrame()
    
    -- Subscribe to state changes
    ClientState.subscribe(function(state)
        if state.profile then
            local lootboxVM = LootboxesVM.build(state.profile)
            updateLootboxUI(lootboxFrame, lootboxVM)
        end
    end)
    
    return lootboxFrame
end

local function updateLootboxUI(frame, lootboxVM)
    -- Update slots
    for i = 1, 4 do
        local slotFrame = frame:FindFirstChild("Slot" .. i)
        local slot = lootboxVM.slots[i]
        
        if slot.id then
            -- Show lootbox
            slotFrame.Visible = true
            slotFrame.RarityLabel.Text = string.upper(slot.rarity)
            slotFrame.StateLabel.Text = string.upper(slot.state)
            
            -- Update buttons
            updateSlotButtons(slotFrame, slot)
            
            -- Update timer
            if slot.isUnlocking then
                startTimer(slotFrame.TimerLabel, slot.unlocksAt)
            end
        else
            -- Hide empty slot
            slotFrame.Visible = false
        end
    end
    
    -- Update pending lootbox
    if lootboxVM.pending then
        frame.PendingFrame.Visible = true
        frame.PendingFrame.RarityLabel.Text = string.upper(lootboxVM.pending.rarity)
        
        -- Show resolution buttons
        frame.DiscardButton.Visible = true
        frame.ReplaceButton.Visible = true
    else
        frame.PendingFrame.Visible = false
        frame.DiscardButton.Visible = false
        frame.ReplaceButton.Visible = false
    end
end
```

## Deck Uniqueness and Ordering

- **Deck uniqueness**: All cards in a deck must be unique (no duplicates)
- **Slot ordering**: Cards are assigned to slots 1-6 based on their `slotNumber` in ascending order
- **Grid layout**: Use `BoardLayout.gridForDeck()` to get visual positions (row, col) for UI rendering
- **Turn order**: Fixed order 1,2,3,4,5,6 (slot 1 acts first)

## Shop UI

The shop system provides a complete client-side integration for Developer Product pack purchases and lootbox purchases with hard currency. This section covers how to build shop UI using the provided state management and purchase flows.

### ShopHandler Integration

The ShopHandler automatically binds to shop purchase buttons using naming conventions:

```lua
-- Pack buttons (expected names)
local packButtons = {
    ["S"] = "PackSButton",
    ["M"] = "PackMButton", 
    ["L"] = "PackLButton",
    ["XL"] = "PackXLButton",
    ["XXL"] = "PackXXLButton",
    ["XXXL"] = "PackXXXLButton"
}

-- Lootbox buttons (expected names)
local lootboxButtons = {
    ["uncommon"] = "LootboxUncommonButton",
    ["rare"] = "LootboxRareButton",
    ["epic"] = "LootboxEpicButton",
    ["legendary"] = "LootboxLegendaryButton"
}
```

### Pack Purchase Flow

**Mock Mode (Development):**
```lua
-- Pack purchase is immediate
local success, errorMessage = NetworkClient.requestStartPackPurchase("M")
if success then
    -- Hard currency is credited immediately
    -- ProfileUpdated fires with updated currencies
end
```

**Live Mode (Production):**
```lua
-- 1. Validate pack with server
local success, errorMessage = NetworkClient.requestStartPackPurchase("M")
if success then
    -- 2. Server returns devProductId
    -- 3. Prompt MarketplaceService
    MarketplaceService:PromptProductPurchase(player, devProductId)
    -- 4. ProcessReceipt handles the actual credit
    -- 5. ProfileUpdated fires with updated currencies
end
```

### Lootbox Error Codes

Common error codes returned by lootbox operations:

- **`BOX_DECISION_REQUIRED`**: Lootbox slots are full, player must discard or replace a lootbox
- **`BOX_NOT_UNLOCKING`**: OpenNow can only be used on lootboxes in "Unlocking" state
- **`BOX_ALREADY_UNLOCKING`**: Only one lootbox can be unlocking at a time
- **`INVALID_SLOT`**: The specified slot index is not valid (out of range)
- **`INVALID_STATE`**: The lootbox is not in the correct state for the requested action
- **`INSUFFICIENT_HARD`**: Not enough hard currency for instant open cost

### Lootbox Purchase Flow

```lua
-- Purchase lootbox with hard currency
local success, errorMessage = NetworkClient.requestBuyLootbox("rare")
if success then
    -- Hard currency deducted, lootbox added
    -- ProfileUpdated fires with updated currencies and lootboxes
    -- If capacity full, pendingLootbox is set
end
```

### Error Handling

Use ErrorMap for consistent error handling:

```lua
local ErrorMap = require(game.ReplicatedStorage.Modules.Utilities.ErrorMap)

-- Handle shop errors
if payload.error then
    local userMessage = ErrorMap.toUserMessage(payload.error.code, payload.error.message)
    
    -- Show error to user
    showErrorDialog(userMessage.title, userMessage.message)
    
    -- Common shop error codes:
    -- PACK_NOT_AVAILABLE - Pack has no devProductId
    -- INSUFFICIENT_HARD - Not enough hard currency
    -- LOOTBOX_CAPACITY_FULL - Slots full, need to resolve pending
end
```

### Loading States

Disable buttons during processing:

```lua
function ShopHandler:HandlePackPurchase(packId, button)
    -- Disable button while processing
    button.Active = false
    local originalText = button.Text
    button.Text = "Processing..."
    
    local success, errorMessage = NetworkClient.requestStartPackPurchase(packId)
    
    if not success then
        -- Show error and re-enable
        self:ShowError("Purchase Failed", errorMessage)
        button.Active = true
        button.Text = originalText
    else
        -- Show success state
        button.Text = "Purchased!"
        
        -- Re-enable after delay
        task.wait(2)
        button.Active = true
        button.Text = originalText
    end
end
```

### Currency Display

Subscribe to currency changes:

```lua
ClientState.subscribe(function(state)
    if state.profile and state.profile.currencies then
        local currencies = state.profile.currencies
        local hardCurrency = currencies.hard or 0
        local softCurrency = currencies.soft or 0
        
        -- Update UI
        hardCurrencyLabel.Text = tostring(hardCurrency)
        softCurrencyLabel.Text = tostring(softCurrency)
    end
end)
```

### Pack Availability

Check pack availability before showing purchase buttons:

```lua
-- Request shop packs
NetworkClient.requestGetShopPacks()

-- Handle response
NetworkClient.onProfileUpdated(function(payload)
    if payload.shopPacks then
        for _, pack in ipairs(payload.shopPacks) do
            local button = findPackButton(pack.id)
            if button then
                if pack.hasDevProductId then
                    button.Visible = true
                    button.Active = true
                else
                    button.Visible = false -- Pack not available
                end
            end
        end
    end
end)
```

### Lootbox Capacity Handling

Handle lootbox overflow:

```lua
ClientState.subscribe(function(state)
    if state.profile then
        local lootboxes = state.profile.lootboxes or {}
        local pendingLootbox = state.profile.pendingLootbox
        
        -- Update lootbox slots
        updateLootboxSlots(lootboxes)
        
        -- Show pending resolution UI
        if pendingLootbox then
            showPendingResolutionDialog(pendingLootbox)
        end
    end
end)
```

### Complete Shop UI Example

```lua
local function createShopUI()
    local shopFrame = createShopFrame()
    
    -- Subscribe to state changes
    ClientState.subscribe(function(state)
        if state.profile then
            -- Update currency display
            updateCurrencyDisplay(state.profile.currencies)
            
            -- Update lootbox slots
            updateLootboxSlots(state.profile.lootboxes)
            
            -- Handle pending lootbox
            if state.profile.pendingLootbox then
                showPendingResolution(state.profile.pendingLootbox)
            end
        end
    end)
    
    -- Request shop packs on open
    shopFrame.Visible = true
    NetworkClient.requestGetShopPacks()
    
    return shopFrame
end

local function updateCurrencyDisplay(currencies)
    local hardCurrency = currencies.hard or 0
    local softCurrency = currencies.soft or 0
    
    shopFrame.HardCurrencyLabel.Text = tostring(hardCurrency)
    shopFrame.SoftCurrencyLabel.Text = tostring(softCurrency)
end

local function updateLootboxSlots(lootboxes)
    for i = 1, 4 do
        local slotFrame = shopFrame:FindFirstChild("LootboxSlot" .. i)
        local lootbox = lootboxes[i]
        
        if lootbox then
            slotFrame.Visible = true
            slotFrame.RarityLabel.Text = string.upper(lootbox.rarity)
            slotFrame.StateLabel.Text = string.upper(lootbox.state)
        else
            slotFrame.Visible = false
        end
    end
end
```

### Testing with DevPanel

The DevPanel provides comprehensive shop testing:

**Available Actions:**
- **"Shop: Fetch Packs"** - Get available packs with availability flags
- **"Shop: Buy Lootbox [Rarity]"** - Purchase lootboxes with hard currency
- **"Shop: Buy Pack [S/M/L] (Mock)"** - Mock pack purchases (mock mode only)

**Status Display:**
- **Hard Currency**: Current hard currency balance
- **Soft Currency**: Current soft currency balance
- **Lootbox Slots**: Current lootbox count and unlocking status
- **Pending**: Whether there's a pending lootbox to resolve

### Production Setup

**Setting up Developer Products:**

1. **Create Products** in Roblox Creator Dashboard
2. **Get Product IDs** from the dashboard
3. **Update ShopPacksCatalog**:
   ```lua
   ["M"] = {
       id = "M", 
       hardAmount = 330,
       additionalHard = 0,  -- UI bonus display (server credits hardAmount + additionalHard)
       robuxPrice = 100,
       devProductId = 123456789 -- Real ProductId from dashboard
   }
   ```
4. **Test in Studio** with `Config.USE_MOCKS = false`
5. **Deploy to production** with real ProductIds

**Live Purchase Flow:**
1. Client calls `requestStartPackPurchase(packId)`
2. Server validates pack and returns `devProductId`
3. Client calls `MarketplaceService:PromptProductPurchase(player, devProductId)`
4. Roblox handles payment and calls `ProcessReceipt`
5. Server credits hard currency and fires `ProfileUpdated`
6. Client receives updated currencies and updates UI
