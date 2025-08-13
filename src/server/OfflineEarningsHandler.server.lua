--[[
	OfflineEarningsHandler Module
	Handles offline earnings when players are not in the game
	
	Features:
	- Tracks when players leave the game
	- Calculates offline earnings based on autoclick logic
	- Limits offline earnings to 8 hours maximum
	- Resets timer when player rejoins
	- Prints detailed earnings information to output
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Variables
local Modules = ReplicatedStorage.Modules
local Multipliers = require(Modules.Multipliers)

--// Constants
local OFFLINE_EARNINGS_DURATION = 8 * 60 * 60 -- 8 hours in seconds

--// Offline Earnings Handler
local OfflineEarningsHandler = {}

function OfflineEarningsHandler:Init()
	-- Connect player events
	Players.PlayerAdded:Connect(function(Player)
		self:HandlePlayerJoin(Player)
	end)

	Players.PlayerRemoving:Connect(function(Player)
		self:HandlePlayerLeave(Player)
	end)

	print("✅ OfflineEarningsHandler initialized successfully!")
end

function OfflineEarningsHandler:HandlePlayerJoin(Player)
	-- Wait for player data to load
	repeat task.wait() until Player:FindFirstChild("Loaded") and Player.Loaded.Value or Player.Parent == nil
	if Player.Parent == nil then return end

	local PlayerData = Player.Data.PlayerData
	local currentTime = os.time()

	-- Check if player has offline earnings
	if PlayerData.LastOnlineTime.Value > 0 then
		local offlineTime = currentTime - PlayerData.LastOnlineTime.Value

		-- Only process if offline time is reasonable (not more than 24 hours)
		if offlineTime > 0 and offlineTime <= 24 * 60 * 60 then
			-- Limit earnings to 8 hours
			local effectiveOfflineTime = math.min(offlineTime, OFFLINE_EARNINGS_DURATION)

			-- Calculate earnings with new rates
			local currency2Earned = self:CalculateOfflineEarnings(Player, effectiveOfflineTime, "Currency2")
			local currency3Earned = self:CalculateOfflineEarnings(Player, effectiveOfflineTime, "Currency3")

			if currency2Earned > 0 or currency3Earned > 0 then
				-- Add earnings to player
				PlayerData.Currency2.Value = PlayerData.Currency2.Value + currency2Earned
				PlayerData.Currency3.Value = PlayerData.Currency3.Value + currency3Earned

				-- Print detailed offline earnings information
				local hours = math.floor(effectiveOfflineTime / 3600)
				local minutes = math.floor((effectiveOfflineTime % 3600) / 60)

				print("💰 " .. Player.Name .. " earned while offline (" .. hours .. "h " .. minutes .. "m):")
				if currency2Earned > 0 then
					print("   • Currency2: +" .. currency2Earned)
				end
				if currency3Earned > 0 then
					print("   • Currency3: +" .. currency3Earned)
				end
			end

			-- Reset LastOnlineTime to prevent future incorrect calculations
			PlayerData.LastOnlineTime.Value = 0
		else
			print("⚠️ " .. Player.Name .. " offline time too large or invalid, skipping earnings")
			-- Reset LastOnlineTime to prevent future issues
			PlayerData.LastOnlineTime.Value = 0
		end
	end
end

function OfflineEarningsHandler:HandlePlayerLeave(Player)
	if not Player:FindFirstChild("Data") then return end

	local PlayerData = Player.Data.PlayerData
	local currentTime = os.time()

	-- Record when player left
	PlayerData.LastOnlineTime.Value = currentTime

	print("👋 " .. Player.Name .. " left the game. Offline earnings timer started.")
end

function OfflineEarningsHandler:CalculateOfflineEarnings(Player, offlineTime, currencyType)
	-- Calculate earnings based on offline time and currency type
	local earnings = 0

	if currencyType == "Currency2" then
		-- 525 Currency2 per 2 minutes (120 seconds)
		earnings = math.floor(offlineTime / 120) * 525
	elseif currencyType == "Currency3" then
		-- 105 Currency3 per 4 minutes (240 seconds)
		earnings = math.floor(offlineTime / 240) * 105
	else
		-- Fallback for other currencies
		local earningsPerSecond = 1 * Multipliers.CurrencyMultiplier(Player)
		earnings = math.floor(offlineTime * earningsPerSecond)
	end

	return earnings
end

--// Initialize the handler
OfflineEarningsHandler:Init()

return OfflineEarningsHandler 