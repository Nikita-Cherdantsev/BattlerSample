# UI Integration Guide

This document provides the essential information for integrating the UI with the Card Battler server.

## RemoteEvents Overview

The server communicates with clients through these key RemoteEvents:

### 1. Profile Management
- **`RequestProfile`** (C→S) → **`ProfileUpdated`** (S→C)
- **`RequestSetDeck`** (C→S) → **`ProfileUpdated`** (S→C)

### 2. Match System
- **`RequestStartMatch`** (C→S) → **Response on same event** (S→C)

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
    {id = string, rarity = string, state = string, acquiredAt = number, startedAt = number?, endsAt = number?},
    -- ... more lootboxes
  },
  updatedAt = number,
  serverNow = number, -- NEW: Server timestamp for time sync
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
```

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

## Deck Uniqueness and Ordering

- **Deck uniqueness**: All cards in a deck must be unique (no duplicates)
- **Slot ordering**: Cards are assigned to slots 1-6 based on their `slotNumber` in ascending order
- **Grid layout**: Use `BoardLayout.gridForDeck()` to get visual positions (row, col) for UI rendering
- **Turn order**: Fixed order 1,2,3,4,5,6 (slot 1 acts first)
