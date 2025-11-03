--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

--// Module
local BattlePrepHandler = {}

--// State
BattlePrepHandler.Connections = {}
BattlePrepHandler._initialized = false
BattlePrepHandler.isAnimating = false
BattlePrepHandler.currentEnemyData = nil
BattlePrepHandler.currentPartName = nil -- Store current part name for NPC/Boss detection

--// Constants
local LOOTBOX_ASSETS = {
	uncommon = "rbxassetid://89282766853868",
	rare = "rbxassetid://101339929529268",
	epic = "rbxassetid://126842532670644",
	legendary = "rbxassetid://97529044228503"
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
		self.TxtDifficultyLabel = txtRivalFrame:FindFirstChild("TxtDifficulty")
		if not self.TxtDifficultyLabel then
			warn("BattlePrepHandler: TxtDifficulty TextLabel not found in TxtRival frame")
		end
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
		proximityPrompt.MaxActivationDistance = 10
		proximityPrompt.Enabled = true
		proximityPrompt.RequiresLineOfSight = false -- Don't require line of sight
		proximityPrompt.HoldDuration = 0 -- Instant activation
		proximityPrompt.Parent = part
	else
		-- Configure existing prompt (in case it was manually added)
		proximityPrompt.ActionText = "Start Battle"
		proximityPrompt.KeyboardKeyCode = Enum.KeyCode.E
		proximityPrompt.MaxActivationDistance = 10
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
		handler.currentPartName = originalPartName -- Use original name (e.g., "BossMode1Head") not "HumanoidRootPart"
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
		proximityPrompt.MaxActivationDistance = 10
		proximityPrompt.Parent = testPart
		
		-- Default to NPC mode if part name doesn't match
		local connection = proximityPrompt.Triggered:Connect(function()
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

function BattlePrepHandler:OpenBattlePrep()
	if self.isAnimating then return end
	self.isAnimating = true

	-- Determine battle mode from part name
	local isNPCMode = self.currentPartName and self.currentPartName:match("^NPCMode")
	local isBossMode = self.currentPartName and self.currentPartName:match("^BossMode")
	
	-- Hide HUD panels if they exist
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = false
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = false
	end
	
	-- Load enemy data based on mode
	if isNPCMode then
		-- NPC mode: request NPC deck from server (async)
		self:LoadNPCEnemyData(function()
			-- After NPC deck loads, update UI and show window
			self:UpdateRewardsDisplay()
			self:UpdateRivalsDeckDisplay()
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
	else
		-- Default: use test data
		self:LoadTestEnemyData()
	end

	-- Update UI with enemy data
	self:UpdateRewardsDisplay()
	self:UpdateRivalsDeckDisplay()
	
	-- Show battle prep window
	self:ShowBattlePrepWindow()
end

function BattlePrepHandler:ShowBattlePrepWindow()
	-- Reset request flag when opening window (in case it was stuck)
	self._isRequestingBattle = false
	
	-- Ensure Start button is enabled when opening window
	if self.StartButton and self.StartButton:IsA("GuiButton") then
		self.StartButton.Active = true
	end
	
	-- Show battle prep gui
	self.StartBattleFrame.Visible = true
	
	-- Register with close button handler
	self:RegisterWithCloseButton(true)

	-- Use TweenUI if available, otherwise just show
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
			self.Utilities.TweenUI.FadeIn(self.StartBattleFrame, .3, function ()
				self.isAnimating = false
			end)
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
		self.currentEnemyData = {
			name = "NPC Opponent",
			deck = result.deck or {},
			levels = result.levels or {}, -- Store levels for each card
			rewards = {reward} -- Single reward (lootbox) as generated by server
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
			difficulty = result.difficulty -- Store difficulty for UI display
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
			{type = "lootbox", rarity = "uncommon", count = 1}
		}
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

function BattlePrepHandler:CloseWindow()
	if self.isAnimating then return end
	self.isAnimating = true

	-- Clean up dynamically created frames
	self:CleanupDynamicFrames()

	-- Note: NPC deck will be cleared server-side after battle completes
	-- If prep window is closed without starting battle, the deck will persist
	-- until next battle or server restart (this is acceptable for simplicity)

	-- Hide battle prep gui
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
			self.Utilities.TweenUI.FadeOut(self.StartBattleFrame, .3, function () 
				self.StartBattleFrame.Visible = false
				self.isAnimating = false
			end)
		end
		if self.Utilities.Blur then
			self.Utilities.Blur.Hide()
		end
	else
		-- Fallback: no animation
		self.StartBattleFrame.Visible = false
		self.isAnimating = false
	end

	-- Show HUD panels
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = true
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = true
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
		-- Verify NetworkClient is available before allowing click
		local networkClient = self.Controller and self.Controller:GetNetworkClient()
		if not networkClient then
			warn("BattlePrepHandler: Cannot start battle - NetworkClient not ready")
			return
		end
		
		-- Verify currentPartName is set (should be set when window opens)
		if not self.currentPartName then
			warn("BattlePrepHandler: Cannot start battle - no part name set")
			return
		end
		
		-- Call the handler
		self:OnStartButtonClicked()
	end)
	
	table.insert(self.Connections, connection)
	print("✅ BattlePrepHandler: START button connected (Type: " .. self.StartButton.ClassName .. ", Active: " .. tostring(self.StartButton.Active) .. ")")
	return true
end

function BattlePrepHandler:OnStartButtonClicked()
	-- Prevent multiple clicks (debounce)
	if self._isRequestingBattle then
		warn("BattlePrepHandler: Battle request already in progress")
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
	
	-- Verify part name is set
	if not self.currentPartName then
		warn("BattlePrepHandler: No part name set - cannot determine battle mode")
		-- Re-enable button on error
		if self.StartButton then
			self.StartButton.Active = true
		end
		return
	end
	
	-- Mark as requesting to prevent duplicate requests
	self._isRequestingBattle = true
	
	-- Determine battle mode from part name (for logging only, server determines this)
	local isNPCMode = self.currentPartName:match("^NPCMode")
	local isBossMode = self.currentPartName:match("^BossMode")
	
	-- Request battle with current enemy data
	-- NOTE: For NPC/Boss mode, don't send variant - the server doesn't use it and will reject "Balanced" in production
	-- Variant is only used for regular PvE battles, not NPC/Boss battles
	local requestData = {
		mode = "PvE",
		seed = nil, -- Let server generate seed
		partName = self.currentPartName -- Include part name for NPC/Boss detection
	}
	
	-- Only add variant for regular PvE battles (not NPC/Boss)
	if not isNPCMode and not isBossMode then
		requestData.variant = "Balanced"
	end
	
	print("✅ BattlePrepHandler: Requesting battle with partName:", tostring(self.currentPartName), "mode:", isNPCMode and "NPC" or (isBossMode and "Boss" or "Normal"), "variant:", tostring(requestData.variant))
	
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
	-- Reset request flag
	self._isRequestingBattle = false
	
	-- Re-enable button (in case of error)
	if self.StartButton then
		self.StartButton.Active = true
	end
	
	if not response.ok then
		warn("BattlePrepHandler: Battle request failed:", response.error and response.error.message or "Unknown error")
		return
	end
	
	-- Hide battle prep frame
	self:CloseWindow()
	
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
		self:CloseWindow()
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
