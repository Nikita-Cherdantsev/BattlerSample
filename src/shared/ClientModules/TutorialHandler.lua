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

-- Module
local TutorialHandler = {}

-- State
TutorialHandler.Connections = {}
TutorialHandler._initialized = false
TutorialHandler.currentStep = nil
TutorialHandler.currentStepIndex = -1  -- -1 означает "еще не инициализирован"
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
	-- Prevent multiple initializations
	if self._initialized then
		print("📚 TutorialHandler: Already initialized, skipping")
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
	self.currentStepIndex = -1  -- -1 означает "еще не инициализирован", чтобы первое обновление всегда обрабатывалось
	self.showingStepIndex = nil  -- Index of the step currently being shown (different from currentStepIndex which is last completed)
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
	self.isTutorialTemporarilyHidden = false  -- Флаг для временного скрытия
	self.windowVisibilityConnections = {}  -- Соединения для отслеживания окон
	self.fadeInTweens = {}  -- Track fade-in tweens to cancel duplicates
	self.conditionalTargets = {}  -- Store computed targets for "conditional" placeholders
	self.pathObjects = {}  -- Store path objects (Beam, Attachments, Parts) for cleanup
	self.beamTemplate = nil  -- Beam template from cloned Tutorial GUI (for cloning)
	
	-- Setup UI
	self:SetupUI()
	
	-- Setup tutorial template from ReplicatedFirst
	self:SetupTutorialTemplate()
	
	-- Setup profile updated handler
	self:SetupProfileUpdatedHandler()
	
	-- Setup window/button listeners
	self:SetupEventListeners()
	
	-- Request tutorial progress from server (will be called after a delay in SetupProfileUpdatedHandler)
	-- Also, tutorial will start automatically when profile is received via ProfileUpdated
	
	self._initialized = true
	print("✅ TutorialHandler initialized successfully!")
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
		print("📚 TutorialHandler: Reusing existing Tutorial ScreenGui")
		self.tutorialGui = existingTutorial
	else
		-- Clone tutorial template from ReplicatedFirst
		local ReplicatedFirst = game:GetService("ReplicatedFirst")
		
		-- Wait for Instances folder
		local instancesFolder = ReplicatedFirst:WaitForChild("Instances", 10)
		if not instancesFolder then
			warn("TutorialHandler: ReplicatedFirst.Instances not found")
			return
		end
		
		-- Wait for Tutorial template
		local tutorialTemplate = instancesFolder:WaitForChild("Tutorial", 10)
		if not tutorialTemplate then
			warn("TutorialHandler: Tutorial template not found in ReplicatedFirst.Instances")
			return
		end
		
		-- Clone the template
		self.tutorialGui = tutorialTemplate:Clone()
		self.tutorialGui.Name = "Tutorial"
		self.tutorialGui.ResetOnSpawn = false
		self.tutorialGui.Parent = playerGui
		print("📚 TutorialHandler: Created new Tutorial ScreenGui")
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
	task.spawn(function()
		task.wait(1)  -- Wait a bit for everything to initialize
		if self._initialized then
			self:RequestTutorialProgress()
		end
	end)
end

function TutorialHandler:SetupEventListeners()
	-- Listen for window opens/closes and button clicks
	-- This will be used to check start/complete conditions
	
	-- We'll check conditions when showing steps
	-- For now, we'll use a polling approach or event-based system
	-- depending on what events are available
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
	print("📚 TutorialHandler: HandleTutorialProgress called with step:", newStep, "current completed:", self.currentStepIndex, "showing:", self.showingStepIndex)
	
	-- If tutorial step is reset to 0 (profile reset), clear tutorial state
	if newStep == 0 and self.currentStepIndex ~= 0 then
		print("📚 TutorialHandler: Tutorial reset detected (step 0), clearing tutorial state")
		self:HideTutorialStep()
		self.currentStepIndex = -1  -- Reset to allow processing
	end
	
	-- Only update if step actually changed (allow first update when currentStepIndex is -1)
	-- Also check if we're already processing this step
	if self.currentStepIndex ~= -1 and self.currentStepIndex == newStep then
		-- Check if we're already showing the next step
		local nextStepIndex = TutorialConfig.GetNextStepIndex(self.currentStepIndex)
		if self.showingStepIndex == nextStepIndex and self.isTutorialActive then
			print("📚 TutorialHandler: Step unchanged and already showing, skipping")
			return
		end
	end
	
	-- Update last completed step
	self.currentStepIndex = newStep
	
	-- Check if tutorial is complete
	if TutorialConfig.IsComplete(self.currentStepIndex) then
		print("📚 TutorialHandler: Tutorial is complete")
		self:HideTutorialStep()
		return
	end
	
	-- Get next step
	local nextStepIndex = TutorialConfig.GetNextStepIndex(self.currentStepIndex)
	print("📚 TutorialHandler: Next step index:", nextStepIndex)
	if not nextStepIndex then
		print("📚 TutorialHandler: No next step, hiding tutorial")
		self:HideTutorialStep()
		return
	end
	
	-- Don't show if we're already showing this step and tutorial is active
	if self.showingStepIndex == nextStepIndex and self.isTutorialActive then
		print("📚 TutorialHandler: Already showing step", nextStepIndex, "skipping")
		return
	end
	
	-- Wait for loading screen to finish before showing tutorial
	task.spawn(function()
		self:WaitForLoadingScreenToFinish()
		-- Double-check we're still supposed to show this step
		-- Only skip if tutorial is active AND showing the same step
		if self.isTutorialActive and self.showingStepIndex == nextStepIndex then
			print("📚 TutorialHandler: Step already showing after loading screen wait, skipping")
			return
		end
		-- Now proceed with showing the tutorial step
		self:ProcessTutorialStep(nextStepIndex)
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
		-- Wait for loading screen to be disabled
		if loadingScreen.Enabled then
			print("📚 TutorialHandler: Waiting for loading screen to finish...")
			local changedSignal = loadingScreen:GetPropertyChangedSignal("Enabled")
			while loadingScreen.Enabled do
				changedSignal:Wait()
			end
			-- Wait a bit more to ensure fade-out animation completes
			task.wait(0.5)
			print("📚 TutorialHandler: Loading screen finished, proceeding with tutorial")
		end
	else
		-- Loading screen not found, wait a bit anyway
		task.wait(1)
	end
end

function TutorialHandler:ProcessTutorialStep(nextStepIndex)
	local TutorialConfig = require(game.ReplicatedStorage.Modules.Tutorial.TutorialConfig)
	
	-- Get step data
	local step = TutorialConfig.GetStep(nextStepIndex)
	if not step then
		print("📚 TutorialHandler: Step not found:", nextStepIndex)
		return
	end
	
	print("📚 TutorialHandler: Next step:", nextStepIndex, "startCondition:", step.startCondition.type, step.startCondition.target)
	
	-- Check start condition
	local startConditionMet = self:CheckStartCondition(step)
	if not startConditionMet then
		print("📚 TutorialHandler: Start condition not met, waiting...")
		self:WaitForStepCondition(step, nextStepIndex)
		return
	end
	
	-- Show tutorial step (pass step index, not step table)
	self:ShowTutorialStep(nextStepIndex)
end

function TutorialHandler:CheckStartCondition(step)
	if not step or not step.startCondition then
		return false
	end
	
	local condition = step.startCondition
	
	if condition.type == "window_open" then
		-- Check if window is open
		local window = self:FindUIObject(condition.target)
		if not window then
			-- Only log once per second to avoid spam
			local now = tick()
			if not self._lastNotFoundLog or (now - self._lastNotFoundLog) > 1 then
				print("📚 TutorialHandler: Window not found:", condition.target)
				self._lastNotFoundLog = now
			end
			return false
		end
		
		-- For ScreenGui, check Enabled; for other GuiObjects, check Visible
		local isOpen = false
		if window:IsA("ScreenGui") then
			isOpen = window.Enabled == true
		else
			isOpen = window.Visible == true
		end
		
		-- Only log when state changes or first check
		local logKey = "window_" .. condition.target
		local lastState = self._windowStates and self._windowStates[logKey]
		if lastState ~= isOpen then
			print("📚 TutorialHandler: Window", condition.target, "isOpen:", isOpen, "type:", window.ClassName)
			if not self._windowStates then
				self._windowStates = {}
			end
			self._windowStates[logKey] = isOpen
		end
		
		return isOpen
	elseif condition.type == "button_click" then
		-- Button clicks are handled via event listeners
		return false  -- Will be set to true when button is actually clicked
	elseif condition.type == "conditional" then
		-- Conditional conditions are handled by execute methods
		return self:CheckConditionalStartCondition(step)
	end
	
	return false
end

function TutorialHandler:CheckCompleteCondition(step)
	if not step or not step.completeCondition then
		return false
	end
	
	local condition = step.completeCondition
	
	if condition.type == "window_open" then
		local window = self:FindUIObject(condition.target)
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

function TutorialHandler:WaitForStepCondition(step, stepIndex)
	-- Wait for the start condition to be met
	if not step or not step.startCondition then
		return
	end
	
	local condition = step.startCondition
	
	-- Check if force = true in completeCondition
	local hasForce = step.completeCondition and step.completeCondition.force == true
	
	if condition.type == "window_open" then
		-- Check condition immediately first
		local conditionMet = self:CheckStartCondition(step)
		
		if conditionMet then
			-- Condition is already met, show step immediately
			print("📚 TutorialHandler: Window condition already met, showing step", stepIndex)
			if stepIndex then
				self:ShowTutorialStep(stepIndex)
			end
			return
		end
		
		-- If force = true and condition not met, complete step immediately
		if hasForce then
			print("📚 TutorialHandler: Window condition not met, but force=true, completing step", stepIndex, "immediately")
			if stepIndex then
				-- Complete the step without showing it
				if self.NetworkClient and self.NetworkClient.requestCompleteTutorialStep then
					self.NetworkClient.requestCompleteTutorialStep(stepIndex)
				else
					warn("📚 TutorialHandler: NetworkClient.requestCompleteTutorialStep not available")
				end
			end
			return
		end
		
		-- Otherwise, wait for window to open using event-based approach
		print("📚 TutorialHandler: Waiting for window to open:", condition.target)
		
		-- Try to find window immediately first (without waiting)
		local window = self:FindUIObject(condition.target)
		
		if window then
			-- Window exists, set up property change listener immediately
			local propertyName = window:IsA("ScreenGui") and "Enabled" or "Visible"
			local connection = window:GetPropertyChangedSignal(propertyName):Connect(function()
				if self:CheckStartCondition(step) then
					print("📚 TutorialHandler: Window condition met via event, showing step", stepIndex)
					if stepIndex then
						self:ShowTutorialStep(stepIndex)
					end
					if connection then
						connection:Disconnect()
					end
				end
			end)
			table.insert(self.Connections, connection)
			
			-- Check immediately in case window is already open
			if self:CheckStartCondition(step) then
				print("📚 TutorialHandler: Window condition already met, showing step", stepIndex)
				if stepIndex then
					self:ShowTutorialStep(stepIndex)
				end
				if connection then
					connection:Disconnect()
				end
			end
		else
			-- Window doesn't exist yet, use WaitForUIObject in a separate thread
			task.spawn(function()
				local window = self:WaitForUIObject(condition.target, 10)
				
				if window then
					-- Set up property change listener (event-based, no polling)
					local propertyName = window:IsA("ScreenGui") and "Enabled" or "Visible"
					local connection = window:GetPropertyChangedSignal(propertyName):Connect(function()
						if self:CheckStartCondition(step) then
							print("📚 TutorialHandler: Window condition met via event, showing step", stepIndex)
							if stepIndex then
								self:ShowTutorialStep(stepIndex)
							end
							if connection then
								connection:Disconnect()
							end
						end
					end)
					table.insert(self.Connections, connection)
					
					-- Check immediately in case window is already open
					if self:CheckStartCondition(step) then
						print("📚 TutorialHandler: Window condition already met, showing step", stepIndex)
						if stepIndex then
							self:ShowTutorialStep(stepIndex)
						end
						if connection then
							connection:Disconnect()
						end
					end
				else
					warn("📚 TutorialHandler: Window not found:", condition.target)
				end
			end)
		end
	elseif condition.type == "button_click" then
		-- If force = true and condition not met, complete step immediately
		if hasForce then
			print("📚 TutorialHandler: Button click condition not met, but force=true, completing step", stepIndex, "immediately")
			if stepIndex then
				-- Complete the step without showing it
				if self.NetworkClient and self.NetworkClient.requestCompleteTutorialStep then
					self.NetworkClient.requestCompleteTutorialStep(stepIndex)
				else
					warn("📚 TutorialHandler: NetworkClient.requestCompleteTutorialStep not available")
				end
			end
			return
		end
		
		-- Set up button click listener
		local button = self:FindUIObject(condition.target)
		if button and (button:IsA("GuiButton") or button:IsA("TextButton") or button:IsA("ImageButton")) then
			-- Button already exists, set up listener
			local connection = button.MouseButton1Click:Connect(function()
				if stepIndex and self._initialized then
					self:ShowTutorialStep(stepIndex)
				end
				if connection then
					connection:Disconnect()
				end
			end)
			table.insert(self.Connections, connection)
		else
			-- Wait for button to appear using DescendantAdded (event-based, no polling)
			task.spawn(function()
				-- Extract button name from path (last part)
				local pathParts = {}
				for part in string.gmatch(condition.target, "([^%.]+)") do
					table.insert(pathParts, part)
				end
				
				if #pathParts == 0 then
					warn("📚 TutorialHandler: Invalid button path:", condition.target)
					return
				end
				
				local buttonName = pathParts[#pathParts]
				
				-- Find parent container (UI root or specific parent)
				local parent = self.UI
				
				-- Navigate to parent (all but last part)
				for i = 1, #pathParts - 1 do
					if parent then
						parent = parent:FindFirstChild(pathParts[i])
					end
				end
				
				if parent then
					-- Listen for descendant added (event-based)
					local connection = parent.DescendantAdded:Connect(function(descendant)
						if descendant.Name == buttonName and 
						   (descendant:IsA("GuiButton") or descendant:IsA("TextButton") or descendant:IsA("ImageButton")) then
							-- Found the button, set up click listener
							local clickConnection = descendant.MouseButton1Click:Connect(function()
								if stepIndex and self._initialized then
									self:ShowTutorialStep(stepIndex)
								end
								if clickConnection then
									clickConnection:Disconnect()
								end
								if connection then
									connection:Disconnect()
								end
							end)
							table.insert(self.Connections, clickConnection)
							table.insert(self.Connections, connection)
						end
					end)
					
					-- Also check existing descendants immediately
					local existingButton = parent:FindFirstChild(buttonName, true)
					if existingButton and (existingButton:IsA("GuiButton") or existingButton:IsA("TextButton") or existingButton:IsA("ImageButton")) then
						local clickConnection = existingButton.MouseButton1Click:Connect(function()
							if stepIndex and self._initialized then
								self:ShowTutorialStep(stepIndex)
							end
							if clickConnection then
								clickConnection:Disconnect()
							end
							if connection then
								connection:Disconnect()
							end
						end)
						table.insert(self.Connections, clickConnection)
						connection:Disconnect()
					end
				else
					warn("📚 TutorialHandler: Parent container not found for button:", condition.target)
				end
			end)
		end
	elseif condition.type == "conditional" then
		-- Wait for conditional condition
		self:WaitForConditionalCondition(step, stepIndex)
	end
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
	
	print("📚 TutorialHandler: Waiting for conditional condition:", step.startCondition.condition)
	
	-- Check if force = true in completeCondition
	local hasForce = step.completeCondition and step.completeCondition.force == true
	
	-- Check condition immediately first
	local conditionMet = self:CheckConditionalStartCondition(step)
	
	if conditionMet then
		-- Condition is already met, show step immediately
		print("📚 TutorialHandler: Conditional condition already met, showing step", stepIndex)
		if stepIndex then
			self:ShowTutorialStep(stepIndex)
		end
		return
	end
	
	-- If force = true and condition not met, complete step immediately
	if hasForce then
		print("📚 TutorialHandler: Conditional condition not met, but force=true, completing step", stepIndex, "immediately")
		if stepIndex then
			-- Complete the step without showing it
			if self.NetworkClient and self.NetworkClient.requestCompleteTutorialStep then
				self.NetworkClient.requestCompleteTutorialStep(stepIndex)
			else
				warn("📚 TutorialHandler: NetworkClient.requestCompleteTutorialStep not available")
			end
		end
		return
	end
	
	-- Otherwise, wait for condition to be met using event-based approach
	-- For playtime_reward_claimable, also listen for Playtime window visibility changes
	local conditionName = step.startCondition.condition
	if conditionName == "playtime_reward_claimable" then
		-- Set up listener for Playtime window visibility
		task.spawn(function()
			local playtimeWindow = self:WaitForUIObject("Playtime", 10)
			if playtimeWindow then
				-- Listen for visibility changes
				local visibilityConnection = playtimeWindow:GetPropertyChangedSignal("Visible"):Connect(function()
					if self:CheckConditionalStartCondition(step) then
						print("📚 TutorialHandler: Playtime reward claimable condition met via window visibility, showing step", stepIndex)
						if stepIndex then
							self:ShowTutorialStep(stepIndex)
						end
						if visibilityConnection then
							visibilityConnection:Disconnect()
						end
					end
				end)
				table.insert(self.Connections, visibilityConnection)
				
				-- Check immediately in case window is already visible
				if self:CheckConditionalStartCondition(step) then
					print("📚 TutorialHandler: Playtime reward claimable condition already met, showing step", stepIndex)
					if stepIndex then
						self:ShowTutorialStep(stepIndex)
					end
					if visibilityConnection then
						visibilityConnection:Disconnect()
					end
				end
			end
		end)
	elseif conditionName == "playtime_reward_available" then
		-- Set up listeners for LeftPanel visibility and marker visibility changes
		task.spawn(function()
			local leftPanel = self:WaitForUIObject("LeftPanel", 10)
			if leftPanel then
				local panelVisibilityConnection = nil
				local markerVisibilityConnection = nil
				
				-- Listen for LeftPanel visibility changes
				panelVisibilityConnection = leftPanel:GetPropertyChangedSignal("Visible"):Connect(function()
					if self:CheckConditionalStartCondition(step) then
						print("📚 TutorialHandler: Playtime reward available condition met via LeftPanel visibility, showing step", stepIndex)
						if stepIndex then
							self:ShowTutorialStep(stepIndex)
						end
						if panelVisibilityConnection then
							panelVisibilityConnection:Disconnect()
						end
						if markerVisibilityConnection then
							markerVisibilityConnection:Disconnect()
						end
					end
				end)
				table.insert(self.Connections, panelVisibilityConnection)
				
				-- Also listen for marker visibility changes
				local btnPlaytime = leftPanel:FindFirstChild("BtnPlaytime")
				if btnPlaytime then
					local marker = btnPlaytime:FindFirstChild("Marker")
					if marker then
						markerVisibilityConnection = marker:GetPropertyChangedSignal("Visible"):Connect(function()
							if self:CheckConditionalStartCondition(step) then
								print("📚 TutorialHandler: Playtime reward available condition met via marker visibility, showing step", stepIndex)
								if stepIndex then
									self:ShowTutorialStep(stepIndex)
								end
								if panelVisibilityConnection then
									panelVisibilityConnection:Disconnect()
								end
								if markerVisibilityConnection then
									markerVisibilityConnection:Disconnect()
								end
							end
						end)
						table.insert(self.Connections, markerVisibilityConnection)
						
						-- Check immediately in case marker is already visible
						if marker.Visible and self:CheckConditionalStartCondition(step) then
							print("📚 TutorialHandler: Playtime reward available condition already met, showing step", stepIndex)
							if stepIndex then
								self:ShowTutorialStep(stepIndex)
							end
							if panelVisibilityConnection then
								panelVisibilityConnection:Disconnect()
							end
							if markerVisibilityConnection then
								markerVisibilityConnection:Disconnect()
							end
						end
					else
						-- Wait for marker to appear
						local markerConnection = btnPlaytime.ChildAdded:Connect(function(child)
							if child.Name == "Marker" then
								markerVisibilityConnection = child:GetPropertyChangedSignal("Visible"):Connect(function()
									if self:CheckConditionalStartCondition(step) then
										print("📚 TutorialHandler: Playtime reward available condition met via marker visibility, showing step", stepIndex)
										if stepIndex then
											self:ShowTutorialStep(stepIndex)
										end
										if panelVisibilityConnection then
											panelVisibilityConnection:Disconnect()
										end
										if markerVisibilityConnection then
											markerVisibilityConnection:Disconnect()
										end
									end
								end)
								table.insert(self.Connections, markerVisibilityConnection)
								
								-- Check immediately
								if child.Visible and self:CheckConditionalStartCondition(step) then
									print("📚 TutorialHandler: Playtime reward available condition already met, showing step", stepIndex)
									if stepIndex then
										self:ShowTutorialStep(stepIndex)
									end
									if panelVisibilityConnection then
										panelVisibilityConnection:Disconnect()
									end
									if markerVisibilityConnection then
										markerVisibilityConnection:Disconnect()
									end
								end
								
								if markerConnection then
									markerConnection:Disconnect()
								end
							end
						end)
						table.insert(self.Connections, markerConnection)
					end
				end
				
				-- Check immediately in case LeftPanel is already visible
				if leftPanel.Visible and self:CheckConditionalStartCondition(step) then
					print("📚 TutorialHandler: Playtime reward available condition already met, showing step", stepIndex)
					if stepIndex then
						self:ShowTutorialStep(stepIndex)
					end
					if panelVisibilityConnection then
						panelVisibilityConnection:Disconnect()
					end
				end
			end
		end)
	elseif conditionName == "lootbox_claim_available" then
		-- Set up listeners for LootboxOpening window and BtnClaim visibility changes
		task.spawn(function()
			local lootboxWindow = self:WaitForUIObject("LootboxOpening", 10)
			if lootboxWindow then
				local windowVisibilityConnection = nil
				local buttonVisibilityConnection = nil
				local buttonActiveConnection = nil
				
				-- Listen for window visibility changes
				windowVisibilityConnection = lootboxWindow:GetPropertyChangedSignal("Visible"):Connect(function()
					if self:CheckConditionalStartCondition(step) then
						print("📚 TutorialHandler: Lootbox claim available condition met via window visibility, showing step", stepIndex)
						if stepIndex then
							self:ShowTutorialStep(stepIndex)
						end
						if windowVisibilityConnection then
							windowVisibilityConnection:Disconnect()
						end
						if buttonVisibilityConnection then
							buttonVisibilityConnection:Disconnect()
						end
						if buttonActiveConnection then
							buttonActiveConnection:Disconnect()
						end
					end
				end)
				table.insert(self.Connections, windowVisibilityConnection)
				
				-- Also listen for BtnClaim visibility and active changes
				local btnClaim = lootboxWindow:FindFirstChild("BtnClaim")
				if btnClaim then
					buttonVisibilityConnection = btnClaim:GetPropertyChangedSignal("Visible"):Connect(function()
						if self:CheckConditionalStartCondition(step) then
							print("📚 TutorialHandler: Lootbox claim available condition met via button visibility, showing step", stepIndex)
							if stepIndex then
								self:ShowTutorialStep(stepIndex)
							end
							if windowVisibilityConnection then
								windowVisibilityConnection:Disconnect()
							end
							if buttonVisibilityConnection then
								buttonVisibilityConnection:Disconnect()
							end
							if buttonActiveConnection then
								buttonActiveConnection:Disconnect()
							end
						end
					end)
					table.insert(self.Connections, buttonVisibilityConnection)
					
					buttonActiveConnection = btnClaim:GetPropertyChangedSignal("Active"):Connect(function()
						if self:CheckConditionalStartCondition(step) then
							print("📚 TutorialHandler: Lootbox claim available condition met via button active, showing step", stepIndex)
							if stepIndex then
								self:ShowTutorialStep(stepIndex)
							end
							if windowVisibilityConnection then
								windowVisibilityConnection:Disconnect()
							end
							if buttonVisibilityConnection then
								buttonVisibilityConnection:Disconnect()
							end
							if buttonActiveConnection then
								buttonActiveConnection:Disconnect()
							end
						end
					end)
					table.insert(self.Connections, buttonActiveConnection)
					
					-- Check immediately in case button is already visible and active
					if btnClaim.Visible and btnClaim.Active and self:CheckConditionalStartCondition(step) then
						print("📚 TutorialHandler: Lootbox claim available condition already met, showing step", stepIndex)
						if stepIndex then
							self:ShowTutorialStep(stepIndex)
						end
						if windowVisibilityConnection then
							windowVisibilityConnection:Disconnect()
						end
						if buttonVisibilityConnection then
							buttonVisibilityConnection:Disconnect()
						end
						if buttonActiveConnection then
							buttonActiveConnection:Disconnect()
						end
					end
				else
					-- Wait for BtnClaim to appear
					local buttonConnection = lootboxWindow.ChildAdded:Connect(function(child)
						if child.Name == "BtnClaim" then
							buttonVisibilityConnection = child:GetPropertyChangedSignal("Visible"):Connect(function()
								if self:CheckConditionalStartCondition(step) then
									print("📚 TutorialHandler: Lootbox claim available condition met via button visibility, showing step", stepIndex)
									if stepIndex then
										self:ShowTutorialStep(stepIndex)
									end
									if windowVisibilityConnection then
										windowVisibilityConnection:Disconnect()
									end
									if buttonVisibilityConnection then
										buttonVisibilityConnection:Disconnect()
									end
									if buttonActiveConnection then
										buttonActiveConnection:Disconnect()
									end
								end
							end)
							table.insert(self.Connections, buttonVisibilityConnection)
							
							buttonActiveConnection = child:GetPropertyChangedSignal("Active"):Connect(function()
								if self:CheckConditionalStartCondition(step) then
									print("📚 TutorialHandler: Lootbox claim available condition met via button active, showing step", stepIndex)
									if stepIndex then
										self:ShowTutorialStep(stepIndex)
									end
									if windowVisibilityConnection then
										windowVisibilityConnection:Disconnect()
									end
									if buttonVisibilityConnection then
										buttonVisibilityConnection:Disconnect()
									end
									if buttonActiveConnection then
										buttonActiveConnection:Disconnect()
									end
								end
							end)
							table.insert(self.Connections, buttonActiveConnection)
							
							-- Check immediately
							if child.Visible and child.Active and self:CheckConditionalStartCondition(step) then
								print("📚 TutorialHandler: Lootbox claim available condition already met, showing step", stepIndex)
								if stepIndex then
									self:ShowTutorialStep(stepIndex)
								end
								if windowVisibilityConnection then
									windowVisibilityConnection:Disconnect()
								end
								if buttonVisibilityConnection then
									buttonVisibilityConnection:Disconnect()
								end
								if buttonActiveConnection then
									buttonActiveConnection:Disconnect()
								end
							end
							
							if buttonConnection then
								buttonConnection:Disconnect()
							end
						end
					end)
					table.insert(self.Connections, buttonConnection)
				end
				
				-- Check immediately in case window is already visible
				if lootboxWindow.Visible and self:CheckConditionalStartCondition(step) then
					print("📚 TutorialHandler: Lootbox claim available condition already met, showing step", stepIndex)
					if stepIndex then
						self:ShowTutorialStep(stepIndex)
					end
					if windowVisibilityConnection then
						windowVisibilityConnection:Disconnect()
					end
				end
			end
		end)
	end
	
	-- Subscribe to ProfileUpdated for tracking changes (no polling needed)
	if self.NetworkClient then
		local profileConnection = self.NetworkClient.onProfileUpdated(function(payload)
			if self:CheckConditionalStartCondition(step) then
				print("📚 TutorialHandler: Conditional condition met via event, showing step", stepIndex)
				if stepIndex then
					self:ShowTutorialStep(stepIndex)
				end
				if profileConnection then
					profileConnection:Disconnect()
				end
			end
		end)
		table.insert(self.Connections, profileConnection)
	else
		warn("📚 TutorialHandler: NetworkClient not available for conditional condition tracking")
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
	
	-- Store the target for "conditional" replacement
	-- Build path from UI root to card instance
	local pathParts = {}
	local current = cardInstance
	local uiRoot = self.UI
	
	while current and current ~= uiRoot and current.Parent do
		table.insert(pathParts, 1, current.Name)
		current = current.Parent
	end
	
	-- If we reached UI root, build the path
	if current == uiRoot then
		local relativePath = table.concat(pathParts, ".")
		self.conditionalTargets = {
			highlight = relativePath,
			arrow = relativePath,
			complete = relativePath .. ".BtnInfo"
		}
		return true
	else
		-- Fallback: use FindUIObject approach with card name
		local cardName = "Card_" .. targetCard.cardId
		-- Try to find using the card name directly
		local foundCard = self:FindUIObject(cardName)
		if foundCard then
			-- Use a simpler path approach
			self.conditionalTargets = {
				highlight = cardName,
				arrow = cardName,
				complete = cardName .. ".BtnInfo"
			}
			return true
		end
	end
	
	return false
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
		warn("📚 TutorialHandler: NotificationMarkerHandler not available")
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
function TutorialHandler:HandleClaimPlaytimeReward(step)
	-- Check if Playtime window is open and visible
	local playtimeWindow = self:FindUIObject("Playtime")
	if not playtimeWindow or not playtimeWindow.Visible then
		return false
	end
	
	-- Get PlaytimeHandler to check reward availability
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local success, PlaytimeHandler = pcall(function()
		return require(ReplicatedStorage.ClientModules.PlaytimeHandler)
	end)
	
	-- Find List frame with rewards
	local listFrame = playtimeWindow:FindFirstChild("List")
	if not listFrame then
		return false
	end
	
	-- Find first available reward with claimable button
	local targetBtnClaim = nil
	local targetRewardIndex = nil
	
	-- Check rewards from 1 to 7
	for i = 1, 7 do
		local rewardFrame = listFrame:FindFirstChild("Reward" .. i)
		if rewardFrame then
			-- Check if reward frame is visible
			if rewardFrame.Visible then
				local content = rewardFrame:FindFirstChild("Content")
				if content then
					local btnClaim = content:FindFirstChild("BtnClaim")
					if btnClaim and btnClaim.Visible and btnClaim.Active then
						-- Check if reward is available (if PlaytimeHandler is available)
						local isAvailable = true
						if success and PlaytimeHandler then
							-- Check if reward is available and not claimed
							isAvailable = PlaytimeHandler:IsRewardAvailable(i) and not PlaytimeHandler:IsRewardClaimed(i)
						end
						
						if isAvailable then
							targetBtnClaim = btnClaim
							targetRewardIndex = i
							break
						end
					end
				end
			end
		end
	end
	
	if not targetBtnClaim then
		return false
	end
	
	-- Store the target for "conditional" replacement
	-- Build path from UI root to BtnClaim
	local pathParts = {}
	local current = targetBtnClaim
	local uiRoot = self.UI
	
	while current and current ~= uiRoot and current.Parent do
		table.insert(pathParts, 1, current.Name)
		current = current.Parent
	end
	
	-- If we reached UI root, build the path
	if current == uiRoot then
		local relativePath = table.concat(pathParts, ".")
		self.conditionalTargets = {
			highlight = relativePath,
			arrow = relativePath,
			complete = relativePath
		}
		return true
	else
		-- Fallback: use FindUIObject approach
		local rewardName = "Reward" .. targetRewardIndex
		local fallbackPath = "Playtime.List." .. rewardName .. ".Content.BtnClaim"
		local foundBtn = self:FindUIObject(fallbackPath)
		if foundBtn then
			self.conditionalTargets = {
				highlight = fallbackPath,
				arrow = fallbackPath,
				complete = fallbackPath
			}
			return true
		end
	end
	
	return false
end

-- Helper: Get relative path from UI root
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

function TutorialHandler:ShowTutorialStep(stepIndex)
	local TutorialConfig = require(game.ReplicatedStorage.Modules.Tutorial.TutorialConfig)
	
	-- Ensure stepIndex is a number
	if type(stepIndex) ~= "number" then
		warn("TutorialHandler: ShowTutorialStep expects a number (step index), got:", type(stepIndex))
		return
	end
	
	-- Prevent showing the same step multiple times
	if self.isTutorialActive and self.showingStepIndex == stepIndex then
		print("📚 TutorialHandler: Step", stepIndex, "already showing, skipping duplicate call")
		return
	end
	
	local step = TutorialConfig.GetStep(stepIndex)
	
	if not step then
		warn("TutorialHandler: Step " .. stepIndex .. " not found")
		return
	end
	
	print("📚 TutorialHandler: Showing tutorial step", stepIndex)
	
	-- Hide previous tutorial step if any
	if self.isTutorialActive then
		print("📚 TutorialHandler: Hiding previous tutorial step before showing new one")
		self:HideTutorialStep()
		-- Wait a tiny bit for hide animation to start
		task.wait(0.05)
	end
	
	self.currentStep = step
	self.showingStepIndex = stepIndex  -- Store the index of the step currently being shown
	-- Note: self.currentStepIndex stores the last completed step (from profile), not the currently showing step
	self.isTutorialActive = true
	
	-- Проверить видимость окна StartBattle перед показом туториала
	if step.startCondition and step.startCondition.target == "StartBattle" then
		local startBattleWindow = self:FindUIObject("StartBattle")
		if not startBattleWindow or not startBattleWindow.Visible then
			print("📚 TutorialHandler: StartBattle window is not open, skipping tutorial")
			return
		end
		
		-- Временно отключить BtnStart до появления туториала
		local startButton = self:FindUIObject("StartBattle.Buttons.BtnStart")
		if startButton and startButton:IsA("GuiButton") then
			print("📚 TutorialHandler: Temporarily disabling BtnStart until tutorial appears")
			startButton.Active = false
			-- Сохранить ссылку для последующего включения
			self._tutorialBlockedButton = startButton
		end
	end
	
	-- Enable tutorial GUI
	if self.tutorialGui then
		self.tutorialGui.Enabled = true
		print("📚 TutorialHandler: Tutorial GUI enabled")
	else
		warn("📚 TutorialHandler: Tutorial GUI is nil!")
	end
	
	-- Create all tutorial elements first (before animation, so TweenUI can capture their base transparency values)
	-- Show highlights (replace "conditional" with computed targets)
	if step.highlightObjects and #step.highlightObjects > 0 then
		local highlightTargets = {}
		for _, objName in ipairs(step.highlightObjects) do
			if objName == "conditional" then
				local conditionalTarget = self.conditionalTargets and self.conditionalTargets.highlight
				if conditionalTarget then
					table.insert(highlightTargets, conditionalTarget)
				else
					warn("📚 TutorialHandler: 'conditional' in highlightObjects but no target computed")
				end
			else
				table.insert(highlightTargets, objName)
			end
		end
		if #highlightTargets > 0 then
			print("📚 TutorialHandler: Highlighting objects:", table.concat(highlightTargets, ", "))
			self:HighlightObjects(highlightTargets)
		end
	end
	
	-- Show arrow (replace "conditional" with computed target)
	if step.arrow and step.arrow.objectName and step.arrow.side then
		local arrowTarget = step.arrow.objectName
		if arrowTarget == "conditional" then
			arrowTarget = self.conditionalTargets and self.conditionalTargets.arrow
			if not arrowTarget then
				warn("📚 TutorialHandler: 'conditional' in arrow.objectName but no target computed")
				arrowTarget = nil
			end
		end
		if arrowTarget then
			print("📚 TutorialHandler: Showing arrow for", arrowTarget, "side:", step.arrow.side)
			self:ShowArrow(arrowTarget, step.arrow.side)
		else
			print("📚 TutorialHandler: No arrow to show or arrow config incomplete")
		end
	else
		print("📚 TutorialHandler: No arrow to show or arrow config incomplete")
	end
	
	-- Show path if specified
	if step.path then
		print("📚 TutorialHandler: Showing path to", step.path)
		self:ShowPath(step.path)
	end
	
	-- Show text
	if step.text then
		print("📚 TutorialHandler: Showing text:", step.text)
		self:ShowText(step.text)
	end
	
	-- Show tutorial with animation (after all elements are created, so TweenUI captures their base values)
	self:ShowTutorialWithAnimation()
	
	-- Set up complete condition listener
	self:SetupCompleteConditionListener(step)
end

function TutorialHandler:HideTutorialStep()
	self.isTutorialActive = false
	self.isTutorialTemporarilyHidden = false  -- Сбросить флаг
	self.currentStep = nil
	self.showingStepIndex = nil  -- Clear showing step index
	
	-- Очистить соединения для отслеживания окон
	for _, conn in ipairs(self.windowVisibilityConnections) do
		if conn then
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
	
	-- Clean up update connections (for position updates)
	for _, conn in ipairs(self.updateConnections) do
		if conn then
			conn:Disconnect()
		end
	end
	self.updateConnections = {}
	
	-- Clean up temporary tutorial connections (complete condition listeners, etc.)
	-- But keep persistent connections (ProfileUpdated) active
	for _, conn in ipairs(self.Connections) do
		if conn then
			conn:Disconnect()
		end
	end
	self.Connections = {}
	
	-- Убедиться, что BtnStart включен, если туториал был скрыт
	if self._tutorialBlockedButton then
		print("📚 TutorialHandler: Tutorial hidden, re-enabling BtnStart")
		self._tutorialBlockedButton.Active = true
		self._tutorialBlockedButton = nil
	end
end

function TutorialHandler:ShowTutorialWithAnimation()
	if not self.tutorialContainer then
		-- Fallback: just enable GUI if container not found
		if self.tutorialGui then
			self.tutorialGui.Enabled = true
		end
		return
	end
	
	local TweenUI = self.Utilities and self.Utilities.TweenUI
	if TweenUI and TweenUI.FadeIn then
		TweenUI.FadeIn(self.tutorialContainer, 0.3, function()
			-- После завершения анимации включить BtnStart обратно
			if self._tutorialBlockedButton then
				print("📚 TutorialHandler: Tutorial appeared, re-enabling BtnStart")
				self._tutorialBlockedButton.Active = true
				self._tutorialBlockedButton = nil
			end
		end)
	else
		-- Fallback: just show
		self.tutorialContainer.Visible = true
		if self.tutorialGui then
			self.tutorialGui.Enabled = true
		end
		-- Включить BtnStart сразу, если нет анимации
		if self._tutorialBlockedButton then
			print("📚 TutorialHandler: Tutorial appeared (no animation), re-enabling BtnStart")
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
		end
		return
	end
	
	local TweenUI = self.Utilities and self.Utilities.TweenUI
	if TweenUI and TweenUI.FadeOut then
		TweenUI.FadeOut(self.tutorialContainer, 0.3, function()
			if self.tutorialGui then
				self.tutorialGui.Enabled = false
			end
		end)
	else
		-- Fallback: just hide
		self.tutorialContainer.Visible = false
		if self.tutorialGui then
			self.tutorialGui.Enabled = false
		end
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
							if conn and conn.Connected then
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
								if conn and conn.Connected then
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
		if conn then
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
	
	self.highlightObjects = {}
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
				print("📚 TutorialHandler: Path target not found, waiting for:", targetName)
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
								print("📚 TutorialHandler: Path target appeared via event:", targetName)
								-- Continue with path setup
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
						warn("📚 TutorialHandler: Path parent not found:", parentPath or "Workspace")
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
				warn("📚 TutorialHandler: Path target not found in UI:", targetName)
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

function TutorialHandler:SetupCompleteConditionListener(step)
	if not step or not step.completeCondition then
		return
	end
	
	local condition = step.completeCondition
	
	-- Сохранить оригинальное значение target для проверки
	local originalTarget = condition.target
	
	-- Resolve "conditional" target
	local target = condition.target
	if target == "conditional" then
		-- For prompt_click, get target from path
		if condition.type == "prompt_click" and step.path then
			target = step.path
		else
			-- Get from conditionalTargets
			target = self.conditionalTargets and self.conditionalTargets.complete
			if not target then
				warn("📚 TutorialHandler: 'conditional' in completeCondition.target but no target computed")
				return
			end
		end
	end
	
	-- Если это prompt_click с conditional target, настроить отслеживание окон
	if condition.type == "prompt_click" and originalTarget == "conditional" then
		print("📚 TutorialHandler: Setting up window visibility tracking for prompt_click with conditional target")
		self:SetupWindowVisibilityTracking(step, stepIndex)
	end
	
	if condition.type == "window_open" then
		-- Use event-based approach instead of polling
		task.spawn(function()
			-- Find window using event-based waiting
			local window = self:WaitForUIObject(target, 10)
			
			if window then
				-- Set up property change listener
				local propertyName = window:IsA("ScreenGui") and "Enabled" or "Visible"
				local connection = window:GetPropertyChangedSignal(propertyName):Connect(function()
					if self:CheckCompleteCondition(step) then
						self:CompleteCurrentStep()
						if connection then
							connection:Disconnect()
						end
					end
				end)
				table.insert(self.Connections, connection)
				
				-- Check immediately in case window is already open
				if self:CheckCompleteCondition(step) then
					self:CompleteCurrentStep()
					if connection then
						connection:Disconnect()
					end
				end
			else
				warn("📚 TutorialHandler: Window not found for complete condition:", target)
			end
		end)
	elseif condition.type == "window_close" then
		-- Set up window close listener (event-based)
		print("📚 TutorialHandler: Setting up complete condition listener for window close:", target)
		
		task.spawn(function()
			-- Find window object using event-based waiting
			local window = self:WaitForUIObject(target, 10)
			
			if window then
				-- Set up property change listener (event-based, no polling)
				local propertyName = window:IsA("ScreenGui") and "Enabled" or "Visible"
				local connection = window:GetPropertyChangedSignal(propertyName):Connect(function()
					-- Check if window is closed
					local isClosed = false
					if window:IsA("ScreenGui") then
						isClosed = window.Enabled == false
					else
						isClosed = window.Visible == false
					end
					
					if isClosed and self.isTutorialActive then
						print("📚 TutorialHandler: Window closed, completing step:", target)
						self:CompleteCurrentStep()
						if connection then
							connection:Disconnect()
						end
					end
				end)
				table.insert(self.Connections, connection)
				
				-- Check immediately in case window is already closed
				local isClosed = false
				if window:IsA("ScreenGui") then
					isClosed = window.Enabled == false
				else
					isClosed = window.Visible == false
				end
				
				if isClosed and self.isTutorialActive then
					print("📚 TutorialHandler: Window already closed, completing step:", target)
					self:CompleteCurrentStep()
					if connection then
						connection:Disconnect()
					end
				end
			else
				warn("📚 TutorialHandler: Window not found for close condition:", target)
			end
		end)
	elseif condition.type == "button_click" then
		-- Set up button click listener
		print("📚 TutorialHandler: Setting up complete condition listener for button:", target)
		
		-- For deck cards, we need to handle the case where cards are recreated
		local function setupButtonListener(button)
			if not button then
				return nil
			end
			
			-- Check if button still exists and is valid
			if not button.Parent then
				warn("📚 TutorialHandler: ⚠️ Button found but has no parent:", button:GetFullName())
				return nil
			end
			
			print("📚 TutorialHandler: ✅ Found button:", button.Name, "Type:", button.ClassName, "FullName:", button:GetFullName())
			print("📚 TutorialHandler: Button parent:", button.Parent:GetFullName())
			print("📚 TutorialHandler: Button parent parent:", button.Parent.Parent and button.Parent.Parent:GetFullName() or "nil")
			
			if button:IsA("GuiButton") or button:IsA("TextButton") or button:IsA("ImageButton") then
				-- Check if button is active and visible
				print("📚 TutorialHandler: Button state - Active:", button.Active, "Visible:", button.Visible, "ZIndex:", button.ZIndex)
				
				-- Check if button is already connected (prevent duplicates)
				local alreadyConnected = false
				for _, conn in ipairs(self.Connections) do
					if conn and conn.Connected then
						-- Try to check if this connection is for this button
						-- (we can't directly check, but we can log)
					end
				end
				
				local clickConnection = button.MouseButton1Click:Connect(function()
					print("📚 TutorialHandler: 🔔 Complete condition button clicked (MouseButton1Click):", target)
					print("📚 TutorialHandler: Button still exists:", button.Parent ~= nil, "Button Active:", button.Active)
					-- Complete step immediately (synchronously) before window might close
					if self.isTutorialActive then
						print("📚 TutorialHandler: Tutorial is active, completing step...")
						-- Use task.spawn to ensure completion happens even if window closes
						task.spawn(function()
							-- Double-check tutorial is still active (window might have closed)
							if self.isTutorialActive and self.showingStepIndex then
								self:CompleteCurrentStep()
							end
						end)
					else
						warn("📚 TutorialHandler: Button clicked but tutorial not active! isTutorialActive:", self.isTutorialActive)
					end
				end)
				
				local activatedConnection = button.Activated:Connect(function()
					print("📚 TutorialHandler: 🔔 Complete condition button activated (Activated):", target)
					print("📚 TutorialHandler: Button still exists:", button.Parent ~= nil, "Button Active:", button.Active)
					-- Complete step immediately (synchronously) before window might close
					if self.isTutorialActive then
						print("📚 TutorialHandler: Tutorial is active, completing step...")
						-- Use task.spawn to ensure completion happens even if window closes
						task.spawn(function()
							-- Double-check tutorial is still active (window might have closed)
							if self.isTutorialActive and self.showingStepIndex then
								self:CompleteCurrentStep()
							end
						end)
					else
						warn("📚 TutorialHandler: Button activated but tutorial not active! isTutorialActive:", self.isTutorialActive)
					end
				end)
				
				table.insert(self.Connections, clickConnection)
				table.insert(self.Connections, activatedConnection)
				print("📚 TutorialHandler: ✅ Complete condition listener connected successfully (both MouseButton1Click and Activated)")
				print("📚 TutorialHandler: Total connections:", #self.Connections)
				
				return true
			else
				warn("📚 TutorialHandler: ❌ Found object but it's not a button type:", button.ClassName, "Path:", target)
				return false
			end
		end
		
		-- For deck cards, always use ChildAdded listener to handle recreation
		if string.find(target, "DeckCard_") then
			-- Extract card ID pattern from path
			local cardIdPattern = string.match(condition.target, "DeckCard_([^_]+)_")
			print("📚 TutorialHandler: Card ID pattern:", cardIdPattern)
			
			if cardIdPattern then
				-- Find Deck container
				local deckWindow = self:FindUIObject("Deck")
				if deckWindow then
					local deckContainer = deckWindow:FindFirstChild("Deck")
					if deckContainer then
						deckContainer = deckContainer:FindFirstChild("Content")
						if deckContainer then
							deckContainer = deckContainer:FindFirstChild("Content")
							if deckContainer then
								print("📚 TutorialHandler: Found deck container, setting up ChildAdded listener")
								
								-- Function to set up listener on a card
								local function setupListenerOnCard(card)
									if not card then return false end
									
									-- Use ChildAdded to wait for BtnInfo instead of task.wait
									local btnInfo = card:FindFirstChild("BtnInfo")
									if btnInfo then
										print("📚 TutorialHandler: Found BtnInfo in card:", card.Name)
										return setupButtonListener(btnInfo) ~= nil
									else
										-- Wait for BtnInfo to be added using events
										local btnInfoConnection = card.ChildAdded:Connect(function(child)
											if child.Name == "BtnInfo" then
												print("📚 TutorialHandler: BtnInfo added to card:", card.Name)
												if setupButtonListener(child) then
													if btnInfoConnection then
														btnInfoConnection:Disconnect()
													end
												end
											end
										end)
										table.insert(self.Connections, btnInfoConnection)
										
										-- Check existing children immediately (in case BtnInfo was added between checks)
										btnInfo = card:FindFirstChild("BtnInfo")
										if btnInfo then
											if btnInfoConnection then
												btnInfoConnection:Disconnect()
											end
											return setupButtonListener(btnInfo) ~= nil
										end
										
										return false
									end
								end
								
								-- Listen for new deck cards being added (this handles recreation)
								local descendantConnection = deckContainer.ChildAdded:Connect(function(child)
									print("📚 TutorialHandler: ChildAdded event fired for:", child.Name)
									if child.Name:match("^DeckCard_" .. cardIdPattern .. "_") then
										print("📚 TutorialHandler: Matching deck card added:", child.Name)
										-- setupListenerOnCard will handle waiting for BtnInfo using events
										setupListenerOnCard(child)
									end
								end)
								table.insert(self.Connections, descendantConnection)
								
								-- Also check existing children (in case card already exists)
								-- But wait a bit first to let DeckHandler finish updating
								task.spawn(function()
									--task.wait(0.2)  -- Give DeckHandler time to update display
									if not self.isTutorialActive then return end
									
									for _, child in pairs(deckContainer:GetChildren()) do
										if child.Name:match("^DeckCard_" .. cardIdPattern .. "_") then
											print("📚 TutorialHandler: Found existing deck card after delay:", child.Name)
											if not setupListenerOnCard(child) then
												-- Try again
												task.wait(0.1)
												setupListenerOnCard(child)
											end
										end
									end
								end)
								
								print("📚 TutorialHandler: ✅ Set up ChildAdded listener for deck card recreation")
							end
						end
					end
				end
			end
		elseif string.find(target, "Card_") and not string.find(target, "DeckCard_") then
			-- For collection cards, handle recreation similar to deck cards
			-- Extract card ID pattern from path (e.g., "Card_600" or "Collection.Content.Content.ScrollingFrame.Card_600.BtnInfo")
			local cardIdPattern = string.match(target, "Card_([^%.]+)")
			print("📚 TutorialHandler: Collection card ID pattern:", cardIdPattern)
			
			if cardIdPattern then
				-- Find Collection container
				local deckWindow = self:FindUIObject("Deck")
				if deckWindow then
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
					
					if collectionContainer then
						print("📚 TutorialHandler: Found collection container, setting up ChildAdded listener")
						
						-- Function to set up listener on a card
						local function setupListenerOnCard(card)
							if not card then return false end
							
							-- Use ChildAdded to wait for BtnInfo instead of task.wait
							local btnInfo = card:FindFirstChild("BtnInfo")
							if btnInfo then
								print("📚 TutorialHandler: Found BtnInfo in collection card:", card.Name)
								return setupButtonListener(btnInfo) ~= nil
							else
								-- Wait for BtnInfo to be added using events
								local btnInfoConnection = card.ChildAdded:Connect(function(child)
									if child.Name == "BtnInfo" then
										print("📚 TutorialHandler: BtnInfo added to collection card:", card.Name)
										if setupButtonListener(child) then
											if btnInfoConnection then
												btnInfoConnection:Disconnect()
											end
										end
									end
								end)
								table.insert(self.Connections, btnInfoConnection)
								
								-- Check existing children immediately (in case BtnInfo was added between checks)
								btnInfo = card:FindFirstChild("BtnInfo")
								if btnInfo then
									if btnInfoConnection then
										btnInfoConnection:Disconnect()
									end
									return setupButtonListener(btnInfo) ~= nil
								end
								
								return false
							end
						end
						
						-- Listen for new collection cards being added (this handles recreation)
						local descendantConnection = collectionContainer.ChildAdded:Connect(function(child)
							print("📚 TutorialHandler: ChildAdded event fired for collection card:", child.Name)
							if child.Name == "Card_" .. cardIdPattern then
								print("📚 TutorialHandler: Matching collection card added:", child.Name)
								-- setupListenerOnCard will handle waiting for BtnInfo using events
								setupListenerOnCard(child)
							end
						end)
						table.insert(self.Connections, descendantConnection)
						
						-- Also check existing children (in case card already exists)
						-- But wait a bit first to let DeckHandler finish updating
						task.spawn(function()
							--task.wait(0.2)  -- Give DeckHandler time to update display
							if not self.isTutorialActive then return end
							
							for _, child in pairs(collectionContainer:GetChildren()) do
								if child.Name == "Card_" .. cardIdPattern then
									print("📚 TutorialHandler: Found existing collection card:", child.Name)
									if setupListenerOnCard(child) then
										print("📚 TutorialHandler: ✅ Set up listener on existing collection card")
										break
									end
								end
							end
						end)
						
						print("📚 TutorialHandler: ✅ Set up ChildAdded listener for collection card recreation")
					else
						warn("📚 TutorialHandler: Collection container not found, falling back to normal approach")
						-- Fall through to normal approach
						local button = self:FindUIObject(target)
						if button and setupButtonListener(button) then
							print("📚 TutorialHandler: ✅ Listener set up on initial button (fallback)")
						else
							warn("📚 TutorialHandler: ❌ Button not found in fallback, waiting for it to appear:", target)
							task.spawn(function()
								local foundButton = self:WaitForUIObject(target, 10)
								if foundButton and setupButtonListener(foundButton) then
									print("📚 TutorialHandler: ✅ Found button using event-based waiting (fallback)")
								end
							end)
						end
					end
				else
					warn("📚 TutorialHandler: Deck window not found, falling back to normal approach")
					-- Fall through to normal approach
					local button = self:FindUIObject(target)
					if button and setupButtonListener(button) then
						print("📚 TutorialHandler: ✅ Listener set up on initial button (fallback)")
					else
						warn("📚 TutorialHandler: ❌ Button not found in fallback, waiting for it to appear:", target)
						task.spawn(function()
							local foundButton = self:WaitForUIObject(target, 10)
							if foundButton and setupButtonListener(foundButton) then
								print("📚 TutorialHandler: ✅ Found button using event-based waiting (fallback)")
							end
						end)
					end
				end
			else
				-- Fall through to normal approach
			end
		else
			-- For non-deck cards, use normal approach
			-- Try to find button immediately
			local button = self:FindUIObject(target)
			print("📚 TutorialHandler: Initial button search result:", button and button:GetFullName() or "nil")
			
			if button and setupButtonListener(button) then
				-- Successfully set up listener
				print("📚 TutorialHandler: ✅ Listener set up on initial button")
			else
				warn("📚 TutorialHandler: ❌ Button not found immediately, waiting for it to appear:", target)
				
				-- Also wait for button to appear using event-based approach
				task.spawn(function()
					local foundButton = self:WaitForUIObject(target, 10)
					if foundButton and setupButtonListener(foundButton) then
						print("📚 TutorialHandler: ✅ Found button using event-based waiting")
					else
						warn("📚 TutorialHandler: ❌ Timeout waiting for complete condition button:", target)
					end
				end)
			end
		end
	elseif condition.type == "prompt_click" then
		-- Set up ProximityPrompt listener
		print("📚 TutorialHandler: Setting up complete condition listener for ProximityPrompt:", target)
		
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
					print("📚 TutorialHandler: ProximityPrompt target not found, waiting for:", target)
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
									print("📚 TutorialHandler: ProximityPrompt target appeared via event:", target)
									-- Now wait for ProximityPrompt
									self:WaitForProximityPrompt(targetObject, step, stepIndex)
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
								self:WaitForProximityPrompt(targetObject, step, stepIndex)
							end
						else
							warn("📚 TutorialHandler: ProximityPrompt target parent not found:", parentPath or "Workspace")
						end
					end
				else
					-- Object already found, wait for ProximityPrompt
					self:WaitForProximityPrompt(targetObject, step, stepIndex)
				end
			else
				-- Try to find in workspace directly
				targetObject = workspace:FindFirstChild(target, true)
				
				if targetObject then
					-- Object already found, wait for ProximityPrompt
					self:WaitForProximityPrompt(targetObject, step, stepIndex)
				else
					warn("📚 TutorialHandler: ProximityPrompt target not found:", target)
				end
			end
		end)
	end
end

-- Wait for ProximityPrompt to appear in target object (event-based only)
function TutorialHandler:WaitForProximityPrompt(targetObject, step, stepIndex)
	if not targetObject then
		warn("📚 TutorialHandler: WaitForProximityPrompt called with nil targetObject")
		return
	end
	
	-- Find ProximityPrompt in target object
	local prompt = targetObject:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = targetObject:FindFirstChild("ProximityPrompt", true)
	end
	
	if prompt then
		-- ProximityPrompt already exists
		self:SetupProximityPromptListener(prompt, step, stepIndex)
	else
		-- Wait for ProximityPrompt to appear using events only
		print("📚 TutorialHandler: ProximityPrompt not found, waiting for it to appear")
		
		-- Declare connections first
		local descendantConnection = nil
		local childConnection = nil
		
		-- Listen for DescendantAdded (covers all descendants)
		descendantConnection = targetObject.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("ProximityPrompt") then
				prompt = descendant
				print("📚 TutorialHandler: ProximityPrompt appeared via DescendantAdded")
				self:SetupProximityPromptListener(prompt, step, stepIndex)
				if descendantConnection then
					descendantConnection:Disconnect()
				end
				if childConnection then
					childConnection:Disconnect()
				end
			end
		end)
		table.insert(self.Connections, descendantConnection)
		
		-- Also listen for direct ChildAdded (faster for direct children)
		childConnection = targetObject.ChildAdded:Connect(function(child)
			if child:IsA("ProximityPrompt") then
				prompt = child
				print("📚 TutorialHandler: ProximityPrompt appeared via ChildAdded")
				self:SetupProximityPromptListener(prompt, step, stepIndex)
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

-- Setup listener for ProximityPrompt
function TutorialHandler:SetupProximityPromptListener(prompt, step, stepIndex)
	if not prompt then
		warn("📚 TutorialHandler: SetupProximityPromptListener called with nil prompt")
		return
	end
	
	print("📚 TutorialHandler: ✅ Found ProximityPrompt:", prompt:GetFullName())
	
	-- Connect to ProximityPrompt activation
	local promptConnection = prompt.Triggered:Connect(function(player)
		if player == Players.LocalPlayer and self.isTutorialActive then
			print("📚 TutorialHandler: 🔔 ProximityPrompt triggered, completing step...")
			self:CompleteCurrentStep()
		end
	end)
	
	table.insert(self.Connections, promptConnection)
	print("📚 TutorialHandler: ✅ ProximityPrompt listener connected successfully")
end

function TutorialHandler:CompleteCurrentStep()
	if not self.isTutorialActive or not self.showingStepIndex then
		warn("📚 TutorialHandler: CompleteCurrentStep called but tutorial not active or no step index")
		return
	end
	
	-- Send completion to server with current step index
	-- self.showingStepIndex is the step being shown (1-indexed)
	-- Server expects stepIndex == currentStep + 1, where currentStep is the last completed step (0-indexed)
	-- So if we're showing step 1, we send stepIndex=1, and server checks: 1 == 0 + 1 ✓
	local stepIndexToSend = self.showingStepIndex
	print("📚 TutorialHandler: Completing step", self.showingStepIndex, "-> sending stepIndex", stepIndexToSend, "to server")
	
	if self.NetworkClient and self.NetworkClient.requestCompleteTutorialStep then
		self.NetworkClient.requestCompleteTutorialStep(stepIndexToSend)
	else
		warn("📚 TutorialHandler: NetworkClient.requestCompleteTutorialStep not available")
	end
	
	-- Hide tutorial step
	self:HideTutorialStep()
end

function TutorialHandler:FindUIObject(objectName)
	-- Search in UI hierarchy
	if not self.UI or not objectName then
		if not self.UI then
			warn("📚 TutorialHandler: FindUIObject - self.UI is nil!")
		end
		return nil
	end
	
	-- If searching for the UI root itself, return it directly
	if objectName == self.UI.Name then
		return self.UI
	end
	
	-- Debug: log when searching for GameUI
	if objectName == "GameUI" and self.UI.Name == "GameUI" then
		-- This should have been caught above, but just in case
		return self.UI
	end
	
	-- Check if objectName contains a path (e.g., "BottomPanel.Packs.Outline.Content.Pack1")
	if string.find(objectName, "%.") then
		-- Split path by dots
		local pathParts = {}
		for part in string.gmatch(objectName, "([^%.]+)") do
			table.insert(pathParts, part)
		end
		
		if #pathParts == 0 then
			return nil
		end
		
		-- Start from UI root
		local current = self.UI
		
		-- Navigate through path
		for i, partName in ipairs(pathParts) do
			if not current then
				return nil
			end
			
			-- Try to find child with this name
			local child = current:FindFirstChild(partName)
			if not child then
				-- If not found and we're not at the last part, return nil
				-- If it's the last part, try recursive search as fallback
				if i < #pathParts then
					return nil
				else
					-- Last part: try recursive search
					child = current:FindFirstChild(partName, true)
				end
			end
			
			if not child then
				return nil
			end
			
			-- If this is the last part, check if it's a GuiObject
			if i == #pathParts then
				if child:IsA("GuiObject") then
					return child
				else
					return nil
				end
			end
			
			-- Move to next level
			current = child
		end
		
		-- Should not reach here, but return nil if we do
		return nil
	else
		-- Simple name search (no path)
		-- Try FindFirstChild with recursive search first (most efficient)
		local obj = self.UI:FindFirstChild(objectName, true)
		if obj and obj:IsA("GuiObject") then
			return obj
		end
		
		-- Also check in PlayerGui directly (for top-level objects)
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
			connection:Disconnect()
		end
	end
	self.Connections = {}
	
	for _, connection in ipairs(self.PersistentConnections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.PersistentConnections = {}
	
	self._initialized = false
	print("✅ TutorialHandler cleaned up")
end

-- Setup window visibility tracking for prompt_click with conditional target
function TutorialHandler:SetupWindowVisibilityTracking(step, stepIndex)
	print("📚 TutorialHandler: SetupWindowVisibilityTracking called")
	
	-- Список основных окон в UI, которые нужно отслеживать
	local windowNames = {
		"Deck", "Daily", "Playtime", "Shop", "RedeemCode", 
		"StartBattle", "Battle", "LootboxOpening"
	}
	
	-- Очистить предыдущие соединения
	for _, conn in ipairs(self.windowVisibilityConnections) do
		if conn then
			conn:Disconnect()
		end
	end
	self.windowVisibilityConnections = {}
	
	print("📚 TutorialHandler: Tracking", #windowNames, "windows for visibility changes")
	
	-- Отслеживать каждое окно
	for _, windowName in ipairs(windowNames) do
		local window = self:FindUIObject(windowName)
		if window then
			print("📚 TutorialHandler: Found window:", windowName, "setting up listener")
			-- Подписаться на изменение видимости
			local propertyName = window:IsA("ScreenGui") and "Enabled" or "Visible"
			local connection = window:GetPropertyChangedSignal(propertyName):Connect(function()
				local isOpen = false
				if window:IsA("ScreenGui") then
					isOpen = window.Enabled == true
				else
					isOpen = window.Visible == true
				end
				
				print("📚 TutorialHandler: Window", windowName, "visibility changed, isOpen:", isOpen, "isTutorialActive:", self.isTutorialActive, "isTemporarilyHidden:", self.isTutorialTemporarilyHidden)
				
				if isOpen then
					-- Окно открылось - временно скрыть туториал
					if self.isTutorialActive and not self.isTutorialTemporarilyHidden then
						print("📚 TutorialHandler: Window opened, temporarily hiding tutorial:", windowName)
						self:TemporarilyHideTutorial()
					end
				else
					-- Окно закрылось - восстановить туториал
					if self.isTutorialActive and self.isTutorialTemporarilyHidden then
						print("📚 TutorialHandler: Window closed, restoring tutorial:", windowName)
						self:RestoreTutorial()
					end
				end
			end)
			table.insert(self.windowVisibilityConnections, connection)
		else
			-- Окно еще не существует, подождать его появления
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
								print("📚 TutorialHandler: Window opened, temporarily hiding tutorial:", windowName)
								self:TemporarilyHideTutorial()
							end
						else
							if self.isTutorialActive and self.isTutorialTemporarilyHidden then
								print("📚 TutorialHandler: Window closed, restoring tutorial:", windowName)
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

-- Метод для временного скрытия туториала (без очистки состояния)
function TutorialHandler:TemporarilyHideTutorial()
	print("📚 TutorialHandler: TemporarilyHideTutorial called, isTutorialActive:", self.isTutorialActive, "isTemporarilyHidden:", self.isTutorialTemporarilyHidden)
	
	if not self.isTutorialActive or self.isTutorialTemporarilyHidden then
		print("📚 TutorialHandler: Skipping hide - tutorial not active or already hidden")
		return
	end
	
	self.isTutorialTemporarilyHidden = true
	
	-- Скрыть GUI
	if self.tutorialGui then
		print("📚 TutorialHandler: Disabling tutorial GUI")
		self.tutorialGui.Enabled = false
	else
		warn("📚 TutorialHandler: tutorialGui is nil!")
	end
	
	-- Скрыть контейнер с анимацией
	if self.tutorialContainer then
		local TweenUI = self.Utilities and self.Utilities.TweenUI
		if TweenUI and TweenUI.FadeOut then
			print("📚 TutorialHandler: Fading out tutorial container")
			TweenUI.FadeOut(self.tutorialContainer, 0.2)
		else
			print("📚 TutorialHandler: Hiding tutorial container directly")
			self.tutorialContainer.Visible = false
		end
	else
		warn("📚 TutorialHandler: tutorialContainer is nil!")
	end
	
	print("📚 TutorialHandler: Tutorial temporarily hidden")
end

-- Метод для восстановления туториала
function TutorialHandler:RestoreTutorial()
	print("📚 TutorialHandler: RestoreTutorial called, isTutorialActive:", self.isTutorialActive, "isTemporarilyHidden:", self.isTutorialTemporarilyHidden)
	
	if not self.isTutorialActive or not self.isTutorialTemporarilyHidden then
		print("📚 TutorialHandler: Skipping restore - tutorial not active or not temporarily hidden")
		return
	end
	
	-- Проверить, что все окна закрыты (использовать тот же список, что и в SetupWindowVisibilityTracking)
	local windowNames = {
		"Deck", "Daily", "Playtime", "Shop", "RedeemCode", 
		"StartBattle", "Battle", "LootboxOpening"
	}
	
	local anyWindowOpen = false
	local openWindows = {}
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
				table.insert(openWindows, windowName)
			end
		else
			print("📚 TutorialHandler: Window", windowName, "not found")
		end
	end
	
	-- Если какое-то окно все еще открыто, не восстанавливать туториал
	if anyWindowOpen then
		print("📚 TutorialHandler: Cannot restore tutorial - some windows are still open:", table.concat(openWindows, ", "))
		return
	end
	
	print("📚 TutorialHandler: All windows closed, restoring tutorial")
	self.isTutorialTemporarilyHidden = false
	
	-- Показать GUI
	if self.tutorialGui then
		print("📚 TutorialHandler: Enabling tutorial GUI")
		self.tutorialGui.Enabled = true
	else
		warn("📚 TutorialHandler: tutorialGui is nil!")
	end
	
	-- Показать контейнер с анимацией
	if self.tutorialContainer then
		local TweenUI = self.Utilities and self.Utilities.TweenUI
		if TweenUI and TweenUI.FadeIn then
			print("📚 TutorialHandler: Fading in tutorial container")
			TweenUI.FadeIn(self.tutorialContainer, 0.2)
		else
			print("📚 TutorialHandler: Showing tutorial container directly")
			self.tutorialContainer.Visible = true
		end
	else
		warn("📚 TutorialHandler: tutorialContainer is nil!")
	end
	
	print("📚 TutorialHandler: Tutorial restored")
end

return TutorialHandler

