--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

--// Variables
local GameSettings = ReplicatedStorage["Game Settings"]
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Modules = ReplicatedStorage.Modules

local Multipliers = require(Modules.Multipliers)

local Cooldowns = {}

--// Script

Players.PlayerAdded:Connect(function(Player)
	Cooldowns[Player.Name] = false
	
	repeat wait() until Player:FindFirstChild("Loaded") and Player.Loaded.Value or Player.Parent == nil
	if Player.Parent == nil then return end
	
	Player.Data.PlayerData.Currency1.Value = 0
	
	if Player.Data.PlayerData.Autoclick.Value then
		Click(Player)
	end

	CheckDailyBonus(Player)
	CheckFavorite(Player)
end)

Players.PlayerRemoving:Connect(function(Player)
	Cooldowns[Player.Name] = nil
end)

--// Clicker
function Click(Player)
	if Cooldowns[Player.Name] == false then
		Cooldowns[Player.Name] = true

		local multiplier = Multipliers.CurrencyMultiplier(Player)
		local playerData = Player.Data.PlayerData
		
		-- Determine which reward path to take
		local shouldUseSpecialRewards = playerData.Currency3.Value > 37800 and playerData.Currency1.Value < playerData.Currency3.Value
		
		if shouldUseSpecialRewards then
			-- Special condition: Convert Currency3 to Currency1 and add standard rewards
			local currency1Reward = math.floor(playerData.Currency3.Value / 900 / 7)
			local currency2Reward = 5 * multiplier
			local currency3Reward = 1 * multiplier
			
			playerData.Currency1.Value += currency1Reward
			playerData.Currency2.Value += currency2Reward
			playerData.Currency3.Value += currency3Reward
		else
			-- Standard rewards
			local currency1Reward = 5 * multiplier
			local currency2Reward = 5 * multiplier
			local currency3Reward = 1 * multiplier
			
			playerData.Currency1.Value += currency1Reward
			playerData.Currency2.Value += currency2Reward
			playerData.Currency3.Value += currency3Reward
		end

		task.wait(0.08)
		Cooldowns[Player.Name] = false
		
		-- Handle autoclick recursion
		if playerData.Autoclick.Value then
			task.wait(1)
			Click(Player)
		end
	end
end

Remotes.Clicker.OnServerEvent:Connect(function(Player, isAutoclick)	
	if Player.Data.PlayerData.Autoclick.Value ~= isAutoclick then
		Player.Data.PlayerData.Autoclick.Value = isAutoclick
	end
	
	Click(Player)
end)

--// Music
Remotes.Setting.OnServerEvent:Connect(function(Player, SettingName, Toggled)
	Player.Data.PlayerData[SettingName].Value = Toggled
end)

--// Rebirth
function Rebirth(Player) -- this will run the action when you passed all requirements for rebirthing
	Player.Data.PlayerData.Currency.Value = 0
	Player.Data.PlayerData.Rebirth.Value += 1
	Player.Data.PlayerData.Currency2.Value += 10 -- gems
end

Remotes.Rebirth.OnServerEvent:Connect(function(Player)
	if Cooldowns[Player.Name] == false then
		Cooldowns[Player.Name] = true	
		if GameSettings.RebirthType.Value == "Linear" then
			if Player.Data.PlayerData.Currency.Value >= GameSettings.RebirthBasePrice.Value * (Player.Data.PlayerData.Rebirth.Value + 1) then
				Rebirth(Player)
			end
		else
			if Player.Data.PlayerData.Currency.Value >= GameSettings.RebirthBasePrice.Value * (GameSettings.RebirthMultiplier.Value + 1.25) ^ Player.Data.PlayerData.Rebirth.Value then
				Rebirth(Player)
			end
		end
		task.wait(0.08)
		Cooldowns[Player.Name] = false
	end
end)

--// Area
Remotes.Area.OnServerEvent:Connect(function(Player)
	if Cooldowns[Player.Name] == true then return end
	Cooldowns[Player.Name] = true

	coroutine.wrap(function()
		task.wait(0.08)
		Cooldowns[Player.Name] = false
	end)()

	local NextArea = ReplicatedStorage.Areas:FindFirstChild(Player.Data.PlayerData.BestZone.Value + 1)
	if not NextArea then return end


	if Player.Data.PlayerData.Currency.Value < NextArea.Cost.Value then return end

	if NextArea.Cost.Value == -1 then return end -- max area

	Player.Data.PlayerData.Currency.Value -= NextArea.Cost.Value
	Player.Data.PlayerData.BestZone.Value = tonumber(NextArea.Name)
end)

--// Perks
local PERK_EFFECTS = {
	Perk1 = { 
		-- Multiple image effects for Perk1 (images only)
		{ imageId = "88224089958984", soundId = nil, videoId = nil },
		{ imageId = "113430709308236", soundId = nil, videoId = nil },
		{ imageId = "118200943436600", soundId = nil, videoId = nil },
		{ imageId = "132683869426920", soundId = nil, videoId = nil },
		{ imageId = "126360424413498", soundId = nil, videoId = nil },
		{ imageId = "131772133367628", soundId = nil, videoId = nil },
		{ imageId = "109970755429378", soundId = nil, videoId = nil },
		{ imageId = "113294402436048", soundId = nil, videoId = nil },
		{ imageId = "104780914781127", soundId = nil, videoId = nil },
		{ imageId = "119803664729741", soundId = nil, videoId = nil },
		{ imageId = "108271835257988", soundId = nil, videoId = nil },
		{ imageId = "95808135393720", soundId = nil, videoId = nil }
	},
	Perk2 = { 
		-- Multiple sound effects for Perk2 (sounds only)
		{ imageId = nil, soundId = "103139190010039", videoId = nil },
		{ imageId = nil, soundId = "100993845767628", videoId = nil },
		{ imageId = nil, soundId = "74869934809969", videoId = nil },
		{ imageId = nil, soundId = "81856023519414", videoId = nil },
		{ imageId = nil, soundId = "100339908699018", videoId = nil },
		{ imageId = nil, soundId = "121157255388803", videoId = nil }
	},
	Perk3 = { 
		-- Multiple video effects for Perk3 (videos only - for future release)
		{ imageId = nil, soundId = nil, videoId = "5608330602" },
		{ imageId = nil, soundId = nil, videoId = "421058925" },
		{ imageId = nil, soundId = nil, videoId = "421058926" },
		{ imageId = nil, soundId = nil, videoId = "421058927" }
	},
	-- Add more perks here
}
local PERK_EARN = {
	Perk1 = { 
		Currency2 = 2000, Currency3 = 1200
	},
	Perk2 = { 
		Currency2 = 120000, Currency3 = 30000
	},
	Perk3 = { 
		Currency1 = 100, Currency2 = 2000, Currency3 = 100
	},
	-- Add more perks here
}
local PERK_RADIUS = 150

-- Get nearby players to play sound for
local function getNearbyPlayers(originPlayer, radius)
	local originChar = originPlayer.Character
	if not originChar or not originChar:FindFirstChild("HumanoidRootPart") then return {} end

	local originPos = originChar.HumanoidRootPart.Position
	local nearbyPlayers = {}

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= originPlayer then
			local char = player.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				local distance = (char.HumanoidRootPart.Position - originPos).Magnitude
				if distance <= radius then
					table.insert(nearbyPlayers, player)
				end
			end
		end
	end

	return nearbyPlayers
end

-- Function to show the usage of certain perk
local function usePerk(player: Player, perkName: string, duration: number)
	local randomEffectId = math.random(1, #PERK_EFFECTS[perkName])
	duration = duration or 5
	
	-- Get nearby players to play sound / show video
	local nearbyPlayers = getNearbyPlayers(player, PERK_RADIUS)

	-- Also include the activating player
	table.insert(nearbyPlayers, player)

	local effect = PERK_EFFECTS[perkName][randomEffectId]
	local imageId = effect.imageId
	local soundId = effect.soundId
	local videoId = effect.videoId
	
	-- Fire to each nearby player
	for _, nearbyPlayer in ipairs(nearbyPlayers) do
		Remotes.PlayPerkEffect:FireClient(nearbyPlayer, player, duration, imageId, soundId, videoId)
	end
end

Remotes.UsePerk.OnServerEvent:Connect(function(Player, perkName : string)
	local playerData = Player.Data.PlayerData
	
	if not playerData[perkName] then
		warn("Unknown perk:", perkName)
		return
	end
	
	if playerData[perkName].Value <= 0 then
		return
	end
	
	-- Consume the perk
	playerData[perkName].Value -= 1
	
	-- Award currency rewards
	local perkRewards = PERK_EARN[perkName]
	if perkRewards then
		for currency, amount in pairs(perkRewards) do
			if playerData[currency] then
				playerData[currency].Value += amount
			else
				warn("Trying to update unknown currency:", currency)
			end
		end
	end
	
	-- Trigger perk effects
	usePerk(Player, perkName)
end)

--// Wheel
local WHEEL_REWARDS = {
	{ Count = 5, Chance = 15, Name = "Perk2" },
	{ Count = 50000, Chance = 5, Name = "Currency3" },
	{ Count = 10, Chance = 25, Name = "Perk1" },
	{ Count = 25000, Chance = 5, Name = "Currency3" },
	{ Count = 5, Chance = 15, Name = "Perk2" },
	{ Count = 10000, Chance = 5, Name = "Currency3" },
	{ Count = 10, Chance = 25, Name = "Perk1" },
	{ Count = 5000, Chance = 5, Name = "Currency3" },
}

local WHEEL_PRICES = {
	{ Bet = 1, Price = 9, DiscountPrice = 9, ProductID = 3360576738 },
	{ Bet = 5, Price = 45, DiscountPrice = 18, ProductID = 3360577931 },
	{ Bet = 10, Price = 90, DiscountPrice = 36, ProductID = 3360578507 },
	{ Bet = 100, Price = 900, DiscountPrice = 360, ProductID = 3360579277 },
	{ Bet = 500, Price = 4500, DiscountPrice = 450, ProductID = 3360579810 },
}

local function wheelSpin(player: Player, perkName: string, duration: number)
	local totalChance = 0
	for _, reward in ipairs(WHEEL_REWARDS) do
		totalChance += reward.Chance
	end

	local roll = math.random() * totalChance
	local cumulative = 0
	for i, reward in ipairs(WHEEL_REWARDS) do
		cumulative += reward.Chance
		if roll <= cumulative then
			return {Index = i, Name = reward.Name, Count = reward.Count}
		end
	end

	local last = WHEEL_REWARDS[#WHEEL_REWARDS]
	return {Index = #WHEEL_REWARDS, Name = last.Name, Count = last.Count}
end

Remotes.WheelRequestSpin.OnServerEvent:Connect(function(Player)
	local priceInfo = WHEEL_PRICES[Player.Data.PlayerData.WheelBet.Value]
	local success, errorMessage = pcall(function()
		MarketplaceService:PromptProductPurchase(Player, priceInfo.ProductID)
	end)
end)

-- Handle post-purchase logic
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local Player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	
	if not Player then
		-- Delay processing until player is available
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	local priceInfo = WHEEL_PRICES[Player.Data.PlayerData.WheelBet.Value]

	local reward = wheelSpin()
	local rewardAmount = reward.Count * priceInfo.Bet
	
	Player.Data.PlayerData[reward.Name].Value += rewardAmount
	Remotes.WheelSpinResult:FireClient(Player, reward.Index, reward.Name, rewardAmount)
	
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.PromptProductPurchaseFinished:Connect(function(playerId, productId, wasPurchased)
	if not wasPurchased then
		local Player = Players:GetPlayerByUserId(playerId)
		if Player then
			-- Send false result to unlock UI
			Remotes.WheelSpinResult:FireClient(Player, wasPurchased)
		end
	end
end)

Remotes.WheelBet.OnServerEvent:Connect(function(Player, bet)
	Player.Data.PlayerData.WheelBet.Value = bet
end)

Remotes.WheelGetData.OnServerInvoke = function()
	local Rewards = {}
	for _, reward in ipairs(WHEEL_REWARDS) do
		table.insert(Rewards, {Name = reward.Name, Count = reward.Count})
	end
	local Prices = {}
	for _, price in ipairs(WHEEL_PRICES) do
		table.insert(Prices, {Bet = price.Bet, Price = price.Price, DiscountPrice = price.DiscountPrice})
	end
	return { Rewards = Rewards, Prices = Prices } 
end

--// Daily
local DAILY_REWARDS = {
	{
		{ Name = "Perk1",  Count = 100 },		
	},
	{
		{ Name = "Perk2",  Count = 30 },		
	},
	{
		{ Name = "Perk1",  Count = 100 },	
	},
	{
		{ Name = "Perk2",  Count = 30 },	
	},
	{
		{ Name = "Perk1",  Count = 100 },	
	},
	{
		{ Name = "Currency3",  Count = 50000 },	
	},
	{
		{ Name = "Perk1",  Count = 100 },	
		{ Name = "Perk2",  Count = 30 },	
	},
}

-- Helper
local function getDateKey(dt)
	return dt:ToIsoDate() -- "YYYY-MM-DD"
end

local function getDaysBetween(date1, date2)
	local d1 = DateTime.fromIsoDate(date1)
	local diff = date2.UnixTimestamp - d1.UnixTimestamp
	return math.floor(diff / 86400)
end

local function canClaimBonus(Player)
	local data = Player.Data.DailyBonus
	if data.LastLogin.Value == "" then return true end

	local now = DateTime.now()
	local daysSince = getDaysBetween(data.LastLogin.Value, now)

	if daysSince == 1 then
		return true
	elseif daysSince == 0 then
		return false -- already claimed today
	else
		return true -- missed a day -> reset
	end
end

function CheckDailyBonus(Player)
	if canClaimBonus(Player) then
		Remotes.DailyBonus:FireClient(Player, "Show", DAILY_REWARDS, Player.Data.DailyBonus.Streak.Value + 1, false)
	end
end

Remotes.DailyBonus.OnServerEvent:Connect(function(Player, action)
	if action == "ShowRequest" then
		local isClaimed = not canClaimBonus(Player)
		Remotes.DailyBonus:FireClient(Player, "Show", DAILY_REWARDS, Player.Data.DailyBonus.Streak.Value, isClaimed)
	elseif action == "Claim" then
		local data = Player.Data.DailyBonus
		local now = DateTime.now()
		local streak = data.Streak.Value or 0
		local lastLogin = data.LastLogin.Value

		local eligible = canClaimBonus(Player)
		if not eligible then return end

		local daysMissed = lastLogin ~= "" and getDaysBetween(lastLogin, now) or 0
		if daysMissed > 1 then
			streak = 0 -- reset
		end

		streak = streak + 1
		if streak > 7 then streak = 1 end -- wrap if more than 7

		-- Give reward
		local rewards = DAILY_REWARDS[streak]
		for _, reward in ipairs(rewards) do
			if Player.Data.PlayerData[reward.Name] then
				Player.Data.PlayerData[reward.Name].Value += reward.Count
				print(" 📅 Daily → claim reward for day " .. streak .. ": [ ".. reward.Name.. " ] = " .. reward.Count)
			end
		end
		
		Player.Data.DailyBonus.Streak.Value = streak
		Player.Data.DailyBonus.LastLogin.Value = getDateKey(now)
		print(" 📅 Daily → save [ Streak ] = " .. streak .. ", [ LastLogin ] = " .. Player.Data.DailyBonus.LastLogin.Value)
		
		Remotes.DailyBonus:FireClient(Player, "Claimed", DAILY_REWARDS, streak, true)
	end
end)

--// Favorite
function CheckFavorite(Player)
	local currentDate = string.match(getDateKey(DateTime.now()), "^%d+%-%d+%-%d+")
	local lastPromptDate = Player.Data.PlayerData.FavoriteLastSeen.Value
	local shouldShowPrompt = (lastPromptDate ~= currentDate)
	
	if shouldShowPrompt then
		-- Wait 5 minutes then show the prompt
		task.delay(5 * 60, function()
			if Player and Player.Parent then
				Remotes.Favorite:FireClient(Player)
			end
		end)
		
		Player.Data.PlayerData.FavoriteLastSeen.Value = currentDate
	end
end