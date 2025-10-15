--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

--// Modules
local NetworkClient = require(game.StarterPlayer.StarterPlayerScripts.Controllers.NetworkClient)
local Manifest = require(ReplicatedStorage.Modules.Assets.Manifest)

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
	self.LootboxOpening = {}
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
	
	-- Wait for GameUI
	local gameGui = playerGui:WaitForChild("GameUI", 5) -- Initial wait
	
	if not gameGui then
		gameGui = playerGui:WaitForChild("GameUI", 10) -- Extended wait
		
		if not gameGui then
			warn("LootboxUIHandler: GameUI not found in PlayerGui after extended waiting")
			return
		end
	end
	
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
	
	-- Store UI reference
	self.UI = gameGui
	self.LootboxContainer = content
	self.LootboxOpening.Main = gameGui:FindFirstChild("LootboxOpening")
	
	-- Store lootbox opening UI references in organized structure
	self.LootboxOpening.Lootbox = self.LootboxOpening.Main:WaitForChild("Lootbox")
	self.LootboxOpening.Effect = self.LootboxOpening.Lootbox:WaitForChild("Effect")
	self.LootboxOpening.Card = self.LootboxOpening.Main:WaitForChild("Card")
	self.LootboxOpening.FirstEffect = self.LootboxOpening.Effect:WaitForChild("1")
	self.LootboxOpening.Currencies = self.LootboxOpening.Main:WaitForChild("Currencies")
	self.LootboxOpening.Currency1 = self.LootboxOpening.Currencies:WaitForChild("Currency1")
	self.LootboxOpening.Currency2 = self.LootboxOpening.Currencies:WaitForChild("Currency2")
	self.LootboxOpening.BtnClaim = self.LootboxOpening.Main:WaitForChild("BtnClaim")
	
	-- Setup each lootbox pack (Pack1, Pack2, Pack3, Pack4)
	self:SetupLootboxPacks()
	
	-- Setup ProfileUpdated event handler
	self:SetupProfileUpdatedHandler()
	
	-- Setup claim button handler
	self:SetupClaimButtonHandler()
	
	print("✅ LootboxUIHandler: Lootbox UI setup completed")
end

function LootboxUIHandler:SetupLootboxPacks()
	-- Setup Pack1, Pack2, Pack3, Pack4
	for i = 1, 4 do
		local packName = "Pack" .. i
		local packFrame = self.LootboxContainer:FindFirstChild(packName)
		
		if packFrame then
			
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
	end
	
	-- Setup BtnOpen
	if pack.btnOpen and pack.btnOpen:IsA("TextButton") then
		local connection = pack.btnOpen.MouseButton1Click:Connect(function()
			self:OnOpenButtonClicked(packIndex)
		end)
		table.insert(self.Connections, connection)
	end
	
	-- Setup BtnSpeedUp
	if pack.btnSpeedUp and pack.btnSpeedUp:IsA("TextButton") then
		local connection = pack.btnSpeedUp.MouseButton1Click:Connect(function()
			self:OnSpeedUpButtonClicked(packIndex)
		end)
		table.insert(self.Connections, connection)
	end
end

-- Button click handlers
function LootboxUIHandler:OnUnlockButtonClicked(packIndex)
	local pack = self.lootboxPacks[packIndex]
	if not pack then return end
	
	-- Check current lootbox state before attempting unlock
	local currentLootbox = self.currentProfile and self.currentProfile.lootboxes and self.currentProfile.lootboxes[pack.slotIndex]
	if not currentLootbox or currentLootbox.state ~= "Idle" then
		return -- Can only unlock Idle lootboxes
	end
	
	-- Request unlock from server
	if NetworkClient and NetworkClient.requestStartUnlock then
		NetworkClient.requestStartUnlock(pack.slotIndex)
	end
end

function LootboxUIHandler:OnOpenButtonClicked(packIndex)
	local pack = self.lootboxPacks[packIndex]
	if not pack then return end
	
	-- Request to open lootbox from server
	if NetworkClient and NetworkClient.requestOpenNow then
		NetworkClient.requestOpenNow(pack.slotIndex)
	end
end

function LootboxUIHandler:OnSpeedUpButtonClicked(packIndex)
	local pack = self.lootboxPacks[packIndex]
	if not pack then return end
	
	
	-- Check if player has enough hard currency
	if self.currentProfile and self.currentProfile.currencies then
		local hardCurrency = self.currentProfile.currencies.hard or 0
		if hardCurrency >= self.SPEED_UP_COST then
			-- Call backend to speed up (complete timer)
			if NetworkClient and NetworkClient.requestSpeedUp then
				local success, error = NetworkClient.requestSpeedUp(pack.slotIndex)
				if success then
				else
					warn("LootboxUIHandler: Speed up request failed:", error)
				end
			else
				warn("LootboxUIHandler: NetworkClient.requestOpenNow not available")
			end
		else
			-- TODO: Show UI message to top up currency
		end
	else
		warn("LootboxUIHandler: Profile or currencies not available")
	end
end

-- Update lootbox UI state
function LootboxUIHandler:UpdateLootboxStates()
	if not self.currentProfile or not self.currentProfile.lootboxes then
		return
	end
	
	-- Prevent infinite loops by checking if we're already updating
	if self._updatingStates then
		return
	end
	
	self._updatingStates = true
	
	local lootboxes = self.currentProfile.lootboxes
	local pendingLootbox = self.currentProfile.pendingLootbox
	
	-- Update lootbox UI based on current player data
	
	-- First, check if any lootbox is currently unlocking (timer not completed)
	local isAnyUnlocking = false
	for i, lootbox in ipairs(lootboxes) do
		-- Check if this lootbox is actively unlocking (has timer that hasn't completed)
		if lootbox and lootbox.state == "Unlocking" and lootbox.unlocksAt and lootbox.unlocksAt > os.time() then
			isAnyUnlocking = true
			break
		end
	end
	
	
	-- Update each pack
	for packIndex = 1, 4 do
		local pack = self.lootboxPacks[packIndex]
		if pack then
			local slotIndex = pack.slotIndex
			local lootbox = lootboxes[slotIndex] -- slotIndex is 1-4, lootboxes array is 1-indexed
			
			-- Check if this slot actually has a lootbox
			-- A lootbox exists if it has a valid state
			local hasLootbox = lootbox and lootbox.state and (
				lootbox.state == "Idle" or
				lootbox.state == "Unlocking" or
				lootbox.state == "Ready" or
				lootbox.state == "Consumed"
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
				-- If any other lootbox is unlocking, lock only Idle lootboxes
				elseif isAnyUnlocking and lootbox.state == "Idle" then
					self:UpdatePackState(packIndex, "Locked", nil)
				-- Otherwise, show normal state
				else
					self:UpdatePackState(packIndex, lootbox.state, lootbox)
				end
			else
				-- No lootbox in this slot - always show empty state
				self:UpdatePackState(packIndex, "Empty", nil)
			end
		end
	end
	
	-- Handle pending lootbox (if any) - this is separate from regular lootboxes
	if pendingLootbox then
		-- Pending lootbox doesn't affect the regular pack states
	end
	
	-- Clear the updating flag to allow future updates
	self._updatingStates = false
end

function LootboxUIHandler:UpdatePackState(packIndex, state, lootboxData)
	local pack = self.lootboxPacks[packIndex]
	if not pack then return end
	
	-- Update pack state
	
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
		
	elseif state == "Ready" then
		-- Show open button
		if pack.btnOpen then
			pack.btnOpen.Visible = true
			pack.btnOpen.Active = true
		end
		
	elseif state == "Locked" then
		-- Show locked frame
		if pack.lockedFrame then
			pack.lockedFrame.Visible = true
		end
		
	elseif state == "Empty" then
		-- Empty slots show nothing - no buttons, no interaction
		-- Players can only get lootboxes through the shop or other means
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
			
			-- Show rewards if any
			if payload.rewards then
				local rewardCount = 0
				if payload.rewards.softDelta and payload.rewards.softDelta > 0 then
					rewardCount = rewardCount + 1
					print("🎁 [LootboxUIHandler] Soft currency reward:", payload.rewards.softDelta)
				end
				if payload.rewards.hardDelta and payload.rewards.hardDelta > 0 then
					rewardCount = rewardCount + 1
					print("🎁 [LootboxUIHandler] Hard currency reward:", payload.rewards.hardDelta)
				end
				if payload.rewards.card then
					rewardCount = rewardCount + 1
					print("🎁 [LootboxUIHandler] Card reward:", payload.rewards.card.cardId, "x" .. payload.rewards.card.copies)
				end
				print("🎁 [LootboxUIHandler] Total rewards received:", rewardCount, "items")
				
				-- Open lootbox UI with rewards (for shop purchases)
				self:OpenLootbox(payload.rewards)
			end
			
			-- Update UI
			self:UpdateLootboxStates()
		else
		end
	end)
	
	-- Store connection for cleanup
	table.insert(self.Connections, connection)
end

function LootboxUIHandler:SetupClaimButtonHandler()
	-- Setup BtnClaim click handler
	if self.LootboxOpening.BtnClaim and self.LootboxOpening.BtnClaim:IsA("TextButton") then
		local connection = self.LootboxOpening.BtnClaim.MouseButton1Click:Connect(function()
			self:OnClaimButtonClicked()
		end)
		table.insert(self.Connections, connection)
	end
end

-- Claim button click handler
function LootboxUIHandler:OnClaimButtonClicked()
	-- Hide LootboxOpening with TweenUI.FadeOut
	if self.LootboxOpening.Main then
		if self.Utilities and self.Utilities.TweenUI then
			self.Utilities.TweenUI.FadeOut(self.LootboxOpening.Main, 0.3, function()
				self.LootboxOpening.Main.Visible = false
			end)
		else
			-- Fallback: no animation
			self.LootboxOpening.Main.Visible = false
		end
	end
end

local fadeInTime = 0.5
local fadeOutTime = 0.3
local effectDelay = 0.05
local cardTweenTime = 1
local angle = 5

-- Reset lootbox state
function LootboxUIHandler:ResetLootboxAnimationState(rewards)
	self.LootboxOpening.Main.Visible = true
	self.LootboxOpening.Lootbox.Size = UDim2.fromScale(0, 0)
	self.LootboxOpening.Lootbox.Visible = true
	
	self.LootboxOpening.Card.Size = UDim2.fromScale(0, 0)
	self.LootboxOpening.Card.Visible = false
	
	self.LootboxOpening.Currencies.Visible = true
	self.LootboxOpening.Currency1.Size = UDim2.fromScale(0, 0)
	self.LootboxOpening.Currency2.Size = UDim2.fromScale(0, 0)
	self.LootboxOpening.Currency1.Visible = false
	self.LootboxOpening.Currency2.Visible = false
	
	self.LootboxOpening.BtnClaim.Visible = false
	
	self.LootboxOpening.FirstEffect.Rotation = 0 
	self.LootboxOpening.FirstEffect.Visible = true 
	
	for i = 2, 9 do
		local img = self.LootboxOpening.Effect:WaitForChild(tostring(i))
		if img then
			img.Visible = false
		end
	end
	
	-- Configure Card frame based on rewards
	if rewards and rewards.card then
		self:ConfigureCardFromRewards(rewards)
	end
	
	-- Configure currencies based on rewards
	if rewards then
		self:ConfigureCurrenciesFromRewards(rewards)
	end
end

-- Configure Card frame from rewards data
function LootboxUIHandler:ConfigureCardFromRewards(rewards)
	if not rewards.card then return end
	
	local card = rewards.card
	local cardId = card.cardId
	local copies = card.copies
	
	-- Get card rarity from CardCatalog
	local CardCatalog = require(ReplicatedStorage.Modules.Cards.CardCatalog)
	local cardData = CardCatalog.GetCard(cardId)
	if not cardData then
		warn("LootboxUIHandler: Card data not found for cardId:", cardId)
		return
	end
	
	local rarity = cardData.rarity:gsub("^%l", string.upper)
	local rarityColor = Manifest.RarityColors[rarity]
	
	if not rarityColor then
		warn("LootboxUIHandler: Rarity color not found for rarity:", rarity)
		return
	end
	
	-- Configure Card BackgroundColor3 based on rarity
	self.LootboxOpening.Card.BackgroundColor3 = rarityColor
	
	-- Configure ImgHero with asset ID from Manifest
	local imgHero = self.LootboxOpening.Card.Content:FindFirstChild("ImgHero")
	if imgHero then
		local assetId = Manifest.CardImages[cardId]
		if assetId then
			imgHero.Image = assetId
		else
			warn("LootboxUIHandler: Card image not found for cardId:", cardId)
		end
	end
	
	-- Configure Progress TxtValue with copies count
	local progressTxtValue = self.LootboxOpening.Card.Content.Progress:FindFirstChild("TxtValue")
	if progressTxtValue then
		progressTxtValue.Text = "x" .. copies
	end
	
	-- Configure Level BackgroundColor3 based on rarity
	local level = self.LootboxOpening.Card.Content:FindFirstChild("Level")
	if level then
		level.BackgroundColor3 = rarityColor
		
		-- Configure UICornerOverlay1
		local uiCornerOverlay1 = level:FindFirstChild("UICornerOverlay1")
		if uiCornerOverlay1 then
			uiCornerOverlay1.BackgroundColor3 = rarityColor
		end
		
		-- Configure UICornerOverlay2
		local uiCornerOverlay2 = level:FindFirstChild("UICornerOverlay2")
		if uiCornerOverlay2 then
			uiCornerOverlay2.BackgroundColor3 = rarityColor
		end
		
		-- Configure Level Content TxtValue
		local levelContent = level:FindFirstChild("Content")
		if levelContent then
			local levelTxtValue = levelContent:FindFirstChild("TxtValue")
			if levelTxtValue then
				levelTxtValue.Text = "1"
			end
		end
	end

	local attackFrame = self.LootboxOpening.Card.Content:FindFirstChild("Attack")
	if attackFrame then
		attackFrame.Visible = true
		local attackValue = attackFrame:FindFirstChild("Value")
		if attackValue then
			attackValue = attackValue:FindFirstChild("TxtValue")
			if attackValue then
				attackValue.Text = tostring(cardData.base.atk)
			end
		end
	end

	local healthFrame = self.LootboxOpening.Card.Content:FindFirstChild("Health")
	if healthFrame then
		healthFrame.Visible = true
		local healthValue = healthFrame:FindFirstChild("Value")
		if healthValue then
			healthValue = healthValue:FindFirstChild("TxtValue")
			if healthValue then
				healthValue.Text = tostring(cardData.base.hp)
			end
		end
	end

	local defenseFrame = self.LootboxOpening.Card.Content:FindFirstChild("Defense")
	if defenseFrame then
		defenseFrame.Visible = cardData.base.defence > 0
		local defenseValue = defenseFrame:FindFirstChild("Value")
		if defenseValue then
			defenseValue = defenseValue:FindFirstChild("TxtValue")
			if defenseValue then
				defenseValue.Text = tostring(cardData.base.defence)
			end
		end
	end
end

-- Configure currencies from rewards data
function LootboxUIHandler:ConfigureCurrenciesFromRewards(rewards)
	-- Configure Currency1 (hard currency) - hide if hardDelta == 0
	if rewards.hardDelta == 0 then
		self.LootboxOpening.Currency1.Visible = false
	else
		self.LootboxOpening.Currency1.Visible = true
		local currency1TxtValue = self.LootboxOpening.Currency1:FindFirstChild("TxtValue")
		if currency1TxtValue then
			currency1TxtValue.Text = tostring(rewards.hardDelta)
		end
	end
	
	-- Configure Currency2 (soft currency) - hide if softDelta == 0
	if rewards.softDelta == 0 then
		self.LootboxOpening.Currency2.Visible = false
	else
		self.LootboxOpening.Currency2.Visible = true
		local currency2TxtValue = self.LootboxOpening.Currency2:FindFirstChild("TxtValue")
		if currency2TxtValue then
			currency2TxtValue.Text = tostring(rewards.softDelta)
		end
	end
end

function LootboxUIHandler:OpenLootbox(rewards)
	self:ResetLootboxAnimationState(rewards)

	if self.Utilities and self.Utilities.TweenUI then
		self.Utilities.TweenUI.FadeIn(self.LootboxOpening.Main, 0.3, function ()
			LootboxUIHandler:OpenLootboxAnimation(rewards)
		end)
	end
end

-- Main animation
function LootboxUIHandler:OpenLootboxAnimation(rewards)
	-- First effect
	local tweenInfo = TweenInfo.new(
		0.1,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1, -- endless cycle
		true -- reverse
	)

	local effectAngleTween = TweenService:Create(self.LootboxOpening.FirstEffect, tweenInfo, {Rotation = angle})
	effectAngleTween:Play()
	
	if self.Utilities and self.Utilities.TweenUI then
		self.Utilities.TweenUI.FadeIn(self.LootboxOpening.Lootbox, fadeInTime)
	end
	local ballSizeTween = TweenService:Create(self.LootboxOpening.Lootbox, TweenInfo.new(fadeInTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(0.237, 0.423) })
	
	ballSizeTween:Play()
	ballSizeTween.Completed:Wait()
	effectAngleTween:Cancel()
	
	ballSizeTween = TweenService:Create(self.LootboxOpening.Lootbox, TweenInfo.new(3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(0.331, 0.589) })
	ballSizeTween:Play()
	
	for i = 2, 9 do
		local img = self.LootboxOpening.Effect:WaitForChild(tostring(i))
		if img then
			img.Visible = true
		end
		if i ~= 9 then
			task.wait(effectDelay)
		end
	end

	if self.Utilities and self.Utilities.TweenUI then
		self.Utilities.TweenUI.FadeOut(self.LootboxOpening.Lootbox, fadeOutTime, function ()
			self.LootboxOpening.Lootbox.Visible = false
		end)
	end

	self.LootboxOpening.Card.Visible = true
	
	if self.Utilities and self.Utilities.TweenUI then
		self.Utilities.TweenUI.FadeIn(self.LootboxOpening.Card, cardTweenTime)
	end
	local cardSizeTween = TweenService:Create(self.LootboxOpening.Card, TweenInfo.new(cardTweenTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(0.094, 0.166) })
	
	cardSizeTween:Play()
	cardSizeTween.Completed:Wait()

	self.LootboxOpening.Currency1.Visible = rewards.hardDelta > 0
	self.LootboxOpening.Currency2.Visible = rewards.softDelta > 0

	local hardSizeTween = TweenService:Create(self.LootboxOpening.Currency1, TweenInfo.new(fadeInTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(0.281, 0.558) })
	hardSizeTween:Play()
	
	local softSizeTween = TweenService:Create(self.LootboxOpening.Currency2, TweenInfo.new(fadeInTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(0.281, 0.558) })
	softSizeTween:Play()

	self.LootboxOpening.BtnClaim.Visible = true
end

-- Public Methods
function LootboxUIHandler:IsInitialized()
	return self._initialized
end

-- Cleanup
function LootboxUIHandler:Cleanup()
	
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
