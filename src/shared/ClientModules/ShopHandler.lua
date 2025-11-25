--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

--// Modules
local NetworkClient = require(game.StarterPlayer.StarterPlayerScripts.Controllers.NetworkClient)

--// Module
local ShopHandler = {}

--// State
ShopHandler.Connections = {}
ShopHandler._initialized = false

ShopHandler.isAnimating = false
ShopHandler.regionalPrices = {} -- Cache regional prices per pack ID

--// Initialization
function ShopHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	self.Utilities = controller:GetModule("Utilities")
	
	self.Connections = {}
	self.pendingPurchase = nil

	self:SetupShop()

	self._initialized = true
	print("✅ ShopHandler initialized successfully!")
	return true
end

function ShopHandler:SetupShop()
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	local gameGui = playerGui:WaitForChild("GameUI", 10) -- Wait up to 10 seconds
	
	if not gameGui then
		warn("ShopHandler: GameUI not found in PlayerGui after waiting")
		return
	end
	
	-- Look for Shop frame
	local shopFrame = gameGui:FindFirstChild("Shop")
	if not shopFrame then
		warn("ShopHandler: Shop frame not found in " .. gameGui.Name)
		return
	end
	
	self.UI = gameGui
	self.ShopFrame = shopFrame
	self.InputBlocker = shopFrame:FindFirstChild("InputBlocker")
	
	shopFrame.Visible = false
	
	self:SetupOpenButton()
	self:SetupCloseButton()
	self:SetupShopButtons()
	self:SetupProfileUpdatedHandler()
	self:SetupModelClickHandler()
	
	print("✅ ShopHandler: Shop UI setup completed")
end

function ShopHandler:SetupOpenButton()
	
	local leftPanel = self.UI:FindFirstChild("LeftPanel")
	if not leftPanel then
		warn("ShopHandler: LeftPanel not found in GameUI")
		return
	end
	
	local shopButton = leftPanel:FindFirstChild("BtnShop")
	if not shopButton then
		warn("ShopHandler: Button not found in Shop frame")
		return
	end
	
	if shopButton:IsA("GuiButton") then
		local connection = shopButton.MouseButton1Click:Connect(function()
			self:OpenWindow()
		end)
		table.insert(self.Connections, connection)
		print("✅ ShopHandler: Open button connected")
	else
		warn("ShopHandler: Found element '" .. shopButton.Name .. "' but it's not a GuiButton (it's a " .. shopButton.ClassName .. ")")
	end
end

function ShopHandler:SetupCloseButton()
	local closeButton = self.ShopFrame:FindFirstChild("Main")
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
		warn("ShopHandler: Close button not found - you may need to add a CloseButton to Shop frame")
		return
	end

	local connection = closeButton.MouseButton1Click:Connect(function()
		self:CloseWindow()
	end)

	table.insert(self.Connections, connection)
	print("✅ ShopHandler: Close button connected")
end

function ShopHandler:SetupShopButtons()
	self:SetupFeaturedButtons()
	self:SetupPackButtons()
	self:SetupLootboxButtons()
	print("✅ ShopHandler: Shop purchase buttons setup completed")
end

function ShopHandler:SetupFeaturedButtons()
	local featuredFrame = self.ShopFrame:WaitForChild("Main"):WaitForChild("Content"):WaitForChild("Content"):WaitForChild("ScrollingFrame"):WaitForChild("FeaturedContent")
	if featuredFrame then
		local coinsFrame = featuredFrame:FindFirstChild("Frame1")
		local coinsButton = coinsFrame:FindFirstChild("Button")
		local connection = coinsButton.MouseButton1Click:Connect(function()
			-- TODO: add data from shop config
			self:HandlePackPurchase("XXL", coinsButton)
		end)
		table.insert(self.Connections, connection)

		local lootboxFrame = featuredFrame:FindFirstChild("Frame2")
		local lootboxButton = lootboxFrame:FindFirstChild("Button")
		local connection = lootboxButton.MouseButton1Click:Connect(function()
			-- TODO: add data from shop config
			self:HandleLootboxPurchase("legendary", lootboxButton)
		end)
		table.insert(self.Connections, connection)
	end
end

function ShopHandler:SetupPackButtons()
	local possiblePaths = {
		{path = {"Main", "Content", "Content", "ScrollingFrame", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		{path = {"Main", "Content", "Content"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		{path = {"Main", "Content", "ScrollingFrame", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		{path = {"Main", "Content", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		{path = {"Main", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		{path = {"Content", "ScrollingFrame", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		{path = {}, frames = {"PackS", "PackM", "PackL", "PackXL", "PackXXL", "PackXXXL"}}
	}
	
	local packIds = {"S", "M", "L", "XL", "XXL", "XXXL"}
	
	for _, pathInfo in ipairs(possiblePaths) do
		
		local currentFrame = self.ShopFrame
		for _, childName in ipairs(pathInfo.path) do
			currentFrame = currentFrame:FindFirstChild(childName)
			if not currentFrame then
				break
			end
		end
		
		if currentFrame then

			-- Try to find buttons in this container
			for i, frameName in ipairs(pathInfo.frames) do
				local frame = currentFrame:FindFirstChild(frameName)
				if frame then
					
					-- Look for button with various possible names
					local button = self:findButtonInFrame(frame)
					if not button then
						button = self:findAnyButtonInFrame(frame)
					end
					
					if button then
						local packId = packIds[i]
						local connection = button.MouseButton1Click:Connect(function()
							self:HandlePackPurchase(packId, button)
						end)
						table.insert(self.Connections, connection)
					end
				end
			end
		end
	end
end

function ShopHandler:findButtonInFrame(frame)
	local buttonNames = {"Button", "BtnBuy", "BuyButton", "PurchaseButton"}
	
	for _, buttonName in ipairs(buttonNames) do
		local button = frame:FindFirstChild(buttonName)
		if button and button:IsA("GuiButton") then
			return button
		end
	end
	
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			for _, buttonName in ipairs(buttonNames) do
				local button = child:FindFirstChild(buttonName)
				if button and button:IsA("GuiButton") then
					return button
				end
			end
			
			if child:IsA("GuiButton") then
				return child
			end
			
			for _, grandchild in ipairs(child:GetChildren()) do
				if grandchild:IsA("GuiButton") then
					return grandchild
				end
			end
		end
	end
	
	return nil
end

function ShopHandler:findAnyButtonInFrame(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiButton") then
			return child
		end
		
		local found = self:findAnyButtonInFrame(child)
		if found then
			return found
		end
	end
	
	return nil
end

function ShopHandler:SetupLootboxButtons()
	local possiblePaths = {
		{path = {"Main", "Content", "Content", "ScrollingFrame", "PacksContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4"}},
		{path = {"Main", "Content", "Content"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4"}},
		{path = {"Main", "Content", "ScrollingFrame", "PacksContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4"}},
		{path = {"Main", "Content", "PacksContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4"}},
		{path = {"Main", "PacksContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4"}},
		{path = {"Content", "ScrollingFrame", "PacksContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4"}},
		{path = {}, frames = {"LootboxUncommon", "LootboxRare", "LootboxEpic", "LootboxLegendary"}}
	}
	
	local rarities = {"uncommon", "rare", "epic", "legendary"}
	
	for _, pathInfo in ipairs(possiblePaths) do
		local currentFrame = self.ShopFrame
		for _, childName in ipairs(pathInfo.path) do
			currentFrame = currentFrame:FindFirstChild(childName)
			if not currentFrame then
				break
			end
		end
		
		if currentFrame then
			-- Try to find buttons in this container
			for i, frameName in ipairs(pathInfo.frames) do
				local frame = currentFrame:FindFirstChild(frameName)
				if frame then
					-- Look for button with various possible names
					local button = self:findButtonInFrame(frame)
					if not button then
						button = self:findAnyButtonInFrame(frame)
					end
					
					if button then
						local rarity = rarities[i]
						local connection = button.MouseButton1Click:Connect(function()
							self:HandleLootboxPurchase(rarity, button)
						end)
						table.insert(self.Connections, connection)
					end
				end
			end
		end
	end
end

function ShopHandler:SetupModelClickHandler()
	local targetModelName = "Samurai"
	local maxWaitTime = 30 -- Maximum wait time in seconds
	local checkInterval = 0.5 -- Check every 0.5 seconds

	local function findModelByName(parent, name)
		for _, child in ipairs(parent:GetDescendants()) do
			if child:IsA("Model") and child.Name == name then
				return child
			end
		end
		return nil
	end

	-- Try to find model immediately
	local targetModel = findModelByName(workspace, targetModelName)

	-- If model not found, wait for it to load
	if not targetModel then
		local startTime = tick()
		local modelConnection = nil
		
		-- Set up listener for new children in workspace
		modelConnection = workspace.ChildAdded:Connect(function(child)
			if child:IsA("Model") and child.Name == targetModelName then
				targetModel = child
			else
				-- Check descendants in case model is nested
				local foundModel = findModelByName(child, targetModelName)
				if foundModel then
					targetModel = foundModel
				end
			end
		end)

		-- Also check periodically in case model was already added but not detected
		while not targetModel and (tick() - startTime) < maxWaitTime do
			targetModel = findModelByName(workspace, targetModelName)
			if not targetModel then
				task.wait(checkInterval)
			end
		end

		-- Always clean up connection
		if modelConnection then
			modelConnection:Disconnect()
		end
	end

	if not targetModel then
		warn("ShopHandler: Model " .. targetModelName .. " not found in workspace after waiting " .. maxWaitTime .. " seconds")
		return
	end

	-- Wait for ProximityPrompt to be added to the model
	local prompt = targetModel:FindFirstChildWhichIsA("ProximityPrompt", true)
	
	if not prompt then
		-- Wait for prompt to be added
		local startTime = tick()
		local promptConnection = nil
		
		promptConnection = targetModel.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("ProximityPrompt") then
				prompt = descendant
				if promptConnection then
					promptConnection:Disconnect()
				end
			end
		end)

		-- Also check periodically
		while not prompt and (tick() - startTime) < maxWaitTime do
			prompt = targetModel:FindFirstChildWhichIsA("ProximityPrompt", true)
			if not prompt then
				task.wait(checkInterval)
			end
		end

		-- Clean up connection
		if promptConnection then
			promptConnection:Disconnect()
		end
	end

	if prompt then
		local connection = prompt.Triggered:Connect(function(player)
			-- Check if battle is active
			local battleHandler = self.Controller and self.Controller:GetBattleHandler()
			if battleHandler and battleHandler.isBattleActive then
				return -- Don't allow interaction during battle
			end
			
			self:OpenWindow()
		end)
		table.insert(self.Connections, connection)
		print("✅ ShopHandler: Model click handler connected for " .. targetModelName)
	else
		warn("ShopHandler: Proximity prompt not found on model " .. targetModelName .. " after waiting")
	end
end

function ShopHandler:HandlePackPurchase(packId, button)
	self:BlockInput(true, packId)
	
	button.Active = false
	
	self.pendingPurchase = {
		packId = packId,
		button = button
	}
	
	local success, result = pcall(function()
		return NetworkClient.requestStartPackPurchase(packId)
	end)
	
	if not success then
		self:ShowError("Network Error", tostring(result))
		
		button.Active = true
		self.pendingPurchase = nil
		return
	end
	
	if not result then
		self:ShowError("No Response", "No response from server")
		
		button.Active = true
		self.pendingPurchase = nil
		return
	end
end

function ShopHandler:HandleLootboxPurchase(rarity, button)
	self:BlockInput(true, rarity)

	button.Active = false

	self.pendingPurchase = {
		lootboxId = rarity,
		button = button
	}
	
	local success, errorMessage = NetworkClient.requestBuyLootbox(rarity)
	if not success then
		self:ShowError("Lootbox Purchase Failed", errorMessage)
		
		button.Active = true
		return
	end
end

function ShopHandler:BlockInput(value, source)
	if not self.InputBlocker then
		warn("ShopHandler: No self.InputBlocker!")
		return
	end

	self.InputBlocker.Active = value
	self.InputBlocker.Visible = value
end

function ShopHandler:ShowError(title, message)
	-- TODO: remove or expand
	if self.UI and self.UI:FindFirstChild("ErrorDialog") then
		local errorDialog = self.UI.ErrorDialog
		errorDialog.Title.Text = title
		errorDialog.Message.Text = message
		errorDialog.Visible = true
	end
end

function ShopHandler:OpenWindow()
	if self.isAnimating then return end
	self.isAnimating = true

	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = false
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = false
	end

	self.ShopFrame.Visible = true

	-- Fetch regional prices when opening shop (client-side for accurate player region)
	self:FetchRegionalPrices()

	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
			self.Utilities.TweenUI.FadeIn(self.ShopFrame, .3, function ()
				self.isAnimating = false
			end)
		end
		if self.Utilities.Blur then
			self.Utilities.Blur.Show()
		end
	else
		self.isAnimating = false
	end
	
	print("✅ ShopHandler: Shop window opened")
end

function ShopHandler:CloseWindow()
	if self.isAnimating then return end
	self.isAnimating = true

	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
			self.Utilities.TweenUI.FadeOut(self.ShopFrame, .3, function () 
				self.ShopFrame.Visible = false
				self.isAnimating = false
			end)
		end
		if self.Utilities.Blur then
			self.Utilities.Blur.Hide()
		end
	else
		self.ShopFrame.Visible = false
		self.isAnimating = false
	end

	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = true
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = true
	end
	
	print("✅ ShopHandler: Shop window closed")
end

--// Public Methods
function ShopHandler:IsInitialized()
	return self._initialized
end

-- Fetch regional prices for all packs using client-side GetProductInfo
-- This ensures accurate regional pricing for the player's region
function ShopHandler:FetchRegionalPrices()
	local ShopPacksCatalog = require(game.ReplicatedStorage.Modules.Shop.ShopPacksCatalog)
	local allPacks = ShopPacksCatalog.AllPacks()
	
	-- Fetch prices for all packs (async, non-blocking)
	task.spawn(function()
		for _, pack in ipairs(allPacks) do
			if pack.devProductId then
				local success, productInfo = pcall(function()
					return MarketplaceService:GetProductInfo(pack.devProductId, Enum.InfoType.Product)
				end)
				
				if success and productInfo and productInfo.PriceInRobux then
					-- Store regional price (client-side GetProductInfo returns player's region price)
					self.regionalPrices[pack.id] = productInfo.PriceInRobux
				else
					-- Fall back to hardcoded price on error
					self.regionalPrices[pack.id] = pack.robuxPrice
					if not success or not productInfo then
						warn(string.format("[ShopHandler] Failed to fetch price for pack %s, using hardcoded price: %d", 
							pack.id, pack.robuxPrice))
					end
				end
			else
				-- No product ID, use hardcoded price
				self.regionalPrices[pack.id] = pack.robuxPrice
			end
		end
		
		-- Update UI with regional prices
		self:UpdatePackPricesInUI()
	end)
end

-- Update pack prices in UI with regional prices
function ShopHandler:UpdatePackPricesInUI()
	local packIds = {"S", "M", "L", "XL", "XXL", "XXXL"}
	local possiblePaths = {
		{path = {"Main", "Content", "Content", "ScrollingFrame", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		{path = {"Main", "Content", "Content"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		{path = {"Main", "Content", "ScrollingFrame", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		{path = {"Main", "Content", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		{path = {"Main", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		{path = {"Content", "ScrollingFrame", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
	}
	
	for _, pathInfo in ipairs(possiblePaths) do
		local currentFrame = self.ShopFrame
		for _, childName in ipairs(pathInfo.path) do
			currentFrame = currentFrame:FindFirstChild(childName)
			if not currentFrame then
				break
			end
		end
		
		if currentFrame then
			for i, frameName in ipairs(pathInfo.frames) do
				local frame = currentFrame:FindFirstChild(frameName)
				if frame then
					local packId = packIds[i]
					local price = self.regionalPrices[packId]
					
					if price then
						-- Try to find price text elements (common names)
						local priceTextNames = {"TxtPrice", "Price", "TxtRobux", "Robux", "TxtValue", "Value"}
						for _, textName in ipairs(priceTextNames) do
							local priceText = frame:FindFirstChild(textName, true) -- Search recursively
							if priceText and (priceText:IsA("TextLabel") or priceText:IsA("TextButton")) then
								priceText.Text = tostring(price)
								break
							end
						end
					end
				end
			end
			
			-- If we found a valid path, we can break
			break
		end
	end
end

function ShopHandler:SetupProfileUpdatedHandler()
	local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
	
	local connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
		if payload.error then
			self:ShowError("Pack Purchase Failed", payload.error.message or payload.error.code)
			if self.pendingPurchase then
				local button = self.pendingPurchase.button

				button.BackgroundTransparency = 0.25
				local messages = {
					[ "INSUFFICIENT_HARD" ] = "Not enough coins..."
				}
				button.Text = messages[ payload.error.code ] or payload.error.code

				task.wait(1)

				button.BackgroundTransparency = 1
				button.Text = ""

				button.Active = true
				self:BlockInput(false, self.pendingPurchase.lootboxId or self.pendingPurchase.packId)
				self.pendingPurchase = nil
			end
			return
		end

		if payload.packId and self.pendingPurchase then
			local pending = self.pendingPurchase
			if pending.packId == payload.packId then
				if payload.error then
					self:ShowError("Pack Purchase Failed", payload.error.message or payload.error.code)
				elseif payload.devProductId then
					local success, purchaseError = pcall(function()
						MarketplaceService:PromptProductPurchase(Players.LocalPlayer, payload.devProductId)
					end)
					
					if not success then
						self:ShowError("Purchase Failed", "Could not prompt purchase")
					end
				else
					self:ShowError("Purchase Failed", "Invalid server response")
				end
				
				pending.button.Active = true
				self:BlockInput(false, self.pendingPurchase.packId)
				self.pendingPurchase = nil
			end
		end

		if payload.rewards and payload.rewards.rarity and self.pendingPurchase then
			local pending = self.pendingPurchase
			if pending.lootboxId == payload.rewards.rarity then
				if payload.error then
					self:ShowError("Lootbox Purchase Failed", payload.error.message or payload.error.code)
				else
					self:ShowError("Purchase Failed", "Invalid server response")
				end
				
				pending.button.Active = true
				self:BlockInput(false, self.pendingPurchase.lootboxId)
				self.pendingPurchase = nil
			end
		end
	end)
	
	table.insert(self.Connections, connection)
end

--// Cleanup
function ShopHandler:Cleanup()
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}

	self._initialized = false
	print("✅ ShopHandler cleaned up")
end

return ShopHandler