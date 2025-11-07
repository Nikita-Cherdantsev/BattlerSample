--[[
	MusicPlayer.client.lua - Background music player
	
	Plays music from ReplicatedStorage.MusicPlaylist in a shuffled loop.
	Each player gets their own music instance with individual volume control.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for music folder
local musicFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Music")

-- Fisher-Yates shuffle algorithm
local function shuffleList(list)
	local shuffled = {}
	-- Create a copy of the list
	for i = 1, #list do
		shuffled[i] = list[i]
	end
	
	-- Shuffle the copy
	for i = #shuffled, 2, -1 do
		local j = math.random(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	
	return shuffled
end

-- Main music loop
while true do
	-- Get current list of songs before each cycle (handles dynamic additions)
	local songs = musicFolder:GetChildren()
	
	if #songs > 0 then
		-- Shuffle songs for variety
		local shuffledSongs = shuffleList(songs)
		
		-- Play each song in shuffled order
		for _, song in ipairs(shuffledSongs) do
			if song:IsA("Sound") then
				song:Play()
				song.Ended:Wait()
			end
		end
	else
		-- Wait if no songs are available
		wait(1)
	end
end

