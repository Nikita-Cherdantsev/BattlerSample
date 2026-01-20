--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

--// Modules
local EventBus = require(ReplicatedStorage.Modules.EventBus)

--// Module
local BattlePrepHandler = {}

--// State
BattlePrepHandler.Connections = {}
BattlePrepHandler._initialized = false
BattlePrepHandler.isAnimating = false
BattlePrepHandler.currentEnemyData = nil
BattlePrepHandler.currentPartName = nil -- Store current part name for NPC/Boss detection
BattlePrepHandler.currentBattleMode = "NPC" -- "NPC" | "Boss" | "Ranked"
BattlePrepHandler.forceMode = nil -- Can be set externally (e.g., by tutorial) to force battle mode
BattlePrepHandler.selectedNPCModelName = nil -- Store selected NPC model name until next battle
BattlePrepHandler.currentViewportModel = nil -- Store cloned model in ViewportFrame
BattlePrepHandler._rankedThumbCache = {} -- userId -> thumbnail content id string

-- Lightweight toast helper (reuses BattleHandler notification UI)
function BattlePrepHandler:ShowToast(message)
	local battleHandler = self.Controller and self.Controller:GetBattleHandler()
	if battleHandler and battleHandler.ShowNotification then
		-- Backward compatible: allow optional styling via second arg (table)
		battleHandler:ShowNotification(tostring(message))
	else
		warn("BattlePrepHandler toast:", tostring(message))
	end
end

function BattlePrepHandler:ShowToastStyled(message, opts)
	local battleHandler = self.Controller and self.Controller:GetBattleHandler()
	if battleHandler and battleHandler.ShowNotification then
		battleHandler:ShowNotification(tostring(message), opts)
	else
		warn("BattlePrepHandler toast:", tostring(message))
	end
end

--// Constants
local LOOTBOX_ASSETS = {
	uncommon = "rbxassetid://89282766853868",
	rare = "rbxassetid://101339929529268",
	epic = "rbxassetid://126842532670644",
	legendary = "rbxassetid://97529044228503",
	onepiece = "rbxassetid://102889022061002"
}

--// Initialization
function BattlePrepHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	
	-- Safe require of Utilities to avoid loading errors
	local success, utilities = pcall(function()
		return controller:GetModule("Utilities")
	end)
	
	if success then
		self.Utilities = utilities
		-- Also try to get Manifest directly
		local manifestSuccess, manifest = pcall(function()
			return require(game.ReplicatedStorage.Modules.Assets.Manifest)
		end)
		if manifestSuccess then
			self.Utilities.Manifest = manifest
			print("✅ BattlePrepHandler: Manifest loaded successfully")
		else
			warn("BattlePrepHandler: Could not load Manifest module: " .. tostring(manifest))
		end
	else
		warn("BattlePrepHandler: Could not load Utilities module: " .. tostring(utilities))
		self.Utilities = {
			CardCatalog = { GetCard = function() return nil end },
			CardStats = { ComputeStats = function() return {} end },
			Manifest = { 
				RarityColors = {},
				CardImages = {}
			},
			TweenUI = { FadeIn = function() end, FadeOut = function() end },
			Blur = { Show = function() end, Hide = function() end }
		}
	end

	-- Setup battle preparation functionality
	self:SetupBattlePrep()

	self._initialized = true
	print("✅ BattlePrepHandler initialized successfully!")
	return true
end

function BattlePrepHandler:SetupBattlePrep()
	-- Access UI from player's PlayerGui
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Wait for GameUI to be available
	local gameGui = playerGui:WaitForChild("GameUI", 10)
	if not gameGui then
		warn("BattlePrepHandler: GameUI not found in PlayerGui")
		return
	end
	
	-- Check if StartBattle frame exists
	local startBattleFrame = gameGui:FindFirstChild("StartBattle")
	if not startBattleFrame then
		warn("BattlePrepHandler: StartBattle frame not found in GameUI")
		return
	end
	
	-- Store UI references
	self.UI = gameGui
	self.StartBattleFrame = startBattleFrame
	
	
	-- Find Main frame
	local mainFrame = startBattleFrame:FindFirstChild("Main")
	if not mainFrame then
		warn("BattlePrepHandler: Main frame not found in StartBattle")
		return
	end
	
	
	-- Find Content frame
	local contentFrame = mainFrame:FindFirstChild("Content")
	if not contentFrame then
		warn("BattlePrepHandler: Content frame not found in Main")
		return
	end
	
	
	-- Find Rewards and RivalsDeck frames
	self.RewardsFrame = contentFrame:FindFirstChild("Rewards")
	self.RivalsDeckFrame = contentFrame:FindFirstChild("RivalsDeck")
	
	-- Find TxtRival frame for difficulty display (boss mode only)
	local txtRivalFrame = contentFrame:FindFirstChild("TxtRival")
	if txtRivalFrame then
		self.TxtRivalFrame = txtRivalFrame
		self.TxtDifficultyLabel = txtRivalFrame:FindFirstChild("TxtDifficulty")
		if not self.TxtDifficultyLabel then
			warn("BattlePrepHandler: TxtDifficulty TextLabel not found in TxtRival frame")
		end
		self:EnsureRankedInfoUI()
	end
	
	-- Find START button (Buttons frame is directly under StartBattle frame)
	-- Use WaitForChild for production reliability (handles late-loading UI)
	local buttonsFrame = startBattleFrame:WaitForChild("Buttons", 5)
	if buttonsFrame then
		-- Wait for button to exist (important for production where UI might load slower)
		self.StartButton = buttonsFrame:WaitForChild("BtnStart", 5)
		if self.StartButton then
			self:SetupStartButton()
		else
			warn("BattlePrepHandler: BtnStart not found in Buttons frame after waiting")
		end
	else
		warn("BattlePrepHandler: Buttons frame not found in StartBattle after waiting")
	end
	
	-- Setup match result callback
	self:SetupMatchResultCallback()
	
	if not self.RewardsFrame then
		warn("BattlePrepHandler: Rewards frame not found in Content")
	end
	
	if not self.RivalsDeckFrame then
		warn("BattlePrepHandler: RivalsDeck frame not found in Content")
	end
	
	-- Hide initially
	startBattleFrame.Visible = false
	
	-- Setup part interaction
	self:SetupPartInteraction()
	
	-- Setup close button
	self:SetupCloseButton()
	
	-- Setup RightPanel.BtnBattle button
	self:SetupRightPanelBattleButton()
	-- Setup RightPanel.BtnRankedBattle button (Ranked PvP MVP)
	self:SetupRightPanelRankedBattleButton()
	
	-- Setup tab buttons (BtnNPC, BtnBoss)
	self:SetupTabButtons()
	
	-- Find and store ViewportFrame reference
	local viewportFrame = mainFrame:FindFirstChild("ViewportFrame")
	if viewportFrame then
		self.ViewportFrame = viewportFrame
	else
		warn("BattlePrepHandler: ViewportFrame not found in Main")
	end
	
	print("✅ BattlePrepHandler: Battle preparation UI setup completed")
end

-- Helper function to setup interaction for a part
local function SetupPartInteractionHelper(part, partName, partType, handler)
	-- Accept BasePart, MeshPart, or Part
	if not part or not (part:IsA("BasePart") or part:IsA("MeshPart") or part:IsA("Part")) then
		warn("⚠️ Part is not a valid BasePart:", part and part.ClassName or "nil")
		return false
	end
	
	-- Store original part for battle logic (we might move ProximityPrompt to HumanoidRootPart)
	local originalPart = part
	local originalPartName = partName
	
	-- Check if part is inside a Humanoid (character parts can be problematic for ProximityPrompts)
	local humanoid = part:FindFirstAncestorOfClass("Humanoid")
	if humanoid then
		-- If part is inside Humanoid, put ProximityPrompt on HumanoidRootPart instead (better for interaction)
		local humanoidRootPart = humanoid.Parent:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
			part = humanoidRootPart
			-- Keep original partName for battle logic (still "BossMode1Head", not "HumanoidRootPart")
			-- partName stays as originalPartName
		end
	end
	
	-- Get or create ProximityPrompt
	local proximityPrompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not proximityPrompt then
		-- Create new ProximityPrompt
		proximityPrompt = Instance.new("ProximityPrompt")
		proximityPrompt.ActionText = "Start Battle"
		proximityPrompt.KeyboardKeyCode = Enum.KeyCode.E
		proximityPrompt.MaxActivationDistance = 30
		proximityPrompt.Enabled = true
		proximityPrompt.RequiresLineOfSight = false -- Don't require line of sight
		proximityPrompt.HoldDuration = 0 -- Instant activation
		proximityPrompt.Parent = part
	else
		-- Configure existing prompt (in case it was manually added)
		proximityPrompt.ActionText = "Start Battle"
		proximityPrompt.KeyboardKeyCode = Enum.KeyCode.E
		proximityPrompt.MaxActivationDistance = 30
		proximityPrompt.Enabled = true
		proximityPrompt.RequiresLineOfSight = false
		proximityPrompt.HoldDuration = 0
	end
	
	-- Verify the prompt is properly set up
	if not proximityPrompt or not proximityPrompt.Parent or proximityPrompt.Parent ~= part then
		warn("⚠️ ProximityPrompt setup failed for", partType, "part:", partName)
		return false
	end
	
	-- Disconnect any existing connections for this part to avoid duplicates
	-- (This handles the case where SetupPartInteraction is called multiple times)
	local partConnections = handler._partConnections or {}
	if partConnections[part] then
		for _, conn in ipairs(partConnections[part]) do
			if conn then
				conn:Disconnect()
			end
		end
		partConnections[part] = {}
	else
		partConnections[part] = {}
		if not handler._partConnections then
			handler._partConnections = {}
		end
		handler._partConnections[part] = partConnections[part]
	end
	
	-- Connect interaction (use original part name for battle logic)
	local connection = proximityPrompt.Triggered:Connect(function()
		-- Extract NPC/Boss name from model (prefer model name over part name)
		-- For tutorial, we need to match with path like "Workspace.Noob" or "Workspace.Rubber King"
		local modelName = nil
		if originalPart and originalPart.Parent then
			-- Try to get model name (Model.Name)
			local model = originalPart.Parent
			if model:IsA("Model") then
				modelName = model.Name
			else
				-- Fallback: try to find parent model
				local parentModel = originalPart:FindFirstAncestorOfClass("Model")
				if parentModel then
					modelName = parentModel.Name
				end
			end
		end
		
		-- Fallback to part name if model name not found
		if not modelName and originalPartName then
			-- Try to extract NPC name from part name
			-- NPCMode1Head -> Noob, BossMode1Head -> Rubber King, etc.
			if originalPartName:match("^NPCMode") then
				modelName = "Noob"  -- Default NPC name
			elseif originalPartName:match("^BossMode") then
				modelName = "Rubber King"  -- Default boss name
			else
				modelName = originalPartName
			end
		end
		
		-- Emit prompt activated event
		EventBus:Emit("PromptActivated", modelName or "NPC")
		
		-- Check if battle is already active
		local battleHandler = handler.Controller and handler.Controller:GetBattleHandler()
		if battleHandler and battleHandler.isBattleActive then
			return -- Don't allow interaction during battle
		end
		
		handler.currentPartName = originalPartName -- Use original name (e.g., "BossMode1Head") not "HumanoidRootPart"
		
		-- Save model name based on part type
		if originalPartName:match("^NPCMode") then
			-- NPC mode: save model name for display
			handler.selectedNPCModelName = modelName
			handler.currentBattleMode = "NPC"
		elseif originalPartName:match("^BossMode") then
			-- Boss mode: save model name temporarily
			handler._tempBossModelName = modelName
			handler.currentBattleMode = "Boss"
		end
		
		handler:OpenBattlePrep()
	end)
	
	table.insert(handler.Connections, connection)
	table.insert(partConnections[part], connection)
	
	return true
end

function BattlePrepHandler:SetupPartInteraction()
	-- Find all parts with NPCMode or BossMode prefix
	local workspace = game:GetService("Workspace")
	
	-- Track which parts we've already set up (by full path) to avoid duplicates
	local setupParts = {}
	
	-- Function to setup a single part if it matches our criteria
	local function SetupPartIfMatches(part)
		if not part or not (part:IsA("BasePart") or part:IsA("MeshPart") or part:IsA("Part")) then
			return false
		end
		
		local fullPath = part:GetFullName()
		
		-- Skip if already set up
		if setupParts[fullPath] then
			return false
		end
		
		local partType = nil
		if part.Name:match("^NPCMode") then
			partType = "NPC"
		elseif part.Name:match("^BossMode") then
			partType = "Boss"
		end
		
		if partType then
			if SetupPartInteractionHelper(part, part.Name, partType, self) then
				setupParts[fullPath] = true
				return true
			end
		end
		
		return false
	end
	
	-- Search all existing descendants in Workspace
	local allDescendants = workspace:GetDescendants()
	local foundCount = 0
	
	for _, descendant in pairs(allDescendants) do
		if SetupPartIfMatches(descendant) then
			foundCount = foundCount + 1
		end
	end
	
	-- Listen for new descendants being added (catches dynamically loaded models)
	local connection = workspace.DescendantAdded:Connect(function(descendant)
		SetupPartIfMatches(descendant)
	end)
	
	table.insert(self.Connections, connection)
	
	-- Fallback: support old "Part" name for backward compatibility
	local testPart = workspace:FindFirstChild("Part")
	if testPart then
		local proximityPrompt = Instance.new("ProximityPrompt")
		proximityPrompt.ActionText = "Start Battle"
		proximityPrompt.KeyboardKeyCode = Enum.KeyCode.E
		proximityPrompt.MaxActivationDistance = 30
		proximityPrompt.Parent = testPart
		
		-- Default to NPC mode if part name doesn't match
		local connection = proximityPrompt.Triggered:Connect(function()
			-- Emit prompt activated event
			EventBus:Emit("PromptActivated", "TestNPC")
			
			-- Check if battle is already active
			local battleHandler = self.Controller and self.Controller:GetBattleHandler()
			if battleHandler and battleHandler.isBattleActive then
				return -- Don't allow interaction during battle
			end
			
			self.currentPartName = "NPCMode1Trigger" -- Default NPC mode
			self:OpenBattlePrep()
		end)
		
		table.insert(self.Connections, connection)
		print("✅ BattlePrepHandler: Fallback part interaction setup completed")
	end
end

function BattlePrepHandler:SetupCloseButton()
	-- Close button is handled by CloseButtonHandler
	-- No need to set up individual close button here
end

function BattlePrepHandler:SetupRightPanelBattleButton()
	-- Find RightPanel and BtnBattle
	local rightPanel = self.UI:FindFirstChild("RightPanel")
	if not rightPanel then
		warn("BattlePrepHandler: RightPanel not found in GameUI")
		return
	end
	
	local btnBattle = rightPanel:FindFirstChild("BtnBattle")
	if not btnBattle then
		warn("BattlePrepHandler: BtnBattle not found in RightPanel")
		return
	end
	
	-- Connect click event
	local connection = btnBattle.MouseButton1Click:Connect(function()
		-- Emit button click event
		EventBus:Emit("ButtonClicked", "RightPanel.BtnBattle")
		
		-- Check if battle is already active
		local battleHandler = self.Controller and self.Controller:GetBattleHandler()
		if battleHandler and battleHandler.isBattleActive then
			return -- Don't allow interaction during battle
		end
		
		-- Open battle prep window
		if self.forceMode then
			-- Force mode is set externally (e.g., by tutorial)
			self.currentBattleMode = self.forceMode
			-- Don't set currentPartName to placeholder - let OpenBattlePrep() call EnsurePartNameForMode() to find real NPC/Boss
			-- This ensures the correct model is loaded and displayed
			self.currentPartName = nil
		else
			-- Default behavior: open in NPC mode
			self.currentBattleMode = "NPC"
			self.currentPartName = nil -- Will be set when selecting NPC
		end
		self:OpenBattlePrep()
	end)
	
	table.insert(self.Connections, connection)
	print("✅ BattlePrepHandler: RightPanel.BtnBattle button connected")
end

function BattlePrepHandler:SetupRightPanelRankedBattleButton()
	-- Find RightPanel and BtnRankedBattle
	local rightPanel = self.UI:FindFirstChild("RightPanel")
	if not rightPanel then
		warn("BattlePrepHandler: RightPanel not found in GameUI")
		return
	end
	
	local btnRankedBattle = rightPanel:FindFirstChild("BtnRankedBattle")
	if not btnRankedBattle then
		warn("BattlePrepHandler: BtnRankedBattle not found in RightPanel")
		return
	end
	
	local connection = btnRankedBattle.MouseButton1Click:Connect(function()
		EventBus:Emit("ButtonClicked", "RightPanel.BtnRankedBattle")
		
		-- Check if battle is already active
		local battleHandler = self.Controller and self.Controller:GetBattleHandler()
		if battleHandler and battleHandler.isBattleActive then
			return
		end
		
		self.currentBattleMode = "Ranked"
		self.currentPartName = nil

		-- Two-phase flow: only open the prep window if an opponent was found.
		self:LoadRankedOpponentData(function(ok)
			if ok then
				self:OpenBattlePrep()
			end
		end)
	end)
	
	table.insert(self.Connections, connection)
	print("✅ BattlePrepHandler: RightPanel.BtnRankedBattle button connected")
end

function BattlePrepHandler:SetupTabButtons()
	-- Find Main frame and Content frame
	local mainFrame = self.StartBattleFrame:FindFirstChild("Main")
	if not mainFrame then
		warn("BattlePrepHandler: Main frame not found for tab buttons")
		return
	end
	
	local contentFrame = mainFrame:FindFirstChild("Content")
	if not contentFrame then
		warn("BattlePrepHandler: Content frame not found for tab buttons")
		return
	end
	
	-- Find Tabs frame
	local tabsFrame = contentFrame:FindFirstChild("Tabs")
	if not tabsFrame then
		warn("BattlePrepHandler: Tabs frame not found in Content")
		return
	end
	self.TabsFrame = tabsFrame
	
	-- Find BtnNPC and BtnBoss
	self.BtnNPC = tabsFrame:FindFirstChild("BtnNPC")
	self.BtnBoss = tabsFrame:FindFirstChild("BtnBoss")
	
	if not self.BtnNPC then
		warn("BattlePrepHandler: BtnNPC not found in Tabs")
	end
	
	if not self.BtnBoss then
		warn("BattlePrepHandler: BtnBoss not found in Tabs")
	end
	
	-- Setup BtnNPC click handler
	if self.BtnNPC then
		local connection = self.BtnNPC.MouseButton1Click:Connect(function()
			-- Don't do anything if already in NPC mode
			if self.currentBattleMode == "NPC" then
				return
			end
			
			-- Switch to NPC mode
			self.currentBattleMode = "NPC"
			self:UpdateTabGradients()
			self:SwitchBattleMode()
		end)
		table.insert(self.Connections, connection)
	end
	
	-- Setup BtnBoss click handler
	if self.BtnBoss then
		local connection = self.BtnBoss.MouseButton1Click:Connect(function()
			-- Don't do anything if already in Boss mode
			if self.currentBattleMode == "Boss" then
				return
			end
			
			-- Switch to Boss mode
			self.currentBattleMode = "Boss"
			self:UpdateTabGradients()
			self:SwitchBattleMode()
		end)
		table.insert(self.Connections, connection)
	end
	
	print("✅ BattlePrepHandler: Tab buttons (BtnNPC, BtnBoss) connected")
	
	-- Update gradients for initial state (NPC is default active)
	self:UpdateTabGradients()
end

-- Update gradients for tab buttons based on active mode
function BattlePrepHandler:UpdateTabGradients()
	-- Create gradients once (optimization)
	local activeGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("#49ba4a")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("#00afa9"))
	})
	local inactiveGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("#225622")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("#00615c"))
	})
	
	-- Helper function to update gradient
	local function UpdateGradient(button, isActive)
		if not button then return end
		local gradient = button:FindFirstChild("UIGradient")
		if gradient then
			gradient.Color = isActive and activeGradient or inactiveGradient
		end
	end
	
	UpdateGradient(self.BtnNPC, self.currentBattleMode == "NPC")
	UpdateGradient(self.BtnBoss, self.currentBattleMode == "Boss")
end

-- Helper function to find a model by name in all descendants (replacement for FindFirstDescendant)
local function FindModelInDescendants(parent, modelName)
	-- First try direct child
	local found = parent:FindFirstChild(modelName)
	if found and found:IsA("Model") then
		return found
	end
	
	-- Then search in all descendants
	for _, descendant in pairs(parent:GetDescendants()) do
		if descendant:IsA("Model") and descendant.Name == modelName then
			return descendant
		end
	end
	
	return nil
end

-- Helper function to find a part by name in all descendants
local function FindPartInDescendants(parent, partName)
	-- First try direct child
	local found = parent:FindFirstChild(partName)
	if found and (found:IsA("BasePart") or found:IsA("MeshPart") or found:IsA("Part")) then
		return found
	end
	
	-- Then search in all descendants
	for _, descendant in pairs(parent:GetDescendants()) do
		if (descendant:IsA("BasePart") or descendant:IsA("MeshPart") or descendant:IsA("Part")) and descendant.Name == partName then
			return descendant
		end
	end
	
	return nil
end

-- Helper function to find models by part prefix (optimized with set for O(1) lookup)
local function FindModelsByPartPrefix(prefix)
	local models = {}
	local modelSet = {} -- Use set for O(1) lookup instead of O(n) linear search
	local workspace = Workspace
	
	for _, descendant in pairs(workspace:GetDescendants()) do
		if (descendant:IsA("BasePart") or descendant:IsA("MeshPart") or descendant:IsA("Part")) 
			and descendant.Name:match("^" .. prefix) then
			local model = descendant:FindFirstAncestorOfClass("Model")
			if model and model.Name and not modelSet[model.Name] then
				modelSet[model.Name] = true
				table.insert(models, model.Name)
			end
		end
	end
	
	return models
end

-- Helper function to find NPC models in Workspace
function BattlePrepHandler:FindNPCModels()
	return FindModelsByPartPrefix("NPCMode")
end

-- Helper function to find Boss models in Workspace
function BattlePrepHandler:FindBossModels()
	return FindModelsByPartPrefix("BossMode")
end

-- Helper function to set currentPartName from model name
local function SetPartNameFromModel(handler, modelName, expectedPrefix)
	if not modelName then return false end
	
	local workspace = Workspace
	local model = FindModelInDescendants(workspace, modelName)
	if not model or not model:IsA("Model") then
		return false
	end
	
	for _, descendant in pairs(model:GetDescendants()) do
		if (descendant:IsA("BasePart") or descendant:IsA("MeshPart") or descendant:IsA("Part")) 
			and descendant.Name:match("^" .. expectedPrefix) then
			handler.currentPartName = descendant.Name
			return true
		end
	end
	
	return false
end

-- Select random NPC model and save it
function BattlePrepHandler:SelectRandomNPC()
	local npcModels = self:FindNPCModels()
	if #npcModels == 0 then
		warn("BattlePrepHandler: No NPC models found in Workspace")
		return nil
	end
	
	-- Select random NPC
	local randomIndex = math.random(1, #npcModels)
	local selectedNPC = npcModels[randomIndex]
	
	-- Save selected NPC until next battle
	self.selectedNPCModelName = selectedNPC
	
	-- Set part name using helper function
	if not SetPartNameFromModel(self, selectedNPC, "NPCMode") then
		warn("BattlePrepHandler: Failed to find NPCMode part for NPC:", selectedNPC)
	end
	
	print("✅ BattlePrepHandler: Selected random NPC:", selectedNPC)
	return selectedNPC
end

-- Clone model into ViewportFrame
function BattlePrepHandler:CloneModelToViewport(modelName, isBoss)
	if not self.ViewportFrame then
		warn("BattlePrepHandler: ViewportFrame not found")
		return
	end
	
	-- Clean up existing model in ViewportFrame
	if self.currentViewportModel then
		self.currentViewportModel:Destroy()
		self.currentViewportModel = nil
	end
	
	-- Find model in Workspace (search in all descendants, not just direct children)
	local workspace = Workspace
	local sourceModel = FindModelInDescendants(workspace, modelName)
	
	if not sourceModel then
		warn("BattlePrepHandler: Model not found in Workspace:", modelName)
		return
	end
	
	-- Ensure it's a Model
	if not sourceModel:IsA("Model") then
		warn("BattlePrepHandler: Found object is not a Model:", modelName, sourceModel.ClassName)
		return
	end
	
	-- Clone model
	local clonedModel = sourceModel:Clone()
	
	-- Get current pivot
	local modelPivot = clonedModel:GetPivot()
	local targetCFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(-150), 0)
	
	-- Set Scale to 1 for the entire model using ScaleTo (once, before moving)
	pcall(function()
		clonedModel:ScaleTo(1)
	end)
	
	if modelPivot then
		-- Model uses Pivot - use PivotTo to move to origin with rotation
		clonedModel:PivotTo(targetCFrame)
	else
		-- Model uses PrimaryPart - move using PrimaryPart
		local primaryPart = clonedModel.PrimaryPart
		if not primaryPart then
			-- Try to find HumanoidRootPart
			primaryPart = clonedModel:FindFirstChild("HumanoidRootPart")
		end
		if not primaryPart then
			-- Find first BasePart
			for _, descendant in pairs(clonedModel:GetDescendants()) do
				if descendant:IsA("BasePart") then
					primaryPart = descendant
					break
				end
			end
		end
		
		if primaryPart then
			-- Move all parts to origin (0,0,0) and apply rotation
			for _, part in pairs(clonedModel:GetDescendants()) do
				if part:IsA("BasePart") then
					-- Calculate relative position from primary part
					local relativeCFrame = primaryPart.CFrame:ToObjectSpace(part.CFrame)
					-- Apply to target position
					part.CFrame = targetCFrame:ToWorldSpace(relativeCFrame)
				end
			end
			
			-- Set PrimaryPart if model has one
			if clonedModel.PrimaryPart then
				clonedModel:SetPrimaryPartCFrame(targetCFrame)
			end
		else
			warn("BattlePrepHandler: No primary part found in model:", modelName)
		end
	end
	
	-- Parent to ViewportFrame
	clonedModel.Parent = self.ViewportFrame
	
	-- Store reference
	self.currentViewportModel = clonedModel
	
	print("✅ BattlePrepHandler: Cloned model to ViewportFrame:", modelName)
end

-- Animate ViewportFrame sliding in from left
function BattlePrepHandler:AnimateViewportFrameIn(callback)
	if not self.ViewportFrame then
		if callback then callback() end
		return
	end
	
	-- Set initial position (off-screen to the left)
	local initialPosition = UDim2.new(-1, 0, 1.418, 0)
	self.ViewportFrame.Position = initialPosition
	
	-- Set target position (on-screen)
	local targetPosition = UDim2.new(-0.095, 0, 1.418, 0)
	
	-- Get TweenUI duration (default 0.3 seconds)
	local duration = 0.3
	
	-- Create tween
	local tween = TweenService:Create(
		self.ViewportFrame,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = targetPosition}
	)
	
	tween:Play()
	
	if callback then
		tween.Completed:Connect(function()
			callback()
		end)
	end
end

-- Animate ViewportFrame sliding out to left
function BattlePrepHandler:AnimateViewportFrameOut(callback)
	if not self.ViewportFrame then
		if callback then callback() end
		return
	end
	
	-- Set target position (off-screen to the left)
	local targetPosition = UDim2.new(-1, 0, 1.418, 0)
	
	-- Get TweenUI duration (default 0.3 seconds)
	local duration = 0.3
	
	-- Create tween
	local tween = TweenService:Create(
		self.ViewportFrame,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Position = targetPosition}
	)
	
	tween:Play()
	
	if callback then
		tween.Completed:Connect(function()
			callback()
		end)
	end
end

-- Reload enemy data and update UI (used when switching modes with window already open)
function BattlePrepHandler:ReloadEnemyData()
	local loadFunction = nil
	if self.currentBattleMode == "NPC" then
		loadFunction = self.LoadNPCEnemyData
	elseif self.currentBattleMode == "Boss" then
		loadFunction = self.LoadBossEnemyData
	elseif self.currentBattleMode == "Ranked" then
		loadFunction = self.LoadRankedOpponentData
	end
	
	if loadFunction then
		loadFunction(self, function()
			self:UpdateRewardsDisplay()
			self:UpdateRivalsDeckDisplay()
			self:UpdateDifficultyDisplay()
		end)
	end
end

-- Ensure currentPartName is set for current battle mode
function BattlePrepHandler:EnsurePartNameForMode()
	if self.currentBattleMode == "NPC" then
		-- Always ensure we have a selected NPC
		if not self.selectedNPCModelName then
			self:SelectRandomNPC()
		end
		-- Ensure currentPartName is set
		if not self.currentPartName or not self.currentPartName:match("^NPCMode") then
			if not SetPartNameFromModel(self, self.selectedNPCModelName, "NPCMode") then
				-- If failed, try to select NPC again
				local npcModelName = self:SelectRandomNPC()
				if not npcModelName then
					warn("BattlePrepHandler: Failed to select NPC model")
					return false
				end
				-- After selecting NPC again, try to set part name once more
				if not SetPartNameFromModel(self, self.selectedNPCModelName, "NPCMode") then
					warn("BattlePrepHandler: Failed to set part name for NPC:", self.selectedNPCModelName)
					return false
				end
			end
		end
		return true
	elseif self.currentBattleMode == "Boss" then
		-- Ensure currentPartName is set for Boss mode
		if not self.currentPartName or not self.currentPartName:match("^BossMode") then
			local bossModels = self:FindBossModels()
			if #bossModels > 0 then
				if not SetPartNameFromModel(self, bossModels[1], "BossMode") then
					warn("BattlePrepHandler: Failed to set part name for Boss:", bossModels[1])
					return false
				end
			else
				warn("BattlePrepHandler: No boss models found")
				return false
			end
		end
		return true
	end
	return false
end

-- Switch battle mode (NPC <-> Boss)
function BattlePrepHandler:SwitchBattleMode()
	if self.isAnimating then return end
	
	local modelName = nil
	local expectedPrefix = nil
	local isBoss = false
	
	if self.currentBattleMode == "NPC" then
		modelName = self.selectedNPCModelName
		if not modelName then
			modelName = self:SelectRandomNPC()
		end
		expectedPrefix = "NPCMode"
		isBoss = false
	elseif self.currentBattleMode == "Boss" then
		local bossModels = self:FindBossModels()
		if #bossModels > 0 then
			modelName = bossModels[1]
		end
		expectedPrefix = "BossMode"
		isBoss = true
	end
	
	-- Set part name if needed
	if modelName and expectedPrefix then
		if not self.currentPartName or not self.currentPartName:match("^" .. expectedPrefix) then
			SetPartNameFromModel(self, modelName, expectedPrefix)
		end
		
		-- Clone model to viewport (model existence is checked inside CloneModelToViewport)
		if FindModelInDescendants(Workspace, modelName) then
			self:CloneModelToViewport(modelName, isBoss)
		end
	end
	
	-- Reload data if window is already open
	if self.StartBattleFrame and self.StartBattleFrame.Visible then
		self:ReloadEnemyData()
	else
		-- Window not open, use full OpenBattlePrep
		self:OpenBattlePrep()
	end
end

function BattlePrepHandler:OpenBattlePrep()
	if self.isAnimating then return end
	self.isAnimating = true

	-- Mark battle as active (prevents other interactions)
	local battleHandler = self.Controller and self.Controller:GetBattleHandler()
	if battleHandler then
		battleHandler.isBattleActive = true
	end

	-- Determine battle mode
	-- If opened from proximity prompt, use part name to determine mode
	-- If opened from button or tab switch, use currentBattleMode
	local isNPCMode = false
	local isBossMode = false
	local isRankedMode = false
	
	if self.currentPartName then
		-- Opened from proximity prompt - determine from part name
		-- Model name and battle mode should already be set in proximity prompt handler
		isNPCMode = self.currentPartName:match("^NPCMode")
		isBossMode = self.currentPartName:match("^BossMode")
		
		-- Ensure battle mode is set (should already be set in proximity prompt handler)
		if isNPCMode then
			self.currentBattleMode = "NPC"
		elseif isBossMode then
			self.currentBattleMode = "Boss"
		end
	else
		-- Opened from button or tab switch - use currentBattleMode
		isNPCMode = (self.currentBattleMode == "NPC")
		isBossMode = (self.currentBattleMode == "Boss")
		isRankedMode = (self.currentBattleMode == "Ranked")
		
		-- Ensure part name is set for current mode (NPC/Boss only)
		if not isRankedMode then
		self:EnsurePartNameForMode()
		end
	end
	
	-- Hide HUD panels if they exist
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = false
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = false
	end
	if self.UI.RightPanel then
		self.UI.RightPanel.Visible = false
	end
	
	-- Load enemy data based on mode
	if isNPCMode then
		-- Verify currentPartName is set before loading NPC deck
		if not self.currentPartName or not self.currentPartName:match("^NPCMode") then
			warn("BattlePrepHandler: currentPartName not set for NPC mode, cannot load deck")
			self:LoadTestEnemyData()
			self:UpdateRewardsDisplay()
			self:UpdateRivalsDeckDisplay()
			self:UpdateDifficultyDisplay()
			self:ShowBattlePrepWindow()
			return
		end
		
		-- NPC mode: request NPC deck from server (async)
		self:LoadNPCEnemyData(function()
			-- After NPC deck loads, update UI and show window
			self:UpdateRewardsDisplay()
			self:UpdateRivalsDeckDisplay()
			self:UpdateDifficultyDisplay()
			self:ShowBattlePrepWindow()
		end)
		return -- Will continue after NPC deck loads
	elseif isBossMode then
		-- Boss mode: request boss deck from server (async)
		self:LoadBossEnemyData(function()
			-- After boss deck loads, update UI and show window
			self:UpdateRewardsDisplay()
			self:UpdateRivalsDeckDisplay()
			self:UpdateDifficultyDisplay()
			self:ShowBattlePrepWindow()
		end)
		return -- Will continue after boss deck loads
	elseif isRankedMode then
		-- Ranked mode: opponent must already be selected by the button (two-phase flow).
		-- If selection is missing, do not open the window (toast is handled by LoadRankedOpponentData).
		if not self._rankedOpponentUserId or not self._rankedTicket then
			self.isAnimating = false
			return
		end
		
		-- Update UI and show window (no extra server call)
		self:UpdateRewardsDisplay()
		self:UpdateRivalsDeckDisplay()
		self:UpdateDifficultyDisplay()
		self:ShowBattlePrepWindow()
		return
	else
		-- Default: use test data
		self:LoadTestEnemyData()
	end

	-- Update UI with enemy data
	self:UpdateRewardsDisplay()
	self:UpdateRivalsDeckDisplay()
	self:UpdateDifficultyDisplay()
	
	-- Show battle prep window
	self:ShowBattlePrepWindow()
end

function BattlePrepHandler:EnsureRankedInfoUI()
	-- We create small UI widgets in code so you don't need to edit the Roblox UI hierarchy manually.
	-- They live under Content/TxtRival (already present in the battle prep UI).
	if not self.TxtRivalFrame or not self.TxtRivalFrame:IsA("GuiObject") then
		return
	end

	if self.TxtRivalFrame:FindFirstChild("RankedInfo") then
		self.RankedInfoFrame = self.TxtRivalFrame:FindFirstChild("RankedInfo")
		self.RankedOpponentNameLabel = self.RankedInfoFrame:FindFirstChild("TxtOpponentName")
		self.RankedOpponentRatingLabel = self.RankedInfoFrame:FindFirstChild("TxtOpponentRating")
		self.RankedOpponentThumb = self.RankedInfoFrame:FindFirstChild("ImgOpponentThumb")
		self.RankedTitleLabel = self.RankedInfoFrame:FindFirstChild("TxtRankedTitle")
		return
	end

	local rankedInfo = Instance.new("Frame")
	rankedInfo.Name = "RankedInfo"
	rankedInfo.BackgroundTransparency = 1
	-- Keep it in the left gutter so it doesn't overlap rival cards.
	-- Height follows parent (TxtRival), width is constrained.
	rankedInfo.AnchorPoint = Vector2.new(0, 0)
	rankedInfo.Position = UDim2.fromOffset(0, 0)
	rankedInfo.Size = UDim2.new(0, 170, 1, 0)
	rankedInfo.Visible = false
	rankedInfo.Parent = self.TxtRivalFrame

	local thumb = Instance.new("ImageLabel")
	thumb.Name = "ImgOpponentThumb"
	thumb.BackgroundTransparency = 1
	thumb.Size = UDim2.fromOffset(34, 34)
	thumb.Position = UDim2.fromOffset(0, 2)
	thumb.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
	thumb.ScaleType = Enum.ScaleType.Crop
	thumb.Parent = rankedInfo

	local thumbCorner = Instance.new("UICorner")
	thumbCorner.CornerRadius = UDim.new(1, 0)
	thumbCorner.Parent = thumb

	local title = Instance.new("TextLabel")
	title.Name = "TxtRankedTitle"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(40, 0)
	title.Size = UDim2.new(1, -40, 0, 16)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.TextColor3 = Color3.fromRGB(255, 215, 0)
	title.Text = "RANKED"
	title.Parent = rankedInfo

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "TxtOpponentName"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(40, 16)
	nameLabel.Size = UDim2.new(1, -40, 0, 18)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Top
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = "Opponent"
	nameLabel.Parent = rankedInfo

	local ratingLabel = Instance.new("TextLabel")
	ratingLabel.Name = "TxtOpponentRating"
	ratingLabel.BackgroundTransparency = 1
	ratingLabel.Position = UDim2.fromOffset(40, 34)
	ratingLabel.Size = UDim2.new(1, -40, 0, 14)
	ratingLabel.Font = Enum.Font.Gotham
	ratingLabel.TextSize = 11
	ratingLabel.TextXAlignment = Enum.TextXAlignment.Left
	ratingLabel.TextYAlignment = Enum.TextYAlignment.Top
	ratingLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	ratingLabel.Text = "Rating: ?"
	-- Many UI variants clip TxtRival height; we keep rating hidden and fold it into the name line.
	ratingLabel.Visible = false
	ratingLabel.Parent = rankedInfo

	self.RankedInfoFrame = rankedInfo
	self.RankedOpponentNameLabel = nameLabel
	self.RankedOpponentRatingLabel = ratingLabel
	self.RankedOpponentThumb = thumb
	self.RankedTitleLabel = title
end

function BattlePrepHandler:UpdateRankedInfoDisplay()
	-- Called as part of UpdateDifficultyDisplay() flow so it refreshes whenever the prep window data reloads.
	if not self.TxtRivalFrame then
		return
	end

	self:EnsureRankedInfoUI()

	local isRanked = (self.currentBattleMode == "Ranked")
	if not isRanked then
		if self.RankedInfoFrame then
			self.RankedInfoFrame.Visible = false
		end
		return
	end

	if not self.RankedInfoFrame then
		return
	end

	local opponent = self.currentEnemyData and self.currentEnemyData.rankedOpponent or nil
	local oppName = opponent and opponent.name or "Opponent"
	local oppRating = opponent and opponent.rating

	self.RankedInfoFrame.Visible = true

	if self.RankedOpponentNameLabel then
		if type(oppRating) == "number" then
			self.RankedOpponentNameLabel.Text = string.format("%s  •  %d", tostring(oppName), math.floor(oppRating))
		else
			self.RankedOpponentNameLabel.Text = tostring(oppName)
		end
	end
	-- Rating label is intentionally hidden; rating is shown inline with name.

	-- Thumbnail: only available for real numeric userIds. Ghosts/unknown fall back to placeholder.
	local thumb = self.RankedOpponentThumb
	if thumb then
		local oppUserId = opponent and opponent.userId
		local numericId = tonumber(oppUserId)
		if numericId and numericId > 0 then
			local cached = self._rankedThumbCache[numericId]
			if cached then
				thumb.Image = cached
			else
				task.spawn(function()
					local ok, content = pcall(function()
						return Players:GetUserThumbnailAsync(numericId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
					end)
					if ok and type(content) == "string" and content ~= "" then
						self._rankedThumbCache[numericId] = content
						-- Guard against the UI being destroyed/recreated.
						if self.RankedOpponentThumb == thumb then
							thumb.Image = content
						end
					else
						thumb.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
					end
				end)
			end
		else
			thumb.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
		end
	end
end

function BattlePrepHandler:LoadRankedOpponentData(onComplete)
	task.spawn(function()
		-- Show "searching" toast while InvokeServer is in-flight (it can take a while).
		self._rankedFindToken = (self._rankedFindToken or 0) + 1
		local findToken = self._rankedFindToken
		self:ShowToastStyled("Looking for a rival...", {
			textColor = Color3.fromRGB(255, 255, 255),
			strokeColor = Color3.fromRGB(0, 160, 255),
			duration = 3.0,
		})
		task.spawn(function()
			-- Re-show periodically so the user always sees feedback (ShowNotification auto-hides after ~3s).
			while self._rankedFindToken == findToken do
				task.wait(2.7)
				if self._rankedFindToken ~= findToken then
					break
				end
				self:ShowToastStyled("Looking for a rival...", {
					textColor = Color3.fromRGB(255, 255, 255),
					strokeColor = Color3.fromRGB(0, 160, 255),
					duration = 3.0,
				})
			end
		end)

		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local NetworkFolder = ReplicatedStorage:WaitForChild("Network", 10)
		if not NetworkFolder then
			warn("BattlePrepHandler: Network folder not found (ranked)")
			self:LoadTestEnemyData()
			self._rankedFindToken = self._rankedFindToken + 1
			if onComplete then onComplete() end
			return
		end
		
		local RequestRankedOpponent = NetworkFolder:FindFirstChild("RequestRankedOpponent")
		if not RequestRankedOpponent then
			warn("BattlePrepHandler: RequestRankedOpponent RemoteFunction not found")
			self:LoadTestEnemyData()
			self._rankedFindToken = self._rankedFindToken + 1
			if onComplete then onComplete() end
			return
		end
		
		local success, result = pcall(function()
			return RequestRankedOpponent:InvokeServer()
		end)

		-- Stop "searching" loop
		self._rankedFindToken = self._rankedFindToken + 1

		-- Hide the searching toast immediately (so it doesn't linger for a couple seconds after success).
		local battleHandler = self.Controller and self.Controller:GetBattleHandler()
		if battleHandler and battleHandler.HideNotification then
			battleHandler:HideNotification()
		end
		
		if not success or not result or not result.ok then
			local code = result and result.error and result.error.code
			local msg = result and result.error and result.error.message or "Unknown error"
			warn("BattlePrepHandler: Failed to get ranked opponent:", msg)
			
			-- Ranked MVP: show toast and keep window open, but disable Start
			if code == "NO_OPPONENTS" then
				self:ShowToast("No opponents found. Please try again later.")
			else
				self:ShowToast("Couldn't find an opponent. Please try again later.")
			end
			
			self._rankedOpponentUserId = nil
			self._rankedTicket = nil
			self.currentEnemyData = { deck = {}, levels = {}, rewards = {}, rankedOpponent = nil }
			if self.StartButton and self.StartButton:IsA("GuiButton") then
				self.StartButton.Active = false
			end
			
			if onComplete then onComplete(false) end
			return
		end
		
		self._rankedOpponentUserId = result.opponent and result.opponent.userId or nil
		self._rankedTicket = result.ticket
		
		self.currentEnemyData = {
			deck = result.deck or {},
			levels = result.levels or {},
			-- Ranked: show possible rewards similar to NPC (cosmetic + aligns with actual rewards)
			rewards = {
				{ type = "lootbox", rarity = "uncommon", count = 1, available = true },
				{ type = "lootbox", rarity = "rare", count = 1, available = true },
				{ type = "lootbox", rarity = "epic", count = 1, available = true },
				{ type = "lootbox", rarity = "legendary", count = 1, available = true },
			},
			rankedOpponent = result.opponent
		}
		
		if onComplete then onComplete(true) end
	end)
end

function BattlePrepHandler:ShowBattlePrepWindow()
	-- Reset request flag when opening window (in case it was stuck)
	self._isRequestingBattle = false
	
	-- Ensure Start button is enabled when opening window
	if self.StartButton and self.StartButton:IsA("GuiButton") then
		-- Ranked requires an opponent ticket
		if self.currentBattleMode == "Ranked" then
			self.StartButton.Active = (self._rankedTicket ~= nil and self._rankedOpponentUserId ~= nil)
		else
		self.StartButton.Active = true
		end
	end

	-- Ranked should not show NPC/Boss tabs (prevents accidental mode switching).
	if self.TabsFrame then
		self.TabsFrame.Visible = (self.currentBattleMode ~= "Ranked")
	end
	
	-- Update tab gradients to reflect current battle mode
	self:UpdateTabGradients()
	
	-- Update ViewportFrame with appropriate model
	if self.currentBattleMode == "NPC" then
		if self.ViewportFrame then
			self.ViewportFrame.Visible = true
		end
		local npcModelName = self.selectedNPCModelName
		if npcModelName and FindModelInDescendants(Workspace, npcModelName) then
			self:CloneModelToViewport(npcModelName, false)
		elseif npcModelName then
			warn("BattlePrepHandler: NPC model not found in Workspace:", npcModelName, "- skipping ViewportFrame update")
		end
	elseif self.currentBattleMode == "Boss" then
		if self.ViewportFrame then
			self.ViewportFrame.Visible = true
		end
		-- Use temp boss model name if set (from proximity prompt), otherwise find first boss
		local bossModelName = self._tempBossModelName
		if not bossModelName then
			local bossModels = self:FindBossModels()
			if #bossModels > 0 then
				bossModelName = bossModels[1]
			end
		end
		if bossModelName and FindModelInDescendants(Workspace, bossModelName) then
			self:CloneModelToViewport(bossModelName, true)
		elseif bossModelName then
			warn("BattlePrepHandler: Boss model not found in Workspace:", bossModelName, "- skipping ViewportFrame update")
		end
		-- Clear temp boss model name
		self._tempBossModelName = nil
	elseif self.currentBattleMode == "Ranked" then
		-- Ranked MVP: no model/thumbnail yet
		if self.ViewportFrame then
			self.ViewportFrame.Visible = false
		end
	end
	
	-- Show battle prep gui
	self.StartBattleFrame.Visible = true
	
	-- Register with close button handler
	self:RegisterWithCloseButton(true)

	-- Animate ViewportFrame sliding in (skip for Ranked since it's hidden)
	if self.currentBattleMode ~= "Ranked" then
	self:AnimateViewportFrameIn(function()
		-- ViewportFrame animation completed
	end)
	end

	-- Use TweenUI if available, otherwise just show
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
			self.Utilities.TweenUI.FadeIn(self.StartBattleFrame, .3, function ()
				self.isAnimating = false
				-- Emit window opened event after animation completes
				EventBus:Emit("WindowOpened", "StartBattle")
			end)
		else
			self.isAnimating = false
			-- Emit window opened event immediately if no animation
			EventBus:Emit("WindowOpened", "StartBattle")
		end
		if self.Utilities.Blur then
			self.Utilities.Blur.Show()
		end
	else
		-- Fallback: no animation
		self.isAnimating = false
	end
	
	print("✅ BattlePrepHandler: Battle preparation window opened")
end

function BattlePrepHandler:LoadNPCEnemyData(onComplete)
	-- Request NPC deck via RemoteFunction (async)
	task.spawn(function()
		-- Request NPC deck via RemoteFunction
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local NetworkFolder = ReplicatedStorage:WaitForChild("Network", 10)
		if not NetworkFolder then
			warn("BattlePrepHandler: Network folder not found")
			self:LoadTestEnemyData() -- Fallback to test data
			if onComplete then onComplete() end
			return
		end
		
		local RequestNPCDeck = NetworkFolder:FindFirstChild("RequestNPCDeck")
		if not RequestNPCDeck then
			warn("BattlePrepHandler: RequestNPCDeck RemoteFunction not found")
			self:LoadTestEnemyData() -- Fallback
			if onComplete then onComplete() end
			return
		end
		
		-- Call server to get/generate NPC deck
		local success, result = pcall(function()
			return RequestNPCDeck:InvokeServer(self.currentPartName)
		end)
		
		if not success or not result or not result.ok then
			warn("BattlePrepHandler: Failed to get NPC deck:", result and result.error and result.error.message or "Unknown error")
			self:LoadTestEnemyData() -- Fallback
			if onComplete then onComplete() end
			return
		end
		
		-- Create enemy data from NPC deck
		-- Use server-generated reward (for victory) if available
	local reward = result.reward or {type = "lootbox", rarity = "uncommon", count = 1}
	local raritiesInPool = result.rarityPool or {"uncommon", "rare", "epic", "legendary"}
	local rewardFrames = {}
	for _, rarity in ipairs(raritiesInPool) do
		table.insert(rewardFrames, {type = "lootbox", rarity = rarity, count = 1, available = true})
	end
	self.currentEnemyData = {
		name = "NPC Opponent",
		deck = result.deck or {},
		levels = result.levels or {}, -- Store levels for each card
		rewards = rewardFrames,
		rewardRarity = reward.rarity,
		rankedOpponent = nil,
	}
		
		print("✅ BattlePrepHandler: NPC deck loaded with", #self.currentEnemyData.deck, "cards")
		
		-- Call completion callback
		if onComplete then
			onComplete()
		end
	end)
end

function BattlePrepHandler:LoadBossEnemyData(onComplete)
	-- Request boss deck via RemoteFunction (async)
	task.spawn(function()
		-- Request boss deck via RemoteFunction
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local NetworkFolder = ReplicatedStorage:WaitForChild("Network", 10)
		if not NetworkFolder then
			warn("BattlePrepHandler: Network folder not found")
			self:LoadTestEnemyData() -- Fallback to test data
			if onComplete then onComplete() end
			return
		end
		
		local RequestNPCDeck = NetworkFolder:FindFirstChild("RequestNPCDeck")
		if not RequestNPCDeck then
			warn("BattlePrepHandler: RequestNPCDeck RemoteFunction not found")
			self:LoadTestEnemyData() -- Fallback
			if onComplete then onComplete() end
			return
		end
		
		-- Call server to get boss deck
		local success, result = pcall(function()
			return RequestNPCDeck:InvokeServer(self.currentPartName)
		end)
		
		if not success or not result or not result.ok then
			warn("BattlePrepHandler: Failed to get boss deck:", result and result.error and result.error.message or "Unknown error")
			self:LoadTestEnemyData() -- Fallback
			if onComplete then onComplete() end
			return
		end
		
		-- Create enemy data from boss deck
		-- Use server-provided hardcoded reward (from BossDecks)
		local reward = result.reward or {type = "lootbox", rarity = "legendary", count = 1}
		self.currentEnemyData = {
			name = "Boss Opponent",
			deck = result.deck or {},
			levels = result.levels or {}, -- Store levels for each card
			rewards = {reward}, -- Single reward (lootbox) as hardcoded in BossDecks
			bossId = result.bossId,
			difficulty = result.difficulty, -- Store difficulty for UI display
			rankedOpponent = nil,
		}
		
		print("✅ BattlePrepHandler: Boss deck loaded - boss:", result.bossId, "difficulty:", result.difficulty, "cards:", #self.currentEnemyData.deck)
		
		-- Call completion callback
		if onComplete then
			onComplete()
		end
	end)
end

function BattlePrepHandler:LoadTestEnemyData()
	-- Create test enemy data with different numbers of cards and rewards
	self.currentEnemyData = {
		name = "Test Enemy",
		deck = {
			"card_100", -- Legendary card
			"card_200", -- Legendary card  
			"card_300"  -- Epic card
		},
		rewards = {
			{type = "lootbox", rarity = "uncommon", count = 1, available = true},
			{type = "lootbox", rarity = "rare", count = 1, available = true},
			{type = "lootbox", rarity = "epic", count = 1, available = true},
			{type = "lootbox", rarity = "legendary", count = 1, available = true}
		},
		rewardRarity = "uncommon",
		rankedOpponent = nil,
	}
	
	print("✅ BattlePrepHandler: Test enemy data loaded with", #self.currentEnemyData.deck, "cards and", #self.currentEnemyData.rewards, "reward types")
end

function BattlePrepHandler:UpdateRewardsDisplay()
	if not self.RewardsFrame or not self.currentEnemyData then
		return
	end
	
	-- Find the template reward frame (the first one)
	local templateReward = nil
	for _, child in pairs(self.RewardsFrame:GetChildren()) do
		if child.Name:match("^Reward%d+$") and child:IsA("Frame") then
			templateReward = child
			break
		end
	end
	
	if not templateReward then
		warn("BattlePrepHandler: No template reward frame found in Rewards")
		return
	end
	
	-- Hide ALL existing reward frames (including templates)
	for _, child in pairs(self.RewardsFrame:GetChildren()) do
		if child.Name:match("^Reward%d+$") and child:IsA("Frame") then
			child.Visible = false
		end
	end
	
	-- Clean up any previously created dynamic frames (named "DynamicReward_X")
	for _, child in pairs(self.RewardsFrame:GetChildren()) do
		if child.Name:match("^DynamicReward_%d+$") and child:IsA("Frame") then
			child:Destroy()
		end
	end
	
	-- Get rewards data
	local rewards = self.currentEnemyData.rewards or {}
	
	-- Create reward frames by cloning the template
	for i, reward in ipairs(rewards) do
		local rewardFrame = templateReward:Clone()
		rewardFrame.Name = "DynamicReward_" .. i
		rewardFrame.Parent = self.RewardsFrame
		rewardFrame.Visible = true
		
		-- Update the cloned reward frame with data
		self:UpdateRewardFrame(rewardFrame, reward)
	end
	
	
end

function BattlePrepHandler:UpdateRewardFrame(rewardFrame, reward)
	-- Update reward image
	local imgReward = rewardFrame:FindFirstChild("ImgReward")
	if imgReward and LOOTBOX_ASSETS[reward.rarity] then
		imgReward.Image = LOOTBOX_ASSETS[reward.rarity]
	end
	
	-- Update reward count
	local txtValue = rewardFrame:FindFirstChild("TxtValue")
	if txtValue then
		txtValue.Text = tostring(reward.count)
	end
end

function BattlePrepHandler:UpdateDifficultyDisplay()
	-- Ranked cosmetics (name/rating/thumb). We piggyback on this update cycle
	-- so Ranked info stays fresh whenever enemy data reloads.
	self:UpdateRankedInfoDisplay()

	-- Only show difficulty for boss mode
	local isBossMode = self.currentPartName and self.currentPartName:match("^BossMode")
	if not isBossMode then
		-- Hide difficulty label for non-boss modes
		if self.TxtDifficultyLabel then
			self.TxtDifficultyLabel.Visible = false
		end
		return
	end
	
	-- Check if we have difficulty data
	if not self.currentEnemyData or not self.currentEnemyData.difficulty then
		if self.TxtDifficultyLabel then
			self.TxtDifficultyLabel.Visible = false
		end
		return
	end
	
	if not self.TxtDifficultyLabel then
		return -- Difficulty label not found
	end
	
	-- Get difficulty string and convert to uppercase
	local difficulty = self.currentEnemyData.difficulty:lower()
	local difficultyUpper = difficulty:upper()
	
	-- Get difficulty color from Manifest
	local difficultyColor = nil
	if self.Utilities and self.Utilities.Manifest and self.Utilities.Manifest.DifficultyColors then
		difficultyColor = self.Utilities.Manifest.DifficultyColors[difficulty]
	end
	
	-- Set text to uppercase difficulty
	self.TxtDifficultyLabel.Text = difficultyUpper
	
	-- Set background color if available
	if difficultyColor then
		self.TxtDifficultyLabel.BackgroundColor3 = difficultyColor
	else
		-- Fallback: use white if Manifest not available
		warn("BattlePrepHandler: DifficultyColors not found in Manifest, using default color")
		self.TxtDifficultyLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	end
	
	-- Make sure it's visible
	self.TxtDifficultyLabel.Visible = true
	
	print("✅ BattlePrepHandler: Difficulty displayed -", difficultyUpper, "color:", difficultyColor)
end

function BattlePrepHandler:UpdateRivalsDeckDisplay()
	if not self.RivalsDeckFrame or not self.currentEnemyData then
		return
	end
	
	-- Find the template card frame (the first one)
	local templateCard = nil
	for _, child in pairs(self.RivalsDeckFrame:GetChildren()) do
		if child.Name == "Card" and child:IsA("Frame") then
			templateCard = child
			break
		end
	end
	
	if not templateCard then
		warn("BattlePrepHandler: No template card frame found in RivalsDeck")
		return
	end
	
	-- Hide ALL existing card frames (including templates)
	for _, child in pairs(self.RivalsDeckFrame:GetChildren()) do
		if child.Name == "Card" and child:IsA("Frame") then
			child.Visible = false
		end
	end
	
	-- Clean up any previously created dynamic frames (named "DynamicCard_X")
	for _, child in pairs(self.RivalsDeckFrame:GetChildren()) do
		if child.Name:match("^DynamicCard_%d+$") and child:IsA("Frame") then
			child:Destroy()
		end
	end
	
	-- Get enemy deck and levels
	local deck = self.currentEnemyData.deck or {}
	local levels = self.currentEnemyData.levels or {}
	
	-- Create card frames by cloning the template
	for i, cardId in ipairs(deck) do
		local cardFrame = templateCard:Clone()
		cardFrame.Name = "DynamicCard_" .. i
		cardFrame.Parent = self.RivalsDeckFrame
		cardFrame.Visible = true
		
		-- Get level for this card (use stored level or default to 1)
		local cardLevel = levels[i] or 1
		
		-- Update the cloned card frame with data
		self:UpdateCardFrame(cardFrame, cardId, cardLevel)
	end
	
	
end


function BattlePrepHandler:UpdateCardFrame(cardFrame, cardId, cardLevel)
	-- Get card data from catalog
	local cardData = self.Utilities.CardCatalog.GetCard(cardId)
	if not cardData then
		warn("BattlePrepHandler: Card not found in catalog:", cardId)
		return
	end
	
	-- Use provided level or default to 1
	cardLevel = cardLevel or 1
	
	-- Get Content frame first (optimization to avoid multiple lookups)
	local contentFrame = cardFrame:FindFirstChild("Content")
	if not contentFrame then
		warn("BattlePrepHandler: Content frame not found in Card frame")
		return
	end
	
	-- Update rarity colors
	local rarityKey = cardData.rarity:gsub("^%l", string.upper) -- Capitalize first letter
	local rarityColors = self.Utilities.Manifest and self.Utilities.Manifest.RarityColors or {}
	local rarityColor = rarityColors[rarityKey]
	
	if rarityColor then
		-- Set the main card frame background color
		cardFrame.BackgroundColor3 = rarityColor
	end
	
	-- Update card hero image
	local imgHero = contentFrame:FindFirstChild("ImgHero")
	if imgHero and self.Utilities.Manifest and self.Utilities.Manifest.CardImages then
		local imageId = self.Utilities.Manifest.CardImages[cardData.id]
		if imageId then
			imgHero.Image = imageId
		end
	end
	
	-- Update stats display (reuse DeckHandler logic)
	local stats = self.Utilities.CardStats.ComputeStats(cardId, cardLevel)
	
	-- Update level display (reuse levelFrame for rarity colors too)
	local levelFrame = contentFrame:FindFirstChild("Level")
	if levelFrame then
		local levelContent = levelFrame:FindFirstChild("Content")
		if levelContent then
			local txtValue = levelContent:FindFirstChild("TxtValue")
			if txtValue then
				txtValue.Text = tostring(cardLevel)
			end
		end
		
		-- Set rarity color for level frame and overlays
		if rarityColor then
			levelFrame.BackgroundColor3 = rarityColor
			
			-- Update UICornerOverlay1
			local overlay1 = levelFrame:FindFirstChild("UICornerOverlay1")
			if overlay1 then
				overlay1.BackgroundColor3 = rarityColor
			end
			
			-- Update UICornerOverlay2
			local overlay2 = levelFrame:FindFirstChild("UICornerOverlay2")
			if overlay2 then
				overlay2.BackgroundColor3 = rarityColor
			end
		end
	end
	
	-- Update attack
	local attackFrame = contentFrame:FindFirstChild("Attack")
	if attackFrame then
		attackFrame.Visible = true
		local valueFrame = attackFrame:FindFirstChild("Value")
		if valueFrame then
			local txtValue = valueFrame:FindFirstChild("TxtValue")
			if txtValue then
				txtValue.Text = tostring(stats.atk)
			end
		end
	end
	
	-- Update defense
	local defenseFrame = contentFrame:FindFirstChild("Defense")
	if defenseFrame then
		if stats.defence > 0 then
			defenseFrame.Visible = true
			local valueFrame = defenseFrame:FindFirstChild("Value")
			if valueFrame then
				local txtValue = valueFrame:FindFirstChild("TxtValue")
				if txtValue then
					txtValue.Text = tostring(stats.defence)
				end
			end
		else
			defenseFrame.Visible = false
		end
	end
	
	-- Update health
	local healthFrame = contentFrame:FindFirstChild("Health")
	if healthFrame then
		healthFrame.Visible = true
		local valueFrame = healthFrame:FindFirstChild("Value")
		if valueFrame then
			local txtValue = valueFrame:FindFirstChild("TxtValue")
			if txtValue then
				txtValue.Text = tostring(stats.hp)
			end
		end
	end
end

function BattlePrepHandler:GetRarityColor(rarity)
	local rarityColors = {
		uncommon = Color3.fromRGB(0, 255, 0),    -- Green
		rare = Color3.fromRGB(0, 0, 255),        -- Blue
		epic = Color3.fromRGB(128, 0, 128),      -- Purple
		legendary = Color3.fromRGB(255, 215, 0)  -- Gold
	}
	
	return rarityColors[rarity] or Color3.fromRGB(255, 255, 255) -- White default
end

function BattlePrepHandler:CloseWindow(showHUD)
	if self.isAnimating then return end
	self.isAnimating = true

	-- Clean up dynamically created frames
	self:CleanupDynamicFrames()

	-- Animate ViewportFrame sliding out
	self:AnimateViewportFrameOut(function()
		-- ViewportFrame animation completed
		-- Clean up cloned model
		if self.currentViewportModel then
			self.currentViewportModel:Destroy()
			self.currentViewportModel = nil
		end
	end)

	-- Note: NPC deck will be cleared server-side after battle completes
	-- If prep window is closed without starting battle, the deck will persist
	-- until next battle or server restart (this is acceptable for simplicity)

	-- Helper function to clear battle active flag (called after animation completes)
	local function clearBattleActiveFlag()
		local battleHandler = self.Controller and self.Controller:GetBattleHandler()
		if battleHandler then
			-- Check if a battle is actually running (currentBattle exists)
			local hasActiveBattle = battleHandler.currentBattle ~= nil
			
			-- Also check if battle frame is visible (indicates battle UI is showing)
			local battleFrameVisible = battleHandler.BattleFrame and battleHandler.BattleFrame.Visible or false
			
			-- Check if rewards window is open
			local rewardsHandler = self.Controller and self.Controller:GetRewardsHandler()
			local rewardsFrameVisible = false
			if rewardsHandler and rewardsHandler.RewardsFrame then
				rewardsFrameVisible = rewardsHandler.RewardsFrame.Visible or false
			end
			
			-- If no battle is running and no battle UI is showing, clear the flag
			-- (When a battle starts, currentBattle will be set, so we won't clear it then)
			if not hasActiveBattle and not battleFrameVisible and not rewardsFrameVisible then
				-- No active battle or battle UI, safe to clear flag
				battleHandler.isBattleActive = false
				-- Also ensure currentBattle is nil (defensive cleanup)
				if battleHandler.currentBattle ~= nil then
					battleHandler.currentBattle = nil
				end
			end
		end
	end
	
	-- Hide battle prep gui
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
			self.Utilities.TweenUI.FadeOut(self.StartBattleFrame, .3, function () 
				self.StartBattleFrame.Visible = false
				self.isAnimating = false
				-- Emit window closed event after animation completes
				EventBus:Emit("WindowClosed", "StartBattle")
				-- Clear battle active flag after animation completes
				clearBattleActiveFlag()
			end)
		end
		if self.Utilities.Blur then
			self.Utilities.Blur.Hide()
		end
	else
		-- Fallback: no animation
		self.StartBattleFrame.Visible = false
		self.isAnimating = false
		-- Emit window closed event immediately if no animation
		EventBus:Emit("WindowClosed", "StartBattle")
		-- Clear battle active flag immediately for fallback case
		clearBattleActiveFlag()
	end
	
	if self.TxtDifficultyLabel then
		self.TxtDifficultyLabel.Visible = false
	end
	
	-- Don't clear currentPartName if opened from button (keep it for next battle)
	-- Only clear if opened from proximity prompt
	-- Actually, we should keep it to remember the mode
	
	-- Show HUD panels
	if showHUD and self.UI then
		if self.UI.LeftPanel then
			self.UI.LeftPanel.Visible = true
			EventBus:Emit("HudShown", "LeftPanel")
		end
		if self.UI.BottomPanel then
			self.UI.BottomPanel.Visible = true
			EventBus:Emit("HudShown", "BottomPanel")
		end
		if self.UI.RightPanel then
			self.UI.RightPanel.Visible = true
			EventBus:Emit("HudShown", "RightPanel")
		end
	end
	
	-- Register with close button handler
	self:RegisterWithCloseButton(false)
	
	print("✅ BattlePrepHandler: Battle preparation window closed")
end

--// Public Methods
function BattlePrepHandler:IsInitialized()
	return self._initialized
end

-- Register with close button handler
function BattlePrepHandler:RegisterWithCloseButton(isOpen)
	local success, CloseButtonHandler = pcall(function()
		return require(game.ReplicatedStorage.ClientModules.CloseButtonHandler)
	end)
	
	if success and CloseButtonHandler then
		local instance = CloseButtonHandler.GetInstance()
		if instance and instance.isInitialized then
			if isOpen then
				instance:RegisterFrameOpen("BattlePrep")
			else
				instance:RegisterFrameClosed("BattlePrep")
			end
		end
	end
end

-- Setup match result callback
function BattlePrepHandler:SetupMatchResultCallback()
	-- Get the NetworkClient from the controller
	local networkClient = self.Controller:GetNetworkClient()
	if not networkClient then
		warn("BattlePrepHandler: NetworkClient not available for match callback")
		return
	end
	
	-- Set the callback to handle match results
	networkClient.setMatchResultCallback(function(response)
		self:OnBattleResponse(response)
	end)
	
	print("✅ BattlePrepHandler: Match result callback connected")
end

-- Setup START button functionality
function BattlePrepHandler:SetupStartButton()
	if not self.StartButton then
		warn("BattlePrepHandler: Cannot setup StartButton - button not found")
		return false
	end
	
	-- Validate button type (must be a GuiButton)
	if not self.StartButton:IsA("GuiButton") then
		warn("BattlePrepHandler: StartButton is not a GuiButton (it's a " .. self.StartButton.ClassName .. ")")
		return false
	end
	
	-- Ensure button is enabled
	self.StartButton.Active = true
	if self.StartButton:GetAttribute("Enabled") ~= false then
		-- Only set if attribute exists, otherwise assume it's enabled by default
	end
	
	-- Disconnect any existing connections to prevent duplicates
	-- (This handles the case where SetupStartButton is called multiple times)
	for _, connection in ipairs(self.Connections) do
		if connection and connection.Connected then
			-- Try to identify if this connection is for StartButton
			-- We'll just keep all connections and let cleanup handle it
		end
	end
	
	-- Connect click event with error handling
	local connection = self.StartButton.MouseButton1Click:Connect(function()
		-- Emit button click event
		EventBus:Emit("ButtonClicked", "StartBattle.Buttons.BtnStart")
		
		-- Verify NetworkClient is available before allowing click
		local networkClient = self.Controller and self.Controller:GetNetworkClient()
		if not networkClient then
			warn("BattlePrepHandler: Cannot start battle - NetworkClient not ready")
			return
		end
		
		-- Ensure we have required selection before starting battle.
		-- Ranked mode has no partName; it uses opponent selection ticket instead.
		if self.currentBattleMode ~= "Ranked" then
		if not self.currentPartName then
			self:EnsurePartNameForMode()
		end
		if not self.currentPartName then
			warn("BattlePrepHandler: Cannot start battle - no part name set")
			return
			end
		end
		
		-- Call the handler
		self:OnStartButtonClicked()
	end)
	
	table.insert(self.Connections, connection)
	print("✅ BattlePrepHandler: START button connected (Type: " .. self.StartButton.ClassName .. ", Active: " .. tostring(self.StartButton.Active) .. ")")
	return true
end

function BattlePrepHandler:OnStartButtonClicked()
	-- Prevent duplicate battle requests (concurrency guard)
	if self._isRequestingBattle then
		return
	end
	
	-- Disable button to prevent spam clicks
	if self.StartButton then
		self.StartButton.Active = false
	end
	
	-- Request battle from server
	self:RequestBattle()
end

function BattlePrepHandler:RequestBattle()
	-- Get the NetworkClient from the controller
	local networkClient = self.Controller and self.Controller:GetNetworkClient()
	if not networkClient then
		warn("BattlePrepHandler: NetworkClient not available - cannot start battle")
		-- Re-enable button on error
		if self.StartButton then
			self.StartButton.Active = true
		end
		return
	end
	
	-- Ranked mode uses opponent ticket, not partName
	local isRanked = (self.currentBattleMode == "Ranked")
	if not isRanked then
	-- Verify part name is set
	if not self.currentPartName then
		warn("BattlePrepHandler: No part name set - cannot determine battle mode")
		if self.StartButton then
			self.StartButton.Active = true
		end
		return
		end
	end
	
	-- Mark as requesting to prevent duplicate requests
	self._isRequestingBattle = true
	
	-- Determine battle mode from part name (for logging only, server determines this)
	local isNPCMode = (not isRanked) and self.currentPartName:match("^NPCMode")
	local isBossMode = (not isRanked) and self.currentPartName:match("^BossMode")
	
	-- Request battle with current enemy data
	-- NOTE: For NPC/Boss mode, don't send variant - the server doesn't use it and will reject "Balanced" in production
	-- Variant is only used for regular PvE battles, not NPC/Boss battles
	local requestData
	if isRanked then
		if not self._rankedOpponentUserId or not self._rankedTicket then
			warn("BattlePrepHandler: Ranked opponent not selected (missing ticket/userId)")
			self._isRequestingBattle = false
			if self.StartButton then
				self.StartButton.Active = true
			end
			return
		end
		requestData = {
			mode = "PvP",
			pvpMode = "Ranked",
			opponentUserId = self._rankedOpponentUserId,
			ticket = self._rankedTicket,
		}
	else
		requestData = {
		mode = "PvE",
		seed = nil, -- Let server generate seed
		partName = self.currentPartName -- Include part name for NPC/Boss detection
	}
	end
	
	-- Only add variant for regular PvE battles (not NPC/Boss and not Ranked PvP)
	if not isRanked and not isNPCMode and not isBossMode then
		requestData.variant = "Balanced"
	end
	
	print("✅ BattlePrepHandler: Requesting battle", isRanked and "(Ranked PvP)" or "", "partName:", tostring(self.currentPartName), "variant:", tostring(requestData.variant))
	
	-- Send battle request with error handling
	local success, errorMessage = pcall(function()
		networkClient.requestStartMatch(requestData)
	end)
	
	if not success then
		warn("BattlePrepHandler: Failed to send battle request:", tostring(errorMessage))
		self._isRequestingBattle = false
		-- Re-enable button on error
		if self.StartButton then
			self.StartButton.Active = true
		end
	end
end

-- Handle battle response from server
function BattlePrepHandler:OnBattleResponse(response)
	if not response.ok then
		warn("BattlePrepHandler: Battle request failed:", response.error and response.error.message or "Unknown error")
		-- Re-enable button (in case of error)
		if self.StartButton then
			self.StartButton.Active = true
		end
		-- Reset request flag
		self._isRequestingBattle = false
		return
	end
	
	-- Clear selected NPC after battle starts (will select new one next time)
	self.selectedNPCModelName = nil
	
	-- Hide battle prep frame
	self:CloseWindow(false)
	
	-- Get BattleHandler from controller
	local battleHandler = self.Controller:GetBattleHandler()
	
	if battleHandler then
		-- Prepare battle data for UI
		-- Use decks from server response to ensure they match the actual battle
		local battleData = {
			playerDeck = response.playerDeck,
			rivalDeck = response.rivalDeck,
			rivalDeckLevels = response.rivalDeckLevels, -- Include levels for rival deck
			battleLog = response.log,
			result = response.result,
			rewards = response.rewards -- Include battle rewards from server
		}
		
		-- Start battle UI
		battleHandler:StartBattle(battleData)
	else
		warn("BattlePrepHandler: BattleHandler not available")
	end

	-- Reset request flag
	self._isRequestingBattle = false
end

-- Clean up dynamically created frames and restore templates
function BattlePrepHandler:CleanupDynamicFrames()
	-- Clean up dynamically created reward frames
	if self.RewardsFrame then
		for _, child in pairs(self.RewardsFrame:GetChildren()) do
			if child.Name:match("^DynamicReward_%d+$") and child:IsA("Frame") then
				child:Destroy()
			end
		end
	end
	
	-- Clean up dynamically created card frames
	if self.RivalsDeckFrame then
		for _, child in pairs(self.RivalsDeckFrame:GetChildren()) do
			if child.Name:match("^DynamicCard_%d+$") and child:IsA("Frame") then
				child:Destroy()
			end
		end
	end
	
end

-- Close the battle prep frame (called by close button handler)
function BattlePrepHandler:CloseFrame()
	if self.StartBattleFrame and self.StartBattleFrame.Visible then
		self:CloseWindow(true)
	end
end

--// Cleanup
function BattlePrepHandler:Cleanup()
	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}

	self._initialized = false
	print("✅ BattlePrepHandler cleaned up")
end

return BattlePrepHandler
