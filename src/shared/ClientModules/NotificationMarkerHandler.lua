--[[
	NotificationMarkerHandler - Universal notification marker handler for LeftPanel buttons
	
	Manages notification markers on LeftPanel buttons, showing/hiding them based on
	various triggers (e.g., uncollected rewards, new items in collection, etc.)
	
	Uses event-driven approach: handlers directly call SetMarkerVisible/SetMarkerHidden
	instead of periodic polling.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Module
local NotificationMarkerHandler = {}

-- State
NotificationMarkerHandler._initialized = false
NotificationMarkerHandler.LeftPanel = nil

-- Marker state tracking
NotificationMarkerHandler.markers = {} -- { buttonName -> { marker, tween, isVisible } }

-- Constants
local PULSE_DURATION = 1.5 -- Duration of one pulse cycle in seconds
local PULSE_SCALE_MIN = 0.8 -- Minimum scale during pulse
local PULSE_SCALE_MAX = 1.1 -- Maximum scale during pulse

--// Initialization
function NotificationMarkerHandler:Init(controller)
	if self._initialized then
		warn("NotificationMarkerHandler: Already initialized")
		return true
	end
	
	-- Setup UI
	self:SetupUI()
	
	-- Register default markers
	self:RegisterDefaultMarkers()
	
	-- No need to check PlaytimeHandler here - it will call us when ready
	-- PlaytimeHandler is responsible for updating markers when data is available
	
	self._initialized = true
	print("✅ NotificationMarkerHandler initialized successfully!")
	return true
end

function NotificationMarkerHandler:SetupUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Wait for GameUI
	local gameGui = playerGui:WaitForChild("GameUI", 10)
	if not gameGui then
		warn("NotificationMarkerHandler: GameUI not found in PlayerGui")
		return
	end
	
	-- Get LeftPanel
	local leftPanel = gameGui:FindFirstChild("LeftPanel")
	if not leftPanel then
		warn("NotificationMarkerHandler: LeftPanel not found in GameUI")
		return
	end
	
	self.LeftPanel = leftPanel
end

function NotificationMarkerHandler:RegisterDefaultMarkers()
	-- Register marker for BtnPlaytime
	-- PlaytimeHandler will manage visibility directly
	self:RegisterMarker("BtnPlaytime")
end

-- Register a marker for a button
-- buttonName: Name of the button in LeftPanel (e.g., "BtnPlaytime")
function NotificationMarkerHandler:RegisterMarker(buttonName)
	if not self.LeftPanel then
		warn("NotificationMarkerHandler: Cannot register marker - LeftPanel not found")
		return
	end
	
	local button = self.LeftPanel:FindFirstChild(buttonName)
	if not button then
		warn("NotificationMarkerHandler: Button '" .. buttonName .. "' not found in LeftPanel")
		return
	end
	
	local marker = button:FindFirstChild("Marker")
	if not marker then
		warn("NotificationMarkerHandler: Marker not found for button '" .. buttonName .. "'")
		return
	end

	local effect = marker:FindFirstChild("Effect")
	local emitter = nil
	if effect then
		emitter = effect:FindFirstChild("Emitter")
	end
	
	-- Ensure marker is hidden by default
	marker.Visible = false
	
	-- Store base scale for proper restoration
	local baseScaleX = marker.Size.X.Scale
	local baseScaleY = marker.Size.Y.Scale
	
	-- Store marker info
	self.markers[buttonName] = {
		marker = marker,
		emitter = emitter,
		tween = nil,
		isVisible = false,
		baseScaleX = baseScaleX,
		baseScaleY = baseScaleY
	}
	
	print("✅ NotificationMarkerHandler: Registered marker for " .. buttonName)
end

-- Set marker visibility (called by handlers when status changes)
-- buttonName: Name of the button (e.g., "BtnPlaytime")
-- visible: true to show, false to hide
function NotificationMarkerHandler:SetMarkerVisible(buttonName, visible)
	local markerData = self.markers[buttonName]
	if not markerData then
		warn("NotificationMarkerHandler: Marker not registered for " .. buttonName)
		return
	end
	
	if visible == markerData.isVisible then
		return -- Already in desired state
	end
	
	if visible then
		self:ShowMarker(buttonName)
	else
		self:HideMarker(buttonName)
	end
end

-- Show marker and start pulse animation
function NotificationMarkerHandler:ShowMarker(buttonName)
	local markerData = self.markers[buttonName]
	if not markerData then return end
	
	if markerData.isVisible then return end -- Already visible
	
	markerData.isVisible = true
	
	-- Set initial scale to MIN before showing
	local marker = markerData.marker
	marker.Size = UDim2.new(
		markerData.baseScaleX * PULSE_SCALE_MIN,
		0,
		markerData.baseScaleY * PULSE_SCALE_MIN,
		0
	)
	
	marker.Visible = true
	markerData.emitter:FindFirstChild("Emit"):Fire()
	
	-- Start pulse animation
	self:StartPulseAnimation(buttonName)
	
	print("✅ NotificationMarkerHandler: Showing marker for " .. buttonName)
end

-- Hide marker and stop pulse animation
function NotificationMarkerHandler:HideMarker(buttonName)
	local markerData = self.markers[buttonName]
	if not markerData then return end
	
	if not markerData.isVisible then return end -- Already hidden
	
	markerData.isVisible = false
	
	-- Stop pulse animation
	if markerData.tween then
		markerData.tween:Cancel()
		markerData.tween = nil
	end
	
	-- Reset scale to base
	local marker = markerData.marker
	marker.Size = UDim2.new(
		markerData.baseScaleX,
		0,
		markerData.baseScaleY,
		0
	)
	
	markerData.emitter:FindFirstChild("Clear"):Fire()
	marker.Visible = false
	
	print("✅ NotificationMarkerHandler: Hiding marker for " .. buttonName)
end

-- Start pulse animation for a marker
function NotificationMarkerHandler:StartPulseAnimation(buttonName)
	local markerData = self.markers[buttonName]
	if not markerData or not markerData.isVisible then return end
	
	-- Cancel existing tween if any
	if markerData.tween then
		markerData.tween:Cancel()
	end
	
	local marker = markerData.marker
	
	-- Create pulse tween (scale from MIN to MAX and back in a loop)
	-- Current scale is at MIN, goal is at MAX
	local tweenInfo = TweenInfo.new(
		PULSE_DURATION / 2,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1, -- Repeat infinitely
		true -- Reverse
	)
	
	local goal = {
		Size = UDim2.new(
			markerData.baseScaleX * PULSE_SCALE_MAX,
			0,
			markerData.baseScaleY * PULSE_SCALE_MAX,
			0
		)
	}
	
	markerData.tween = TweenService:Create(marker, tweenInfo, goal)
	markerData.tween:Play()
end

--// Public Methods
function NotificationMarkerHandler:IsInitialized()
	return self._initialized
end

--// Cleanup
function NotificationMarkerHandler:Cleanup()
	if not self._initialized then
		return
	end
	
	-- Stop all animations and hide markers
	for buttonName, markerData in pairs(self.markers) do
		if markerData.tween then
			markerData.tween:Cancel()
			markerData.tween = nil
		end
		if markerData.marker then
			markerData.marker.Visible = false
		end
	end
	
	self.markers = {}
	self._initialized = false
	
	print("✅ NotificationMarkerHandler cleaned up")
end

return NotificationMarkerHandler

