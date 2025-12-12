--[[
	EventBus - Centralized event system for client-side handlers
	
	Provides a simple pub/sub event system for decoupling components.
	Allows handlers to emit events when windows open/close or buttons are clicked,
	and TutorialHandler can subscribe to these events instead of polling.
]]

local EventBus = {}

-- Internal event storage: { eventName -> { callbacks... } }
EventBus._events = {}

-- Subscribe to an event
-- @param eventName: string - Name of the event (e.g., "WindowOpened", "ButtonClicked")
-- @param callback: function - Callback function to call when event fires
-- @return: function - Disconnect function
function EventBus:On(eventName, callback)
	if not eventName or type(eventName) ~= "string" then
		warn("EventBus:On - Invalid eventName:", eventName)
		return function() end
	end
	
	if not callback or type(callback) ~= "function" then
		warn("EventBus:On - Invalid callback for event:", eventName)
		return function() end
	end
	
	if not self._events[eventName] then
		self._events[eventName] = {}
	end
	
	table.insert(self._events[eventName], callback)
	
	-- Return disconnect function
	return function()
		if self._events[eventName] then
			for i, cb in ipairs(self._events[eventName]) do
				if cb == callback then
					table.remove(self._events[eventName], i)
					break
				end
			end
			
			-- Clean up empty event arrays
			if #self._events[eventName] == 0 then
				self._events[eventName] = nil
			end
		end
	end
end

-- Emit an event
-- @param eventName: string - Name of the event
-- @param ...: any - Arguments to pass to callbacks
function EventBus:Emit(eventName, ...)
	if not eventName or type(eventName) ~= "string" then
		warn("EventBus:Emit - Invalid eventName:", eventName)
		return
	end
	
	if self._events[eventName] then
		for _, callback in ipairs(self._events[eventName]) do
			local success, err = pcall(callback, ...)
			if not success then
				warn("EventBus:Emit - Error in callback for event", eventName, ":", err)
			end
		end
	end
end

-- Unsubscribe from an event (alternative to using disconnect function)
-- @param eventName: string - Name of the event
-- @param callback: function - Callback to remove
function EventBus:Off(eventName, callback)
	if not self._events[eventName] then
		return
	end
	
	for i, cb in ipairs(self._events[eventName]) do
		if cb == callback then
			table.remove(self._events[eventName], i)
			break
		end
	end
	
	-- Clean up empty event arrays
	if #self._events[eventName] == 0 then
		self._events[eventName] = nil
	end
end

-- Clear all listeners for an event
-- @param eventName: string - Name of the event (optional, clears all if nil)
function EventBus:Clear(eventName)
	if eventName then
		self._events[eventName] = nil
	else
		-- Clear all events
		self._events = {}
	end
end

-- Get count of listeners for an event (for debugging)
-- @param eventName: string - Name of the event
-- @return: number - Count of listeners
function EventBus:GetListenerCount(eventName)
	if not self._events[eventName] then
		return 0
	end
	return #self._events[eventName]
end

return EventBus
