local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")

local badgeId = 144694100307654

-- Функция для проверки и присвоения бейджа
local function awardBadge(player)
	-- Проверяем информацию о бейдже
	local success, badgeInfo = pcall(BadgeService.GetBadgeInfoAsync, BadgeService, badgeId)
	if success and badgeInfo.IsEnabled then
		-- Проверяем, получал ли игрок ранее этот бейдж
		local hasBadge = BadgeService:UserHasBadgeAsync(player.UserId, badgeId)
		if not hasBadge then
			-- Присваиваем бейдж
			local awarded, errorMessage = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, badgeId)
			if not awarded then
				warn("Ошибка при присвоении бейджа:", errorMessage)
			end
		end
	else
		warn("Ошибка при получении информации о бейдже или бейдж отключен.")
	end
end

-- Пример: присвоение бейджа при входе игрока в игру
Players.PlayerAdded:Connect(function(player)
	-- Здесь можно добавить дополнительные условия для присвоения бейджа
	awardBadge(player)
end)
