-- Logger utility for structured, debug-flag controlled logging
local Logger = {}

-- Debug flag - set to true to enable debug logs
local DEBUG_ENABLED = false

-- Enable debug logging (call this from dev harnesses or when needed)
function Logger.EnableDebug()
	DEBUG_ENABLED = true
end

-- Disable debug logging
function Logger.DisableDebug()
	DEBUG_ENABLED = false
end

-- Check if debug logging is enabled
function Logger.IsDebugEnabled()
	return DEBUG_ENABLED
end

-- Debug log (only prints if DEBUG_ENABLED is true)
function Logger.debug(message, ...)
	if DEBUG_ENABLED then
		local formattedMessage = string.format(message, ...)
		print(string.format("[DEBUG] %s", formattedMessage))
	end
end

-- Info log (always prints)
function Logger.info(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("[INFO] %s", formattedMessage))
end

-- Warning log (always prints)
function Logger.warn(message, ...)
	local formattedMessage = string.format(message, ...)
	warn(string.format("[WARN] %s", formattedMessage))
end

-- Error log (always prints)
function Logger.error(message, ...)
	local formattedMessage = string.format(message, ...)
	error(string.format("[ERROR] %s", formattedMessage))
end

-- Structured log for shop purchases
function Logger.shopPurchase(userId, packId, hardBefore, hardAdded, hardAfter)
	if DEBUG_ENABLED then
		print(string.format("SHOP_PURCHASE user=%s pack=%s hardBefore=%d add=%d hardAfter=%d", 
			tostring(userId), packId, hardBefore, hardAdded, hardAfter))
	end
end

-- Structured log for lootbox events
function Logger.lootAdd(userId, rarity, overflow, slotCount)
	if DEBUG_ENABLED then
		print(string.format("LOOT_ADD user=%s rarity=%s overflow=%s slots=%d", 
			tostring(userId), rarity, tostring(overflow), slotCount))
	end
end

function Logger.lootStart(userId, slot, rarity, startTime, unlocksAt, remainSec)
	if DEBUG_ENABLED then
		print(string.format("LOOT_START user=%s slot=%d rarity=%s start=%d unlocksAt=%d remain=%d", 
			tostring(userId), slot, rarity, startTime, unlocksAt, remainSec))
	end
end

function Logger.lootOpenNow(userId, slot, cost, remainBefore, rewards)
	if DEBUG_ENABLED then
		local summary = Logger.formatRewards(rewards)
		print(string.format("LOOT_OPEN_NOW user=%s slot=%d cost=%d remainBefore=%d rewards=%s", 
			tostring(userId), slot, cost, remainBefore, summary))
	end
end

function Logger.lootComplete(userId, slot, rewards)
	if DEBUG_ENABLED then
		local summary = Logger.formatRewards(rewards)
		print(string.format("LOOT_COMPLETE user=%s slot=%d rewards=%s", 
			tostring(userId), slot, summary))
	end
end

function Logger.lootPending(userId, action, slot)
	if DEBUG_ENABLED then
		local slotStr = slot and tostring(slot) or "none"
		print(string.format("LOOT_PENDING_%s user=%s slot=%s", 
			string.upper(action), tostring(userId), slotStr))
	end
end

function Logger.lootState(userId, slotCount, unlockingSlot, remainSec, hasPending)
	if DEBUG_ENABLED then
		local unlockingStr = unlockingSlot and tostring(unlockingSlot) or "none"
		print(string.format("LOOT_STATE user=%s slots=%d unlocking=%s remain=%d pending=%s", 
			tostring(userId), slotCount, unlockingStr, remainSec, tostring(hasPending)))
	end
end

-- Helper to format rewards summary
function Logger.formatRewards(rewards)
	if not rewards then return "none" end
	
	local parts = {}
	
	if rewards.softDelta and rewards.softDelta > 0 then
		table.insert(parts, string.format("soft=%d", rewards.softDelta))
	end
	
	if rewards.hardDelta and rewards.hardDelta > 0 then
		table.insert(parts, string.format("hard=%d", rewards.hardDelta))
	end
	
	if rewards.cards and #rewards.cards > 0 then
		local cardCounts = {}
		for _, card in ipairs(rewards.cards) do
			cardCounts[card] = (cardCounts[card] or 0) + 1
		end
		
		local cardParts = {}
		for cardId, count in pairs(cardCounts) do
			table.insert(cardParts, string.format("%dx%s", count, cardId))
		end
		table.insert(parts, string.format("cards=%s", table.concat(cardParts, ",")))
	end
	
	return table.concat(parts, " ")
end

return Logger
