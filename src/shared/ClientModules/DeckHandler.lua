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
	self.Utilities = controller:GetModule("Utilities")
	
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
	
	print("DeckHandler: Looking for UI in PlayerGui...")
	
	-- Debug: Print all children in PlayerGui
	print("Available children in PlayerGui:")
	for _, child in pairs(playerGui:GetChildren()) do
		print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
	end
	
	-- Wait for Roblox to automatically clone GameUI from StarterGui
	local gameGui = playerGui:WaitForChild("GameUI", 10) -- Wait up to 10 seconds
	
	if not gameGui then
		warn("DeckHandler: GameUI not found in PlayerGui after waiting")
		return
	end
	
	print("DeckHandler: Found GameUI: " .. tostring(gameGui))
	
	-- Look for Deck frame
	local deckFrame = gameGui:FindFirstChild("Deck")
	if not deckFrame then
		warn("DeckHandler: Deck frame not found in " .. gameGui.Name)
		print("Available children in " .. gameGui.Name .. ":")
		for _, child in pairs(gameGui:GetChildren()) do
			print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
		end
		return
	end
	
	print("DeckHandler: Deck frame found, setting up handlers...")
	
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
	print("DeckHandler: Looking for deck button...")
	
	local leftPanel = self.UI:FindFirstChild("LeftPanel")
	if not leftPanel then
		warn("DeckHandler: LeftPanel not found in GameUI")
		return
	end
	
	print("DeckHandler: LeftPanel found, looking for BtnDeck...")
	local deckButton = leftPanel:FindFirstChild("BtnDeck")
	if not deckButton then
		warn("DeckHandler: BtnDeck not found in LeftPanel")
		return
	end
	
	print("DeckHandler: Deck button found: " .. deckButton.Name .. " (" .. deckButton.ClassName .. ")")
	
	-- Test if the button has the right events
	if deckButton:IsA("GuiButton") then
		local connection = deckButton.MouseButton1Click:Connect(function()
			print("DeckHandler: Deck button clicked!")
			self:OpenWindow()
		end)
		table.insert(self.Connections, connection)
		print("✅ DeckHandler: Open button connected")
	else
		warn("DeckHandler: Found element '" .. deckButton.Name .. "' but it's not a GuiButton (it's a " .. deckButton.ClassName .. ")")
	end
end

function DeckHandler:SetupCloseButton()
	-- Look for close button in the deck frame
	-- Path: GameUI.Deck.TopPanel.BtnClose.Button
	local closeButton = self.DeckFrame:FindFirstChild("TopPanel")
	if closeButton then
		closeButton = closeButton:FindFirstChild("BtnClose")
		if closeButton then
			closeButton = closeButton:FindFirstChild("Button")
		end
	end
	
	if not closeButton then
		warn("DeckHandler: Close button not found - you may need to add a CloseButton to Deck frame")
		return
	end

	local connection = closeButton.MouseButton1Click:Connect(function()
		self:CloseWindow()
	end)

	table.insert(self.Connections, connection)
	print("✅ DeckHandler: Close button connected")
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
			print("DeckHandler: Loaded profile data")
			return true
		end
	end
	
	-- Request profile from server if not available
	print("DeckHandler: Requesting profile from server...")
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
	
	-- Get all cards from catalog, sorted by slot number
	local allCards = CardCatalog.GetCardsSortedBySlot()
	
	-- Create collection cards
	for _, cardData in ipairs(allCards) do
		local cardInstance = self:CreateCollectionCard(cardData)
		if cardInstance then
			cardInstance.Parent = self.CollectionContainer
		end
	end
	
	print("✅ DeckHandler: Collection display updated")
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
	local connection = cardButton.MouseButton1Click:Connect(function()
		self:OnCollectionCardClicked(cardData.id)
	end)
	table.insert(self.Connections, connection)
	
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
	local connection = cardInstance.MouseButton1Click:Connect(function()
		self:OnDeckCardClicked(cardData.id, slotIndex)
	end)
	table.insert(self.Connections, connection)
	
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
	
	-- Update hero image
	local heroImage = cardInstance:FindFirstChild("Content")
	if heroImage then
		heroImage = heroImage:FindFirstChild("ImgHero")
		if heroImage then
			local imageId
			if hasCard then
				-- Use normal image if player has the card
				imageId = Manifest.CardImages[cardData.id]
			else
				-- Use disabled image if player doesn't have the card
				imageId = Manifest.CardImagesDisabled[cardData.id]
			end
			
			if imageId then
				heroImage.Image = imageId
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
	print("DeckHandler: Collection card clicked: " .. cardId)
	-- TODO: Implement card selection logic for deck building
end

function DeckHandler:OnDeckCardClicked(cardId, slotIndex)
	print("DeckHandler: Deck card clicked: " .. cardId .. " in slot " .. slotIndex)
	-- TODO: Implement card removal from deck
end

function DeckHandler:OpenWindow()
	if self.isAnimating then return end
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
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = false
	end

	-- Update displays
	self:UpdateCollectionDisplay()
	self:UpdateDeckDisplay()

	-- Show deck frame
	self.DeckFrame.Visible = true

	-- Use TweenUI if available, otherwise just show
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
			self.Utilities.TweenUI.FadeIn(self.DeckFrame, .3, function ()
				self.isAnimating = false
			end)
		end
		if self.Utilities.Blur then
			self.Utilities.Blur.Show()
		end
	else
		-- Fallback: no animation
		self.isAnimating = false
	end
	
	print("✅ DeckHandler: Deck window opened")
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
	
	print("✅ DeckHandler: Deck window closed")
end

function DeckHandler:SetupProfileUpdatedHandler()
	-- Listen for ProfileUpdated events to handle profile changes
	local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
	
	local connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
		-- Check if this is a profile update (not an error)
		if not payload.error then
			print("DeckHandler: Received profile update")
			
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
			
			-- Update displays if window is open
			if self.DeckFrame and self.DeckFrame.Visible then
				self:UpdateCollectionDisplay()
				self:UpdateDeckDisplay()
			end
		else
			print("DeckHandler: Received profile error:", payload.error.message or payload.error.code)
		end
	end)
	
	-- Store connection for cleanup
	table.insert(self.Connections, connection)
end

--// Public Methods
function DeckHandler:IsInitialized()
	return self._initialized
end

--// Cleanup
function DeckHandler:Cleanup()
	print("Cleaning up DeckHandler...")

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
