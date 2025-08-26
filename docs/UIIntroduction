# Сводная спецификация для UI

## 1) Контракты и сеть

**RemoteEvents**

* Профиль: `RequestProfile` (C→S) → **`ProfileUpdated`** (S→C).
* Дека: `RequestSetDeck` (C→S) → **`ProfileUpdated`** (S→C).
* Матч: `RequestStartMatch` (C→S) → **ответ на том же событии** (S→C, request/response без отдельного эвента).&#x20;

**Payload — `ProfileUpdated`:**

```lua
{
  deck = {string, string, string, string, string, string}, -- 6 уникальных cardId
  collectionSummary = { {cardId=string, count=number, level=number}, ... },
  loginInfo = { lastLoginAt=number, loginStreak=number },
  squadPower = number,
  lootboxes = {
    {id=string, rarity=string, state=string, acquiredAt=number, startedAt=number?, endsAt=number?},
    ...
  },
  updatedAt = number,
  serverNow = number,             -- серверное время для синхронизации таймеров
  error = {code=string, message=string}? -- только при ошибке
}
```



**Payload — ответ на `RequestStartMatch`:**

```lua
{
  ok = boolean,
  matchId = string?,
  seed = number|string?,
  result = {
    winner="A"|"B", rounds=number,
    survivorsA=number, survivorsB=number,
    totalActions=number, totalDamage=number, totalKOs=number,
    totalDefenceReduced=number
  }?,
  log = { {type=string, round=number, attackerSlot=number, defenderSlot=number, damage=number, ...}, ... }?,
  serverNow = number,
  error = {code=string, message=string}?
}
```



> Во **всех** ответах теперь есть `serverNow` — используйте его как «источник правды» для любых таймеров.&#x20;

---

## 2) Дека, слоты, сетка, порядок ходов

* **Дека**: всегда **6 уникальных** cardId (дубликаты запрещены).
* **Порядок слотов** определяется **по `slotNumber`** карты (возр.) → места 1..6.
* **Порядок ходов** фиксированный: **1,2,3,4,5,6** (первым ходит слот 1).
* **Сетка 3×2** (для отрисовки): визуально **верхний ряд 5-3-1**, **нижний 6-4-2**.
  Для разметки используйте `BoardLayout.gridForDeck(deck)` → получите `{slot,row,col,cardId}`.&#x20;

---

## 3) Общие модули (shared)

Импорт из `ReplicatedStorage.Modules.Utilities`:

```lua
local Utilities = require(ReplicatedStorage.Modules.Utilities)
local Types       = Utilities.Types
local ErrorMap    = Utilities.ErrorMap
local BoardLayout = Utilities.BoardLayout
local TimeUtils   = Utilities.TimeUtils
```

* **Types.lua** — энамы/типы (`Rarity`, `Class`, `LootboxState`, `ProfileV2`, формы payload).
* **ErrorMap.lua** — `code → {title, message}`, хелпер `toUserMessage(code, fallback?)`.
* **BoardLayout.lua** — грид 3×2, `gridForDeck`, `SLOT_ORDER()`, координаты слота.
* **TimeUtils.lua** — `nowUnix()`, длительности лутбоксов, форматтеры.&#x20;

---

## 4) Клиентский слой (из коробки)

* **NetworkClient** (`src/client/Controllers/NetworkClient.client.lua`)
  Методы: `requestProfile()`, `requestSetDeck(deckIds)`, `requestStartMatch(opts)`; события `onProfileUpdated(cb)`, `onceProfile(cb)`; `getServerNow()`; внутри — дебаунс и нормализация ошибок.&#x20;
* **ClientState** (`src/client/State/ClientState.client.lua`)
  Централизованный стор: хранит профиль (v2), `serverNow`, ошибки/флаги. `init(NetworkClient)`, `subscribe(fn)`, `getState()`.&#x20;
* **selectors.lua** — чистые селекторы: дека, коллекция списком (сортировки: `name|rarity|level|slotNumber`), валюты, лутбоксы, `serverNow`.&#x20;
* **ViewModels** (`src/shared/Modules/ViewModels/`)

  * `CardVM.build(cardId, entry?) → { id, name, rarity, class, level, stats, power, slotNumber, description }`
  * `DeckVM.build(deckIds, collection) → { slots[{slot,row,col,card}], squadPower }` (+ утилиты состава)
  * `ProfileVM.build(profile, serverNow?) → { deckVM, collectionVM, lootboxes, currencies, loginInfo, squadPower }` (+ сортировки/фильтры)&#x20;

---

## 5) Ассеты

* **Assets Manifest** (`src/shared/Modules/Assets/Manifest.lua`) + **Resolver**
  `Resolver.getCardImage(cardId)`, `getClassIcon(class)`, `getRarityFrame(rarity)`, `getRarityColor(rarity)`, `getUIColor(name)`, `getButtonColor(state)` — со стабильными фолбэками (UI не падает, если ID нет).&#x20;

---

## 6) Конфиги, моки, Dev Panel

* **Config.lua** (`src/client/Config.lua`)
  `USE_MOCKS`, `SHOW_DEV_PANEL`, `DEBUG_LOGS`, `AUTO_REQUEST_PROFILE` — флаги для дев-режима и отладки. Рекомендации: dev → `USE_MOCKS=true`, `SHOW_DEV_PANEL=true`.&#x20;
* **MockData / MockNetwork** (`src/client/Dev/`)
  Полноценный оффлайн: моковые `ProfileUpdated`/матчи, совместимы по схеме, с `serverNow`, валидацией и задержкой; значения классов/редкостей стандартизированы (lowercase) и синхронизированы с сервером. Переключение «на лету» через Dev Panel выполняет переинициализацию и сразу тянет профиль.&#x20;
* **DevPanel.client.lua** — маленькая панель (ScreenGui) с кнопками:
  **Refresh Profile**, **Set Sample Deck**, **Start PvE**, **Toggle Mocks**; статус: `serverNow`, `squadPower`, Mock ON/OFF.&#x20;

---

## 7) Быстрый старт

1. В `Config.lua` (по желанию оффлайн):

```lua
USE_MOCKS = true
SHOW_DEV_PANEL = true
AUTO_REQUEST_PROFILE = true
```

2. Bootstrap:

```lua
local NetworkClient = require(StarterPlayer.StarterPlayerScripts.Controllers.NetworkClient)
local ClientState   = require(StarterPlayer.StarterPlayerScripts.State.ClientState)
local ProfileVM     = require(ReplicatedStorage.Modules.ViewModels.ProfileVM)

ClientState.init(NetworkClient)
NetworkClient.requestProfile()

ClientState.subscribe(function(state)
  if not state.profile then return end
  local vm = ProfileVM.build(state.profile, state.serverNow)
  -- vm.deckVM.slots → для грид-рендера (row/col/slot)
  -- vm.collectionVM → список карточек с level/stats/power
  -- vm.lootboxes → используйте state.serverNow для таймеров
end)
```



3. Сменить деку (6 **уникальных** карт):

```lua
NetworkClient.requestSetDeck({ "dps_001","support_001","tank_001","dps_002","support_002","tank_002" })
```

4. Запустить бой:

```lua
NetworkClient.requestStartMatch({ mode = "PvE" })
```



---

## 8) Важные нюансы

* **serverNow** всегда присутствует → все таймеры (лутбоксы и пр.) считаем **от него**, а не от локального `os.time()`.&#x20;
* **Дека**: 6 уникальных карт; раскладка и ходовой порядок определяются **`slotNumber`** (сортировка по возрастанию) и фиксированным порядком ходов 1→6.&#x20;
* **Ошибки**: всегда пускаем через `ErrorMap.toUserMessage(code, fallback?)` — единый UX.&#x20;
* **ViewModels/Selectors** — чистые функции (без побочных эффектов), их безопасно дергать из любого UI-фреймворка.&#x20;

---

## 9) Где лежит что

* Shared: `src/shared/Modules/{Types, BoardLayout, TimeUtils, ErrorMap}`.&#x20;
* Ассеты: `src/shared/Modules/Assets/{Manifest, Resolver}`.&#x20;
* Карты/дека/статы/уровни: `src/shared/Modules/Cards/{CardCatalog, DeckValidator, CardStats, CardLevels}`.&#x20;
* VM: `src/shared/Modules/ViewModels/{CardVM, DeckVM, ProfileVM}`.&#x20;
* Клиент: `src/client/{Controllers/NetworkClient.client.lua, State/*, Dev/*, Config.lua}`.&#x20;