--[[
	Promo Code Handler
	
	Client-side handler for promo code redemption UI.
]]

local PromoCodeHandler = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Modules
local EventBus = require(ReplicatedStorage.Modules.EventBus)

local localPlayer = Players.LocalPlayer

-- State
PromoCodeHandler.Connections = {}
PromoCodeHandler._initialized = false
PromoCodeHandler.isWindowOpen = false
PromoCodeHandler.isAnimating = false
PromoCodeHandler.NetworkClient = nil
PromoCodeHandler.Controller = nil
PromoCodeHandler.Utilities = nil
PromoCodeHandler.UI = nil

-- Constants
local TWEEN_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MESSAGE_DURATION = 5

local function waitForChildRecursive(parent, childName, timeout)
	return parent:WaitForChild(childName, timeout)
end
local function showFollowTextMessage(message, duration)
	duration = duration or MESSAGE_DURATION
	
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		warn("[PromoCodeHandler] PlayerGui not found")
		return
	end
	
	local gameUI = playerGui:FindFirstChild("GameUI")
	if not gameUI then
		warn("[PromoCodeHandler] GameUI not found")
		return
	end
	
	local followFrame = gameUI:FindFirstChild("FollowText")
	if not followFrame then
		warn("[PromoCodeHandler] FollowText not found")
		return
	end
	
	local followLabel = followFrame:FindFirstChildOfClass("TextLabel")
	if not followLabel then
		warn("[PromoCodeHandler] FollowText Label not found")
		return
	end
	
	local followStroke = followLabel:FindFirstChildOfClass("UIStroke")
	if not followStroke then
		warn("[PromoCodeHandler] FollowText Stroke not found")
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
	task.delay(duration, function()
		local fadeOutFrameTween = TweenService:Create(followFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
		local fadeOutLabelTween = TweenService:Create(followLabel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 1 })
		local fadeOutStrokeTween = TweenService:Create(followStroke, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 })
		
		fadeOutFrameTween:Play()
		fadeOutLabelTween:Play()
		fadeOutStrokeTween:Play()
		
		fadeOutLabelTween.Completed:Connect(function()
			followFrame.Visible = false
		end)
	end)
end

function PromoCodeHandler:Init(controller)
	if self._initialized then
		return
	end
	
	self.Controller = controller
	
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
		warn("PromoCodeHandler: Could not load NetworkClient: " .. tostring(NetworkClient))
		return false
	end
	
	-- Get Utilities module
	local success, utilities = pcall(function()
		return controller:GetModule("Utilities")
	end)
	
	if success then
		self.Utilities = utilities
	else
		warn("PromoCodeHandler: Could not load Utilities module: " .. tostring(utilities))
		self.Utilities = {
			TweenUI = { FadeIn = function() end, FadeOut = function() end },
			Blur = { Show = function() end, Hide = function() end }
		}
	end
	
	-- Get UI references
	local playerGui = localPlayer:WaitForChild("PlayerGui", 10)
	if not playerGui then
		warn("[PromoCodeHandler] PlayerGui not available")
		return false
	end
	
	local gameUI = waitForChildRecursive(playerGui, "GameUI", 10)
	if not gameUI then
		warn("[PromoCodeHandler] GameUI not found")
		return false
	end
	
	-- Store UI reference
	self.UI = gameUI
	
	-- Get top panel button
	local topPanel = waitForChildRecursive(gameUI, "TopPanel", 10)
	if not topPanel then
		warn("[PromoCodeHandler] TopPanel not found")
		return false
	end
	
	local btnCodesFrame = topPanel:FindFirstChild("BtnCodes")
	if not btnCodesFrame then
		warn("[PromoCodeHandler] BtnCodes not found in TopPanel")
		return false
	end
	
	local btnCodes = btnCodesFrame:FindFirstChild("Button")
	if not btnCodes then
		warn("[PromoCodeHandler] BtnCodes.Button not found in TopPanel")
		return false
	end
	
	-- Get redeem code window
	local redeemCodeFrame = waitForChildRecursive(gameUI, "RedeemCode", 10)
	if not redeemCodeFrame then
		warn("[PromoCodeHandler] RedeemCode window not found")
		return false
	end
	
	local mainFrame = redeemCodeFrame:FindFirstChild("Main")
	if not mainFrame then
		warn("[PromoCodeHandler] RedeemCode.Main not found")
		return false
	end
	
	local content = mainFrame:FindFirstChild("Content")
	if not content then
		warn("[PromoCodeHandler] RedeemCode.Main.Content not found")
		return false
	end
	
	-- Get close button
	local btnClose = content:FindFirstChild("BtnClose")
	if not btnClose then
		warn("[PromoCodeHandler] RedeemCode.Main.Content.BtnClose not found")
		return false
	end
	
	local btnCloseButton = btnClose:FindFirstChild("Button")
	if not btnCloseButton then
		warn("[PromoCodeHandler] RedeemCode.Main.Content.BtnClose.Button not found")
		return false
	end
	
	if not btnCloseButton:IsA("GuiButton") then
		warn("[PromoCodeHandler] RedeemCode.Main.Content.BtnClose.Button is not a GuiButton")
		return false
	end
	
	local innerContent = content:FindFirstChild("Content")
	if not innerContent then
		warn("[PromoCodeHandler] RedeemCode.Main.Content.Content not found")
		return false
	end
	
	local textBox = innerContent:FindFirstChild("TextBox")
	if not textBox then
		warn("[PromoCodeHandler] RedeemCode.Main.Content.Content.TextBox not found")
		return false
	end
	
	-- Store original placeholder text if it exists
	local originalPlaceholderText = textBox.PlaceholderText
	
	local function updatePlaceholderVisibility()
		if textBox.Text == "" then
			textBox.PlaceholderText = originalPlaceholderText
		else
			textBox.PlaceholderText = ""
		end
	end
	
	-- Hide placeholder when focused
	textBox.Focused:Connect(function()
		textBox.PlaceholderText = ""
	end)
	
	-- Show placeholder when focus lost if empty
	textBox.FocusLost:Connect(function()
		updatePlaceholderVisibility()
	end)
	
	-- Also update when text changes
	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		if not textBox:IsFocused() then
			updatePlaceholderVisibility()
		end
	end)
	
	-- Get redeem button
	local buttons = redeemCodeFrame:FindFirstChild("Buttons")
	if not buttons then
		warn("[PromoCodeHandler] RedeemCode.Buttons not found")
		return false
	end
	
	local btnRedeem = buttons:FindFirstChild("BtnRedeem")
	if not btnRedeem then
		warn("[PromoCodeHandler] RedeemCode.Buttons.BtnRedeem not found")
		return false
	end
	
	-- Store references
	self.TopPanelBtnCodes = btnCodes
	self.RedeemCodeFrame = redeemCodeFrame
	self.CodeTextBox = textBox
	self.BtnRedeem = btnRedeem
	self.BtnClose = btnCloseButton
	
	-- Setup button to open window
	local btnCodesConnection = btnCodes.MouseButton1Click:Connect(function()
		-- Emit button click event
		EventBus:Emit("ButtonClicked", "TopPanel.BtnCodes")
		self:OpenWindow()
	end)
	table.insert(self.Connections, btnCodesConnection)
	
	-- Setup close button
	local btnCloseConnection = btnCloseButton.MouseButton1Click:Connect(function()
		self:CloseWindow()
	end)
	table.insert(self.Connections, btnCloseConnection)
	
	-- Setup redeem button
	local btnRedeemConnection = btnRedeem.MouseButton1Click:Connect(function()
		self:OnRedeemClicked()
	end)
	table.insert(self.Connections, btnRedeemConnection)
	
	-- Listen for profile updates to handle promo code responses
	local profileUpdatedRemote = ReplicatedStorage:WaitForChild("Network"):WaitForChild("ProfileUpdated")
	local profileConnection = profileUpdatedRemote.OnClientEvent:Connect(function(payload)
		if payload and payload.promoCode then
			self:HandlePromoCodeResponse(payload.promoCode)
		end
	end)
	table.insert(self.Connections, profileConnection)
	
	-- Initially hide the window
	self:CloseWindow()
	
	self._initialized = true
	return true
end

function PromoCodeHandler:OpenWindow()
	if self.isWindowOpen or self.isAnimating then
		return
	end
	
	-- Check if battle is active
	local battleHandler = self.Controller and self.Controller:GetBattleHandler()
	if battleHandler and battleHandler.isBattleActive then
		return -- Don't allow opening during battle
	end
	
	self.isWindowOpen = true
	self.isAnimating = true
	
	-- Register with close button handler
	local CloseButtonHandler = require(game.ReplicatedStorage.ClientModules.CloseButtonHandler)
	local closeButtonHandler = CloseButtonHandler.GetInstance()
	if closeButtonHandler then
		closeButtonHandler:RegisterFrameOpen("PromoCode")
	end
	
	-- Hide HUD panels if they exist
	if self.UI and self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = false
	end
	if self.UI and self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = false
	end
	if self.UI and self.UI.RightPanel then
		self.UI.RightPanel.Visible = false
	end
	
	if self.RedeemCodeFrame then
		self.RedeemCodeFrame.Visible = true
		
		-- Clear text box
		if self.CodeTextBox then
			self.CodeTextBox.Text = ""
		end
		
		-- Use TweenUI if available, otherwise just show
		if self.Utilities then
			if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
				self.Utilities.TweenUI.FadeIn(self.RedeemCodeFrame, .3, function()
					self.isAnimating = false
					-- Emit window opened event after animation completes
					EventBus:Emit("WindowOpened", "RedeemCode")
				end)
			end
			if self.Utilities.Blur then
				self.Utilities.Blur.Show()
			end
		else
			self.isAnimating = false
			-- Emit window opened event immediately if no animation
			EventBus:Emit("WindowOpened", "RedeemCode")
		end
	end
end

function PromoCodeHandler:CloseWindow()
	if self.isAnimating then
		return
	end
	self.isAnimating = true
	
	if self.Utilities then
		if self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
			self.Utilities.TweenUI.FadeOut(self.RedeemCodeFrame, .3, function()
				if self.RedeemCodeFrame then
					self.RedeemCodeFrame.Visible = false
				end
				self.isAnimating = false
			end)
		end
		if self.Utilities.Blur then
			self.Utilities.Blur.Hide()
		end
	else
		if self.RedeemCodeFrame then
			self.RedeemCodeFrame.Visible = false
		end
		self.isAnimating = false
	end
	
	self.isWindowOpen = false
	
	-- Register with close button handler (for BtnCodes visibility, not Close button)
	local CloseButtonHandler = require(game.ReplicatedStorage.ClientModules.CloseButtonHandler)
	local closeButtonHandler = CloseButtonHandler.GetInstance()
	if closeButtonHandler then
		closeButtonHandler:RegisterFrameClosed("PromoCode")
	end
	
	-- Show HUD panels
	if self.UI and self.UI.LeftPanel then
		self.UI.LeftPanel.Visible = true
		EventBus:Emit("HudShown", "LeftPanel")
	end
	if self.UI and self.UI.BottomPanel then
		self.UI.BottomPanel.Visible = true
		EventBus:Emit("HudShown", "BottomPanel")
	end
	if self.UI and self.UI.RightPanel then
		self.UI.RightPanel.Visible = true
		EventBus:Emit("HudShown", "RightPanel")
	end
end

function PromoCodeHandler:OnRedeemClicked()
	if not self.CodeTextBox then
		return
	end
	
	local code = self.CodeTextBox.Text
	if not code or code == "" then
		showFollowTextMessage("Please enter a promo code", 3)
		return
	end
	
	-- Hide redeem button while processing
	if self.BtnRedeem then
		self.BtnRedeem.Visible = false
	end
	
	-- Send request to server
	if self.NetworkClient and self.NetworkClient.requestRedeemPromoCode then
		self.NetworkClient.requestRedeemPromoCode(code)
	else
		warn("[PromoCodeHandler] NetworkClient.requestRedeemPromoCode not available")
		-- Show button again if request failed
		if self.BtnRedeem then
			self.BtnRedeem.Visible = true
		end
	end
end

function PromoCodeHandler:HandlePromoCodeResponse(response)
	if not response then
		-- Show button again if no response
		if self.BtnRedeem then
			self.BtnRedeem.Visible = true
		end
		return
	end
	
	-- Show button again after receiving response
	if self.BtnRedeem then
		self.BtnRedeem.Visible = true
	end
	
	if response.status == "success" then
		showFollowTextMessage("Promo code redeemed successfully!", MESSAGE_DURATION)
		-- Clear text box
		if self.CodeTextBox then
			self.CodeTextBox.Text = ""
		end
	elseif response.status == "code_not_found" then
		showFollowTextMessage("Promo code not found!", MESSAGE_DURATION)
	elseif response.status == "already_redeemed" then
		showFollowTextMessage("This promo code has already been redeemed!", MESSAGE_DURATION)
	elseif response.status == "invalid_code" then
		showFollowTextMessage("Invalid promo code!", MESSAGE_DURATION)
	else
		showFollowTextMessage("Failed to redeem promo code!", MESSAGE_DURATION)
	end
end

function PromoCodeHandler:Cleanup()
	for _, connection in ipairs(self.Connections) do
		if connection and connection.Disconnect then
			connection:Disconnect()
		end
	end
	self.Connections = {}
	self._initialized = false
end

return PromoCodeHandler

