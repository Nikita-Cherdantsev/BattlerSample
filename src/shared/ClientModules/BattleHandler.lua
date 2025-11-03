--[[
	BattleHandler - Client-side battle UI controller
	
	Handles battle screen display, animations, and user interaction.
	Integrates with server-side MatchService for battle execution.
]]

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

--// Module
local BattleHandler = {}

--// State
BattleHandler.Connections = {}
BattleHandler._initialized = false
BattleHandler.isAnimating = false
BattleHandler.currentBattle = nil
BattleHandler.battleState = nil
BattleHandler.battleResult = nil -- Store battle result for rewards
BattleHandler.originalCardSizes = {} -- Store original sizes to prevent accumulation
BattleHandler.cardHealthValues = {} -- Store current health values for each card frame

--// Constants
local ANIMATION_DURATION = 0.5
local CARD_SCALE_INCREASE = 1.1 -- 10% size increase
local ATTACK_MOVE_DISTANCE = 100 -- Distance to move toward center
local TWEEN_DURATION = 0.4 -- Duration for each animation phase

--// Initialization
function BattleHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	
	-- Safe require of Utilities to avoid loading errors
	local success, utilities = pcall(function()
		return controller:GetModule("Utilities")
	end)
	
	if success then
		self.Utilities = utilities
	else
		warn("BattleHandler: Could not load Utilities module: " .. tostring(utilities))
		self.Utilities = {
			CardCatalog = { GetCard = function() return nil end },
			Manifest = { CardImages = {} }
		}
	end

	-- Directly require Manifest module for card images
	local manifestSuccess, manifest = pcall(function()
		return require(ReplicatedStorage.Modules.Assets.Manifest)
	end)
	
	if manifestSuccess then
		self.Manifest = manifest
	else
		warn("BattleHandler: Could not load Manifest module: " .. tostring(manifest))
		self.Manifest = { CardImages = {} }
	end

	-- Setup battle UI
	self:SetupBattleUI()

	self._initialized = true
	return true
end

function BattleHandler:SetupBattleUI()
	-- Get UI references
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gameGui = playerGui:WaitForChild("GameUI")
	
	-- Find Battle frame
	self.BattleFrame = gameGui:FindFirstChild("Battle")
	if not self.BattleFrame then
		warn("BattleHandler: Battle frame not found in GameUI")
		return
	end
	
	-- Find player deck panel
	local playerFrame = self.BattleFrame:FindFirstChild("Player")
	if playerFrame then
		local contentFrame = playerFrame:FindFirstChild("Content")
		if contentFrame then
			local innerContent = contentFrame:FindFirstChild("Content")
			if innerContent then
				self.PlayerDeckFrame = innerContent
			else
				warn("BattleHandler: Inner Content frame not found in Player Content")
			end
		else
			warn("BattleHandler: Content frame not found in Player frame")
		end
	else
		warn("BattleHandler: Player frame not found in Battle frame")
	end
	
	-- Find rival deck panel
	local rivalFrame = self.BattleFrame:FindFirstChild("Rival")
	if rivalFrame then
		local contentFrame = rivalFrame:FindFirstChild("Content")
		if contentFrame then
			local innerContent = contentFrame:FindFirstChild("Content")
			if innerContent then
				self.RivalDeckFrame = innerContent
			else
				warn("BattleHandler: Inner Content frame not found in Rival Content")
			end
		else
			warn("BattleHandler: Content frame not found in Rival frame")
		end
	else
		warn("BattleHandler: Rival frame not found in Battle frame")
	end
	
	-- Store original card positions and sizes for animations
	self:StoreOriginalCardProperties()
end

function BattleHandler:StoreOriginalCardProperties()
	self.originalCardProperties = {}
	
	-- Store player card properties
	if self.PlayerDeckFrame then
		local placeholderFrames = {}
		for _, child in pairs(self.PlayerDeckFrame:GetChildren()) do
			if child.Name == "Placeholder" and child:IsA("Frame") then
				table.insert(placeholderFrames, child)
			end
		end
		
		-- Sort by LayoutOrder
		table.sort(placeholderFrames, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		
		for i = 1, math.min(6, #placeholderFrames) do
			local placeholder = placeholderFrames[i]
			if placeholder then
				self.originalCardProperties["player_" .. i] = {
					position = placeholder.Position,
					size = placeholder.Size,
					anchorPoint = placeholder.AnchorPoint
				}
			end
		end
	end
	
	-- Store rival card properties
	if self.RivalDeckFrame then
		local placeholderFrames = {}
		for _, child in pairs(self.RivalDeckFrame:GetChildren()) do
			if child.Name == "Placeholder" and child:IsA("Frame") then
				table.insert(placeholderFrames, child)
			end
		end
		
		-- Sort by LayoutOrder
		table.sort(placeholderFrames, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		
		for i = 1, math.min(6, #placeholderFrames) do
			local placeholder = placeholderFrames[i]
			if placeholder then
				self.originalCardProperties["rival_" .. i] = {
					position = placeholder.Position,
					size = placeholder.Size,
					anchorPoint = placeholder.AnchorPoint
				}
			end
		end
	end
end

--// Public API

-- Start a battle with the given battle data
function BattleHandler:StartBattle(battleData)
	if not self._initialized then
		warn("BattleHandler: Not initialized")
		return false
	end
	
	if not battleData then
		warn("BattleHandler: No battle data provided")
		return false
	end
	
	-- Store battle data
	self.currentBattle = battleData
	
	-- Show battle frame
	self:ShowBattleFrame()
	
	-- Display decks
	self:DisplayDecks(battleData)
	
	-- Start battle simulation
	self:SimulateBattle(battleData)
	
	return true
end

function BattleHandler:ShowBattleFrame()
	if not self.BattleFrame then
		return
	end
	
	self.BattleFrame.Visible = true
	
	-- Use TweenUI if available
	if self.Utilities and self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
		self.Utilities.TweenUI.FadeIn(self.BattleFrame, 0.3)
	end
end

function BattleHandler:HideBattleFrame()
	if not self.BattleFrame then
		return
	end
	
	-- Use TweenUI if available
	if self.Utilities and self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
		self.Utilities.TweenUI.FadeOut(self.BattleFrame, 0.3, function()
			self.BattleFrame.Visible = false
		end)
	else
		self.BattleFrame.Visible = false
	end
end

function BattleHandler:DisplayDecks(battleData)
	-- Display player deck
	if battleData.playerDeck then
		self:DisplayDeck(battleData.playerDeck, "player")
	end
	
	-- Display rival deck with levels
	if battleData.rivalDeck then
		-- Pass rival deck levels if available
		self:DisplayDeck(battleData.rivalDeck, "rival", battleData.rivalDeckLevels)
	end
end

function BattleHandler:DisplayDeck(deck, deckType, deckLevels)
	deckLevels = deckLevels or {} -- Array of levels indexed by deck array position
	local deckFrame = (deckType == "player") and self.PlayerDeckFrame or self.RivalDeckFrame
	if not deckFrame then
		warn("BattleHandler: Deck frame not found for", deckType)
		return
	end
	
	-- Get placeholder frames by their explicit names: Placeholder1, Placeholder2, etc.
	local placeholderFrames = {}
	for i = 1, 6 do
		local placeholderName = "Placeholder" .. i
		local placeholder = deckFrame:FindFirstChild(placeholderName)
		if placeholder and placeholder:IsA("Frame") then
			placeholderFrames[i] = placeholder
		else
			warn("BattleHandler: Placeholder" .. i .. " not found in", deckType, "deck")
		end
	end
	
	-- Get collection for player deck to retrieve card levels
	local collection = nil
	if deckType == "player" and self.ClientState and self.ClientState.getProfile then
		local profile = self.ClientState:getProfile()
		if profile and profile.collection then
			collection = profile.collection
		end
	end
	
	-- Create a mapping of cardId -> level for easier lookup (especially for rival deck)
	local cardLevelMap = {}
	if deckType == "player" then
		-- For player deck, use collection
		if collection then
			for cardId, cardEntry in pairs(collection) do
				cardLevelMap[cardId] = cardEntry.level or 1
			end
		end
	else
		-- For rival deck, map deckLevels array to cardId
		-- deckLevels[i] corresponds to deck[i]
		if deckLevels then
			for deckIndex, cardId in ipairs(deck) do
				local level = deckLevels[deckIndex]
				if level then
					cardLevelMap[cardId] = level
				end
			end
		end
	end
	
	-- Sort deck cards by their slotNumber field (ascending order)
	-- This matches the logic in DeckValidator.MapDeckToBoard
	local sortedCards = {}
	for deckIndex, cardId in ipairs(deck) do
		local cardData = self.Utilities.CardCatalog.GetCard(cardId)
		if cardData and cardData.slotNumber then
			-- Get card level from cardLevelMap (works for both player and rival)
			-- If a card appears multiple times in the deck, we need to track which instance this is
			local level = cardLevelMap[cardId] or 1
			
			table.insert(sortedCards, {
				cardId = cardId,
				slotNumber = cardData.slotNumber,
				level = level,
				originalIndex = deckIndex -- Keep track for debugging
			})
		else
			warn("BattleHandler: Card data or slotNumber not found for", cardId)
		end
	end
	
	-- Sort by slotNumber (ascending) - this matches MapDeckToBoard logic exactly
	table.sort(sortedCards, function(a, b)
		return a.slotNumber < b.slotNumber
	end)
	
	-- Place cards sequentially in slots 1-6 based on sorted order
	-- This matches how MapDeckToBoard assigns slots 1, 2, 3... based on sorted slotNumber
	-- Important: Only place cards that exist (deck size may be < 6)
	
	-- First, clear all placeholder slots (hide cards, show Content frames)
	for i = 1, 6 do
		if placeholderFrames[i] then
			local cardFrame = placeholderFrames[i]:FindFirstChild("Card")
			local contentFrame = placeholderFrames[i]:FindFirstChild("Content")
			if cardFrame then
				cardFrame.Visible = false
			end
			if contentFrame then
				contentFrame.Visible = true
			end
		end
	end
	
	-- Then, place cards in their sorted order positions
	for i, cardInfo in ipairs(sortedCards) do
		if placeholderFrames[i] then
			self:UpdateCardSlot(placeholderFrames[i], cardInfo.cardId, cardInfo.level)
		else
			warn(string.format("BattleHandler: No placeholder frame for slot %d (deck has %d cards)", i, #sortedCards))
		end
	end
end

function BattleHandler:UpdateCardSlot(placeholder, cardId, level)
	-- Find the Content frame inside the placeholder (to hide it)
	local contentFrame = placeholder:FindFirstChild("Content")
	if contentFrame then
		-- Hide the Content frame (which contains ImgPattern)
		contentFrame.Visible = false
	end
	
	-- Look for existing Card frame directly under Placeholder (sibling of Content)
	local cardFrame = placeholder:FindFirstChild("Card")
	if cardFrame then
		-- Show the Card frame and populate it
		cardFrame.Visible = true
		self:PopulateCardFrame(cardFrame, cardId, level or 1)
		
		-- Store original size to prevent animation accumulation
		if not self.originalCardSizes[cardFrame] then
			self.originalCardSizes[cardFrame] = cardFrame.Size
		end
	else
		warn("BattleHandler: Card frame not found in Placeholder - please ensure Card template exists in UI")
	end
end

function BattleHandler:PopulateCardFrame(cardFrame, cardId, level)
	-- Get card data
	local cardData = self.Utilities.CardCatalog.GetCard(cardId)
	if not cardData then
		warn("BattleHandler: Card data not found for", cardId)
		return
	end
	
	-- Get card stats for the actual level
	local cardLevel = level or 1
	local CardStats = self.Controller:GetModule("CardStats")
	local stats = CardStats and CardStats.ComputeStats(cardId, cardLevel) or {atk = 0, hp = 0, defence = 0}
	
	-- Get Content frame first
	local contentFrame = cardFrame:FindFirstChild("Content")
	if not contentFrame then
		warn("BattleHandler: Content frame not found in Card frame")
		return
	end
	
	-- Update card hero image
	-- Path: Content -> ImgHero
	local imgHero = contentFrame:FindFirstChild("ImgHero")
	if imgHero then
		if self.Manifest and self.Manifest.CardImages then
			local imageId = self.Manifest.CardImages[cardId]
			if imageId then
				imgHero.Image = imageId
			else
				warn("BattleHandler: No image found for card", cardId)
			end
		end
	end
	
	-- Update attack stat
	-- Path: Content -> Attack -> Value -> TxtValue
	local attackFrame = contentFrame:FindFirstChild("Attack")
	if attackFrame then
		attackFrame.Visible = true
		local valueFrame = attackFrame:FindFirstChild("Value")
		if valueFrame then
			local txtValue = valueFrame:FindFirstChild("TxtValue")
			if txtValue then
				txtValue.Text = tostring(stats.atk)
			end
		end
	end
	
	-- Update defense stat
	-- Path: Content -> Defense -> Value -> TxtValue
	local defenseFrame = contentFrame:FindFirstChild("Defense")
	if defenseFrame then
		if stats.defence > 0 then
			defenseFrame.Visible = true
			local valueFrame = defenseFrame:FindFirstChild("Value")
			if valueFrame then
				local txtValue = valueFrame:FindFirstChild("TxtValue")
				if txtValue then
					txtValue.Text = tostring(stats.defence)
				end
			end
		else
			defenseFrame.Visible = false
		end
	end
	
	-- Update health stat
	-- Path: Content -> Health -> Value -> TxtValue
	local healthFrame = contentFrame:FindFirstChild("Health")
	if healthFrame then
		healthFrame.Visible = true
		local valueFrame = healthFrame:FindFirstChild("Value")
		if valueFrame then
			local txtValue = valueFrame:FindFirstChild("TxtValue")
			if txtValue then
				txtValue.Text = tostring(stats.hp)
			end
		end
		
		-- Store initial health value for this card frame
		self.cardHealthValues[cardFrame] = stats.hp
	end
	
	-- Set rarity color for card background and level frame
	local rarityKey = cardData.rarity:gsub("^%l", string.upper) -- Capitalize first letter
	local rarityColor = self.Manifest.RarityColors[rarityKey]
	if rarityColor then
		cardFrame.BackgroundColor3 = rarityColor
	end
	
	-- Update level display
	-- Path: Content -> Level -> Content -> TxtValue
	local levelFrame = contentFrame:FindFirstChild("Level")
	if levelFrame then
		local levelContent = levelFrame:FindFirstChild("Content")
		if levelContent then
			local txtValue = levelContent:FindFirstChild("TxtValue")
			if txtValue then
				txtValue.Text = tostring(cardLevel)
			end
		end
		
		-- Set rarity color for level frame and overlays
		if rarityColor then
			levelFrame.BackgroundColor3 = rarityColor
			
			-- Update UICornerOverlay1
			local overlay1 = levelFrame:FindFirstChild("UICornerOverlay1")
			if overlay1 then
				overlay1.BackgroundColor3 = rarityColor
			end
			
			-- Update UICornerOverlay2
			local overlay2 = levelFrame:FindFirstChild("UICornerOverlay2")
			if overlay2 then
				overlay2.BackgroundColor3 = rarityColor
			end
		end
	end
	
end


function BattleHandler:SimulateBattle(battleData)
	if not battleData.battleLog then
		warn("BattleHandler: No battle log provided")
		return
	end
	
	-- Process battle log with animations
	self:ProcessBattleLog(battleData.battleLog)
end

function BattleHandler:ProcessBattleLog(battleLog)
	-- Process battle log sequentially with delays
	self:ProcessNextBattleAction(battleLog, 1)
end

function BattleHandler:ProcessNextBattleAction(battleLog, index)
	if index > #battleLog then
		-- Store battle result from current battle
		if self.currentBattle and self.currentBattle.result then
			self.battleResult = self.currentBattle.result
		end
		
		-- Battle ended
		self:OnBattleEnd()
		return
	end
	
	local logEntry = battleLog[index]
	
	-- Check if this is a round start (abbreviated: t = "r")
	if logEntry.t == "r" then
		-- Small delay for round start
		task.wait(0.5)
		self:ProcessNextBattleAction(battleLog, index + 1)
		
	-- Check if this is an attack (abbreviated: t = "a")
	elseif logEntry.t == "a" then
		-- Animate attack and wait for completion
		local animationComplete = false
		self:AnimateAttack(logEntry, logEntry.r or 1, function()
			animationComplete = true
		end)
		
		-- Wait for animation to actually complete
		while not animationComplete do
			task.wait(0.1)
		end
		
		-- Small delay after animation before next action
		task.wait(0.1)
		self:ProcessNextBattleAction(battleLog, index + 1)
		
	else
		-- Unknown action type, skip with small delay
		task.wait(0.1)
		self:ProcessNextBattleAction(battleLog, index + 1)
	end
end

function BattleHandler:AnimateAttack(logEntry, round, onComplete)
	-- Use abbreviated field names from compact log
	local attackerSlot = logEntry.as
	local defenderSlot = logEntry.ds
	local attackerPlayer = logEntry.ap
	local defenderPlayer = logEntry.dp
	local damage = logEntry.d
	local defenderHealth = logEntry.dh
	local defenderKO = logEntry.k
	
	-- Debug: Log attack info
	warn(string.format("AnimateAttack: %s slot %d → %s slot %d, health: %s", 
		attackerPlayer, attackerSlot, defenderPlayer, defenderSlot, 
		defenderHealth and tostring(defenderHealth) or "nil"))
	
	-- Get attacker and defender card frames
	local attackerFrame = self:GetCardFrame(attackerPlayer, attackerSlot)
	local defenderFrame = self:GetCardFrame(defenderPlayer, defenderSlot)
	
	if not attackerFrame or not defenderFrame then
		warn("BattleHandler: Could not find card frames for attack animation")
		if onComplete then onComplete() end
		return
	end
	
	-- Simplified animation: just size changes as requested
	self:PlaySimpleAttackAnimation(attackerFrame, defenderFrame, damage, defenderKO, defenderHealth, defenderPlayer, defenderSlot, onComplete)
end

function BattleHandler:GetCardFrame(player, slot)
	local deckFrame = (player == "A") and self.PlayerDeckFrame or self.RivalDeckFrame
	if not deckFrame then
		warn("BattleHandler: Deck frame not found for player", player)
		return nil
	end
	
	-- Get the placeholder frame by its explicit name: Placeholder1, Placeholder2, etc.
	local placeholderName = "Placeholder" .. slot
	local placeholder = deckFrame:FindFirstChild(placeholderName)
	if not placeholder or not placeholder:IsA("Frame") then
		warn("BattleHandler: Placeholder" .. slot .. " not found in", player, "deck")
		return nil
	end
	
	-- Look for the existing Card frame directly under Placeholder (sibling of Content)
	local cardFrame = placeholder:FindFirstChild("Card")
	if not cardFrame then
		warn("BattleHandler: Card frame not found in Placeholder" .. slot)
		return nil
	end
	
	return cardFrame
end

function BattleHandler:PlaySimpleAttackAnimation(attackerFrame, defenderFrame, damage, defenderKO, actualHealth, defenderPlayer, defenderSlot, onComplete)
	-- Get or store original sizes
	local originalAttackerSize = self.originalCardSizes[attackerFrame] or attackerFrame.Size
	local originalDefenderSize = self.originalCardSizes[defenderFrame] or defenderFrame.Size
	
	-- Ensure they're stored
	if not self.originalCardSizes[attackerFrame] then
		self.originalCardSizes[attackerFrame] = originalAttackerSize
	end
	if not self.originalCardSizes[defenderFrame] then
		self.originalCardSizes[defenderFrame] = originalDefenderSize
	end
	
	-- Create scaled sizes using UDim2 properly
	local attackerScaledSize = UDim2.new(
		originalAttackerSize.X.Scale * CARD_SCALE_INCREASE,
		originalAttackerSize.X.Offset * CARD_SCALE_INCREASE,
		originalAttackerSize.Y.Scale * CARD_SCALE_INCREASE,
		originalAttackerSize.Y.Offset * CARD_SCALE_INCREASE
	)
	local defenderScaledSize = UDim2.new(
		originalDefenderSize.X.Scale * CARD_SCALE_INCREASE,
		originalDefenderSize.X.Offset * CARD_SCALE_INCREASE,
		originalDefenderSize.Y.Scale * CARD_SCALE_INCREASE,
		originalDefenderSize.Y.Offset * CARD_SCALE_INCREASE
	)
	
	-- Phase 1: Increase size of attacking card
	local attackerScaleTween = TweenService:Create(attackerFrame, TweenInfo.new(TWEEN_DURATION), {
		Size = attackerScaledSize
	})
	
	-- Phase 2: Increase size of attacked card
	local defenderScaleTween = TweenService:Create(defenderFrame, TweenInfo.new(TWEEN_DURATION), {
		Size = defenderScaledSize
	})
	
	-- Phase 3: Return attacked card to original size
	local defenderReturnTween = TweenService:Create(defenderFrame, TweenInfo.new(TWEEN_DURATION), {
		Size = originalDefenderSize
	})
	
	-- Phase 4: Return attacking card to original size
	local attackerReturnTween = TweenService:Create(attackerFrame, TweenInfo.new(TWEEN_DURATION), {
		Size = originalAttackerSize
	})
	
	-- Chain animations
	attackerScaleTween:Play()
		attackerScaleTween.Completed:Connect(function()
			defenderScaleTween:Play()
			defenderScaleTween.Completed:Connect(function()
				-- Update defender's health after impact using actual health from server
				self:UpdateCardHealth(defenderFrame, actualHealth, defenderPlayer, defenderSlot)
				
				defenderReturnTween:Play()
			defenderReturnTween.Completed:Connect(function()
				attackerReturnTween:Play()
				attackerReturnTween.Completed:Connect(function()
					-- Animation complete, call callback
					if onComplete then
						onComplete()
					end
				end)
			end)
		end)
	end)
end

function BattleHandler:UpdateCardHealth(cardFrame, actualHealth, player, slot)
	if not cardFrame then
		warn("BattleHandler:UpdateCardHealth - cardFrame is nil")
		return
	end
	
	-- Use actual health from server if provided
	local newHealth = actualHealth or 0
	
	-- Get old health from stored values (by frame)
	local oldHealth = self.cardHealthValues[cardFrame]
	if oldHealth == nil then
		-- Try to read current health from UI if not stored
		local contentFrame = cardFrame:FindFirstChild("Content")
		if contentFrame then
			local healthFrame = contentFrame:FindFirstChild("Health")
			if healthFrame then
				local valueFrame = healthFrame:FindFirstChild("Value")
				if valueFrame then
					local txtValue = valueFrame:FindFirstChild("TxtValue")
					if txtValue then
						local currentText = txtValue.Text
						if currentText and currentText ~= "" then
							oldHealth = tonumber(currentText) or 0
						end
					end
				end
			end
		end
		oldHealth = oldHealth or 0
	end
	
	-- Store new health
	self.cardHealthValues[cardFrame] = newHealth
	
	-- Update UI
	local contentFrame = cardFrame:FindFirstChild("Content")
	if contentFrame then
		local healthFrame = contentFrame:FindFirstChild("Health")
		if healthFrame then
			local valueFrame = healthFrame:FindFirstChild("Value")
			if valueFrame then
				local txtValue = valueFrame:FindFirstChild("TxtValue")
				if txtValue then
					-- Always update the text to ensure it's visible
					txtValue.Text = tostring(newHealth)
					
					-- Debug: Log health update with player/slot info
					local identifier = (player and slot) and string.format("%s slot %d", player, slot) or "unknown"
					if oldHealth ~= newHealth then
						warn(string.format("Health updated: %d → %d (%s)", oldHealth, newHealth, identifier))
					else
						warn(string.format("Health check: %d (no change, %s)", newHealth, identifier))
					end
				else
					warn("BattleHandler: TxtValue not found in health frame")
				end
			else
				warn("BattleHandler: Value frame not found in health frame")
			end
		else
			warn("BattleHandler: Health frame not found in Content")
		end
	else
		warn("BattleHandler: Content frame not found in card frame")
	end
end

function BattleHandler:OnBattleEnd()
	print("🎁 BattleHandler:OnBattleEnd called")
	print("🎁 BattleHandler: battleResult =", self.battleResult and "present" or "nil")
	print("🎁 BattleHandler: currentBattle =", self.currentBattle and "present" or "nil")
	if self.currentBattle then
		print("🎁 BattleHandler: currentBattle.rewards =", self.currentBattle.rewards and "present" or "nil")
		if self.currentBattle.rewards then
			print("🎁 BattleHandler: reward type =", self.currentBattle.rewards.type)
		end
	end
	
	-- Wait a moment then hide battle frame
	task.wait(2)
	self:HideBattleFrame()
	
	-- Show rewards if battle result is available
	if self.battleResult and self.Controller then
		print("🎁 BattleHandler: Getting RewardsHandler...")
		local rewardsHandler = self.Controller:GetRewardsHandler()
		if rewardsHandler then
			print("🎁 BattleHandler: RewardsHandler found, calling ShowRewards")
			-- Determine if player won (CombatEngine returns "A" for player, "B" for opponent)
			local isVictory = (self.battleResult.winner == "A")
			print("🎁 BattleHandler: winner =", self.battleResult.winner, "isVictory =", isVictory)
			-- Get rewards from current battle (included in server response)
			local battleRewards = nil
			if self.currentBattle and self.currentBattle.rewards then
				battleRewards = self.currentBattle.rewards
				print("🎁 BattleHandler: battleRewards type =", battleRewards.type, "amount/rarity =", battleRewards.amount or battleRewards.rarity)
			else
				print("🎁 BattleHandler: WARNING - No rewards in currentBattle!")
			end
			rewardsHandler:ShowRewards(self.battleResult, isVictory, battleRewards)
		else
			warn("🎁 BattleHandler: RewardsHandler not found!")
		end
	else
		if not self.battleResult then
			warn("🎁 BattleHandler: No battleResult available")
		end
		if not self.Controller then
			warn("🎁 BattleHandler: No Controller available")
		end
	end
	
	-- Clean up
	self.currentBattle = nil
	self.battleState = nil
	self.battleResult = nil
end

--// Cleanup
function BattleHandler:Cleanup()
	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}

	self._initialized = false
end

return BattleHandler
