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
	-- Access UI from player's PlayerGui (which should be copied from StarterGui)
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	print("ShopHandler: Looking for UI in PlayerGui...")
	
	-- Debug: Print all children in PlayerGui
	print("Available children in PlayerGui:")
	for _, child in pairs(playerGui:GetChildren()) do
		print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
	end
	
	-- Debug: Check all GameUI instances
	local gameUIs = {}
	for _, child in pairs(playerGui:GetChildren()) do
		if child.Name == "GameUI" then
			table.insert(gameUIs, child)
		end
	end
	print("ShopHandler: Found " .. #gameUIs .. " GameUI instances")
	for i, gameUI in ipairs(gameUIs) do
		print("  GameUI " .. i .. ": " .. tostring(gameUI))
	end
	
	-- Wait for Roblox to automatically clone GameUI from StarterGui
	-- This is the correct way to get the UI that the player can actually interact with
	local gameGui = playerGui:WaitForChild("GameUI", 10) -- Wait up to 10 seconds
	
	if not gameGui then
		warn("ShopHandler: GameUI not found in PlayerGui after waiting")
		return
	end
	
	print("ShopHandler: Found GameUI: " .. tostring(gameGui))
	
	print("ShopHandler: Main UI container found: " .. gameGui.Name)
	
	-- Look for Shop frame
	local shopFrame = gameGui:FindFirstChild("Shop")
	if not shopFrame then
		warn("ShopHandler: Shop frame not found in " .. gameGui.Name)
		print("Available children in " .. gameGui.Name .. ":")
		for _, child in pairs(gameGui:GetChildren()) do
			print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
		end
		return
	end
	
	print("ShopHandler: Shop frame found, setting up handlers...")
	
	-- Store UI reference for later use
	self.UI = gameGui
	self.ShopFrame = shopFrame
	
	-- Hide shop initially
	shopFrame.Visible = false
	
	-- Setup shop functionality
	self:SetupOpenButton()
	self:SetupCloseButton()
	
	print("✅ ShopHandler: Shop UI setup completed")
end

function ShopHandler:SetupOpenButton()
	-- Look for shop button in the UI
	-- Path: GameUI -> LeftPanel -> Shop -> Button
	print("ShopHandler: Looking for shop button...")
	
	local leftPanel = self.UI:FindFirstChild("LeftPanel")
	if not leftPanel then
		warn("ShopHandler: LeftPanel not found in GameUI")
		return
	end
	
	print("ShopHandler: LeftPanel found, looking for Shop...")
	local shopFrame = leftPanel:FindFirstChild("Shop")
	if not shopFrame then
		warn("ShopHandler: Shop frame not found in LeftPanel")
		return
	end
	
	print("ShopHandler: Shop found, looking for Button...")
	local shopButton = shopFrame:FindFirstChild("Button")
	if not shopButton then
		warn("ShopHandler: Button not found in Shop frame")
		return
	end
	
	print("ShopHandler: Shop button found: " .. shopButton.Name .. " (" .. shopButton.ClassName .. ")")
	
	-- Test if the button has the right events
	if shopButton:IsA("GuiButton") then
		local connection = shopButton.MouseButton1Click:Connect(function()
			print("ShopHandler: Shop button clicked!")
			print("ShopHandler: Button instance: " .. tostring(shopButton))
			print("ShopHandler: Button parent: " .. tostring(shopButton.Parent))
			print("ShopHandler: Button parent parent: " .. tostring(shopButton.Parent.Parent))
			self:OpenWindow()
		end)
		table.insert(self.Connections, connection)
		print("✅ ShopHandler: Open button connected")
		print("ShopHandler: Button connection created for: " .. tostring(shopButton))
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
	if self.Utilities and self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
		self.Utilities.TweenUI.FadeIn(self.ShopFrame, .3, function ()
			self.isAnimating = false
		end)
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
	if self.Utilities and self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
		self.Utilities.TweenUI.FadeOut(self.ShopFrame, .3, function () 
			self.ShopFrame.Visible = false
			self.isAnimating = false
		end)
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
