--[[
	ShopHandler Module
	Handles shop and gamepass functionality
	
	This module manages:
	- Gamepass display and information
	- Purchase prompts
	- Shop UI management
	- Gamepass ownership status
]]

--// Services
local MarketPlaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Module
local ShopHandler = {}

--// State
ShopHandler.Connections = {}
ShopHandler._initialized = false
ShopHandler.Gamepasses = {}

--// Initialization
function ShopHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	self.Utilities = controller:GetModule("Utilities")
	
	if not self.ClientState:IsInitialized() then
		warn("ClientState not initialized, cannot initialize ShopHandler")
		return false
	end
	
	-- Setup shop functionality
	self:SetupGamepasses()
	
	self._initialized = true
	print("✅ ShopHandler initialized successfully!")
	return true
end

function ShopHandler:SetupGamepasses()
	local Frames = self.ClientState:GetFrames()
	local Data = self.ClientState:GetData()
	local Player = self.ClientState:GetPlayer()
	
	-- Get gamepasses from ReplicatedStorage
	local Gamepasses = ReplicatedStorage.Gamepasses
	
	for _, Gamepass in Gamepasses:GetChildren() do
		local NewGamepass = ReplicatedStorage.ClientUI.GamepassTemplate:Clone()
		
		-- Get gamepass info from Marketplace
		local GamepassInfo
		local Success, Error = pcall(function()
			GamepassInfo = MarketPlaceService:GetProductInfo(Gamepass.Value, Enum.InfoType.GamePass)
		end)
		
		if not Success then 
			warn("An error occurred while gathering gamepass data: "..Error) 
			NewGamepass:Destroy() 
			continue 
		end
		
		-- Setup gamepass UI
		self:SetupGamepassUI(NewGamepass, GamepassInfo, Gamepass, Data)
		
		-- Store gamepass reference
		self.Gamepasses[Gamepass.Name] = NewGamepass
		
		-- Parent to shop frame
		NewGamepass.Parent = Frames.Shop.Gamepasses
	end
end

function ShopHandler:SetupGamepassUI(NewGamepass, GamepassInfo, Gamepass, Data)
	local Player = self.ClientState:GetPlayer()
	
	-- Set gamepass information
	NewGamepass.InnerPart.ImageLabel.Image = "rbxassetid://"..(GamepassInfo.IconImageAssetId or 666669321)
	NewGamepass.InnerPart.Description.Text = GamepassInfo.Description 
	NewGamepass.InnerPart.GPName.Text = GamepassInfo.Name
	local gpValueObj = Data.Gamepasses:FindFirstChild(Gamepass.Name)
	local owned = gpValueObj and gpValueObj.Value
	NewGamepass.InnerPart.Price.Text = owned and "Owned ✅" or "\u{E002}"..(GamepassInfo.PriceInRobux or 10000)
	
	-- Connect ownership changes
	if gpValueObj then
		local connection = gpValueObj.Changed:Connect(function()
			NewGamepass.InnerPart.Price.Text = gpValueObj.Value and "Owned ✅" or "\u{E002}"..GamepassInfo.PriceInRobux
		end)
		table.insert(self.Connections, connection)
	end
	
	-- Setup purchase button
	local buttonConnection = NewGamepass.InnerPart.Button.MouseButton1Click:Connect(function()
		MarketPlaceService:PromptGamePassPurchase(Player, Gamepass.Value)
		self.Utilities.Audio.PlayAudio("Click")
	end)
	table.insert(self.Connections, buttonConnection)
end

--// Public Methods
function ShopHandler:IsInitialized()
	return self._initialized
end

function ShopHandler:GetGamepass(gamepassName)
	return self.Gamepasses[gamepassName]
end

function ShopHandler:GetAllGamepasses()
	return self.Gamepasses
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
	
	-- Clear gamepasses
	self.Gamepasses = {}
	
	self._initialized = false
	print("✅ ShopHandler cleaned up")
end

return ShopHandler 