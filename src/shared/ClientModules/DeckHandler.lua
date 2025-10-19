--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

--// Modules
local Config = require(game.StarterPlayer.StarterPlayerScripts.Config)
local ErrorMap = require(game.ReplicatedStorage.Modules.ErrorMap)
local NetworkClient = require(game.StarterPlayer.StarterPlayerScripts.Controllers.NetworkClient)
local CardCatalog = require(game.ReplicatedStorage.Modules.Cards.CardCatalog)
local CardStats = require(game.ReplicatedStorage.Modules.Cards.CardStats)
local CardLevels = require(game.ReplicatedStorage.Modules.Cards.CardLevels)
local Manifest = require(game.ReplicatedStorage.Modules.Assets.Manifest)

--// Module
local DeckHandler = {}

--// State
DeckHandler.Connections = {}
DeckHandler._initialized = false

DeckHandler.isAnimating = false
DeckHandler.currentProfile = nil
DeckHandler.collectionCards = {}
DeckHandler.deckCards = {}

--// Initialization
function DeckHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	
	-- Safe require of Utilities to avoid loading errors
	local success, utilities = pcall(function()
		return controller:GetModule("Utilities")
	end)
	
	if success then
		self.Utilities = utilities
	else
		warn("DeckHandler: Could not load Utilities module: " .. tostring(utilities))
		self.Utilities = {
			TweenUI = { FadeIn = function() end, FadeOut = function() end },
			Blur = { Show = function() end, Hide = function() end }
		}
	end
	
	-- Get CardInfoHandler reference
	self.CardInfoHandler = nil
	
	-- Initialize state
	self.Connections = {}
	self.currentProfile = nil
	self.collectionCards = {}
	self.deckCards = {}

	-- Setup Deck functionality
	self:SetupDeck()

	self._initialized = true
	print("✅ DeckHandler initialized successfully!")
	return true
end

function DeckHandler:SetupDeck()
	-- Access UI from player's PlayerGui (which should be copied from StarterGui)
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	
	-- Debug: Print all children in PlayerGui
	for _, child in pairs(playerGui:GetChildren()) do
	end
	
	-- Wait for Roblox to automatically clone GameUI from StarterGui
	local gameGui = playerGui:WaitForChild("GameUI", 5) -- Initial wait
	
	if not gameGui then
		gameGui = playerGui:WaitForChild("GameUI", 10) -- Extended wait
		
		if not gameGui then
			warn("DeckHandler: GameUI not found in PlayerGui after extended waiting")
			return
		end
	end
	
	
	-- Look for Deck frame
	local deckFrame = gameGui:FindFirstChild("Deck")
	if not deckFrame then
		warn("DeckHandler: Deck frame not found in " .. gameGui.Name)
		for _, child in pairs(gameGui:GetChildren()) do
		end
		return
	end
	
	
	-- Store UI reference for later use
	self.UI = gameGui
	self.DeckFrame = deckFrame
	
	-- Hide deck initially
	deckFrame.Visible = false
	
	-- Setup deck functionality
	self:SetupOpenButton()
	self:SetupCloseButton()
	self:SetupCardContainers()
	
	-- Setup ProfileUpdated event handler
	self:SetupProfileUpdatedHandler()
	
	print("✅ DeckHandler: Deck UI setup completed")
end

function DeckHandler:SetupOpenButton()
	-- Look for deck button in the UI
	-- Path: GameUI -> LeftPanel -> BtnDeck
	
	local leftPanel = self.UI:FindFirstChild("LeftPanel")
	if not leftPanel then
		warn("DeckHandler: LeftPanel not found in GameUI")
		return
	end
	
	local deckButton = leftPanel:FindFirstChild("BtnDeck")
	if not deckButton then
		warn("DeckHandler: BtnDeck not found in LeftPanel")
		return
	end
	
	
	-- Debug: Print the structure of the deck button
	for _, child in pairs(deckButton:GetChildren()) do
	end
	
	-- Connect to the TextButton itself (not the ImgLabel)
	-- The TextButton is the actual clickable element
	if deckButton:IsA("TextButton") then
		local connection = deckButton.MouseButton1Click:Connect(function()
			self:OpenWindow()
		end)
		table.insert(self.Connections, connection)
		print("✅ DeckHandler: Open button (TextButton) connected")
		return
	end
	
	-- Fallback for other button types
	warn("DeckHandler: Found element '" .. deckButton.Name .. "' but it's not a TextButton (it's a " .. deckButton.ClassName .. ")")
	
	-- Try to connect to other clickable elements as fallback
	if deckButton:IsA("GuiButton") or deckButton:IsA("ImageButton") then
		local connection = deckButton.MouseButton1Click:Connect(function()
			self:OpenWindow()
		end)
		table.insert(self.Connections, connection)
		print("✅ DeckHandler: Open button (fallback) connected")
	else
		warn("DeckHandler: Cannot connect click handler to " .. deckButton.ClassName)
	end
end

function DeckHandler:SetupCloseButton()
	-- Close button is now handled by CloseButtonHandler
	-- No need to set up individual close button here
end

function DeckHandler:SetupCardContainers()
	-- Setup collection container
	-- Path: GameUI.Deck.Collection.Content.Content.ScrollingFrame
	local collectionContainer = self.DeckFrame:FindFirstChild("Collection")
	if collectionContainer then
		collectionContainer = collectionContainer:FindFirstChild("Content")
		if collectionContainer then
			collectionContainer = collectionContainer:FindFirstChild("Content")
			if collectionContainer then
				collectionContainer = collectionContainer:FindFirstChild("ScrollingFrame")
			end
		end
	end
	
	if collectionContainer then
		self.CollectionContainer = collectionContainer
		print("✅ DeckHandler: Collection container found")
	else
		warn("DeckHandler: Collection container not found")
	end
	
	-- Setup deck container
	-- Path: GameUI.Deck.Deck.Content.Content
	local deckContainer = self.DeckFrame:FindFirstChild("Deck")
	if deckContainer then
		deckContainer = deckContainer:FindFirstChild("Content")
		if deckContainer then
			deckContainer = deckContainer:FindFirstChild("Content")
		end
	end
	
	if deckContainer then
		self.DeckContainer = deckContainer
		print("✅ DeckHandler: Deck container found")
	else
		warn("DeckHandler: Deck container not found")
	end
	
	-- Find template objects
	self.PlaceholderTemplate = self.DeckFrame:FindFirstChild("_Placeholder")
	self.CardTemplate = self.DeckFrame:FindFirstChild("_Card")
	
	if self.PlaceholderTemplate then
		print("✅ DeckHandler: Placeholder template found")
	else
		warn("DeckHandler: Placeholder template not found")
	end
	
	if self.CardTemplate then
		print("✅ DeckHandler: Card template found")
	else
		warn("DeckHandler: Card template not found")
	end
end

function DeckHandler:LoadProfileData()
	-- Load profile data from client state
	if self.ClientState and self.ClientState.GetState then
		local state = self.ClientState:GetState()
		if state and state.profile then
			self.currentProfile = state.profile
			return true
		end
	end
	
	-- Request profile from server if not available
	NetworkClient.requestProfile()
	return false
end

function DeckHandler:UpdateCollectionDisplay()
	if not self.CollectionContainer or not self.currentProfile then
		return
	end
	
	-- Clear existing collection cards
	for _, child in pairs(self.CollectionContainer:GetChildren()) do
		if child.Name:match("^Card_") then
			child:Destroy()
		end
	end
	
	-- Get all cards from catalog and sort them by ownership and name
	local sortedCards = self:SortCollectionCards()
	
	-- Create collection cards
	for _, cardData in ipairs(sortedCards) do
		local cardInstance = self:CreateCollectionCard(cardData)
		if cardInstance then
			cardInstance.Parent = self.CollectionContainer
		end
	end
	
	print("✅ DeckHandler: Collection display updated")
end

-- Sort collection cards: owned cards first (by name), then unowned cards (by name)
function DeckHandler:SortCollectionCards()
	if not self.currentProfile or not self.currentProfile.collection then
		-- If no profile, return all cards sorted by name
		local allCards = {}
		for id, card in pairs(CardCatalog.Cards) do
			table.insert(allCards, card)
		end
		
		table.sort(allCards, function(a, b)
			return a.name < b.name
		end)
		
		return allCards
	end
	
	local ownedCards = {}
	local unownedCards = {}
	
	-- Get all cards from catalog
	for id, card in pairs(CardCatalog.Cards) do
		-- Check if player owns this card
		local collectionData = self.currentProfile.collection[id]
		local isOwned = false
		
		if collectionData then
			-- Check if it's a number (old format) or table (new format)
			if type(collectionData) == "number" then
				isOwned = collectionData > 0
			elseif type(collectionData) == "table" and collectionData.count then
				isOwned = collectionData.count > 0
			end
		end
		
		if isOwned then
			table.insert(ownedCards, card)
		else
			table.insert(unownedCards, card)
		end
	end
	
	-- Sort owned cards by slotNumber
	table.sort(ownedCards, function(a, b)
		return a.slotNumber < b.slotNumber
	end)
	
	-- Sort unowned cards by slotNumber
	table.sort(unownedCards, function(a, b)
		return a.slotNumber < b.slotNumber
	end)
	
	-- Combine: owned cards first, then unowned cards
	local sortedCards = {}
	for _, card in ipairs(ownedCards) do
		table.insert(sortedCards, card)
	end
	for _, card in ipairs(unownedCards) do
		table.insert(sortedCards, card)
	end
	
	return sortedCards
end

function DeckHandler:UpdateDeckDisplay()
	if not self.DeckContainer or not self.currentProfile then
		return
	end
	
	-- Clear existing deck cards
	for _, child in pairs(self.DeckContainer:GetChildren()) do
		if child.Name:match("^DeckCard_") or child.Name:match("^Placeholder_") then
			child:Destroy()
		end
	end
	
	-- Create deck slots (6 slots)
	for i = 1, 6 do
		local cardId = self.currentProfile.deck and self.currentProfile.deck[i]
		local cardInstance
		
		if cardId then
			-- Create card instance
			local cardData = CardCatalog.GetCard(cardId)
			if cardData then
				cardInstance = self:CreateDeckCard(cardData, i)
			end
		end
		
		if not cardInstance then
			-- Create placeholder
			cardInstance = self:CreatePlaceholder(i)
		end
		
		if cardInstance then
			cardInstance.Parent = self.DeckContainer
		end
	end
	
	print("✅ DeckHandler: Deck display updated")
end

function DeckHandler:CreateCollectionCard(cardData)
	if not self.CardTemplate then
		return nil
	end
	
	-- Clone the template
	local cardInstance = self.CardTemplate:Clone()
	cardInstance.Name = "Card_" .. cardData.id
	cardInstance.Visible = true
	
	-- Get collection data for this card
	local collectionEntry = self.currentProfile.collection and self.currentProfile.collection[cardData.id]
	local hasCard = collectionEntry ~= nil
	local cardLevel = hasCard and collectionEntry.level or 0
	local cardCount = hasCard and collectionEntry.count or 0
	
	-- Update card appearance based on rarity and ownership
	self:UpdateCardAppearance(cardInstance, cardData, hasCard, cardLevel, cardCount)
	
	-- Add click handler for collection cards
    local cardButton = cardInstance:FindFirstChild("BtnInfo")
	if cardButton and cardButton:IsA("GuiButton") then
		local connection = cardButton.MouseButton1Click:Connect(function()
			self:OnCollectionCardClicked(cardData.id)
		end)
		table.insert(self.Connections, connection)
	else
		warn("DeckHandler: BtnInfo button not found or not a GuiButton in collection card")
	end
	
	return cardInstance
end

function DeckHandler:CreateDeckCard(cardData, slotIndex)
	if not self.CardTemplate then
		return nil
	end
	
	-- Clone the template
	local cardInstance = self.CardTemplate:Clone()
	cardInstance.Name = "DeckCard_" .. cardData.id .. "_" .. slotIndex
	cardInstance.Visible = true
	
	-- Get collection data for this card
	local collectionEntry = self.currentProfile.collection and self.currentProfile.collection[cardData.id]
	local hasCard = collectionEntry ~= nil
	local cardLevel = hasCard and collectionEntry.level or 0
	local cardCount = hasCard and collectionEntry.count or 0
	
	-- Update card appearance
	self:UpdateCardAppearance(cardInstance, cardData, hasCard, cardLevel, cardCount)
	
	-- Add click handler for deck cards
    local cardButton = cardInstance:FindFirstChild("BtnInfo")
	if cardButton and cardButton:IsA("GuiButton") then
		local connection = cardButton.MouseButton1Click:Connect(function()
			self:OnDeckCardClicked(cardData.id, slotIndex)
		end)
		table.insert(self.Connections, connection)
	else
		warn("DeckHandler: BtnInfo button not found or not a GuiButton in deck card")
	end
	
	return cardInstance
end

function DeckHandler:CreatePlaceholder(slotIndex)
	if not self.PlaceholderTemplate then
		return nil
	end
	
	-- Clone the template
	local placeholderInstance = self.PlaceholderTemplate:Clone()
	placeholderInstance.Name = "Placeholder_" .. slotIndex
	placeholderInstance.Visible = true
	
	return placeholderInstance
end

function DeckHandler:UpdateCardAppearance(cardInstance, cardData, hasCard, cardLevel, cardCount)
	-- Update rarity colors
	local rarityKey = cardData.rarity:gsub("^%l", string.upper) -- Capitalize first letter
	local rarityColors = hasCard and Manifest.RarityColors or Manifest.RarityColorsDisabled
	local rarityColor = rarityColors[rarityKey]
	
	if rarityColor then
		cardInstance.BackgroundColor3 = rarityColor
		
		-- Update level background color
		local levelFrame = cardInstance:FindFirstChild("Content")
		if levelFrame then
			levelFrame = levelFrame:FindFirstChild("Level")
			if levelFrame then
				levelFrame.BackgroundColor3 = rarityColor
			end

            local cornerOverlay = levelFrame:FindFirstChild("UICornerOverlay1")
			if cornerOverlay then
				cornerOverlay.BackgroundColor3 = rarityColor
			end

            cornerOverlay = levelFrame:FindFirstChild("UICornerOverlay2")
			if cornerOverlay then
				cornerOverlay.BackgroundColor3 = rarityColor
			end
		end
	end
	
	-- Update level display
	local levelText = cardInstance:FindFirstChild("Content")
	if levelText then
		levelText = levelText:FindFirstChild("Level")
		if levelText then
			levelText = levelText:FindFirstChild("Content")
			if levelText then
				levelText = levelText:FindFirstChild("TxtValue")
				if levelText then
					levelText.Text = tostring(cardLevel)
				end
			end
		end
	end
	
	-- Update level up and max level icons
	local levelUpIcon = cardInstance:FindFirstChild("Content")
	if levelUpIcon then
		levelUpIcon = levelUpIcon:FindFirstChild("Level")
		if levelUpIcon then
			levelUpIcon = levelUpIcon:FindFirstChild("Content")
			if levelUpIcon then
				local imgLevelUp = levelUpIcon:FindFirstChild("ImgLevelUp")
				local imgMax = levelUpIcon:FindFirstChild("ImgMax")
				
				if imgLevelUp and imgMax then
					if cardLevel >= 10 then
						imgLevelUp.Visible = false
						imgMax.Visible = true
					else
						-- Check if can level up
						local canLevelUp, _ = CardLevels.CanLevelUp(cardData.id, cardLevel, cardCount, self.currentProfile.currencies.soft)
						imgLevelUp.Visible = canLevelUp
						imgMax.Visible = false
					end
				end
			end
		end
	end
	
	-- Update progress display
	local progressFrame = cardInstance:FindFirstChild("Content")
	if progressFrame then
		progressFrame = progressFrame:FindFirstChild("Progress")
		if progressFrame then
			if hasCard then
				progressFrame.Visible = true
				
				-- Update progress text
				local progressText = progressFrame:FindFirstChild("TxtValue")
				if progressText then
					local nextLevelCost = CardLevels.GetLevelCost(cardLevel + 1)
					if nextLevelCost then
						progressText.Text = cardCount .. " / " .. nextLevelCost.requiredCount
					else
						progressText.Text = cardCount .. " / MAX"
					end
				end
			else
				progressFrame.Visible = false
			end
		end
	end
	
	-- Update card image
	local cardContent = cardInstance:FindFirstChild("Content")
	if cardContent then
		local imgHero = cardContent:FindFirstChild("ImgHero")
		if imgHero then
			local imageId
			if hasCard then
				imageId = Manifest.CardImages[cardData.id]
			else
				imageId = Manifest.CardImagesDisabled[cardData.id]
			end
			
			if imageId then
				imgHero.Image = imageId
			end
		end
	end
	
	-- Update overlay visibility
	local overlay = cardInstance:FindFirstChild("Content")
	if overlay then
		overlay = overlay:FindFirstChild("Overlay")
		if overlay then
			overlay.Visible = hasCard
		end
	end
	
	-- Update stats display
	if hasCard then
		local stats = CardStats.ComputeStats(cardData.id, cardLevel)
		
		-- Update attack
		local attackFrame = cardInstance:FindFirstChild("Content")
		if attackFrame then
			attackFrame = attackFrame:FindFirstChild("Attack")
			if attackFrame then
				attackFrame.Visible = true
				local attackValue = attackFrame:FindFirstChild("Value")
				if attackValue then
					attackValue = attackValue:FindFirstChild("TxtValue")
					if attackValue then
						attackValue.Text = tostring(stats.atk)
					end
				end
			end
		end
		
		-- Update defense
		local defenseFrame = cardInstance:FindFirstChild("Content")
		if defenseFrame then
			defenseFrame = defenseFrame:FindFirstChild("Defense")
			if defenseFrame then
				if stats.defence > 0 then
					defenseFrame.Visible = true
					local defenseValue = defenseFrame:FindFirstChild("Value")
					if defenseValue then
						defenseValue = defenseValue:FindFirstChild("TxtValue")
						if defenseValue then
							defenseValue.Text = tostring(stats.defence)
						end
					end
				else
					defenseFrame.Visible = false
				end
			end
		end
		
		-- Update health
		local healthFrame = cardInstance:FindFirstChild("Content")
		if healthFrame then
			healthFrame = healthFrame:FindFirstChild("Health")
			if healthFrame then
				healthFrame.Visible = true
				local healthValue = healthFrame:FindFirstChild("Value")
				if healthValue then
					healthValue = healthValue:FindFirstChild("TxtValue")
					if healthValue then
						healthValue.Text = tostring(stats.hp)
					end
				end
			end
		end
	else
		-- Hide stats for unowned cards
		local attackFrame = cardInstance:FindFirstChild("Content")
		if attackFrame then
			attackFrame = attackFrame:FindFirstChild("Attack")
			if attackFrame then
				attackFrame.Visible = false
			end
		end
		
		local defenseFrame = cardInstance:FindFirstChild("Content")
		if defenseFrame then
			defenseFrame = defenseFrame:FindFirstChild("Defense")
			if defenseFrame then
				defenseFrame.Visible = false
			end
		end
		
		local healthFrame = cardInstance:FindFirstChild("Content")
		if healthFrame then
			healthFrame = healthFrame:FindFirstChild("Health")
			if healthFrame then
				healthFrame.Visible = false
			end
		end
	end
end

function DeckHandler:OnCollectionCardClicked(cardId)
	
	-- Get CardInfoHandler reference if not already set
	if not self.CardInfoHandler then
		self.CardInfoHandler = self.Controller:GetCardInfoHandler()
	end
	
	-- Show card info
	if self.CardInfoHandler and self.CardInfoHandler.ShowCardInfo then
		self.CardInfoHandler:ShowCardInfo(cardId, nil)
	else
		warn("DeckHandler: CardInfoHandler not available")
	end
end

function DeckHandler:OnDeckCardClicked(cardId, slotIndex)
	
	-- Get CardInfoHandler reference if not already set
	if not self.CardInfoHandler then
		self.CardInfoHandler = self.Controller:GetCardInfoHandler()
	end
	
	-- Show card info
	if self.CardInfoHandler and self.CardInfoHandler.ShowCardInfo then
		self.CardInfoHandler:ShowCardInfo(cardId, slotIndex)
	else
		warn("DeckHandler: CardInfoHandler not available")
	end
end

function DeckHandler:OpenWindow()
	
	if self.isAnimating then 
		return 
	end
	self.isAnimating = true

	-- Load profile data if not available
	if not self.currentProfile then
		if not self:LoadProfileData() then
			-- Profile not available yet, wait for ProfileUpdated event
			self.isAnimating = false
			return
		end
	end

	-- Hide HUD panels if they exist
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = false
	else
	end
	
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = false
	else
	end

	-- Update displays
	self:UpdateCollectionDisplay()
	self:UpdateDeckDisplay()

	-- Show deck frame
	if self.DeckFrame then
		self.DeckFrame.Visible = true
		
		-- Register with close button handler
		self:RegisterWithCloseButton(true)
	else
		warn("DeckHandler: DeckFrame is nil!")
		self.isAnimating = false
		return
	end

	-- Use TweenUI if available, otherwise just show
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
			self.Utilities.TweenUI.FadeIn(self.DeckFrame, .3, function ()
				self.isAnimating = false
			end)
		else
			self.isAnimating = false
		end
		
		if self.Utilities.Blur and self.Utilities.Blur.Show then
			self.Utilities.Blur.Show()
		else
		end
	else
		-- Fallback: no animation
		self.isAnimating = false
	end
	
	print("✅ DeckHandler: Deck window opened successfully")
end

function DeckHandler:CloseWindow()
	if self.isAnimating then return end
	self.isAnimating = true

	-- Hide deck gui
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
			self.Utilities.TweenUI.FadeOut(self.DeckFrame, .3, function () 
				self.DeckFrame.Visible = false
				self.isAnimating = false
			end)
		end
		if self.Utilities.Blur then
			self.Utilities.Blur.Hide()
		end
	else
		-- Fallback: no animation
		self.DeckFrame.Visible = false
		self.isAnimating = false
	end

	-- Show HUD panels
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = true
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = true
	end
	
	-- Register with close button handler
	self:RegisterWithCloseButton(false)
	
	print("✅ DeckHandler: Deck window closed")
end

function DeckHandler:SetupProfileUpdatedHandler()
	-- Listen for ProfileUpdated events to handle profile changes
	local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
	
	local connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
		-- Check if this is a profile update (not an error)
		if not payload.error then
			
			-- Initialize profile if not exists
			if not self.currentProfile then
				self.currentProfile = {
					deck = {},
					collection = {},
					currencies = { soft = 0, hard = 0 }
				}
			end
			
			-- Update deck
			if payload.deck then
				self.currentProfile.deck = payload.deck
			end
			
			-- Update collection from collectionSummary
			if payload.collectionSummary then
				-- Convert collectionSummary array to collection map
				self.currentProfile.collection = {}
				for _, entry in ipairs(payload.collectionSummary) do
					self.currentProfile.collection[entry.cardId] = {
						count = entry.count,
						level = entry.level
					}
				end
			end
			
			-- Update currencies if available
			if payload.currencies then
				self.currentProfile.currencies = payload.currencies
			end
			
			-- Always update collection display if collection changed (even if window is closed)
			-- This ensures new cards from lootboxes are immediately visible when opening the deck
			if payload.collectionSummary and self.DeckFrame then
				local cardCount = #payload.collectionSummary
				print("✅ DeckHandler: Updating collection display with", cardCount, "unique cards")
				self:UpdateCollectionDisplay()
			end
			
			-- Update deck display if window is open
			if self.DeckFrame and self.DeckFrame.Visible then
				self:UpdateDeckDisplay()
			end
		else
		end
	end)
	
	-- Store connection for cleanup
	table.insert(self.Connections, connection)
end

--// Public Methods
function DeckHandler:IsInitialized()
	return self._initialized
end

-- Debug function to manually open deck window
function DeckHandler:DebugOpenWindow()
	
	if self.DeckFrame then
	end
	
	if self.UI then
		if self.UI.LeftPanel then
		end
		if self.UI.BottomPanel then
		end
	end
	
	self:OpenWindow()
end

-- Register with close button handler
function DeckHandler:RegisterWithCloseButton(isOpen)
	local success, CloseButtonHandler = pcall(function()
		return require(game.ReplicatedStorage.ClientModules.CloseButtonHandler)
	end)
	
	if success and CloseButtonHandler then
		local instance = CloseButtonHandler.GetInstance()
		if instance and instance.isInitialized then
			if isOpen then
				instance:RegisterFrameOpen("Deck")
			else
				instance:RegisterFrameClosed("Deck")
			end
		end
	end
end

-- Close the deck frame (called by close button handler)
function DeckHandler:CloseFrame()
	if self.DeckFrame and self.DeckFrame.Visible then
		self:CloseWindow()
	end
end

--// Cleanup
function DeckHandler:Cleanup()

	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}

	self._initialized = false
	print("✅ DeckHandler cleaned up")
end

return DeckHandler
