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
local CardInfoHandler = {}

--// State
CardInfoHandler.Connections = {}
CardInfoHandler._initialized = false

CardInfoHandler.isAnimating = false
CardInfoHandler.currentProfile = nil
CardInfoHandler.currentCardId = nil
CardInfoHandler.currentSlotIndex = nil

--// Initialization
function CardInfoHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	self.Utilities = controller:GetModule("Utilities")
	
	-- Initialize state
	self.Connections = {}
	self.currentProfile = nil
	self.currentCardId = nil
	self.currentSlotIndex = nil

	-- Setup Card Info functionality
	self:SetupCardInfo()

	self._initialized = true
	print("✅ CardInfoHandler initialized successfully!")
	return true
end

function CardInfoHandler:SetupCardInfo()
	-- Access UI from player's PlayerGui (which should be copied from StarterGui)
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	print("CardInfoHandler: Looking for UI in PlayerGui...")
	
	-- Debug: Print all children in PlayerGui
	print("Available children in PlayerGui:")
	for _, child in pairs(playerGui:GetChildren()) do
		print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
	end
	
	-- Wait for Roblox to automatically clone GameUI from StarterGui
	local gameGui = playerGui:WaitForChild("GameUI", 10) -- Wait up to 10 seconds
	
	if not gameGui then
		warn("CardInfoHandler: GameUI not found in PlayerGui after waiting")
		return
	end
	
	print("CardInfoHandler: Found GameUI: " .. tostring(gameGui))
	
	-- Look for CardInfo frame
	local cardInfoFrame = gameGui:FindFirstChild("CardInfo")
	if not cardInfoFrame then
		warn("CardInfoHandler: CardInfo frame not found in " .. gameGui.Name)
		print("Available children in " .. gameGui.Name .. ":")
		for _, child in pairs(gameGui:GetChildren()) do
			print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
		end
		return
	end
	
	print("CardInfoHandler: CardInfo frame found, setting up handlers...")
	
	-- Store UI reference for later use
	self.UI = gameGui
	self.CardInfoFrame = cardInfoFrame
	
	-- Hide card info initially
	cardInfoFrame.Visible = false
	
	-- Setup card info functionality
	self:SetupCloseButton()
	self:SetupActionButtons()
	
	-- Setup ProfileUpdated event handler
	self:SetupProfileUpdatedHandler()
	
	print("✅ CardInfoHandler: CardInfo UI setup completed")
end

function CardInfoHandler:SetupCloseButton()
	-- Look for close button in the card info frame
	-- Path: GameUI.CardInfo.TopPanel.BtnClose.Button
	local topPanel = self.CardInfoFrame:FindFirstChild("TopPanel")
	if topPanel then
		local btnClose = topPanel:FindFirstChild("BtnClose")
		if btnClose then
			local closeButton = btnClose:FindFirstChild("Button")
			if closeButton then
				local connection = closeButton.MouseButton1Click:Connect(function()
					self:CloseWindow()
				end)
				table.insert(self.Connections, connection)
				print("✅ CardInfoHandler: Close button connected")
				return
			end
		end
	end
	
	warn("CardInfoHandler: Close button not found - you may need to add a CloseButton to CardInfo frame")
end

function CardInfoHandler:SetupActionButtons()
	-- Setup buttons for card actions
	local buttons = self.CardInfoFrame:FindFirstChild("Buttons")
	if not buttons then
		warn("CardInfoHandler: Buttons container not found")
		return
	end
	
	-- Collection button
	local btnCollection = buttons:FindFirstChild("BtnCollection")
	if btnCollection then
		local connection = btnCollection.MouseButton1Click:Connect(function()
			self:OnCollectionButtonClicked()
		end)
		table.insert(self.Connections, connection)
		print("✅ CardInfoHandler: Collection button connected")
	end
	
	-- Deck button
	local btnDeck = buttons:FindFirstChild("BtnDeck")
	if btnDeck then
		local connection = btnDeck.MouseButton1Click:Connect(function()
			self:OnDeckButtonClicked()
		end)
		table.insert(self.Connections, connection)
		print("✅ CardInfoHandler: Deck button connected")
	end
	
	-- Level up button
	local btnLevelUp = buttons:FindFirstChild("BtnLevelUp")
	if btnLevelUp then
		local connection = btnLevelUp.MouseButton1Click:Connect(function()
			self:OnLevelUpButtonClicked()
		end)
		table.insert(self.Connections, connection)
		print("✅ CardInfoHandler: Level up button connected")
	end
end

function CardInfoHandler:LoadProfileData()
	-- Load profile data from client state
	if self.ClientState and self.ClientState.GetState then
		local state = self.ClientState:GetState()
		if state and state.profile then
			self.currentProfile = state.profile
			print("CardInfoHandler: Loaded profile data")
			return true
		end
	end
	
	-- Request profile from server if not available
	print("CardInfoHandler: Requesting profile from server...")
	NetworkClient.requestProfile()
	return false
end

function CardInfoHandler:ShowCardInfo(cardId, slotIndex)
	-- Load profile data if not available
	if not self.currentProfile then
		if not self:LoadProfileData() then
			-- Profile not available yet, wait for ProfileUpdated event
			return
		end
	end
	
	self.currentCardId = cardId
	self.currentSlotIndex = slotIndex
	
	-- Get card data
	local cardData = CardCatalog.GetCard(cardId)
	if not cardData then
		warn("CardInfoHandler: Invalid card ID: " .. cardId)
		return
	end
	
	-- Get collection data for this card
	local collectionEntry = self.currentProfile.collection and self.currentProfile.collection[cardId]
	local hasCard = collectionEntry ~= nil
	local cardLevel = hasCard and collectionEntry.level or 0
	local cardCount = hasCard and collectionEntry.count or 0
	
	-- Update card info display
	self:UpdateCardInfoDisplay(cardData, hasCard, cardLevel, cardCount)
	
	-- Show the window
	self:OpenWindow()
end

function CardInfoHandler:UpdateCardInfoDisplay(cardData, hasCard, cardLevel, cardCount)
	if not self.CardInfoFrame then
		return
	end
	
	-- Get rarity info
	local rarityKey = cardData.rarity:gsub("^%l", string.upper) -- Capitalize first letter
	local rarityColors = hasCard and Manifest.RarityColors or Manifest.RarityColorsDisabled
	local rarityGradientColors = Manifest.RarityColorsGradient
	
	-- Update header
	self:UpdateHeader(cardData, Manifest.RarityColors, rarityGradientColors)
	
	-- Update level section
	self:UpdateLevelSection(cardData, hasCard, cardLevel, cardCount, rarityColors)
	
	-- Update progress section
	self:UpdateProgressSection(cardData, hasCard, cardLevel, cardCount)
	
	-- Update card image
	self:UpdateCardImage(cardData, hasCard)
	
	-- Update rarity section
	self:UpdateRaritySection(cardData, Manifest.RarityColors)
	
	-- Update parameters (attack, health, defense)
	self:UpdateParameters(cardData, hasCard, cardLevel, Manifest.RarityColors)
	
	-- Update buttons
	self:UpdateButtons(cardData, hasCard, cardLevel, cardCount)
end

function CardInfoHandler:UpdateHeader(cardData, rarityColors, rarityGradientColors)
	-- Update character name
	local mainContent = self.CardInfoFrame:FindFirstChild("Main")
	if mainContent then
		local content = mainContent:FindFirstChild("Content")
		if content then
			local header = content:FindFirstChild("Header")
			if header then
				local headerContent = header:FindFirstChild("Content")
				if headerContent then
					local textLabel = headerContent:FindFirstChild("Text")
					if textLabel then
						local textLabelChild = textLabel:FindFirstChild("TextLabel")
						if textLabelChild then
							textLabelChild.Text = cardData.name
						end
					end
					
					-- Update header gradient
					local uiGradient = headerContent:FindFirstChild("UIGradient")
					if uiGradient then
						local rarityKey = cardData.rarity:gsub("^%l", string.upper)
						uiGradient.Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, rarityColors[rarityKey] or Color3.new(1, 1, 1)),
							ColorSequenceKeypoint.new(1, rarityGradientColors[rarityKey] or Color3.new(0.5, 0.5, 0.5))
						})
					end
				end
			end
		end
		
		-- Update main frame gradient
		local uiGradient = mainContent:FindFirstChild("UIGradient")
		if uiGradient then
			local rarityKey = cardData.rarity:gsub("^%l", string.upper)
			uiGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, rarityColors[rarityKey] or Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, rarityGradientColors[rarityKey] or Color3.new(0.5, 0.5, 0.5))
			})
		end
	end
end

function CardInfoHandler:UpdateLevelSection(cardData, hasCard, cardLevel, cardCount, rarityColors)
	local mainContent = self.CardInfoFrame:FindFirstChild("Main")
	if not mainContent then return end
	
	local content = mainContent:FindFirstChild("Content")
	if not content then return end

	content = content:FindFirstChild("Content")
	if not content then return end
	
	local levelSection = content:FindFirstChild("Level")
	if not levelSection then return end
	
	-- Update level text
	local txtValue = levelSection:FindFirstChild("TxtValue")
	if txtValue then
		txtValue.Text = tostring(cardLevel)
	end
	
	-- Update level icons
	local imgLevelUp = levelSection:FindFirstChild("ImgLevelUp")
	local imgMax = levelSection:FindFirstChild("ImgMax")
	
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
	
	-- Update background color based on rarity and ownership
	local rarityKey = cardData.rarity:gsub("^%l", string.upper)
	levelSection.BackgroundColor3 = rarityColors[rarityKey] or Color3.new(1, 1, 1)
end

function CardInfoHandler:UpdateProgressSection(cardData, hasCard, cardLevel, cardCount)
	local mainContent = self.CardInfoFrame:FindFirstChild("Main")
	if not mainContent then return end
	
	local content = mainContent:FindFirstChild("Content")
	if not content then return end

	content = content:FindFirstChild("Content")
	if not content then return end
	
	local progressSection = content:FindFirstChild("Progress")
	if not progressSection then return end
	
	local txtValue = progressSection:FindFirstChild("TxtValue")
	if txtValue then
		if cardLevel >= 10 then
			txtValue.Text = "Max level"
		else
			local nextLevelCost = CardLevels.GetLevelCost(cardLevel + 1)
			if nextLevelCost then
				txtValue.Text = "To level up:\n" .. cardCount .. " / " .. nextLevelCost.requiredCount
			else
				txtValue.Text = "Max level"
			end
		end
	end
end

function CardInfoHandler:UpdateCardImage(cardData, hasCard)
	local mainContent = self.CardInfoFrame:FindFirstChild("Main")
	if not mainContent then return end
	
	local content = mainContent:FindFirstChild("Content")
	if not content then return end

	content = content:FindFirstChild("Content")
	if not content then return end
	
	local cardSection = content:FindFirstChild("Card")
	if not cardSection then return end
	
	-- Update background color based on rarity and ownership
	local rarityKey = cardData.rarity:gsub("^%l", string.upper)
	local rarityColors = hasCard and Manifest.RarityColors or Manifest.RarityColorsDisabled
	cardSection.BackgroundColor3 = rarityColors[rarityKey] or Color3.new(1, 1, 1)
	
	-- Update card image
	local cardContent = cardSection:FindFirstChild("Content")
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
end

function CardInfoHandler:UpdateRaritySection(cardData, rarityColors)
	local mainContent = self.CardInfoFrame:FindFirstChild("Main")
	if not mainContent then return end
	
	local content = mainContent:FindFirstChild("Content")
	if not content then return end

	content = content:FindFirstChild("Content")
	if not content then return end
	
	local raritySection = content:FindFirstChild("Rarity")
	if not raritySection then return end
	
	-- Update rarity background color
	local imgRarity = raritySection:FindFirstChild("ImgRarity")
	if imgRarity then
		local rarityKey = cardData.rarity:gsub("^%l", string.upper)
		imgRarity.BackgroundColor3 = rarityColors[rarityKey] or Color3.new(1, 1, 1)
	end
	
	-- Update rarity text
	local txtRarity = raritySection:FindFirstChild("TxtRarity")
	if txtRarity then
		-- Map rarity to display name
		local rarityDisplayNames = {
			["Uncommon"] = "Uncommon",
			["Rare"] = "Rare", 
			["Epic"] = "Epic",
			["Legendary"] = "Legendary"
		}
		txtRarity.Text = rarityDisplayNames[rarityKey] or cardData.rarity
	end
end

function CardInfoHandler:UpdateParameters(cardData, hasCard, cardLevel, rarityColors)
	if not hasCard then
		-- Hide all parameters for unowned cards
		self:SetParameterVisibility("Attack", false)
		self:SetParameterVisibility("Health", false)
		self:SetParameterVisibility("Defense", false)
		return
	end
	
	local currentStats = CardStats.ComputeStats(cardData.id, cardLevel)
	local nextLevelStats = CardLevels.CanLevelUp(cardData.id, cardLevel, self.currentProfile.collection[cardData.id].count, self.currentProfile.currencies.soft)
	
	if nextLevelStats then
		nextLevelStats = CardStats.ComputeStats(cardData.id, cardLevel + 1)
	end
	
	local canLevelUp = nextLevelStats ~= nil
	
	-- Update Attack
	self:UpdateParameter("Attack", currentStats.atk, nextLevelStats and nextLevelStats.atk, canLevelUp, rarityColors)
	
	-- Update Health
	self:UpdateParameter("Health", currentStats.hp, nextLevelStats and nextLevelStats.hp, canLevelUp, rarityColors)
	
	-- Update Defense
	self:UpdateParameter("Defense", currentStats.defence, nextLevelStats and nextLevelStats.defence, canLevelUp, rarityColors)
end

function CardInfoHandler:UpdateParameter(paramName, currentValue, nextValue, canLevelUp, rarityColors)
	local mainContent = self.CardInfoFrame:FindFirstChild("Main")
	if not mainContent then return end
	
	local content = mainContent:FindFirstChild("Content")
	if not content then return end

	content = content:FindFirstChild("Content")
	if not content then return end
	
	local params = content:FindFirstChild("Params")
	if not params then return end
	
	local paramSection = params:FindFirstChild(paramName)
	if not paramSection then return end
	
	local values = paramSection:FindFirstChild("Values")
	if not values then return end
	
	-- Update current value
	local txtValue = values:FindFirstChild("TxtValue")
	if txtValue then
		txtValue.Text = tostring(currentValue)
	end
	
	-- Update next value (if level up is available)
	local txtNewValue = values:FindFirstChild("TxtNewValue")
	local txtArrow = values:FindFirstChild("TxtArrow")
	
	if txtNewValue and txtArrow then
		if canLevelUp and nextValue then
			txtNewValue.Text = tostring(nextValue)
			txtNewValue.Visible = true
			txtArrow.Visible = true
			
			-- Set color based on rarity
			local rarityKey = self:GetCurrentCardRarity()
			if rarityColors[rarityKey] then
				txtNewValue.TextColor3 = rarityColors[rarityKey]
			end
		else
			txtNewValue.Visible = false
			txtArrow.Visible = false
		end
	end
end

function CardInfoHandler:SetParameterVisibility(paramName, visible)
	local mainContent = self.CardInfoFrame:FindFirstChild("Main")
	if not mainContent then return end
	
	local content = mainContent:FindFirstChild("Content")
	if not content then return end

	content = content:FindFirstChild("Content")
	if not content then return end
	
	local params = content:FindFirstChild("Params")
	if not params then return end
	
	local paramSection = params:FindFirstChild(paramName)
	if paramSection then
		paramSection.Visible = visible
	end
end

function CardInfoHandler:UpdateButtons(cardData, hasCard, cardLevel, cardCount)
	local buttons = self.CardInfoFrame:FindFirstChild("Buttons")
	if not buttons then return end
	
	-- Check if card is in collection
	local isInCollection = hasCard
	
	-- Check if card is in deck
	local isInDeck = false
	if self.currentProfile.deck then
		for _, deckCardId in pairs(self.currentProfile.deck) do
			if deckCardId == cardData.id then
				isInDeck = true
				break
			end
		end
	end
	
	-- Check if can level up
	local canLevelUp = false
	if hasCard then
		canLevelUp = CardLevels.CanLevelUp(cardData.id, cardLevel, cardCount, self.currentProfile.currencies.soft)
	end
	
	-- Update Collection button (show if card is in deck and can be removed)
	local btnCollection = buttons:FindFirstChild("BtnCollection")
	if btnCollection then
		btnCollection.Visible = isInCollection and isInDeck
	end
	
	-- Update Deck button (show if card is in collection but not in deck)
	local btnDeck = buttons:FindFirstChild("BtnDeck")
	if btnDeck then
		btnDeck.Visible = isInCollection and not isInDeck
	end
	
	-- Update Level Up button
	local btnLevelUp = buttons:FindFirstChild("BtnLevelUp")
	if btnLevelUp then
		btnLevelUp.Visible = canLevelUp
		
		-- Update level up cost text
		local bevel = btnLevelUp:FindFirstChild("Bevel")
		if bevel then
			local main = bevel:FindFirstChild("Main")
			if main then
				local txtValue = main:FindFirstChild("TxtValue")
				if txtValue and hasCard then
					local levelUpCost = CardLevels.GetLevelUpCost(cardData.id, cardLevel, cardCount, self.currentProfile.currencies.soft)
					if levelUpCost then
						txtValue.Text = tostring(levelUpCost.softAmount)
					end
				end
			end
		end
	end
end

function CardInfoHandler:GetCurrentCardRarity()
	if not self.currentCardId then return "Uncommon" end
	
	local cardData = CardCatalog.GetCard(self.currentCardId)
	if not cardData then return "Uncommon" end
	
	return cardData.rarity:gsub("^%l", string.upper)
end

-- Helper function to check if a card is in the deck
function CardInfoHandler:IsCardInDeck(cardId)
	if not self.currentProfile or not self.currentProfile.deck then
		return false
	end
	
	for _, deckCardId in pairs(self.currentProfile.deck) do
		if deckCardId == cardId then
			return true
		end
	end
	return false
end

-- Helper function to add a card to the deck
function CardInfoHandler:AddCardToDeck(cardId)
	if not self.currentProfile then
		warn("CardInfoHandler: No profile available for deck operations")
		return false
	end
	
	-- Validate that player owns this card
	local collectionEntry = self.currentProfile.collection and self.currentProfile.collection[cardId]
	if not collectionEntry or collectionEntry.count <= 0 then
		warn("CardInfoHandler: Player does not own card:", cardId)
		return false
	end
	
	-- Check if card is already in deck
	if self:IsCardInDeck(cardId) then
		warn("CardInfoHandler: Card is already in deck:", cardId)
		return false
	end
	
	-- Get current deck
	local currentDeck = self.currentProfile.deck or {}
	
	-- Check if deck is full (max 6 cards)
	if #currentDeck >= 6 then
		warn("CardInfoHandler: Deck is full (6/6 cards). Cannot add more cards.")
		return false
	end
	
	-- Create new deck with the card added
	local newDeck = {}
	for i, deckCardId in ipairs(currentDeck) do
		newDeck[i] = deckCardId
	end
	newDeck[#newDeck + 1] = cardId
	
	-- Validate the new deck using DeckValidator
	local DeckValidator = require(game.ReplicatedStorage.Modules.Cards.DeckValidator)
	local isValid, errorMessage = DeckValidator.ValidateDeck(newDeck)
	if not isValid then
		warn("CardInfoHandler: New deck would be invalid:", errorMessage)
		return false
	end
	
	-- Additional validation: Check if deck would exceed 6 cards (should not happen due to earlier check, but safety)
	if #newDeck > 6 then
		warn("CardInfoHandler: Deck would exceed maximum size (6 cards)")
		return false
	end
	
	-- Request deck update via network
	print("CardInfoHandler: Adding card to deck:", cardId)
	if NetworkClient and NetworkClient.requestSetDeck then
		local success, error = NetworkClient.requestSetDeck(newDeck)
		if success then
			print("CardInfoHandler: Successfully requested to add card to deck")
			-- The UI will update automatically when ProfileUpdated event is received
			return true
		else
			warn("CardInfoHandler: Failed to request deck update:", error)
			-- TODO: Show user-friendly error message
			return false
		end
	else
		warn("CardInfoHandler: NetworkClient.requestSetDeck not available")
		return false
	end
end

-- Helper function to remove a card from the deck
function CardInfoHandler:RemoveCardFromDeck(cardId)
	if not self.currentProfile then
		warn("CardInfoHandler: No profile available for deck operations")
		return false
	end
	
	-- Check if card is in deck
	if not self:IsCardInDeck(cardId) then
		warn("CardInfoHandler: Card is not in deck:", cardId)
		return false
	end
	
	-- Get current deck and remove the card
	local currentDeck = self.currentProfile.deck or {}
	local newDeck = {}
	
	for i, deckCardId in ipairs(currentDeck) do
		if deckCardId ~= cardId then
			newDeck[#newDeck + 1] = deckCardId
		end
	end
	
	-- Note: Deck can have less than 6 cards, so we don't validate size here
	-- But we still validate the structure
	local DeckValidator = require(game.ReplicatedStorage.Modules.Cards.DeckValidator)
	local isValid, errorMessage = DeckValidator.ValidateDeck(newDeck)
	if not isValid then
		warn("CardInfoHandler: New deck would be invalid:", errorMessage)
		return false
	end
	
	-- Request deck update via network
	print("CardInfoHandler: Removing card from deck:", cardId)
	if NetworkClient and NetworkClient.requestSetDeck then
		local success, error = NetworkClient.requestSetDeck(newDeck)
		if success then
			print("CardInfoHandler: Successfully requested to remove card from deck")
			-- The UI will update automatically when ProfileUpdated event is received
			return true
		else
			warn("CardInfoHandler: Failed to request deck update:", error)
			-- TODO: Show user-friendly error message
			return false
		end
	else
		warn("CardInfoHandler: NetworkClient.requestSetDeck not available")
		return false
	end
end

function CardInfoHandler:OnCollectionButtonClicked()
	if not self.currentCardId then
		warn("CardInfoHandler: No current card selected for collection action")
		return
	end
	
	print("CardInfoHandler: Collection button clicked for card:", self.currentCardId)
	
	-- Remove card from deck if it's currently in the deck
	if self:IsCardInDeck(self.currentCardId) then
		self:RemoveCardFromDeck(self.currentCardId)
	else
		print("CardInfoHandler: Card is not in deck, no action needed")
	end
end

function CardInfoHandler:OnDeckButtonClicked()
	if not self.currentCardId then
		warn("CardInfoHandler: No current card selected for deck action")
		return
	end
	
	print("CardInfoHandler: Deck button clicked for card:", self.currentCardId)
	
	-- Add card to deck if it's not already in the deck
	if not self:IsCardInDeck(self.currentCardId) then
		self:AddCardToDeck(self.currentCardId)
	else
		print("CardInfoHandler: Card is already in deck, no action needed")
	end
end

function CardInfoHandler:OnLevelUpButtonClicked()
	if not self.currentCardId then
		warn("CardInfoHandler: No current card selected for level up action")
		return
	end
	
	print("CardInfoHandler: Level up button clicked for card:", self.currentCardId)
	
	-- Get current card data for validation
	local collectionEntry = self.currentProfile.collection and self.currentProfile.collection[self.currentCardId]
	if not collectionEntry then
		warn("CardInfoHandler: Card not found in collection for level up")
		return
	end
	
	local cardLevel = collectionEntry.level or 0
	local cardCount = collectionEntry.count or 0
	
	-- Check if level up is possible
	local canLevelUp, reason = CardLevels.CanLevelUp(self.currentCardId, cardLevel, cardCount, self.currentProfile.currencies.soft)
	if not canLevelUp then
		warn("CardInfoHandler: Cannot level up card:", reason)
		return
	end
	
	-- Request level up via network
	if NetworkClient and NetworkClient.requestLevelUpCard then
		NetworkClient.requestLevelUpCard(self.currentCardId)
	else
		warn("CardInfoHandler: NetworkClient.requestLevelUpCard not available")
	end
end

function CardInfoHandler:OpenWindow()
	if self.isAnimating then return end
	self.isAnimating = true

	-- Hide HUD panels if they exist
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = false
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = false
	end

	-- Show card info frame
	self.CardInfoFrame.Visible = true

	-- Use TweenUI if available, otherwise just show
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
			self.Utilities.TweenUI.FadeIn(self.CardInfoFrame, .3, function ()
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
	
	print("✅ CardInfoHandler: card info window opened")
end

function CardInfoHandler:CloseWindow()
	if self.isAnimating then return end
	self.isAnimating = true

	-- Hide card info gui
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
			self.Utilities.TweenUI.FadeOut(self.CardInfoFrame, .3, function () 
				self.CardInfoFrame.Visible = false
				self.isAnimating = false
			end)
		end
		if self.Utilities.Blur then
			self.Utilities.Blur.Hide()
		end
	else
		-- Fallback: no animation
		self.CardInfoFrame.Visible = false
		self.isAnimating = false
	end

	-- Show HUD panels
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = true
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = true
	end
	
	-- Clear current card data
	self.currentCardId = nil
	self.currentSlotIndex = nil
	
	print("✅ CardInfoHandler: card info window closed")
end

function CardInfoHandler:SetupProfileUpdatedHandler()
	-- Listen for ProfileUpdated events to handle profile changes
	local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
	
	local connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
		-- Check if this is a profile update (not an error)
		if not payload.error then
			print("CardInfoHandler: Received profile update")
			
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
			
			-- Update display if window is open and we have current card
			if self.CardInfoFrame and self.CardInfoFrame.Visible and self.currentCardId then
				local cardData = CardCatalog.GetCard(self.currentCardId)
				if cardData then
					local collectionEntry = self.currentProfile.collection[self.currentCardId]
					local hasCard = collectionEntry ~= nil
					local cardLevel = hasCard and collectionEntry.level or 0
					local cardCount = hasCard and collectionEntry.count or 0
					
					self:UpdateCardInfoDisplay(cardData, hasCard, cardLevel, cardCount)
				end
			end
		else
			print("CardInfoHandler: Received profile error:", payload.error.message or payload.error.code)
		end
	end)
	
	-- Store connection for cleanup
	table.insert(self.Connections, connection)
end

--// Public Methods
function CardInfoHandler:IsInitialized()
	return self._initialized
end

--// Cleanup
function CardInfoHandler:Cleanup()
	print("Cleaning up CardInfoHandler...")

	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}

	self._initialized = false
	print("✅ CardInfoHandler cleaned up")
end

return CardInfoHandler
