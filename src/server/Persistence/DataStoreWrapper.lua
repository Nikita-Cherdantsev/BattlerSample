local DataStoreWrapper = {}

-- Services
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

-- Configuration
local MAX_RETRIES = 5
local BASE_DELAY = 1 -- seconds
local MAX_DELAY = 16 -- seconds
local BUDGET_THRESHOLD = 0.8 -- 80% of budget

-- State
local pendingWrites = {}
local isShuttingDown = false

-- Utility functions
local function GenerateKey(storeName, key)
	return string.format("%s_%s", storeName, key)
end

local function LogError(storeName, key, operation, error, context)
	local errorInfo = {
		timestamp = os.time(),
		storeName = storeName,
		key = key,
		operation = operation,
		error = tostring(error),
		context = context or {}
	}
	
	warn(string.format("[DataStore Error] %s:%s %s failed: %s", 
		storeName, key, operation, tostring(error)))
	
	-- In production, you might want to log to external service
	-- For now, just print structured error info
	print("DataStore Error Details:", HttpService:JSONEncode(errorInfo))
end

local function CalculateDelay(retryCount)
	local delay = BASE_DELAY * (2 ^ retryCount)
	return math.min(delay, MAX_DELAY)
end

local function WaitForBudget(storeName)
	local success, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	
	if success and budget < BUDGET_THRESHOLD then
		-- Wait a bit for budget to recover
		task.wait(0.1)
		return true
	end
	
	return false
end

-- Public API

-- Initialize a DataStore
function DataStoreWrapper.GetDataStore(storeName)
	local success, dataStore = pcall(function()
		return DataStoreService:GetDataStore(storeName)
	end)
	
	if not success then
		error("Failed to get DataStore: " .. tostring(dataStore))
	end
	
	return dataStore
end

-- Get data with retry logic
function DataStoreWrapper.GetAsync(storeName, key, maxRetries)
	maxRetries = maxRetries or MAX_RETRIES
	local dataStore = DataStoreWrapper.GetDataStore(storeName)
	
	for retryCount = 0, maxRetries do
		local success, result = pcall(function()
			return dataStore:GetAsync(key)
		end)
		
		if success then
			return result
		end
		
		-- Check if we should retry
		if retryCount < maxRetries then
			local delay = CalculateDelay(retryCount)
			LogError(storeName, key, "GetAsync", result, {retryCount = retryCount, delay = delay})
			task.wait(delay)
		else
			LogError(storeName, key, "GetAsync", result, {retryCount = retryCount, final = true})
			error("GetAsync failed after " .. maxRetries .. " retries: " .. tostring(result))
		end
	end
end

-- Update data with retry logic
function DataStoreWrapper.UpdateAsync(storeName, key, updateFunction, maxRetries)
	maxRetries = maxRetries or MAX_RETRIES
	local dataStore = DataStoreWrapper.GetDataStore(storeName)
	
	-- Check budget before attempting
	if WaitForBudget(storeName) then
		-- Queue the write if we're near budget
		table.insert(pendingWrites, {
			storeName = storeName,
			key = key,
			updateFunction = updateFunction,
			maxRetries = maxRetries,
			timestamp = os.time()
		})
		return
	end
	
	for retryCount = 0, maxRetries do
		local success, result = pcall(function()
			return dataStore:UpdateAsync(key, updateFunction)
		end)
		
		if success then
			return result
		end
		
		-- Check if we should retry
		if retryCount < maxRetries then
			local delay = CalculateDelay(retryCount)
			LogError(storeName, key, "UpdateAsync", result, {retryCount = retryCount, delay = delay})
			task.wait(delay)
		else
			LogError(storeName, key, "UpdateAsync", result, {retryCount = retryCount, final = true})
			error("UpdateAsync failed after " .. maxRetries .. " retries: " .. tostring(result))
		end
	end
end

-- Process pending writes (called periodically or on shutdown)
function DataStoreWrapper.ProcessPendingWrites()
	if #pendingWrites == 0 then
		return
	end
	
	print("Processing", #pendingWrites, "pending DataStore writes...")
	
	local processed = 0
	local failed = 0
	
	for i = #pendingWrites, 1, -1 do
		local write = pendingWrites[i]
		
		-- Check if write is too old (older than 5 minutes)
		if os.time() - write.timestamp > 300 then
			table.remove(pendingWrites, i)
			failed = failed + 1
			LogError(write.storeName, write.key, "UpdateAsync", "Write expired", {age = os.time() - write.timestamp})
			-- Skip to next iteration
		else
			-- Check budget
			if WaitForBudget(write.storeName) then
				-- Skip to next iteration
			else
				-- Attempt the write
				local success, result = pcall(function()
					return DataStoreWrapper.UpdateAsync(write.storeName, write.key, write.updateFunction, write.maxRetries)
				end)
				
				if success then
					table.remove(pendingWrites, i)
					processed = processed + 1
				else
					failed = failed + 1
					LogError(write.storeName, write.key, "UpdateAsync", result, {pending = true})
				end
			end
		end
	end
	
	print("DataStore pending writes processed:", processed, "successful,", failed, "failed,", #pendingWrites, "remaining")
end

-- Flush all pending writes (call on shutdown)
function DataStoreWrapper.Flush()
	print("Flushing DataStore pending writes...")
	isShuttingDown = true
	
	-- Process writes until none remain or we hit a reasonable limit
	local maxAttempts = 10
	local attempts = 0
	
	while #pendingWrites > 0 and attempts < maxAttempts do
		DataStoreWrapper.ProcessPendingWrites()
		attempts = attempts + 1
		
		if #pendingWrites > 0 then
			task.wait(0.5) -- Wait before next attempt
		end
	end
	
	if #pendingWrites > 0 then
		warn("DataStore flush incomplete:", #pendingWrites, "writes remaining")
	else
		print("DataStore flush completed successfully")
	end
end

-- Get status information
function DataStoreWrapper.GetStatus()
	return {
		pendingWrites = #pendingWrites,
		isShuttingDown = isShuttingDown,
		storeName = "DataStoreWrapper"
	}
end

-- Start periodic processing of pending writes
local function StartPeriodicProcessing()
	spawn(function()
		while not isShuttingDown do
			DataStoreWrapper.ProcessPendingWrites()
			task.wait(30) -- Process every 30 seconds
		end
	end)
end

-- Auto-start periodic processing
StartPeriodicProcessing()

return DataStoreWrapper
