--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

--// Modules
local EventBus = require(ReplicatedStorage.Modules.EventBus)
local CardCatalog = require(ReplicatedStorage.Modules.Cards.CardCatalog)
local Resolver = require(ReplicatedStorage.Modules.Assets.Resolver)

--// Module
local LikeHandler = {}

--// State
LikeHandler.Connections = {}
LikeHandler._initialized = false
LikeHandler.isAnimating = false
LikeHandler.isWindowOpen = false
LikeHandler.canClaimReward = false  -- Cached eligibility from server
LikeHandler._hasCheckedEligibility = false  -- Flag to check only once per session
LikeHandler._pendingClaim = false  -- Flag to track if we're expecting a claim response
LikeHandler._rewardConfig = nil  -- Cached reward config from server
LikeHandler._lastKnownClaimedState = false  -- Cached claimed state for immediate button update

--// Constants
local MESSAGE_DURATION = 3

--// Initialization
function LikeHandler:Init(controller)
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
		warn("LikeHandler: Could not load NetworkClient: " .. tostring(NetworkClient))
		return false
	end

	-- Safe require of Utilities to avoid loading errors
	local success, utilities = pcall(function()
		return controller:GetModule("Utilities")
	end)
	
	if success then
		self.Utilities = utilities
	else
		warn("LikeHandler: Could not load Utilities module: " .. tostring(utilities))
		self.Utilities = {
			TweenUI = { FadeIn = function() end, FadeOut = function() end },
			Blur = { Show = function() end, Hide = function() end }
		}
	end

	-- Initialize state
	self.Connections = {}
	self.isAnimating = false
	self.isWindowOpen = false
	self.canClaimReward = false
	self._hasCheckedEligibility = false
	self._pendingClaim = false
	self._rewardConfig = nil
	self._lastKnownClaimedState = false

	-- Setup like reward functionality
	self:SetupLikeReward()

	-- Setup ProfileUpdated handler
	self:SetupProfileUpdatedHandler()

	self._initialized = true
	print("✅ LikeHandler initialized successfully!")
	return true
end

function LikeHandler:SetupLikeReward()
	-- Access UI from player's PlayerGui
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Wait for GameUI
	local gameGui = playerGui:WaitForChild("GameUI", 10)
	if not gameGui then
		warn("LikeHandler: GameUI not found in PlayerGui after extended waiting")
		return
	end
	
	-- Store UI reference
	self.UI = gameGui
	
	-- Find RightPanel and BtnLikeReward
	local rightPanel = gameGui:FindFirstChild("RightPanel")
	if not rightPanel then
		warn("LikeHandler: RightPanel not found in GameUI")
		return
	end
	
	local likeButton = rightPanel:FindFirstChild("BtnLikeReward")
	if not likeButton then
		warn("LikeHandler: BtnLikeReward not found in RightPanel")
		return
	end
	
	self.LikeButton = likeButton
	
	-- Find LikeReward window
	local likeRewardFrame = gameGui:FindFirstChild("LikeReward")
	if not likeRewardFrame then
		warn("LikeHandler: LikeReward frame not found in GameUI")
		return
	end
	
	self.LikeRewardFrame = likeRewardFrame
	self.InputBlocker = likeRewardFrame:FindFirstChild("InputBlocker")
	
	-- Find emitter for particles and cache UI elements in one pass
	local mainFrame = likeRewardFrame:FindFirstChild("Main")
	if mainFrame then
		local content = mainFrame:FindFirstChild("Content")
		if content then
			local imgBackground = content:FindFirstChild("ImgBackground")
			if imgBackground then
				self.Emitter = imgBackground:FindFirstChild("Emitter")
			end
			
			-- Cache card UI elements for UpdateCardDisplay
			local card = content:FindFirstChild("Card")
			if card then
				local cardContent = card:FindFirstChild("Content")
				if cardContent then
					self._cardUI = {
						imgHero = cardContent:FindFirstChild("ImgHero"),
						level = cardContent:FindFirstChild("Level"),
						progress = cardContent:FindFirstChild("Progress"),
						attack = cardContent:FindFirstChild("Attack"),
						defense = cardContent:FindFirstChild("Defense"),
						health = cardContent:FindFirstChild("Health")
					}
				end
			end
			
			-- Setup close button using cached content
			local btnClose = content:FindFirstChild("BtnClose")
			if btnClose then
				local btnCloseButton = btnClose:FindFirstChild("Button")
				if btnCloseButton then
					local connection = btnCloseButton.MouseButton1Click:Connect(function()
						self:CloseWindow()
					end)
					table.insert(self.Connections, connection)
				end
			end
		end
	end
	
	-- Hide window initially
	likeRewardFrame.Visible = false
	
	-- Setup button click
	if likeButton:IsA("TextButton") or likeButton:IsA("GuiButton") or likeButton:IsA("ImageButton") then
		local connection = likeButton.MouseButton1Click:Connect(function()
			EventBus:Emit("ButtonClicked", "RightPanel.BtnLikeReward")
			self:OpenWindow()
		end)
		table.insert(self.Connections, connection)
		print("✅ LikeHandler: Like button connected")
	else
		warn("LikeHandler: Found element '" .. likeButton.Name .. "' but it's not a clickable button")
	end
	
	-- Setup claim button
	local buttons = likeRewardFrame:FindFirstChild("Buttons")
	if buttons then
		local btnClaim = buttons:FindFirstChild("BtnClaim")
		if btnClaim then
			local connection = btnClaim.MouseButton1Click:Connect(function()
				self:OnClaimClicked()
			end)
			table.insert(self.Connections, connection)
		end
	end
	
	-- Check initial eligibility on init (only if reward not claimed)
	-- We'll check this after profile is loaded
end

function LikeHandler:SetupProfileUpdatedHandler()
	-- Listen for ProfileUpdated events
	local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
	
	local connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
		-- Handle likeReward updates
		if payload.likeReward then
			-- Cache claimed state immediately
			if payload.likeReward.claimed ~= nil then
				self._lastKnownClaimedState = payload.likeReward.claimed
			end
			
			self:HandleLikeRewardUpdate(payload.likeReward)
			
			-- If reward was just claimed, handle it only if we're expecting it
			if payload.likeReward.claimed and self._pendingClaim then
				self:HandleRewardClaimed()
				self._pendingClaim = false
			end
		end
		
		-- Handle eligibility response
		if payload.likeRewardEligibility ~= nil then
			self.canClaimReward = payload.likeRewardEligibility
		end
		
		-- Cache reward config if provided
		if payload.likeRewardConfig then
			self._rewardConfig = payload.likeRewardConfig
		end
		
		-- Update button visibility when profile changes (without triggering eligibility check)
		self:UpdateButtonVisibility()
		
		-- Check eligibility on initial profile load if reward not claimed (only once per session)
		if not self._hasCheckedEligibility then
			if payload.likeReward and not payload.likeReward.claimed then
				if self.NetworkClient then
					self._hasCheckedEligibility = true
					self.NetworkClient.requestCheckLikeRewardEligibility()
				end
			else
				-- Mark as checked even if reward is claimed or profile doesn't have likeReward
				self._hasCheckedEligibility = true
			end
		end
	end)
	
	table.insert(self.Connections, connection)
end

function LikeHandler:HandleRewardClaimed()
	-- Show success message
	self:ShowFollowTextMessage("You've got the reward!")
	
	-- Hide input blocker
	if self.InputBlocker then
		self.InputBlocker.Visible = false
		self.InputBlocker.Active = false
	end
	
	-- Hide button immediately after successful claim
	if self.LikeButton then
		self.LikeButton.Visible = false
		self.LikeButton.Active = false
	end
	
	-- Update cached state
	self._lastKnownClaimedState = true
	
	if self.isWindowOpen then
		self:CloseWindow()
	end
end

function LikeHandler:HandleLikeRewardUpdate(likeRewardData)
	if likeRewardData.claimed then
		self.canClaimReward = false
		self._lastKnownClaimedState = true  -- Cache the claimed state
		self:UpdateButtonVisibility()
	end
end

function LikeHandler:UpdateButtonVisibility()
	if not self.LikeButton then
		return
	end
	
	-- Hide and disable button if reward is claimed
	-- Check cached state first for immediate updates, then fallback to ClientState
	local isClaimed = self._lastKnownClaimedState
	
	if not isClaimed and self.ClientState then
		local profile = self.ClientState.getProfile()
		if profile and profile.likeReward and profile.likeReward.claimed then
			isClaimed = true
			-- Update cached state
			self._lastKnownClaimedState = true
		end
	end
	
	if isClaimed then
		self.LikeButton.Visible = false
		self.LikeButton.Active = false
	else
		-- Just update visibility, don't check eligibility here
		self.LikeButton.Visible = true
		self.LikeButton.Active = true
	end
end

function LikeHandler:OpenWindow()
	if self.isAnimating or self.isWindowOpen then
		return
	end
	
	-- Don't open if reward is already claimed
	if self.ClientState then
		local profile = self.ClientState.getProfile()
		if profile and profile.likeReward and profile.likeReward.claimed then
			return
		end
	end
	
	self.isAnimating = true

	-- Record window open timestamp on server
	if self.NetworkClient then
		self.NetworkClient.requestRecordLikeRewardWindowOpen()
	end

	-- Hide HUD panels
	if self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = false
	end
	if self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = false
	end
	if self.UI.RightPanel then
		self.UI.RightPanel.Visible = false
	end

	-- Update card display
	self:UpdateCardDisplay()

	-- Start particles
	if self.Emitter then
		local emitEvent = self.Emitter:FindFirstChild("Emit")
		if emitEvent then
			emitEvent:Fire()
		end
	end

	-- Show like reward window
	self.LikeRewardFrame.Visible = true
	self.isWindowOpen = true
	
	-- Register with close button handler
	self:RegisterWithCloseButton(true)

	-- Use TweenUI if available
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
			self.Utilities.TweenUI.FadeIn(self.LikeRewardFrame, .3, function()
				self.isAnimating = false
				EventBus:Emit("WindowOpened", "LikeReward")
			end)
		end
		if self.Utilities.Blur then
			self.Utilities.Blur.Show()
		end
	else
		self.isAnimating = false
		EventBus:Emit("WindowOpened", "LikeReward")
	end
end

function LikeHandler:CloseWindow()
	if self.isAnimating then
		return
	end
	self.isAnimating = true

	-- Hide like reward window
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
			self.Utilities.TweenUI.FadeOut(self.LikeRewardFrame, .3, function()
				self.LikeRewardFrame.Visible = false
				self.isAnimating = false
				EventBus:Emit("WindowClosed", "LikeReward")
			end)
		end
		if self.Utilities.Blur then
			self.Utilities.Blur.Hide()
		end
	else
		self.LikeRewardFrame.Visible = false
		self.isAnimating = false
		EventBus:Emit("WindowClosed", "LikeReward")
	end

	self.isWindowOpen = false

	-- Stop particles
	if self.Emitter then
		local clearEvent = self.Emitter:FindFirstChild("Clear")
		if clearEvent then
			clearEvent:Fire()
		end
	end

	-- Show HUD panels
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
	
	-- Register with close button handler
	self:RegisterWithCloseButton(false)
end

function LikeHandler:UpdateCardDisplay()
	-- Get reward config from cached value (received from server)
	-- Fallback to default if not cached yet
	local rewardConfig = self._rewardConfig or { cardId = "card_100", amount = 1 }
	local rewardCardId = rewardConfig.cardId
	local rewardAmount = rewardConfig.amount
	
	-- Get card data from catalog
	local cardData = CardCatalog.Cards[rewardCardId]
	if not cardData then
		warn("LikeHandler: Card " .. rewardCardId .. " not found in catalog")
		return
	end
	
	-- Get card image from manifest
	local cardImage = Resolver.getCardImage(rewardCardId)
	
	-- Use cached UI elements
	if not self._cardUI then
		warn("LikeHandler: Card UI elements not cached")
		return
	end
	
	-- Update hero image
	if self._cardUI.imgHero then
		self._cardUI.imgHero.Image = cardImage
	end
	
	-- Update level (base level 1)
	if self._cardUI.level then
		local levelContent = self._cardUI.level:FindFirstChild("Content")
		if levelContent then
			local txtValue = levelContent:FindFirstChild("TxtValue")
			if txtValue then
				txtValue.Text = "1"
			end
		end
	end
	
	-- Update progress (amount)
	if self._cardUI.progress then
		local txtValue = self._cardUI.progress:FindFirstChild("TxtValue")
		if txtValue then
			txtValue.Text = "x" .. tostring(rewardAmount)
		end
	end
	
	-- Update attack
	if self._cardUI.attack then
		local value = self._cardUI.attack:FindFirstChild("Value")
		if value then
			local txtValue = value:FindFirstChild("TxtValue")
			if txtValue then
				txtValue.Text = tostring(cardData.base.atk)
			end
		end
	end
	
	-- Update defense (hide parent if 0)
	if self._cardUI.defense then
		if cardData.base.defence == 0 then
			self._cardUI.defense.Visible = false
		else
			self._cardUI.defense.Visible = true
			local value = self._cardUI.defense:FindFirstChild("Value")
			if value then
				local txtValue = value:FindFirstChild("TxtValue")
				if txtValue then
					txtValue.Text = tostring(cardData.base.defence)
				end
			end
		end
	end
	
	-- Update health
	if self._cardUI.health then
		local value = self._cardUI.health:FindFirstChild("Value")
		if value then
			local txtValue = value:FindFirstChild("TxtValue")
			if txtValue then
				txtValue.Text = tostring(cardData.base.hp)
			end
		end
	end
end

function LikeHandler:OnClaimClicked()
	-- Show input blocker
	if self.InputBlocker then
		self.InputBlocker.Visible = true
		self.InputBlocker.Active = true
	end
	
	-- Check cached eligibility
	if self.canClaimReward then
		-- Set flag that we're expecting a claim response
		self._pendingClaim = true
		-- Request claim from server
		if self.NetworkClient then
			self.NetworkClient.requestClaimLikeReward()
		end
	else
		-- Show error message
		self:ShowFollowTextMessage("Conditions not met!")
		
		-- Hide input blocker
		if self.InputBlocker then
			self.InputBlocker.Visible = false
			self.InputBlocker.Active = false
		end
	end
end

function LikeHandler:ShowFollowTextMessage(message)
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end
	
	local gameUI = playerGui:FindFirstChild("GameUI")
	if not gameUI then
		return
	end
	
	local followFrame = gameUI:FindFirstChild("FollowText")
	if not followFrame then
		return
	end
	
	local followLabel = followFrame:FindFirstChildOfClass("TextLabel")
	if not followLabel then
		return
	end
	
	local followStroke = followLabel:FindFirstChildOfClass("UIStroke")
	if not followStroke then
		return
	end
	
	-- Set message
	followLabel.Text = message
	
	-- Fade in
	followFrame.Visible = true
	followFrame.BackgroundTransparency = 1
	followLabel.TextTransparency = 1
	followStroke.Transparency = 1
	
	local frameTween = TweenService:Create(followFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.5 })
	local labelTween = TweenService:Create(followLabel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 })
	local strokeTween = TweenService:Create(followStroke, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0.5 })
	
	frameTween:Play()
	labelTween:Play()
	strokeTween:Play()
	
	-- Fade out after duration
	task.delay(MESSAGE_DURATION, function()
		local frameTweenOut = TweenService:Create(followFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
		local labelTweenOut = TweenService:Create(followLabel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
		local strokeTweenOut = TweenService:Create(followStroke, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
		
		frameTweenOut:Play()
		labelTweenOut:Play()
		strokeTweenOut:Play()
		
		labelTweenOut.Completed:Connect(function()
			followFrame.Visible = false
		end)
	end)
end

function LikeHandler:RegisterWithCloseButton(isOpen)
	local success, CloseButtonHandler = pcall(function()
		return require(game.ReplicatedStorage.ClientModules.CloseButtonHandler)
	end)
	
	if success and CloseButtonHandler then
		local instance = CloseButtonHandler.GetInstance()
		if instance and instance.isInitialized then
			if isOpen then
				instance:RegisterFrameOpen("LikeReward")
			else
				instance:RegisterFrameClosed("LikeReward")
			end
		end
	end
end

function LikeHandler:CloseFrame()
	if self.LikeRewardFrame and self.LikeRewardFrame.Visible then
		self:CloseWindow()
	end
end

--// Public Methods
function LikeHandler:IsInitialized()
	return self._initialized
end

--// Cleanup
function LikeHandler:Cleanup()
	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			if connection.Disconnect then
				connection:Disconnect()
			end
		end
	end
	self.Connections = {}

	self._initialized = false
end

return LikeHandler
