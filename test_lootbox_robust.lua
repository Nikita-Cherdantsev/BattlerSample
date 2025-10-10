--[[
	Robust Lootbox Test Script
	Idempotent and state-aware test for lootbox flows
	Run this in Studio Client console
]]

local RS = game:GetService("ReplicatedStorage")
local Net = RS:WaitForChild("Network")

print("== Robust Lootbox Test ==")

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
    clear    = function() Net.RequestClearLoot:FireServer({}) end,
}

-- Helper functions (globally available)
_G.findSlotByState = function(state)
    local p = _G.lastLootPayload or {}
    for i, box in ipairs(p.lootboxes or {}) do
        if box.state == state then
            return i
        end
    end
    return nil
end

_G.dumpLoot = function()
    local p = _G.lastLootPayload or {}
    print("=== Current Loot State ===")
    print("Lootboxes:", #(p.lootboxes or {}))
    print("Pending:", p.pendingLootbox and "YES" or "NO")
    for i, box in ipairs(p.lootboxes or {}) do
        print(("  Slot %d: %s %s"):format(i, box.rarity, box.state))
    end
    if p.pendingLootbox then
        print(("  Pending: %s %s"):format(p.pendingLootbox.rarity, p.pendingLootbox.state or "N/A"))
    end
    if p.currencies then
        print(("  currencies: soft=%d hard=%d"):format(p.currencies.soft or 0, p.currencies.hard or 0))
    end
    if p.collectionSummary and #p.collectionSummary > 0 then
        for _, card in ipairs(p.collectionSummary) do
            print(("  card %s  count=%d  level=%d"):format(card.cardId, card.count, card.level))
        end
    end
end

-- Helper to inspect lootbox drops manually
_G.inspectDrops = function()
    print("=== Lootbox Drop Inspector ===")
    
    -- Get current state
    _G.Loot.state()
    if not waitForUpdate(3) then
        warn("Failed to get current state")
        return
    end
    
    local p = _G.lastLootPayload
    print("Current state:")
    _G.dumpLoot()
    
    -- Find an Idle slot
    local idleSlot = _G.findSlotByState("Idle")
    if not idleSlot then
        warn("No Idle slot found for drop inspection")
        return
    end
    
    print(("\nFound Idle slot %d, testing drops..."):format(idleSlot))
    
    -- Capture initial state
    local initialSoft = p.currencies and p.currencies.soft or 0
    local initialHard = p.currencies and p.currencies.hard or 0
    local initialCollection = p.collectionSummary or {}
    
    print(("Initial: soft=%d, hard=%d, cards=%d"):format(initialSoft, initialHard, #initialCollection))
    
    -- Start unlock
    _G.Loot.start(idleSlot)
    if not waitForUpdate(3) then
        warn("Failed to start unlock")
        return
    end
    
    local startP = _G.lastLootPayload
    if startP.error then
        warn("Start unlock failed:", startP.error.code)
        return
    end
    
    print("✅ Unlock started, opening now...")
    
    -- Open now
    _G.Loot.openNow(idleSlot)
    if not waitForUpdate(3) then
        warn("Failed to open now")
        return
    end
    
    local finalP = _G.lastLootPayload
    if finalP.error then
        warn("OpenNow failed:", finalP.error.code)
        return
    end
    
    -- Show results
    local finalSoft = finalP.currencies and finalP.currencies.soft or 0
    local finalHard = finalP.currencies and finalP.currencies.hard or 0
    local finalCollection = finalP.collectionSummary or {}
    
    print(("Final: soft=%d, hard=%d, cards=%d"):format(finalSoft, finalHard, #finalCollection))
    
    local softGained = finalSoft - initialSoft
    local hardSpent = initialHard - finalHard
    local cardsGained = #finalCollection - #initialCollection
    
    print(("\n🎁 DROP RESULTS:"):format())
    print(("  Soft currency: +%d"):format(softGained))
    print(("  Hard currency: -%d"):format(hardSpent))
    print(("  Cards gained: +%d"):format(cardsGained))
    
    if cardsGained > 0 then
        print("  New cards:")
        for _, card in ipairs(finalCollection) do
            local wasInInitial = false
            for _, initialCard in ipairs(initialCollection) do
                if initialCard.cardId == card.cardId then
                    wasInInitial = true
                    local countIncrease = card.count - initialCard.count
                    if countIncrease > 0 then
                        print(("    - %s: +%d (now %d total)"):format(card.cardId, countIncrease, card.count))
                    end
                    break
                end
            end
            if not wasInInitial then
                print(("    - %s: NEW CARD! (count=%d, level=%d)"):format(card.cardId, card.count, card.level))
            end
        end
    end
    
    print("✅ Drop inspection complete!")
end

-- Wait for profile update
local function waitForUpdate(timeout)
    timeout = timeout or 5
    local start = tick()
    local lastPayload = _G.lastLootPayload
    
    while tick() - start < timeout do
        -- Check if we got a new payload (different from what we started with)
        if _G.lastLootPayload and _G.lastLootPayload ~= lastPayload then
            return true
        end
        task.wait(0.1)
    end
    return false
end

-- Wait for rate limit cooldown
local function waitForRateLimit()
    print("⏳ Waiting 15 seconds to avoid rate limits...")
    task.wait(15) -- Wait 15 seconds to avoid minute rate limits (5 requests/minute = 12s between requests)
    print("✅ Rate limit cooldown complete")
end

-- Ensure clean state
local function ensureCleanState()
    print("\n=== Ensuring Clean State ===")
    
    -- First, get current state
    _G.Loot.state()
    if not waitForUpdate(3) then
        warn("Failed to get initial state")
        return false
    end
    
    local p = _G.lastLootPayload
    local lootCount = #(p.lootboxes or {})
    
    -- If we have loot or pending, clear it
    if lootCount > 0 or p.pendingLootbox then
        print("Clearing existing loot and pending...")
        _G.Loot.clear()
        if not waitForUpdate(3) then
            warn("Failed to clear loot")
            return false
        end
        
        -- Wait for the clear response
        if not waitForUpdate(3) then
            warn("Failed to get clear loot response")
            return false
        end
        
        -- Get the new payload after clear
        local newP = _G.lastLootPayload
        print(("  Clear response: loot=%d, pending=%s, error=%s"):format(
            #(newP.lootboxes or {}), 
            newP.pendingLootbox and "YES" or "NO",
            newP.error and newP.error.code or "none"
        ))
        
        if newP.error then
            warn("Clear loot failed:", newP.error.code, newP.error.message)
            if newP.error.code == "FORBIDDEN" then
                warn("RequestClearLoot is not available - this is a dev-only endpoint")
                return false
            end
            if newP.error.code == "RATE_LIMITED" then
                print("Rate limited, waiting and retrying...")
                waitForRateLimit()
                _G.Loot.clear()
                if not waitForUpdate(3) then
                    warn("Failed to clear loot on retry")
                    return false
                end
                newP = _G.lastLootPayload
                if newP.error then
                    warn("Clear loot still failed after retry:", newP.error.code)
                    return false
                end
            else
                return false
            end
        end
        
        if newP.pendingLootbox or #(newP.lootboxes or {}) > 0 then
            warn("Clear loot did not work properly - still have loot or pending")
            print("Current state after clear:")
            _G.dumpLoot()
            return false
        end
        
        print("✅ Loot cleared successfully")
    else
        print("✅ Already in clean state")
    end
    
    -- Final state check
    _G.Loot.state()
    if not waitForUpdate(3) then
        warn("Failed to get final state")
        return false
    end
    
    local finalP = _G.lastLootPayload
    if finalP.pendingLootbox or #(finalP.lootboxes or {}) > 0 then
        warn("Final state check failed - still have loot or pending")
        return false
    end
    
    print("✅ Clean state ensured")
    return true
end

-- Fill to exactly 4 slots
local function fillToFourSlots()
    print("\n=== Filling to 4 Slots ===")
    
    local p = _G.lastLootPayload
    local currentCount = #(p.lootboxes or {})
    
    if currentCount >= 4 then
        print("Already have 4+ slots, clearing first")
        _G.Loot.clear()
        if not waitForUpdate(3) then
            warn("Failed to clear loot")
            return false
        end
        currentCount = 0
    end
    
    local rarities = {"uncommon", "rare", "epic", "legendary"}
    local attempts = 0
    local maxAttempts = 20
    
    while currentCount < 4 and attempts < maxAttempts do
        attempts = attempts + 1
        local rarity = rarities[((attempts - 1) % #rarities) + 1]
        
        print(("Adding box %d (attempt %d): %s"):format(currentCount + 1, attempts, rarity))
        _G.Loot.add(rarity)
        
        if not waitForUpdate(3) then
            warn("Failed to get response for add box")
            return false
        end
        
        -- Get the new payload after add box
        local newP = _G.lastLootPayload
        local newCount = #(newP.lootboxes or {})
        
        -- Debug: Show what we got
        print(("  Add box response: loot=%d, pending=%s, error=%s"):format(
            newCount, 
            newP.pendingLootbox and "YES" or "NO",
            newP.error and newP.error.code or "none"
        ))
        
        -- Add delay between ALL requests to avoid rate limiting
        waitForRateLimit()
        
        if newP.error then
            -- Handle specific errors
            if newP.error.code == "RATE_LIMITED" then
                print("⚠️  Rate limited, waiting and retrying...")
                waitForRateLimit()
                -- Retry the add
                _G.Loot.add(rarity)
                if not waitForUpdate(3) then
                    warn("Failed to get retry response for add box")
                    return false
                end
                newP = _G.lastLootPayload
                if newP.error and newP.error.code == "RATE_LIMITED" then
                    print("⚠️  Still rate limited, waiting longer...")
                    waitForRateLimit()
                    _G.Loot.add(rarity)
                    if not waitForUpdate(3) then
                        warn("Failed to get second retry response for add box")
                        return false
                    end
                    newP = _G.lastLootPayload
                    if newP.error then
                        warn("❌ Add box still failed after second retry:", newP.error.code)
                        return false
                    end
                elseif newP.error then
                    warn("❌ Add box still failed after retry:", newP.error.code)
                    return false
                end
                -- Continue with the retry result
                newCount = #(newP.lootboxes or {})
                print(("  Retry response: loot=%d, pending=%s"):format(
                    newCount, 
                    newP.pendingLootbox and "YES" or "NO"
                ))
            else
                warn("❌ Add box failed:", newP.error.code, newP.error.message or "")
                return false
            end
        end
        
        if newCount > currentCount then
            -- Successfully added
            currentCount = newCount
            print("✅ Added successfully, now have " .. currentCount .. " slots")
        elseif newP.pendingLootbox then
            -- Pending box created, discard it and retry
            print("⚠️  Pending box created, discarding and retrying...")
            _G.Loot.discard()
            if not waitForUpdate(3) then
                warn("Failed to discard pending")
                return false
            end
        else
            -- Some other error
            warn("❌ Add box failed: unknown error")
            return false
        end
    end
    
    if currentCount < 4 then
        warn("Failed to reach 4 slots after " .. maxAttempts .. " attempts")
        return false
    end
    
    print("✅ Successfully filled to 4 slots")
    return true
end

-- Test overflow behavior
local function testOverflow()
    print("\n=== Testing Overflow ===")
    
    waitForRateLimit() -- Ensure we're not rate limited
    _G.Loot.add("epic")
    if not waitForUpdate(3) then
        warn("Failed to get overflow response")
        return false
    end
    
    local p = _G.lastLootPayload
    if p.error and p.error.code == "BOX_DECISION_REQUIRED" and p.pendingLootbox then
        print("✅ Overflow correctly returned BOX_DECISION_REQUIRED with pending=YES")
        return true
    else
        warn("❌ Overflow failed:", p.error and p.error.code or "no error", "pending:", p.pendingLootbox and "YES" or "NO")
        return false
    end
end

-- Test discard pending
local function testDiscardPending()
    print("\n=== Testing Discard Pending ===")
    
    waitForRateLimit() -- Ensure we're not rate limited
    _G.Loot.discard()
    if not waitForUpdate(3) then
        warn("Failed to get discard response")
        return false
    end
    
    local p = _G.lastLootPayload
    if not p.error and not p.pendingLootbox and #(p.lootboxes or {}) == 4 then
        print("✅ Discard pending succeeded: pending=NO, 4 slots intact")
        return true
    else
        warn("❌ Discard pending failed:", p.error and p.error.code or "unknown", "pending:", p.pendingLootbox and "YES" or "NO")
        return false
    end
end

-- Test replace pending
local function testReplacePending()
    print("\n=== Testing Replace Pending ===")
    
    -- Create pending again
    waitForRateLimit() -- Ensure we're not rate limited
    _G.Loot.add("legendary")
    if not waitForUpdate(3) then
        warn("Failed to create pending")
        return false
    end
    
    local p = _G.lastLootPayload
    if p.error and p.error.code == "RATE_LIMITED" then
        print("⚠️  Rate limited on add, waiting and retrying...")
        waitForRateLimit()
        _G.Loot.add("legendary")
        if not waitForUpdate(3) then
            warn("Failed to create pending on retry")
            return false
        end
        p = _G.lastLootPayload
        if p.error and p.error.code == "RATE_LIMITED" then
            print("⚠️  Still rate limited, waiting longer...")
            waitForRateLimit()
            _G.Loot.add("legendary")
            if not waitForUpdate(3) then
                warn("Failed to create pending on second retry")
                return false
            end
            p = _G.lastLootPayload
        end
    end
    
    if not p.pendingLootbox then
        warn("Failed to create pending box")
        return false
    end
    
    -- Replace slot 1
    waitForRateLimit() -- Ensure we're not rate limited
    _G.Loot.replace(1)
    if not waitForUpdate(3) then
        warn("Failed to get replace response")
        return false
    end
    
    local newP = _G.lastLootPayload
    if not newP.error and not newP.pendingLootbox and #(newP.lootboxes or {}) == 4 then
        local slot1 = newP.lootboxes[1]
        if slot1 and slot1.rarity == "legendary" and slot1.state == "Idle" then
            print("✅ Replace pending succeeded: slot 1 replaced with legendary Idle box")
            return true
        else
            warn("❌ Slot 1 not properly replaced")
            return false
        end
    else
        warn("❌ Replace pending failed:", newP.error and newP.error.code or "unknown")
        return false
    end
end

-- Test OpenNow on Idle (should fail)
local function testOpenNowOnIdle()
    print("\n=== Testing OpenNow on Idle (should fail) ===")
    
    local idleSlot = _G.findSlotByState("Idle")
    if not idleSlot then
        warn("No Idle slot found")
        return false
    end
    
    print("Trying OpenNow on Idle slot " .. idleSlot)
    waitForRateLimit() -- Ensure we're not rate limited
    _G.Loot.openNow(idleSlot)
    if not waitForUpdate(3) then
        warn("Failed to get OpenNow response")
        return false
    end
    
    local p = _G.lastLootPayload
    if p.error and p.error.code == "BOX_NOT_UNLOCKING" then
        print("✅ OpenNow on Idle correctly returned BOX_NOT_UNLOCKING")
        return true
    else
        warn("❌ OpenNow on Idle failed:", p.error and p.error.code or "no error")
        return false
    end
end

-- Test Start -> OpenNow flow
local function testStartToOpenNow()
    print("\n=== Testing Start -> OpenNow Flow ===")
    
    local idleSlot = _G.findSlotByState("Idle")
    if not idleSlot then
        warn("No Idle slot found")
        return false
    end
    
    print("Starting unlock on slot " .. idleSlot)
    waitForRateLimit() -- Ensure we're not rate limited
    _G.Loot.start(idleSlot)
    if not waitForUpdate(3) then
        warn("Failed to get start unlock response")
        return false
    end
    
    local p = _G.lastLootPayload
    if p.error then
        warn("❌ Start unlock failed:", p.error.code)
        return false
    end
    
    local box = p.lootboxes[idleSlot]
    if not box or box.state ~= "Unlocking" then
        warn("❌ Box not in Unlocking state after start")
        return false
    end
    
    print("✅ Box is now Unlocking, trying OpenNow")
    waitForRateLimit() -- Ensure we're not rate limited
    _G.Loot.openNow(idleSlot)
    if not waitForUpdate(3) then
        warn("Failed to get OpenNow response")
        return false
    end
    
    local newP = _G.lastLootPayload
    if not newP.error and #(newP.lootboxes or {}) == 3 then
        print("✅ OpenNow succeeded: box removed, array compacted")
        return true
    else
        warn("❌ OpenNow failed:", newP.error and newP.error.code or "unknown")
        return false
    end
end

-- Sanity check after clear
local function sanityCheckAfterClear()
    print("\n=== Sanity Check After Clear ===")
    
    _G.Loot.state()
    if not waitForUpdate(3) then
        warn("Failed to get state for sanity check")
        return false
    end
    
    local p = _G.lastLootPayload
    local lootCount = #(p.lootboxes or {})
    
    if lootCount ~= 0 then
        warn("❌ Expected 0 lootboxes, got " .. lootCount)
        return false
    end
    
    if p.pendingLootbox then
        warn("❌ Expected no pending lootbox, but found one")
        return false
    end
    
    print("✅ Sanity check passed: 0 lootboxes, no pending")
    _G.dumpLoot()
    return true
end

-- Test lootbox drops and rewards
local function testLootboxDrops()
    print("\n=== Testing Lootbox Drops ===")
    
    -- Get initial currency state
    _G.Loot.state()
    if not waitForUpdate(3) then
        warn("Failed to get initial state for drop test")
        return false
    end
    
    local initialP = _G.lastLootPayload
    local initialSoft = initialP.currencies and initialP.currencies.soft or 0
    local initialHard = initialP.currencies and initialP.currencies.hard or 0
    local initialCollection = initialP.collectionSummary or {}
    
    print(("Initial currencies: soft=%d, hard=%d"):format(initialSoft, initialHard))
    print(("Initial collection: %d cards"):format(#initialCollection))
    
    -- Find an Idle slot
    local idleSlot = _G.findSlotByState("Idle")
    if not idleSlot then
        warn("No Idle slot found for drop test")
        return false
    end
    
    print("Testing drops on slot " .. idleSlot)
    
    -- Start unlock
    waitForRateLimit()
    _G.Loot.start(idleSlot)
    if not waitForUpdate(3) then
        warn("Failed to start unlock for drop test")
        return false
    end
    
    local startP = _G.lastLootPayload
    if startP.error then
        warn("❌ Start unlock failed for drop test:", startP.error.code)
        return false
    end
    
    -- Open now to get rewards
    waitForRateLimit()
    _G.Loot.openNow(idleSlot)
    if not waitForUpdate(3) then
        warn("Failed to open now for drop test")
        return false
    end
    
    local finalP = _G.lastLootPayload
    if finalP.error then
        warn("❌ OpenNow failed for drop test:", finalP.error.code)
        return false
    end
    
    -- Check if rewards were granted
    local finalSoft = finalP.currencies and finalP.currencies.soft or 0
    local finalHard = finalP.currencies and finalP.currencies.hard or 0
    local finalCollection = finalP.collectionSummary or {}
    
    print(("Final currencies: soft=%d, hard=%d"):format(finalSoft, finalHard))
    print(("Final collection: %d cards"):format(#finalCollection))
    
    local softGained = finalSoft - initialSoft
    local hardSpent = initialHard - finalHard
    local cardsGained = #finalCollection - #initialCollection
    
    print(("Rewards: +%d soft currency, -%d hard currency, +%d cards"):format(softGained, hardSpent, cardsGained))
    
    -- Verify rewards were granted
    if softGained <= 0 then
        warn("❌ No soft currency gained from lootbox")
        return false
    end
    
    if hardSpent <= 0 then
        warn("❌ No hard currency spent for instant open")
        return false
    end
    
    if cardsGained <= 0 then
        warn("❌ No cards gained from lootbox")
        return false
    end
    
    print("✅ Lootbox drops working correctly:")
    
    -- Show detailed card information
    print("  Collection details:")
    for _, card in ipairs(finalCollection) do
        print(("    - %s: count=%d, level=%d"):format(card.cardId, card.count, card.level))
    end
    
    -- Show what was actually gained
    print("  Rewards breakdown:")
    print(("    - Soft currency: +%d (from %d to %d)"):format(softGained, initialSoft, finalSoft))
    print(("    - Hard currency: -%d (from %d to %d)"):format(hardSpent, initialHard, finalHard))
    print(("    - Cards gained: +%d (from %d to %d cards)"):format(cardsGained, #initialCollection, #finalCollection))
    
    -- Show new cards specifically
    if cardsGained > 0 then
        print("  New cards added:")
        for _, card in ipairs(finalCollection) do
            local wasInInitial = false
            for _, initialCard in ipairs(initialCollection) do
                if initialCard.cardId == card.cardId then
                    wasInInitial = true
                    local countIncrease = card.count - initialCard.count
                    if countIncrease > 0 then
                        print(("    - %s: +%d (now %d total)"):format(card.cardId, countIncrease, card.count))
                    end
                    break
                end
            end
            if not wasInInitial then
                print(("    - %s: NEW CARD! (count=%d, level=%d)"):format(card.cardId, card.count, card.level))
            end
        end
    end
    
    return true
end

-- Main test runner
local function runTests()
    print("Starting robust lootbox tests...")
    
    -- Wait a bit to avoid rate limiting from previous runs
    print("Waiting for rate limit cooldown...")
    waitForRateLimit()
    
    -- Ensure clean state
    if not ensureCleanState() then
        warn("Failed to ensure clean state, aborting")
        return
    end
    
    -- Sanity check after clear
    if not sanityCheckAfterClear() then
        warn("Sanity check failed, aborting")
        return
    end
    
    -- Fill to 4 slots
    if not fillToFourSlots() then
        warn("Failed to fill to 4 slots, aborting")
        return
    end
    
    -- Test overflow
    if not testOverflow() then
        warn("Overflow test failed")
        return
    end
    
    -- Test discard pending
    if not testDiscardPending() then
        warn("Discard pending test failed")
        return
    end
    
    -- Test replace pending
    if not testReplacePending() then
        warn("Replace pending test failed")
        return
    end
    
    -- Test OpenNow on Idle (should fail)
    if not testOpenNowOnIdle() then
        warn("OpenNow on Idle test failed")
        return
    end
    
    -- Test Start -> OpenNow flow
    if not testStartToOpenNow() then
        warn("Start -> OpenNow test failed")
        return
    end
    
    -- Test lootbox drops
    if not testLootboxDrops() then
        warn("Lootbox drops test failed")
        return
    end
    
    print("\n🎉 All tests passed!")
    _G.dumpLoot()
end

-- Module exports
local M = {}

function M.run()
    runTests()
end

-- Run tests automatically when loaded
runTests()

print("\n== Test Complete ==")
    print("Helper functions available:")
    print("  _G.dumpLoot() - show current loot state")
    print("  _G.findSlotByState('Idle') - find slot by state")
    print("  _G.inspectDrops() - manually test lootbox drops and see rewards")
    print("  _G.Loot.* - all lootbox operations")

return M
