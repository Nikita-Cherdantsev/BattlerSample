--[[ This Script Handles Admin Commands

Current Commands:
/givestats Player Stat Amount

]]

local ADMINS = {
	265786219, -- Put userids here. If you are the owner of the game this is not required
	
}



--------- Main Script ---------

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--// Variables
local AdminFunctions = require(script.AdminFunctions)

function Main(Player) -- this code is called for each player joining
	if not AdminFunctions.IsPlayerAdmin(Player, ADMINS) then return end -- player is not an admin if this returns false
	
	Player.Chatted:Connect(function(Message)
		local SplittedMessage = string.split(Message, " ")
		local Command = string.lower(SplittedMessage[1])
		local PlayerName = string.lower(SplittedMessage[2])
		local Arg1 = string.lower(SplittedMessage[3]) or ""
		local Arg2 = SplittedMessage[4] and string.lower(SplittedMessage[4]) or ""
		
		if Command == "/givestats" then -- /givestats PlayerName StatName Amount
			local TargetPlayer = AdminFunctions.FindPlayerFromName(PlayerName)
			if TargetPlayer == nil then return end -- no player exists
			
			if Arg1 == string.lower(ReplicatedStorage["Game Settings"].CurrencyName.Value) then
				Arg1 = "currency"
			end
			
			local Stat = AdminFunctions.FindStatFromStatName(TargetPlayer, Arg1)
			if Stat == nil then return end -- stat does not exist
			
			if Stat:IsA("IntValue") or Stat:IsA("NumberValue") then
				Arg2 = tonumber(Arg2)
				if Arg2 == nil then return end
				
				Stat.Value = Arg2 -- set the stat to Arg2 if it's a number
			elseif Stat:IsA("BoolValue") then
				Stat.Value = Arg1 == "true" and true or false -- make it true if you put in True or true and the rest if false	
			elseif Stat:IsA("StringValue") then
				Stat.Value = Arg1
			end
		end
	end)
end

Players.PlayerAdded:Connect(Main)