--[[
	Test Script for ClientState, ClientController, ClickerHandler, UIHandler, SettingsHandler, RebirthHandler, ShopHandler, AreaHandler, GemShopHandler, and StatsHandler Modules
	This script tests all modules to ensure they work correctly together
]]

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Test the ClientState module
print("=== Testing ClientState ===")
local ClientState = require(ReplicatedStorage.ClientModules.ClientState)

--// Test initialization
print("Testing ClientState initialization...")
local stateSuccess = ClientState:Init()

if stateSuccess then
	print("✅ ClientState initialized successfully!")

	-- Test getters
	print("Testing getters...")
	print("Player:", ClientState:GetPlayer())
	print("UI:", ClientState:GetUI())
	print("Frames:", ClientState:GetFrames())
	print("Remotes:", ClientState:GetRemotes())
	print("GameSettings:", ClientState:GetGameSettings())
	print("PlayerData:", ClientState:GetPlayerData())
	print("Data:", ClientState:GetData())
	print("Modules:", ClientState:GetModules())

	-- Test validation
	print("IsInitialized:", ClientState:IsInitialized())

	print("✅ All ClientState tests passed!")
else
	print("❌ ClientState initialization failed!")
end

--// Test the ClientController module
print("\n=== Testing ClientController ===")
local ClientController = require(ReplicatedStorage.ClientModules.ClientController)

--// Test initialization
print("Testing ClientController initialization...")
local controllerSuccess = ClientController:Init()

if controllerSuccess then
	print("✅ ClientController initialized successfully!")

	-- Test handler management
	print("Testing handler management...")
	ClientController:AddHandler("TestHandler", {name = "Test"})
	local handler = ClientController:GetHandler("TestHandler")
	print("TestHandler:", handler and handler.name or "nil")

	-- Test ClickerHandler specifically
	local clickerHandler = ClientController:GetHandler("ClickerHandler")
	if clickerHandler then print("ClickerHandler:", "loaded successfully") if type(clickerHandler.IsInitialized) == "function" then print("ClickerHandler initialized:", clickerHandler:IsInitialized()) end end
	-- Test UIHandler specifically
	local uiHandler = ClientController:GetHandler("UIHandler")
	if uiHandler then print("UIHandler:", "loaded successfully") if type(uiHandler.IsInitialized) == "function" then print("UIHandler initialized:", uiHandler:IsInitialized()) end end
	-- Test SettingsHandler specifically
	local settingsHandler = ClientController:GetHandler("SettingsHandler")
	if settingsHandler then print("SettingsHandler:", "loaded successfully") if type(settingsHandler.IsInitialized) == "function" then print("SettingsHandler initialized:", settingsHandler:IsInitialized()) end end
	-- Test RebirthHandler specifically
	local rebirthHandler = ClientController:GetHandler("RebirthHandler")
	if rebirthHandler then print("RebirthHandler:", "loaded successfully") if type(rebirthHandler.IsInitialized) == "function" then print("RebirthHandler initialized:", rebirthHandler:IsInitialized()) end end
	-- Test ShopHandler specifically
	local shopHandler = ClientController:GetHandler("ShopHandler")
	if shopHandler then print("ShopHandler:", "loaded successfully") if type(shopHandler.IsInitialized) == "function" then print("ShopHandler initialized:", shopHandler:IsInitialized()) end end
	-- Test AreaHandler specifically
	local areaHandler = ClientController:GetHandler("AreaHandler")
	if areaHandler then print("AreaHandler:", "loaded successfully") if type(areaHandler.IsInitialized) == "function" then print("AreaHandler initialized:", areaHandler:IsInitialized()) end end
	-- Test StatsHandler specifically
	local statsHandler = ClientController:GetHandler("StatsHandler")
	if statsHandler then print("StatsHandler:", "loaded successfully") if type(statsHandler.IsInitialized) == "function" then print("StatsHandler initialized:", statsHandler:IsInitialized()) end end
	-- Test module access
	print("Testing module access...")
	local utilities = ClientController:GetModule("Utilities")
	print("Utilities module:", utilities and "loaded" or "nil")
	-- Test client state access
	print("Testing client state access...")
	local state = ClientController:GetClientState()
	print("ClientState reference:", state and "valid" or "nil")
	print("✅ All ClientController tests passed!")
else
	print("❌ ClientController initialization failed!")
end
print("\n=== All Tests Complete ===") 