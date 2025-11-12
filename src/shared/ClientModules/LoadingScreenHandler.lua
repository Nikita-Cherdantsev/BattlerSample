local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LoadingScreenHandler = {}
LoadingScreenHandler._initialized = false
LoadingScreenHandler._controller = nil
LoadingScreenHandler._elements = {}
LoadingScreenHandler._connections = {}
LoadingScreenHandler._dotsAnimating = false
LoadingScreenHandler._serverReady = false
LoadingScreenHandler._clientReady = false
LoadingScreenHandler._completed = false
LoadingScreenHandler._externalReady = false

local DOT_STATES = {"", ".", "..", "..."}

local function getTransparencyProperty(instance)
	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		return "ImageTransparency"
	elseif instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		return "TextTransparency"
	elseif instance:IsA("Frame") or instance:IsA("ScrollingFrame") then
		return "BackgroundTransparency"
	elseif instance:IsA("UIStroke") then
		return "Transparency"
	end
	
	return nil
end

local function applyTransparency(instance, transparency)
	local property = getTransparencyProperty(instance)
	if property then
		instance[property] = transparency
	end
	
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		instance.TextStrokeTransparency = transparency
	end
end

local function tweenTransparency(instance, transparency, tweenInfo)
	local property = getTransparencyProperty(instance)
	if not property then
		return nil
	end
	
	local targetTransparency = transparency
	if instance:IsA("UIStroke") and transparency == 0 then
		targetTransparency = 0.75
	end
	
	local tween = TweenService:Create(instance, tweenInfo, {[property] = targetTransparency})
	tween:Play()
	return tween
end

function LoadingScreenHandler:_applyTransparencyRecursive(instance, transparency)
	if not instance then
		return
	end
	
	if instance:IsA("UIStroke") and transparency == 0 then
		applyTransparency(instance, 0.75)
	else
		applyTransparency(instance, transparency)
	end
	for _, child in ipairs(instance:GetChildren()) do
		self:_applyTransparencyRecursive(child, transparency)
	end
end

function LoadingScreenHandler:_tweenTransparencyRecursive(instance, transparency, tweenInfo, includeDescendants)
	if not instance then
		return
	end
	
	includeDescendants = includeDescendants ~= false
	
	local tweens = {}
	local function recurse(target)
		local shouldTween = not (target.Name == "Text" and target.Parent and target.Parent.Name == "GameLogo")
		
		if shouldTween then
			local tween = tweenTransparency(target, transparency, tweenInfo)
			if tween then
				table.insert(tweens, tween)
			end
		end
		
		if includeDescendants then
			for _, child in ipairs(target:GetChildren()) do
				if target.Name == "GameLogo" and child.Name == "Text" then
					for _, grandChild in ipairs(child:GetChildren()) do
						recurse(grandChild)
					end
				else
					recurse(child)
				end
			end
		end
	end
	
	recurse(instance)
	
	if #tweens > 0 then
		task.wait(tweenInfo.Time + tweenInfo.DelayTime)
	end
end

function LoadingScreenHandler:_cacheUiElements()
	local player = Players.LocalPlayer
	if not player then
		player = Players.PlayerAdded:Wait()
	end
	
	local playerGui = player:WaitForChild("PlayerGui", 10)
	if not playerGui then
		warn("LoadingScreenHandler: PlayerGui not found")
		return false
	end
	
	local screenGui = playerGui:WaitForChild("LoadingScreen")
	if not screenGui then
		warn("LoadingScreenHandler: LoadingScreen GUI not found")
		return false
	end
	
	local devLogo = screenGui:FindFirstChild("DevLogo")
	local gameLogo = screenGui:FindFirstChild("GameLogo")
	if not devLogo or not gameLogo then
		warn("LoadingScreenHandler: Expected child frames missing in LoadingScreen")
		return false
	end
	
	local textFolder = gameLogo:FindFirstChild("Text")
	
	local elements = {
		screenGui = screenGui,
		devLogoFrame = devLogo,
		gameLogoFrame = gameLogo,
		backgroundImage = gameLogo:FindFirstChild("ImgBackground"),
		gameLogoImage = gameLogo:FindFirstChild("ImgGameLogo"),
		loadingText = textFolder and textFolder:FindFirstChild("TxtLoading") or nil,
		dotsText = textFolder and textFolder:FindFirstChild("TxtDots") or nil
	}
	
	for name, instance in pairs(elements) do
		if not instance then
			warn(string.format("LoadingScreenHandler: Element '%s' is missing", name))
			return false
		end
	end
	
	self._elements = elements
	self._elements.screenGui.Enabled = true
	
	return true
end

function LoadingScreenHandler:_prepareInitialState()
	local elements = self._elements
	if elements.screenGui then
		elements.screenGui.Enabled = true
	end
	self:_applyTransparencyRecursive(elements.devLogoFrame, 1)
	self:_applyTransparencyRecursive(elements.gameLogoFrame, 1)
	elements.dotsText.Text = "..."
end

function LoadingScreenHandler:_startDotsAnimation()
	if self._dotsAnimating then
		return
	end
	
	self._dotsAnimating = true
	local dotsText = self._elements.dotsText
	
	task.spawn(function()
		local index = 1
		while self._dotsAnimating and dotsText and dotsText.Parent do
			dotsText.Text = DOT_STATES[index]
			index = index % #DOT_STATES + 1
			task.wait(0.3)
		end
	end)
end

function LoadingScreenHandler:_stopDotsAnimation()
	self._dotsAnimating = false
end

function LoadingScreenHandler:_playIntroSequence()
	local elements = self._elements
	local devFrameTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local devLogoTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local devLogoFadeOutInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local contentTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	
	-- DevLogo frame fade in (background/frame but keep child transparent first)
	self:_applyTransparencyRecursive(elements.devLogoFrame, 1)
	self:_tweenTransparencyRecursive(elements.devLogoFrame, 0, devFrameTweenInfo, false)
	
	-- DevLogo image fade in
	local imgDevLogo = elements.devLogoFrame:FindFirstChild("ImgDevLogo")
	if imgDevLogo then
		self:_tweenTransparencyRecursive(imgDevLogo, 0, devLogoTweenInfo)
	end
	
	task.wait(0.5)
	
	-- DevLogo image fade out
	if imgDevLogo then
		self:_tweenTransparencyRecursive(imgDevLogo, 1, devLogoFadeOutInfo)
	end
	
	-- Game logo background and logo fade in
	self:_tweenTransparencyRecursive(elements.gameLogoFrame, 0, contentTweenInfo, false)
	if elements.backgroundImage then
		self:_tweenTransparencyRecursive(elements.backgroundImage, 0, contentTweenInfo)
	end
	if elements.gameLogoImage then
		self:_tweenTransparencyRecursive(elements.gameLogoImage, 0, contentTweenInfo)
	end
	
	task.wait(contentTweenInfo.Time + contentTweenInfo.DelayTime)
	
	local textTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if elements.loadingText then
		self:_tweenTransparencyRecursive(elements.loadingText, 0, textTweenInfo)
	end
	if elements.dotsText then
		self:_tweenTransparencyRecursive(elements.dotsText, 0, textTweenInfo)
	end
	
	task.wait(textTweenInfo.Time + textTweenInfo.DelayTime)
	self:_startDotsAnimation()
end

function LoadingScreenHandler:_fadeOutAndDisable()
	if self._completed then
		return
	end
	
	self._completed = true
	self:_stopDotsAnimation()
	
	local elements = self._elements
	local hideTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	
	self:_tweenTransparencyRecursive(elements.gameLogoFrame, 1, hideTweenInfo)

	local devFadeInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	self:_tweenTransparencyRecursive(elements.devLogoFrame, 1, devFadeInfo, false)
	
	if elements.dotsText then
		elements.dotsText.Text = "..."
	end
	
	if elements.screenGui then
		elements.screenGui.Enabled = false
	end
end

function LoadingScreenHandler:_tryComplete()
	if self._serverReady and self._clientReady and self._externalReady then
		self:_fadeOutAndDisable()
	end
end

function LoadingScreenHandler:Init(controller)
	if self._initialized then
		return
	end
	
	self._controller = controller
	self._serverReady = false
	self._clientReady = false
	self._externalReady = false
	self._completed = false
	self._dotsAnimating = false
	
	if not self:_cacheUiElements() then
		return
	end
	
	self._initialized = true
end

function LoadingScreenHandler:Cleanup()
	self:_stopDotsAnimation()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
	self._externalReady = false
end

function LoadingScreenHandler:Show()
	if not self._initialized then
		return
	end
	
	self._serverReady = false
	self._clientReady = false
	self._externalReady = false
	self._completed = false
	self._dotsAnimating = false
	
	self:_prepareInitialState()
	task.spawn(function()
		self:_playIntroSequence()
	end)
end

function LoadingScreenHandler:SetServerReady()
	if self._serverReady then return end
	self._serverReady = true
	self:_tryComplete()
end

function LoadingScreenHandler:SetClientReady()
	if self._clientReady then return end
	self._clientReady = true
	self:_tryComplete()
end

function LoadingScreenHandler:SetExternalReady()
	if self._externalReady then return end
	self._externalReady = true
	self:_tryComplete()
end

return LoadingScreenHandler

