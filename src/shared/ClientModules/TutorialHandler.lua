--[[
	TutorialHandler
	
	Manages tutorial display on the client side.
	Handles highlighting, arrows, and text popups.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Modules
local EventBus = require(ReplicatedStorage.Modules.EventBus)
local Logger = require(ReplicatedStorage.Modules.Logger)

-- Module
local TutorialHandler = {}

-- State
TutorialHandler.Connections = {}
TutorialHandler._initialized = false
TutorialHandler.currentStep = nil
TutorialHandler.currentStepIndex = -1  -- -1 means "not yet initialized"
TutorialHandler.isTutorialActive = false
TutorialHandler.tutorialGui = nil  -- Cloned ScreenGui from ReplicatedFirst
TutorialHandler.overlayObject = nil  -- Reference to Tutorial.Overlay
TutorialHandler.highlightTemplate = nil  -- Template for highlight from Overlay._Highlight
TutorialHandler.arrowObject = nil  -- Reference to Tutorial.Arrow (from template)
TutorialHandler.arrowLeft = nil  -- Reference to Tutorial.Arrow.ArrowLeft
TutorialHandler.arrowRight = nil  -- Reference to Tutorial.Arrow.ArrowRight
TutorialHandler.arrowTargetObject = nil  -- Object that arrow points to
TutorialHandler.arrowAnimationStarted = false  -- Flag to prevent position updates during animation
TutorialHandler.textObject = nil   -- Reference to Tutorial.Text
TutorialHandler.textLabel = nil    -- Reference to Tutorial.Text.TxtDescription
TutorialHandler.highlightObjects = {}  -- Array of cloned highlight objects
TutorialHandler.unifiedMasks = nil  -- Shared masks for all highlights
TutorialHandler.updateConnections = {}
TutorialHandler.tweenConnections = {}
TutorialHandler.proximityPromptsState = {}  -- Store original Enabled state of prompts
TutorialHandler.proximityPromptListener = nil  -- Listener for new prompts

-- Constants
local HIGHLIGHT_Z_INDEX = 1000
local ARROW_Z_INDEX = 1001
local TEXT_Z_INDEX = 1002
local HIGHLIGHT_COLOR = Color3.fromRGB(255, 255, 0)  -- Yellow highlight
local HIGHLIGHT_TRANSPARENCY = 0.7
local DARK_OVERLAY_COLOR = Color3.fromRGB(0, 0, 0)
local DARK_OVERLAY_TRANSPARENCY = 0.5

-- Path to tutorial template in ReplicatedFirst
local TUTORIAL_TEMPLATE_PATH = "ReplicatedFirst/Instances/Tutorial"

-- Initialization
function TutorialHandler:Init(controller)
	if self._initialized then
		return true
	end
	
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	
	-- Get NetworkClient
	local success, NetworkClient = pcall(function()
		local StarterPlayer = game:GetService("StarterPlayer")
		local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
		local Controllers = StarterPlayerScripts:WaitForChild("Controllers")
		return require(Controllers:WaitForChild("NetworkClient"))
	end)
	
	if success and NetworkClient then
		self.NetworkClient = NetworkClient
	else
		warn("TutorialHandler: Could not load NetworkClient")
		return false
	end
	
	-- Safe require of Utilities to avoid loading errors
	local success, utilities = pcall(function()
		return controller:GetModule("Utilities")
	end)
	
	if success then
		self.Utilities = utilities
	else
		warn("TutorialHandler: Could not load Utilities module: " .. tostring(utilities))
		self.Utilities = {
			TweenUI = { FadeIn = function() end, FadeOut = function() end }
		}
	end
	
	-- Initialize state
	self.Connections = {}  -- Temporary connections (cleaned up when hiding tutorial step)
	self.PersistentConnections = {}  -- Persistent connections (ProfileUpdated, etc.)
	self.profileUpdatedConnection = nil  -- Reference to ProfileUpdated connection to prevent duplicates
	self.currentStep = nil
	self.currentStepIndex = -1  -- -1 means "not yet initialized", ensures first update is always processed
	self.showingStepIndex = nil  -- Index of the step currently being shown (different from currentStepIndex which is last completed)
	self.lastShownStepIndex = nil  -- Last step index that was shown (for tracking forceStepOnGameLoad completion)
	self.isTutorialActive = false
	self.tutorialGui = nil  -- Cloned ScreenGui from ReplicatedFirst
	self.tutorialContainer = nil  -- Reference to Tutorial Frame (parent of Arrow/Overlay/Text)
	self.overlayObject = nil  -- Reference to Tutorial.Overlay
	self.highlightTemplate = nil  -- Template for highlight from Overlay._Highlight
	self.arrowObject = nil  -- Reference to Tutorial.Arrow (from template)
	self.arrowLeft = nil  -- Reference to Tutorial.Arrow.ArrowLeft
	self.arrowRight = nil  -- Reference to Tutorial.Arrow.ArrowRight
	self.arrowTargetObject = nil  -- Object that arrow points to
	self.arrowAnimationStarted = false  -- Flag to prevent position updates during animation
	self.textObject = nil   -- Reference to Tutorial.Text
	self.textLabel = nil    -- Reference to Tutorial.Text.TxtDescription
	self.highlightObjects = {}  -- Array of cloned highlight objects
	self.unifiedMasks = nil  -- Shared masks for all highlights
	self.updateConnections = {}
	self.tweenConnections = {}
	self.isTutorialTemporarilyHidden = false  -- Flag for temporary hiding
	self.windowVisibilityConnections = {}  -- Connections for window tracking
	self.fadeInTweens = {}  -- Track fade-in tweens to cancel duplicates
	self.conditionalTargets = {}  -- Store computed targets for "conditional" placeholders
	self.pathObjects = {}  -- Store path objects (Beam, Attachments, Parts) for cleanup
	self.beamTemplate = nil  -- Beam template from cloned Tutorial GUI (for cloning)
	self.isInitialLoad = false  -- Flag to track if this is the initial game load (for forceStepOnGameLoad)
	self.pendingStepIndex = nil  -- Step index we're waiting for (for event-based conditions)
	self.stepOverrides = {}  -- stepIndex -> { nextStep = number?, text = string? } - хранилище override значений без модификации конфига
	self.pendingNextStepIndex = nil  -- Step index scheduled to be shown (via task.spawn)
	self._uiObjectCache = {}  -- Cache for UI objects to avoid repeated FindUIObject calls
	
	-- Setup UI
	self:SetupUI()
	
	-- Setup tutorial template from ReplicatedFirst
	self:SetupTutorialTemplate()
	
	-- Setup profile updated handler
	self:SetupProfileUpdatedHandler()
	
	-- Setup window/button listeners
	self:SetupEventListeners()
	
	self._initialized = true
	return true
end

function TutorialHandler:SetupUI()
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Wait for GameUI
	local gameGui = playerGui:WaitForChild("GameUI", 10)
	if not gameGui then
		warn("TutorialHandler: GameUI not found in PlayerGui")
		return
	end
	
	self.UI = gameGui
end

function TutorialHandler:SetupTutorialTemplate()
	-- Check if tutorialGui already exists in PlayerGui
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Try to find existing Tutorial ScreenGui
	local existingTutorial = playerGui:FindFirstChild("Tutorial")
	if existingTutorial and existingTutorial:IsA("ScreenGui") then
		self.tutorialGui = existingTutorial
	else
		local ReplicatedFirst = game:GetService("ReplicatedFirst")
		
		local instancesFolder = ReplicatedFirst:WaitForChild("Instances", 10)
		if not instancesFolder then
			warn("TutorialHandler: ReplicatedFirst.Instances not found")
			return
		end
		
		local tutorialTemplate = instancesFolder:WaitForChild("Tutorial", 10)
		if not tutorialTemplate then
			warn("TutorialHandler: Tutorial template not found in ReplicatedFirst.Instances")
			return
		end
		
		self.tutorialGui = tutorialTemplate:Clone()
		self.tutorialGui.Name = "Tutorial"
		self.tutorialGui.ResetOnSpawn = false
		self.tutorialGui.Parent = playerGui
	end
	
	-- Always update references to tutorial UI elements (whether new or existing)
	-- Get reference to Tutorial Frame container (parent of Arrow/Overlay/Text)
	self.tutorialContainer = self.tutorialGui:FindFirstChild("Tutorial", true)
	if not self.tutorialContainer then
		warn("TutorialHandler: Tutorial Frame not found in tutorial template")
	end
	
	-- Get references to Arrow, Text, and Overlay objects
	self.arrowObject = self.tutorialGui:FindFirstChild("Arrow", true)
	self.textObject = self.tutorialGui:FindFirstChild("Text", true)
	self.overlayObject = self.tutorialGui:FindFirstChild("Overlay", true)
	
	if self.textObject then
		self.textLabel = self.textObject:FindFirstChild("TxtDescription", true)
	end
	
	-- Get highlight template from Overlay
	if self.overlayObject then
		self.highlightTemplate = self.overlayObject:FindFirstChild("_Highlight", true)
		if not self.highlightTemplate then
			warn("TutorialHandler: Highlight template '_Highlight' not found in Overlay")
		end
	else
		warn("TutorialHandler: Overlay not found in tutorial template")
	end
	
	-- Get ArrowLeft and ArrowRight from Arrow
	if self.arrowObject then
		self.arrowLeft = self.arrowObject:FindFirstChild("ArrowLeft", true)
		self.arrowRight = self.arrowObject:FindFirstChild("ArrowRight", true)
		if not self.arrowLeft or not self.arrowRight then
			warn("TutorialHandler: ArrowLeft or ArrowRight not found in Arrow")
		end
	end
	
	-- Get Beam template from cloned tutorial GUI (for cloning when needed)
	if self.tutorialGui then
		self.beamTemplate = self.tutorialGui:FindFirstChild("Beam", true)
		if not self.beamTemplate then
			warn("TutorialHandler: Beam template not found in cloned Tutorial GUI")
		end
	end
	
	-- Hide tutorial initially
	if self.tutorialGui then
		self.tutorialGui.Enabled = false
	end
	if self.tutorialContainer then
		self.tutorialContainer.Visible = false
	end
	if self.arrowObject then
		self.arrowObject.Visible = false
	end
	if self.arrowLeft then
		self.arrowLeft.Visible = false
	end
	if self.arrowRight then
		self.arrowRight.Visible = false
	end
	if self.textObject then
		self.textObject.Visible = false
	end
	
	-- Scale tutorial UI elements based on aspect ratio
	-- Wait a frame to ensure screen size is available
	task.spawn(function()
		task.wait() -- Wait for next frame to ensure screen size is available
		self:ScaleTutorialUI()
	end)
end

-- Scale tutorial UI elements based on device aspect ratio
function TutorialHandler:ScaleTutorialUI()
	-- Reference values
	local REFERENCE_WIDTH = 1920
	local REFERENCE_HEIGHT = 1080
	local REFERENCE_TEXT_SIZE = 32
	local REFERENCE_PADDING = 25
	
	-- Get current screen size from Camera ViewportSize
	local workspace = game:GetService("Workspace")
	local camera = workspace.CurrentCamera
	
	if not camera then
		-- Camera not available yet, try again next frame
		task.spawn(function()
			task.wait(0.1)
			self:ScaleTutorialUI()
		end)
		return
	end
	
	local screenSize = camera.ViewportSize
	if screenSize.X == 0 or screenSize.Y == 0 then
		-- Screen size not available yet, try again next frame
		task.spawn(function()
			task.wait(0.1)
			self:ScaleTutorialUI()
		end)
		return
	end
	
	-- Calculate aspect ratios
	local referenceAspectRatio = REFERENCE_WIDTH / REFERENCE_HEIGHT
	local currentAspectRatio = screenSize.X / screenSize.Y
	
	-- Calculate scale factor based on aspect ratio difference
	-- We scale based on the smaller dimension to maintain proportions
	local scaleFactor = math.min(screenSize.X / REFERENCE_WIDTH, screenSize.Y / REFERENCE_HEIGHT)
	
	-- Apply scaling to text size
	if self.textLabel then
		local scaledTextSize = math.floor(REFERENCE_TEXT_SIZE * scaleFactor)
		self.textLabel.TextSize = scaledTextSize
	end
	
	-- Find and scale UIPadding
	-- Path: Tutorial.Tutorial.Text.Text.UIPadding
	if self.textObject then
		local textInnerFrame = self.textObject:FindFirstChild("Text", true)
		if textInnerFrame then
			local uiPadding = textInnerFrame:FindFirstChild("UIPadding")
			if uiPadding then
				local scaledPadding = math.floor(REFERENCE_PADDING * scaleFactor)
				uiPadding.PaddingTop = UDim.new(0, scaledPadding)
				uiPadding.PaddingBottom = UDim.new(0, scaledPadding)
			else
				warn("TutorialHandler: UIPadding not found in Tutorial.Text.Text")
			end
		else
			warn("TutorialHandler: Inner Text frame not found in Tutorial.Text")
		end
	end
end

function TutorialHandler:SetupProfileUpdatedHandler()
	local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
	
	local connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
		-- Handle tutorial step from profile snapshot
		if payload.tutorialStep ~= nil then
			self:HandleTutorialProgress(payload.tutorialStep)
		end
	end)
	
	-- Store in persistent connections (not cleaned up when hiding tutorial step)
	table.insert(self.PersistentConnections, connection)
	
	-- Also request tutorial progress explicitly on initialization
	-- This ensures we get the tutorial state even if profile doesn't include it
	-- Reduced delay for faster initialization
	task.spawn(function()
		task.wait(0.1)  -- Minimal delay to ensure UI is ready
		if self._initialized then
			self:RequestTutorialProgress()
		end
	end)
end

function TutorialHandler:SetupEventListeners()
	local windowOpenedDisconnect = EventBus:On("WindowOpened", function(windowName)
		self:OnWindowOpened(windowName)
	end)
	table.insert(self.PersistentConnections, windowOpenedDisconnect)
	
	local windowClosedDisconnect = EventBus:On("WindowClosed", function(windowName)
		self:OnWindowClosed(windowName)
	end)
	table.insert(self.PersistentConnections, windowClosedDisconnect)
	
	local buttonClickedDisconnect = EventBus:On("ButtonClicked", function(buttonPath)
		self:OnButtonClicked(buttonPath)
	end)
	table.insert(self.PersistentConnections, buttonClickedDisconnect)
	
	local promptActivatedDisconnect = EventBus:On("PromptActivated", function(promptName)
		self:OnPromptActivated(promptName)
	end)
	table.insert(self.PersistentConnections, promptActivatedDisconnect)
	
	local hudShownDisconnect = EventBus:On("HudShown", function(panelName)
		self:OnHudShown(panelName)
	end)
	table.insert(self.PersistentConnections, hudShownDisconnect)
end

-- Get next step index with override support (doesn't modify original config)
function TutorialHandler:GetNextStepIndex(currentStep)
	local TutorialConfig = require(game.ReplicatedStorage.Modules.Tutorial.TutorialConfig)
	
	-- Проверить override значения (приоритет над конфигом)
	if self.stepOverrides[currentStep] and self.stepOverrides[currentStep].nextStep then
		return self.stepOverrides[currentStep].nextStep
	end
	
	-- Использовать стандартную логику из конфига
	return TutorialConfig.GetNextStepIndex(currentStep)
end

-- Helper: Resolve conditional target
function TutorialHandler:ResolveConditionalTarget(target, step)
	if target ~= "conditional" then
		return target
	end
	
	if step and step.path and step.startCondition and step.startCondition.type == "prompt_click" then
		return self:ExtractNPCNameFromPath(step.path)
	end
	
	return self.conditionalTargets and self.conditionalTargets.complete
end

-- Helper: Extract NPC name from path (e.g., "Workspace.Noob" -> "Noob")
function TutorialHandler:ExtractNPCNameFromPath(path)
	local pathParts = {}
	for part in string.gmatch(path, "([^%.]+)") do
		table.insert(pathParts, part)
	end
	return #pathParts > 0 and pathParts[#pathParts] or nil
end

-- Helper: Check if event matches step start condition
function TutorialHandler:CheckStartConditionMatch(step, eventType, eventValue)
	if not step or not step.startCondition or step.startCondition.type ~= eventType then
		return false
	end
	
	local target = step.startCondition.target
	target = self:ResolveConditionalTarget(target, step)
	
	if eventType == "window_open" then
		return target == eventValue
	elseif eventType == "hud_show" then
		return target == eventValue
	elseif eventType == "button_click" then
		return target and (target == eventValue or string.find(eventValue, target))
	elseif eventType == "prompt_click" then
		return target and (target == eventValue or string.find(eventValue, target))
	end
	
	return false
end

-- Helper: Check if event matches step complete condition
function TutorialHandler:CheckCompleteConditionMatch(condition, eventType, eventValue)
	if not condition or condition.type ~= eventType then
		return false
	end
	
	-- Special handling for prompt_click with promptTargets array
	if eventType == "prompt_click" and self.currentStep and self.currentStep.promptTargets then
		-- Check if eventValue matches any of the promptTargets
		for _, promptTarget in ipairs(self.currentStep.promptTargets) do
			if promptTarget == eventValue or string.find(eventValue, promptTarget) then
				return true
			end
		end
		return false
	end
	
	local target = condition.target
	if target == "conditional" then
		if eventType == "prompt_click" and self.currentStep and self.currentStep.path then
			target = self:ExtractNPCNameFromPath(self.currentStep.path)
		else
			target = self.conditionalTargets and self.conditionalTargets.complete
		end
	end
	
	if not target then
		return false
	end
	
	if eventType == "window_open" or eventType == "window_close" then
		return target == eventValue
	elseif eventType == "button_click" then
		return target == eventValue or string.find(eventValue, target)
	elseif eventType == "prompt_click" then
		return target == eventValue or string.find(eventValue, target)
	end
	
	return false
end

-- Helper: Handle event for next step (when tutorial is not active)
function TutorialHandler:HandleEventForNextStep(eventType, eventValue)
	local TutorialConfig = require(game.ReplicatedStorage.Modules.Tutorial.TutorialConfig)
	local nextStepIndex = self.pendingStepIndex or self:GetNextStepIndex(self.currentStepIndex)
	if not nextStepIndex then
		return false
	end
	
	local step = TutorialConfig.GetStep(nextStepIndex)
	if not step or not self:CheckStartConditionMatch(step, eventType, eventValue) then
		return false
	end
	
	self.pendingStepIndex = nil
	self:ProcessTutorialStep(nextStepIndex, false)
	return true
end

function TutorialHandler:OnWindowOpened(windowName)
	if not self._initialized then
		return
	end
	
	-- Clear UI object cache when window opens (window might have been created/destroyed)
	-- This ensures fresh lookups for windows that might not have existed before
	self._uiObjectCache = {}
	
	if not self.isTutorialActive then
		self:HandleEventForNextStep("window_open", windowName)
		return
	end
	
	if self.currentStep and self.currentStep.completeCondition then
		if self:CheckCompleteConditionMatch(self.currentStep.completeCondition, "window_open", windowName) then
			self:CompleteCurrentStep()
		end
	end
end

function TutorialHandler:OnWindowClosed(windowName)
	if not self._initialized then
		return
	end

	-- If there is a pending hud_show step, window close might have unblocked it
	if self.pendingStepIndex then
		local TutorialConfig = require(game.ReplicatedStorage.Modules.Tutorial.TutorialConfig)
		local pendingIndex = self.pendingStepIndex
		local pendingStep = TutorialConfig.GetStep(pendingIndex)

		if pendingStep and pendingStep.startCondition and pendingStep.startCondition.type == "hud_show" then
			if self:CheckStartCondition(pendingStep) then
				Logger.debug("[TutorialHandler] Window %s closed, pending hud_show step %d condition met, processing",
					tostring(windowName), pendingIndex)
				self.pendingStepIndex = nil
				self:ProcessTutorialStep(pendingIndex, false)
			else
				Logger.debug("[TutorialHandler] Window %s closed, pending hud_show step %d still blocked",
					tostring(windowName), pendingIndex)
			end
		end
	end

	if not self.isTutorialActive then
		return
	end
	
	if self.currentStep and self.currentStep.completeCondition then
		if self:CheckCompleteConditionMatch(self.currentStep.completeCondition, "window_close", windowName) then
			self:CompleteCurrentStep()
		end
	end
end

function TutorialHandler:OnButtonClicked(buttonPath)
	if not self._initialized then
		return
	end
	
	if not self.isTutorialActive then
		self:HandleEventForNextStep("button_click", buttonPath)
		return
	end
	
	if self.currentStep and self.currentStep.completeCondition then
		if self:CheckCompleteConditionMatch(self.currentStep.completeCondition, "button_click", buttonPath) then
			self:CompleteCurrentStep()
		end
	end
end

function TutorialHandler:OnPromptActivated(promptName)
	if not self._initialized then
		return
	end
	
	if not self.isTutorialActive then
		self:HandleEventForNextStep("prompt_click", promptName)
		return
	end
	
	if self.currentStep and self.currentStep.completeCondition then
		if self:CheckCompleteConditionMatch(self.currentStep.completeCondition, "prompt_click", promptName) then
			self:CompleteCurrentStep()
		end
	end
end

function TutorialHandler:OnHudShown(panelName)
	if not self._initialized then
		return
	end
	
	-- Clear UI object cache when HUD panel is shown (panel might have been created/destroyed)
	self._uiObjectCache = {}
	
	if not self.isTutorialActive then
		self:HandleEventForNextStep("hud_show", panelName)
		return
	end
	
	-- HUD panels don't have complete conditions, they're only for start conditions
end

function TutorialHandler:RequestTutorialProgress()
	if not self.NetworkClient or not self.NetworkClient.requestTutorialProgress then
		warn("TutorialHandler: NetworkClient.requestTutorialProgress not available")
		return
	end
	
	self.NetworkClient.requestTutorialProgress()
end

function TutorialHandler:HandleTutorialProgress(tutorialStep)
	local TutorialConfig = require(game.ReplicatedStorage.Modules.Tutorial.TutorialConfig)
	
	local newStep = tutorialStep or 0
	Logger.debug("[TutorialHandler] HandleTutorialProgress: received step %d, currentStepIndex = %d, isInitialLoad = %s", 
		newStep, self.currentStepIndex, tostring(self.isInitialLoad))
	
	if newStep == 0 and self.currentStepIndex > 0 then
		-- Tutorial was completed or reset (had progress, now reset to 0)
		self:HideTutorialStep()
		self.currentStepIndex = 0  -- Set to 0, not -1, to indicate tutorial is complete
		self.isInitialLoad = false
		-- Ensure ProximityPrompts are restored when tutorial is completed
		self:RestoreAllProximityPrompts()
		Logger.debug("[TutorialHandler] Tutorial completed or reset to 0")
		return
	end
	
	-- If newStep == 0 and currentStepIndex == -1, this is a new player starting tutorial
	-- Continue processing to show first step
	
	-- Ignore outdated ProfileUpdated that would rollback progress
	-- This can happen when ProfileUpdated comes from other actions with cached profile data
	-- Note: With new server logic, altNextStep rollbacks set tutorialStep = altNextStep - 1,
	-- so we might receive a step that's lower than currentStepIndex
	-- Check if this might be a valid altNextStep rollback
	if self.currentStepIndex ~= -1 and newStep < self.currentStepIndex then
		local isPossibleAltNextStep = false
		-- Check if any step between newStep+1 and currentStepIndex has altNextStep that would result in newStep+1
		-- Example: currentStepIndex=13, newStep=10, check if step 13 has altNextStep=11 (which would set tutorialStep=10)
		for stepIndex = newStep + 1, self.currentStepIndex do
			local stepConfig = TutorialConfig.GetStep(stepIndex)
			if stepConfig and stepConfig.altNextStep then
				-- altNextStep indicates which step to show, server sets tutorialStep = altNextStep - 1
				-- So if altNextStep - 1 == newStep, this is a valid rollback
				if stepConfig.altNextStep - 1 == newStep then
					isPossibleAltNextStep = true
					Logger.debug("[TutorialHandler] Valid altNextStep rollback detected: step %d has altNextStep = %d, server set tutorialStep = %d", 
						stepIndex, stepConfig.altNextStep, newStep)
					break
				end
			end
		end
		
		if not isPossibleAltNextStep then
			-- This is not a valid altNextStep rollback - likely outdated data
			if self.currentStepIndex - newStep > 2 then
				Logger.debug("[TutorialHandler] Ignoring outdated ProfileUpdated: received step %d but currentStepIndex is %d (likely from unrelated action with stale data)", 
					newStep, self.currentStepIndex)
				return  -- Don't process outdated step
			end
			-- Small rollback (1-2 steps) - allow it
			Logger.debug("[TutorialHandler] Allowing small rollback from step %d to %d", 
				self.currentStepIndex, newStep)
		end
	end
	
	local wasUninitialized = (self.currentStepIndex == -1)
	
	-- Check if we already processed this step via optimistic update
	local wasOptimistic = (self.currentStepIndex ~= -1 and self.currentStepIndex >= newStep)
	
	if wasOptimistic then
		if self.currentStepIndex > newStep then
			-- We're ahead of server via optimistic updates
			-- Check if this is a valid altNextStep rollback
			local rollbackTargetStep = newStep + 1  -- The step we should show after rollback (e.g., 11)
			local isAltNextStepRollback = false
			
			-- First, check steps in the normal range
			for stepIndex = newStep + 1, math.max(self.currentStepIndex, rollbackTargetStep + 1) do
				local stepConfig = TutorialConfig.GetStep(stepIndex)
				if stepConfig and stepConfig.altNextStep then
					if stepConfig.altNextStep - 1 == newStep then
						isAltNextStepRollback = true
						Logger.debug("[TutorialHandler] Valid altNextStep rollback: step %d has altNextStep = %d, server set tutorialStep = %d", 
							stepIndex, stepConfig.altNextStep, newStep)
						break
					end
				end
			end
			
			-- If not found, check if any step has altNextStep that matches rollbackTargetStep
			-- This catches cases where we just completed a step (e.g., 13) that's not yet in currentStepIndex
			if not isAltNextStepRollback then
				for stepIndex = 1, TutorialConfig.GetStepCount() do
					local stepConfig = TutorialConfig.GetStep(stepIndex)
					if stepConfig and stepConfig.altNextStep == rollbackTargetStep then
						-- This step has altNextStep that matches the rollback target
						-- Check if altNextStep - 1 == newStep
						if stepConfig.altNextStep - 1 == newStep then
							isAltNextStepRollback = true
							Logger.debug("[TutorialHandler] Valid altNextStep rollback: step %d has altNextStep = %d, server set tutorialStep = %d (found via full search)", 
								stepIndex, stepConfig.altNextStep, newStep)
							break
						end
					end
				end
			end
			
			if isAltNextStepRollback then
				-- This is a valid altNextStep rollback from server
				-- Server is the source of truth, so we must accept the rollback
				-- even if we optimistically progressed further
				Logger.debug("[TutorialHandler] Server confirmed altNextStep rollback to step %d (was at %d via optimistic update), syncing and showing next step", 
					newStep, self.currentStepIndex)
				self.currentStepIndex = newStep
				-- Continue processing to show the next step (altNextStep)
			else
				-- Normal case: sync to server state but skip redundant processing
				Logger.debug("[TutorialHandler] Server confirmed step %d (already at %d via optimistic update), syncing to server state", 
					newStep, self.currentStepIndex)
				self.currentStepIndex = newStep
				return
			end
		elseif self.currentStepIndex == newStep then
			-- Server confirmed what we already optimistically updated
			
			-- IMPORTANT: For step 13, clear stepOverrides if server confirmed victory (newStep == 13)
			-- If server returned step 13, it means victory (useAltNextStep = false)
			-- If server returned step 10, it means loss (useAltNextStep = true, rollback to show step 11)
			if newStep == 13 and self.stepOverrides[13] then
				Logger.debug("[TutorialHandler] Server confirmed step 13 (victory), clearing stepOverrides[13]")
				self.stepOverrides[13] = nil
			end
			
			local nextStepIndex = self:GetNextStepIndex(self.currentStepIndex)
			-- Only skip if step is actually showing (not just pending)
			-- pendingNextStepIndex alone is not enough - step might not have been shown yet
			if self.showingStepIndex == nextStepIndex and self.isTutorialActive then
				Logger.debug("[TutorialHandler] Server confirmed step %d (already processed via optimistic update), next step %d is already showing, skipping", 
					newStep, nextStepIndex)
				return
			end
			-- Continue processing to ensure next step is shown
			-- This handles cases where task.spawn hasn't executed yet, step wasn't shown, or pendingNextStepIndex was set but step failed to show
		end
	else
		-- Normal case: server has a new step for us
		self.currentStepIndex = newStep
	end
	
	-- Reset lastShownStepIndex if we've progressed past or caught up to the shown step
	-- This prevents the forceStepOnGameLoad logic from interfering with normal progression
	if self.lastShownStepIndex and self.currentStepIndex >= self.lastShownStepIndex then
		self.lastShownStepIndex = nil
	end
	
	if wasUninitialized then
		self.isInitialLoad = true
		Logger.debug("[TutorialHandler] First load detected, setting isInitialLoad = true for step %d", newStep)
	end
	
	if TutorialConfig.IsComplete(self.currentStepIndex) then
		self:HideTutorialStep()
		self.isInitialLoad = false
		-- Ensure ProximityPrompts are restored when tutorial is completed
		self:RestoreAllProximityPrompts()
		Logger.debug("[TutorialHandler] Tutorial is complete at step %d", self.currentStepIndex)
		return
	end
	
	local nextStepIndex = self:GetNextStepIndex(self.currentStepIndex)
	
	if self.lastShownStepIndex and self.lastShownStepIndex < self.currentStepIndex then
		Logger.debug("[TutorialHandler] Just completed step %d shown via forceStepOnGameLoad, showing step %d instead of next step %d", 
			self.lastShownStepIndex, self.currentStepIndex, nextStepIndex)
		nextStepIndex = self.currentStepIndex
		self.lastShownStepIndex = nil  -- Clear after using
	end
	
	if not nextStepIndex then
		self:HideTutorialStep()
		self.isInitialLoad = false
		-- Ensure ProximityPrompts are restored when tutorial is completed
		self:RestoreAllProximityPrompts()
		Logger.debug("[TutorialHandler] No next step after %d, tutorial complete", self.currentStepIndex)
		return
	end
	
	Logger.debug("[TutorialHandler] Current step: %d, Next step: %d, showingStepIndex: %s", 
		self.currentStepIndex, nextStepIndex, tostring(self.showingStepIndex))
	
	if self.showingStepIndex == nextStepIndex and self.isTutorialActive then
		Logger.debug("[TutorialHandler] Already showing step %d, skipping", nextStepIndex)
		return
	end
	
	task.spawn(function()
		self:WaitForLoadingScreenToFinish()
		if self.isTutorialActive and self.showingStepIndex == nextStepIndex then
			return
		end
		
		local wasInitialLoad = self.isInitialLoad
		
		-- Check forceStepOnGameLoad only on first load (wasUninitialized)
		-- Check it for the NEXT step that should be shown, not the completed one
		-- Don't modify currentStepIndex to preserve server progress
		if wasInitialLoad and wasUninitialized and self.currentStepIndex > 0 then
			-- Check forceStepOnGameLoad for NEXT step, not current (completed) step
			local nextStepConfig = TutorialConfig.GetStep(nextStepIndex)
			if nextStepConfig and nextStepConfig.forceStepOnGameLoad then
				local forceStepIndex = nextStepConfig.forceStepOnGameLoad
				if forceStepIndex and forceStepIndex >= 1 and forceStepIndex <= TutorialConfig.GetStepCount() then
					-- Check startCondition of the target step before showing it
					local forceStepConfig = TutorialConfig.GetStep(forceStepIndex)
					if forceStepConfig then
						local forceStepConditionMet = self:CheckStartCondition(forceStepConfig)
						
						-- If condition not met and step has altNextStep, use altNextStep instead
						if not forceStepConditionMet and forceStepConfig.altNextStep then
							local altNextStep = forceStepConfig.altNextStep
							Logger.debug("[TutorialHandler] forceStepOnGameLoad: step %d condition not met, using altNextStep %d instead", 
								forceStepIndex, altNextStep)
							
							-- Send request to server to complete step 13 (which has altNextStep = 11)
							-- Server will set tutorialStep = 10 (altNextStep - 1)
							-- We need to find which step has this altNextStep
							local sourceStepIndex = nil
							for i = 1, TutorialConfig.GetStepCount() do
								local stepConfig = TutorialConfig.GetStep(i)
								if stepConfig and stepConfig.altNextStep == altNextStep then
									sourceStepIndex = i
									break
								end
							end
							
							if sourceStepIndex and self.NetworkClient and self.NetworkClient.requestCompleteTutorialStep then
								Logger.debug("[TutorialHandler] Sending requestCompleteTutorialStep(%d, useAltNextStep=true) to server to trigger altNextStep rollback", 
									sourceStepIndex)
								self.NetworkClient.requestCompleteTutorialStep(sourceStepIndex, true)
							end
							
							-- Wait for server to update tutorialStep before showing altNextStep
							-- HandleTutorialProgress will be called when server responds
							self.isInitialLoad = false
							return
						end
						
						-- If condition met, show the target step
						if forceStepConditionMet then
							Logger.debug("[TutorialHandler] forceStepOnGameLoad triggered: next step %d has forceStepOnGameLoad = %d, showing step %d locally", 
								nextStepIndex, forceStepIndex, forceStepIndex)
							self:ShowTutorialStep(forceStepIndex, true)
							self.isInitialLoad = false
							return
						end
						
						-- Condition not met and no altNextStep - wait for condition
						Logger.debug("[TutorialHandler] forceStepOnGameLoad: step %d condition not met, waiting for condition", forceStepIndex)
						self:WaitForConditionalCondition(forceStepConfig, forceStepIndex)
						self.isInitialLoad = false
						return
					end
				end
			end
		end
		
		if self.isInitialLoad then
			self.isInitialLoad = false
		end
		
		Logger.debug("[TutorialHandler] Processing next step %d, wasInitialLoad = %s", 
			nextStepIndex, tostring(wasInitialLoad))
		self:ProcessTutorialStep(nextStepIndex, wasInitialLoad, false)
	end)
end

function TutorialHandler:WaitForLoadingScreenToFinish()
	local player = Players.LocalPlayer
	if not player then
		return
	end
	
	local playerGui = player:WaitForChild("PlayerGui", 10)
	if not playerGui then
		return
	end
	
	local loadingScreen = playerGui:FindFirstChild("LoadingScreen")
	if loadingScreen then
		if loadingScreen.Enabled then
			local changedSignal = loadingScreen:GetPropertyChangedSignal("Enabled")
			while loadingScreen.Enabled do
				changedSignal:Wait()
			end
			task.wait(0.1)  -- Reduced delay after loading screen closes
		end
	else
		task.wait(0.2)  -- Reduced delay when no loading screen
	end
end

function TutorialHandler:ProcessTutorialStep(nextStepIndex, isInitialLoad, isRollback)
	local TutorialConfig = require(game.ReplicatedStorage.Modules.Tutorial.TutorialConfig)
	
	Logger.debug("[TutorialHandler] ProcessTutorialStep: nextStepIndex = %d, isInitialLoad = %s, currentStepIndex = %d", 
		nextStepIndex, tostring(isInitialLoad), self.currentStepIndex)
	
	local step = TutorialConfig.GetStep(nextStepIndex)
	if not step then
		warn(string.format("[TutorialHandler] Step %d not found", nextStepIndex))
		return
	end
	
	local startConditionMet = self:CheckStartCondition(step)
	Logger.debug("[TutorialHandler] Step %d startCondition met: %s", nextStepIndex, tostring(startConditionMet))
	
	if not startConditionMet then
		-- Check if completeCondition has force = true
		-- If so, automatically complete the step even if startCondition is not met
		if step.completeCondition and step.completeCondition.force == true then
			Logger.debug("[TutorialHandler] Step %d has force = true, auto-completing step (optimistic update)", nextStepIndex)
			
			-- Optimistic update: update local state immediately without waiting for server
			-- This provides instant visual feedback for consecutive force steps
			local wasOptimisticUpdate = false
			if self.currentStepIndex < nextStepIndex then
				-- Update local state optimistically
				local oldStepIndex = self.currentStepIndex
				self.currentStepIndex = nextStepIndex
				wasOptimisticUpdate = true
				Logger.debug("[TutorialHandler] Optimistic update: currentStepIndex %d -> %d", oldStepIndex, nextStepIndex)
			end
			
			-- Send request to server asynchronously (doesn't block)
			if self.NetworkClient and self.NetworkClient.requestCompleteTutorialStep then
				self.NetworkClient.requestCompleteTutorialStep(nextStepIndex)
			end
			
			-- Process next step immediately if it also has force = true
			-- This creates instant cascade for consecutive force steps
			local nextNextStepIndex = self:GetNextStepIndex(nextStepIndex)
			if nextNextStepIndex then
				local nextStep = TutorialConfig.GetStep(nextNextStepIndex)
				if nextStep then
					local nextStartConditionMet = self:CheckStartCondition(nextStep)
					if not nextStartConditionMet and nextStep.completeCondition and nextStep.completeCondition.force == true then
						Logger.debug("[TutorialHandler] Cascading: next step %d also has force = true, processing immediately", nextNextStepIndex)
						-- Process immediately without waiting for server response
						-- Use task.spawn with task.wait to ensure UI is ready before processing next step
						task.spawn(function()
							task.wait()  -- Wait one frame to ensure previous step is fully processed
							self:ProcessTutorialStep(nextNextStepIndex, false)
						end)
						return
					end
				end
			end
			
			-- If next step doesn't have force, wait for server confirmation
			-- But if we did optimistic update, we need to trigger processing
			if wasOptimisticUpdate then
				-- Wait for server to confirm, then process next step normally
				-- The HandleTutorialProgress will handle it when server responds
				return
			end
			
			return
		end
		
		-- forceStepOnGameLoad only works on initial game load, not during normal step transitions
		if step.forceStepOnGameLoad and isInitialLoad then
			local forceStepIndex = step.forceStepOnGameLoad
			if forceStepIndex and forceStepIndex >= 1 and forceStepIndex <= TutorialConfig.GetStepCount() then
				-- Check startCondition of the target step before showing it
				local forceStepConfig = TutorialConfig.GetStep(forceStepIndex)
				if forceStepConfig then
					local forceStepConditionMet = self:CheckStartCondition(forceStepConfig)
					
						-- If condition not met and step has altNextStep, use altNextStep instead
						if not forceStepConditionMet and forceStepConfig.altNextStep then
							local altNextStep = forceStepConfig.altNextStep
							Logger.debug("[TutorialHandler] forceStepOnGameLoad: step %d condition not met, using altNextStep %d instead", 
								forceStepIndex, altNextStep)
							
							-- Send request to server to complete step 13 (which has altNextStep = 11)
							-- Server will set tutorialStep = 10 (altNextStep - 1)
							local sourceStepIndex = nil
							for i = 1, TutorialConfig.GetStepCount() do
								local stepConfig = TutorialConfig.GetStep(i)
								if stepConfig and stepConfig.altNextStep == altNextStep then
									sourceStepIndex = i
									break
								end
							end
							
							if sourceStepIndex and self.NetworkClient and self.NetworkClient.requestCompleteTutorialStep then
								Logger.debug("[TutorialHandler] Sending requestCompleteTutorialStep(%d, useAltNextStep=true) to server to trigger altNextStep rollback", 
									sourceStepIndex)
								self.NetworkClient.requestCompleteTutorialStep(sourceStepIndex, true)
							end
							
							-- Wait for server to update tutorialStep before showing altNextStep
							return
						end
					
					-- If condition met, show the target step
					if forceStepConditionMet then
						Logger.debug("[TutorialHandler] forceStepOnGameLoad triggered: step %d has forceStepOnGameLoad = %d, showing step %d locally", 
							nextStepIndex, forceStepIndex, forceStepIndex)
						self:ShowTutorialStep(forceStepIndex, true)
						return
					end
					
					-- Condition not met and no altNextStep - wait for condition
					Logger.debug("[TutorialHandler] forceStepOnGameLoad: step %d condition not met, waiting for condition", forceStepIndex)
					self:WaitForConditionalCondition(forceStepConfig, forceStepIndex)
					return
				end
			else
				warn(string.format("[TutorialHandler] Invalid forceStepOnGameLoad value: %s for step %d", tostring(forceStepIndex), nextStepIndex))
			end
		else
			if step.forceStepOnGameLoad then
				Logger.debug("[TutorialHandler] Step %d has forceStepOnGameLoad = %d but isInitialLoad = %s, ignoring", 
					nextStepIndex, step.forceStepOnGameLoad, tostring(isInitialLoad))
			end
		end
		
		-- Normal handling: wait for condition
		Logger.debug("[TutorialHandler] Step %d startCondition not met, waiting for condition (type: %s)", 
			nextStepIndex, step.startCondition and step.startCondition.type or "unknown")
		if step.startCondition.type == "conditional" then
			self:WaitForConditionalCondition(step, nextStepIndex)
		elseif step.startCondition.type == "hud_show" then
			-- For hud_show, also listen to visibility changes, not just HudShown event
			-- This handles cases where panel is already visible but event didn't fire
			self.pendingStepIndex = nextStepIndex
			Logger.debug("[TutorialHandler] Step %d pending, waiting for hud_show event or visibility change", nextStepIndex)
			
			-- Also set up property listener for immediate visibility check
			task.spawn(function()
				local panel = self:GetCachedUIObject(step.startCondition.target)
				if panel then
					-- Check immediately if already visible
					if panel.Visible then
						-- Before processing, re-check startCondition (may still be blocked by an open window)
						if self:CheckStartCondition(step) then
							Logger.debug("[TutorialHandler] Step %d: panel %s is already visible and condition met, processing immediately", 
								nextStepIndex, step.startCondition.target)
							self.pendingStepIndex = nil
							self:ProcessTutorialStep(nextStepIndex, false)
						else
							Logger.debug("[TutorialHandler] Step %d: panel %s visible, but startCondition still not met (blocking window?)", 
								nextStepIndex, step.startCondition.target)
						end
						return
					end
					
					-- Listen for visibility changes
					local connection = panel:GetPropertyChangedSignal("Visible"):Connect(function()
						if panel.Visible and self.pendingStepIndex == nextStepIndex then
							-- Re-check start condition to avoid recursive processing while blocking windows are open
							if self:CheckStartCondition(step) then
								Logger.debug("[TutorialHandler] Step %d: panel %s became visible and condition met, processing", 
									nextStepIndex, step.startCondition.target)
								self.pendingStepIndex = nil
								if connection then
									connection:Disconnect()
								end
								self:ProcessTutorialStep(nextStepIndex, false)
							else
								Logger.debug("[TutorialHandler] Step %d: panel %s became visible, but startCondition still not met", 
									nextStepIndex, step.startCondition.target)
							end
						end
					end)
					if connection then
						table.insert(self.Connections, connection)
					end
				else
					-- Panel not found, wait for it to appear via HudShown event
					Logger.debug("[TutorialHandler] Step %d: panel %s not found, waiting for HudShown event", 
						nextStepIndex, step.startCondition.target)
				end
			end)
		elseif step.startCondition.type == "window_open" then
			-- For window_open, also check if window is already open
			-- This handles cases where window opened before tutorial started listening
			self.pendingStepIndex = nextStepIndex
			Logger.debug("[TutorialHandler] Step %d pending, waiting for window_open event or window state change", nextStepIndex)
			
			-- Also set up immediate check and property listener
			task.spawn(function()
				local window = self:GetCachedUIObject(step.startCondition.target)
				if window then
					-- Check immediately if already open
					local isOpen = false
					if window:IsA("ScreenGui") then
						isOpen = window.Enabled == true
					else
						isOpen = window.Visible == true
					end
					
					if isOpen then
						Logger.debug("[TutorialHandler] Step %d: window %s is already open, processing immediately", 
							nextStepIndex, step.startCondition.target)
						self.pendingStepIndex = nil
						self:ProcessTutorialStep(nextStepIndex, false)
						return
					end
					
					-- Listen for window state changes
					local propertyName = window:IsA("ScreenGui") and "Enabled" or "Visible"
					local connection = window:GetPropertyChangedSignal(propertyName):Connect(function()
						local isOpenNow = false
						if window:IsA("ScreenGui") then
							isOpenNow = window.Enabled == true
						else
							isOpenNow = window.Visible == true
						end
						
						if isOpenNow and self.pendingStepIndex == nextStepIndex then
							Logger.debug("[TutorialHandler] Step %d: window %s became open, processing", 
								nextStepIndex, step.startCondition.target)
							self.pendingStepIndex = nil
							if connection then
								connection:Disconnect()
							end
							self:ProcessTutorialStep(nextStepIndex, false)
						end
					end)
					if connection then
						table.insert(self.Connections, connection)
					end
				else
					-- Window not found, wait for it to appear via WindowOpened event
					Logger.debug("[TutorialHandler] Step %d: window %s not found, waiting for WindowOpened event", 
						nextStepIndex, step.startCondition.target)
				end
			end)
		else
			self.pendingStepIndex = nextStepIndex
			Logger.debug("[TutorialHandler] Step %d pending, waiting for event", nextStepIndex)
		end
		return
	end
	
	Logger.debug("[TutorialHandler] Step %d startCondition met, showing step", nextStepIndex)
	-- Pass forceShow=true if this is a rollback (to allow showing already completed step)
	self:ShowTutorialStep(nextStepIndex, isRollback == true)
end

function TutorialHandler:CheckStartCondition(step)
	if not step or not step.startCondition then
		return false
	end
	
	local condition = step.startCondition
	local result = false
	
	-- Helper: check if any blocking window is currently open
	local function isAnyBlockingWindowOpen()
		-- Reuse the same window list that is used for temporarily hiding the tutorial
		local windowNames = {
			"Deck", "Daily", "Playtime", "Shop", "RedeemCode", 
			"StartBattle", "Battle", "LootboxOpening", "LikeReward"
		}
		
		for _, windowName in ipairs(windowNames) do
			local window = self:FindUIObject(windowName)
			if window then
				local isOpen = false
				if window:IsA("ScreenGui") then
					isOpen = window.Enabled == true
				else
					isOpen = window.Visible == true
				end
				
				if isOpen then
					return true
				end
			end
		end
		
		return false
	end
	
	if condition.type == "window_open" then
		-- Check if window is open (use cached lookup for performance)
		local window = self:GetCachedUIObject(condition.target)
		if not window then
			result = false
		else
			-- For ScreenGui, check Enabled; for other GuiObjects, check Visible
			if window:IsA("ScreenGui") then
				result = window.Enabled == true
			else
				result = window.Visible == true
			end
		end
	elseif condition.type == "hud_show" then
		-- Check if HUD panel is visible (use cached lookup for performance)
		local panel = self:GetCachedUIObject(condition.target)
		if not panel then
			result = false
		else
			-- HUD panels are GuiObjects, check Visible property
			result = panel.Visible == true
		end
		
		-- Additionally, for hud_show we must ensure that no blocking windows are open.
		-- This prevents situations where a HUD panel is visible under an active modal window
		-- (e.g., LootboxOpening), which would cause the tutorial hint to overlap and block input.
		if result and isAnyBlockingWindowOpen() then
			result = false
		end
	elseif condition.type == "button_click" then
		-- Button clicks are handled via event listeners
		result = false  -- Will be set to true when button is actually clicked
	elseif condition.type == "conditional" then
		-- Conditional conditions are handled by execute methods
		result = self:CheckConditionalStartCondition(step)
	end
	
	return result
end

function TutorialHandler:CheckCompleteCondition(step)
	if not step or not step.completeCondition then
		return false
	end
	
	local condition = step.completeCondition
	
	if condition.type == "window_open" then
		-- Use cached lookup for better performance
		local window = self:GetCachedUIObject(condition.target)
		if not window then
			return false
		end
		
		-- For ScreenGui, check Enabled; for other GuiObjects, check Visible
		if window:IsA("ScreenGui") then
			return window.Enabled == true
		else
			return window.Visible == true
		end
	elseif condition.type == "button_click" then
		-- This will be handled when button is clicked
		return false
	elseif condition.type == "prompt_click" then
		-- This will be handled when ProximityPrompt is activated
		return false
	elseif condition.type == "window_close" then
		-- This will be handled when window closes (event-based)
		return false
	end
	
	return false
end


-- Check conditional start condition
function TutorialHandler:CheckConditionalStartCondition(step)
	if not step or not step.startCondition or step.startCondition.type ~= "conditional" then
		return false
	end
	
	local condition = step.startCondition
	local executeMethod = condition.execute
	
	if not executeMethod then
		warn("TutorialHandler: Conditional condition missing execute method")
		return false
	end
	
	-- Call the execute method
	if self[executeMethod] then
		return self[executeMethod](self, step)
	else
		warn("TutorialHandler: Execute method not found:", executeMethod)
		return false
	end
end

-- Wait for conditional condition to be met
function TutorialHandler:WaitForConditionalCondition(step, stepIndex)
	if not step or not step.startCondition or step.startCondition.type ~= "conditional" then
		return
	end
	
	local conditionName = step.startCondition.condition
	local hasForce = step.completeCondition and step.completeCondition.force == true
	
	-- Check condition immediately first
	local conditionMet = self:CheckConditionalStartCondition(step)
	
	if conditionMet then
		if stepIndex then
			self:ShowTutorialStep(stepIndex)
		end
		return
	end
	
	if hasForce then
		if stepIndex and self.NetworkClient and self.NetworkClient.requestCompleteTutorialStep then
			self.NetworkClient.requestCompleteTutorialStep(stepIndex)
		end
		return
	end
	
	if conditionName == "playtime_reward_claimable" then
		-- Check condition immediately first
		if conditionMet then
			if stepIndex then
				self:ShowTutorialStep(stepIndex)
			end
			return
		end
		
		-- Listen for WindowOpened event instead of waiting for UI object
		-- This is much faster and avoids race conditions
		local windowOpenedConnection = EventBus:On("WindowOpened", function(windowName)
			if windowName == "Playtime" then
				-- Playtime window opened, check condition immediately
				local conditionMetNow = self:CheckConditionalStartCondition(step)
				if conditionMetNow then
					if windowOpenedConnection then
						windowOpenedConnection()
						windowOpenedConnection = nil
					end
					if stepIndex then
						self:ShowTutorialStep(stepIndex)
					end
				end
			end
		end)
		
		if windowOpenedConnection then
			table.insert(self.Connections, windowOpenedConnection)
		end
	elseif conditionName == "playtime_reward_available" then
		task.spawn(function()
			local leftPanel = self:WaitForUIObject("LeftPanel", 10)
			if leftPanel then
				local connections = {}
				self:SetupConditionalPropertyListener(leftPanel, "Visible", step, stepIndex, connections)
				
				local btnPlaytime = leftPanel:FindFirstChild("BtnPlaytime")
				if btnPlaytime then
					local marker = btnPlaytime:FindFirstChild("Marker")
					if marker then
						self:SetupConditionalPropertyListener(marker, "Visible", step, stepIndex, connections)
					else
						local markerConnection = btnPlaytime.ChildAdded:Connect(function(child)
							if child.Name == "Marker" then
								self:SetupConditionalPropertyListener(child, "Visible", step, stepIndex, connections)
								if markerConnection then
									markerConnection:Disconnect()
								end
							end
						end)
						table.insert(self.Connections, markerConnection)
					end
				end
			end
		end)
	elseif conditionName == "lootbox_available" then
		-- Check condition immediately first
		if conditionMet then
			if stepIndex then
				self:ShowTutorialStep(stepIndex)
			end
			return
		end
		
		-- If condition not met, wait for BottomPanel to become visible first
		-- This gives time for profile to update after victory (lootbox added to profile)
		-- Only show altNextStep after BottomPanel is shown and condition still not met
		Logger.debug("[TutorialHandler] WaitForConditionalCondition: lootbox_available not met yet, waiting for HudShown(BottomPanel)")
		local hudShownConnection = EventBus:On("HudShown", function(panelName)
			if panelName == "BottomPanel" then
				-- BottomPanel became visible, check condition again
				-- This gives time for profile to update with lootbox after victory
				local conditionMetNow = self:CheckConditionalStartCondition(step)
				if conditionMetNow then
					Logger.debug("[TutorialHandler] WaitForConditionalCondition: lootbox_available condition met after HudShown(BottomPanel)")
					if hudShownConnection then
						hudShownConnection()
						hudShownConnection = nil
					end
					if stepIndex then
						self:ShowTutorialStep(stepIndex)
					end
				elseif step.altNextStep then
					-- Still no lootbox after BottomPanel shown, show altNextStep
					local altNextStep = step.altNextStep
					Logger.debug("[TutorialHandler] WaitForConditionalCondition: lootbox_available still not met after HudShown(BottomPanel), showing altNextStep %d", altNextStep)
					if hudShownConnection then
						hudShownConnection()
						hudShownConnection = nil
					end
					self.currentStepIndex = altNextStep - 1
					self:ShowTutorialStep(altNextStep, true)
				end
			end
		end)
		
		if hudShownConnection then
			table.insert(self.Connections, hudShownConnection)
		end
	elseif conditionName == "lootbox_claim_available" then
		task.spawn(function()
			local lootboxWindow = self:WaitForUIObject("LootboxOpening", 10)
			if lootboxWindow then
				local connections = {}
				self:SetupConditionalPropertyListener(lootboxWindow, "Visible", step, stepIndex, connections)
				
				local btnClaim = lootboxWindow:FindFirstChild("BtnClaim")
				if btnClaim then
					self:SetupConditionalPropertyListener(btnClaim, "Visible", step, stepIndex, connections)
					self:SetupConditionalPropertyListener(btnClaim, "Active", step, stepIndex, connections)
				else
					local buttonConnection = lootboxWindow.ChildAdded:Connect(function(child)
						if child.Name == "BtnClaim" then
							self:SetupConditionalPropertyListener(child, "Visible", step, stepIndex, connections)
							self:SetupConditionalPropertyListener(child, "Active", step, stepIndex, connections)
							if buttonConnection then
								buttonConnection:Disconnect()
							end
						end
					end)
					table.insert(self.Connections, buttonConnection)
				end
			end
		end)
	elseif conditionName == "reward_window_open" then
		-- Handle Reward window opening (event-based)
		task.spawn(function()
			local rewardWindow = self:WaitForUIObject("Reward", 10)
			if rewardWindow then
				local connections = {}
				-- Listen for window visibility
				self:SetupConditionalPropertyListener(rewardWindow, "Visible", step, stepIndex, connections)
				
				-- Also listen for Victory/Loss frames appearing (they might appear after window opens)
				local function setupVictoryLossListeners()
					local victoryFrame = rewardWindow:FindFirstChild("Victory")
					local lossFrame = rewardWindow:FindFirstChild("Loss")
					
					if victoryFrame then
						self:SetupConditionalPropertyListener(victoryFrame, "Visible", step, stepIndex, connections)
					end
					if lossFrame then
						self:SetupConditionalPropertyListener(lossFrame, "Visible", step, stepIndex, connections)
					end
					
					-- Also check for BtnClaim button
					local buttonsFrame = rewardWindow:FindFirstChild("Buttons")
					if buttonsFrame then
						local btnClaim = buttonsFrame:FindFirstChild("BtnClaim")
						if btnClaim then
							self:SetupConditionalPropertyListener(btnClaim, "Visible", step, stepIndex, connections)
						end
					end
				end
				
				-- Setup listeners immediately if frames already exist
				setupVictoryLossListeners()
				
				-- Also listen for frames being added
				local frameAddedConnection = rewardWindow.DescendantAdded:Connect(function(descendant)
					if descendant.Name == "Victory" or descendant.Name == "Loss" then
						self:SetupConditionalPropertyListener(descendant, "Visible", step, stepIndex, connections)
					end
				end)
				table.insert(self.Connections, frameAddedConnection)
				
				-- Also check ChildAdded for Buttons frame
				local buttonsConnection = rewardWindow.ChildAdded:Connect(function(child)
					if child.Name == "Buttons" then
						local btnClaim = child:FindFirstChild("BtnClaim")
						if btnClaim then
							self:SetupConditionalPropertyListener(btnClaim, "Visible", step, stepIndex, connections)
						end
					end
				end)
				table.insert(self.Connections, buttonsConnection)
			end
		end)
	elseif conditionName == "collection_count" then
		-- Check condition immediately - if not met and has forceStepOnGameLoad, skip to next step
		if not conditionMet and stepIndex == 9 then
			-- Step 9: if no 3rd card, skip to step 10
			-- Check if step 8 has forceStepOnGameLoad = 10
			local step8Config = TutorialConfig.GetStep(8)
			if step8Config and step8Config.forceStepOnGameLoad == 10 then
				Logger.debug("[TutorialHandler] WaitForConditionalCondition: collection_count not met for step 9, skipping to step 10")
				-- Update currentStepIndex to 9 to allow showing step 10
				self.currentStepIndex = 9
				self:ShowTutorialStep(10, true)
				return
			end
		end
		
		-- If condition met, show the step
		if conditionMet then
			if stepIndex then
				self:ShowTutorialStep(stepIndex)
			end
			return
		end
		
		-- Wait for Deck window to become visible, then check condition
		Logger.debug("[TutorialHandler] WaitForConditionalCondition: collection_count not met yet, waiting for Deck window")
		local windowOpenedConnection = EventBus:On("WindowOpened", function(windowName)
			if windowName == "Deck" then
				-- Deck window opened, check condition again
				local conditionMetNow = self:CheckConditionalStartCondition(step)
				if conditionMetNow then
					Logger.debug("[TutorialHandler] WaitForConditionalCondition: collection_count condition met after Deck window opened")
					if windowOpenedConnection then
						windowOpenedConnection()
						windowOpenedConnection = nil
					end
					if stepIndex then
						self:ShowTutorialStep(stepIndex)
					end
				elseif stepIndex == 9 then
					-- Still no 3rd card, skip to step 10
					local step8Config = TutorialConfig.GetStep(8)
					if step8Config and step8Config.forceStepOnGameLoad == 10 then
						Logger.debug("[TutorialHandler] WaitForConditionalCondition: collection_count still not met, skipping to step 10")
						if windowOpenedConnection then
							windowOpenedConnection()
							windowOpenedConnection = nil
						end
						self.currentStepIndex = 9
						self:ShowTutorialStep(10, true)
					end
				end
			end
		end)
		
		if windowOpenedConnection then
			table.insert(self.Connections, windowOpenedConnection)
		end
	end
	
	-- Subscribe to ProfileUpdated for tracking changes (no polling needed)
	if self.NetworkClient then
		local profileConnection = self.NetworkClient.onProfileUpdated(function(payload)
			if self:CheckConditionalStartCondition(step) then
				if stepIndex then
					self:ShowTutorialStep(stepIndex)
				end
				if profileConnection then
					profileConnection:Disconnect()
				end
			end
		end)
		table.insert(self.Connections, profileConnection)
	end
end

-- Execute method: HandleAddCardToDeck
-- Checks if collection has more than 2 cards and finds an active card not in the list
function TutorialHandler:HandleAddCardToDeck(step)
	local ClientState = self.ClientState
	if not ClientState or not ClientState.getProfile then
		return false
	end
	
	-- Get profile using getProfile method
	local profile = ClientState:getProfile()
	if not profile or not profile.collection then
		return false
	end
	
	-- Count total cards in collection
	-- collection is a map: cardId -> {count, level}
	local totalCount = 0
	for cardId, cardData in pairs(profile.collection) do
		if cardData and cardData.count then
			totalCount = totalCount + cardData.count
		end
	end
	
	-- Check if we have more than 2 cards
	if totalCount <= 2 then
		return false
	end
	
	-- Get current deck
	local currentDeck = profile.deck or {}
	local deckCardIds = {}
	for _, cardId in ipairs(currentDeck) do
		deckCardIds[cardId] = true
	end
	
	-- Find a card in collection that is not in deck and has count > 0
	local targetCard = nil
	for cardId, cardData in pairs(profile.collection) do
		if cardData and cardData.count and cardData.count > 0 and not deckCardIds[cardId] then
			targetCard = {
				cardId = cardId,
				count = cardData.count,
				level = cardData.level or 1
			}
			break
		end
	end
	
	if not targetCard then
		return false
	end
	
	-- Find the card in Collection UI
	local deckWindow = self:FindUIObject("Deck")
	if not deckWindow or not deckWindow.Visible then
		return false
	end
	
	local collectionContainer = deckWindow:FindFirstChild("Collection")
	if collectionContainer then
		collectionContainer = collectionContainer:FindFirstChild("Content")
		if collectionContainer then
			collectionContainer = collectionContainer:FindFirstChild("Content")
			if collectionContainer then
				collectionContainer = collectionContainer:FindFirstChild("ScrollingFrame")
			end
		end
	end
	
	if not collectionContainer then
		return false
	end
	
	-- Find card instance in collection
	local cardInstance = collectionContainer:FindFirstChild("Card_" .. targetCard.cardId, true)
	if not cardInstance then
		return false
	end
	
	local relativePath = self:GetRelativePath(cardInstance, self.UI)
	if relativePath then
		self.conditionalTargets = {
			highlight = relativePath,
			arrow = relativePath,
			complete = relativePath .. ".BtnInfo"
		}
		return true
	end
	
	local cardName = "Card_" .. targetCard.cardId
	local foundCard = self:FindUIObject(cardName)
	if foundCard then
		self.conditionalTargets = {
			highlight = cardName,
			arrow = cardName,
			complete = cardName .. ".BtnInfo"
		}
		return true
	end
	
	return false
end

-- Execute method: HandleLootboxAvailable
-- Checks if player has any lootbox in inventory
function TutorialHandler:HandleLootboxAvailable(step)
	local profile = self.ClientState and self.ClientState.getProfile and self.ClientState:getProfile()
	if not profile then
		return false
	end
	
	local hasLootbox = profile.lootboxes and #profile.lootboxes > 0
	return hasLootbox
end

-- Execute method: HandlePlaytimeRewardAvailable
-- Checks if notification marker is visible on playtime button (indicates reward is available)
function TutorialHandler:HandlePlaytimeRewardAvailable(step)
	-- Get NotificationMarkerHandler to check marker visibility
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local success, NotificationMarkerHandler = pcall(function()
		return require(ReplicatedStorage.ClientModules.NotificationMarkerHandler)
	end)
	
	if not success or not NotificationMarkerHandler then
		warn("TutorialHandler: NotificationMarkerHandler not available")
		return false
	end
	
	-- Check if LeftPanel is visible first
	local leftPanel = self:FindUIObject("LeftPanel")
	if not leftPanel or not leftPanel.Visible then
		return false
	end
	
	-- Check if marker is visible for BtnPlaytime
	local markerData = NotificationMarkerHandler.markers and NotificationMarkerHandler.markers["BtnPlaytime"]
	if markerData and markerData.isVisible then
		-- Store targets (they are already specified in step config)
		self.conditionalTargets = {}
		return true
	end
	
	-- Also check directly in UI as fallback
	local btnPlaytime = leftPanel:FindFirstChild("BtnPlaytime")
	if btnPlaytime then
		local marker = btnPlaytime:FindFirstChild("Marker")
		if marker and marker.Visible then
			-- Store targets (they are already specified in step config)
			self.conditionalTargets = {}
			return true
		end
	end
	
	return false
end

-- Execute method: HandleLootboxClaimAvailable
-- Checks if LootboxOpening window is open and BtnClaim button is visible and active
function TutorialHandler:HandleLootboxClaimAvailable(step)
	-- Check if LootboxOpening window is open and visible
	local lootboxWindow = self:FindUIObject("LootboxOpening")
	if not lootboxWindow or not lootboxWindow.Visible then
		return false
	end
	
	-- Check if BtnClaim button exists, is visible and active
	local btnClaim = lootboxWindow:FindFirstChild("BtnClaim")
	if not btnClaim then
		return false
	end
	
	-- Button must be visible and active to be claimable
	if btnClaim.Visible and btnClaim.Active then
		-- Store targets (they are already specified in step config)
		self.conditionalTargets = {}
		return true
	end
	
	return false
end

-- Execute method: HandleClaimPlaytimeReward
-- Finds the first available and visible BtnClaim button in Playtime window
-- Optimized: asks PlaytimeHandler which reward is available first, then finds the button
function TutorialHandler:HandleClaimPlaytimeReward(step)
	-- Check if Playtime window is open and visible
	local playtimeWindow = self:GetCachedUIObject("Playtime")
	if not playtimeWindow or not playtimeWindow.Visible then
		return false
	end
	
	-- Get PlaytimeHandler to check reward availability
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local success, PlaytimeHandler = pcall(function()
		return require(ReplicatedStorage.ClientModules.PlaytimeHandler)
	end)
	
	if not success or not PlaytimeHandler then
		return false
	end
	
	-- Ask handler which reward is available (much faster than searching all buttons)
	local targetRewardIndex = nil
	for i = 1, 7 do
		if PlaytimeHandler:IsRewardAvailable(i) and not PlaytimeHandler:IsRewardClaimed(i) then
			targetRewardIndex = i
			break
		end
	end
	
	if not targetRewardIndex then
		return false
	end
	
	-- Now find the button for this specific reward index
	local listFrame = playtimeWindow:FindFirstChild("List")
	if not listFrame then
		return false
	end
	
	local rewardFrame = listFrame:FindFirstChild("Reward" .. targetRewardIndex)
	if not rewardFrame or not rewardFrame.Visible then
		return false
	end
	
	local content = rewardFrame:FindFirstChild("Content")
	if not content then
		return false
	end
	
	local btnClaim = content:FindFirstChild("BtnClaim")
	if not btnClaim or not btnClaim.Visible or not btnClaim.Active then
		return false
	end
	
	-- Found the button, set up targets
	local targetContent = content:FindFirstChild("Content")
	local contentPath = targetContent and self:GetRelativePath(targetContent, self.UI) or nil
	local relativePath = self:GetRelativePath(btnClaim, self.UI)
	
	if relativePath then
		local highlightPath = contentPath and (contentPath .. "," .. relativePath) or relativePath
		self.conditionalTargets = {
			highlight = highlightPath,
			arrow = relativePath,
			complete = relativePath
		}
		return true
	end
	
	-- Fallback to path-based lookup
	local fallbackContentPath = "Playtime.List.Reward" .. targetRewardIndex .. ".Content.Content"
	local fallbackBtnPath = "Playtime.List.Reward" .. targetRewardIndex .. ".Content.BtnClaim"
	local foundContent = self:FindUIObject(fallbackContentPath)
	local foundBtn = self:FindUIObject(fallbackBtnPath)
	if foundBtn then
		local fallbackHighlight = foundContent and (fallbackContentPath .. "," .. fallbackBtnPath) or fallbackBtnPath
		self.conditionalTargets = {
			highlight = fallbackHighlight,
			arrow = fallbackBtnPath,
			complete = fallbackBtnPath
		}
		return true
	end
	
	return false
end

-- Execute method: HandleRewardWindowOpen
-- Checks if Reward window is open and determines victory/loss to set appropriate text and nextStep
function TutorialHandler:HandleRewardWindowOpen(step)
	-- Check if Reward window is open and visible
	local rewardWindow = self:FindUIObject("Reward")
	if not rewardWindow or not rewardWindow.Visible then
		return false
	end
	
	-- Check Victory and Loss frames to determine battle result
	local victoryFrame = rewardWindow:FindFirstChild("Victory")
	local lossFrame = rewardWindow:FindFirstChild("Loss")
	
	local isVictory = victoryFrame and victoryFrame.Visible
	local isLoss = lossFrame and lossFrame.Visible
	
	-- If neither frame is visible yet, wait
	if not isVictory and not isLoss then
		return false
	end
	
	-- Find BtnClaim button
	local buttonsFrame = rewardWindow:FindFirstChild("Buttons")
	local btnClaim = buttonsFrame and buttonsFrame:FindFirstChild("BtnClaim")
	if not btnClaim then
		return false
	end
	
	-- Get relative path for BtnClaim
	local btnClaimPath = self:GetRelativePath(btnClaim, self.UI)
	if not btnClaimPath then
		btnClaimPath = "Reward.Buttons.BtnClaim"
	end
	
	if isVictory then
		-- Victory case: use normal text and highlight Victory frame
		local victoryPath = self:GetRelativePath(victoryFrame, self.UI) or "Reward.Victory"
		
		-- Find PacksSelector.Packs for highlighting
		local packsSelectorFrame = rewardWindow:FindFirstChild("PacksSelector")
		local packsFrame = packsSelectorFrame and packsSelectorFrame:FindFirstChild("Packs")
		local packsPath = nil
		if packsFrame then
			packsPath = self:GetRelativePath(packsFrame, self.UI)
		end
		if not packsPath then
			packsPath = "Reward.PacksSelector.Packs"
		end
		
		-- Use normal text (already set in config)
		-- Combine victoryPath and packsPath for highlights
		self.conditionalTargets = {
			highlight = victoryPath .. "," .. packsPath .."," .. btnClaimPath,
			arrow = btnClaimPath,
			complete = btnClaimPath
		}
		
		-- Очистить override для победы (использовать исходный nextStep из конфига)
		-- Удалить override полностью, чтобы использовать исходные значения из конфига
		self.stepOverrides[13] = nil
		
		return true
	elseif isLoss then
		-- Loss case: use altText and highlight Loss frame
		local lossPath = self:GetRelativePath(lossFrame, self.UI) or "Reward.Loss"
		
		-- Сохранить override значения, не модифицируя оригинальный конфиг
		if not self.stepOverrides[13] then
			self.stepOverrides[13] = {}
		end
		
		-- Использовать altText для отображения
		if step.altText then
			self.stepOverrides[13].text = step.altText
		end
		
		-- Использовать altNextStep для следующего шага
		if step.altNextStep then
			self.stepOverrides[13].nextStep = step.altNextStep
		end
		
		self.conditionalTargets = {
			highlight = lossPath .. "," .. btnClaimPath,
			arrow = btnClaimPath,
			complete = btnClaimPath
		}
		
		return true
	end
	
	return false
end

function TutorialHandler:GetRelativePath(object, root)
	if not object or not root then
		return nil
	end
	
	local pathParts = {}
	local current = object
	
	while current and current ~= root do
		table.insert(pathParts, 1, current.Name)
		current = current.Parent
	end
	
	return table.concat(pathParts, ".")
end

local function disconnectConnections(connections)
	if not connections then return end
	for _, conn in ipairs(connections) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
end

function TutorialHandler:CheckConditionAndShowStep(step, stepIndex, connections)
	-- Don't show steps that have already been completed
	-- This prevents showing step 13 again after it was completed
	if self.currentStepIndex and self.currentStepIndex >= stepIndex then
		-- Step already completed, disconnect connections and return
		disconnectConnections(connections)
		return false
	end
	
	-- Don't show if tutorial is active and showing this step
	if self.isTutorialActive and self.showingStepIndex == stepIndex then
		return false
	end
	
	if self:CheckConditionalStartCondition(step) then
		if stepIndex then
			self:ShowTutorialStep(stepIndex)
		end
		disconnectConnections(connections)
		return true
	end
	return false
end

function TutorialHandler:SetupConditionalPropertyListener(object, propertyName, step, stepIndex, connections)
	if not object then return nil end
	
	local connection = object:GetPropertyChangedSignal(propertyName):Connect(function()
		self:CheckConditionAndShowStep(step, stepIndex, connections)
	end)
	
	table.insert(self.Connections, connection)
	if connections then
		table.insert(connections, connection)
	end
	
	self:CheckConditionAndShowStep(step, stepIndex, connections)
	
	return connection
end

-- Helper function to wait for UI object using events instead of polling
function TutorialHandler:WaitForUIObject(objectPath, timeoutSeconds)
	timeoutSeconds = timeoutSeconds or 10
	
	-- Try to find immediately
	local obj = self:FindUIObject(objectPath)
	if obj then
		return obj
	end
	
	-- Parse path to find root and target name
	local pathParts = {}
	for part in string.gmatch(objectPath, "([^%.]+)") do
		table.insert(pathParts, part)
	end
	
	if #pathParts == 0 then
		return nil
	end
	
	local targetName = pathParts[#pathParts]
	local root = self.UI
	
	-- Try to find parent path
	if #pathParts > 1 then
		local parentPath = table.concat(pathParts, ".", 1, #pathParts - 1)
		root = self:FindUIObject(parentPath)
		if not root then
			-- Fallback to UI root
			root = self.UI
		end
	end
	
	if not root then
		return nil
	end
	
	-- Use event-based approach
	local foundObject = nil
	local connection = nil
	local timedOut = false
	
	-- Set up timeout
	local timeoutConnection = task.delay(timeoutSeconds, function()
		timedOut = true
		if connection then
			connection:Disconnect()
		end
	end)
	
	-- Listen for descendant added
	connection = root.DescendantAdded:Connect(function(descendant)
		if descendant.Name == targetName then
			-- Verify it matches the full path
			local fullPath = self:GetRelativePath(descendant, self.UI)
			if fullPath == objectPath or string.find(fullPath, objectPath) then
				foundObject = descendant
				if connection then
					connection:Disconnect()
				end
				if timeoutConnection then
					task.cancel(timeoutConnection)
				end
			end
		end
	end)
	
	-- Check existing descendants immediately
	local existingObj = root:FindFirstChild(targetName, true)
	if existingObj then
		local fullPath = self:GetRelativePath(existingObj, self.UI)
		if fullPath == objectPath or string.find(fullPath, objectPath) then
			foundObject = existingObj
			if connection then
				connection:Disconnect()
			end
			if timeoutConnection then
				task.cancel(timeoutConnection)
			end
		end
	end
	
	-- Wait for object or timeout (using minimal wait)
	while not foundObject and not timedOut and self._initialized do
		task.wait()  -- Wait one frame
	end
	
	if connection and connection.Connected then
		connection:Disconnect()
	end
	
	return foundObject
end

function TutorialHandler:ShowTutorialStep(stepIndex, forceShow)
	-- Don't show steps that have already been completed
	-- UNLESS forceShow is true (for forceStepOnGameLoad)
	if not forceShow and self.currentStepIndex and self.currentStepIndex >= stepIndex then
		Logger.debug("[TutorialHandler] ShowTutorialStep: Step %d already completed (currentStepIndex=%d), skipping", 
			stepIndex, self.currentStepIndex)
		return
	end
	
	-- Don't show the same step twice
	if self.showingStepIndex == stepIndex and self.isTutorialActive then
		Logger.debug("[TutorialHandler] ShowTutorialStep: Step %d already showing, skipping", stepIndex)
		return
	end
	
	local TutorialConfig = require(game.ReplicatedStorage.Modules.Tutorial.TutorialConfig)
	
	-- Ensure stepIndex is a number
	if type(stepIndex) ~= "number" then
		warn("TutorialHandler: ShowTutorialStep expects a number (step index), got:", type(stepIndex))
		return
	end
	
	-- Clear pending flag if this step was scheduled
	if self.pendingNextStepIndex == stepIndex then
		self.pendingNextStepIndex = nil
	end
	
	local step = TutorialConfig.GetStep(stepIndex)
	
	if not step then
		warn("TutorialHandler: Step " .. stepIndex .. " not found")
		return
	end
	
	if self.isTutorialActive then
		self:HideTutorialStep()
		-- This ensures UI is fully hidden before showing next step
		task.wait(0.15)
	end
	
	self.currentStep = step
	self.showingStepIndex = stepIndex  -- Store the index of the step currently being shown
	self.lastShownStepIndex = stepIndex  -- Store last shown step for tracking
	-- Note: self.currentStepIndex stores the last completed step (from profile), not the currently showing step
	self.isTutorialActive = true
	
	if step.startCondition and step.startCondition.target == "StartBattle" then
		local startBattleWindow = self:GetCachedUIObject("StartBattle")
		if not startBattleWindow or not startBattleWindow.Visible then
			return
		end
		
		local startButton = self:GetCachedUIObject("StartBattle.Buttons.BtnStart")
		if startButton and startButton:IsA("GuiButton") then
			startButton.Active = false
			self._tutorialBlockedButton = startButton
		end
	end
	
	if self.tutorialGui then
		self.tutorialGui.Enabled = true
	else
		warn("TutorialHandler: Tutorial GUI is nil")
	end
	
	-- Create all tutorial elements first (before animation, so TweenUI can capture their base transparency values)
	-- Show highlights (replace "conditional" with computed targets)
	if step.highlightObjects and #step.highlightObjects > 0 then
		local highlightTargets = {}
		for _, objName in ipairs(step.highlightObjects) do
			if objName == "conditional" then
				local conditionalTarget = self.conditionalTargets and self.conditionalTargets.highlight
				if conditionalTarget then
					-- Check if conditionalTarget contains multiple paths (comma-separated)
					if string.find(conditionalTarget, ",") then
						-- Split by comma and add each path
						for path in string.gmatch(conditionalTarget, "([^,]+)") do
							path = string.match(path, "^%s*(.-)%s*$")  -- Trim whitespace
							if path and path ~= "" then
								table.insert(highlightTargets, path)
							end
						end
					else
						table.insert(highlightTargets, conditionalTarget)
					end
				else
					warn("TutorialHandler: 'conditional' in highlightObjects but no target computed")
				end
			else
				table.insert(highlightTargets, objName)
			end
		end
		if #highlightTargets > 0 then
			self:HighlightObjects(highlightTargets)
		end
	end
	
	-- Show arrow (replace "conditional" with computed target)
	if step.arrow and step.arrow.objectName and step.arrow.side then
		local arrowTarget = step.arrow.objectName
		if arrowTarget == "conditional" then
			arrowTarget = self.conditionalTargets and self.conditionalTargets.arrow
			if not arrowTarget then
				warn("TutorialHandler: 'conditional' in arrow.objectName but no target computed")
			end
		end
		if arrowTarget then
			self:ShowArrow(arrowTarget, step.arrow.side)
		end
	end
	
	if step.path then
		self:ShowPath(step.path)
	end
	
	-- Использовать override текст, если он есть, иначе использовать текст из конфига
	local textToShow = step.text
	if self.stepOverrides[stepIndex] and self.stepOverrides[stepIndex].text then
		textToShow = self.stepOverrides[stepIndex].text
	end
	
	if textToShow then
		self:ShowText(textToShow)
	end
	
	-- Disable all ProximityPrompts when tutorial overlay is shown
	self:DisableAllProximityPrompts()
	
	-- If step requires prompt_click, re-enable required prompts
	if step.completeCondition and step.completeCondition.type == "prompt_click" then
		Logger.debug("[TutorialHandler] ShowTutorialStep: Step requires prompt_click, enabling required ProximityPrompts")
		self:EnableRequiredProximityPrompts(step)
	end
	
	self:ShowTutorialWithAnimation()
	self:SetupCompleteConditionListener(step)
end

function TutorialHandler:HideTutorialStep()
	self.isTutorialActive = false
	self.isTutorialTemporarilyHidden = false
	self.currentStep = nil
	self.showingStepIndex = nil
	self.pendingStepIndex = nil
	self.pendingNextStepIndex = nil  -- Clear pending next step flag
	
	for _, conn in ipairs(self.windowVisibilityConnections) do
		if conn and typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
	end
	self.windowVisibilityConnections = {}
	
	-- Hide tutorial with animation first
	self:HideTutorialWithAnimation()
	
	-- Hide all tutorial elements
	self:HideHighlight()
	self:HideArrow()
	self:HideText()
	self:HidePath()
	
	-- Clear conditional targets
	self.conditionalTargets = {}
	
	-- Clear UI object cache to ensure fresh lookups on next step
	self._uiObjectCache = {}
	
	-- Clean up update connections (for position updates)
	for _, conn in ipairs(self.updateConnections) do
		if conn and typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
	end
	self.updateConnections = {}
	
	-- Clean up temporary tutorial connections (complete condition listeners, etc.)
	-- But keep persistent connections (ProfileUpdated) active
	for _, conn in ipairs(self.Connections) do
		if conn and typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
	end
	self.Connections = {}
	
	if self._tutorialBlockedButton then
		self._tutorialBlockedButton.Active = true
		self._tutorialBlockedButton = nil
	end
	
	-- Restore all ProximityPrompts when tutorial overlay is hidden
	self:RestoreAllProximityPrompts()
end

function TutorialHandler:ShowTutorialWithAnimation()
	if not self.tutorialContainer then
		-- Fallback: just enable GUI if container not found
		if self.tutorialGui then
			self.tutorialGui.Enabled = true
			Logger.debug("[TutorialHandler] ShowTutorialWithAnimation: Enabled GUI (no container)")
		else
			warn("[TutorialHandler] ShowTutorialWithAnimation: No tutorialGui or tutorialContainer")
		end
		return
	end
	
	Logger.debug("[TutorialHandler] ShowTutorialWithAnimation: Showing tutorial container")
	
	-- Enable GUI BEFORE animation to prevent race condition with FadeOut callback
	if self.tutorialGui then
		self.tutorialGui.Enabled = true
		Logger.debug("[TutorialHandler] ShowTutorialWithAnimation: GUI enabled before animation")
	end
	
	local TweenUI = self.Utilities and self.Utilities.TweenUI
	if TweenUI and TweenUI.FadeIn then
		Logger.debug("[TutorialHandler] ShowTutorialWithAnimation: Using TweenUI.FadeIn")
		TweenUI.FadeIn(self.tutorialContainer, 0.1, function()
			if self._tutorialBlockedButton then
				self._tutorialBlockedButton.Active = true
				self._tutorialBlockedButton = nil
			end
			Logger.debug("[TutorialHandler] ShowTutorialWithAnimation: FadeIn complete")
		end)
	else
		Logger.debug("[TutorialHandler] ShowTutorialWithAnimation: Using fallback (no TweenUI)")
		self.tutorialContainer.Visible = true
		if self.tutorialGui then
			self.tutorialGui.Enabled = true
		end
		if self._tutorialBlockedButton then
			self._tutorialBlockedButton.Active = true
			self._tutorialBlockedButton = nil
		end
	end
end

function TutorialHandler:HideTutorialWithAnimation()
	if not self.tutorialContainer then
		-- Fallback: just disable GUI if container not found
		if self.tutorialGui then
			self.tutorialGui.Enabled = false
			Logger.debug("[TutorialHandler] HideTutorialWithAnimation: Disabled GUI (no container)")
		else
			Logger.debug("[TutorialHandler] HideTutorialWithAnimation: No tutorialGui or tutorialContainer")
		end
		return
	end
	
	Logger.debug("[TutorialHandler] HideTutorialWithAnimation: Hiding tutorial container")
	
	local TweenUI = self.Utilities and self.Utilities.TweenUI
	if TweenUI and TweenUI.FadeOut then
		Logger.debug("[TutorialHandler] HideTutorialWithAnimation: Using TweenUI.FadeOut")
		-- Store current isTutorialActive state to check in callback
		local wasTutorialActive = self.isTutorialActive
		-- Pass skipHide=true to prevent TweenUI from hiding container, we'll do it in callback if needed
		TweenUI.FadeOut(self.tutorialContainer, 0.1, function()
			-- Only hide container and disable GUI if tutorial is still not active (prevent race condition)
			-- If a new step was shown while FadeOut was animating, isTutorialActive will be true
			if not self.isTutorialActive and wasTutorialActive == false then
				if self.tutorialContainer then
					self.tutorialContainer.Visible = false
				end
				if self.tutorialGui then
					self.tutorialGui.Enabled = false
				end
				Logger.debug("[TutorialHandler] HideTutorialWithAnimation: FadeOut complete, container hidden (tutorial not active)")
			else
				Logger.debug("[TutorialHandler] HideTutorialWithAnimation: FadeOut complete, but tutorial is active again, keeping container visible")
			end
		end, true)  -- skipHide = true to prevent TweenUI from hiding container automatically
	else
		Logger.debug("[TutorialHandler] HideTutorialWithAnimation: Using fallback (no TweenUI)")
		-- Fallback: just hide
		self.tutorialContainer.Visible = false
		if self.tutorialGui and not self.isTutorialActive then
			self.tutorialGui.Enabled = false
		end
		Logger.debug("[TutorialHandler] HideTutorialWithAnimation: Fallback complete, container hidden")
	end
end

function TutorialHandler:HighlightObjects(objectNames)
	-- Hide previous highlights
	self:HideHighlight()
	
	if not objectNames or #objectNames == 0 then
		return
	end
	
	-- Check if we have overlay and template
	if not self.overlayObject then
		warn("TutorialHandler: Overlay not available for highlights")
		return
	end
	
	if not self.highlightTemplate then
		warn("TutorialHandler: Highlight template not available")
		return
	end
	
	-- Collect all objects first (wait for all to appear)
	local objectsToHighlight = {}
	local allFound = false
	
	local function collectObjects()
		objectsToHighlight = {}
		for _, objectName in ipairs(objectNames) do
			local obj = self:FindUIObject(objectName)
			if obj then
				table.insert(objectsToHighlight, obj)
			else
				return false
			end
		end
		return true
	end
	
	-- Try to collect all objects
	if not collectObjects() then
		-- Wait for all objects to appear using events
		task.spawn(function()
			-- Set up listeners for each missing object
			local missingObjects = {}
			for _, objectName in ipairs(objectNames) do
				if not self:FindUIObject(objectName) then
					table.insert(missingObjects, objectName)
				end
			end
			
			if #missingObjects > 0 then
				local connections = {}
				local allFound = false
				
				local function checkAllFound()
					if allFound then return end
					
					local stillMissing = {}
					for _, objectName in ipairs(missingObjects) do
						if not self:FindUIObject(objectName) then
							table.insert(stillMissing, objectName)
						end
					end
					
					if #stillMissing == 0 then
						allFound = true
						-- Disconnect all connections
						for _, conn in ipairs(connections) do
							if conn and typeof(conn) == "RBXScriptConnection" and conn.Connected then
								conn:Disconnect()
							end
						end
						-- Create highlights
						if collectObjects() then
							self:CreateHighlightsWithUnifiedMasks(objectsToHighlight)
						end
					end
				end
				
				-- Set up DescendantAdded listeners for each missing object
				for _, objectName in ipairs(missingObjects) do
					local pathParts = {}
					for part in string.gmatch(objectName, "([^%.]+)") do
						table.insert(pathParts, part)
					end
					
					if #pathParts > 0 then
						local targetName = pathParts[#pathParts]
						local parentPath = #pathParts > 1 and table.concat(pathParts, ".", 1, #pathParts - 1) or nil
						
						local root = parentPath and self:FindUIObject(parentPath) or self.UI
						if root then
							local conn = root.DescendantAdded:Connect(function(descendant)
								if descendant.Name == targetName then
									checkAllFound()
								end
							end)
							table.insert(connections, conn)
						end
					end
				end
				
				-- Check existing objects immediately
				checkAllFound()
				
				-- Timeout fallback (only if still waiting)
				if not allFound then
					task.delay(10, function()
						if not allFound then
							allFound = true
							for _, conn in ipairs(connections) do
								if conn and typeof(conn) == "RBXScriptConnection" and conn.Connected then
									conn:Disconnect()
								end
							end
							-- Create highlights with whatever we found
							if collectObjects() and #objectsToHighlight > 0 then
								self:CreateHighlightsWithUnifiedMasks(objectsToHighlight)
							end
						end
					end)
				end
			end
		end)
	else
		-- All objects found, create highlights
		self:CreateHighlightsWithUnifiedMasks(objectsToHighlight)
	end
end

function TutorialHandler:CreateHighlightsWithUnifiedMasks(objects)
	if not objects or #objects == 0 then
		return
	end
	
	if not self.overlayObject or not self.highlightTemplate then
		warn("TutorialHandler: Overlay or highlight template not available")
		return
	end
	
	-- Get overlay position and size for relative positioning
	local overlayPos = self.overlayObject.AbsolutePosition
	local overlaySize = self.overlayObject.AbsoluteSize
	
	-- Create highlight frames and individual masks for each object
	local highlightDataList = {}
	
	for _, obj in ipairs(objects) do
		if obj and obj:IsA("GuiObject") then
			-- Clone highlight template
			local highlightFrame = self.highlightTemplate:Clone()
			highlightFrame.Name = "Highlight_" .. obj.Name
			highlightFrame.Parent = self.overlayObject
			highlightFrame.Visible = true
			-- Make sure highlight frame doesn't block clicks (it's just visual)
			if highlightFrame:IsA("GuiButton") or highlightFrame:IsA("TextButton") or highlightFrame:IsA("ImageButton") then
				highlightFrame.Active = false
			end
			
			-- Create individual masks for this object (TopMask, BottomMask, LeftMask, RightMask)
			local masks = {}
			local maskNames = {"Top", "Bottom", "Left", "Right"}
			
			for _, maskName in ipairs(maskNames) do
				local mask = Instance.new("TextButton")
				mask.Name = maskName .. "Mask_" .. obj.Name
				mask.BackgroundColor3 = DARK_OVERLAY_COLOR
				mask.BackgroundTransparency = DARK_OVERLAY_TRANSPARENCY
				mask.BorderSizePixel = 0
				mask.Text = ""
				mask.AutoButtonColor = false
				mask.Active = true
				mask.ZIndex = HIGHLIGHT_Z_INDEX - 1
				mask.Parent = self.overlayObject
				masks[maskName] = mask
			end
			
			table.insert(highlightDataList, {
				object = obj,
				frame = highlightFrame,
				masks = masks
			})
		end
	end
	
	-- Function to update all highlights and their individual masks
	local function updateHighlights()
		-- Check if all objects still exist
		for i = #highlightDataList, 1, -1 do
			local data = highlightDataList[i]
			if not data.object or not data.object.Parent then
				table.remove(highlightDataList, i)
			end
		end
		
		if #highlightDataList == 0 then
			return
		end
		
		-- Update overlay position (it might change)
		local rawOverlayPos = self.overlayObject.AbsolutePosition
		local rawOverlaySize = self.overlayObject.AbsoluteSize
		
		-- Round overlay coordinates to integers for consistency across devices
		local overlayPosX = math.floor(rawOverlayPos.X)
		local overlayPosY = math.floor(rawOverlayPos.Y)
		local overlaySizeX = math.ceil(rawOverlaySize.X)
		local overlaySizeY = math.ceil(rawOverlaySize.Y)
		
		-- Collect all object bounds first
		local objectBounds = {}
		for _, data in ipairs(highlightDataList) do
			local obj = data.object
			if obj and obj.Parent then
				local absPos, absSize = obj.AbsolutePosition, obj.AbsoluteSize
				-- Round all coordinates to integers for consistency
				local relativeX = math.floor(absPos.X - overlayPosX)
				local relativeY = math.floor(absPos.Y - overlayPosY)
				local width = math.ceil(absSize.X)
				local height = math.ceil(absSize.Y)
				
				-- Update highlight frame position (relative to overlay)
				data.frame.Position = UDim2.new(0, relativeX, 0, relativeY)
				data.frame.Size = UDim2.new(0, width, 0, height)
				
				table.insert(objectBounds, {
					x = relativeX,
					y = relativeY,
					width = width,
					height = height,
					right = relativeX + width,
					bottom = relativeY + height,
					data = data
				})
			end
		end
		
		-- Update masks for each object, ensuring they don't overlap and form a unified "holey" overlay
		-- Rule: between two objects, only one mask should exist:
		-- - For vertical: bottom mask of upper object (hide top mask of lower object)
		-- - For horizontal: right mask of left object (hide left mask of right object)
		for idx, bounds in ipairs(objectBounds) do
			local data = bounds.data
			local masks = data.masks
			
			-- Check if there's an object directly above this one (overlapping horizontally)
			-- If yes, hide top mask of this object (upper object will have bottom mask)
			local hasObjectAbove = false
			for _, otherBounds in ipairs(objectBounds) do
				if otherBounds ~= bounds then
					if otherBounds.bottom <= bounds.y then
						-- Other object is above
						if not (otherBounds.right <= bounds.x or otherBounds.x >= bounds.right) then
							-- Overlaps horizontally - there's an object directly above
							hasObjectAbove = true
							break
						end
					end
				end
			end
			
			-- Top mask: hide if there's an object directly above (it will have bottom mask)
			if hasObjectAbove then
				masks.Top.Visible = false
			else
				local topStartY = 0
				local topEndY = bounds.y
				
				-- Find the bottom-most object above this one (that doesn't overlap horizontally)
				for _, otherBounds in ipairs(objectBounds) do
					if otherBounds ~= bounds then
						if otherBounds.bottom <= bounds.y then
							-- Other object is above, but doesn't overlap horizontally
							if otherBounds.right <= bounds.x or otherBounds.x >= bounds.right then
								topStartY = math.max(topStartY, otherBounds.bottom)
							end
						end
					end
				end
				
				if topStartY < topEndY then
					local topStartYInt = math.floor(topStartY)
					local topEndYInt = math.floor(topEndY)
					local maskHeight = topEndYInt - topStartYInt
					masks.Top.Position = UDim2.new(0, 0, 0, topStartYInt)
					masks.Top.Size = UDim2.new(1, 0, 0, maskHeight)
					masks.Top.Visible = true
				else
					masks.Top.Visible = false
				end
			end
			
			-- Bottom mask: always show (upper object's bottom mask covers space to lower object)
			local bottomStartY = bounds.bottom
			local bottomEndY = overlaySizeY
			
			-- Find the top-most object below this one
			for _, otherBounds in ipairs(objectBounds) do
				if otherBounds ~= bounds then
					if otherBounds.y >= bounds.bottom then
						-- Other object is below
						if not (otherBounds.right <= bounds.x or otherBounds.x >= bounds.right) then
							-- Overlaps horizontally - stop bottom mask at this object
							bottomEndY = math.min(bottomEndY, otherBounds.y)
						else
							-- Doesn't overlap horizontally - still consider it
							bottomEndY = math.min(bottomEndY, otherBounds.y)
						end
					end
				end
			end
			
			if bottomStartY < bottomEndY then
				local bottomStartYInt = math.floor(bottomStartY)
				local bottomEndYInt = math.floor(bottomEndY)
				local maskHeight = bottomEndYInt - bottomStartYInt
				masks.Bottom.Position = UDim2.new(0, 0, 0, bottomStartYInt)
				masks.Bottom.Size = UDim2.new(1, 0, 0, maskHeight)
				masks.Bottom.Visible = true
			else
				masks.Bottom.Visible = false
			end
			
			-- Check if there's an object directly to the left (overlapping vertically)
			-- If yes, hide left mask of this object (left object will have right mask)
			local hasObjectLeft = false
			for _, otherBounds in ipairs(objectBounds) do
				if otherBounds ~= bounds then
					if otherBounds.right <= bounds.x then
						-- Other object is to the left
						if not (otherBounds.bottom <= bounds.y or otherBounds.y >= bounds.bottom) then
							-- Overlaps vertically - there's an object directly to the left
							hasObjectLeft = true
							break
						end
					end
				end
			end
			
			-- Left mask: hide if there's an object directly to the left (it will have right mask)
			if hasObjectLeft then
				masks.Left.Visible = false
			else
				local leftStart = 0
				local leftEnd = bounds.x
				local leftTop = bounds.y
				local leftBottom = bounds.bottom
				
				-- Find the rightmost object to the left (that doesn't overlap vertically)
				for _, otherBounds in ipairs(objectBounds) do
					if otherBounds ~= bounds then
						if otherBounds.right <= bounds.x then
							-- Other object is to the left, but doesn't overlap vertically
							if otherBounds.bottom <= bounds.y or otherBounds.y >= bounds.bottom then
								leftStart = math.max(leftStart, otherBounds.right)
							end
						end
					end
				end
				
				if leftStart < leftEnd then
					local leftStartInt = math.floor(leftStart)
					local leftEndInt = math.floor(leftEnd)
					local leftTopInt = math.floor(leftTop)
					local leftBottomInt = math.floor(leftBottom)
					local maskWidth = leftEndInt - leftStartInt
					local maskHeight = leftBottomInt - leftTopInt
					masks.Left.Position = UDim2.new(0, leftStartInt, 0, leftTopInt)
					masks.Left.Size = UDim2.new(0, maskWidth, 0, maskHeight)
					masks.Left.Visible = true
				else
					masks.Left.Visible = false
				end
			end
			
			-- Right mask: always show (left object's right mask covers space to right object)
			local rightStart = bounds.right
			local rightEnd = overlaySizeX
			local rightTop = bounds.y
			local rightBottom = bounds.bottom
			
			-- Find the leftmost object to the right
			for _, otherBounds in ipairs(objectBounds) do
				if otherBounds ~= bounds then
					if otherBounds.x >= bounds.right then
						-- Other object is to the right
						if not (otherBounds.bottom <= bounds.y or otherBounds.y >= bounds.bottom) then
							-- Overlaps vertically - stop right mask at this object
							rightEnd = math.min(rightEnd, otherBounds.x)
						else
							-- Doesn't overlap vertically - still consider it
							rightEnd = math.min(rightEnd, otherBounds.x)
						end
					end
				end
			end
			
			if rightStart < rightEnd then
				local rightStartInt = math.floor(rightStart)
				local rightEndInt = math.floor(rightEnd)
				local rightTopInt = math.floor(rightTop)
				local rightBottomInt = math.floor(rightBottom)
				local maskWidth = rightEndInt - rightStartInt
				local maskHeight = rightBottomInt - rightTopInt
				masks.Right.Position = UDim2.new(0, rightStartInt, 0, rightTopInt)
				masks.Right.Size = UDim2.new(0, maskWidth, 0, maskHeight)
				masks.Right.Visible = true
			else
				masks.Right.Visible = false
			end
		end
	end
	
	-- Initial update
	updateHighlights()
	
	-- Update on size/position changes
	local connection = RunService.Heartbeat:Connect(updateHighlights)
	table.insert(self.updateConnections, connection)
	
	-- Store references
	for _, data in ipairs(highlightDataList) do
		table.insert(self.highlightObjects, {
			object = data.object,
			frame = data.frame,
			masks = data.masks,
			connection = connection
		})
	end
end

function TutorialHandler:HideHighlight()
	-- Disconnect update connections
	for _, conn in ipairs(self.updateConnections) do
		if conn and typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
	end
	self.updateConnections = {}
	
	-- Remove all cloned highlights and their masks from Overlay
	if self.overlayObject then
		-- Remove all highlight frames and their individual masks
		for _, highlightData in ipairs(self.highlightObjects) do
			if highlightData.frame and highlightData.frame.Parent then
				highlightData.frame:Destroy()
			end
			
			-- Remove individual masks for this highlight
			if highlightData.masks then
				for _, mask in pairs(highlightData.masks) do
					if mask and mask.Parent then
						mask:Destroy()
					end
				end
			end
		end
	end
	
	-- Check if tutorial is not active before clearing highlights
	-- If tutorial is not active, restore ProximityPrompts when overlay is hidden
	local wasTutorialActive = self.isTutorialActive
	
	self.highlightObjects = {}
	
	-- If tutorial is not active and highlights are being hidden, restore ProximityPrompts
	-- This handles cases where overlay is hidden but tutorial was active
	if not wasTutorialActive then
		Logger.debug("[TutorialHandler] HideHighlight: Tutorial not active, restoring ProximityPrompts")
		self:RestoreAllProximityPrompts()
	end
end

function TutorialHandler:ShowArrow(objectName, side)
	-- Hide previous arrow
	self:HideArrow()
	
	if not objectName or not side then
		return
	end
	
	local obj = self:FindUIObject(objectName)
	if not obj then
		-- Wait for object to appear using events
		task.spawn(function()
			local foundObj = self:WaitForUIObject(objectName, 10)
			if foundObj then
				self:CreateArrowForObject(foundObj, side)
			end
		end)
		return
	end
	
	self:CreateArrowForObject(obj, side)
end

function TutorialHandler:CreateArrowForObject(obj, side)
	if not obj or not obj:IsA("GuiObject") then
		return
	end
	
	-- Use existing arrow from cloned template
	if not self.arrowObject then
		warn("TutorialHandler: Arrow object not found in tutorial template")
		return
	end
	
	if not self.arrowLeft or not self.arrowRight then
		warn("TutorialHandler: ArrowLeft or ArrowRight not found in Arrow")
		return
	end
	
	if not self.overlayObject then
		warn("TutorialHandler: Overlay not available for arrow positioning")
		return
	end
	
	self.arrowObject.Visible = true
	
	if side == "left" then
		self.arrowLeft.Visible = true
		self.arrowRight.Visible = false
	elseif side == "right" then
		self.arrowLeft.Visible = false
		self.arrowRight.Visible = true
	end
	
	self.arrowTargetObject = obj
	self.arrowSide = side
	
	local function updateArrowPosition()
		local targetObj = self.arrowTargetObject
		if not targetObj or not targetObj.Parent or not self.arrowObject or not self.overlayObject then
			return
		end
		
		local overlayPos = self.overlayObject.AbsolutePosition
		local overlaySize = self.overlayObject.AbsoluteSize
		local absPos, absSize = targetObj.AbsolutePosition, targetObj.AbsoluteSize
		local arrowFrame = (self.arrowSide == "left") and self.arrowLeft or self.arrowRight
		local arrowFrameSize = arrowFrame.AbsoluteSize
		
		-- Calculate relative positions (0-1 scale)
		local relativeX = (absPos.X - overlayPos.X) / overlaySize.X
		local relativeY = (absPos.Y - overlayPos.Y) / overlaySize.Y
		local objectWidth = absSize.X / overlaySize.X
		local objectHeight = absSize.Y / overlaySize.Y
		local objectCenterY = relativeY + objectHeight
		
		-- Calculate arrow size in scale
		local arrowWidth = arrowFrameSize.X / overlaySize.X
		local arrowHeight = arrowFrameSize.Y / overlaySize.Y
		
		-- Offset in scale (20 pixels converted to scale)
		local offsetScale = 20 / overlaySize.X  -- Horizontal offset
		
		local sideX, sideY = 0, 0
		local basePosition = nil
		
		if side == "left" then
			sideX = relativeX
			sideY = objectCenterY
			-- Position: left of object, offset by arrow width + 20px (in scale)
			local posX = relativeX - arrowWidth - offsetScale
			local posY = objectCenterY - arrowHeight / 2
			basePosition = UDim2.new(posX, 0, posY, 0)
		elseif side == "right" then
			sideX = relativeX + objectWidth
			sideY = objectCenterY
			-- Position: right of object, offset by arrow width + 20px (in scale)
			local posX = relativeX + objectWidth + arrowWidth + offsetScale
			local posY = objectCenterY - arrowHeight / 2
			basePosition = UDim2.new(posX, 0, posY, 0)
		end
		
		if not self.arrowAnimationStarted and basePosition then
			self.arrowObject.Position = basePosition
			self.arrowBasePosition = basePosition
			self.arrowSidePosition = {x = sideX, y = sideY}
		end
	end
	
	updateArrowPosition()
	
	task.spawn(function()
		task.wait()
		updateArrowPosition()
		
		if self.arrowSidePosition and self.arrowBasePosition and self.arrowObject then
			local basePos = self.arrowBasePosition
			local sidePos = self.arrowSidePosition
			local overlaySize = self.overlayObject.AbsoluteSize
			local arrowFrame = (side == "left") and self.arrowLeft or self.arrowRight
			local arrowFrameSize = arrowFrame.AbsoluteSize
			
			-- Calculate arrow size in scale
			local arrowWidth = arrowFrameSize.X / overlaySize.X
			
			local targetPosition = nil
			if side == "left" then
				-- Animate towards object side (move right)
				local targetX = sidePos.x - arrowWidth / 2
				targetPosition = UDim2.new(targetX, 0, basePos.Y.Scale, 0)
			elseif side == "right" then
				-- Animate towards object side (move left)
				local targetX = sidePos.x + arrowWidth / 2
				targetPosition = UDim2.new(targetX, 0, basePos.Y.Scale, 0)
			end
			
			if targetPosition then
				self.arrowAnimationStarted = true
				local pulseInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
				local pulseTween = TweenService:Create(self.arrowObject, pulseInfo, {Position = targetPosition})
				if pulseTween then
					pulseTween:Play()
					table.insert(self.tweenConnections, pulseTween)
				end
			end
		end
	end)
	
	local connection = RunService.Heartbeat:Connect(updateArrowPosition)
	table.insert(self.updateConnections, connection)
end

function TutorialHandler:HideArrow()
	-- Stop tweens
	for _, tween in ipairs(self.tweenConnections) do
		if tween then
			tween:Cancel()
		end
	end
	self.tweenConnections = {}
	
	-- Hide arrow container and both arrow directions
	if self.arrowObject then
		self.arrowObject.Visible = false
	end
	if self.arrowLeft then
		self.arrowLeft.Visible = false
	end
	if self.arrowRight then
		self.arrowRight.Visible = false
	end
	
	-- Clear references
	self.arrowTargetObject = nil
	self.arrowFrame = nil
	self.arrowSide = nil
	self.arrowSidePosition = nil
	self.arrowBasePosition = nil
	self.arrowAnimationStarted = false
end

function TutorialHandler:ShowText(text)
	-- Hide previous text
	self:HideText()
	
	if not text or text == "" then
		return
	end
	
	-- Use existing text object from cloned template
	if not self.textObject or not self.textLabel then
		warn("TutorialHandler: Text object or TxtDescription not found in tutorial template")
		return
	end
	
	-- Set text and show
	self.textLabel.Text = text
	self.textObject.Visible = true
end

function TutorialHandler:HideText()
	-- Hide text object
	if self.textObject then
		self.textObject.Visible = false
	end
end

function TutorialHandler:ShowPath(targetName)
	-- Hide previous path
	self:HidePath()
	
	if not targetName then
		return
	end
	
	-- Check if we have beam template
	if not self.beamTemplate then
		warn("TutorialHandler: Beam template not found")
		return
	end
	
	-- Find target object (can be in workspace or UI)
	-- Use async approach to wait for object to appear
	task.spawn(function()
		local targetObject = nil
		local workspace = game:GetService("Workspace")
		
		-- Try to find in workspace first
		if string.find(targetName, "Workspace") then
			-- Remove "Workspace." prefix if present
			local path = string.gsub(targetName, "^Workspace%.", "")
			targetObject = workspace:FindFirstChild(path, true)
			
			-- If not found, wait for it to appear using events only
			if not targetObject then
				-- Parse path to find parent and child name
				local pathParts = {}
				for part in string.gmatch(path, "([^%.]+)") do
					table.insert(pathParts, part)
				end
				
				if #pathParts > 0 then
					local childName = pathParts[#pathParts]
					local parentPath = ""
					if #pathParts > 1 then
						parentPath = table.concat(pathParts, ".", 1, #pathParts - 1)
					end
					
					local parent = workspace
					if parentPath ~= "" then
						parent = workspace:FindFirstChild(parentPath, true)
					end
					
					if parent then
						-- Use event-based approach only (no polling)
						local connection = parent.DescendantAdded:Connect(function(descendant)
							if descendant.Name == childName then
								targetObject = descendant
								self:SetupPathForObject(targetObject, targetName)
								if connection then
									connection:Disconnect()
								end
							end
						end)
						table.insert(self.Connections, connection)
						
						-- Also check existing descendants immediately (in case object already exists)
						local existingObject = parent:FindFirstChild(childName, true)
						if existingObject then
							targetObject = existingObject
							connection:Disconnect()
							self:SetupPathForObject(targetObject, targetName)
						end
					else
						-- Parent not found, need to wait for parent first
						warn("TutorialHandler: Path parent not found:", parentPath or "Workspace")
					end
				end
			else
				-- Object already found, setup immediately
				self:SetupPathForObject(targetObject, targetName)
			end
		else
			-- Try to find in UI
			targetObject = self:FindUIObject(targetName)
			
			if targetObject then
				-- Object already found, setup immediately
				self:SetupPathForObject(targetObject, targetName)
			else
				-- UI objects are handled differently - they appear through UI system
				-- For now, we'll use a simple check (UI objects usually appear quickly)
				warn("TutorialHandler: Path target not found in UI:", targetName)
			end
		end
	end)
end

function TutorialHandler:SetupPathForObject(targetObject, targetName)
	
	-- Get player character
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	if not player or not player.Character then
		warn("TutorialHandler: Player character not found")
		return
	end
	
	local character = player.Character
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		warn("TutorialHandler: HumanoidRootPart not found")
		return
	end
	
	-- Create Attachment on player
	local fromAttachment = Instance.new("Attachment")
	fromAttachment.Name = "TutorialPathFrom"
	fromAttachment.Parent = humanoidRootPart
	fromAttachment.Position = Vector3.new(0, 1, 0)  -- Slightly above center
	
	-- Create Attachment for target
	local toAttachment = Instance.new("Attachment")
	toAttachment.Name = "TutorialPathTo"
	
	-- Clone beam template and place it in Workspace
	local workspace = game:GetService("Workspace")
	local beam = self.beamTemplate:Clone()
	beam.Name = "TutorialBeam"
	beam.Parent = workspace
	
	-- Set attachments
	beam.Attachment0 = fromAttachment
	beam.Attachment1 = toAttachment
	
	-- Handle target positioning
	local targetPart = nil
	local updateConnection = nil
	
	if targetObject:IsA("BasePart") or targetObject:IsA("Model") then
		-- 3D object - attach directly
		if targetObject:IsA("Model") then
			local primaryPart = targetObject.PrimaryPart or targetObject:FindFirstChild("HumanoidRootPart")
			if primaryPart then
				targetPart = primaryPart
			else
				-- Use first part
				targetPart = targetObject:FindFirstChildOfClass("BasePart")
			end
		else
			targetPart = targetObject
		end
		
		if targetPart then
			toAttachment.Parent = targetPart
			toAttachment.Position = Vector3.new(0, 0, 0)
		end
	else
		-- UI object - create invisible part and update position
		targetPart = Instance.new("Part")
		targetPart.Name = "TutorialPathTarget"
		targetPart.Anchored = true
		targetPart.CanCollide = false
		targetPart.Transparency = 1
		targetPart.Size = Vector3.new(0.1, 0.1, 0.1)
		targetPart.Parent = workspace
		toAttachment.Parent = targetPart
		
		-- Function to update target position from UI
		local function updateTargetPosition()
			if not targetObject or not targetObject.Parent then
				return
			end
			
			local absPos = targetObject.AbsolutePosition
			local absSize = targetObject.AbsoluteSize
			local centerX = absPos.X + absSize.X / 2
			local centerY = absPos.Y + absSize.Y / 2
			
			local camera = workspace.CurrentCamera
			if camera then
				local ray = camera:ViewportPointToRay(centerX, centerY)
				local distance = 10  -- Distance from camera
				local worldPosition = ray.Origin + ray.Direction * distance
				targetPart.Position = worldPosition
			end
		end
		
		updateConnection = RunService.Heartbeat:Connect(updateTargetPosition)
		updateTargetPosition()  -- Initial update
	end
	
	-- Store references for cleanup
	table.insert(self.pathObjects, {
		beam = beam,  -- Store cloned beam for destruction
		fromAttachment = fromAttachment,
		toAttachment = toAttachment,
		targetPart = targetPart,
		updateConnection = updateConnection,
		targetObject = targetObject
	})
end

function TutorialHandler:HidePath()
	if not self.pathObjects then
		return
	end
	
	for _, pathData in ipairs(self.pathObjects) do
		-- Disconnect update connection
		if pathData.updateConnection then
			pathData.updateConnection:Disconnect()
		end
		
		-- Destroy cloned beam
		if pathData.beam then
			pathData.beam:Destroy()
		end
		
		-- Destroy attachments
		if pathData.fromAttachment then
			pathData.fromAttachment:Destroy()
		end
		if pathData.toAttachment then
			pathData.toAttachment:Destroy()
		end
		
		-- Only destroy targetPart if we created it (for UI objects)
		if pathData.targetPart and pathData.targetPart.Name == "TutorialPathTarget" then
			pathData.targetPart:Destroy()
		end
	end
	
	self.pathObjects = {}
end

-- Helper: Find Deck container
function TutorialHandler:FindDeckContainer()
	local deckWindow = self:FindUIObject("Deck")
	if not deckWindow then
		return nil
	end
	
	local container = deckWindow:FindFirstChild("Deck")
	if container then
		container = container:FindFirstChild("Content")
		if container then
			container = container:FindFirstChild("Content")
		end
	end
	return container
end

-- Helper: Find Collection container
function TutorialHandler:FindCollectionContainer()
	local deckWindow = self:FindUIObject("Deck")
	if not deckWindow then
		return nil
	end
	
	local container = deckWindow:FindFirstChild("Collection")
	if container then
		container = container:FindFirstChild("Content")
		if container then
			container = container:FindFirstChild("Content")
			if container then
				container = container:FindFirstChild("ScrollingFrame")
			end
		end
	end
	return container
end

-- Helper: Setup button listener
function TutorialHandler:SetupButtonClickListener(button)
	if not button or not button.Parent then
		return false
	end
	
	if not (button:IsA("GuiButton") or button:IsA("TextButton") or button:IsA("ImageButton")) then
		warn("TutorialHandler: Found object but it's not a button type:", button.ClassName)
		return false
	end
	
	local function completeStep()
		if self.isTutorialActive and self.showingStepIndex then
			self:CompleteCurrentStep()
		end
	end
	
	local clickConnection = button.MouseButton1Click:Connect(completeStep)
	local activatedConnection = button.Activated:Connect(completeStep)
	
	table.insert(self.Connections, clickConnection)
	table.insert(self.Connections, activatedConnection)
	return true
end

-- Helper: Setup listener on card button (BtnInfo)
function TutorialHandler:SetupCardButtonListener(card, buttonName)
	if not card then
		return false
	end
	
	local btnInfo = card:FindFirstChild(buttonName or "BtnInfo")
	if btnInfo then
		return self:SetupButtonClickListener(btnInfo)
	end
	
	local btnInfoConnection = card.ChildAdded:Connect(function(child)
		if child.Name == (buttonName or "BtnInfo") then
			if self:SetupButtonClickListener(child) then
				if btnInfoConnection then
					btnInfoConnection:Disconnect()
				end
			end
		end
	end)
	table.insert(self.Connections, btnInfoConnection)
	
	btnInfo = card:FindFirstChild(buttonName or "BtnInfo")
	if btnInfo then
		if btnInfoConnection then
			btnInfoConnection:Disconnect()
		end
		return self:SetupButtonClickListener(btnInfo)
	end
	
	return false
end

-- Helper: Setup listener for DeckCard button
function TutorialHandler:SetupDeckCardButtonListener(target, condition)
	local cardIdPattern = string.match(condition.target, "DeckCard_([^_]+)_")
	if not cardIdPattern then
		return false
	end
	
	local deckContainer = self:FindDeckContainer()
	if not deckContainer then
		return false
	end
	
	local function setupListenerOnCard(card)
		return self:SetupCardButtonListener(card)
	end
	
	local descendantConnection = deckContainer.ChildAdded:Connect(function(child)
		if child.Name:match("^DeckCard_" .. cardIdPattern .. "_") then
			setupListenerOnCard(child)
		end
	end)
	table.insert(self.Connections, descendantConnection)
	
	task.spawn(function()
		if not self.isTutorialActive then
			return
		end
		
		for _, child in pairs(deckContainer:GetChildren()) do
			if child.Name:match("^DeckCard_" .. cardIdPattern .. "_") then
				if not setupListenerOnCard(child) then
					task.wait(0.1)
					setupListenerOnCard(child)
				end
			end
		end
	end)
	
	return true
end

-- Helper: Setup listener for Collection Card button
function TutorialHandler:SetupCollectionCardButtonListener(target, condition)
	local cardIdPattern = string.match(target, "Card_([^%.]+)")
	if not cardIdPattern then
		return false
	end
	
	local collectionContainer = self:FindCollectionContainer()
	if not collectionContainer then
		return false
	end
	
	local function setupListenerOnCard(card)
		return self:SetupCardButtonListener(card)
	end
	
	local descendantConnection = collectionContainer.ChildAdded:Connect(function(child)
		if child.Name == "Card_" .. cardIdPattern then
			setupListenerOnCard(child)
		end
	end)
	table.insert(self.Connections, descendantConnection)
	
	task.spawn(function()
		if not self.isTutorialActive then
			return
		end
		
		for _, child in pairs(collectionContainer:GetChildren()) do
			if child.Name == "Card_" .. cardIdPattern then
				if setupListenerOnCard(child) then
					break
				end
			end
		end
	end)
	
	return true
end

-- Helper: Setup listener for generic button
function TutorialHandler:SetupGenericButtonListener(target)
	local button = self:FindUIObject(target)
	if button and self:SetupButtonClickListener(button) then
		return
	end
	
	task.spawn(function()
		local foundButton = self:WaitForUIObject(target, 10)
		if foundButton then
			self:SetupButtonClickListener(foundButton)
		end
	end)
end

function TutorialHandler:SetupCompleteConditionListener(step)
	if not step or not step.completeCondition then
		return
	end
	
	local condition = step.completeCondition
	
	-- Resolve "conditional" target
	local target = condition.target
	if target == "conditional" then
		if condition.type == "prompt_click" and step.path then
			target = step.path
		else
			target = self.conditionalTargets and self.conditionalTargets.complete
			if not target then
				warn("TutorialHandler: 'conditional' in completeCondition.target but no target computed")
				return
			end
		end
	end
	
	if condition.type == "prompt_click" and condition.target == "conditional" then
		self:SetupWindowVisibilityTracking(step)
	end
	
	if condition.type == "window_open" or condition.type == "window_close" then
		task.spawn(function()
			local window = self:WaitForUIObject(target, 10)
			if not window then
				warn("TutorialHandler: Window not found for complete condition:", target)
				return
			end
			
			local propertyName = window:IsA("ScreenGui") and "Enabled" or "Visible"
			local connection = window:GetPropertyChangedSignal(propertyName):Connect(function()
				if condition.type == "window_open" then
					if self:CheckCompleteCondition(step) then
						self:CompleteCurrentStep()
						connection:Disconnect()
					end
				elseif condition.type == "window_close" then
					local isClosed = window:IsA("ScreenGui") and not window.Enabled or not window.Visible
					if isClosed and self.isTutorialActive then
						self:CompleteCurrentStep()
						connection:Disconnect()
					end
				end
			end)
			table.insert(self.Connections, connection)
			
			if condition.type == "window_open" and self:CheckCompleteCondition(step) then
				self:CompleteCurrentStep()
				connection:Disconnect()
			elseif condition.type == "window_close" then
				local isClosed = window:IsA("ScreenGui") and not window.Enabled or not window.Visible
				if isClosed and self.isTutorialActive then
					self:CompleteCurrentStep()
					connection:Disconnect()
				end
			end
		end)
	elseif condition.type == "button_click" then
		if string.find(target, "DeckCard_") then
			self:SetupDeckCardButtonListener(target, condition)
		elseif string.find(target, "Card_") and not string.find(target, "DeckCard_") then
			if not self:SetupCollectionCardButtonListener(target, condition) then
				self:SetupGenericButtonListener(target)
			end
		else
			self:SetupGenericButtonListener(target)
		end
	elseif condition.type == "prompt_click" then
		-- Set up ProximityPrompt listener
		
		-- Wait for target object and ProximityPrompt to appear using events only
		task.spawn(function()
			local targetObject = nil
			local workspace = game:GetService("Workspace")
			
			-- Find target object (from path)
			if string.find(target, "Workspace") then
				-- Remove "Workspace." prefix if present
				local path = string.gsub(target, "^Workspace%.", "")
				targetObject = workspace:FindFirstChild(path, true)
				
				-- If not found, wait for it to appear using events only
				if not targetObject then
					-- Parse path to find parent and child name
					local pathParts = {}
					for part in string.gmatch(path, "([^%.]+)") do
						table.insert(pathParts, part)
					end
					
					if #pathParts > 0 then
						local childName = pathParts[#pathParts]
						local parentPath = ""
						if #pathParts > 1 then
							parentPath = table.concat(pathParts, ".", 1, #pathParts - 1)
						end
						
						local parent = workspace
						if parentPath ~= "" then
							parent = workspace:FindFirstChild(parentPath, true)
						end
						
							if parent then
							-- Use event-based approach only (no polling)
							local connection = parent.DescendantAdded:Connect(function(descendant)
								if descendant.Name == childName then
									targetObject = descendant
									-- Now wait for ProximityPrompt
									self:WaitForProximityPrompt(targetObject, step)
									if connection then
										connection:Disconnect()
									end
								end
							end)
							table.insert(self.Connections, connection)
							
							-- Check existing descendants immediately
							local existingObject = parent:FindFirstChild(childName, true)
							if existingObject then
								targetObject = existingObject
								connection:Disconnect()
								self:WaitForProximityPrompt(targetObject, step)
							end
						else
							warn("TutorialHandler: ProximityPrompt target parent not found:", parentPath or "Workspace")
						end
					end
				else
					-- Object already found, wait for ProximityPrompt
					self:WaitForProximityPrompt(targetObject, step)
				end
			else
				-- Try to find in workspace directly
				targetObject = workspace:FindFirstChild(target, true)
				
				if targetObject then
					-- Object already found, wait for ProximityPrompt
					self:WaitForProximityPrompt(targetObject, step)
				else
					warn("TutorialHandler: ProximityPrompt target not found:", target)
				end
			end
		end)
	end
end

-- Wait for ProximityPrompt to appear in target object (event-based only)
function TutorialHandler:WaitForProximityPrompt(targetObject, step)
	if not targetObject then
		warn("TutorialHandler: WaitForProximityPrompt called with nil targetObject")
		return
	end
	
	-- Find ProximityPrompt in target object
	local prompt = targetObject:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = targetObject:FindFirstChild("ProximityPrompt", true)
	end
	
	if prompt then
		self:SetupProximityPromptListener(prompt)
	else
		local descendantConnection = nil
		local childConnection = nil
		
		descendantConnection = targetObject.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("ProximityPrompt") then
				prompt = descendant
				self:SetupProximityPromptListener(prompt)
				if descendantConnection then
					descendantConnection:Disconnect()
				end
				if childConnection then
					childConnection:Disconnect()
				end
			end
		end)
		table.insert(self.Connections, descendantConnection)
		
		childConnection = targetObject.ChildAdded:Connect(function(child)
			if child:IsA("ProximityPrompt") then
				prompt = child
				self:SetupProximityPromptListener(prompt)
				if childConnection then
					childConnection:Disconnect()
				end
				if descendantConnection then
					descendantConnection:Disconnect()
				end
			end
		end)
		table.insert(self.Connections, childConnection)
	end
end

-- Enable ProximityPrompts that match promptTargets for the current step
function TutorialHandler:EnableRequiredProximityPrompts(step)
	if not step or not step.promptTargets or #step.promptTargets == 0 then
		return
	end
	
	local workspace = game:GetService("Workspace")
	
	-- Find and enable prompts that match promptTargets
	for _, promptTarget in ipairs(step.promptTargets) do
		-- Search for objects with matching names
		local targetObject = workspace:FindFirstChild(promptTarget, true)
		if targetObject then
			-- Find ProximityPrompt in target object
			local prompt = targetObject:FindFirstChildOfClass("ProximityPrompt")
			if not prompt then
				prompt = targetObject:FindFirstChild("ProximityPrompt", true)
			end
			
			if prompt then
				-- Re-enable this prompt if it was disabled
				if self.proximityPromptsState[prompt] ~= nil then
					local success, err = pcall(function()
						prompt.Enabled = true
					end)
					if not success then
						warn("TutorialHandler: Failed to re-enable ProximityPrompt for target:", promptTarget, err)
					else
						Logger.debug("[TutorialHandler] EnableRequiredProximityPrompts: Re-enabled ProximityPrompt for target:", promptTarget)
					end
				else
					-- Prompt wasn't disabled, but ensure it's enabled
					local success, err = pcall(function()
						if not prompt.Enabled then
							prompt.Enabled = true
							Logger.debug("[TutorialHandler] EnableRequiredProximityPrompts: Enabled ProximityPrompt for target:", promptTarget)
						end
					end)
					if not success then
						warn("TutorialHandler: Failed to enable ProximityPrompt for target:", promptTarget, err)
					end
				end
			end
		end
	end
end

-- Setup listener for ProximityPrompt
function TutorialHandler:SetupProximityPromptListener(prompt)
	if not prompt then
		warn("TutorialHandler: SetupProximityPromptListener called with nil prompt")
		return
	end
	
	-- Re-enable this prompt if it was disabled, as it's needed for tutorial step completion
	-- This allows users to interact with prompts required for prompt_click steps
	if self.proximityPromptsState[prompt] ~= nil then
		-- Prompt was disabled, restore it to enabled state
		local success, err = pcall(function()
			prompt.Enabled = true
		end)
		if not success then
			warn("TutorialHandler: Failed to re-enable ProximityPrompt:", err)
		else
			Logger.debug("[TutorialHandler] SetupProximityPromptListener: Re-enabled ProximityPrompt for tutorial step")
		end
	else
		-- Prompt wasn't disabled, but ensure it's enabled
		local success, err = pcall(function()
			if not prompt.Enabled then
				prompt.Enabled = true
				Logger.debug("[TutorialHandler] SetupProximityPromptListener: Enabled ProximityPrompt for tutorial step")
			end
		end)
		if not success then
			warn("TutorialHandler: Failed to enable ProximityPrompt:", err)
		end
	end
	
	local promptConnection = prompt.Triggered:Connect(function(player)
		if player == Players.LocalPlayer and self.isTutorialActive then
			self:CompleteCurrentStep()
		end
	end)
	
	table.insert(self.Connections, promptConnection)
end

function TutorialHandler:CompleteCurrentStep()
	if not self.isTutorialActive or not self.showingStepIndex then
		warn(string.format("[TutorialHandler] CompleteCurrentStep called but tutorial not active (isTutorialActive: %s, showingStepIndex: %s)", 
			tostring(self.isTutorialActive), tostring(self.showingStepIndex)))
		return
	end
	
	local stepIndexToSend = self.showingStepIndex
	local TutorialConfig = require(game.ReplicatedStorage.Modules.Tutorial.TutorialConfig)
	
	-- IMPORTANT: Always send the CURRENT showing step to server (e.g., step 13)
	-- Server will check if this step has altNextStep and handle the rollback
	-- Do NOT send altNextStep directly - server needs to know which step was completed
	
	Logger.debug("[TutorialHandler] CompleteCurrentStep: completing step %d, currentStepIndex = %d", 
		stepIndexToSend, self.currentStepIndex)
	
	-- Optimistic update: update local state immediately for instant visual feedback
	-- BUT only if we're completing the next sequential step (not skipping steps)
	-- This prevents server rejection when trying to complete step N+2 while server is on step N
	local wasOptimisticUpdate = false
	if self.currentStepIndex == stepIndexToSend - 1 then
		-- We're completing the next sequential step - safe to optimistically update
		local oldStepIndex = self.currentStepIndex
		self.currentStepIndex = stepIndexToSend
		wasOptimisticUpdate = true
		Logger.debug("[TutorialHandler] Optimistic update: currentStepIndex %d -> %d", oldStepIndex, stepIndexToSend)
		
		-- IMPORTANT: For step 13, check stepOverrides BEFORE determining next step
		-- This ensures we use the correct next step (14 for victory, 11 for loss)
		-- Don't show next step optimistically for step 13 - wait for server confirmation
		-- to avoid showing wrong step (11) briefly before server confirms (14)
		if stepIndexToSend == 13 then
			Logger.debug("[TutorialHandler] Step 13 completed, waiting for server confirmation before showing next step")
			-- Hide current step and wait for server response
			self:HideTutorialStep()
			-- Send request to server - it will determine victory/loss and return correct step
			local useAltNextStep = false
			if self.stepOverrides[13] and self.stepOverrides[13].nextStep then
				local overrideNextStep = self.stepOverrides[13].nextStep
				local stepConfig = TutorialConfig.GetStep(stepIndexToSend)
				if stepConfig and stepConfig.altNextStep == overrideNextStep then
					useAltNextStep = true
					Logger.debug("[TutorialHandler] CompleteCurrentStep: Step 13 has altNextStep override (loss case), will use altNextStep")
				end
			end
			
			if self.NetworkClient and self.NetworkClient.requestCompleteTutorialStep then
				self.NetworkClient.requestCompleteTutorialStep(stepIndexToSend, useAltNextStep)
				Logger.debug("[TutorialHandler] Sent requestCompleteTutorialStep(%d, useAltNextStep=%s) to server", stepIndexToSend, tostring(useAltNextStep))
			end
			return
		end
	elseif self.currentStepIndex < stepIndexToSend - 1 then
		-- We're trying to skip steps - don't optimistically update, wait for server
		Logger.debug("[TutorialHandler] Cannot optimistically update: currentStepIndex=%d, stepIndexToSend=%d (would skip steps), waiting for server", 
			self.currentStepIndex, stepIndexToSend)
		
		-- Check if next step's startCondition is already met, show it immediately
		local nextStepIndex = self:GetNextStepIndex(stepIndexToSend)
		if nextStepIndex then
			local nextStep = TutorialConfig.GetStep(nextStepIndex)
			if nextStep then
				local nextStartConditionMet = self:CheckStartCondition(nextStep)
				if nextStartConditionMet then
					Logger.debug("[TutorialHandler] Next step %d startCondition already met, showing immediately", nextStepIndex)
					-- Hide current step first
					self:HideTutorialStep()
					-- Mark next step as pending to track scheduled show
					self.pendingNextStepIndex = nextStepIndex
					-- Use task.spawn with task.wait() for more reliable execution than task.defer
					task.spawn(function()
						-- Wait for FadeOut animation to complete (0.3s duration + small buffer)
						-- This ensures UI is fully hidden and ready before showing next step
						task.wait(0.35)
						-- Verify we should still show this step
						-- Check that pending flag is still set and we haven't progressed past this step
						if self.pendingNextStepIndex == nextStepIndex then
							-- Verify currentStepIndex hasn't been rolled back (server might have rejected)
							local currentStep = self.currentStepIndex
							if currentStep >= stepIndexToSend then
								self:ShowTutorialStep(nextStepIndex)
								self.pendingNextStepIndex = nil  -- Clear flag after showing
							else
								-- Step was rolled back by server, clear flag
								Logger.debug("[TutorialHandler] Step %d was rolled back by server (currentStepIndex=%d < stepIndexToSend=%d), clearing pending flag", 
									nextStepIndex, currentStep, stepIndexToSend)
								self.pendingNextStepIndex = nil
							end
						else
							-- Step was cancelled or superseded
							self.pendingNextStepIndex = nil
						end
					end)
					
					-- Send request to server asynchronously
					if self.NetworkClient and self.NetworkClient.requestCompleteTutorialStep then
						self.NetworkClient.requestCompleteTutorialStep(stepIndexToSend)
						Logger.debug("[TutorialHandler] Sent requestCompleteTutorialStep(%d) to server", stepIndexToSend)
					end
					return
				else
					-- Next step's startCondition is not met yet
					-- If it's a conditional step, wait for the condition to be met
					if nextStep.startCondition and nextStep.startCondition.type == "conditional" then
						Logger.debug("[TutorialHandler] Next step %d is conditional and condition not met, waiting for condition", nextStepIndex)
						-- Hide current step first
						self:HideTutorialStep()
						-- Send request to server asynchronously
						if self.NetworkClient and self.NetworkClient.requestCompleteTutorialStep then
							self.NetworkClient.requestCompleteTutorialStep(stepIndexToSend)
							Logger.debug("[TutorialHandler] Sent requestCompleteTutorialStep(%d) to server", stepIndexToSend)
						end
						-- Wait for conditional condition to be met
						self:WaitForConditionalCondition(nextStep, nextStepIndex)
						return
					end
				end
			end
		end
	end
	
	-- Check if step is already completed (e.g., shown via forceStepOnGameLoad but already done on server)
	-- This happens when forceStepOnGameLoad shows an earlier step that was already completed
	-- In this case, we should skip server request and automatically show next step in sequence
	-- This allows forceStepOnGameLoad to show steps in order for tutorial purposes
	if stepIndexToSend < self.currentStepIndex then
		Logger.debug("[TutorialHandler] CompleteCurrentStep: Step %d already completed (currentStepIndex=%d), skipping server request and showing next step in sequence", 
			stepIndexToSend, self.currentStepIndex)
		
		-- Hide current step
		self:HideTutorialStep()
		
		-- Get the next step in sequence (stepIndexToSend + 1, not currentStepIndex + 1)
		-- This allows showing steps in order: 5 -> 6 -> 7, even if they're already completed
		local nextStepInSequence = self:GetNextStepIndex(stepIndexToSend)
		if nextStepInSequence then
			-- Continue showing steps in sequence until we reach a step that needs server update
			-- Process the next step immediately (it will handle its own startCondition)
			task.spawn(function()
				self:WaitForLoadingScreenToFinish()
				-- Check if next step is also already completed
				-- If so, it will also skip server request and continue to next step
				self:ProcessTutorialStep(nextStepInSequence, false)
			end)
		else
			Logger.debug("[TutorialHandler] No next step after %d, tutorial complete", stepIndexToSend)
		end
		return
	end
	
	-- Check if we have override for nextStep (e.g., altNextStep for loss case in step 13, or no lootbox case in step 14)
	-- This indicates victory/loss: if stepOverrides[13].nextStep = 11, it's a loss
	-- For step 14: if stepOverrides[14].nextStep = 11, it means no lootbox was available
	local useAltNextStep = false
	if stepIndexToSend == 13 then
		if self.stepOverrides[13] and self.stepOverrides[13].nextStep then
			local overrideNextStep = self.stepOverrides[13].nextStep
			local stepConfig = TutorialConfig.GetStep(stepIndexToSend)
			if stepConfig and stepConfig.altNextStep == overrideNextStep then
				useAltNextStep = true
				Logger.debug("[TutorialHandler] CompleteCurrentStep: Step 13 has altNextStep override (loss case), will use altNextStep")
			end
		end
	elseif stepIndexToSend == 14 then
		-- For step 14, check if stepOverrides[14] exists (set by HandleLootboxAvailable when no lootbox)
		if self.stepOverrides[14] and self.stepOverrides[14].nextStep then
			local overrideNextStep = self.stepOverrides[14].nextStep
			local stepConfig = TutorialConfig.GetStep(stepIndexToSend)
			if stepConfig and stepConfig.altNextStep == overrideNextStep then
				useAltNextStep = true
				Logger.debug("[TutorialHandler] CompleteCurrentStep: Step 14 has altNextStep override (no lootbox case), will use altNextStep")
			end
		end
	end
	
	-- Send request to server
	if self.NetworkClient and self.NetworkClient.requestCompleteTutorialStep then
		self.NetworkClient.requestCompleteTutorialStep(stepIndexToSend, useAltNextStep)
		Logger.debug("[TutorialHandler] Sent requestCompleteTutorialStep(%d, useAltNextStep=%s) to server", stepIndexToSend, tostring(useAltNextStep))
	else
		warn("[TutorialHandler] NetworkClient.requestCompleteTutorialStep not available")
	end
	
	-- Hide tutorial step (next step will be shown when server confirms)
	self:HideTutorialStep()
end

-- Get cached UI object or find and cache it
function TutorialHandler:GetCachedUIObject(objectName)
	if not objectName then
		return nil
	end
	
	-- Check cache first
	if self._uiObjectCache[objectName] then
		local cached = self._uiObjectCache[objectName]
		-- Verify object still exists, has valid parent, and is a GuiObject
		-- This ensures we don't return stale references to destroyed or recreated objects
		if cached and cached.Parent and cached:IsA("GuiObject") then
			return cached
		else
			-- Cache invalid, clear it
			self._uiObjectCache[objectName] = nil
		end
	end
	
	-- Find object
	local obj = self:FindUIObject(objectName)
	if obj then
		-- Cache it for future use
		self._uiObjectCache[objectName] = obj
	end
	
	return obj
end

function TutorialHandler:FindUIObject(objectName)
	if not self.UI or not objectName then
		return nil
	end
	
	if objectName == self.UI.Name or (objectName == "GameUI" and self.UI.Name == "GameUI") then
		return self.UI
	end
	
	if string.find(objectName, "%.") then
		local pathParts = {}
		for part in string.gmatch(objectName, "([^%.]+)") do
			table.insert(pathParts, part)
		end
		
		if #pathParts == 0 then
			return nil
		end
		
		local current = self.UI
		
		for i, partName in ipairs(pathParts) do
			if not current then
				return nil
			end
			
			local child = current:FindFirstChild(partName)
			if not child and i == #pathParts then
				child = current:FindFirstChild(partName, true)
			end
			
			if not child then
				return nil
			end
			
			if i == #pathParts then
				return child:IsA("GuiObject") and child or nil
			end
			
			current = child
		end
		
		return nil
	else
		local obj = self.UI:FindFirstChild(objectName, true)
		if obj and obj:IsA("GuiObject") then
			return obj
		end
		local Players = game:GetService("Players")
		local player = Players.LocalPlayer
		if player then
			local playerGui = player:FindFirstChild("PlayerGui")
			if playerGui then
				local topLevelObj = playerGui:FindFirstChild(objectName, true)
				if topLevelObj and topLevelObj:IsA("GuiObject") then
					return topLevelObj
				end
			end
		end
		
		-- Try recursive search as fallback
		local function searchRecursive(parent)
			if not parent then
				return nil
			end
			for _, child in ipairs(parent:GetChildren()) do
				if child.Name == objectName and child:IsA("GuiObject") then
					return child
				end
				local found = searchRecursive(child)
				if found then
					return found
				end
			end
			return nil
		end
		
		return searchRecursive(self.UI)
	end
end

-- Public Methods
function TutorialHandler:IsInitialized()
	return self._initialized
end

-- Cleanup
function TutorialHandler:Cleanup()
	-- Hide tutorial
	self:HideTutorialStep()
	
	-- Disconnect all connections (both temporary and persistent)
	for _, connection in ipairs(self.Connections) do
		if connection then
			if type(connection) == "function" then
				connection()
			elseif connection.Disconnect then
				connection:Disconnect()
			end
		end
	end
	self.Connections = {}
	
	for _, connection in ipairs(self.PersistentConnections) do
		if connection then
			if type(connection) == "function" then
				connection()
			elseif connection.Disconnect then
				connection:Disconnect()
			end
		end
	end
	self.PersistentConnections = {}
	
	-- Clear caches
	self._uiObjectCache = {}
	
	self._initialized = false
	Logger.debug("✅ TutorialHandler cleaned up")
end

-- Setup window visibility tracking for prompt_click with conditional target
function TutorialHandler:SetupWindowVisibilityTracking(step)
	
	local windowNames = {
		"Deck", "Daily", "Playtime", "Shop", "RedeemCode", 
		"StartBattle", "Battle", "LootboxOpening", "LikeReward"
	}
	
	for _, conn in ipairs(self.windowVisibilityConnections) do
		if conn and typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
	end
	self.windowVisibilityConnections = {}
	
	for _, windowName in ipairs(windowNames) do
		local window = self:FindUIObject(windowName)
		if window then
			local propertyName = window:IsA("ScreenGui") and "Enabled" or "Visible"
			local connection = window:GetPropertyChangedSignal(propertyName):Connect(function()
				local isOpen = false
				if window:IsA("ScreenGui") then
					isOpen = window.Enabled == true
				else
					isOpen = window.Visible == true
				end
				
				if isOpen then
					if self.isTutorialActive and not self.isTutorialTemporarilyHidden then
						self:TemporarilyHideTutorial()
					end
				else
					if self.isTutorialActive and self.isTutorialTemporarilyHidden then
						self:RestoreTutorial()
					end
				end
			end)
			table.insert(self.windowVisibilityConnections, connection)
		else
			task.spawn(function()
				local foundWindow = self:WaitForUIObject(windowName, 10)
				if foundWindow then
					local propertyName = foundWindow:IsA("ScreenGui") and "Enabled" or "Visible"
					local connection = foundWindow:GetPropertyChangedSignal(propertyName):Connect(function()
						local isOpen = false
						if foundWindow:IsA("ScreenGui") then
							isOpen = foundWindow.Enabled == true
						else
							isOpen = foundWindow.Visible == true
						end
						
						if isOpen then
							if self.isTutorialActive and not self.isTutorialTemporarilyHidden then
								self:TemporarilyHideTutorial()
							end
						else
							if self.isTutorialActive and self.isTutorialTemporarilyHidden then
								self:RestoreTutorial()
							end
						end
					end)
					table.insert(self.windowVisibilityConnections, connection)
				end
			end)
		end
	end
end

function TutorialHandler:TemporarilyHideTutorial()
	if not self.isTutorialActive or self.isTutorialTemporarilyHidden then
		return
	end
	
	self.isTutorialTemporarilyHidden = true
	
	if self.tutorialGui then
		self.tutorialGui.Enabled = false
	end
	
	if self.tutorialContainer then
		local TweenUI = self.Utilities and self.Utilities.TweenUI
		if TweenUI and TweenUI.FadeOut then
			TweenUI.FadeOut(self.tutorialContainer, 0.2)
		else
			self.tutorialContainer.Visible = false
		end
	end
end

function TutorialHandler:RestoreTutorial()
	if not self.isTutorialActive or not self.isTutorialTemporarilyHidden then
		return
	end
	
	local windowNames = {
		"Deck", "Daily", "Playtime", "Shop", "RedeemCode", 
		"StartBattle", "Battle", "LootboxOpening", "LikeReward"
	}
	
	local anyWindowOpen = false
	for _, windowName in ipairs(windowNames) do
		local window = self:FindUIObject(windowName)
		if window then
			local isOpen = false
			if window:IsA("ScreenGui") then
				isOpen = window.Enabled == true
			else
				isOpen = window.Visible == true
			end
			
			if isOpen then
				anyWindowOpen = true
				break
			end
		end
	end
	
	if anyWindowOpen then
		return
	end
	
	self.isTutorialTemporarilyHidden = false
	
	if self.tutorialGui then
		self.tutorialGui.Enabled = true
	end
	
	if self.tutorialContainer then
		local TweenUI = self.Utilities and self.Utilities.TweenUI
		if TweenUI and TweenUI.FadeIn then
			TweenUI.FadeIn(self.tutorialContainer, 0.2)
		else
			self.tutorialContainer.Visible = true
		end
	end
end

-- Disable all ProximityPrompts in workspace when tutorial overlay is shown
function TutorialHandler:DisableAllProximityPrompts()
	local workspace = game:GetService("Workspace")
	
	-- Find all ProximityPrompts in workspace
	local allPrompts = {}
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			table.insert(allPrompts, descendant)
		end
	end
	
	-- Store original state and disable prompts
	for _, prompt in ipairs(allPrompts) do
		-- Store original state if not already stored
		if not self.proximityPromptsState[prompt] then
			self.proximityPromptsState[prompt] = prompt.Enabled
		end
		-- Disable the prompt safely
		local success, err = pcall(function()
			prompt.Enabled = false
		end)
		if not success then
			warn("TutorialHandler: Failed to disable ProximityPrompt:", err)
		end
	end
	
	-- Listen for new prompts being added while tutorial is active
	if not self.proximityPromptListener then
		self.proximityPromptListener = workspace.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("ProximityPrompt") then
				-- Store original state and disable new prompt
				if not self.proximityPromptsState[descendant] then
					self.proximityPromptsState[descendant] = descendant.Enabled
				end
				local success, err = pcall(function()
					descendant.Enabled = false
				end)
				if not success then
					warn("TutorialHandler: Failed to disable new ProximityPrompt:", err)
				end
			end
		end)
	end
end

-- Restore all ProximityPrompts to their original state when tutorial overlay is hidden
function TutorialHandler:RestoreAllProximityPrompts()
	-- Restore all stored prompts
	for prompt, originalState in pairs(self.proximityPromptsState) do
		if prompt and prompt.Parent then
			local success, err = pcall(function()
				prompt.Enabled = originalState
			end)
			if not success then
				warn("TutorialHandler: Failed to restore ProximityPrompt:", err)
			end
		end
	end
	
	-- Clear stored state
	self.proximityPromptsState = {}
	
	-- Disconnect listener
	if self.proximityPromptListener then
		self.proximityPromptListener:Disconnect()
		self.proximityPromptListener = nil
	end
end

return TutorialHandler

