--[[
	Final test script for lootbox fixes
	Run this in Studio Client console to test all the fixes
]]

local RS = game:GetService("ReplicatedStorage")
local Net = RS:WaitForChild("Network")

print("== Testing Lootbox Fixes Final ==")

-- Setup
_G.lastLootPayload = nil
if _G._profUpdCon then _G._profUpdCon:Disconnect() end
_G._profUpdCon = Net.ProfileUpdated.OnClientEvent:Connect(function(p)
    _G.lastLootPayload = p
    local lootCount = (p.lootboxes and #p.lootboxes) or 0
    print(("[ProfileUpdated] serverNow=%s | loot=%d | pending=%s")
        :format(tostring(p.serverNow), lootCount, p.pendingLootbox and "YES" or "NO"))
    if p.currencies then
        print(("  currencies: soft=%s hard=%s"):format(p.currencies.soft, p.currencies.hard))
    end
    if p.collectionSummary then
        for _,e in ipairs(p.collectionSummary) do
            print(("  card %s  count=%s  level=%s"):format(e.cardId, e.count, e.level))
        end
    end
    if p.error then
        warn("  ERROR:", p.error.code, p.error.message or "")
    end
end)

-- Test functions
_G.Loot = {
    state    = function() Net.RequestLootState:FireServer({}) end,
    add      = function(r) Net.RequestAddBox:FireServer({ rarity = r, source = "console_test" }) end,
    discard  = function() Net.RequestResolvePendingDiscard:FireServer({}) end,
    replace  = function(i) Net.RequestResolvePendingReplace:FireServer({ slotIndex = i }) end,
    start    = function(i) Net.RequestStartUnlock:FireServer({ slotIndex = i }) end,
    openNow  = function(i) Net.RequestOpenNow:FireServer({ slotIndex = i }) end,
    complete = function(i) Net.RequestCompleteUnlock:FireServer({ slotIndex = i }) end,
}

print("Setup done. Testing the fixes...")

-- Test 1: Fill to capacity
print("\n=== Test 1: Fill to capacity ===")
_G.Loot.state()
task.wait(1)

for i = 1, 4 do
    print("Adding box " .. i)
    _G.Loot.add("epic")
    task.wait(1)
end

-- Test 2: Add 5th box (should go to pending with BOX_DECISION_REQUIRED)
print("\n=== Test 2: Add 5th box (overflow) ===")
_G.Loot.add("rare")
task.wait(1)

-- Test 3: Discard pending
print("\n=== Test 3: Discard pending ===")
_G.Loot.discard()
task.wait(1)

-- Test 4: Add 5th box again and replace
print("\n=== Test 4: Add 5th box and replace ===")
_G.Loot.add("legendary")
task.wait(1)

-- Find an idle slot (using correct casing)
local function findIdleSlot()
    local p = _G.lastLootPayload or {}
    for i, box in ipairs(p.lootboxes or {}) do
        if box.state == "Idle" then
            return i
        end
    end
    return nil
end

local idleSlot = findIdleSlot()
print("Idle slot found:", idleSlot)

if idleSlot then
    print("Replacing slot " .. idleSlot)
    _G.Loot.replace(idleSlot)
    task.wait(1)
end

-- Test 5: Try OpenNow on Idle (should fail with BOX_NOT_UNLOCKING)
print("\n=== Test 5: Try OpenNow on Idle (should fail) ===")
local idleSlot2 = findIdleSlot()
print("Idle slot for open test:", idleSlot2)

if idleSlot2 then
    print("Trying OpenNow on Idle slot " .. idleSlot2 .. " (should fail)")
    _G.Loot.openNow(idleSlot2)
    task.wait(1)
end

-- Test 6: Start unlock then OpenNow (should work)
print("\n=== Test 6: Start unlock then OpenNow ===")
local idleSlot3 = findIdleSlot()
print("Idle slot for start unlock:", idleSlot3)

if idleSlot3 then
    print("Starting unlock on slot " .. idleSlot3)
    _G.Loot.start(idleSlot3)
    task.wait(1)
    
    print("Opening slot " .. idleSlot3 .. " instantly")
    _G.Loot.openNow(idleSlot3)
    task.wait(1)
end

-- Test 7: Try to start unlock on another slot while one is unlocking (should fail)
print("\n=== Test 7: Try second start unlock (should fail) ===")
_G.Loot.state()
task.wait(1)

local idleSlot4 = findIdleSlot()
if idleSlot4 then
    print("Trying to start unlock on slot " .. idleSlot4 .. " while another is unlocking (should fail)")
    _G.Loot.start(idleSlot4)
    task.wait(1)
end

print("\n== Test Complete ==")
print("Expected results:")
print("- No INTERNAL errors or 'attempt to call a nil value' errors")
print("- BOX_DECISION_REQUIRED for 5th box overflow")
print("- BOX_NOT_UNLOCKING for OpenNow on Idle")
print("- BOX_ALREADY_UNLOCKING for second start unlock")
print("- All operations should succeed with proper error codes")
print("- Idle slots should be found correctly with TitleCase state strings")
