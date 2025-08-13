--// EDIT STUFF HERE:
local ADMINRANK = 254 -- What rank in group for admin


--// MAIN SCRIPT
local AdminFunctions = {}

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--// General
function AdminFunctions.IsPlayerAdmin(Player, AdminList) -- checks if user is allowed to use commands
	if table.find(AdminList, Player.UserId) then return true end -- In table
	
	local IsGroupGame = game.CreatorType == Enum.CreatorType.Group
	local CreatorId = game.CreatorId

	if IsGroupGame then
		return Player:GetRankInGroup(CreatorId) >= ADMINRANK
	else
		return CreatorId == Player.UserId
	end
end

function AdminFunctions.FindPlayerFromName(PlayerName)
	for _, Player in Players:GetPlayers() do
		if string.lower(Player.Name) == PlayerName then
			return Player
		end
	end
end

--// Stats
function AdminFunctions.FindStatFromStatName(Player, StatName)
	for _, Stat in Player.Data:GetDescendants() do
		if string.lower(Stat.Name) == StatName then
			return Stat
		end
	end
end

function AdminFunctions.RandomID(Folder)
	local Chance = math.random(1,10000)
	if Folder:FindFirstChild(Chance) then
		return AdminFunctions.RandomID(Folder) -- reroll if exists
	end
	return Chance
end

return AdminFunctions