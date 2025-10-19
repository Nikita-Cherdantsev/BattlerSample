--[[
	Close Button Handler
	
	Manages the visibility and functionality of the close button in TopPanel.
	Coordinates between different modules (Daily, Playtime, Deck) to show/hide
	the close button when frames are opened/closed.
]]

local CloseButtonHandler = {}
CloseButtonHandler.__index = CloseButtonHandler

-- Singleton instance
local _instance = nil

-- UI References
CloseButtonHandler.UI = nil
CloseButtonHandler.CloseButton = nil
CloseButtonHandler.CloseButtonFrame = nil

-- State tracking
CloseButtonHandler.openFrames = {} -- Track which frames are currently open
CloseButtonHandler.frameStack = {} -- Track the order of opened frames (most recent last)
CloseButtonHandler.isInitialized = false

-- Initialize the close button handler
function CloseButtonHandler.Init()
	if _instance then
		return _instance
	end
	
	local self = setmetatable({}, CloseButtonHandler)
	
	if self:SetupCloseButtonUI() then
		self.isInitialized = true
		_instance = self
	end
	
	return self
end

-- Get the singleton instance
function CloseButtonHandler.GetInstance()
	return _instance
end

-- Setup close button UI elements
function CloseButtonHandler:SetupCloseButtonUI()
	-- Wait for GameUI to be available
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	
	local gameUI = player:WaitForChild("PlayerGui"):WaitForChild("GameUI", 15)
	if not gameUI then
		warn("❌ CloseButtonHandler: GameUI not found")
		return false
	end
	
	-- Find close button in TopPanel
	local topPanel = gameUI:FindFirstChild("TopPanel")
	if not topPanel then
		warn("❌ CloseButtonHandler: TopPanel not found")
		return false
	end
	
	local btnCloseFrame = topPanel:FindFirstChild("BtnClose")
	if not btnCloseFrame then
		warn("❌ CloseButtonHandler: BtnClose frame not found")
		return false
	end
	
	-- Store the frame reference
	self.CloseButtonFrame = btnCloseFrame
	
	-- Find the actual button inside the frame
	self.CloseButton = btnCloseFrame:FindFirstChild("Button")
	if not self.CloseButton then
		warn("❌ CloseButtonHandler: Button not found inside BtnClose frame")
		return false
	end
	
	-- Initially hide the close button
	self:SetCloseButtonVisible(false)
	
	-- Connect close button click
	self.CloseButton.MouseButton1Click:Connect(function()
		self:HandleCloseButtonClick()
	end)
	
	return true
end

-- Set close button visibility
function CloseButtonHandler:SetCloseButtonVisible(visible)
	if not self.CloseButton or not self.CloseButtonFrame then
		warn("❌ CloseButtonHandler: Cannot set visibility - missing button or frame references")
		return
	end
	
	-- Set both frame and button properties
	self.CloseButtonFrame.Visible = visible
	self.CloseButtonFrame.Active = visible
	self.CloseButton.Visible = visible
	self.CloseButton.Active = visible
end

-- Register a frame as opened
function CloseButtonHandler:RegisterFrameOpen(frameName)
	if not self.openFrames[frameName] then
		self.openFrames[frameName] = true
		-- Add to frame stack (most recent at the end)
		table.insert(self.frameStack, frameName)
		self:UpdateCloseButtonVisibility()
	end
end

-- Register a frame as closed
function CloseButtonHandler:RegisterFrameClosed(frameName)
	if self.openFrames[frameName] then
		self.openFrames[frameName] = nil
		-- Remove from frame stack
		for i = #self.frameStack, 1, -1 do
			if self.frameStack[i] == frameName then
				table.remove(self.frameStack, i)
				break
			end
		end
		self:UpdateCloseButtonVisibility()
	end
end

-- Update close button visibility based on open frames
function CloseButtonHandler:UpdateCloseButtonVisibility()
	local hasOpenFrames = false
	for frameName, isOpen in pairs(self.openFrames) do
		if isOpen then
			hasOpenFrames = true
			break
		end
	end
	
	self:SetCloseButtonVisible(hasOpenFrames)
end

-- Get list of open frame names
function CloseButtonHandler:GetOpenFrameNames()
	local openFrames = {}
	for frameName, isOpen in pairs(self.openFrames) do
		if isOpen then
			table.insert(openFrames, frameName)
		end
	end
	return openFrames
end

-- Handle close button click
function CloseButtonHandler:HandleCloseButtonClick()
	-- Close only the most recent frame (last in stack)
	if #self.frameStack > 0 then
		local mostRecentFrame = self.frameStack[#self.frameStack]
		self:CloseFrame(mostRecentFrame)
	end
end

-- Close a specific frame by name
function CloseButtonHandler:CloseFrame(frameName)
	if frameName == "Daily" then
		-- Close Daily frame
		local DailyHandler = require(game.ReplicatedStorage.ClientModules.DailyHandler)
		if DailyHandler and DailyHandler.CloseFrame then
			DailyHandler:CloseFrame()
		end
	elseif frameName == "Playtime" then
		-- Close Playtime frame
		local PlaytimeHandler = require(game.ReplicatedStorage.ClientModules.PlaytimeHandler)
		if PlaytimeHandler and PlaytimeHandler.CloseFrame then
			PlaytimeHandler:CloseFrame()
		end
	elseif frameName == "Deck" then
		-- Close Deck frame
		local DeckHandler = require(game.ReplicatedStorage.ClientModules.DeckHandler)
		if DeckHandler and DeckHandler.CloseFrame then
			DeckHandler:CloseFrame()
		end
	elseif frameName == "CardInfo" then
		-- Close CardInfo frame
		local CardInfoHandler = require(game.ReplicatedStorage.ClientModules.CardInfoHandler)
		if CardInfoHandler and CardInfoHandler.CloseFrame then
			CardInfoHandler:CloseFrame()
		end
	end
end

-- Cleanup
function CloseButtonHandler:Cleanup()
	self.openFrames = {}
	self.frameStack = {}
	self.isInitialized = false
	_instance = nil
end

return CloseButtonHandler
