--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

--// Modules
local Config = require(game.StarterPlayer.StarterPlayerScripts.Config)
local ErrorMap = require(game.ReplicatedStorage.Modules.ErrorMap)
local NetworkClient = require(game.StarterPlayer.StarterPlayerScripts.Controllers.NetworkClient)

--// Module
local ShopHandler = {}

--// State
ShopHandler.Connections = {}
ShopHandler._initialized = false

ShopHandler.isAnimating = false

--// Initialization
function ShopHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	self.Utilities = controller:GetModule("Utilities")
	
	-- Initialize state
	self.Connections = {}
	self.pendingPackPurchase = nil

	-- Setup Shop bonus functionality
	self:SetupShop()

	self._initialized = true
	print("✅ ShopHandler initialized successfully!")
	return true
end

function ShopHandler:SetupShop()
	-- Access UI from player's PlayerGui (which should be copied from StarterGui)
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	
	-- Debug: Print all children in PlayerGui
	for _, child in pairs(playerGui:GetChildren()) do
	end
	
	-- Debug: Check all GameUI instances
	local gameUIs = {}
	for _, child in pairs(playerGui:GetChildren()) do
		if child.Name == "GameUI" then
			table.insert(gameUIs, child)
		end
	end
	for i, gameUI in ipairs(gameUIs) do
	end
	
	-- Wait for Roblox to automatically clone GameUI from StarterGui
	-- This is the correct way to get the UI that the player can actually interact with
	local gameGui = playerGui:WaitForChild("GameUI", 10) -- Wait up to 10 seconds
	
	if not gameGui then
		warn("ShopHandler: GameUI not found in PlayerGui after waiting")
		return
	end
	
	
	
	-- Look for Shop frame
	local shopFrame = gameGui:FindFirstChild("Shop")
	if not shopFrame then
		warn("ShopHandler: Shop frame not found in " .. gameGui.Name)
		for _, child in pairs(gameGui:GetChildren()) do
		end
		return
	end
	
	
	-- Store UI reference for later use
	self.UI = gameGui
	self.ShopFrame = shopFrame
	
	-- Hide shop initially
	shopFrame.Visible = false
	
	-- Setup shop functionality
	self:SetupOpenButton()
	self:SetupCloseButton()
	
	print("✅ ShopHandler: Shop UI setup completed")
	
	-- Setup shop purchase buttons
	self:SetupShopButtons()
	
	-- Setup ProfileUpdated event handler for pack purchase responses
	self:SetupProfileUpdatedHandler()
end

function ShopHandler:SetupOpenButton()
	-- Look for shop button in the UI
	-- Path: GameUI -> LeftPanel -> Shop -> Button
	
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
	
	
	-- Test if the button has the right events
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
	-- Look for close button in the shop frame
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
	
	-- Alternative: look for close button directly in shop frame
	if not closeButton then
		closeButton = self.ShopFrame:FindFirstChild("CloseButton")
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
	if self.ShopFrame then
	end
	
	-- Look for pack purchase buttons
	self:SetupPackButtons()
	
	-- Look for lootbox purchase buttons
	self:SetupLootboxButtons()
	
	print("✅ ShopHandler: Shop purchase buttons setup completed")
end

function ShopHandler:SetupPackButtons()
	
	-- Debug: Print the entire shop frame structure
	
	-- Try multiple possible UI structures
	local possiblePaths = {
		-- Path 1: Main/Content/Content/ScrollingFrame/CurrencyContent/ (the actual structure!)
		{path = {"Main", "Content", "Content", "ScrollingFrame", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		-- Path 2: Main/Content/Content/ (nested Content - fallback)
		{path = {"Main", "Content", "Content"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		-- Path 3: Main/Content/ScrollingFrame/CurrencyContent/Frame1..6/BtnBuy/Button
		{path = {"Main", "Content", "ScrollingFrame", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		-- Path 4: Main/Content/CurrencyContent/Frame1..6/BtnBuy/Button
		{path = {"Main", "Content", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		-- Path 5: Main/CurrencyContent/Frame1..6/BtnBuy/Button
		{path = {"Main", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		-- Path 6: Content/ScrollingFrame/CurrencyContent/Frame1..6/BtnBuy/Button
		{path = {"Content", "ScrollingFrame", "CurrencyContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4", "Frame5", "Frame6"}},
		-- Path 7: Direct children of shop frame
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
						-- Try to find ANY GuiButton in the entire hierarchy
						button = self:findAnyButtonInFrame(frame)
						if button then
						end
					end
					
					if button then
						local packId = packIds[i]
						-- Pack button found, connecting
						
						-- Connect button click
						local connection = button.MouseButton1Click:Connect(function()
							self:HandlePackPurchase(packId, button)
						end)
						table.insert(self.Connections, connection)
						
					else
					end
				-- else: Frame not found (normal for alternate paths)
				end
			end
		end
	end
end

function ShopHandler:findButtonInFrame(frame)
	-- Look for button with various possible names and structures
	local buttonNames = {"Button", "BtnBuy", "BuyButton", "PurchaseButton"}
	
	-- First check direct children
	for _, buttonName in ipairs(buttonNames) do
		local button = frame:FindFirstChild(buttonName)
		if button and button:IsA("GuiButton") then
			return button
		end
	end
	
	-- Look deeper - check children of children (like CoinItem)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			-- Check direct children of this child
			for _, buttonName in ipairs(buttonNames) do
				local button = child:FindFirstChild(buttonName)
				if button and button:IsA("GuiButton") then
					return button
				end
			end
			
			-- Check if this child itself is a button
			if child:IsA("GuiButton") then
				return child
			end
			
			-- Look even deeper - check grandchildren
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
	-- Recursively search for ANY GuiButton in the entire hierarchy
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiButton") then
			return child
		end
		
		-- Recursively search children
		local found = self:findAnyButtonInFrame(child)
		if found then
			return found
		end
	end
	
	return nil
end

function ShopHandler:SetupLootboxButtons()
	
	-- Try multiple possible UI structures for lootboxes
	local possiblePaths = {
		-- Path 1: Main/Content/Content/ScrollingFrame/PacksContent/ (the actual structure!)
		{path = {"Main", "Content", "Content", "ScrollingFrame", "PacksContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4"}},
		-- Path 2: Main/Content/Content/ (nested Content - fallback)
		{path = {"Main", "Content", "Content"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4"}},
		-- Path 3: Main/Content/ScrollingFrame/PacksContent/Frame1..4/BtnBuy/Button
		{path = {"Main", "Content", "ScrollingFrame", "PacksContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4"}},
		-- Path 4: Main/Content/PacksContent/Frame1..4/BtnBuy/Button
		{path = {"Main", "Content", "PacksContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4"}},
		-- Path 5: Main/PacksContent/Frame1..4/BtnBuy/Button
		{path = {"Main", "PacksContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4"}},
		-- Path 6: Content/ScrollingFrame/PacksContent/Frame1..4/BtnBuy/Button
		{path = {"Content", "ScrollingFrame", "PacksContent"}, frames = {"Frame1", "Frame2", "Frame3", "Frame4"}},
		-- Path 7: Direct children of shop frame
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
						-- Try to find ANY GuiButton in the entire hierarchy
						button = self:findAnyButtonInFrame(frame)
						if button then
						end
					end
					
					if button then
						local rarity = rarities[i]
						-- Lootbox button found, connecting
						
						-- Connect button click
						local connection = button.MouseButton1Click:Connect(function()
							self:HandleLootboxPurchase(rarity, button)
						end)
						table.insert(self.Connections, connection)
						
					end
				-- else: Lootbox frame not found (normal for alternate paths)
				end
			end
		end
	end
end

function ShopHandler:HandlePackPurchase(packId, button)
	
	-- Disable button while processing
	button.Active = false
	local originalText = button.Text
	button.Text = "Processing..."
	
	-- Store button state for async response
	self.pendingPackPurchase = {
		packId = packId,
		button = button,
		originalText = originalText
	}
	
	-- Request pack purchase validation
	local success, result = pcall(function()
		return NetworkClient.requestStartPackPurchase(packId)
	end)
	
	if not success then
		self:ShowError("Network Error", tostring(result))
		
		-- Re-enable button
		button.Active = true
		button.Text = originalText
		self.pendingPackPurchase = nil
		return
	end
	
	if not result then
		self:ShowError("No Response", "No response from server")
		
		-- Re-enable button
		button.Active = true
		button.Text = originalText
		self.pendingPackPurchase = nil
		return
	end
	
	-- The actual response will come via ProfileUpdated event
	-- We'll handle it in the ProfileUpdated callback
end

function ShopHandler:HandleLootboxPurchase(rarity, button)
	
	-- Disable button while processing
	button.Active = false
	local originalText = button.Text
	button.Text = "Processing..."
	
	-- NetworkClient is now directly required at the top of the file
	
	-- Request lootbox purchase
	local success, errorMessage = NetworkClient.requestBuyLootbox(rarity)
	if not success then
		self:ShowError("Lootbox Purchase Failed", errorMessage)
		
		-- Re-enable button
		button.Active = true
		button.Text = originalText
		return
	end
	
	button.Text = "Purchased!"
	
	-- Re-enable after delay
	task.wait(2)
	button.Active = true
	button.Text = originalText
end

function ShopHandler:ShowError(title, message)
	-- Simple error display (in a real implementation, you'd use a proper error dialog)
	
	-- You could also fire a custom event for the UI to handle
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

	-- Hide HUD panels if they exist
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = false
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = false
	end

	-- Show shop frame
	self.ShopFrame.Visible = true

	-- Use TweenUI if available, otherwise just show
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
		-- Fallback: no animation
		self.isAnimating = false
	end
	
	print("✅ ShopHandler: Shop window opened")
end

function ShopHandler:CloseWindow()
	if self.isAnimating then return end
	self.isAnimating = true

	-- Hide Shop gui
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
		-- Fallback: no animation
		self.ShopFrame.Visible = false
		self.isAnimating = false
	end

	-- Show HUD panels
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

--// Cleanup
function ShopHandler:SetupProfileUpdatedHandler()
	-- Listen for ProfileUpdated events to handle pack purchase responses
	local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
	
	local connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
		-- Check if this is a pack purchase response
		if payload.packId and self.pendingPackPurchase then
			local pending = self.pendingPackPurchase
			if pending.packId == payload.packId then
				
				if payload.error then
					-- Handle error
					self:ShowError("Pack Purchase Failed", payload.error.message or payload.error.code)
					
					-- Re-enable button
					pending.button.Active = true
					pending.button.Text = pending.originalText
				elseif payload.devProductId then
					-- Real mode: proceed with Roblox purchase
					
					-- Prompt Roblox purchase
					local success, purchaseError = pcall(function()
						MarketplaceService:PromptProductPurchase(Players.LocalPlayer, payload.devProductId)
					end)
					
					if not success then
						self:ShowError("Purchase Failed", "Could not prompt purchase")
						
						-- Re-enable button
						pending.button.Active = true
						pending.button.Text = pending.originalText
					else
						-- Wait for ProcessReceipt to complete
						pending.button.Text = "Purchasing..."
					end
				else
					-- No devProductId - this shouldn't happen in production
					self:ShowError("Purchase Failed", "Invalid server response")
					
					-- Re-enable button
					pending.button.Active = true
					pending.button.Text = pending.originalText
				end
				
				-- Clear pending purchase
				self.pendingPackPurchase = nil
			end
		end
	end)
	
	-- Store connection for cleanup
	table.insert(self.Connections, connection)
end

function ShopHandler:Cleanup()

	-- Disconnect all connections
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