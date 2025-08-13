--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

--// Module
local PerksHandler = {}

--// State
PerksHandler.Connections = {}
PerksHandler._initialized = false

--// Initialization
function PerksHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	self.Utilities = controller:GetModule("Utilities")

	-- Setup perks functionality
	self:SetupPerks()

	self._initialized = true
	print("✅ PerksHandler initialized successfully!")
	return true
end

function PerksHandler:SetupPerks()
	local UI = self.ClientState:GetUI()
	local Remotes = self.ClientState:GetRemotes()
	local PlayerData = self.ClientState:GetPlayerData()

	-- Setup perks
	self:SetupPerk1(UI, Remotes, PlayerData)
	self:SetupPerk2(UI, Remotes, PlayerData)
	self:SetupPerk3(UI, Remotes, PlayerData)
	
	-- Play visual effect if using is successful
	local connection = Remotes.PlayPerkEffect.OnClientEvent:Connect(function(activatingPlayer, duration, imageId, soundId, videoId)
		PerksHandler:PlayEffect(activatingPlayer, duration, imageId, soundId, videoId)
	end)

	table.insert(self.Connections, connection)
	
	-- TODO: future updates.
	--self:SetupPerk4(UI, Remotes)
end

function PerksHandler:SetupPerk1(UI, Remotes, PlayerData)
	-- Create button animations
	-- TODO: @emegerd добавить обработку анимаций кнопок с наведением.
	-- self.Utilities.ButtonAnimations.Create(UI.Clicker)

	-- Connect input events for the perk
	local button = UI.BottomPanel.Perk1.Button
	self:SetupButtonInputEvents(button, Remotes)
	
	-- Setup perk amount
	local oldAmount = PlayerData.Perk1.Value
	local amount = UI.BottomPanel.Perk1.Amount
	
	amount.Text = self.Utilities.Short.en(oldAmount)

	local connection = PlayerData.Perk1.Changed:Connect(function(newAmount)
		task.spawn(function()
			if newAmount ~= oldAmount then
				amount.Text = self.Utilities.Short.en(newAmount)
			end
		end)

		oldAmount = newAmount
	end)
	
	table.insert(self.Connections, connection)
end

function PerksHandler:SetupPerk2(UI, Remotes, PlayerData)
	-- Create button animations
	-- TODO: @emegerd добавить обработку анимаций кнопок с наведением.
	-- self.Utilities.ButtonAnimations.Create(UI.Clicker)

	-- Connect input events for the perk
	local button = UI.BottomPanel.Perk2.Button
	self:SetupButtonInputEvents(button, Remotes)
	
	-- Setup perk amount
	local oldAmount = PlayerData.Perk2.Value
	local amount = UI.BottomPanel.Perk2.Amount
	
	amount.Text = self.Utilities.Short.en(oldAmount)

	local connection = PlayerData.Perk2.Changed:Connect(function(newAmount)
		task.spawn(function()
			if newAmount ~= oldAmount then
				amount.Text = self.Utilities.Short.en(newAmount)
			end
		end)

		oldAmount = newAmount
	end)

	table.insert(self.Connections, connection)
end

function PerksHandler:SetupPerk3(UI, Remotes, PlayerData)
	-- Create button animations
	-- TODO: @emegerd добавить обработку анимаций кнопок с наведением.
	-- self.Utilities.ButtonAnimations.Create(UI.Clicker)

	-- Connect input events for the perk
	local button = UI.BottomPanel.Perk3.Button
	self:SetupButtonInputEvents(button, Remotes)

	-- Setup perk amount
	local oldAmount = PlayerData.Perk3.Value
	local amount = UI.BottomPanel.Perk3.Amount

	amount.Text = self.Utilities.Short.en(oldAmount)

	local connection = PlayerData.Perk3.Changed:Connect(function(newAmount)
		task.spawn(function()
			if newAmount ~= oldAmount then
				amount.Text = self.Utilities.Short.en(newAmount)
			end
		end)

		oldAmount = newAmount
	end)

	table.insert(self.Connections, connection)
end

function PerksHandler:SetupButtonInputEvents(button : TextButton, Remotes)
	local connection = button.MouseButton1Click:Connect(function()
		Remotes.UsePerk:FireServer(button.Parent.Name)
	end)

	table.insert(self.Connections, connection)
end

function PerksHandler:PlayEffect(activatingPlayer, duration, imageId, soundId, videoId)
	-- Show image effects for all nearby players (including the activating player)
	if imageId then
		local character = activatingPlayer.Character
		if not character then return end

		local head = character:FindFirstChild("Head")
		if not head then return end

		-- Remove any existing icon
		local existingGui = head:FindFirstChild("PerkIcon")
		if existingGui then
			existingGui:Destroy()
		end

		-- Create BillboardGui
		local gui = Instance.new("BillboardGui")
		gui.Name = "PerkIcon"
		gui.Size = UDim2.new(0, 200, 0, 200)
		gui.StudsOffset = Vector3.new(0, 3, 0)
		gui.AlwaysOnTop = true
		gui.Adornee = head
		gui.Parent = head
		
		-- ImageLabel
		local imageLabel = Instance.new("ImageLabel")
		imageLabel.Size = UDim2.new(1, 0, 1, 0)
		imageLabel.BackgroundTransparency = 1
		imageLabel.Image = "rbxassetid://" .. imageId
		imageLabel.Parent = gui

		-- Destroy after duration
		task.delay(duration, function()
			if gui and gui.Parent then
				gui:Destroy()
			end
		end)
	end

	if soundId then
		local existingSound = SoundService:FindFirstChild("PerkSound")
		if existingSound then
			existingSound:Destroy()
		end
		
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://" .. soundId
		sound.Volume = 1
		sound.Name = "PerkSound"
		sound.Parent = SoundService
		
		sound:Play()

		-- Destroy after duration
		task.delay(duration, function()
			if sound and sound.Parent then
				sound:Destroy()
			end
		end)
	end
	
	if videoId then
		self:PlayVideoEffect(activatingPlayer, duration, videoId)
	end
end

function PerksHandler:PlayVideoEffect(activatingPlayer, duration, videoId)
	local character = activatingPlayer.Character
	if not character then return end

	local head = character:FindFirstChild("Head")
	if not head then return end

	-- Remove any existing video
	local existingVideo = head:FindFirstChild("PerkVideo")
	if existingVideo then
		existingVideo:Destroy()
	end

	-- Create BillboardGui for video
	local videoGui = Instance.new("BillboardGui")
	videoGui.Name = "PerkVideo"
	videoGui.Size = UDim2.new(0, 200, 0, 150) -- Larger size for video
	videoGui.StudsOffset = Vector3.new(0, 4, 0) -- Higher offset for video
	videoGui.AlwaysOnTop = true
	videoGui.Adornee = head
	videoGui.Parent = head

	-- Create VideoFrame
	local videoFrame = Instance.new("VideoFrame")
	videoFrame.Size = UDim2.new(1, 0, 1, 0)
	videoFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	videoFrame.BorderSizePixel = 0
	videoFrame.Video = "rbxassetid://" .. videoId
	videoFrame.Looped = true
	videoFrame.Parent = videoGui

	-- Start playing the video
	videoFrame:Play()

	-- Destroy after duration
	task.delay(duration, function()
		if videoGui and videoGui.Parent then
			videoGui:Destroy()
		end
	end)
end

--// Public Methods
function PerksHandler:IsInitialized()
	return self._initialized
end

--// Cleanup
function PerksHandler:Cleanup()
	print("Cleaning up PerksHandler...")

	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}

	self._initialized = false
	print("✅ PerksHandler cleaned up")
end

return PerksHandler 
