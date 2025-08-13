--[[
	SettingsHandler Module
	Handles settings and user preferences
	
	This module manages:
	- Music settings
	- Show other pets settings
	- Other user preferences
]]

--// Services
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Module
local SettingsHandler = {}

--// State
SettingsHandler.Connections = {}
SettingsHandler._initialized = false

--// Initialization
function SettingsHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	self.Utilities = controller:GetModule("Utilities")
	
	if not self.ClientState:IsInitialized() then
		warn("ClientState not initialized, cannot initialize SettingsHandler")
		return false
	end
	
	-- Setup settings functionality
	self:SetupMusicSetting()
	self:SetupShowOtherPetsSetting()
	
	self._initialized = true
	print("✅ SettingsHandler initialized successfully!")
	return true
end

function SettingsHandler:SetupMusicSetting()
	local Frames = self.ClientState:GetFrames()
	local PlayerData = self.ClientState:GetPlayerData()
	local Remotes = self.ClientState:GetRemotes()
	
	local SettingsScroll = Frames.Settings.ObjectHolder
	local MusicSetting = SettingsScroll.Music
	
	-- Setup button animations
	self.Utilities.ButtonAnimations.Create(MusicSetting.Toggle.On)
	self.Utilities.ButtonAnimations.Create(MusicSetting.Toggle.Off)
	
	-- Setup on button
	local onConnection = MusicSetting.Toggle.On.Click.MouseButton1Click:Connect(function()
		Remotes.Setting:FireServer("Music", true)
		self.Utilities.Audio.PlayAudio("Click")
	end)
	table.insert(self.Connections, onConnection)
	
	-- Setup off button
	local offConnection = MusicSetting.Toggle.Off.Click.MouseButton1Click:Connect(function()
		Remotes.Setting:FireServer("Music", false)
		self.Utilities.Audio.PlayAudio("Click")
	end)
	table.insert(self.Connections, offConnection)
	
	-- Setup music playback
	SoundService.Music.PlaybackSpeed = PlayerData.Music.Value and 1 or 0
	
	local musicConnection = PlayerData.Music.Changed:Connect(function()
		SoundService.Music.PlaybackSpeed = PlayerData.Music.Value and 1 or 0
	end)
	table.insert(self.Connections, musicConnection)
end

function SettingsHandler:SetupShowOtherPetsSetting()
	local Frames = self.ClientState:GetFrames()
	local Remotes = self.ClientState:GetRemotes()
	
	local SettingsScroll = Frames.Settings.ObjectHolder
	local ShowOtherPetsSetting = SettingsScroll.ShowOtherPets
	
	-- Setup button animations
	self.Utilities.ButtonAnimations.Create(ShowOtherPetsSetting.Toggle.On)
	self.Utilities.ButtonAnimations.Create(ShowOtherPetsSetting.Toggle.Off)
	
	-- Setup on button
	local onConnection = ShowOtherPetsSetting.Toggle.On.Click.MouseButton1Click:Connect(function()
		Remotes.Setting:FireServer("ShowOtherPets", true)
		self.Utilities.Audio.PlayAudio("Click")
	end)
	table.insert(self.Connections, onConnection)
	
	-- Setup off button
	local offConnection = ShowOtherPetsSetting.Toggle.Off.Click.MouseButton1Click:Connect(function()
		Remotes.Setting:FireServer("ShowOtherPets", false)
		self.Utilities.Audio.PlayAudio("Click")
	end)
	table.insert(self.Connections, offConnection)
end

--// Public Methods
function SettingsHandler:IsInitialized()
	return self._initialized
end

--// Cleanup
function SettingsHandler:Cleanup()
	print("Cleaning up SettingsHandler...")
	
	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}
	
	self._initialized = false
	print("✅ SettingsHandler cleaned up")
end

return SettingsHandler 