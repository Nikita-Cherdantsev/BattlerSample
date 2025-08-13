local DS = game:GetService("DataStoreService")
local RS = game:GetService("ReplicatedStorage")

local Main = {}

local Cache = Instance.new("Folder")
Cache.Name = "Cache"
Cache.Parent = game.ServerStorage

local UserIds = Instance.new("Folder")
UserIds.Name = "UserIds"
UserIds.Parent = Cache

local Names = Instance.new("Folder")
Names.Name = "Names"
Names.Parent = Cache

local Modules = RS.Modules
local Short = require(Modules.Utilities).Short

local DataSave = RS["Game Settings"].DataSave.Value

function Main.GetNameFromUserId(Id)
	local Cached = Cache.UserIds:FindFirstChild(tostring(Id))

	if Cached then
		return tostring(Cached.Value)
	else
		local new
		pcall(function()
			new = game:GetService("Players"):GetNameFromUserIdAsync(Id)
		end)
		if new then
			local x = Instance.new("StringValue")
			x.Name = tostring(Id)
			x.Value = tostring(new)
			x.Parent = Cache.UserIds

			if not Cache.Names:FindFirstChild(tostring(new)) then
				local y = Instance.new("IntValue")
				y.Name = tostring(new)
				y.Value = tonumber(Id)
				y.Parent = Cache.Names
			end

			return tostring(new)
		end
	end

	return nil
end

local function EncodeNumber(Number)
	Number += 1
	Number = math.log10(Number)
	Number *= 270000000000
	Number = math.round(Number)
	return Number
end

local function DecodeNumber(Number)
	Number /= 270000000000
	Number = 10 ^ Number
	Number -= 1
	Number = math.round(Number)
	return Number
end

function Main.UploadLeaderboardStats(Player, Info)
	if Player:FindFirstChild("Loaded") and Player.Loaded.Value then
		local Stat = Player.Data[Info.Folder][Info.Stat].Value
		Stat = EncodeNumber(Stat)
		local Datastore = DS:GetOrderedDataStore(Info.Datastore..DataSave)
		Datastore:SetAsync(Player.UserId, Stat)
		task.wait(0.05)
	end
end

function Main.UpdateLeaderboard(Leaderboard, Info)
	local Leaderboard = workspace.airport.Leaderboards[Leaderboard]

	local Datastore = DS:GetOrderedDataStore(Info.Datastore..DataSave)
	local GetData = Datastore:GetSortedAsync(false, 100)
	local GetCurrent = GetData:GetCurrentPage()

	task.wait()

	local Sort = Leaderboard.SurfaceGui.MainFrame.Players.Scroll

	for Rank,Data in GetCurrent do
		local LBInstance = Sort:FindFirstChild(tostring(Rank))
		LBInstance.Visible = true
		LBInstance.Rank.Text = "#"..Rank
		local Username = Main.GetNameFromUserId(Data.key)
		if Username == nil then Username = "Failed to load" end
		LBInstance.PlrName.Text = Username 
		LBInstance.PlayerIcon.Image = game.Players:GetUserThumbnailAsync(Data.key, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		local Amount = Data.value
		Amount = Short.en(DecodeNumber(Amount))
		LBInstance.Amount.Text = Amount
	end	
end

function Main.Setup(Module)
	for _,Leaderboard in workspace.airport.Leaderboards:GetChildren() do
		if not Module[Leaderboard.Name] then continue end -- lb doesnt exist anymore
		local MainFrame = Leaderboard.SurfaceGui.MainFrame
		MainFrame.Title.Text = Leaderboard.Name == "Currency" and "Top 100 Most "..RS["Game Settings"].Currency1Name.Value or Module[Leaderboard.Name].Title
		MainFrame.Players.Amount.Text = Leaderboard.Name == "Currency" and RS["Game Settings"].Currency1Name.Value or Module[Leaderboard.Name].Stat
		
		local Template = RS.LeaderboardHandlerUI.Template
		if Leaderboard:FindFirstChild("Template") then
			Template = Leaderboard.Template
		end
		
		for i = 1,100 do			
			local Clone = Template:Clone()
			Clone.LayoutOrder = i
			Clone.Name = i
			Clone.Rank.Text = ""
			Clone.PlrName.Text = ""
			Clone.Amount.Text = ""
			Clone.Parent = MainFrame.Players.Scroll
		end 
	end
end

return Main