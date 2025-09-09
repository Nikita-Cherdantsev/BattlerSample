--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

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

	-- Setup Shop bonus functionality
	self:SetupShop()

	self._initialized = true
	print("✅ ShopHandler initialized successfully!")
	return true
end

function ShopHandler:SetupShop()
	local UI = self.ClientState:getUI()

	if not UI then
		warn("ShopHandler: UI not available")
		return
	end

	-- Ensure Shop window exists
	if not UI:FindFirstChild("Shop") then
		warn("ShopHandler: Shop window not found in UI")
		return
	end

	UI.Shop.Visible = false

	-- Setup HUD button click
	self:SetupOpenButton(UI)

	-- Setup close button
	self:SetupCloseButton(UI)

end

function ShopHandler:SetupOpenButton(UI)
	if not UI.LeftPanel or not UI.LeftPanel:FindFirstChild("Shop") then
		warn("ShopHandler: Shop button not found in LeftPanel")
		return
	end

	local button : TextButton = UI.LeftPanel.Shop:WaitForChild("Button")
	local connection = button.MouseButton1Click:Connect(function()
		self:OpenWindow(UI)
	end)

	table.insert(self.Connections, connection)
end

function ShopHandler:SetupCloseButton(UI)
	if not UI.Shop or not UI.Shop:FindFirstChild("Main") then
		warn("ShopHandler: Shop main content not found")
		return
	end

	local mainContent = UI.Shop.Main
	if not mainContent:FindFirstChild("Content") then
		warn("ShopHandler: Shop content not found")
		return
	end

	local content = mainContent.Content
	if not content:FindFirstChild("BtnClose") then
		warn("ShopHandler: Shop close button not found")
		return
	end

	local button : TextButton = content.BtnClose:WaitForChild("Button")
	local connection = button.MouseButton1Click:Connect(function()
		self:CloseWindow(UI)
	end)

	table.insert(self.Connections, connection)
end

function ShopHandler:OpenWindow(UI)
	if self.isAnimating then return end
	self.isAnimating = true

	-- Hide HUD
	if UI.LeftPanel then
		UI.LeftPanel.Visible = false
	end
	if UI.BottomPanel then
		UI.BottomPanel.Visible = false
	end

	UI.Shop.Visible = true

	-- Use TweenUI if available, otherwise just show
	if self.Utilities and self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
		self.Utilities.TweenUI.FadeIn(UI.Shop, .3, function ()
			self.isAnimating = false
		end)
	else
		-- Fallback: no animation
		self.isAnimating = false
	end
end

function ShopHandler:CloseWindow(UI)
	if self.isAnimating then return end
	self.isAnimating = true

	-- Hide Shop gui
	if self.Utilities and self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
		self.Utilities.TweenUI.FadeOut(UI.Shop, .3, function () 
			UI.Shop.Visible = false
			self.isAnimating = false
		end)
	else
		-- Fallback: no animation
		UI.Shop.Visible = false
		self.isAnimating = false
	end

	-- Show HUD
	if UI.LeftPanel then
		UI.LeftPanel.Visible = true
	end
	if UI.BottomPanel then
		UI.BottomPanel.Visible = true
	end
end

--// Public Methods
function ShopHandler:IsInitialized()
	return self._initialized
end

--// Cleanup
function ShopHandler:Cleanup()
	print("Cleaning up ShopHandler...")

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
