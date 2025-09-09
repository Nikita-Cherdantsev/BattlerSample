--[[
	Dev Panel - Minimal developer UI for testing flows
	
	Provides a small, non-intrusive panel with buttons to test
	common UI flows. Only appears when Config.SHOW_DEV_PANEL is true.
]]

local DevPanel = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Config = require(script.Parent.Parent.Config)
local NetworkClient = require(script.Parent.Parent.Controllers.NetworkClient)
local ClientState = require(script.Parent.Parent.State.ClientState)
local Utilities = require(script.Parent.Parent.Utilities)

-- Use card data from Utilities
local CLIENT_CARD_DATA = Utilities.CardCatalog.GetAllCards()

-- State
local panel = nil
local statusLabel = nil
local isInitialized = false

-- Utility functions
local function log(message, ...)
	print(string.format("[DevPanel] %s", string.format(message, ...)))
end

local function createButton(parent, text, onClick)
	local button = Instance.new("TextButton")
	button.Text = text
	button.Size = UDim2.new(1, -20, 0, 30)
	button.Position = UDim2.new(0, 10, 0, 0)
	button.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.SourceSans
	button.TextSize = 14
	button.Parent = parent
	
	-- Add hover effect
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	end)
	
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	end)
	
	button.MouseButton1Click:Connect(onClick)
	
	return button
end

local function updateStatus()
	if not statusLabel then return end
	
	local state = ClientState.getState()
	local serverNow = NetworkClient.getServerNow()
	local squadPower = state.profile and state.profile.squadPower or 0
	local mockStatus = Config.USE_MOCKS and "ON" or "OFF"
	
	-- Get lootbox info
	local lootboxes = state.profile and state.profile.lootboxes or {}
	local pendingLootbox = state.profile and state.profile.pendingLootbox
	local unlockingCount = 0
	for _, lootbox in ipairs(lootboxes) do
		if lootbox.state == "unlocking" then
			unlockingCount = unlockingCount + 1
		end
	end
	
	local pendingStatus = pendingLootbox and "Y" or "N"
	
	statusLabel.Text = string.format(
		"Server: %d\nPower: %d\nMocks: %s\nLoot: %d slots\nUnlocking: %d\nPending: %s",
		serverNow,
		squadPower,
		mockStatus,
		#lootboxes,
		unlockingCount,
		pendingStatus
	)
end

-- Create the dev panel
function DevPanel.create()
	if not Config.SHOW_DEV_PANEL then
		log("Dev panel disabled in config")
		return
	end
	
	if panel then
		log("Dev panel already exists")
		return
	end
	
	log("Creating dev panel")
	
	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DevPanel"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	
	-- Create main frame
	panel = Instance.new("Frame")
	panel.Name = "MainFrame"
	panel.Size = Config.DEV_PANEL_SETTINGS.SIZE
	panel.Position = Config.DEV_PANEL_SETTINGS.POSITION
	panel.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	panel.BorderSizePixel = 0
	panel.ZIndex = Config.DEV_PANEL_SETTINGS.Z_INDEX
	panel.Parent = screenGui
	
	-- Create title
	local title = Instance.new("TextLabel")
	title.Text = "Dev Panel"
	title.Size = UDim2.new(1, 0, 0, 25)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 16
	title.Parent = panel
	
	-- Create status label
	statusLabel = Instance.new("TextLabel")
	statusLabel.Text = "Loading..."
	statusLabel.Size = UDim2.new(1, -20, 0, 40)
	statusLabel.Position = UDim2.new(0, 10, 0, 30)
	statusLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	statusLabel.Font = Enum.Font.SourceSans
	statusLabel.TextSize = 12
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.Parent = panel
	
	-- Create button container
	local buttonContainer = Instance.new("Frame")
	buttonContainer.Name = "Buttons"
	buttonContainer.Size = UDim2.new(1, -20, 1, -80)
	buttonContainer.Position = UDim2.new(0, 10, 0, 80)
	buttonContainer.BackgroundTransparency = 1
	buttonContainer.Parent = panel
	
	-- Create buttons
	local buttonY = 0
	local buttonHeight = 35
	local buttonSpacing = 5
	
	-- Refresh Profile button
	local refreshButton = createButton(buttonContainer, "Refresh Profile", function()
		log("Refresh Profile clicked")
		NetworkClient.requestProfile()
	end)
	refreshButton.Position = UDim2.new(0, 0, 0, buttonY)
	buttonY = buttonY + buttonHeight + buttonSpacing
	
	-- Set Sample Deck button
	local sampleDeckButton = createButton(buttonContainer, "Set Sample Deck", function()
		log("Set Sample Deck clicked")
		
		-- Get first 6 unique card IDs from client card data (by slotNumber)
		local allCards = {}
		for cardId, card in pairs(CLIENT_CARD_DATA) do
			table.insert(allCards, {id = cardId, slotNumber = card.slotNumber})
		end
		
		-- Sort by slotNumber
		table.sort(allCards, function(a, b)
			return a.slotNumber < b.slotNumber
		end)
		
		-- Take first 6
		local deckIds = {}
		for i = 1, math.min(6, #allCards) do
			table.insert(deckIds, allCards[i].id)
		end
		
		if #deckIds == 6 then
			log("Setting sample deck: %s", table.concat(deckIds, ", "))
			NetworkClient.requestSetDeck(deckIds)
		else
			log("Not enough cards for sample deck")
		end
	end)
	sampleDeckButton.Position = UDim2.new(0, 0, 0, buttonY)
	buttonY = buttonY + buttonHeight + buttonSpacing
	
	-- Start PvE button
	local pveButton = createButton(buttonContainer, "Start PvE", function()
		log("Start PvE clicked")
		NetworkClient.requestStartMatch({mode = "PvE"})
	end)
	pveButton.Position = UDim2.new(0, 0, 0, buttonY)
	buttonY = buttonY + buttonHeight + buttonSpacing
	
	-- Level Up First Upgradeable button
	local levelUpButton = createButton(buttonContainer, "Level Up First Upgradeable", function()
		log("Level Up First Upgradeable clicked")
		
		-- Get current state
		local state = ClientState.getState()
		if not state.profile or not state.profile.collection then
			log("No profile available for level-up")
			return
		end
		
		-- Find first upgradeable card using selectors
		local selectors = require(script.Parent.Parent.State.selectors)
		local upgradeableCards = selectors.selectUpgradeableCards(state)
		
		if #upgradeableCards == 0 then
			log("No cards can be leveled up")
			return
		end
		
		local firstCard = upgradeableCards[1]
		local cardId = firstCard.cardId
		
		-- Get before state for logging
		local collection = selectors.selectCollectionMap(state)
		local currencies = selectors.selectCurrencies(state)
		local squadPower = selectors.selectSquadPower(state)
		local entry = collection[cardId]
		
		-- Check if card is in deck
		local deckIds = selectors.selectDeckIds(state)
		local isInDeck = false
		if deckIds then
			for _, deckCardId in ipairs(deckIds) do
				if deckCardId == cardId then
					isInDeck = true
					break
				end
			end
		end
		
		-- Print before state
		log("BEFORE Level-Up:")
		log("  Card: %s", cardId)
		log("  Level: %d", entry.level)
		log("  Count: %d", entry.count)
		log("  Soft Currency: %d", currencies.soft)
		log("  Squad Power: %d", squadPower)
		log("  In Deck: %s", tostring(isInDeck))
		
		-- Set leveling state
		ClientState.setIsLeveling(true)
		
		-- Request level-up
		local success, errorMessage = NetworkClient.requestLevelUpCard(cardId)
		if not success then
			log("Level-up request failed: %s", errorMessage or "Unknown error")
			ClientState.setIsLeveling(false)
		else
			log("Level-up request sent successfully")
		end
	end)
	levelUpButton.Position = UDim2.new(0, 0, 0, buttonY)
	buttonY = buttonY + buttonHeight + buttonSpacing
	
	-- Print Collection Summary button
	local collectionSummaryButton = createButton(buttonContainer, "Print Collection Summary", function()
		log("Print Collection Summary clicked")
		
		-- Get current state
		local state = ClientState.getState()
		if not state.profile then
			log("No profile available for collection summary")
			return
		end
		
		-- Get unified collection using selectors
		local selectors = require(script.Parent.Parent.State.selectors)
		local unifiedCollection = selectors.selectUnifiedCollection(state)
		
		-- Calculate summary statistics
		local totalCatalogSize = #unifiedCollection
		local ownedCount = 0
		local rarityBreakdown = {}
		local topPowerCards = {}
		local unownedNotable = {}
		
		-- Initialize rarity breakdown
		local rarityOrder = { legendary = 4, epic = 3, rare = 2, common = 1 }
		for rarity, _ in pairs(rarityOrder) do
			rarityBreakdown[rarity] = { owned = 0, total = 0 }
		end
		
		-- Process each card
		for _, card in ipairs(unifiedCollection) do
			-- Count owned cards
			if card.owned then
				ownedCount = ownedCount + 1
				
				-- Add to power ranking (only owned cards have power)
				if card.power then
					table.insert(topPowerCards, {
						cardId = card.cardId,
						name = card.name,
						power = card.power,
						level = card.level
					})
				end
			else
				-- Add to unowned notable (first few by rarity/slot)
				table.insert(unownedNotable, {
					cardId = card.cardId,
					name = card.name,
					rarity = card.rarity,
					slotNumber = card.slotNumber
				})
			end
			
			-- Update rarity breakdown
			if rarityBreakdown[card.rarity] then
				rarityBreakdown[card.rarity].total = rarityBreakdown[card.rarity].total + 1
				if card.owned then
					rarityBreakdown[card.rarity].owned = rarityBreakdown[card.rarity].owned + 1
				end
			end
		end
		
		-- Sort top power cards
		table.sort(topPowerCards, function(a, b)
			return a.power > b.power
		end)
		
		-- Sort unowned notable by rarity then slot
		table.sort(unownedNotable, function(a, b)
			local rarityA = rarityOrder[a.rarity] or 0
			local rarityB = rarityOrder[b.rarity] or 0
			if rarityA ~= rarityB then
				return rarityA > rarityB
			end
			return a.slotNumber < b.slotNumber
		end)
		
		-- Calculate coverage percentage
		local coveragePercent = totalCatalogSize > 0 and math.floor((ownedCount / totalCatalogSize) * 100) or 0
		
		-- Print summary
		log("=== COLLECTION SUMMARY ===")
		log("Total Catalog Size: %d", totalCatalogSize)
		log("Owned Count: %d", ownedCount)
		log("Coverage: %d%%", coveragePercent)
		log("")
		
		-- Print rarity breakdown
		log("Rarity Breakdown:")
		for _, rarity in ipairs({"legendary", "epic", "rare", "common"}) do
			local breakdown = rarityBreakdown[rarity]
			if breakdown.total > 0 then
				local ownedPercent = breakdown.total > 0 and math.floor((breakdown.owned / breakdown.total) * 100) or 0
				log("  %s: %d/%d (%d%%)", 
					string.upper(rarity), 
					breakdown.owned, 
					breakdown.total, 
					ownedPercent
				)
			end
		end
		log("")
		
		-- Print top power cards (top 5)
		if #topPowerCards > 0 then
			log("Top Power Cards:")
			for i = 1, math.min(5, #topPowerCards) do
				local card = topPowerCards[i]
				log("  %d. %s (Lv.%d) - %d power", 
					i, 
					card.name, 
					card.level, 
					card.power
				)
			end
		end
		log("")
		
		-- Print unowned notable (first 5)
		if #unownedNotable > 0 then
			log("Unowned Notable (First 5):")
			for i = 1, math.min(5, #unownedNotable) do
				local card = unownedNotable[i]
				log("  %d. %s (%s, slot %d)", 
					i, 
					card.name, 
					card.rarity, 
					card.slotNumber
				)
			end
		end
		
		log("=== END SUMMARY ===")
	end)
	collectionSummaryButton.Position = UDim2.new(0, 0, 0, buttonY)
	buttonY = buttonY + buttonHeight + buttonSpacing
	
	-- Lootbox buttons
	local lootRefreshButton = createButton(buttonContainer, "Loot: Refresh", function()
		log("Loot Refresh clicked")
		NetworkClient.requestLootState()
	end)
	lootRefreshButton.Position = UDim2.new(0, 0, 0, buttonY)
	buttonY = buttonY + buttonHeight + buttonSpacing
	
	-- Add box buttons (only visible when mocks or debug enabled)
	if Config.USE_MOCKS or Config.DEBUG_LOGS then
		local addUncommonButton = createButton(buttonContainer, "Loot: Add Uncommon", function()
			log("Add Uncommon clicked")
			NetworkClient.requestAddBox("uncommon", "dev_panel")
		end)
		addUncommonButton.Position = UDim2.new(0, 0, 0, buttonY)
		buttonY = buttonY + buttonHeight + buttonSpacing
		
		local addRareButton = createButton(buttonContainer, "Loot: Add Rare", function()
			log("Add Rare clicked")
			NetworkClient.requestAddBox("rare", "dev_panel")
		end)
		addRareButton.Position = UDim2.new(0, 0, 0, buttonY)
		buttonY = buttonY + buttonHeight + buttonSpacing
		
		local addEpicButton = createButton(buttonContainer, "Loot: Add Epic", function()
			log("Add Epic clicked")
			NetworkClient.requestAddBox("epic", "dev_panel")
		end)
		addEpicButton.Position = UDim2.new(0, 0, 0, buttonY)
		buttonY = buttonY + buttonHeight + buttonSpacing
		
		local addLegendaryButton = createButton(buttonContainer, "Loot: Add Legendary", function()
			log("Add Legendary clicked")
			NetworkClient.requestAddBox("legendary", "dev_panel")
		end)
		addLegendaryButton.Position = UDim2.new(0, 0, 0, buttonY)
		buttonY = buttonY + buttonHeight + buttonSpacing
	end
	
	-- Lootbox operations
	local startUnlockButton = createButton(buttonContainer, "Loot: Start Unlock (slot 1)", function()
		log("Start Unlock (slot 1) clicked")
		NetworkClient.requestStartUnlock(1)
	end)
	startUnlockButton.Position = UDim2.new(0, 0, 0, buttonY)
	buttonY = buttonY + buttonHeight + buttonSpacing
	
	local completeUnlockButton = createButton(buttonContainer, "Loot: Complete (slot 1)", function()
		log("Complete Unlock (slot 1) clicked")
		NetworkClient.requestCompleteUnlock(1)
	end)
	completeUnlockButton.Position = UDim2.new(0, 0, 0, buttonY)
	buttonY = buttonY + buttonHeight + buttonSpacing
	
	local openNowButton = createButton(buttonContainer, "Loot: Open Now (slot 1)", function()
		log("Open Now (slot 1) clicked")
		NetworkClient.requestOpenNow(1)
	end)
	openNowButton.Position = UDim2.new(0, 0, 0, buttonY)
	buttonY = buttonY + buttonHeight + buttonSpacing
	
	-- Pending resolution
	local resolveDiscardButton = createButton(buttonContainer, "Loot: Resolve Pending (Discard)", function()
		log("Resolve Pending Discard clicked")
		NetworkClient.requestResolvePendingDiscard()
	end)
	resolveDiscardButton.Position = UDim2.new(0, 0, 0, buttonY)
	buttonY = buttonY + buttonHeight + buttonSpacing
	
	local resolveReplaceButton = createButton(buttonContainer, "Loot: Resolve Pending (Replace slot 1)", function()
		log("Resolve Pending Replace (slot 1) clicked")
		NetworkClient.requestResolvePendingReplace(1)
	end)
	resolveReplaceButton.Position = UDim2.new(0, 0, 0, buttonY)
	buttonY = buttonY + buttonHeight + buttonSpacing
	
	-- Toggle Mocks button
	local toggleMocksButton = createButton(buttonContainer, "Toggle Mocks", function()
		log("Toggle Mocks clicked")
		
		-- Toggle config
		Config.USE_MOCKS = not Config.USE_MOCKS
		
		-- Reinitialize NetworkClient and ClientState
		NetworkClient.reinitialize()
		
		-- Clean up existing subscriptions
		if isInitialized then
			-- Note: In a real implementation, you'd want to properly clean up subscriptions
			-- For now, we'll just reinitialize ClientState
			ClientState.init(NetworkClient)
		end
		
		-- Request profile immediately
		NetworkClient.requestProfile()
		
		-- Update status
		updateStatus()
		
		log("Mocks toggled to: %s", Config.USE_MOCKS and "ON" or "OFF")
	end)
	toggleMocksButton.Position = UDim2.new(0, 0, 0, buttonY)
	
	-- Set up status updates
	ClientState.subscribe(function()
		updateStatus()
	end)
	
	-- Initial status update
	updateStatus()
	
	log("Dev panel created successfully")
end

-- Initialize the dev panel
function DevPanel.init()
	if isInitialized then
		log("Dev panel already initialized")
		return
	end
	
	log("Initializing dev panel")
	
	-- Create the panel
	DevPanel.create()
	
	-- Auto-request profile if configured
	if Config.AUTO_REQUEST_PROFILE then
		log("Auto-requesting profile")
		NetworkClient.requestProfile()
	end
	
	isInitialized = true
	log("Dev panel initialized")
end

-- Destroy the dev panel
function DevPanel.destroy()
	if panel then
		panel:Destroy()
		panel = nil
		statusLabel = nil
		isInitialized = false
		log("Dev panel destroyed")
	end
end

-- Toggle the dev panel
function DevPanel.toggle()
	if panel then
		DevPanel.destroy()
	else
		DevPanel.create()
	end
end

-- Auto-initialize when script runs
DevPanel.init()

return DevPanel
