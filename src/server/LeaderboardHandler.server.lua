local Leaderboards = require(game.ReplicatedStorage.Modules.Leaderboards)
local Main = require(script.Main)

Main.Setup(Leaderboards)

while task.wait(5) do
	for Name, Info in Leaderboards do
		--// Upload Stats of Players
				
		for _, Player in game.Players:GetPlayers() do
			local suc,er = pcall(function()
				Main.UploadLeaderboardStats(Player, Info)
			end)

			if er then warn("Error while uploading leaderboard data: "..er) end

			task.wait(1)
		end
		
		--// Update Leaderboard

		task.wait(5)
		
		local suc,er = pcall(function()
			Main.UpdateLeaderboard(Name, Info)
		end)

		if er then warn("Error while updating leaderboards: "..er) end		
		
		task.wait(15)
	end
end