--[[
	AreaHandler Module
	Handles area detection, UI, and door unlocking
	
	This module manages:
	- Detecting when the player is near a new area/door
	- Showing the area unlock UI and cost
	- Handling area purchase requests
	- Updating door visuals and collision
]]

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--// Module
local AreaHandler = {}

--// State
AreaHandler.Connections = {}
AreaHandler._initialized = false
AreaHandler.AreaDetectionThread = nil

--// Initialization
function AreaHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	self.Utilities = controller:GetModule("Utilities")
	
	if not self.ClientState:IsInitialized() then
		warn("ClientState not initialized, cannot initialize AreaHandler")
		return false
	end
	
	self:SetupAreaUI()
	self:SetupAreaDetection()
	self:SetupDoorUpdates()
	
	self._initialized = true
	print("✅ AreaHandler initialized successfully!")
	return true
end

function AreaHandler:SetupAreaUI()
	local Frames = self.ClientState:GetFrames()
	local Remotes = self.ClientState:GetRemotes()
	
	self.Utilities.ButtonAnimations.Create(Frames.Area.Buy)
	local buyConnection = Frames.Area.Buy.Click.MouseButton1Click:Connect(function()
		Remotes.Area:FireServer()
		self.Utilities.Audio.PlayAudio("Click")
		task.wait(0.05)
		if Frames.Area.Visible then
			self.Utilities.ButtonHandler.OnClick(Frames.Area, UDim2.new(0,0,0,0))
		end
	end)
	table.insert(self.Connections, buyConnection)
end

function AreaHandler:SetupAreaDetection()
	if self.AreaDetectionThread then
		self.AreaDetectionThread:Disconnect()
	end
	
	self.AreaDetectionThread = RunService.Heartbeat:Connect(function()
		self:AreaDetectionStep()
	end)
end

function AreaHandler:AreaDetectionStep()
	local Player = self.ClientState:GetPlayer()
	local PlayerData = self.ClientState:GetPlayerData()
	local Frames = self.ClientState:GetFrames()
	local GameSettings = self.ClientState:GetGameSettings()
	
	local Door = workspace.Map.Doors:FindFirstChild(tostring(PlayerData.BestZone.Value + 1))
	if not Door then return end
	
	local BoundBox = workspace:GetPartBoundsInBox(Door.CFrame, Door.Size + Vector3.new(2,2,2))
	for _, Part in BoundBox do
		if Part.Parent == Player.Character then
			if not Frames.Area.Visible then
				self.Utilities.ButtonHandler.OnClick(Frames.Area, UDim2.new(0.262,0,0.391,0))
				if ReplicatedStorage.Areas[Door.Name].Cost.Value ~= -1 then
					Frames.Area.Cost.Text = self.Utilities.Short.en(ReplicatedStorage.Areas[Door.Name].Cost.Value).." "..GameSettings.CurrencyName.Value
				else
					Frames.Area.Cost.Text = "Maxed"
				end
			end
			break
		end
	end
end

function AreaHandler:SetupDoorUpdates()
	local function UpdateAllDoors()
		local PlayerData = self.ClientState:GetPlayerData()
		for _, Door in workspace.Map.Doors:GetChildren() do
			local IsVisible = PlayerData.BestZone.Value < tonumber(Door.Name)
			Door.Transparency = IsVisible and 0.35 or 1
			Door.CanCollide = IsVisible
			for _, Object in Door:GetDescendants() do
				if Object:IsA("TextLabel") then
					Object.TextTransparency = IsVisible and 0 or 1
				elseif Object:IsA("UIStroke") then
					Object.Transparency = IsVisible and 0 or 1
				end
			end
		end
	end
	
	UpdateAllDoors()
	workspace.Map.Doors.ChildAdded:Connect(UpdateAllDoors)
	self.ClientState:GetPlayerData().BestZone.Changed:Connect(UpdateAllDoors)
end

--// Public Methods
function AreaHandler:IsInitialized()
	return self._initialized
end

--// Cleanup
function AreaHandler:Cleanup()
	print("Cleaning up AreaHandler...")
	for _, connection in ipairs(self.Connections) do
		if connection then connection:Disconnect() end
	end
	self.Connections = {}
	if self.AreaDetectionThread then
		self.AreaDetectionThread:Disconnect()
		self.AreaDetectionThread = nil
	end
	self._initialized = false
	print("✅ AreaHandler cleaned up")
end

return AreaHandler 