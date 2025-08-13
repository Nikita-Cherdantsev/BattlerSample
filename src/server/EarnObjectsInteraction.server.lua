local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Get the earn object function from RemoteHandler
local function handleEarnObject(player, part)
	-- Determine currency type and amount from part attributes or use defaults
	local currencyType = part:GetAttribute("CurrencyType") or "Currency1"
	local minAmount = part:GetAttribute("MinAmount") or 1
	local maxAmount = part:GetAttribute("MaxAmount") or 10
	local amount = math.random(minAmount, maxAmount)

	-- Apply multiplier
	local Multiplier = require(game.ReplicatedStorage.Modules.Multipliers)
	local finalAmount = amount * Multiplier.CurrencyMultiplier(player)

	-- Award currency
	if player.Data and player.Data.PlayerData and player.Data.PlayerData[currencyType] then
		player.Data.PlayerData[currencyType].Value += finalAmount
		print(string.format("[EARN] %s earned %d %s from %s", player.Name, finalAmount, currencyType, part:GetFullName()))
	else
		warn("[EARN] Could not award currency: ", currencyType, player.Name)
	end
end

local function setupPrompt(part)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then return end
	if prompt:GetAttribute("_EarnConnected") then return end -- чтобы не подключать дважды
	prompt:SetAttribute("_EarnConnected", true)
	print("[DEBUG] setupPrompt for", part:GetFullName())

	prompt.Triggered:Connect(function(player)
		print("[DEBUG] Triggered by", player.Name)
		handleEarnObject(player, part)
	end)
end

for _, part in ipairs(CollectionService:GetTagged("EarnObjects")) do
	setupPrompt(part)
end

CollectionService:GetInstanceAddedSignal("EarnObjects"):Connect(setupPrompt) 