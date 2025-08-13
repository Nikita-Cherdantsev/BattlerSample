--// Configure

local LoadingFunctions = {}
local Values = require(script.Parent.Values)
local DS = game:GetService("DataStoreService")

local RS = game:GetService("ReplicatedStorage")
local PlayerData = DS:GetDataStore(RS["Game Settings"].DataSave.Value)

local MPS = game:GetService("MarketplaceService")

local function CreateFolder(Player, FolderName)
	local NewFolder = Instance.new("Folder")
	NewFolder.Name = FolderName
	NewFolder.Parent = Player
	return NewFolder
end

--// Module

LoadingFunctions.LoadData = function(Player)
	local MainFolder = CreateFolder(Player,"Data")
	local Datastore

	local suc,er = pcall(function()
		Datastore = PlayerData:GetAsync(Player.UserId)
	end)

	if er then warn(er) Player:Kick("Failed to load. Make sure to allow API Services in studio & publish your games in order to make datastores work") return end

	if Datastore and Datastore.SessionId and game.JobId ~= Datastore.SessionId and os.time() - Datastore.LastInGame < 60 and not game:GetService("RunService"):IsStudio() then Player:Kick("Session Locked") end

	for _,FolderName in Values.Folders do
		if FolderName ~= "NonSaveValues" then
			CreateFolder(MainFolder, FolderName)
		else
			CreateFolder(Player, FolderName)
		end
	end

	--// Create all the non save values

	for _, Info in Values.NonSaveValues do
		local NewInstance = Instance.new(Info.Type)
		NewInstance.Name = Info.Name
		NewInstance.Value = Info.Value
		NewInstance.Parent = Player.NonSaveValues
	end

	--// Create all the save values

	for FolderName, FolderInfo in Values.SaveValues do	
		for _, Info in FolderInfo do
			local NewInstance = Instance.new(Info.Type)
			NewInstance.Name = Info.Name
			NewInstance.Value = Info.Value
			NewInstance.Parent = MainFolder[FolderName]

			if Datastore and Datastore[FolderName] then
				if Datastore[FolderName][Info.ID] ~= nil and Datastore[FolderName][Info.ID] ~= Info.Value then
					NewInstance.Value = Datastore[FolderName][Info.ID]
				end
			end
		end		
	end

	--// Check Gamepasses
	--// TODO: Uncomment this if you want to add gamepass support back in
	--[[for _,Gamepass in MainFolder.Gamepasses:GetChildren() do
		if Gamepass.Value then continue end -- only check if you DONT have it
		
		if RS.Gamepasses:FindFirstChild(Gamepass.Name) == nil then continue end
		
		local GPId = RS.Gamepasses[Gamepass.Name].Value
		Gamepass.Value = MPS:UserOwnsGamePassAsync(Player.UserId, GPId)
	end]]
end

return LoadingFunctions
