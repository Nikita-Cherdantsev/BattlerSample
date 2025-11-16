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
CardInfoHandler.originalGradientColor = nil -- Store original gradient color
CardInfoHandler.originalBevelColor = nil -- Store original bevel background color
CardInfoHandler.InputBlocker = nil -- Overlay to close card info

CardInfoHandler.isAnimating = false
CardInfoHandler.currentProfile = nil
CardInfoHandler.currentCardId = nil
CardInfoHandler.currentSlotIndex = nil

-- Local helper to show small notifications using GameUI.FollowText
function CardInfoHandler:ShowDeckNotification(message)
	-- Cache references
	if not self._notif then
		local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
		if playerGui then
			local gameUI = playerGui:FindFirstChild("GameUI")
			local followFrame = gameUI and gameUI:FindFirstChild("FollowText")
			local followLabel = followFrame and followFrame:FindFirstChildOfClass("TextLabel")
			local stroke = followLabel and followLabel:FindFirstChildOfClass("UIStroke")	

			if followFrame and followLabel and stroke then
				self._notif = {
					frame = followFrame,
					label = followLabel,
					stroke = stroke,
					token = 0
				}
			else
				-- Fallback: build a lightweight toast ScreenGui if FollowText is unavailable or hidden
				local toastGui = Instance.new("ScreenGui")
				toastGui.Name = "DeckToastGui"
				toastGui.ResetOnSpawn = false
				toastGui.IgnoreGuiInset = true
				toastGui.DisplayOrder = 1000
				toastGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
				toastGui.Parent = playerGui
				
				local frame = Instance.new("Frame")
				frame.Name = "Toast"
				frame.Size = UDim2.new(0.5, 0, 0.05, 0)
				frame.Position = UDim2.new(0.5, 0, 0.10, 0)
				frame.AnchorPoint = Vector2.new(0.5, 0)
				frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
				frame.BackgroundTransparency = 0.75
				frame.BorderSizePixel = 0
				frame.ZIndex = 1000
				frame.Visible = false
				frame.Parent = toastGui
				
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.5, 0)
				corner.Parent = frame
				
				local label = Instance.new("TextLabel")
				label.Name = "Text"
				label.Size = UDim2.new(1, -24, 1, -12)
				label.Position = UDim2.new(0, 12, 0, 6)
				label.BackgroundTransparency = 1
				label.TextColor3 = Color3.fromRGB(255, 255, 255)
				label.TextScaled = true
				label.Font = Enum.Font.Montserrat
				label.FontWeight = Enum.FontWeight.Bold
				label.ZIndex = 1001
				label.Text = ""
				label.Parent = frame

				local stroke = Instance.new("UIStroke")
				stroke.Color = Color3.fromRGB(0, 0, 0)
				stroke.Transparency = 0.75
				stroke.Thickness = 0.02
				stroke.Parent = label
				
				self._notif = {
					frame = frame,
					label = label,
					token = 0,
					_isFallback = true
				}
			end
		else
			return
		end
	end
	
	local frame = self._notif.frame
	local label = self._notif.label
	local stroke = self._notif.stroke
	self._notif.token = (self._notif.token or 0) + 1
	local token = self._notif.token
	
	-- Prepare (ensure it renders above Deck UI just like FollowReward)
	frame.ZIndex = 1000
	label.ZIndex = 1001
	frame.Visible = true
	frame.BackgroundTransparency = 1
	label.TextTransparency = 1
	stroke.Transparency = 1
	label.Text = message

	-- Fade in using TweenService (match FollowRewardHandler behaviour)
	local TweenService = game:GetService("TweenService")
	local fadeInInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(frame, fadeInInfo, { BackgroundTransparency = 0.5 }):Play()
	TweenService:Create(label, fadeInInfo, { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, fadeInInfo, { Transparency = 0.5 }):Play()

	-- Auto fade out
	task.delay(2.5, function()
		if self._notif and self._notif.token == token then
			local fadeOutInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween1 = TweenService:Create(frame, fadeOutInfo, { BackgroundTransparency = 1 })
			local tween2 = TweenService:Create(label, fadeOutInfo, { TextTransparency = 1 })
			local tween3 = TweenService:Create(stroke, fadeOutInfo, { Transparency = 1 })
			tween1:Play()
			tween2:Play()
			tween3:Play()
			tween2.Completed:Connect(function()
				if self._notif and self._notif.token == token then
					frame.Visible = false
				end
			end)
		end
	end)
end

--// Initialization
function CardInfoHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	
	-- Safe require of Utilities to avoid loading errors
	local success, utilities = pcall(function()
		return controller:GetModule("Utilities")
	end)
	
	if success then
		self.Utilities = utilities
	else
		warn("CardInfoHandler: Could not load Utilities module: " .. tostring(utilities))
		self.Utilities = {
			TweenUI = { FadeIn = function() end, FadeOut = function() end }
		}
	end
	
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
	
	
	-- Debug: Print all children in PlayerGui
	for _, child in pairs(playerGui:GetChildren()) do
	end
	
	-- Wait for Roblox to automatically clone GameUI from StarterGui
	local gameGui = playerGui:WaitForChild("GameUI", 5) -- Initial wait
	
	if not gameGui then
		gameGui = playerGui:WaitForChild("GameUI", 10) -- Extended wait
		
		if not gameGui then
			warn("CardInfoHandler: GameUI not found in PlayerGui after extended waiting")
			return
		end
	end
	
	
	-- Look for CardInfo frame
	local cardInfoFrame = gameGui:FindFirstChild("CardInfo")
	if not cardInfoFrame then
		warn("CardInfoHandler: CardInfo frame not found in " .. gameGui.Name)
		for _, child in pairs(gameGui:GetChildren()) do
		end
		return
	end
	
	
	-- Store UI reference for later use
	self.UI = gameGui
	self.CardInfoFrame = cardInfoFrame
	self.InputBlocker = cardInfoFrame:FindFirstChild("InputBlocker")
	
	-- Hide card info initially
	cardInfoFrame.Visible = false
	
	-- Setup card info functionality
	self:SetupCloseButton()
	self:SetupActionButtons()
	
	-- Store original gradient color for level up button
	self:StoreOriginalGradientColor()
	
	-- Setup ProfileUpdated event handler
	self:SetupProfileUpdatedHandler()
	
	print("✅ CardInfoHandler: CardInfo UI setup completed")
end

function CardInfoHandler:SetupCloseButton()
	local closeButton = self.CardInfoFrame and self.CardInfoFrame:FindFirstChild("Main")
	if closeButton then
		closeButton = closeButton:FindFirstChild("Content")
		if closeButton then
			closeButton = closeButton:FindFirstChild("BtnClose")
			if closeButton then
				closeButton = closeButton:FindFirstChild("Button")
			end
		end
	end
	
	if not closeButton then
		warn("CardInfoHandler: Close button not found - you may need to add a CloseButton to CardInfo frame")
		return
	end

	local connection = closeButton.MouseButton1Click:Connect(function()
		self:CloseWindow()
	end)

	table.insert(self.Connections, connection)

	if self.InputBlocker then
		local blockerConnection = self.InputBlocker.MouseButton1Click:Connect(function()
			self:CloseWindow()
		end)
		table.insert(self.Connections, blockerConnection)
	else
		warn("CardInfoHandler: InputBlocker not found")
	end

	print("✅ CardInfoHandler: Close button connected")
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

function CardInfoHandler:StoreOriginalGradientColor()
	-- Store the original gradient color and bevel color for the level up button
	local buttons = self.CardInfoFrame:FindFirstChild("Buttons")
	if not buttons then
		return
	end
	
	local btnLevelUp = buttons:FindFirstChild("BtnLevelUp")
	if btnLevelUp then
		local bevel = btnLevelUp:FindFirstChild("Bevel")
		if bevel then
			local main = bevel:FindFirstChild("Main")
			if main then
				local uiGradient = main:FindFirstChild("UIGradient")
				if uiGradient then
					-- Store the original gradient color
					self.originalGradientColor = uiGradient.Color
				end
			end
			-- Store the original bevel background color
			self.originalBevelColor = bevel.BackgroundColor3
		end
	end
	print("✅ CardInfoHandler: Original gradient and bevel colors stored")
end

function CardInfoHandler:LoadProfileData()
	-- Always refresh profile data from client state to ensure we have the latest data
	-- This is critical for deck operations to use the current deck state
	if self.ClientState and self.ClientState.getProfile then
		local profile = self.ClientState:getProfile()
		if profile then
			self.currentProfile = profile
			return true
		end
	end
	
	-- Fallback: Try GetState method (for backward compatibility)
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

function CardInfoHandler:ShowCardInfo(cardId, slotIndex)
	-- Always reload profile data from ClientState to ensure we have the latest deck
	-- This fixes the issue where deck changes weren't reflected in card operations
	if not self:LoadProfileData() then
		-- Profile not available yet, wait for ProfileUpdated event
		return
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
	
	-- Update frame stroke color
	self:UpdateFrameStrokeColor(Manifest.RarityColors[rarityKey], rarityGradientColors[rarityKey])
	
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

function CardInfoHandler:UpdateFrameStrokeColor(colorFrom, colorTo)
	local mainContent = self.CardInfoFrame:FindFirstChild("Main")
	if not mainContent then return end
	
	local uiGradient = mainContent:FindFirstChild("UIGradient")
	if uiGradient then
		uiGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, colorFrom),
			ColorSequenceKeypoint.new(1, colorTo)
		})
	end
end

function CardInfoHandler:UpdateHeader(cardData, rarityColors, rarityGradientColors)
	-- Update character name
	local mainContent = self.CardInfoFrame:FindFirstChild("Main")
	if not mainContent then return end
	
	local content = mainContent:FindFirstChild("Content")
	if not content then return end
	
	local header = content:FindFirstChild("Header")
	if not header then return end
	
	local headerContent = header:FindFirstChild("Content")
	if not headerContent then return end
	
	local text = headerContent:FindFirstChild("Text")
	if text then
		local textLabelChild = text:FindFirstChild("TextLabel")
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

function CardInfoHandler:UpdateLevelSection(cardData, hasCard, cardLevel, cardCount, rarityColors)
	local mainContent = self.CardInfoFrame:FindFirstChild("Main")
	if not mainContent then return end
	
	local content = mainContent:FindFirstChild("Content")
	if not content then return end
	
	local innerContent = content:FindFirstChild("Content")
	if not innerContent then return end
	
	local levelSection = innerContent:FindFirstChild("Level")
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
			local canLevelUp, _ = CardLevels.CanLevelUp(cardData.id, cardLevel, cardCount, self.currentProfile.currencies.soft, cardData.rarity)
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
	
	local innerContent = content:FindFirstChild("Content")
	if not innerContent then return end
	
	local progressSection = innerContent:FindFirstChild("Progress")
	if not progressSection then return end
	
	local txtValue = progressSection:FindFirstChild("TxtValue")
	if txtValue then
		if cardLevel >= 10 then
			txtValue.Text = "Max level"
		else
			local nextLevelCost = CardLevels.GetLevelCost(cardLevel + 1, cardData.rarity)
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
	
	local innerContent = content:FindFirstChild("Content")
	if not innerContent then return end
	
	local cardSection = innerContent:FindFirstChild("Card")
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
	
	local innerContent = content:FindFirstChild("Content")
	if not innerContent then return end
	
	local raritySection = innerContent:FindFirstChild("Rarity")
	if not raritySection then return end
	
	local rarityKey = cardData.rarity:gsub("^%l", string.upper)

	-- Update rarity background color
	local imgRarity = raritySection:FindFirstChild("ImgRarity")
	if imgRarity then
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
	local nextLevelStats = CardLevels.CanLevelUp(cardData.id, cardLevel, self.currentProfile.collection[cardData.id].count, self.currentProfile.currencies.soft, cardData.rarity)
	
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
	
	local innerContent = content:FindFirstChild("Content")
	if not innerContent then return end
	
	local params = innerContent:FindFirstChild("Params")
	if not params then return end
	
	local paramSection = params:FindFirstChild(paramName)
	if not paramSection then return end

	self:SetParameterVisibility(paramName, true)
	
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
	
	local innerContent = content:FindFirstChild("Content")
	if not innerContent then return end
	
	local params = innerContent:FindFirstChild("Params")
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
	
	-- Check level-up requirements separately
	local hasEnoughCards = false
	local hasEnoughSoftCurrency = false
	local canLevelUp = false
	
	if hasCard and cardLevel < 10 then
		local nextLevel = cardLevel + 1
		local cost = CardLevels.GetLevelCost(nextLevel, cardData.rarity)
		
		if cost then
			-- Check if player has enough card copies
			hasEnoughCards = cardCount >= cost.requiredCount
			
			-- Check if player has enough soft currency
			hasEnoughSoftCurrency = self.currentProfile.currencies.soft >= cost.softAmount
			
			-- Can level up only if both requirements are met
			canLevelUp = hasEnoughCards and hasEnoughSoftCurrency
		end
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
		-- Show button if player has enough cards (regardless of soft currency)
		btnLevelUp.Visible = hasEnoughCards
		
		if hasEnoughCards then
			-- Update level up cost text
			local bevel = btnLevelUp:FindFirstChild("Bevel")
			if bevel then
				local main = bevel:FindFirstChild("Main")
				if main then
					local txtValue = main:FindFirstChild("TxtValue")
					if txtValue then
						local nextLevel = cardLevel + 1
						local cost = CardLevels.GetLevelCost(nextLevel, cardData.rarity)
						if cost then
							txtValue.Text = tostring(cost.softAmount)
						end
					end
				end
				
				-- Update button state based on soft currency availability
				local uiGradient = bevel:FindFirstChild("Main"):FindFirstChild("UIGradient")
				local notEnoughEnergyLabel = bevel:FindFirstChild("NotEnoughEnergyLabel")
				
			if hasEnoughSoftCurrency then
				-- Enough soft currency: Active button with original gradient
				btnLevelUp.Active = true
				btnLevelUp.Selectable = true
				if uiGradient then
					-- Restore original gradient color
					if self.originalGradientColor then
						uiGradient.Color = self.originalGradientColor
					else
						-- Fallback to default gradient if original wasn't stored
						uiGradient.Color = ColorSequence.new{
							ColorSequenceKeypoint.new(0, Color3.new(0.2, 0.6, 1)), -- Blue
							ColorSequenceKeypoint.new(1, Color3.new(0.8, 0.9, 1))   -- Light blue/white
						}
					end
				end
				-- Set Bevel background to active color (140, 58, 0)
				bevel.BackgroundColor3 = Color3.fromRGB(140, 58, 0)
				if notEnoughEnergyLabel then
					notEnoughEnergyLabel.Visible = false
				end
			else
				-- Not enough soft currency: Inactive button with gray gradient
				btnLevelUp.Active = false
				btnLevelUp.Selectable = false
				if uiGradient then
					uiGradient.Color = ColorSequence.new(Color3.new(0.5, 0.5, 0.5)) -- Gray gradient
				end
				-- Set Bevel background to dark gray
				bevel.BackgroundColor3 = Color3.fromRGB(80, 80, 80) -- Dark gray
				if notEnoughEnergyLabel then
					notEnoughEnergyLabel.Visible = true
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

-- Helper function to sort deck by slotNumber and assign to slots 1-6
function CardInfoHandler:SortDeckBySlotNumber(deckIds)
	if not deckIds or #deckIds == 0 then
		return {}
	end
	
	local CardCatalog = require(game.ReplicatedStorage.Modules.Cards.CardCatalog)
	
	-- Create array of card data with slotNumber for sorting
	local cardData = {}
	for _, cardId in ipairs(deckIds) do
		local card = CardCatalog.GetCard(cardId)
		if card and card.slotNumber then
			table.insert(cardData, {
				cardId = cardId,
				slotNumber = card.slotNumber
			})
		else
			warn("CardInfoHandler: Card missing slotNumber:", cardId)
		end
	end
	
	-- Sort by slotNumber (ascending)
	table.sort(cardData, function(a, b)
		return a.slotNumber < b.slotNumber
	end)
	
	-- Create sorted deck array (slots 1-6 filled in order)
	local sortedDeck = {}
	for i = 1, math.min(#cardData, 6) do
		sortedDeck[i] = cardData[i].cardId
	end
	
	return sortedDeck
end

-- Helper function to add a card to the deck
function CardInfoHandler:AddCardToDeck(cardId)
	-- Always refresh profile before deck operations to ensure we have the latest deck state
	if not self:LoadProfileData() or not self.currentProfile then
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
		self:ShowDeckNotification("Your deck can contain at most 6 cards!")
		return false
	end
	
	-- Create new deck with the card added and sort by slotNumber
	local tempDeck = {}
	for i, deckCardId in ipairs(currentDeck) do
		tempDeck[i] = deckCardId
	end
	tempDeck[#tempDeck + 1] = cardId
	
	-- Sort the deck by slotNumber to maintain proper slot assignment
	local newDeck = self:SortDeckBySlotNumber(tempDeck)
	
	-- Hard cap before validation: max 6 cards
	if #newDeck > 6 then
		self:ShowDeckNotification("Your deck can contain at most 6 cards!")
		return false
	end
	
	-- Validate the new deck using DeckValidator
	local DeckValidator = require(game.ReplicatedStorage.Modules.Cards.DeckValidator)
	local isValid, errorMessage = DeckValidator.ValidateDeck(newDeck)
	if not isValid then
		warn("CardInfoHandler: New deck would be invalid:", errorMessage)
		-- Notify: bounds messages
		local msg = tostring(errorMessage)
		if msg:find("at most 6") or #newDeck > 6 then
			self:ShowDeckNotification("Your deck can contain at most 6 cards!")
		elseif msg:find("1 and 6") or msg:find("at least 1") then
			self:ShowDeckNotification("Your deck must have at least 1 card!")
		end
		return false
	end
	
	-- Additional validation: Check if deck would exceed 6 cards (should not happen due to earlier check, but safety)
	if #newDeck > 6 then
		warn("CardInfoHandler: Deck would exceed maximum size (6 cards)")
		return false
	end
	
	-- Request deck update via network
	if NetworkClient and NetworkClient.requestSetDeck then
		local success, error = NetworkClient.requestSetDeck(newDeck)
		if success then
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
	-- Always refresh profile before deck operations to ensure we have the latest deck state
	if not self:LoadProfileData() or not self.currentProfile then
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
	local tempDeck = {}
	
	for i, deckCardId in ipairs(currentDeck) do
		if deckCardId ~= cardId then
			tempDeck[#tempDeck + 1] = deckCardId
		end
	end
	
	-- Sort the remaining deck by slotNumber to maintain proper slot assignment
	local newDeck = self:SortDeckBySlotNumber(tempDeck)
	
	-- Note: Deck can have less than 6 cards, so we don't validate size here
	-- But we still validate the structure
	local DeckValidator = require(game.ReplicatedStorage.Modules.Cards.DeckValidator)
	local isValid, errorMessage = DeckValidator.ValidateDeck(newDeck)
	if not isValid then
		warn("CardInfoHandler: New deck would be invalid:", errorMessage)
		-- Notify: require at least 1 card
		if tostring(errorMessage):find("1 and 6") or tostring(errorMessage):find("at least 1") then
			self:ShowDeckNotification("Your deck must have at least 1 card!")
		end
		return false
	end
	
	-- Request deck update via network
	if NetworkClient and NetworkClient.requestSetDeck then
		local success, error = NetworkClient.requestSetDeck(newDeck)
		if success then
			-- The UI will update automatically when ProfileUpdated event is received
			return true
		else
			warn("CardInfoHandler: Failed to request deck update:", error)
			-- Map error message to user notification
			local err = tostring(error)
			if #newDeck > 6 or err:find("at most 6") then
				self:ShowDeckNotification("Your deck can contain at most 6 cards!")
			elseif err:find("1 and 6") or err:find("at least 1") then
				self:ShowDeckNotification("Your deck must have at least 1 card!")
			end
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
	
	
	-- Remove card from deck if it's currently in the deck
	if self:IsCardInDeck(self.currentCardId) then
		if self:RemoveCardFromDeck(self.currentCardId) then
			self:CloseWindow()
		end
	else
	end
end

function CardInfoHandler:OnDeckButtonClicked()
	if not self.currentCardId then
		warn("CardInfoHandler: No current card selected for deck action")
		return
	end
	
	
	-- Add card to deck if it's not already in the deck
	if not self:IsCardInDeck(self.currentCardId) then
		if self:AddCardToDeck(self.currentCardId) then
			self:CloseWindow()
		end
	else
	end
end

function CardInfoHandler:OnLevelUpButtonClicked()
	if not self.currentCardId then
		warn("CardInfoHandler: No current card selected for level up action")
		return
	end
	
	-- Check if button is active (should not be clickable when gray)
	local buttons = self.CardInfoFrame:FindFirstChild("Buttons")
	if buttons then
		local btnLevelUp = buttons:FindFirstChild("BtnLevelUp")
		if btnLevelUp and not btnLevelUp.Active then
			warn("CardInfoHandler: Level up button is inactive - cannot level up")
			return
		end
	end
	
	-- Get current card data for validation
	local collectionEntry = self.currentProfile.collection and self.currentProfile.collection[self.currentCardId]
	if not collectionEntry then
		warn("CardInfoHandler: Card not found in collection for level up")
		return
	end
	
	local cardLevel = collectionEntry.level or 0
	local cardCount = collectionEntry.count or 0
	
	-- Get card data from catalog
	local cardData = self.Utilities.CardCatalog.GetCard(self.currentCardId)
	if not cardData then
		warn("CardInfoHandler: Card not found in catalog:", self.currentCardId)
		return
	end
	
	-- Check if level up is possible
	local canLevelUp, reason = CardLevels.CanLevelUp(self.currentCardId, cardLevel, cardCount, self.currentProfile.currencies.soft, cardData.rarity)
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

	-- Show card info frame
	self.CardInfoFrame.Visible = true

	-- Use TweenUI if available, otherwise just show
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
			self.Utilities.TweenUI.FadeIn(self.CardInfoFrame, .3, function ()
				self.isAnimating = false
			end)
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
	else
		-- Fallback: no animation
		self.CardInfoFrame.Visible = false
		self.isAnimating = false
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
			
			-- Always update display if we have current card (even if window is closed)
			-- This ensures level-up status is accurate when window is opened
			if self.CardInfoFrame and self.currentCardId then
				local cardData = CardCatalog.GetCard(self.currentCardId)
				if cardData then
					local collectionEntry = self.currentProfile.collection[self.currentCardId]
					local hasCard = collectionEntry ~= nil
					local cardLevel = hasCard and collectionEntry.level or 0
					local cardCount = hasCard and collectionEntry.count or 0
					
					-- Update display (whether window is open or closed)
					self:UpdateCardInfoDisplay(cardData, hasCard, cardLevel, cardCount)
					
					if self.CardInfoFrame.Visible then
						print("✅ CardInfoHandler: Updated card info for", self.currentCardId, "- count:", cardCount, "level:", cardLevel)
					end
				end
			end
		else
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
