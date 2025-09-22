--[[
	Test script for RequestAddBox functionality
	Run this in Studio Client console to test the fix
]]

local RS = game:GetService("ReplicatedStorage")
local Net = RS:WaitForChild("Network")

print("== Testing RequestAddBox Fix ==")

-- Setup
_G.lastLootPayload = nil
if _G._profUpdCon then _G._profUpdCon:Disconnect() end
_G._profUpdCon = Net.ProfileUpdated.OnClientEvent:Connect(function(p)
    _G.lastLootPayload = p
    local lootCount = (p.lootboxes and #p.lootboxes) or 0
    print(("[ProfileUpdated] serverNow=%s | loot=%d | pending=%s")
        :format(tostring(p.serverNow), lootCount, p.pendingLootbox and "YES" or "NO"))
    if p.currencies then
        print("  currencies:", "soft=", p.currencies.soft, "hard=", p.currencies.hard)
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
    add      = function(rarity) Net.RequestAddBox:FireServer({ rarity = rarity, source = "console_test" }) end,
    discard  = function() Net.RequestResolvePendingDiscard:FireServer({}) end,
    replace  = function(slot) Net.RequestResolvePendingReplace:FireServer({ slotIndex = slot }) end,
    start    = function(slot) Net.RequestStartUnlock:FireServer({ slotIndex = slot }) end,
    openNow  = function(slot) Net.RequestOpenNow:FireServer({ slotIndex = slot }) end,
    complete = function(slot) Net.RequestCompleteUnlock:FireServer({ slotIndex = slot }) end,
}

print("Setup done. Use _G.Loot.state(), _G.Loot.add('epic'), etc.")
print("Testing case-insensitive rarity handling...")

-- Test cases
local function testCase(name, rarity, shouldSucceed)
    print(string.format("\n--- Testing %s: %s (should %s) ---", name, rarity, shouldSucceed and "succeed" or "fail"))
    _G.Loot.add(rarity)
    task.wait(1) -- Wait for response
    
    if _G.lastLootPayload then
        local hasError = _G.lastLootPayload.error ~= nil
        local success = not hasError
        
        if success == shouldSucceed then
            print(string.format("✅ %s: %s", name, success and "PASSED" or "FAILED as expected"))
        else
            print(string.format("❌ %s: Expected %s, got %s", name, shouldSucceed and "success" or "failure", success and "success" or "failure"))
            if hasError then
                print("  Error:", _G.lastLootPayload.error.code, _G.lastLootPayload.error.message)
            end
        end
    else
        print(string.format("❌ %s: No response received", name))
    end
end

-- Run tests
_G.Loot.state()
task.wait(1)

testCase("Epic (lowercase)", "epic", true)
testCase("Rare (uppercase)", "RARE", true)
testCase("Uncommon (mixed case)", "Uncommon", true)
testCase("Legendary (lowercase)", "legendary", true)
testCase("Invalid rarity", "common", false)
testCase("Invalid rarity (uppercase)", "COMMON", false)
testCase("Invalid rarity (mixed)", "Common", false)

print("\n== Test Complete ==")
