-- In this module you can find things like Rebirth Multiplier. By using code such as Multipliers.RebirthMultiplier(Player) returns a number which is that player's multiplier. Useful if you have multipliers in multiple scripts

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameSettings = ReplicatedStorage["Game Settings"]

local Multipliers = {}

function Multipliers.RebirthMultiplier(Player)
	local Multi = 1
	
	if GameSettings.RebirthType.Value == "Linear" then
		Multi *= (Player.Data.PlayerData.Rebirth.Value * GameSettings.RebirthMultiplier.Value + 1) -- so multi = RebirthMulti + 1
	else
		Multi *= (GameSettings.RebirthMultiplier.Value + 0.5) ^ Player.Data.PlayerData.Rebirth.Value
	end
	
	return Multi	
end

function Multipliers.CurrencyMultiplier(Player)
	local Multiplier = GameSettings.DefaultCurrencyMultiplier.Value
	
	-- TODO: This is test value. Change it to config value or some formula.
	local milestone = 100
	if Player.Data.PlayerData.Currency3.Value >= milestone then
		Multiplier = 1
	end
	
	-- TODO: Uncomment this when the rebirth is implemented
	--[[Multi *= (Player.Data.Gamepasses.DoubleCurrency.Value and 2 or 1)
	Multi *= Multipliers.RebirthMultiplier(Player)]]
	
	return Multiplier
end

function Multipliers.GetLuckMultiplier(Player)
	return 1 * (Player.Data.Gamepasses.Lucky.Value and 2 or 1)
end

return Multipliers