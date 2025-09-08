-- ServerBootstrap.server.lua
-- This is the only auto-run Script on the server
-- It requires all modules and calls their init() functions where needed

local ServerScriptService = game:GetService("ServerScriptService")

-- Wait for all required modules to be available and require them
local DataStoreWrapper = require(ServerScriptService:WaitForChild("Persistence"):WaitForChild("DataStoreWrapper"))
local ProfileSchema = require(ServerScriptService:WaitForChild("Persistence"):WaitForChild("ProfileSchema"))
local ProfileManager = require(ServerScriptService:WaitForChild("Persistence"):WaitForChild("ProfileManager"))
local PlayerDataService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("PlayerDataService"))
local MatchService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("MatchService"))
local CombatEngine = require(ServerScriptService:WaitForChild("Services"):WaitForChild("CombatEngine"))
local RemoteEvents = require(ServerScriptService:WaitForChild("Network"):WaitForChild("RemoteEvents"))
local LevelUpDevHarness = require(ServerScriptService:WaitForChild("Services"):WaitForChild("LevelUpDevHarness"))

-- Runtime verification: ensure all required modules are properly loaded
local function VerifyModuleTypes()
	print("🔍 Verifying server module types...")
	
	local modules = {
		{name = "DataStoreWrapper", instance = DataStoreWrapper},
		{name = "ProfileSchema", instance = ProfileSchema},
		{name = "ProfileManager", instance = ProfileManager},
		{name = "PlayerDataService", instance = PlayerDataService},
		{name = "MatchService", instance = MatchService},
		{name = "CombatEngine", instance = CombatEngine},
		{name = "RemoteEvents", instance = RemoteEvents},
		{name = "LevelUpDevHarness", instance = LevelUpDevHarness}
	}
	
	for _, module in ipairs(modules) do
		if type(module.instance) == "table" then
			print("✅ " .. module.name .. " loaded successfully")
		else
			error("❌ " .. module.name .. " failed to load (got " .. type(module.instance) .. ")")
		end
	end
	
	print("🎯 All server modules loaded successfully")
end

-- Initialize the server
local function InitializeServer()
	print("🚀 Initializing server...")
	
	-- Verify all modules are the correct type
	VerifyModuleTypes()
	
	-- Initialize RemoteEvents (this sets up the network layer)
	if RemoteEvents.Init then
		RemoteEvents.Init()
		print("✅ RemoteEvents initialized")
		
		-- Verify Network folder was created
		local networkFolder = game.ReplicatedStorage:FindFirstChild("Network")
		if networkFolder then
			print("✅ Network folder created successfully")
		else
			warn("⚠️ Network folder not found after RemoteEvents.Init()")
		end
	else
		print("⚠️ RemoteEvents has no Init function")
	end
	
	-- Initialize PlayerDataService (this sets up player lifecycle)
	if PlayerDataService.Init then
		PlayerDataService.Init()
		print("✅ PlayerDataService initialized")
	else
		print("⚠️ PlayerDataService has no Init function")
	end
	
	-- Initialize MatchService (this sets up match handling)
	if MatchService.Init then
		MatchService.Init()
		print("✅ MatchService initialized")
	else
		print("⚠️ MatchService has no Init function")
	end
	
	-- Run Level-Up Dev Harness (Studio only)
	if LevelUpDevHarness.RunAllTests then
		LevelUpDevHarness.RunAllTests()
		print("✅ Level-Up Dev Harness completed")
	else
		print("⚠️ LevelUpDevHarness has no RunAllTests function")
	end
	
	print("🎉 Server initialization complete!")
end

-- Start the server
InitializeServer()
