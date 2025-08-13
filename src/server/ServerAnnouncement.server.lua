-- ServerAnnouncement.lua
-- Server-side script for sending system announcements
-- Place this in ServerScriptService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("Starting ServerAnnouncement")

-- Create RemoteEvent if it doesn't exist
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local AnnouncementEvent = Remotes:FindFirstChild("Announcement")
if not AnnouncementEvent then
	AnnouncementEvent = Instance.new("RemoteEvent")
	AnnouncementEvent.Name = "Announcement"
	AnnouncementEvent.Parent = Remotes
end

-- Define the messages in the order they should be displayed
local Messages = {
	{
		id = "welcome",
		text = "Welcome to Football Card Collection Game!",
		color = Color3.fromRGB(0, 170, 255), -- Blue
		playerOnly = true, -- This message is customized per player
	},
	{
		id = "beta",
		text = "🎮 Game is in beta! Updates 2-3 times per week",
		color = Color3.fromRGB(0, 170, 255), -- Blue
	},
	{
		id = "code",
		text = "🎁 Use 'LEGENDARYSTART', next code at 50 likes",
		color = Color3.fromRGB(255, 215, 0), -- Gold
	},
	{
		id = "like",
		text = "👍 Enjoying the game? Press the like button!",
		color = Color3.fromRGB(85, 255, 85), -- Green
	}
}

-- Keep track of what messages players have seen to avoid duplicates
local PlayerRecentMessages = {}

-- Common interval for all messages is 7 minutes
local MESSAGE_INTERVAL = 180 -- 7 minutes

-- Function to broadcast message to all players
local function BroadcastAnnouncement(messageId, text, color)
	-- Skip welcome message in global broadcasts
	if messageId == "welcome" then
		return
	end

	-- Mark this message as recently seen for all players
	for _, player in pairs(Players:GetPlayers()) do
		if not PlayerRecentMessages[player.UserId] then
			PlayerRecentMessages[player.UserId] = {}
		end

		PlayerRecentMessages[player.UserId][messageId] = true
	end

	-- Send the message to all players
	AnnouncementEvent:FireAllClients(text, color)
	print("Broadcasting: " .. text)
end

-- Function to send message to specific player
local function SendPlayerAnnouncement(player, messageId, text, color)
	-- Skip if player recently saw this message (unless it's the welcome message)
	if messageId ~= "welcome" then
		if PlayerRecentMessages[player.UserId] and PlayerRecentMessages[player.UserId][messageId] then
			print("Skipping duplicate message for " .. player.Name .. ": " .. messageId)
			return
		end

		-- Mark message as seen
		if not PlayerRecentMessages[player.UserId] then
			PlayerRecentMessages[player.UserId] = {}
		end

		PlayerRecentMessages[player.UserId][messageId] = true
	end

	-- For welcome message, customize it with player name
	if messageId == "welcome" then
		text = "Welcome to the game, " .. player.Name .. "!"
	end

	-- Send the message
	AnnouncementEvent:FireClient(player, text, color)
	print("Sending to " .. player.Name .. ": " .. text)
end

-- Clear recent messages after some time
local function ClearRecentMessage(player, messageId)
	spawn(function()
		wait(MESSAGE_INTERVAL * 0.8) -- Clear a bit before the next cycle

		if player and player.Parent and PlayerRecentMessages[player.UserId] then
			PlayerRecentMessages[player.UserId][messageId] = nil
			print("Cleared recent message for " .. player.Name .. ": " .. messageId)
		end
	end)
end

-- Show welcome message and all regular messages when players join
Players.PlayerAdded:Connect(function(player)
	-- Initialize player's recent messages
	PlayerRecentMessages[player.UserId] = {}

	-- Wait a bit before showing welcome message
	wait(2)

	-- Show welcome and all regular messages in sequence
	for i, message in ipairs(Messages) do
		-- Skip customization for regular messages
		if message.playerOnly then
			SendPlayerAnnouncement(player, message.id, message.text, message.color)
		else
			SendPlayerAnnouncement(player, message.id, message.text, message.color)

			-- Set up to clear this message after some time
			ClearRecentMessage(player, message.id)
		end

		-- Wait between messages
		if i < #Messages then
			wait(30) -- 4 second delay between messages
		end
	end
end)

-- Clean up when player leaves
Players.PlayerRemoving:Connect(function(player)
	PlayerRecentMessages[player.UserId] = nil
end)

-- Start sequential periodic messages
local function StartSequentialMessages()
	-- Start from the first non-welcome message
	local currentIndex = 2 -- Skip the welcome message which is index 1

	-- Single loop that cycles through all standard messages
	spawn(function()
		wait(300) -- Initial delay before starting the cycle

		while true do
			-- Get the current message
			local message = Messages[currentIndex]

			-- Skip player-only messages in the broadcast
			if not message.playerOnly then
				-- Broadcast to all players
				BroadcastAnnouncement(message.id, message.text, message.color)

				-- Clear the message from recent history after some time
				for _, player in pairs(Players:GetPlayers()) do
					ClearRecentMessage(player, message.id)
				end
			end

			-- Move to the next message (loop back if at the end)
			currentIndex = currentIndex + 1
			if currentIndex > #Messages or Messages[currentIndex].playerOnly then
				currentIndex = 2 -- Reset to first standard message
			end

			-- Wait the common interval
			wait(MESSAGE_INTERVAL)
		end
	end)
end

-- Expose global functions (just in case they're needed)
_G.BroadcastAnnouncement = function(text, color)
	AnnouncementEvent:FireAllClients(text, color)
end

_G.SendPlayerAnnouncement = function(player, text, color)
	AnnouncementEvent:FireClient(player, text, color)
end

-- Start the sequential periodic messages
StartSequentialMessages()

print("ServerAnnouncement initialized")