--!native

-- TODO: Fix global position not being retained properly when rotated gui is resized
-- TODO: Clean up extra guis if they haven't been reused for a while

local UserGameSettings = UserSettings():GetService("UserGameSettings")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local AssetService = game:GetService("AssetService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")

local DefaultEmitter = ReplicatedFirst.Instances.Emitter
local DefaultAttributes = DefaultEmitter:GetAttributes()

local IsPlugin = script.Parent:IsA("LocalScript") == false

local UserId = 0

if IsPlugin then
	UserId = game:GetService("StudioService"):GetUserId()
else
	UserId = Players.LocalPlayer.UserId
end

local InstalledVersion = DefaultEmitter:GetAttribute("Version")
local PluginVersion = ReplicatedStorage:GetAttribute("Emitter2D_Version")

if PluginVersion == nil then
	warn("Emitter2D: Waiting for ReplicatedStorage.Emitter2D_Version attribute...")
	ReplicatedStorage:GetAttributeChangedSignal("Emitter2D_Version"):Wait()
	PluginVersion = ReplicatedStorage:GetAttribute("Emitter2D_Version")
	warn("Emitter2D: Version found, now initializing")
end

if typeof(PluginVersion) ~= "number" then
	error("ReplicatedStorage.Emitter2D_Version must be a number")
end

if InstalledVersion < PluginVersion then
	error(`Cannot load Emitter2D: Version mismatch! Please update your plugin and install the new client version. ({InstalledVersion} vs {PluginVersion})`)
end

local ScreenSize = workspace.CurrentCamera.ViewportSize

type VERIFY_FAILED = "__VERIFY_FAILED"
local VERIFY_FAILED = "__VERIFY_FAILED" :: VERIFY_FAILED

-- Randomizers

local function NewSpawnRandomizers()
	return {
		-- Property-matching randomizers
		Color = Random.new();
		Depth = Random.new();
		DepthTransparency = Random.new();
		EmissionRate = Random.new();
		FlipbookFramerate = Random.new();
		FlipbookStartRandom = Random.new();
		LifeTime = Random.new();
		Rotation = Random.new();
		RotationSpeed = Random.new();
		Scale = Random.new();
		Size = Random.new();
		Speed = Random.new();
		SpreadAngle = Random.new();
		Squash = Random.new();
		Transparency = Random.new();

		-- Other randomizers
		Position = Random.new();
	}
end

-- Attribute enums

local Enums = {
	["SizeConstraint"] = {
		"Offset";
		"RelativeYY";
		"RelativeXX";
		"RelativeMin";
		"RelativeMax";
	};

	["Orientation"] = {
		"Normal";
		"VelocityParallel";
		"VelocityPerpendicular";
	};

	["EmissionShape"] = {
		"Rectangle";
		"Oval";
		"Point";
	};
	
	["EmissionShapeStyle"] = {
		"Volume";
		"Surface";
	};
	
	["EmissionDirectionMode"] = {
		"FromUp";
		"FromCenter";
		"FromSurface";
	};

	["ClassName"] = {
		"Emitter2D";
	};

	["FlipbookMode"] = {
		"Loop";
		"OneShot";
		"PingPong";
		"Random";
	};
	
	["FlipbookLayout"] = {
		"None";
		"Grid2x2";
		"Grid4x4";
		"Grid8x8";
	};
	
	["ResampleMode"] = Enum.ResamplerMode;
}

local AllowUnofficial = {
	["SilenceWarnings"] = true;
	["EmitCount"] = true;
	["EmitDelay"] = true;
}

local FlipbookFramesPerRow = {
	Grid2x2 = 2;
	Grid4x4 = 4;
	Grid8x8 = 8;
}

for Name, Value in Enums do
	if typeof(Value) == "Enum" then
		local EnumItems = Value:GetEnumItems()
		for i,EnumItem in EnumItems do
			EnumItems[i] = EnumItem.Name
		end
		Enums[Name] = EnumItems
	end
end

local Verifiers : {[string]: (any) -> (false?, string?)} = {
	["Version"] = function(emitterVersion)
		if emitterVersion ~= InstalledVersion then
			return VERIFY_FAILED, "The version attribute cannot be changed manually."
		end
		return emitterVersion
	end;
	["FlipbookResolution"] = function(resolution)
		if resolution < 8 or resolution > 1024 or math.log(resolution, 2) % 1 ~= 0 then
			return VERIFY_FAILED, "Valid FlipbookResolution Values: 8, 16, 32, 64, 128, 256, 512, 1024"
		end
		return resolution
	end;
	["EmissionRate"] = function(rate)
		if rate.Max > 10000 then
			return VERIFY_FAILED, "EmissionRate is capped below 10000 (and much, much lower is recommended)"
		end
		return rate
	end;
	["Texture"] = function(texture)
		local id = tonumber(texture)
		if id then
			return "rbxassetid://" .. id
		end
		return texture
	end;
}

local Migrations = {
	{
		Version = 1.2;
		Added = {
			Paused = false;
			EmissionShapeStyle = "Volume";
		};
		Removed = {
			"IgnoreClipDescendants";
			"EasingStyle";
			"EasingDirection";
		};
		Changed = {
			EmissionShape = function(Attributes:{[string]:any})
				local OldEmissionShape = Attributes.EmissionShape
				if OldEmissionShape == "Area" then
					return "Rectangle"
				elseif OldEmissionShape == "Center" then
					return "Point"
				end
				return OldEmissionShape
			end;
			IgnoreClipsDescendants = function(Attributes:{[string]:any})
				return if Attributes.IgnoreClipDescendants ~= nil then Attributes.IgnoreClipDescendants else false
			end;
		};
	};
	{
		Version = 1.21;
		Added = {
			Depth = NumberRange.new(0);
		};
	};
	{
		Version = 1.22;
		Added = {
			EmissionDirectionMode = "FromUp";
		};
	};
	{
		Version = 1.23;
		Added = {
			DepthTransparency = NumberSequence.new(0);
		};
	};
	{
		Version = 1.24;
		Added = {
			UseScreenSize = false;
		};
	};
	{
		Version = 1.25;
		Added = {
			IgnoreGraphicsLevel = false;
		};
	};
	{
		Version = 1.26;
		Added = {
			EmissionRateScaleByArea = false;
		};
	};
}

-- Functions

local function lerp(a,b,c)
	return a+(b-a)*c
end

local function reachAfterRepetition(t, reps)
	return t^(1/reps)
end

local function isGuiIntersecting(g1pos, g1size, g2pos, g2size)
	return not (
		g2pos.x > g1pos.x + g1size.x or 
		g2pos.x + g2size.x < g1pos.x or 
		g2pos.y > g1pos.y + g1size.y or 
		g2pos.y + g2size.y < g1pos.y
	)
end

local function generateSequence(SequenceObject, Seed: number)
	local Keypoints = SequenceObject.Keypoints
	if typeof(SequenceObject) == "NumberSequence" then
		local Sequence = {}
		for i = 1, #Keypoints do
			local Keypoint = Keypoints[i]
			table.insert(Sequence, {
				Time = Keypoint.Time;
				Value = Keypoint.Value + (Keypoint.Envelope * 2 * Seed);
			})
		end
		return Sequence
	elseif typeof(SequenceObject) == "ColorSequence" then
		return Keypoints
	end
end

local function evaluateSequence(Time, Sequence, Index)
	local NextValue = Sequence[Index+1]
	while Time > NextValue.Time do
		Index += 1
		NextValue = Sequence[Index+1]
	end
	return Sequence[Index], NextValue, Index
end

local function getFlipbookPosition(CurrentFrame, FramesPerRow)
	local FrameX = 1 + ((CurrentFrame-1) % FramesPerRow)
	local FrameY = math.ceil(FramesPerRow * CurrentFrame/(FramesPerRow^2))
	return FrameX, FrameY
end

local function getFlipbookFramesSinceStart(TimeElapsed, Framerate)
	return 1 + math.floor(TimeElapsed * Framerate)
end

local function getAngleFromDirection(Direction)
	local Angle = math.deg(math.atan2(Direction.X, -Direction.Y))
	if (Angle < math.huge) == false then
		Angle = 0
	end
	return Angle
end

local function getDirectionFromAngle(Angle)
	local Angle = math.rad(Angle-90)
	return Vector2.new(math.cos(Angle), math.sin(Angle))
end

local function ellipseNormalAtPoint(width, height, x, y)
	local a = width / 2
	local b = height / 2

	local nx = x / (a * a)
	local ny = y / (b * b)

	local mag = math.sqrt(nx * nx + ny * ny)
	return nx / mag, ny / mag
end

local function verifyAttribute(Name, Value) : (any, string?)
	-- Allow unofficial attributes
	if AllowUnofficial[Name] then
		return Value
	end
	
	-- If value has a verifier, run it
	local Verifier = Verifiers[Name]
	if Verifier then
		local Result, Reason = Verifier(Value)
		if Result == VERIFY_FAILED then
			return VERIFY_FAILED, Reason
		else
			Value = Result
		end
	end
	
	-- If value is an enum, check if it's a valid one
	local EnumList = Enums[Name]
	if EnumList then
		if not table.find(EnumList, Value) then
			return VERIFY_FAILED, "InvalidEnum"
		end
	end
	
	-- Check if value has correct type
	if typeof(Value) ~= typeof(DefaultAttributes[Name]) then
		return VERIFY_FAILED, "InvalidType"
	end

	-- If no problems are found, confirm success
	return Value
end

local function migrateAttributes(Attributes:{[string]:any})
	for _, Migration in Migrations do
		if typeof(Attributes.Version) ~= "number" or Attributes.Version < Migration.Version then
			-- add attributes
			local Added = Migration.Added
			if Added then
				for Name, Value in Added do
					Attributes[Name] = Value
				end
			end

			-- change attributes
			local Changed = Migration.Changed
			if Changed then
				for Name, Setter in Changed do
					local Success, Value = pcall(Setter, Attributes)
					if Success then
						Attributes[Name] = Value
					else
						error(`Failed to change attribute '{Name}' during migration to version {Migration.Version}:\n{tostring(Value)}`)
					end
				end
			end

			-- remove attributes
			local Removed = Migration.Removed
			if Removed then
				for _,Name in Removed do
					Attributes[Name] = nil
				end
			end

			-- update version
			Attributes.Version = Migration.Version
		end
	end

	-- set version to latest
	Attributes.Version = DefaultEmitter:GetAttribute("Version")
end

-- Migration version check to make sure I updated everything properly

local LastMigrationVersion = 0

local OriginalAttributes: {[string]:any} = {
	["EmissionShape"] = "Area";
	["FlipbookResolution"] = 1024;
	["IgnoreClipsDescendants"] = false;
	["FlipbookFramerate"] = NumberRange.new(20);
	["SizeConstraint"] = "RelativeYY";
	["ZIndex"] = 1;
	["FlipbookLayout"] = "None";
	["SpreadAngle"] = 45;
	["Transparency"] = NumberSequence.new(0);
	["UseJitterFix"] = true;
	["ClassName"] = "Emitter2D";
	["Orientation"] = "Normal";
	["Color"] = ColorSequence.new(Color3.new(0,0,0));
	["Drag"] = 0;
	["EmissionRate"] = NumberRange.new(10);
	["TimeScale"] = 1;
	["FlipbookMode"] = "OneShot";
	["Squash"] = NumberSequence.new(0.5);
	["Speed"] = NumberRange.new(400);
	["Version"] = 0;
	["VelocityInheritance"] = 0;
	["Size"] = NumberRange.new(300);
	["Enabled"] = true;
	["Acceleration"] = Vector2.new(0,1000);
	["Texture"] = "rbxassetid://867619398";
	["Scale"] = NumberSequence.new(1);
	["FlipbookStartRandom"] = false;
	["Rotation"] = NumberRange.new(0);
	["MasterScale"] = 1;
	["LockedToGui"] = false;
	["EmissionDirection"] = 0;
	["ResampleMode"] = "Default";
	["Paused"] = false;
	["RotationSpeed"] = NumberRange.new(0);
	["LifeTime"] = NumberRange.new(0.3, 0.7);
}

for i, Migration in Migrations do
	migrateAttributes(OriginalAttributes)
	if Migration.Version <= LastMigrationVersion then
		error(`Version lower or equal to previous, did you forget to change it? [Migration #{i}, v{Migration.Version} <= v{LastMigrationVersion}]`)
	elseif Migration.Version > InstalledVersion then
		error(`Version higher than installed version, did you forget to update the config version attribute? [Migration #{i}, v{Migration.Version} <= v{InstalledVersion}]`)
	end
	LastMigrationVersion = Migration.Version
end

for k, v in DefaultEmitter:GetAttributes() do
	if typeof(v) ~= typeof(OriginalAttributes[k]) then
		error(`Final migration check type mismatch for attribute '{k}': [{typeof(OriginalAttributes[k])} ~= {typeof(v)}]`)
	end
end

-- Module

local Emitter2D = {}
Emitter2D.__index = Emitter2D
Emitter2D.__tostring = function(self)
	return `Emitter2D [{self.Config:GetFullName()}]`
end

Emitter2D.PlayerGui = if IsPlugin == false then Players.LocalPlayer:WaitForChild("PlayerGui") else StarterGui -- playergui must be set externally when loaded in edit mode

Emitter2D.GlobalEnabled = true
Emitter2D.GlobalEvents = {}

Emitter2D.Particles = {}
Emitter2D.ParticleFolders = {}

Emitter2D.EntityList = nil

function Emitter2D.new()
	return setmetatable({}, Emitter2D)
end

function Emitter2D:Initiate(Config)
	self.Config = Config -- necessary for tostring(self)
	
	-- Cancel if config is a higher version than this module supports
	
	local EmitterVersion = Config:GetAttribute("Version")
	if typeof(EmitterVersion) == "number" and EmitterVersion > InstalledVersion then
		error(tostring(self) .. ` Cannot load emitter from a newer version. Please update the plugin and install the new client! ({Config:GetAttribute("Version")} > {InstalledVersion})`)
	end
	
	-- Set properties
	
	self.ValidAncestry = false

	self.Events = {}
	self.Bindables = {}

	self.Cache = {}
	self.CacheCount = 0

	self.Particles = {}
	self.ParticleCount = 0

	self.Time = 0
	self.NextSpawn = 0

	self.LastPosition = nil
	self.LastRotation = nil

	-- Create particle folder

	local ParticleFolder = Instance.new("Folder")
	ParticleFolder.Name = "Particles_"..Config.Name
	ParticleFolder.Archivable = false
	ParticleFolder:AddTag("Emitter2D_ParticleFolder")
	ParticleFolder:SetAttribute("Owner", UserId)
	
	local ParticleFrame = Instance.new("Frame")
	ParticleFrame.Name = "ParticleFrame"
	ParticleFrame.Interactable = false
	ParticleFrame.BackgroundTransparency = 1
	ParticleFrame.Size = UDim2.fromScale(1, 1)
	ParticleFrame.Parent = ParticleFolder
	
	self.Events.ParticleFolderDestroyed = ParticleFolder.Destroying:Connect(function()
		self:Destroy()
	end)

	self.Events.ConfigNameChanged = Config:GetPropertyChangedSignal("Name"):Connect(function()
		ParticleFolder.Name = "Particles_"..Config.Name
	end)
	
	self.ParticleFolder = ParticleFolder
	self.ParticleFrame = ParticleFrame
	
	Emitter2D.ParticleFolders[ParticleFolder] = Config
	
	ParticleFolder.Parent = Config
	
	-- Migrate emitter to current version if it's a lower version

	local Attributes = Config:GetAttributes()

	migrateAttributes(Attributes)

	for Name in Config:GetAttributes() do
		if Attributes[Name] == nil then
			Config:SetAttribute(Name, nil)
		end
	end

	for Name, Value in Attributes do
		Config:SetAttribute(Name, Value)
	end
	
	-- Track attribute changes

	local function updateAttribute(Name, Value)
		local Value = Value or Config:GetAttribute(Name)
		local Result, Reason = verifyAttribute(Name, Value)
		if Result == VERIFY_FAILED then
			local DefaultValue = DefaultAttributes[Name]
			if not Attributes.SilenceWarnings then
				if Reason == "InvalidEnum" then
					warn(tostring(self) .. ` '{tostring(Value)}' is not a valid value for attribute '{Name}'`)
					warn(`Valid values for {Name} are '{table.concat(Enums[Name], "', '")}'`)
				elseif Reason == "InvalidType" then
					warn(tostring(self) .. ` '{typeof(Value)}' is not a valid type for attribute '{Name}'`)
				else
					warn(tostring(self) .. ` Invalid value for attribute '{Name}'`.. if Reason then `: {Reason}` else ``)
				end
				warn(`Attribute has been reset to default value. ({tostring(DefaultValue)})`)
			end
			Config:SetAttribute(Name, DefaultValue)
		elseif Result ~= Value then
			if Reason then
				warn(tostring(self) .. ` {Reason}`)
			end
			Config:SetAttribute(Name, Result)
		else
			Attributes[Name] = Value
		end
	end

	self.Events.AttributeChanged = Config.AttributeChanged:Connect(updateAttribute)

	updateAttribute("Version")

	for Name, Value in Attributes do
		if Name ~= "Version" then
			updateAttribute(Name, Value)
		end
	end

	for Name, Value in DefaultEmitter:GetAttributes() do
		if Attributes[Name] == nil then
			warn(("%s Missing attribute '%s', value has been set to default (%s)"):format(tostring(self), Name, tostring(Value)))
			Config:SetAttribute(Name, Value)
		end
	end

	self.Attributes = Attributes
	
	-- Create randomizers
	
	self.SpawnRandomizers = NewSpawnRandomizers()

	-- Reset emitter time when specific things change to avoid issues

	local ResetTime = function()
		self.Time = 0
		self.NextSpawn = Attributes.EmissionRate.Min > 0 and 0 or math.huge
	end

	ResetTime()

	self.Events.RateChanged = Config:GetAttributeChangedSignal("EmissionRate"):Connect(ResetTime)
	self.Events.EnabledChanged = Config:GetAttributeChangedSignal("Enabled"):Connect(ResetTime)
	self.Events.TimeScaleChanged = Config:GetAttributeChangedSignal("TimeScale"):Connect(ResetTime)

	-- Automatically stop simulating if the gui stops being rendered
	-- (really wish roblox would just add a property to check if a gui object is being rendered)

	local function UpdateRenderable()
		-- Get ParentGui and ParentScreen
		
		local ParentGui = Config:FindFirstAncestorWhichIsA("GuiObject")
		local ParentScreen = Config:FindFirstAncestorWhichIsA("LayerCollector")
		
		-- Initial active checks
		
		local ValidAncestry =
			if ParentGui == nil
			or ParentScreen == nil
			or (Config:IsDescendantOf(Emitter2D.PlayerGui) == false and Config:IsDescendantOf(workspace) == false)
			then false
			else true
		
		-- Set active to false if there is a non-renderable in the ancestor chain before playergui or workspace
		-- (really wish roblox would just add a property to check if a gui object is being rendered)
		
		if ValidAncestry then
			local Object = Config.Parent
			while Object ~= nil do
				if Object:IsA("GuiBase2d") or Object:IsA("Folder") then
					Object = Object.Parent
					continue
				elseif Object == Emitter2D.PlayerGui or Object == workspace then
					break
				else
					ValidAncestry = false
					break
				end
			end
		end

		-- Begin detection for conditions that cause the gui to stop being rendered
		-- REALLY wish roblox would just add a property to check if a gui object is being rendered
		-- vv Leave a like or comment on this post to encourage roblox to add it! vv
		-- https://devforum.roblox.com/t/add-a-read-only-property-that-shows-whether-a-gui-is-being-rendered/
		
		if ValidAncestry then
			ResetTime()
			
			self.ZIndexBehavior = ParentScreen.ZIndexBehavior

			self.AbsoluteRotation = ParentGui.AbsoluteRotation
			self.AbsolutePosition = ParentGui.AbsolutePosition
			self.AbsoluteSize = ParentGui.AbsoluteSize

			self.LastPosition = nil
			self.LastRotation = nil

			if self.AncestorEvents then
				for Object, Events in self.AncestorEvents do
					for Name, Event in Events do
						Event:Disconnect()
					end
				end
			end

			self.AncestorEvents = {}

			self.NotVisibleCount = 0
			self.ClipCount = 0

			local Ancestor = ParentGui

			while Ancestor do
				if Ancestor:IsA("GuiObject") or Ancestor:IsA("LayerCollector") then
					local Events = {}

					local Gui = Ancestor
					local IsVisible = true
					
					local function UpdateVisible(Visible:boolean)
						if Visible then
							if IsVisible == false then
								IsVisible = true
								self.NotVisibleCount -= 1
							end
						else
							if IsVisible == true then
								IsVisible = false
								self.NotVisibleCount += 1
							end
						end
					end
					
					if Gui:IsA("GuiObject") then
						Events.VisibleChanged = Gui:GetPropertyChangedSignal("Visible"):Connect(function()
							UpdateVisible(Gui.Visible)
						end)
						UpdateVisible(Gui.Visible)
					elseif Gui:IsA("LayerCollector") then
						Events.VisibleChanged = Gui:GetPropertyChangedSignal("Enabled"):Connect(function()
							UpdateVisible(Gui.Enabled)
						end)
						Events.ZIndexBehaviorChanged = Gui:GetPropertyChangedSignal("ZIndexBehavior"):Connect(function()
							self.ZIndexBehavior = Gui.ZIndexBehavior
						end)
						UpdateVisible(Gui.Enabled)
					end

					if Gui ~= ParentGui and Attributes.IgnoreClipsDescendants == false and Gui:IsA("GuiObject") then
						local IsClipped = false
						
						local function CheckClipped()
							local Clipped = not isGuiIntersecting(
								ParentGui.AbsolutePosition, 
								ParentGui.AbsoluteSize, 
								Gui.AbsolutePosition, 
								Gui.AbsoluteSize
							)
							
							if IsClipped ~= Clipped then
								if IsClipped then
									IsClipped = false
									self.ClipCount -= 1
								else
									IsClipped = true
									self.ClipCount += 1
								end
							end
						end
						
						local function UpdateClipsDescendants()
							if Gui:IsA("GuiObject") == false or Gui.ClipsDescendants then
								Events.SizeChanged = Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(CheckClipped)
								Events.ParentPositionChanged = ParentGui:GetPropertyChangedSignal("Position"):Connect(CheckClipped)
								CheckClipped()
							else
								if Events.SizeChanged then
									Events.SizeChanged:Disconnect()
								end
								if Events.ParentPositionChanged then
									Events.ParentPositionChanged:Disconnect()
								end
								if IsClipped then
									IsClipped = false
									self.ClipCount -= 1
								end
							end
						end
						
						Events.ClipsDescendantsChanged = Gui:GetPropertyChangedSignal("ClipsDescendants"):Connect(UpdateClipsDescendants)
						UpdateClipsDescendants()
					end
					
					self.AncestorEvents[Ancestor] = Events
				end
				Ancestor = Ancestor.Parent
			end
		else
			if self.AncestorEvents then
				for Object, Events in self.AncestorEvents do
					for Name, Event in Events do
						Event:Disconnect()
					end
				end
				self.AncestorEvents = nil
			end

			self:ClearAllParticles()

			if Config:IsDescendantOf(Emitter2D.PlayerGui) or Config:IsDescendantOf(workspace) then
				warn(tostring(self).." Emitter must be parented to a gui object!")
			end
		end

		self.ValidAncestry = ValidAncestry
	end

	self.Events.AncestryChanged = Config.AncestryChanged:Connect(UpdateRenderable)
	self.Events.IgnoreClipsDescendantsChanged = Config:GetAttributeChangedSignal("IgnoreClipsDescendants"):Connect(UpdateRenderable)
	UpdateRenderable()

	-- Create Emit bindable

	local Emit = Config:FindFirstChild("Emit") or Instance.new("BindableEvent")

	self.Events.EmitFired = Emit.Event:Connect(function(Amount)
		if self.ValidAncestry then
			for i = 1,Amount or 1 do
				self:SpawnParticle()
			end
		else
			warn(tostring(self).."Cannot emit particles while emitter is inactive. Make sure the emitter is parented to a gui in the players PlayerGui.")
		end
	end)

	Emit.Name = "Emit"
	Emit.Archivable = false
	Emit.Parent = Config
	
	table.insert(self.Bindables, Emit)

	-- Create TimeStep bindable

	local TimeStep = Config:FindFirstChild("TimeStep") or Instance.new("BindableEvent")

	self.Events.TimeStepFired = TimeStep.Event:Connect(function(Delta)
		if self.ValidAncestry then
			self:Update(Delta)
		else
			warn(tostring(self).."Cannot update time while emitter is inactive. Make sure the emitter is parented to a gui in the players PlayerGui.")
		end
	end)

	TimeStep.Name = "TimeStep"
	TimeStep.Archivable = false
	TimeStep.Parent = Config
	
	table.insert(self.Bindables, TimeStep)
	
	-- Create SetSeeds bindable
	
	local SetSeeds = Config:FindFirstChild("SetSeeds") or Instance.new("BindableEvent")

	self.Events.SetSeedsFired = SetSeeds.Event:Connect(function(Seeds: { [string]: number })
		assert(typeof(Seeds) == "table", `First argument must be a table of seeds with the keys being the seed names and the values being the seed number.`)
		local FailedAny = false
		for Attribute, Seed in Seeds do
			if self.SpawnRandomizers[Attribute] then
				self.SpawnRandomizers[Attribute] = Random.new(Seed)
			else
				FailedAny = true
				warn(`Failed to set seed: '{tostring(Attribute)}' is not a valid seed key!`)
			end
		end
		if FailedAny then
			local validKeys = ""
			for Attribute, Randomizer in self.SpawnRandomizers do
				validKeys ..= `{Attribute}, `
			end
			warn(`Valid seed keys: {validKeys:sub(1, -3)}`)
		end
	end)

	SetSeeds.Name = "SetSeeds"
	SetSeeds.Archivable = false
	SetSeeds.Parent = Config

	table.insert(self.Bindables, SetSeeds)

	-- Create Clear bindable

	local Clear = Config:FindFirstChild("Clear") or Instance.new("BindableEvent")

	self.Events.ClearFired = Clear.Event:Connect(function()
		self:ClearAllParticles()
	end)

	Clear.Name = "Clear"
	Clear.Archivable = false
	Clear.Parent = Config
	
	table.insert(self.Bindables, Clear)
	
	-- Add to particle list
	
	Emitter2D.Particles[Config] = self
end

function Emitter2D:SpawnParticle(Position, Velocity) 
	local Attributes = self.Attributes
	local Randomizers = self.SpawnRandomizers :: typeof(NewSpawnRandomizers())
	local EmissionDirection = Attributes.EmissionDirection

	-- Create particle gui

	local ParentGui = self.Config.Parent
	local ParticleGui = self.Cache[self.CacheCount]

	if ParticleGui then
		self.Cache[self.CacheCount] = nil
		self.CacheCount -= 1
	else
		ParticleGui = Instance.new("ImageLabel")
	end

	ParticleGui.Name = "Particle"
	ParticleGui.Image = Attributes.Texture
	ParticleGui.Archivable = false
	ParticleGui.Interactable = false
	ParticleGui.BackgroundTransparency = 1
	ParticleGui.AnchorPoint = Vector2.new(0.5, 0.5)
	ParticleGui.ResampleMode = Enum.ResamplerMode[Attributes.ResampleMode]

	-- Create particle data

	local ParticleData = {
		ParticleGui = ParticleGui;
		ParentGui = ParentGui;

		Events = {};

		Time = 0;

		Position = Position;
		Velocity = Velocity;

		Size = Attributes.Size.Min + (Attributes.Size.Max - Attributes.Size.Min) * Randomizers.Size:NextNumber();
		Depth = Attributes.Depth.Min + (Attributes.Depth.Max - Attributes.Depth.Min) * Randomizers.Depth:NextNumber();
		LifeTime = Attributes.LifeTime.Min + (Attributes.LifeTime.Max - Attributes.LifeTime.Min) * Randomizers.LifeTime:NextNumber();
		Rotation = Attributes.Rotation.Min + (Attributes.Rotation.Max - Attributes.Rotation.Min) * Randomizers.Rotation:NextNumber();
		RotationSpeed = Attributes.RotationSpeed.Min + (Attributes.RotationSpeed.Max - Attributes.RotationSpeed.Min) * Randomizers.RotationSpeed:NextNumber();
	}

	-- Set particle initial position

	if Position == nil then
		local ParentRotation = self.AbsoluteRotation
		local ParentPosition = self.AbsolutePosition
		local ParentSize = self.AbsoluteSize
		
		local PositionRandomizer = Randomizers.Position

		if Attributes.EmissionShape == "Rectangle" then
			if Attributes.EmissionShapeStyle == "Volume" then
				Position = Vector2.new(ParentSize.X * PositionRandomizer:NextNumber(), ParentSize.Y * PositionRandomizer:NextNumber())
			elseif Attributes.EmissionShapeStyle == "Surface" then
				local SpawnVertical = PositionRandomizer:NextNumber() <= ParentSize.Y / (ParentSize.X + ParentSize.Y)
				local SpawnSide = PositionRandomizer:NextInteger(0, 1)
				Position = Vector2.new(
					if SpawnVertical then ParentSize.X * SpawnSide else ParentSize.X * PositionRandomizer:NextNumber(),
					if SpawnVertical then ParentSize.Y * PositionRandomizer:NextNumber() else ParentSize.Y * SpawnSide
				)
				if Attributes.EmissionDirectionMode == "FromSurface" then
					if SpawnVertical then
						if SpawnSide == 0 then
							EmissionDirection -= 90
						else
							EmissionDirection += 90
						end
					else
						if SpawnSide == 0 then
							EmissionDirection += 0
						else
							EmissionDirection += 180
						end
					end
				end
			else
				error(tostring(self) .. `Invalid EmissionShapeStyle`)
			end
		elseif Attributes.EmissionShape == "Point" then
			Position = ParentSize * 0.5
			if Attributes.EmissionDirectionMode == "FromSurface" then
				EmissionDirection += Randomizers.Rotation:NextNumber(0, 360) -- TODO consider adding separate seed for this
			end
		elseif Attributes.EmissionShape == "Oval" then
			local Angle = math.rad(360 * PositionRandomizer:NextNumber())
			local Distance = if Attributes.EmissionShapeStyle == "Volume" then 0.5 * PositionRandomizer:NextNumber() ^ 0.5 else 0.5
			Position = ParentSize * Vector2.new(0.5 + math.cos(Angle) * Distance, 0.5 + math.sin(Angle) * Distance)
			if Attributes.EmissionDirectionMode == "FromSurface" then
				local SurfaceNormal = Vector2.new(ellipseNormalAtPoint(ParentSize.X, ParentSize.Y, Position.X-ParentSize.X/2, Position.Y-ParentSize.Y/2))
				EmissionDirection += getAngleFromDirection(SurfaceNormal)
			end
		else
			error(tostring(self).."Invalid EmissionShape")
		end

		ParticleData.Position = Position
	end
	
	-- Account for EmissionDirectionMode.FromCenter
	
	if Attributes.EmissionDirectionMode == "FromCenter" then
		EmissionDirection += getAngleFromDirection((ParticleData.Position - ParentGui.AbsoluteSize/2).Unit)
	end

	-- Set particle initial velocity

	if Velocity == nil then
		local Spread = Attributes.SpreadAngle * (Randomizers.SpreadAngle:NextNumber()-0.5) * 2
		local Angle = math.rad(EmissionDirection - 90 + Spread)
		local Speed = Attributes.Speed.Min + (Attributes.Speed.Max - Attributes.Speed.Min) * Randomizers.Speed:NextNumber();
		
		Velocity = Vector2.new(
			math.cos(Angle) * Speed, 
			math.sin(Angle) * Speed
		)
		
		ParticleData.Velocity = Velocity
	end
	
	-- Set initial flipbook frame if relevant
	
	local FlipbookFramerate = Attributes.FlipbookFramerate :: NumberRange
	ParticleData.FlipbookFramerate = FlipbookFramerate.Min + Randomizers.FlipbookFramerate:NextNumber() * (FlipbookFramerate.Max-FlipbookFramerate.Min)
	
	if Attributes.FlipbookStartRandom then
		ParticleData.FlipbookStartFrame = Randomizers.FlipbookStartRandom:NextNumber(1, FlipbookFramesPerRow[Attributes.FlipbookLayout])
	else
		ParticleData.FlipbookStartFrame = 1
	end
	
	ParticleData.FlipbookFrame = ParticleData.FlipbookStartFrame

	-- Generate scale sequence

	ParticleData.ScaleSequence = generateSequence(Attributes.Scale, Randomizers.Scale:NextNumber())
	ParticleData.ScaleSequenceIndex = 1

	-- Generate squash sequence

	ParticleData.SquashSequence = generateSequence(Attributes.Squash, Randomizers.Squash:NextNumber())
	ParticleData.SquashSequenceIndex = 1

	-- Generate transparency sequence

	ParticleData.TransparencySequence = generateSequence(Attributes.Transparency, Randomizers.Transparency:NextNumber())
	ParticleData.TransparencySequenceIndex = 1

	-- Generate color sequence

	ParticleData.ColorSequence = generateSequence(Attributes.Color, Randomizers.Color:NextNumber())
	ParticleData.ColorSequenceIndex = 1
	
	-- Generate depth transparency sequence
	
	if Attributes.Depth.Min ~= Attributes.Depth.Max then
		ParticleData.DepthTransparencySequence = generateSequence(Attributes.DepthTransparency, Randomizers.DepthTransparency:NextNumber())
		ParticleData.DepthTransparencySequenceIndex = 1
	end

	-- Finish

	self.Particles[ParticleGui] = ParticleData
	self.ParticleCount += 1
	
	if IsPlugin then
		ParticleGui:AddTag("Emitter2D_Particle")
	end

	return ParticleData
end

function Emitter2D:UpdateParticle(ParticleData, Delta)
	-- Variables

	local Attributes = self.Attributes

	local ParticleGui = ParticleData.ParticleGui
	local ParentGui = ParticleData.ParentGui

	local SizeMultiplier = Attributes.MasterScale
	local VelocityMultiplier = Attributes.MasterScale
	
	-- Calculate effect of depth on velocity multiplier
	
	local Depth = ParticleData.Depth
	if Depth ~= 0 then
		local DepthMultiplier = if Depth > 0 then 1 / (Depth + 1) else -Depth + 1
		SizeMultiplier *= DepthMultiplier
		VelocityMultiplier *= DepthMultiplier
	end

	-- Calculate animation progress

	ParticleData.Time += Delta

	local Progress = ParticleData.Time / ParticleData.LifeTime

	if Progress > 1 then
		return self:RemoveParticle(ParticleData)
	end

	-- Update velocity

	if self.AbsoluteRotation == 0 then
		ParticleData.Velocity += Attributes.Acceleration * Delta
	else
		ParticleData.Velocity += self.WorldRight * (Attributes.Acceleration.X * Delta)
		ParticleData.Velocity += self.WorldDown * (Attributes.Acceleration.Y * Delta)
	end
	
	ParticleData.Velocity *= if Attributes.Drag == 0 then 1
		elseif Attributes.Drag > 0 then reachAfterRepetition(0.5, 1 / Delta / Attributes.Drag) 
		else reachAfterRepetition(1.5, 1 / Delta / -Attributes.Drag)
	
	-- Update position
	
	ParticleData.Position += ParticleData.Velocity * VelocityMultiplier * Delta
	ParticleGui.Position = UDim2.fromOffset(math.round(ParticleData.Position.X), math.round(ParticleData.Position.Y))

	-- Update rotation

	ParticleData.Rotation += ParticleData.RotationSpeed * Delta

	if Attributes.Orientation == "Normal" then
		ParticleGui.Rotation = ParticleData.Rotation
	elseif Attributes.Orientation == "VelocityParallel" then
		ParticleGui.Rotation = ParticleData.Rotation + getAngleFromDirection(ParticleData.Velocity.Unit) + 90
	elseif Attributes.Orientation == "VelocityPerpendicular" then
		ParticleGui.Rotation = ParticleData.Rotation + getAngleFromDirection(ParticleData.Velocity.Unit)
	else
		error(tostring(self).."Invalid Orientation")
	end
	
	-- Update squash
	
	local LastSquash, NextSquash, SquashSequenceIndex = 
		evaluateSequence(Progress, ParticleData.SquashSequence, ParticleData.SquashSequenceIndex)
	
	ParticleData.SquashSequenceIndex = SquashSequenceIndex

	local SquashProgress = (Progress - LastSquash.Time) / (NextSquash.Time - LastSquash.Time)
	local SquashValue = LastSquash.Value + (NextSquash.Value - LastSquash.Value) * SquashProgress

	SquashValue = 6 * (SquashValue-0.5) -- Convert to regular emitter range

	-- Update size
	
	local LastScale, NextScale, ScaleSequenceIndex = 
		evaluateSequence(Progress, ParticleData.ScaleSequence, ParticleData.ScaleSequenceIndex)
	
	ParticleData.ScaleSequenceIndex = ScaleSequenceIndex

	local ScaleProgress = (Progress - LastScale.Time) / (NextScale.Time - LastScale.Time)
	local ScaleValue = LastScale.Value + (NextScale.Value - LastScale.Value) * ScaleProgress
	local PixelSize = ScaleValue * ParticleData.Size * SizeMultiplier

	-- "Offset" is default, no conditional required
	if Attributes.SizeConstraint == "RelativeXX" then
		local SizeX = if Attributes.UseScreenSize then workspace.CurrentCamera.ViewportSize.X else self.AbsoluteSize.X
		VelocityMultiplier *= SizeX / 150
		PixelSize *= SizeX / 150
	elseif Attributes.SizeConstraint == "RelativeYY" then
		local SizeY = if Attributes.UseScreenSize then workspace.CurrentCamera.ViewportSize.Y else self.AbsoluteSize.Y
		VelocityMultiplier *= SizeY / 150
		PixelSize *= SizeY / 150
	elseif Attributes.SizeConstraint == "RelativeMin" then
		local SizeX = if Attributes.UseScreenSize then workspace.CurrentCamera.ViewportSize.X else self.AbsoluteSize.X
		local SizeY = if Attributes.UseScreenSize then workspace.CurrentCamera.ViewportSize.Y else self.AbsoluteSize.Y
		local Size = math.min(SizeX, SizeY)
		VelocityMultiplier *= Size / 150
		PixelSize *= Size / 150
	elseif Attributes.SizeConstraint == "RelativeMax" then
		local SizeX = if Attributes.UseScreenSize then workspace.CurrentCamera.ViewportSize.X else self.AbsoluteSize.X
		local SizeY = if Attributes.UseScreenSize then workspace.CurrentCamera.ViewportSize.Y else self.AbsoluteSize.Y
		local Size = math.max(SizeX, SizeY)
		VelocityMultiplier *= Size / 150
		PixelSize *= Size / 150
	end

	local SquashLength = 1 + math.abs(SquashValue)
	local SquashWidth = 1 / SquashLength
	
	if SquashValue >= 0 then
		PixelSize = Vector2.new(PixelSize * SquashWidth, PixelSize * SquashLength)
	else
		PixelSize = Vector2.new(PixelSize * SquashLength, PixelSize * SquashWidth)
	end

	if Attributes.UseJitterFix then
		ParticleGui.Size = UDim2.fromOffset(-1+math.round(PixelSize.X/2)*2, -1+math.round(PixelSize.Y/2)*2)
	else
		ParticleGui.Size = UDim2.fromOffset(math.round(PixelSize.X), math.round(PixelSize.Y))
	end
	
	-- Calculate depth transparency
	
	local DepthTransparency = 0

	if ParticleData.DepthTransparencySequence then
		local LastDepthTransparency, NextDepthTransparency, DepthTransparencySequenceIndex = 
			evaluateSequence(Progress, ParticleData.DepthTransparencySequence, ParticleData.DepthTransparencySequenceIndex)

		ParticleData.DepthTransparencySequenceIndex = DepthTransparencySequenceIndex

		local DepthTransparencyProgress = (Progress - LastDepthTransparency.Time) / (NextDepthTransparency.Time - LastDepthTransparency.Time)
		local DepthTransparencyValue = LastDepthTransparency.Value + (NextDepthTransparency.Value - LastDepthTransparency.Value) * DepthTransparencyProgress

		local DepthAttribute = Attributes.Depth
		local DepthRatio = (ParticleData.Depth - DepthAttribute.Min) / (DepthAttribute.Max - DepthAttribute.Min)
		
		DepthTransparency = DepthTransparencyValue * DepthRatio
	end

	-- Update transparency

	local LastTransparency, NextTransparency, TransparencySequenceIndex = 
		evaluateSequence(Progress, ParticleData.TransparencySequence, ParticleData.TransparencySequenceIndex)
	
	ParticleData.TransparencySequenceIndex = TransparencySequenceIndex

	local TransparencyProgress = (Progress - LastTransparency.Time) / (NextTransparency.Time - LastTransparency.Time)
	local TransparencyValue = LastTransparency.Value + (NextTransparency.Value - LastTransparency.Value) * TransparencyProgress

	ParticleGui.ImageTransparency = TransparencyValue + (1-TransparencyValue) * DepthTransparency

	-- Update color

	local LastColor, NextColor, ColorSequenceIndex = 
		evaluateSequence(Progress, ParticleData.ColorSequence, ParticleData.ColorSequenceIndex)
	
	ParticleData.ColorSequenceIndex = ColorSequenceIndex

	local ColorProgress = (Progress - LastColor.Time) / (NextColor.Time - LastColor.Time)
	local ColorValue = LastColor.Value:Lerp(NextColor.Value, ColorProgress)

	ParticleGui.ImageColor3 = ColorValue
	
	-- Update flipbook
	
	local FlipbookLayout = Attributes.FlipbookLayout 
	if FlipbookLayout == "None" then
		ParticleGui.ImageRectSize = Vector2.zero
		ParticleGui.ImageRectOffset = Vector2.zero
	else
		local FlipbookMode = Attributes.FlipbookMode
		local FlipbookResolution = Attributes.FlipbookResolution
		
		local FramesPerRow = FlipbookFramesPerRow[FlipbookLayout]
		local FrameCount = FramesPerRow ^ 2
		local FrameWidth = FlipbookResolution / FramesPerRow
		
		local CurrentFrame = ParticleData.FlipbookFrame
		local StartFrame = ParticleData.FlipbookStartFrame
		
		if FlipbookMode == "OneShot" then
			CurrentFrame = StartFrame + math.ceil(Progress * (1 + FrameCount - StartFrame)) - 1
		elseif FlipbookMode == "Loop" then
			local FramesSinceStart = StartFrame + getFlipbookFramesSinceStart(ParticleData.Time, ParticleData.FlipbookFramerate)
			CurrentFrame = 1 + ((FramesSinceStart - 1) % FrameCount)
		elseif FlipbookMode == "Random" then
			local FramesSinceStart = getFlipbookFramesSinceStart(ParticleData.Time, ParticleData.FlipbookFramerate)
			local FramesSinceStartBefore = getFlipbookFramesSinceStart(ParticleData.Time-Delta, ParticleData.FlipbookFramerate)
			if FramesSinceStartBefore ~= FramesSinceStart then
				CurrentFrame = math.random(1, FrameCount)
			end
		elseif FlipbookMode == "PingPong" then -- TODO: fix image staying same for two ticks between loops
			local FramesSinceStart = StartFrame + getFlipbookFramesSinceStart(ParticleData.Time, ParticleData.FlipbookFramerate)
			CurrentFrame = 1 + ((FramesSinceStart - 1) % FrameCount)
			if math.floor((FramesSinceStart-1)/FrameCount) % 2 == 1 then
				CurrentFrame = 1 + (FrameCount-CurrentFrame)
			end
		end
		
		local FrameX, FrameY = getFlipbookPosition(CurrentFrame, FramesPerRow)
		
		ParticleGui.ImageRectSize = Vector2.new(FrameWidth, FrameWidth)
		ParticleGui.ImageRectOffset = Vector2.new((FrameX-1) * FrameWidth, (FrameY-1) * FrameWidth)
		ParticleData.FlipbookFrame = CurrentFrame
	end

	-- Finish and parent

	ParticleGui.Visible = true
	ParticleGui.ZIndex = Attributes.ZIndex
	ParticleGui.Parent = self.ParticleFrame
end

function Emitter2D:Update(Delta)
	local Attributes = self.Attributes
	local ParentGui = self.Config:FindFirstAncestorWhichIsA("GuiObject")

	-- Progress emitter time

	self.Time += Delta 

	-- Check if parent gui moved

	local Rotation = ParentGui.AbsoluteRotation
	local Position = ParentGui.AbsolutePosition
	local Size = ParentGui.AbsoluteSize

	self.AbsoluteRotation = Rotation
	self.AbsolutePosition = Position
	self.AbsoluteSize = Size

	local Moved = if self.LastPosition and Position ~= self.LastPosition then Position - self.LastPosition else nil
	local Rotated = if self.LastRotation and Rotation ~= self.LastRotation then Rotation - self.LastRotation else nil
	local Resized = if self.LastSize and Size ~= self.LastSize then Vector2.new(Size.X/self.LastSize.X, Size.Y/self.LastSize.Y) else nil

	-- Update WorldDown and WorldRight

	if Rotated or self.WorldDown == nil or self.WorldRight == nil then
		self.WorldDown = getDirectionFromAngle(-Rotation+180)
		self.WorldRight = getDirectionFromAngle(-Rotation+90)
	end

	-- LockedToGui behavior

	if Attributes.LockedToGui then
		if Resized then
			for i,ParticleData in self.Particles do
				ParticleData.Position *= Resized
			end
		end
	else
		if Rotated then
			local Center = Size/2

			for i,ParticleData in self.Particles do
				-- Retain proper position

				local CenterOffset = ParticleData.Position - Center
				local CenterDistance = CenterOffset.Magnitude

				local NewRotation = getAngleFromDirection(CenterOffset) - Rotated

				ParticleData.Position = Center + getDirectionFromAngle(NewRotation) * CenterDistance

				if Attributes.Orientation == "Normal" then
					ParticleData.Rotation -= Rotated
				end

				-- Retain proper velocity

				local Velocity = ParticleData.Velocity
				local VelocitySpeed = Velocity.Magnitude
				local VelocityAngle = getAngleFromDirection(Velocity)

				ParticleData.Velocity = getDirectionFromAngle(VelocityAngle - Rotated) * VelocitySpeed
			end
		end
		if Moved then
			if Rotation ~= 0 then
				for i,ParticleData in self.Particles do
					ParticleData.Position -= self.WorldRight * Moved.X
					ParticleData.Position -= self.WorldDown * Moved.Y
				end
			else
				for i,ParticleData in self.Particles do
					ParticleData.Position -= Moved
				end
			end
		end
	end

	self.LastPosition = Position
	self.LastRotation = Rotation
	self.LastSize = Size

	-- Set ZIndex

	self.ParticleFrame.ZIndex = Attributes.ZIndex

	-- Update existing particles

	for i,ParticleData in self.Particles do
		self:UpdateParticle(ParticleData, Delta)
	end

	-- Spawn new particles

	if Attributes.Enabled then
		local EmissionRateMin = Attributes.EmissionRate.Min
		local EmissionRateMax = Attributes.EmissionRate.Max
		
		if Attributes.IgnoreGraphicsLevel == false then
			local Modifier = 0.85 ^ (10 - math.min(UserGameSettings.SavedQualityLevel.Value, 10))
			EmissionRateMin *= Modifier
			EmissionRateMax *= Modifier
		end
		
		if Attributes.EmissionRateScaleByArea and Attributes.EmissionShape ~= "Point" then
			if Attributes.EmissionShapeStyle == "Volume" then
				local ScreenSize = workspace.CurrentCamera.ViewportSize
				local ScreenVolume = ScreenSize.X * ScreenSize.Y
				local EmitterVolume = math.min(self.AbsoluteSize.X * self.AbsoluteSize.Y, ScreenVolume) -- prevents explosive rate when screen is tiny on studio startup
				if Attributes.EmissionShape == "Oval" then
					EmitterVolume *= math.pi / 4
				end
				local Modifier = 50 * (EmitterVolume / ScreenVolume) -- ratio multiplied by 50 to make it reasonably close to static rate
				EmissionRateMin *= Modifier
				EmissionRateMax *= Modifier
			elseif Attributes.EmissionShapeStyle == "Surface" then
				local ScreenSize = workspace.CurrentCamera.ViewportSize
				local ScreenWidth: number
				if Attributes.SizeConstraint == "RelativeXX" then
					ScreenWidth = ScreenSize.X
				elseif Attributes.SizeConstraint == "RelativeYY" then
					ScreenWidth = ScreenSize.Y
				elseif Attributes.SizeConstraint == "RelativeMin" then
					ScreenWidth = math.min(ScreenSize.Y)
				elseif Attributes.SizeConstraint == "RelativeMax" then
					ScreenWidth = math.max(ScreenSize.Y)
				end
				local EmitterWidth = (self.AbsoluteSize.X + self.AbsoluteSize.Y) / 2
				local Modifier = 10 * EmitterWidth  / ScreenWidth
				EmissionRateMin *= Modifier
				EmissionRateMax *= Modifier
			end
		end
		
		self.NextSpawn = math.max(self.NextSpawn, self.Time - 0.2) -- prevents spam after large stutters / lag spikes / game freezes
		
		while self.Time > self.NextSpawn do
			local ParticleData = self:SpawnParticle()
			if Moved then
				-- TODO: use WorldDown/WorldRight for velocity inheritance
				ParticleData.Velocity += (Moved * Attributes.VelocityInheritance) / Attributes.MasterScale
			end
			self:UpdateParticle(ParticleData, self.Time - self.NextSpawn)
			self.NextSpawn += 1 / lerp(EmissionRateMin, EmissionRateMax, math.random())
		end
	else
		self.NextSpawn = self.Time
	end

	-- Sort particles by depth
	-- TODO: consider optimizing this by re-using depth list and inserting at correct index on spawn time

	if self.ZIndexBehavior ~= Enum.ZIndexBehavior.Global then
		local Depth = Attributes.Depth :: NumberRange
		if Depth.Min ~= Depth.Max then
			local List = table.create(self.ParticleCount)

			local Index = 0
			for ParticleGui, ParticleData in self.Particles do
				Index += 1
				List[Index] = ParticleData
			end

			table.sort(List, function(DataA, DataB)
				return DataA.Depth > DataB.Depth
			end)

			for i, ParticleData in List do
				ParticleData.ParticleGui.ZIndex = Attributes.ZIndex + i
			end
		end
	end
end

function Emitter2D:RemoveParticle(ParticleData, NoCache)
	local ParticleGui = ParticleData.ParticleGui
	if ParticleGui then
		self.Particles[ParticleGui] = nil
		self.ParticleCount -= 1
		
		if NoCache then
			ParticleGui:Destroy()
		else
			ParticleGui.Visible = false
			self.CacheCount += 1
			self.Cache[self.CacheCount] = ParticleGui
		end
	end

	local Events = ParticleData.Events
	if Events then
		for Name, Event in Events do
			Event:Disconnect()
		end
	end
end

function Emitter2D:ClearAllParticles(NoCache)
	for ParticleGui, ParticleData in self.Particles do
		self:RemoveParticle(ParticleData, NoCache)
	end
end

function Emitter2D:Destroy()
	if self.Config then
		Emitter2D.Particles[self.Config] = nil
	end
	
	if self.Events then
		for Name, Event in self.Events do
			Event:Disconnect()
		end
	end

	if self.AncestorEvents then
		for Object, Events in self.AncestorEvents do
			for Name, Event in Events do
				Event:Disconnect()
			end
		end
	end

	if self.ParticleFolder then
		Emitter2D.ParticleFolders[self.ParticleFolder] = nil
		if self.ParticleFolder.Parent ~= nil then
			task.defer(function()
				self.ParticleFolder:Destroy()
			end)
		end
	end
	
	if self.Bindables then
		for _,bindable in self.Bindables do
			bindable:Destroy()
		end
	end
end

-- Updater

local EnvironmentId = "Emitter2D_"..HttpService:GenerateGUID(false)
local LastPrint = tick()

RunService:BindToRenderStep(EnvironmentId, Enum.RenderPriority.First.Value, function(Delta)
	--if tick() - lastPrint >= 1 then
	--	lastPrint = tick()
	--	print(environmentId, "is active")
	--end
	for Config, Entity in Emitter2D.Particles do
		if Emitter2D.GlobalEnabled 
		and Entity.ValidAncestry 
		and Entity.NotVisibleCount == 0 
		and (Entity.Attributes.IgnoreClipsDescendants or Entity.ClipCount == 0) 
		then
			Entity.ParticleFolder.Parent = Config.Parent
			if Config:GetAttribute("Paused") == false then
				task.spawn(Entity.Update, Entity, Delta * Entity.Attributes.TimeScale)
			end
		else
			Entity.ParticleFolder.Parent = nil
			if Entity.ParticleCount > 0 then
				Entity:ClearAllParticles()
			end
		end
	end
end)

-- Hide particles from other clients in plugin mode
-- TODO hide the parent frame instead of individual particles

if IsPlugin then
	local ForeignParticleEvents = {} :: {[ImageLabel]:{[any]:any}}

	Emitter2D.GlobalEvents.HideForeignParticles = CollectionService:GetInstanceAddedSignal("Emitter2D_Particle"):Connect(function(particleGui:ImageLabel)
		local particleFrame = particleGui.Parent
		local particleFolder = particleFrame and particleFrame.Parent
		if particleFolder and particleFolder:GetAttribute("Owner") ~= UserId then
			local events = {}
			events.TransparencyChanged = particleGui:GetPropertyChangedSignal("ImageTransparency"):Connect(function()
				particleGui.ImageTransparency = 1
			end)
			particleGui.ImageTransparency = 1
			ForeignParticleEvents[particleGui] = events
		end
	end)

	Emitter2D.GlobalEvents.CleanupForeignParticles = CollectionService:GetInstanceRemovedSignal("Emitter2D_Particle"):Connect(function(particleGui:ImageLabel)
		local events = ForeignParticleEvents[particleGui]
		if events then
			for name,conn in events do
				conn:Disconnect()
			end
			ForeignParticleEvents[particleGui] = nil
		end
	end)
	
	local function CleanUpParticleFolder(particleFolder:Folder)
		if particleFolder:GetAttribute("Owner") == UserId and Emitter2D.ParticleFolders[particleFolder] == nil then
			--print("Removing Duplicate Particle Folder ", particleFolder:GetFullName())
			task.defer(particleFolder.Destroy, particleFolder)
		end
	end
	
	Emitter2D.GlobalEvents.RemoveDuplicateFolders = CollectionService:GetInstanceAddedSignal("Emitter2D_ParticleFolder"):Connect(CleanUpParticleFolder)
	
	for _, particleFolder:Folder in CollectionService:GetTagged("Emitter2D_ParticleFolder") do
		CleanUpParticleFolder(particleFolder)
	end
end

function Emitter2D.disconnectGlobalEvents()
	RunService:UnbindFromRenderStep(EnvironmentId)
	for name,conn in Emitter2D.GlobalEvents do
		conn:Disconnect()
	end
end

if IsPlugin then
	Emitter2D.GlobalEvents.Deactivate = script.Parent.Parent.Events.Deactivate.Event:Connect(function()
		--print("Deactivating Emitter2D module")
		Emitter2D.disconnectGlobalEvents()
	end)
end

-- Return

return Emitter2D