--[[
	CommandService - Handles developer commands via chat
]]

local CommandService = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)
local ProfileSchema = require(script.Parent.Parent.Persistence.ProfileSchema)
local ProfileSnapshotService = require(script.Parent.ProfileSnapshotService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local DEVELOPER_IDS = {
	[7823577556] = true,
	[8303502785] = true,
	[8768307230] = true,
}

local function IsDeveloper(player)
	if not player then
		return false
	end
	if RunService:IsStudio() then
		return true
	end
	return DEVELOPER_IDS[player.UserId] == true
end

local function ComputeSquadPower(profile)
	local CardStats = require(ReplicatedStorage.Modules.Cards.CardStats)
	local totalPower = 0
	for _, cardId in ipairs(profile.deck) do
		local cardEntry = profile.collection[cardId]
		local level = cardEntry and cardEntry.level or 1
		totalPower = totalPower + CardStats.ComputeCardPower(cardId, level)
	end
	return math.floor(totalPower * 10 + 0.5) / 10
end

local function ResetProfileCommand(player)
	if not IsDeveloper(player) then
		return false, "Only developers can use this command"
	end
	
	local userId = player.UserId
	print(string.format("[CommandService] Resetting profile for player %s (UserId: %d)", player.Name, userId))
	
	local newProfile = ProfileSchema.CreateProfile(userId)
	local BoxTypes = require(ReplicatedStorage.Modules.Loot.BoxTypes)
	local BoxRoller = require(ReplicatedStorage.Modules.Loot.BoxRoller)
	
	if not newProfile.lootboxes then
		newProfile.lootboxes = {}
	end
	
	local now = os.time()
	newProfile.lootboxes[1] = {
		id = BoxRoller.GenerateBoxId(),
		rarity = BoxTypes.BoxRarity.BEGINNER,
		state = BoxTypes.BoxState.READY,
		seed = BoxRoller.GenerateSeed(),
		source = "starter",
		startedAt = now,
		unlocksAt = now
	}
	
	newProfile.squadPower = ComputeSquadPower(newProfile)
	ProfileManager.ClearCache(userId)
	
	if not ProfileManager.SaveProfile(userId, newProfile) then
		warn(string.format("[CommandService] ❌ Failed to save reset profile for player %s", player.Name))
		return false, "Error saving profile"
	end
	
	if not ProfileManager.LoadProfile(userId) then
		warn(string.format("[CommandService] ❌ Failed to reload profile for player %s", player.Name))
		return false, "Error reloading profile"
	end
	
	if PlayerDataService.ClearCache then
		PlayerDataService.ClearCache(userId)
	end
	if PlayerDataService.EnsureProfileLoaded then
		PlayerDataService.EnsureProfileLoaded(player)
	end
	
	local snapshot = ProfileSnapshotService.GetSnapshot(player, {
		includeCollection = true,
		includeLoginInfo = true,
		includeDaily = true,
		includePlaytime = true
	})
	
	if snapshot then
		snapshot.forceReload = true
		snapshot.serverNow = os.time()
		
		local networkFolder = ReplicatedStorage:FindFirstChild("Network")
		local ProfileUpdated = networkFolder and networkFolder:FindFirstChild("ProfileUpdated")
		
		if ProfileUpdated then
			ProfileUpdated:FireClient(player, snapshot)
			print(string.format("[CommandService] ✅ Profile reset and sent to client for player %s", player.Name))
		else
			warn("[CommandService] ⚠️ ProfileUpdated not found, client will not receive update")
		end
	end
	
	return true, "Profile successfully reset to initial state"
end

local function OnPlayerChatted(player, message)
	if not IsDeveloper(player) or not message:match("^/resetprofile") then
		return
	end
	
	local pcallSuccess, wrappedResult = pcall(function()
		local success, message = ResetProfileCommand(player)
		return { success = success, message = message }
	end)
	
	if pcallSuccess and wrappedResult then
		if wrappedResult.success then
			print(string.format("[CommandService] ✅ %s: %s", player.Name, wrappedResult.message))
		else
			warn(string.format("[CommandService] ❌ %s: %s", player.Name, wrappedResult.message))
		end
	else
		warn(string.format("[CommandService] Error executing command for %s: %s", player.Name, tostring(wrappedResult)))
	end
end

function CommandService.Init()
	if TextChatService then
		local textChatCommands = TextChatService:FindFirstChild("TextChatCommands")
		if textChatCommands then
			local command = Instance.new("TextChatCommand")
			command.Name = "resetprofile"
			command.PrimaryAlias = "/resetprofile"
			command.Triggered:Connect(function(textSource)
				local player = Players:GetPlayerByUserId(textSource.UserId)
				if player and IsDeveloper(player) then
					OnPlayerChatted(player, "/resetprofile")
				end
			end)
			command.Parent = textChatCommands
		end
	end
	
	local function connectChat(player)
		player.Chatted:Connect(function(message)
			OnPlayerChatted(player, message)
		end)
	end
	
	Players.PlayerAdded:Connect(connectChat)
	for _, player in ipairs(Players:GetPlayers()) do
		connectChat(player)
	end
	
	print("✅ CommandService initialized")
end

return CommandService
