--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

--// Modules
local NetworkClient = require(game.StarterPlayer.StarterPlayerScripts.Controllers.NetworkClient)

--// Module
local LootboxUIHandler = {}

--// State
LootboxUIHandler.Connections = {}
LootboxUIHandler._initialized = false
LootboxUIHandler.currentProfile = nil
LootboxUIHandler.lootboxPacks = {} -- Store references to Pack1, Pack2, Pack3, Pack4
LootboxUIHandler.timerConnections = {} -- Store timer update connections

-- Configuration
LootboxUIHandler.SPEED_UP_COST = 0 -- Hard currency cost for speed up (temporary for testing)

--// Initialization
function LootboxUIHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	
	-- Safe require of Utilities to avoid loading errors
	local success, utilities = pcall(function()
		return controller:GetModule("Utilities")
	end)
	
	if success then
		self.Utilities = utilities
	else
		warn("LootboxUIHandler: Could not load Utilities module: " .. tostring(utilities))
		self.Utilities = {
			TweenUI = { FadeIn = function() end, FadeOut = function() end },
			Blur = { Show = function() end, Hide = function() end }
		}
	end
	
	-- Initialize state
	self.Connections = {}
	self.timerConnections = {}
	self.currentProfile = nil
	self.lootboxPacks = {}
	self._updatingStates = false -- Prevent infinite loops

	-- Setup Lootbox UI
	self:SetupLootboxUI()

	self._initialized = true
	print("✅ LootboxUIHandler initialized successfully!")
	return true
end

function LootboxUIHandler:SetupLootboxUI()
	-- Access UI from player's PlayerGui
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	print("LootboxUIHandler: Looking for UI in PlayerGui...")
	
	-- Wait for GameUI
	local gameGui = playerGui:WaitForChild("GameUI", 5) -- Initial wait
	
	if not gameGui then
		print("LootboxUIHandler: GameUI not found initially, waiting longer...")
		gameGui = playerGui:WaitForChild("GameUI", 10) -- Extended wait
		
		if not gameGui then
			warn("LootboxUIHandler: GameUI not found in PlayerGui after extended waiting")
			return
		end
	end
	
	print("LootboxUIHandler: Found GameUI: " .. tostring(gameGui))
	
	-- Find the lootbox packs container
	-- Path: GameUI -> BottomPanel -> Packs -> Outline -> Content
	local bottomPanel = gameGui:FindFirstChild("BottomPanel")
	if not bottomPanel then
		warn("LootboxUIHandler: BottomPanel not found")
		return
	end
	
	local packs = bottomPanel:FindFirstChild("Packs")
	if not packs then
		warn("LootboxUIHandler: Packs not found")
		return
	end
	
	local outline = packs:FindFirstChild("Outline")
	if not outline then
		warn("LootboxUIHandler: Outline not found")
		return
	end
	
	local content = outline:FindFirstChild("Content")
	if not content then
		warn("LootboxUIHandler: Content not found")
		return
	end
	
	print("LootboxUIHandler: Found lootbox packs container")
	
	-- Store UI reference
	self.UI = gameGui
	self.LootboxContainer = content
	
	-- Setup each lootbox pack (Pack1, Pack2, Pack3, Pack4)
	self:SetupLootboxPacks()
	
	-- Setup ProfileUpdated event handler
	self:SetupProfileUpdatedHandler()
	
	print("✅ LootboxUIHandler: Lootbox UI setup completed")
end

function LootboxUIHandler:SetupLootboxPacks()
	-- Setup Pack1, Pack2, Pack3, Pack4
	for i = 1, 4 do
		local packName = "Pack" .. i
		local packFrame = self.LootboxContainer:FindFirstChild(packName)
		
		if packFrame then
			print("LootboxUIHandler: Found " .. packName)
			
			-- Store pack reference (slot index matches pack number 1-4)
			self.lootboxPacks[i] = {
				frame = packFrame,
				slotIndex = i,
				btnUnlock = packFrame:FindFirstChild("BtnUnlock"),
				btnOpen = packFrame:FindFirstChild("BtnOpen"),
				btnSpeedUp = packFrame:FindFirstChild("BtnSpeedUp"),
				lockedFrame = packFrame:FindFirstChild("Locked"),
				timerFrame = packFrame:FindFirstChild("Timer"),
				timerText = nil
			}
			
			-- Find timer text
			if self.lootboxPacks[i].timerFrame then
				local background = self.lootboxPacks[i].timerFrame:FindFirstChild("Background")
				if background then
					self.lootboxPacks[i].timerText = background:FindFirstChild("TxtValue")
				end
			end
			
			-- Setup button click handlers
			self:SetupPackButtons(i)
		else
			warn("LootboxUIHandler: " .. packName .. " not found")
		end
	end
end

function LootboxUIHandler:SetupPackButtons(packIndex)
	local pack = self.lootboxPacks[packIndex]
	if not pack then return end
	
	-- Setup BtnUnlock
	if pack.btnUnlock and pack.btnUnlock:IsA("TextButton") then
		local connection = pack.btnUnlock.MouseButton1Click:Connect(function()
			self:OnUnlockButtonClicked(packIndex)
		end)
		table.insert(self.Connections, connection)
		print("LootboxUIHandler: BtnUnlock connected for Pack" .. packIndex)
	end
	
	-- Setup BtnOpen
	if pack.btnOpen and pack.btnOpen:IsA("TextButton") then
		local connection = pack.btnOpen.MouseButton1Click:Connect(function()
			self:OnOpenButtonClicked(packIndex)
		end)
		table.insert(self.Connections, connection)
		print("LootboxUIHandler: BtnOpen connected for Pack" .. packIndex)
	end
	
	-- Setup BtnSpeedUp
	if pack.btnSpeedUp and pack.btnSpeedUp:IsA("TextButton") then
		local connection = pack.btnSpeedUp.MouseButton1Click:Connect(function()
			self:OnSpeedUpButtonClicked(packIndex)
		end)
		table.insert(self.Connections, connection)
		print("LootboxUIHandler: BtnSpeedUp connected for Pack" .. packIndex)
	end
end

-- Button click handlers
function LootboxUIHandler:OnUnlockButtonClicked(packIndex)
	local pack = self.lootboxPacks[packIndex]
	if not pack then return end
	
	print("LootboxUIHandler: Unlock button clicked for Pack" .. packIndex .. " (slot " .. pack.slotIndex .. ")")
	
	-- Check current lootbox state before attempting unlock
	local currentLootbox = self.currentProfile and self.currentProfile.lootboxes and self.currentProfile.lootboxes[pack.slotIndex]
	if currentLootbox then
		print("LootboxUIHandler: Current lootbox state for slot " .. pack.slotIndex .. ": " .. tostring(currentLootbox.state))
		if currentLootbox.state ~= "Idle" then
			warn("LootboxUIHandler: Cannot start unlock - lootbox is in state: " .. tostring(currentLootbox.state))
			return
		end
	else
		print("LootboxUIHandler: No lootbox found in slot " .. pack.slotIndex)
		print("LootboxUIHandler: Note: You need to add a lootbox to this slot first before unlocking")
		return -- Don't try to unlock empty slots
	end
	
	-- Call backend to start unlock
	if NetworkClient and NetworkClient.requestStartUnlock then
		local success, error = NetworkClient.requestStartUnlock(pack.slotIndex)
		if success then
			print("LootboxUIHandler: Start unlock request sent successfully")
		else
			warn("LootboxUIHandler: Start unlock request failed:", error)
		end
	else
		warn("LootboxUIHandler: NetworkClient.requestStartUnlock not available")
	end
end

function LootboxUIHandler:OnOpenButtonClicked(packIndex)
	local pack = self.lootboxPacks[packIndex]
	if not pack then return end
	
	print("LootboxUIHandler: Open button clicked for Pack" .. packIndex .. " (slot " .. pack.slotIndex .. ")")
	
	-- Call backend to open lootbox
	if NetworkClient and NetworkClient.requestOpenNow then
		local success, error = NetworkClient.requestOpenNow(pack.slotIndex)
		if success then
			print("LootboxUIHandler: Open now request sent successfully")
		else
			warn("LootboxUIHandler: Open now request failed:", error)
		end
	else
		warn("LootboxUIHandler: NetworkClient.requestOpenNow not available")
	end
end

function LootboxUIHandler:OnSpeedUpButtonClicked(packIndex)
	local pack = self.lootboxPacks[packIndex]
	if not pack then return end
	
	print("LootboxUIHandler: SpeedUp button clicked for Pack" .. packIndex .. " (slot " .. pack.slotIndex .. ")")
	
	-- Check if player has enough hard currency
	if self.currentProfile and self.currentProfile.currencies then
		local hardCurrency = self.currentProfile.currencies.hard or 0
		if hardCurrency >= self.SPEED_UP_COST then
			-- Call backend to speed up (open now)
			if NetworkClient and NetworkClient.requestOpenNow then
				local success, error = NetworkClient.requestOpenNow(pack.slotIndex)
				if success then
					print("LootboxUIHandler: Speed up request sent successfully")
				else
					warn("LootboxUIHandler: Speed up request failed:", error)
				end
			else
				warn("LootboxUIHandler: NetworkClient.requestOpenNow not available")
			end
		else
			print("LootboxUIHandler: Not enough hard currency for speed up. Need: " .. self.SPEED_UP_COST .. ", Have: " .. hardCurrency)
			-- TODO: Show UI message to top up currency
		end
	else
		warn("LootboxUIHandler: Profile or currencies not available")
	end
end

-- Update lootbox UI state
function LootboxUIHandler:UpdateLootboxStates()
	if not self.currentProfile or not self.currentProfile.lootboxes then
		print("LootboxUIHandler: No profile or lootboxes data available")
		return
	end
	
	-- Prevent infinite loops by checking if we're already updating
	if self._updatingStates then
		print("LootboxUIHandler: Already updating states, skipping to prevent loop")
		return
	end
	
	self._updatingStates = true
	
	local lootboxes = self.currentProfile.lootboxes
	local pendingLootbox = self.currentProfile.pendingLootbox
	
	print("LootboxUIHandler: Updating lootbox states...")
	print("LootboxUIHandler: Current lootboxes:")
	for i, lootbox in ipairs(lootboxes) do
		if lootbox then
			local hasLootbox = lootbox.state and (
				(lootbox.state == "Idle" and lootbox.unlocksAt) or
				(lootbox.state == "Unlocking" and lootbox.unlocksAt) or
				(lootbox.state == "Ready") or
				(lootbox.state == "Consumed")
			)
			if hasLootbox then
				print("  Slot " .. i .. ": HAS LOOTBOX - state=" .. tostring(lootbox.state) .. ", unlocksAt=" .. tostring(lootbox.unlocksAt))
			else
				print("  Slot " .. i .. ": NO LOOTBOX - state=" .. tostring(lootbox.state) .. ", unlocksAt=" .. tostring(lootbox.unlocksAt))
			end
		else
			print("  Slot " .. i .. ": empty")
		end
	end
	print("LootboxUIHandler: Pending lootbox:", pendingLootbox ~= nil)
	
	-- First, check if any lootbox is currently unlocking (timer not completed)
	local isAnyUnlocking = false
	for i, lootbox in ipairs(lootboxes) do
		-- Only consider slots that actually have lootboxes
		local hasLootbox = lootbox and lootbox.state and (
			(lootbox.state == "Idle" and lootbox.unlocksAt) or
			(lootbox.state == "Unlocking" and lootbox.unlocksAt) or
			(lootbox.state == "Ready") or
			(lootbox.state == "Consumed")
		)
		
		if hasLootbox and lootbox.state == "Unlocking" and lootbox.unlocksAt and lootbox.unlocksAt > os.time() then
			isAnyUnlocking = true
			break
		end
	end
	
	print("LootboxUIHandler: Any lootbox unlocking:", isAnyUnlocking)
	
	-- Update each pack
	for packIndex = 1, 4 do
		local pack = self.lootboxPacks[packIndex]
		if pack then
			local slotIndex = pack.slotIndex
			local lootbox = lootboxes[slotIndex] -- slotIndex is 1-4, lootboxes array is 1-indexed
			
			-- Check if this slot actually has a lootbox
			-- A lootbox exists if it has valid state AND unlocksAt timestamp (for Idle/Unlocking/Ready)
			local hasLootbox = lootbox and lootbox.state and (
				(lootbox.state == "Idle" and lootbox.unlocksAt) or
				(lootbox.state == "Unlocking" and lootbox.unlocksAt) or
				(lootbox.state == "Ready") or
				(lootbox.state == "Consumed")
			)
			
			if hasLootbox then
				-- This slot has a real lootbox
				if lootbox.state == "Unlocking" then
					-- Check if timer has completed
					if lootbox.unlocksAt and lootbox.unlocksAt <= os.time() then
						-- Timer completed, lootbox is ready to open
						self:UpdatePackState(packIndex, "Ready", lootbox)
					else
						-- Still unlocking, show SpeedUp state
						self:UpdatePackState(packIndex, "Unlocking", lootbox)
					end
				-- If any other lootbox is unlocking, lock this one
				elseif isAnyUnlocking then
					self:UpdatePackState(packIndex, "Locked", nil)
				-- Otherwise, show normal state
				else
					self:UpdatePackState(packIndex, lootbox.state, lootbox)
				end
			else
				-- No lootbox in this slot - show appropriate state
				if isAnyUnlocking then
					-- If any lootbox is unlocking, show locked state for empty slots
					self:UpdatePackState(packIndex, "Locked", nil)
				else
					-- No lootboxes unlocking, show empty state (no buttons)
					self:UpdatePackState(packIndex, "Empty", nil)
				end
			end
		end
	end
	
	-- Handle pending lootbox (if any) - this is separate from regular lootboxes
	if pendingLootbox then
		print("LootboxUIHandler: Pending lootbox detected, this is a separate pending state")
		-- Pending lootbox doesn't affect the regular pack states
	end
	
	-- Clear the updating flag to allow future updates
	self._updatingStates = false
end

function LootboxUIHandler:UpdatePackState(packIndex, state, lootboxData)
	local pack = self.lootboxPacks[packIndex]
	if not pack then return end
	
	print("LootboxUIHandler: Updating Pack" .. packIndex .. " to state: " .. tostring(state))
	if lootboxData then
		print("  - Lootbox data: state=" .. tostring(lootboxData.state) .. ", unlocksAt=" .. tostring(lootboxData.unlocksAt))
	end
	
	-- Hide all buttons and frames first
	if pack.btnUnlock then pack.btnUnlock.Visible = false end
	if pack.btnOpen then pack.btnOpen.Visible = false end
	if pack.btnSpeedUp then pack.btnSpeedUp.Visible = false end
	if pack.lockedFrame then pack.lockedFrame.Visible = false end
	if pack.timerFrame then pack.timerFrame.Visible = false end
	
	-- Show appropriate UI based on state
	if state == "Idle" then
		-- Show unlock button
		if pack.btnUnlock then
			pack.btnUnlock.Visible = true
			pack.btnUnlock.Active = true
		end
		print("LootboxUIHandler: Showing Unlock button for Pack" .. packIndex)
		
	elseif state == "Unlocking" then
		-- Show speed up button and timer
		if pack.btnSpeedUp then
			pack.btnSpeedUp.Visible = true
			pack.btnSpeedUp.Active = true
		end
		if pack.timerFrame then
			pack.timerFrame.Visible = true
			self:StartTimer(packIndex, lootboxData)
		end
		print("LootboxUIHandler: Showing SpeedUp button for Pack" .. packIndex)
		
	elseif state == "Ready" then
		-- Show open button
		if pack.btnOpen then
			pack.btnOpen.Visible = true
			pack.btnOpen.Active = true
		end
		print("LootboxUIHandler: Showing Open button for Pack" .. packIndex)
		
	elseif state == "Locked" then
		-- Show locked frame
		if pack.lockedFrame then
			pack.lockedFrame.Visible = true
		end
		print("LootboxUIHandler: Showing Locked frame for Pack" .. packIndex)
		
	elseif state == "Empty" then
		-- Empty slots show nothing - no buttons, no interaction
		-- Players can only get lootboxes through the shop or other means
		print("LootboxUIHandler: Showing empty state for Pack" .. packIndex .. " (no lootbox)")
	end
end

-- Timer management
function LootboxUIHandler:StartTimer(packIndex, lootboxData)
	if not lootboxData or not lootboxData.unlocksAt then return end
	
	local pack = self.lootboxPacks[packIndex]
	if not pack or not pack.timerText then return end
	
	-- Stop existing timer for this pack
	self:StopTimer(packIndex)
	
	local unlocksAt = lootboxData.unlocksAt
	local connection
	
	local function updateTimer()
		local currentTime = os.time()
		local remainingTime = math.max(0, unlocksAt - currentTime)
		
		if remainingTime <= 0 then
			-- Timer finished, lootbox is ready
			pack.timerText.Text = "Ready!"
			self:StopTimer(packIndex)
			
			-- Request fresh profile data from server to get updated lootbox state
			print("LootboxUIHandler: Timer completed, requesting fresh profile data...")
			if NetworkClient and NetworkClient.requestProfile then
				NetworkClient.requestProfile()
			end
			
			-- Don't call UpdateLootboxStates here - it will be called automatically
			-- when the ProfileUpdated event fires from the server response
			return
		end
		
		-- Format time as MM:SS
		local minutes = math.floor(remainingTime / 60)
		local seconds = remainingTime % 60
		pack.timerText.Text = string.format("%02d:%02d", minutes, seconds)
	end
	
	-- Update immediately
	updateTimer()
	
	-- Update every second
	connection = game:GetService("RunService").Heartbeat:Connect(function()
		updateTimer()
	end)
	
	-- Store connection for cleanup
	self.timerConnections[packIndex] = connection
end

function LootboxUIHandler:StopTimer(packIndex)
	local connection = self.timerConnections[packIndex]
	if connection then
		connection:Disconnect()
		self.timerConnections[packIndex] = nil
	end
end

function LootboxUIHandler:StopAllTimers()
	for packIndex = 1, 4 do
		self:StopTimer(packIndex)
	end
end

function LootboxUIHandler:SetupProfileUpdatedHandler()
	-- Listen for ProfileUpdated events
	local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
	
	local connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
		if not payload.error then
			print("LootboxUIHandler: Received profile update")
			
			-- Initialize profile if not exists
			if not self.currentProfile then
				self.currentProfile = {
					lootboxes = {},
					pendingLootbox = nil,
					currencies = { soft = 0, hard = 0 }
				}
			end
			
			-- Update lootboxes
			if payload.lootboxes then
				self.currentProfile.lootboxes = payload.lootboxes
			end
			
			-- Update pending lootbox
			if payload.pendingLootbox then
				self.currentProfile.pendingLootbox = payload.pendingLootbox
			else
				self.currentProfile.pendingLootbox = nil
			end
			
			-- Update currencies
			if payload.currencies then
				self.currentProfile.currencies = payload.currencies
			end
			
			-- Update UI
			self:UpdateLootboxStates()
		else
			print("LootboxUIHandler: Received profile error:", payload.error.message or payload.error.code)
		end
	end)
	
	-- Store connection for cleanup
	table.insert(self.Connections, connection)
end

-- Public Methods
function LootboxUIHandler:IsInitialized()
	return self._initialized
end

-- Debug function to manually refresh lootbox states
function LootboxUIHandler:DebugRefreshStates()
	print("LootboxUIHandler: Manual state refresh requested")
	print("Current profile exists:", self.currentProfile ~= nil)
	if self.currentProfile then
		print("Lootboxes count:", #(self.currentProfile.lootboxes or {}))
		print("Pending lootbox:", self.currentProfile.pendingLootbox ~= nil)
	end
	
	-- Request fresh profile data
	if NetworkClient and NetworkClient.requestProfile then
		NetworkClient.requestProfile()
		print("Profile refresh requested")
	else
		print("NetworkClient.requestProfile not available")
	end
	
	-- Also trigger immediate UI update
	self:UpdateLootboxStates()
end

-- Debug function to clear all lootboxes (for testing)
function LootboxUIHandler:DebugClearLootboxes()
	print("LootboxUIHandler: Clearing all lootboxes for testing...")
	if NetworkClient and NetworkClient.requestClearLoot then
		local success, error = NetworkClient.requestClearLoot()
		if success then
			print("LootboxUIHandler: Clear loot request sent successfully")
			-- Wait a moment and then refresh UI
			task.wait(1)
			self:UpdateLootboxStates()
		else
			warn("LootboxUIHandler: Clear loot request failed:", error)
		end
	else
		warn("LootboxUIHandler: NetworkClient.requestClearLoot not available")
	end
end

-- Debug function to show current UI state vs lootbox states
function LootboxUIHandler:DebugShowUIState()
	print("LootboxUIHandler: Current UI State vs Lootbox States:")
	
	if not self.currentProfile or not self.currentProfile.lootboxes then
		print("  No profile or lootboxes available")
		return
	end
	
	for packIndex = 1, 4 do
		local pack = self.lootboxPacks[packIndex]
		if pack then
			local slotIndex = pack.slotIndex
			local lootbox = self.currentProfile.lootboxes[slotIndex]
			
			print("  Pack" .. packIndex .. " (slot " .. slotIndex .. "):")
			if lootbox then
				print("    Lootbox state: " .. tostring(lootbox.state))
			else
				print("    Lootbox state: empty")
			end
			
			-- Show what buttons are currently visible
			local visibleButtons = {}
			if pack.btnUnlock and pack.btnUnlock.Visible then table.insert(visibleButtons, "Unlock") end
			if pack.btnOpen and pack.btnOpen.Visible then table.insert(visibleButtons, "Open") end
			if pack.btnSpeedUp and pack.btnSpeedUp.Visible then table.insert(visibleButtons, "SpeedUp") end
			if pack.lockedFrame and pack.lockedFrame.Visible then table.insert(visibleButtons, "Locked") end
			
			if #visibleButtons > 0 then
				print("    UI showing: " .. table.concat(visibleButtons, ", "))
			else
				print("    UI showing: nothing")
			end
		end
	end
end

-- Cleanup
function LootboxUIHandler:Cleanup()
	print("Cleaning up LootboxUIHandler...")
	
	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}
	
	-- Stop all timers
	self:StopAllTimers()
	
	self._initialized = false
	print("✅ LootboxUIHandler cleaned up")
end

return LootboxUIHandler
