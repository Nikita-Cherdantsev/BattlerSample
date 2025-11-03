--[[
	RewardsHandler - Client-side post-battle rewards UI controller
	
	Handles displaying rewards after battle completion (loss or victory).
	Manages reward claiming, lootbox slot management, and pack selector UI.
]]

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

--// Module
local RewardsHandler = {}

--// State
RewardsHandler.Connections = {}
RewardsHandler._initialized = false
RewardsHandler.currentReward = nil -- {type = "soft" | "lootbox", amount = number, rarity = string (for lootbox)}
RewardsHandler.isWaitingForSlot = false -- True when waiting for player to free up a slot
RewardsHandler.pendingLootboxReward = nil -- Stores lootbox reward when no slots available

--// Constants
local SOFT_CURRENCY_MIN = 10
local SOFT_CURRENCY_MAX = 100

--// Initialization
function RewardsHandler:Init(controller)
	self.Controller = controller
	self.ClientState = controller:GetClientState()
	
	-- Safe require of Utilities to avoid loading errors
	local success, utilities = pcall(function()
		return controller:GetModule("Utilities")
	end)
	
	if success then
		self.Utilities = utilities
	else
		warn("RewardsHandler: Could not load Utilities module: " .. tostring(utilities))
		self.Utilities = {
			TweenUI = { FadeIn = function() end, FadeOut = function() end },
			Blur = { Show = function() end, Hide = function() end }
		}
	end
	
	-- Directly require Manifest module
	local manifestSuccess, manifest = pcall(function()
		return require(ReplicatedStorage.Modules.Assets.Manifest)
	end)
	
	if manifestSuccess then
		self.Manifest = manifest
	else
		warn("RewardsHandler: Could not load Manifest module: " .. tostring(manifest))
		self.Manifest = { 
			Currency = { Soft = { Big = "" } },
			Lootbox = {}
		}
	end
	
	-- Get NetworkClient for server requests
	local networkClientSuccess, networkClient = pcall(function()
		return require(game.StarterPlayer.StarterPlayerScripts.Controllers.NetworkClient)
	end)
	
	if networkClientSuccess then
		self.NetworkClient = networkClient
	else
		warn("RewardsHandler: Could not load NetworkClient: " .. tostring(networkClient))
		self.NetworkClient = nil
	end
	
	-- Get LootboxUIHandler for pack selector logic
	self.LootboxHandler = nil -- Will be set when needed
	
	-- Setup rewards UI
	self:SetupRewardsUI()
	
	-- Setup ProfileUpdated handler to detect when slots are freed
	self:SetupProfileUpdatedHandler()
	
	self._initialized = true
	print("✅ RewardsHandler initialized successfully!")
	return true
end

function RewardsHandler:SetupRewardsUI()
	-- Access UI from player's PlayerGui
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Wait for GameUI
	local gameGui = playerGui:WaitForChild("GameUI", 10)
	if not gameGui then
		warn("RewardsHandler: GameUI not found in PlayerGui")
		-- Debug: print all children
		for _, child in pairs(playerGui:GetChildren()) do
			print("RewardsHandler: PlayerGui child:", child.Name, child.ClassName)
		end
		return
	end
	
	-- Debug: print all GameUI children
	print("RewardsHandler: Searching for Rewards frame in GameUI...")
	for _, child in pairs(gameGui:GetChildren()) do
		print("RewardsHandler: GameUI child:", child.Name, child.ClassName)
	end
	
	-- Find Rewards frame (could be named "Rewards" or check alternative names)
	self.RewardsFrame = gameGui:FindFirstChild("Rewards")
	
	-- Try alternative names if not found
	if not self.RewardsFrame then
		self.RewardsFrame = gameGui:FindFirstChild("BattleRewards")
	end
	if not self.RewardsFrame then
		self.RewardsFrame = gameGui:FindFirstChild("Reward")
	end
	
	if not self.RewardsFrame then
		warn("RewardsHandler: Rewards frame not found in GameUI (searched: Rewards, BattleRewards, Reward)")
		warn("RewardsHandler: Available frames in GameUI:")
		for _, child in pairs(gameGui:GetChildren()) do
			if child:IsA("Frame") or child:IsA("ScreenGui") then
				warn("  - " .. child.Name .. " (" .. child.ClassName .. ")")
			end
		end
		return
	end
	
	print("✅ RewardsHandler: Found Rewards frame:", self.RewardsFrame.Name)
	
	-- Store UI references
	self.UI = gameGui
	
	-- Find buttons
	local buttonsFrame = self.RewardsFrame:FindFirstChild("Buttons")
	if buttonsFrame then
		self.BtnClaim = buttonsFrame:FindFirstChild("BtnClaim")
		self.BtnDestroy = buttonsFrame:FindFirstChild("BtnDestroy")
	else
		warn("RewardsHandler: Buttons frame not found")
	end
	
	-- Find Loss frame and components
	self.LossFrame = self.RewardsFrame:FindFirstChild("Loss")
	if self.LossFrame then
		local lossContent = self.LossFrame:FindFirstChild("Content")
		if lossContent then
			local innerContent = lossContent:FindFirstChild("Content")
			if innerContent then
				local rewardFrame = innerContent:FindFirstChild("Reward")
				if rewardFrame then
					local rewardContent = rewardFrame:FindFirstChild("Content")
					if rewardContent then
						self.LossImgReward = rewardContent:FindFirstChild("ImgReward")
						self.LossTxtValue = rewardContent:FindFirstChild("TxtValue")
					end
				end
			end
		end
	end
	
	-- Find Victory frame and components
	self.VictoryFrame = self.RewardsFrame:FindFirstChild("Victory")
	if self.VictoryFrame then
		local victoryContent = self.VictoryFrame:FindFirstChild("Content")
		if victoryContent then
			local innerContent = victoryContent:FindFirstChild("Content")
			if innerContent then
				local rewardFrame = innerContent:FindFirstChild("Reward")
				if rewardFrame then
					local rewardContent = rewardFrame:FindFirstChild("Content")
					if rewardContent then
						self.VictoryImgReward = rewardContent:FindFirstChild("ImgReward")
						self.VictoryTxtValue = rewardContent:FindFirstChild("TxtValue")
					end
				end
			end
		end
	end
	
	-- Find PackSelector frame
	self.PackSelectorFrame = self.RewardsFrame:FindFirstChild("PacksSelector")
	
	-- Setup button handlers
	self:SetupButtonHandlers()
	
	-- Hide rewards frame initially
	self.RewardsFrame.Visible = false
	
	print("✅ RewardsHandler: Rewards UI setup completed")
end

function RewardsHandler:SetupButtonHandlers()
	-- Setup BtnClaim
	if self.BtnClaim and self.BtnClaim:IsA("TextButton") then
		local connection = self.BtnClaim.MouseButton1Click:Connect(function()
			self:OnClaimButtonClicked()
		end)
		table.insert(self.Connections, connection)
	end
	
	-- Setup BtnDestroy
	if self.BtnDestroy and self.BtnDestroy:IsA("TextButton") then
		local connection = self.BtnDestroy.MouseButton1Click:Connect(function()
			self:OnDestroyButtonClicked()
		end)
		table.insert(self.Connections, connection)
	end
end

function RewardsHandler:SetupProfileUpdatedHandler()
	-- Listen for ProfileUpdated events to detect when slots are freed
	local ProfileUpdated = game.ReplicatedStorage.Network:WaitForChild("ProfileUpdated")
	
	local connection = ProfileUpdated.OnClientEvent:Connect(function(payload)
		-- Update PackSelector states if it's visible (using LootboxUIHandler's logic)
		if self.PackSelectorFrame and self.PackSelectorFrame.Visible and self.LootboxHandler then
			task.spawn(function()
				task.wait(0.1) -- Small delay to ensure profile is updated
				if self.LootboxHandler.UpdateLootboxStates then
					self.LootboxHandler:UpdateLootboxStates(nil, "PackSelector")
				end
			end)
		end
		
		if not payload.error and self.isWaitingForSlot then
			-- Check if we now have a free slot (a lootbox was opened/removed)
			if payload.lootboxes then
				local currentCount = #payload.lootboxes
				local previousCount = 0
				if self.ClientState and self.ClientState.getProfile then
					local profile = self.ClientState:getProfile()
					if profile and profile.lootboxes then
						previousCount = #profile.lootboxes
					end
				end
				
				-- Slot was freed if count decreased
				if currentCount < previousCount and self.pendingLootboxReward then
					-- Wait for lootbox opening animation to complete (rewards will be shown automatically)
					-- The reward lootbox will be added after animation via the lootbox handler's ProfileUpdated
					-- So we just wait a bit and then add the pending reward
					task.spawn(function()
						-- Wait for opening animation to complete (~5 seconds based on LootboxUIHandler)
						task.wait(6)
						self:AddPendingLootboxReward()
					end)
				end
			end
		end
	end)
	
	table.insert(self.Connections, connection)
end

-- Show rewards after battle
function RewardsHandler:ShowRewards(battleResult, isVictory, battleRewards)
	print("🎁 RewardsHandler:ShowRewards called")
	print("🎁 RewardsHandler: _initialized =", self._initialized)
	print("🎁 RewardsHandler: isVictory =", isVictory)
	print("🎁 RewardsHandler: battleRewards =", battleRewards and "present" or "nil")
	
	if not self._initialized then
		warn("RewardsHandler: Not initialized")
		return
	end
	
	-- Store rewards from server (generated server-side)
	if battleRewards then
		self.currentReward = battleRewards
		print("🎁 RewardsHandler: Stored reward - type =", battleRewards.type, "amount/rarity =", battleRewards.amount or battleRewards.rarity)
	else
		-- Fallback: should not happen if server sends rewards
		warn("RewardsHandler: No rewards in battle result, using fallback")
		if isVictory then
			self.currentReward = {
				type = "lootbox",
				rarity = "uncommon",
				count = 1
			}
		else
			self.currentReward = {
				type = "soft",
				amount = 50 -- Fallback amount
			}
		end
	end
	
	if isVictory then
		print("🎁 RewardsHandler: Showing victory rewards")
		self:ShowVictoryRewards(battleResult)
	else
		print("🎁 RewardsHandler: Showing loss rewards")
		self:ShowLossRewards(battleResult)
	end
end

function RewardsHandler:ShowLossRewards(battleResult)
	print("🎁 RewardsHandler:ShowLossRewards called")
	-- Use reward from server
	local softAmount = self.currentReward.amount or 50
	print("🎁 RewardsHandler: Soft currency amount =", softAmount)
	
	-- Show Loss frame, hide others
	if self.LossFrame then 
		self.LossFrame.Visible = true 
		print("🎁 RewardsHandler: Loss frame set to visible")
	else
		warn("🎁 RewardsHandler: LossFrame not found!")
	end
	if self.VictoryFrame then self.VictoryFrame.Visible = false end
	if self.PackSelectorFrame then self.PackSelectorFrame.Visible = false end
	
	-- Enable BtnClaim, disable BtnDestroy
	if self.BtnClaim then
		self.BtnClaim.Visible = true
		self.BtnClaim.Active = true
		print("🎁 RewardsHandler: BtnClaim enabled")
	else
		warn("🎁 RewardsHandler: BtnClaim not found!")
	end
	if self.BtnDestroy then
		self.BtnDestroy.Visible = false
		self.BtnDestroy.Active = false
	end
	
	-- Fill Loss frame with reward info
	if self.LossImgReward then
		self.LossImgReward.Image = self.Manifest.Currency.Soft.Big
		print("🎁 RewardsHandler: Set LossImgReward image")
	else
		warn("🎁 RewardsHandler: LossImgReward not found!")
	end
	if self.LossTxtValue then
		self.LossTxtValue.Text = tostring(softAmount)
		print("🎁 RewardsHandler: Set LossTxtValue to", softAmount)
	else
		warn("🎁 RewardsHandler: LossTxtValue not found!")
	end
	
	-- Show Rewards frame
	print("🎁 RewardsHandler: Calling ShowRewardsFrame")
	self:ShowRewardsFrame()
end

function RewardsHandler:ShowVictoryRewards(battleResult)
	-- Use reward from server
	local rarity = self.currentReward.rarity or "uncommon"
	
	-- Check if player has free slots
	local profile = self.ClientState:getProfile()
	local hasFreeSlot = false
	if profile and profile.lootboxes then
		hasFreeSlot = #profile.lootboxes < 4
	end
	
	-- Show Victory frame, hide Loss
	if self.VictoryFrame then self.VictoryFrame.Visible = true end
	if self.LossFrame then self.LossFrame.Visible = false end
	
	-- Fill Victory frame with reward info
	if self.VictoryImgReward then
		self.VictoryImgReward.Image = self.Manifest.Lootbox[rarity] or ""
	end
	if self.VictoryTxtValue then
		self.VictoryTxtValue.Text = "1"
	end
	
	if hasFreeSlot then
		-- Player has free slot - simple claim
		self:ShowVictoryRewardsFreeSlot()
	else
		-- Player has no free slots - show pack selector
		self:ShowVictoryRewardsNoSlot()
	end
end

function RewardsHandler:ShowVictoryRewardsFreeSlot()
	-- Hide PackSelector, enable BtnClaim, disable BtnDestroy
	if self.PackSelectorFrame then self.PackSelectorFrame.Visible = false end
	if self.BtnClaim then
		self.BtnClaim.Visible = true
		self.BtnClaim.Active = true
	end
	if self.BtnDestroy then
		self.BtnDestroy.Visible = false
		self.BtnDestroy.Active = false
	end
	
	-- Show Rewards frame
	self:ShowRewardsFrame()
end

function RewardsHandler:ShowVictoryRewardsNoSlot()
	-- Show PackSelector, enable BtnDestroy, disable BtnClaim
	if self.PackSelectorFrame then self.PackSelectorFrame.Visible = true end
	if self.BtnClaim then
		self.BtnClaim.Visible = false
		self.BtnClaim.Active = false
	end
	if self.BtnDestroy then
		self.BtnDestroy.Visible = true
		self.BtnDestroy.Active = true
	end
	
	-- Setup PackSelector with lootboxes
	self:SetupPackSelector()
	
	-- Show Rewards frame
	self:ShowRewardsFrame()
	
	-- Store pending reward
	self.isWaitingForSlot = true
	self.pendingLootboxReward = self.currentReward
end

function RewardsHandler:SetupPackSelector()
	print("🎁 RewardsHandler: Setting up PackSelector")
	
	-- Get LootboxUIHandler to reuse its logic
	if not self.LootboxHandler then
		self.LootboxHandler = self.Controller:GetLootboxHandler()
	end
	
	if not self.LootboxHandler then
		warn("RewardsHandler: LootboxHandler not available")
		return
	end
	
	-- Find packs container in PackSelector (same structure as BottomPanel)
	local packsContainer = nil
	if self.PackSelectorFrame then
		-- Try to find Packs frame with same structure as BottomPanel
		packsContainer = self.PackSelectorFrame:FindFirstChild("Packs")
		if packsContainer then
			local outline = packsContainer:FindFirstChild("Outline")
			if outline then
				packsContainer = outline:FindFirstChild("Content")
			end
		end
		
		-- Alternative: try direct Content path
		if not packsContainer then
			local content = self.PackSelectorFrame:FindFirstChild("Content")
			if content then
				packsContainer = content:FindFirstChild("Packs")
				if packsContainer then
					local outline = packsContainer:FindFirstChild("Outline")
					if outline then
						packsContainer = outline:FindFirstChild("Content")
					end
				end
			end
		end
	end
	
	if not packsContainer then
		warn("RewardsHandler: Packs container not found in PackSelector")
		-- Debug: print all children
		if self.PackSelectorFrame then
			print("RewardsHandler: PackSelectorFrame children:")
			for _, child in pairs(self.PackSelectorFrame:GetDescendants()) do
				if child.Name == "Pack1" or child.Name == "Pack2" or child.Name == "Pack3" or child.Name == "Pack4" then
					print("  Found:", child.Name, "at", child:GetFullName())
				end
			end
		end
		return
	end
	
	print("🎁 RewardsHandler: Found PackSelector packs container")
	
	-- Use LootboxUIHandler's reusable setup method
	if self.LootboxHandler.SetupPacksForContainer then
		local success = self.LootboxHandler:SetupPacksForContainer("PackSelector", packsContainer)
		if success then
			print("🎁 RewardsHandler: PackSelector packs initialized via LootboxUIHandler")
			
			-- Setup button handlers for PackSelector (since SetupPacksForContainer only sets up BottomPanel buttons)
			local containerData = self.LootboxHandler.packContainers["PackSelector"]
			if containerData then
				for i = 1, 4 do
					local pack = containerData.packs[i]
					if pack then
						-- Setup button handlers
						if pack.btnUnlock and pack.btnUnlock:IsA("TextButton") then
							local connection = pack.btnUnlock.MouseButton1Click:Connect(function()
								if self.NetworkClient then
									self.NetworkClient.requestStartUnlock(pack.slotIndex)
								end
							end)
							table.insert(self.Connections, connection)
						end
						
						if pack.btnOpen and pack.btnOpen:IsA("TextButton") then
							local connection = pack.btnOpen.MouseButton1Click:Connect(function()
								if self.NetworkClient then
									self.NetworkClient.requestOpenNow(pack.slotIndex)
								end
							end)
							table.insert(self.Connections, connection)
						end
						
						if pack.btnSpeedUp and pack.btnSpeedUp:IsA("TextButton") then
							local connection = pack.btnSpeedUp.MouseButton1Click:Connect(function()
								if self.NetworkClient then
									self.NetworkClient.requestSpeedUp(pack.slotIndex)
								end
							end)
							table.insert(self.Connections, connection)
						end
					end
				end
			end
		else
			warn("RewardsHandler: Failed to setup PackSelector packs")
		end
	end
	
	-- Update pack states using LootboxUIHandler's logic
	if self.LootboxHandler.UpdateLootboxStates then
		self.LootboxHandler:UpdateLootboxStates(nil, "PackSelector")
	end
	
	print("🎁 RewardsHandler: PackSelector setup completed")
end

function RewardsHandler:OnClaimButtonClicked()
	if not self.currentReward then
		return
	end
	
	-- Request server to grant reward
	if not self.NetworkClient then
		warn("RewardsHandler: NetworkClient not available")
		return
	end
	
	local requestData = {}
	if self.currentReward.type == "soft" then
		requestData.rewardType = "soft"
		requestData.amount = self.currentReward.amount
	elseif self.currentReward.type == "lootbox" then
		requestData.rewardType = "lootbox"
		requestData.rarity = self.currentReward.rarity
	else
		warn("RewardsHandler: Unknown reward type:", self.currentReward.type)
		return
	end
	
	-- Call server to grant reward
	if self.NetworkClient.requestClaimBattleReward then
		self.NetworkClient.requestClaimBattleReward(requestData)
		-- Close rewards and complete battle
		self:CloseRewards()
	else
		warn("RewardsHandler: NetworkClient.requestClaimBattleReward not available")
	end
end

function RewardsHandler:OnDestroyButtonClicked()
	-- Player chose to destroy reward - don't grant anything
	-- Close rewards and complete battle
	self.pendingLootboxReward = nil
	self.isWaitingForSlot = false
	self:CloseRewards()
end

function RewardsHandler:GrantLootboxReward()
	if not self.currentReward or self.currentReward.type ~= "lootbox" then
		return
	end
	
	-- Request server to add lootbox
	if not self.NetworkClient then
		warn("RewardsHandler: NetworkClient not available")
		return
	end
	
	local requestData = {
		rewardType = "lootbox",
		rarity = self.currentReward.rarity
	}
	
	if self.NetworkClient.requestClaimBattleReward then
		self.NetworkClient.requestClaimBattleReward(requestData)
	else
		warn("RewardsHandler: NetworkClient.requestClaimBattleReward not available")
	end
end

function RewardsHandler:AddPendingLootboxReward()
	if not self.pendingLootboxReward then
		return
	end
	
	-- Grant the pending lootbox
	self.currentReward = self.pendingLootboxReward
	self:GrantLootboxReward()
	
	-- Reset state
	self.pendingLootboxReward = nil
	self.isWaitingForSlot = false
	
	-- Close rewards and complete battle
	self:CloseRewards()
end

function RewardsHandler:ShowRewardsFrame()
	print("🎁 RewardsHandler:ShowRewardsFrame called")
	if not self.RewardsFrame then
		warn("🎁 RewardsHandler: RewardsFrame not found!")
		return
	end
	
	print("🎁 RewardsHandler: Setting RewardsFrame visible")
	self.RewardsFrame.Visible = true
	
	-- Use TweenUI if available
	if self.Utilities and self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
		print("🎁 RewardsHandler: Using TweenUI.FadeIn")
		self.Utilities.TweenUI.FadeIn(self.RewardsFrame, 0.3)
	else
		print("🎁 RewardsHandler: TweenUI not available, just setting visible")
	end
end

function RewardsHandler:CloseRewards()
	if not self.RewardsFrame then
		return
	end
	
	-- Use TweenUI if available
	if self.Utilities and self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
		self.Utilities.TweenUI.FadeOut(self.RewardsFrame, 0.3, function()
			self.RewardsFrame.Visible = false
			-- Reset state
			self.currentReward = nil
			self.isWaitingForSlot = false
			self.pendingLootboxReward = nil
		end)
	else
		self.RewardsFrame.Visible = false
		-- Reset state
		self.currentReward = nil
		self.isWaitingForSlot = false
		self.pendingLootboxReward = nil
	end
end

--// Cleanup
function RewardsHandler:Cleanup()
	-- Disconnect all connections
	for _, connection in ipairs(self.Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self.Connections = {}
	
	self._initialized = false
end

return RewardsHandler

