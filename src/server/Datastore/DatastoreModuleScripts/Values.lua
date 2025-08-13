return {
	["Folders"] = {
		"PlayerData",
		"NonSaveValues",
		"Gamepasses",
		"AutoDelete",
		"DailyBonus",
	},
	
	["SaveValues"] = {
		["PlayerData"] = {
			{Name = "Currency1", Value = 0, ID = 1, Type = "NumberValue"},
			{Name = "Music", Value = 0, ID = 2, Type = "BoolValue"},
			{Name = "Rebirth", Value = 0, ID = 3, Type = "NumberValue"},
			{Name = "BestZone", Value = 0, ID = 5, Type = "IntValue"},
			{Name = "Currency2", Value = 0, ID = 6, Type = "NumberValue"},
			{Name = "Currency3", Value = 0, ID = 7, Type = "NumberValue"},
			{Name = "Autoclick", Value = false, ID = 8, Type = "BoolValue"},
			{Name = "LastOnlineTime", Value = 0, ID = 9, Type = "NumberValue"},
			{Name = "OfflineEarningsStartTime", Value = 0, ID = 10, Type = "NumberValue"},
			
			--// Perks
			{Name = "Perk1", Value = 30, ID = 12, Type = "NumberValue"},
			{Name = "Perk2", Value = 20, ID = 13, Type = "NumberValue"},
			{Name = "Perk3", Value = 0, ID = 14, Type = "NumberValue"},
			{Name = "Perk4", Value = 0, ID = 15, Type = "NumberValue"},
			
			--// Wheel
			{Name = "WheelBet", Value = 1, ID = 16, Type = "IntValue"},
			
			--// Favorite
			{Name = "FavoriteLastSeen", Value = "", ID = 17, Type = "StringValue"},
		},
		
		["Gamepasses"] = {
			{Name = "DoubleCurrency", Value = false, ID = 1, Type = "BoolValue"},
			{Name = "MoreStorage1", Value = false, ID = 2, Type = "BoolValue"},
			{Name = "MoreStorage2", Value = false, ID = 3, Type = "BoolValue"},
			{Name = "Lucky", Value = false, ID = 6, Type = "BoolValue"}
		},
		
		["DailyBonus"] = {
			{Name = "LastLogin", Value = "", ID = 1, Type = "StringValue"},
			{Name = "Streak", Value = 0, ID = 2, Type = "IntValue"},
		}
	},
	
	["NonSaveValues"] = {
		{Name = "IsReady", Value = false, Type = "BoolValue"}
	},
}
