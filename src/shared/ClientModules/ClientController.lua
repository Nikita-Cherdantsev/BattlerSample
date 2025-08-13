--[[
	ClientController Module
	Main orchestrator for all client modules
	
	This module manages the initialization and coordination
	of all client-side functionality.
]]

--// Services
local RunService = game:GetService("RunService")

--// Module
local ClientController = {}

--// Module References (will be populated during Init)
ClientController.Modules = {}
ClientController.Handlers = {}
ClientController.Connections = {}

--// Initialization
function ClientController:Init()
	print("Initializing ClientController...")
	
	-- Initialize ClientState first
	local ClientState = require(script.Parent.ClientState)
	local stateSuccess = ClientState:Init()
	
	if not stateSuccess then
		warn("Failed to initialize ClientState")
		return false
	end
	
	-- Store ClientState reference
	self.ClientState = ClientState
	
	-- Initialize core modules
	self:InitCoreModules()
	
	-- Initialize handlers (will be added as we create them)
	self:InitHandlers()
	
	-- Start the render loop
	self:StartRenderLoop()
	
	print("✅ ClientController initialized successfully!")
	return true
end

function ClientController:InitCoreModules()
	-- Load utility modules
	local Modules = self.ClientState:GetModules()
	
	self.Modules.Utilities = require(Modules.Utilities)
	self.Modules.Multipliers = require(Modules.Multipliers)
	
	print("✅ Core modules loaded")
end

function ClientController:InitHandlers()
	-- Initialize ClickerHandler
	local ClickerHandler = require(script.Parent.ClickerHandler)
	local clickerSuccess = ClickerHandler:Init(self)
	
	if clickerSuccess then
		self:AddHandler("ClickerHandler", ClickerHandler)
	else
		warn("Failed to initialize ClickerHandler")
	end
	
	-- Initialize UIHandler
	local UIHandler = require(script.Parent.UIHandler)
	local uiSuccess = UIHandler:Init(self)
	
	if uiSuccess then
		self:AddHandler("UIHandler", UIHandler)
	else
		warn("Failed to initialize UIHandler")
	end
	
	-- Initialize PerksHandler
	local PerksHandler = require(script.Parent.PerksHandler)
	local perksSuccess = PerksHandler:Init(self)

	if perksSuccess then
		self:AddHandler("PerksHandler", PerksHandler)
	else
		warn("Failed to initialize PerksHandler")
	end
	
	-- Initialize WheelHandler
	local WheelHandler = require(script.Parent.WheelHandler)
	local wheelSuccess = WheelHandler:Init(self)

	if wheelSuccess then
		self:AddHandler("WheelHandler", WheelHandler)
	else
		warn("Failed to initialize WheelHandler")
	end
	
	-- Initialize DailyHandler
	local DailyHandler = require(script.Parent.DailyHandler)
	local dailylSuccess = DailyHandler:Init(self)

	if dailylSuccess then
		self:AddHandler("DailyHandler", DailyHandler)
	else
		warn("Failed to initialize DailyHandler")
	end
	
	-- Initialize SettingsHandler
	-- TODO: @emegerd обработать настройки, пока что их не будет.
	--[[local SettingsHandler = require(script.Parent.SettingsHandler)
	local settingsSuccess = SettingsHandler:Init(self)
	
	if settingsSuccess then
		self:AddHandler("SettingsHandler", SettingsHandler)
	else
		warn("Failed to initialize SettingsHandler")
	end]]
	
	-- Initialize RebirthHandler
	--[[local RebirthHandler = require(script.Parent.RebirthHandler)
	local rebirthSuccess = RebirthHandler:Init(self)
	
	if rebirthSuccess then
		self:AddHandler("RebirthHandler", RebirthHandler)
	else
		warn("Failed to initialize RebirthHandler")
	end
	
	-- Initialize ShopHandler
	local ShopHandler = require(script.Parent.ShopHandler)
	local shopSuccess = ShopHandler:Init(self)
	
	if shopSuccess then
		self:AddHandler("ShopHandler", ShopHandler)
	else
		warn("Failed to initialize ShopHandler")
	end
	
	-- Initialize AreaHandler
	local AreaHandler = require(script.Parent.AreaHandler)
	local areaSuccess = AreaHandler:Init(self)
	
	if areaSuccess then
		self:AddHandler("AreaHandler", AreaHandler)
	else
		warn("Failed to initialize AreaHandler")
	end

	-- Initialize StatsHandler
	local StatsHandler = require(script.Parent.StatsHandler)
	local statsSuccess = StatsHandler:Init(self)
	
	if statsSuccess then
		self:AddHandler("StatsHandler", StatsHandler)
	else
		warn("Failed to initialize StatsHandler")
	end]]

	print("✅ Handlers initialized")
end

function ClientController:StartRenderLoop()
	-- Start the main render loop
	local connection = RunService.RenderStepped:Connect(function()
		self:Update()
	end)
	
	table.insert(self.Connections, connection)
	print("✅ Render loop started")
end

function ClientController:Update()
	-- Main update loop - call update methods for handlers that need it
	local areaHandler = self:GetHandler("AreaHandler")
	if areaHandler and areaHandler.Update then
		areaHandler:Update()
	end
end

--// Handler Management
function ClientController:AddHandler(name, handler)
	if self.Handlers[name] then
		warn("Handler", name, "already exists, overwriting...")
	end
	
	self.Handlers[name] = handler
	print("✅ Added handler:", name)
end

function ClientController:GetHandler(name)
	return self.Handlers[name]
end

function ClientController:GetModule(name)
	return self.Modules[name]
end

function ClientController:GetClientState()
	return self.ClientState
end

--// Cleanup
function ClientController:Cleanup()
	print("Cleaning up ClientController...")
	
	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}
	
	-- Clean up handlers
	for name, handler in pairs(self.Handlers) do
		if handler and handler.Cleanup then
			handler:Cleanup()
		end
	end
	self.Handlers = {}
	
	print("✅ ClientController cleaned up")
end

return ClientController 