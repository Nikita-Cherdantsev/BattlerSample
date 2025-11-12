local MIN_RUNTIME = 8

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local startTime = os.clock()

local instancesFolder = ReplicatedFirst:WaitForChild("Instances", 5)
local loadingTemplate = instancesFolder and instancesFolder:FindFirstChild("LoadingScreen")
local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
local playerGui = player:WaitForChild("PlayerGui")

local loadingScreen = loadingTemplate and loadingTemplate:Clone() or playerGui:FindFirstChild("LoadingScreen")
if loadingScreen then
	loadingScreen.Name = "LoadingScreen"
	loadingScreen.Enabled = true
	loadingScreen.IgnoreGuiInset = true
	loadingScreen.ResetOnSpawn = false
	loadingScreen.Parent = playerGui
end

local controllersFolder = StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("Controllers")
local MainController = require(controllersFolder:WaitForChild("MainController"))

local clientModules = ReplicatedStorage:WaitForChild("ClientModules")
local LoadingScreenHandler = require(clientModules:WaitForChild("LoadingScreenHandler"))

LoadingScreenHandler:Init(MainController)
LoadingScreenHandler:Show()

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local function waitForClientReady()
	ReplicatedStorage:SetAttribute("ClientInitialized", ReplicatedStorage:GetAttribute("ClientInitialized") or false)
	if ReplicatedStorage:GetAttribute("ClientInitialized") then
		LoadingScreenHandler:SetClientReady()
		return
	end
	
	local connection
	connection = ReplicatedStorage:GetAttributeChangedSignal("ClientInitialized"):Connect(function()
		if ReplicatedStorage:GetAttribute("ClientInitialized") then
			connection:Disconnect()
			LoadingScreenHandler:SetClientReady()
		end
	end)
end

waitForClientReady()

local function waitForServerReady()
	ReplicatedStorage:SetAttribute("ServerInitialized", ReplicatedStorage:GetAttribute("ServerInitialized") or false)
	if ReplicatedStorage:GetAttribute("ServerInitialized") then
		LoadingScreenHandler:SetServerReady()
		return
	end
	
	local connection
	connection = ReplicatedStorage:GetAttributeChangedSignal("ServerInitialized"):Connect(function()
		if ReplicatedStorage:GetAttribute("ServerInitialized") then
			connection:Disconnect()
			LoadingScreenHandler:SetServerReady()
		end
	end)
end

waitForServerReady()

local elapsed = os.clock() - startTime
if elapsed < MIN_RUNTIME then
	task.wait(MIN_RUNTIME - elapsed)
end

LoadingScreenHandler:SetExternalReady()

