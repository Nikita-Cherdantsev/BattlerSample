--[[
	ClientState Module
	Manages all shared state for client modules
	
	This module centralizes all the common references and state
	that multiple client modules need to access.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Module
local ClientState = {}

--// State Variables
ClientState.Player = nil
ClientState.UI = nil
ClientState.Frames = nil
ClientState.Remotes = nil
ClientState.GameSettings = nil
ClientState.PlayerData = nil
ClientState.Data = nil
ClientState.Modules = nil

--// Initialization
function ClientState:Init()
	-- Wait for player to be fully loaded
	self.Player = Players.LocalPlayer
	repeat wait() until self.Player:FindFirstChild("Loaded") and self.Player.Loaded.Value or self.Player.Parent == nil
	
	if self.Player.Parent == nil then 
		warn("Player left before ClientState could initialize")
		return false 
	end
	
	-- Initialize data references
	self.Data = self.Player.Data
	self.PlayerData = self.Data.PlayerData
	
	-- Initialize game settings and modules
	self.GameSettings = ReplicatedStorage["Game Settings"]
	self.Modules = ReplicatedStorage.Modules
	
	-- Initialize UI references
	self.UI = self.Player.PlayerGui:WaitForChild("GameUI")
	self.Frames = self.UI.Frames
	
	-- Initialize remotes
	self.Remotes = ReplicatedStorage.Remotes
	
	print("ClientState initialized successfully")
	return true
end

--// Getters for safety
function ClientState:GetPlayer()
	return self.Player
end

function ClientState:GetUI()
	return self.UI
end

function ClientState:GetFrames()
	return self.Frames
end

function ClientState:GetRemotes()
	return self.Remotes
end

function ClientState:GetGameSettings()
	return self.GameSettings
end

function ClientState:GetPlayerData()
	return self.PlayerData
end

function ClientState:GetData()
	return self.Data
end

function ClientState:GetModules()
	return self.Modules
end

--// Validation
function ClientState:IsInitialized()
	return self.Player ~= nil and self.UI ~= nil and self.Remotes ~= nil
end

return ClientState 