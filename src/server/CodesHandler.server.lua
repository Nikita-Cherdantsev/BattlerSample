local Codes = {
	["100CASH"] = {100, "Currency"}, -- Put in amount, then the stat name
	["100DIAMONDS"] = {100, "Diamonds"},
	["3REBIRTHS"] = {3, "Rebirths"}
}



--------- Main Script ---------

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

--// Functions
function RandomID(Folder)
	local Chance = math.random(1, 20000)
	if Folder:FindFirstChild(tostring(Chance)) then
		return RandomID(Folder)
	end
	return Chance
end

--// Variables
local CodeStore = DataStoreService:GetDataStore("CodesStore")

--// Main
ReplicatedStorage.Remotes.RedeemCode.OnServerEvent:Connect(function(Player, Code)
	if not Codes[Code] then return end -- code doesnt exist

	local isRedeemed = CodeStore:GetAsync(Code.."_"..tostring(Player.UserId))
	
	if isRedeemed then return end -- Already redeemed
	
	if type(Codes[Code][1]) == "number" then -- Stat
		if Codes[Code][2] == "Diamonds" then
			Player.Data.PlayerData.Currency2.Value += Codes[Code][1]
		elseif Codes[Code][2] == "Currency" then
			Player.Data.PlayerData.Currency.Value += Codes[Code][1]
		elseif Codes[Code][2] == "Rebirths" then
			Player.Data.PlayerData.Rebirth.Value += Codes[Code][1]
		else
			return
		end
	end
	CodeStore:SetAsync(Code.."_"..tostring(Player.UserId), true)
end)