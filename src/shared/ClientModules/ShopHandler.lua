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
	
	shopFrame.Visible = false
	
	self:SetupOpenButton()
	self:SetupCloseButton()
	self:SetupShopButtons()
	self:SetupProfileUpdatedHandler()
	
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

function ShopHandler:HandlePackPurchase(packId, button)
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

function ShopHandler:SetupProfileUpdatedHandler()
	local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
	
	local connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
		if payload.error then
			self:ShowError("Pack Purchase Failed", payload.error.message or payload.error.code)
			if self.pendingPurchase then
				local button = self.pendingPurchase.button

				button.BackgroundTransparency = 0.25
				local messages = {
					[ "INSUFFICIENT_HARD" ] = "Not enough coins...",
					[ "RATE_LIMITED" ] = "Too many requests, please wait!"
				}
				button.Text = messages[ payload.error.code ] or payload.error.code

				task.wait(1)

				button.BackgroundTransparency = 1
				button.Text = ""

				button.Active = true
				self.pendingPurchase = nil
			end
			return
		end

		if payload.packId and self.pendingPurchase then
			local pending = self.pendingPurchase
			if pending.packId == payload.packId then
				if payload.error then
					self:ShowError("Pack Purchase Failed", payload.error.message or payload.error.code)
					pending.button.Active = true
				elseif payload.devProductId then
					local success, purchaseError = pcall(function()
						MarketplaceService:PromptProductPurchase(Players.LocalPlayer, payload.devProductId)
					end)
					
					if not success then
						self:ShowError("Purchase Failed", "Could not prompt purchase")
						pending.button.Active = true
					end
				else
					self:ShowError("Purchase Failed", "Invalid server response")
					pending.button.Active = true
				end
				
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