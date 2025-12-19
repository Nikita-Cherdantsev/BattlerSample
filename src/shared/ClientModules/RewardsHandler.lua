--[[
	RewardsHandler - Client-side post-battle rewards UI controller
	
	Handles displaying rewards after battle completion (loss or victory).
	Manages reward claiming, lootbox slot management, and pack selector UI.
]]

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--// Modules
local EventBus = require(ReplicatedStorage.Modules.EventBus)

--// Module
local RewardsHandler = {}

--// State
RewardsHandler.Connections = {}
RewardsHandler._initialized = false
RewardsHandler.currentReward = nil -- {type = "soft" | "lootbox", amount = number, rarity = string (for lootbox)}
RewardsHandler.isWaitingForSlot = false -- True when waiting for player to free up a slot
RewardsHandler.pendingLootboxReward = nil -- Stores lootbox reward when no slots available
RewardsHandler.pendingClaimUpdate = false -- True when waiting for ProfileUpdated after claiming reward

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
	
	-- Find PackSelector text elements
	if self.PackSelectorFrame then
		self.TxtDescription = self.PackSelectorFrame:FindFirstChild("TxtDescription")
		self.TxtOr = self.PackSelectorFrame:FindFirstChild("TxtOr")
	end
	
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
			-- Emit button click event
			EventBus:Emit("ButtonClicked", "Reward.Buttons.BtnClaim")
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
				-- Update text visibility after state update
				self:UpdatePackSelectorTextVisibility()
			end)
		end
		
		if not payload.error then
			-- Handle pending claim update - wait for panel update, then close
			if self.pendingClaimUpdate then
				-- Check if this is a victory (lootbox reward) or loss (soft reward)
				local isVictory = self.currentReward and self.currentReward.type == "lootbox"
				
				if isVictory then
					-- For victory: wait for lootbox to be added to profile
					local previousLootboxCount = 0
					if self.LootboxHandler and self.LootboxHandler.currentProfile and self.LootboxHandler.currentProfile.lootboxes then
						previousLootboxCount = #self.LootboxHandler.currentProfile.lootboxes
					end
					
					local currentLootboxCount = payload.lootboxes and #payload.lootboxes or 0
					
					-- Only proceed if lootbox count increased (lootbox was added)
					if currentLootboxCount > previousLootboxCount then
						self.pendingClaimUpdate = false
						
						-- Update PackSelectorFrame to show the new lootbox
						if self.PackSelectorFrame and self.PackSelectorFrame.Visible and self.LootboxHandler then
							-- Victory case: update panel and wait before closing
							task.spawn(function()
								-- CRITICAL: Update LootboxHandler's currentProfile BEFORE calling UpdateLootboxStates
								if self.LootboxHandler.currentProfile then
									if payload.lootboxes then
										self.LootboxHandler.currentProfile.lootboxes = payload.lootboxes
									end
									if payload.pendingLootbox then
										self.LootboxHandler.currentProfile.pendingLootbox = payload.pendingLootbox
									else
										self.LootboxHandler.currentProfile.pendingLootbox = nil
									end
									if payload.currencies then
										self.LootboxHandler.currentProfile.currencies = payload.currencies
									end
								end

								if self.LootboxHandler.UpdateLootboxStates then
									self.LootboxHandler:UpdateLootboxStates(nil, "PackSelector")
								end
								
								-- Update text visibility after state update
								self:UpdatePackSelectorTextVisibility()
								
								-- Wait a bit more so user can see the update
								task.wait(0.5)
								
								-- Close rewards window
								self:CloseRewards()
							end)
						else
							-- PackSelector not visible, close immediately
							self:CloseRewards()
						end
					else
						-- Update profile but don't close yet
						if self.LootboxHandler and self.LootboxHandler.currentProfile then
							if payload.lootboxes then
								self.LootboxHandler.currentProfile.lootboxes = payload.lootboxes
							end
							if payload.pendingLootbox then
								self.LootboxHandler.currentProfile.pendingLootbox = payload.pendingLootbox
							else
								self.LootboxHandler.currentProfile.pendingLootbox = nil
							end
							if payload.currencies then
								self.LootboxHandler.currentProfile.currencies = payload.currencies
							end
						end
					end
				else
					-- Loss case: close immediately without delay
					self.pendingClaimUpdate = false
					self:CloseRewards()
				end
				return
			end
			
			-- Check if a lootbox was opened (has rewards)
			if payload.rewards and self.isWaitingForSlot and self.pendingLootboxReward then
				-- A lootbox was opened successfully - show Claim button and update panel
				task.spawn(function()
					-- Show Claim button, hide Destroy button
					if self.BtnDestroy then
						self.BtnDestroy.Visible = false
						self.BtnDestroy.Active = false
					end
					if self.BtnClaim then
						self.BtnClaim.Visible = true
						self.BtnClaim.Active = true
					end
					
					-- Update PackSelectorFrame to reflect the opened slot
					if self.LootboxHandler and self.LootboxHandler.UpdateLootboxStates then
						self.LootboxHandler:UpdateLootboxStates(nil, "PackSelector")
					end
					
					-- Update text visibility after slot was freed
					self:UpdatePackSelectorTextVisibility()
					
					-- Set currentReward so it can be claimed when user clicks Claim
					-- Don't automatically grant the reward - wait for user to click Claim
					self.currentReward = self.pendingLootboxReward
					-- Keep isWaitingForSlot true until user clicks Claim
				end)
			elseif self.isWaitingForSlot and self.pendingLootboxReward then
				-- Check if slot was freed (lootbox count decreased)
				local currentCount = payload.lootboxes and #payload.lootboxes or 0
				local previousCount = 0
				if self.ClientState and self.ClientState.getProfile then
					local profile = self.ClientState:getProfile()
					if profile and profile.lootboxes then
						previousCount = #profile.lootboxes
					end
				end
				
				if currentCount < previousCount then
					-- Slot was freed - save reward to pending and show Claim button
					if self.pendingLootboxReward and self.NetworkClient and self.NetworkClient.requestSaveBattleRewardToPending then
						-- Save reward to pending on server
						local requestData = {
							rewardType = "lootbox",
							rarity = self.pendingLootboxReward.rarity
						}
						self.NetworkClient.requestSaveBattleRewardToPending(requestData)
					end
					
					-- Show Claim button, hide Destroy button
					if self.BtnDestroy then
						self.BtnDestroy.Visible = false
						self.BtnDestroy.Active = false
					end
					if self.BtnClaim then
						self.BtnClaim.Visible = true
						self.BtnClaim.Active = true
					end
					
					-- Update PackSelectorFrame
					if self.LootboxHandler and self.LootboxHandler.UpdateLootboxStates then
						self.LootboxHandler:UpdateLootboxStates(nil, "PackSelector")
					end
					
					-- Update text visibility after slot was freed
					self:UpdatePackSelectorTextVisibility()
					
					-- Set currentReward so it can be claimed when user clicks Claim
					-- Don't automatically grant the reward - wait for user to click Claim
					self.currentReward = self.pendingLootboxReward
					-- Keep isWaitingForSlot true until user clicks Claim
				end
			end
		end
	end)
	
	table.insert(self.Connections, connection)
end

-- Show rewards after battle
function RewardsHandler:ShowRewards(battleResult, isVictory, battleRewards)
	if not self._initialized then
		warn("RewardsHandler: Not initialized")
		return
	end
	
	-- CRITICAL: Reset isRewardClaimed flag when opening rewards window
	-- This ensures buttons are visible on subsequent opens
	if self.LootboxHandler then
		self.LootboxHandler.isRewardClaimed = false
	end
	
	-- Store rewards from server (generated server-side)
	if battleRewards then
		self.currentReward = battleRewards
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
		self:ShowVictoryRewards(battleResult)
	else
		self:ShowLossRewards(battleResult)
	end
end

function RewardsHandler:ShowLossRewards(battleResult)
	-- Use reward from server
	local softAmount = self.currentReward.amount or 50
	
	-- Show Loss frame, hide others
	if self.LossFrame then 
		self.LossFrame.Visible = true 
	end
	if self.VictoryFrame then self.VictoryFrame.Visible = false end
	if self.PackSelectorFrame then self.PackSelectorFrame.Visible = false end
	
	-- Enable BtnClaim, disable BtnDestroy
	if self.BtnClaim then
		self.BtnClaim.Visible = true
		self.BtnClaim.Active = true
	end
	if self.BtnDestroy then
		self.BtnDestroy.Visible = false
		self.BtnDestroy.Active = false
	end
	
	-- Fill Loss frame with reward info
	if self.LossImgReward then
		self.LossImgReward.Image = self.Manifest.Currency.Soft.Big
	end
	if self.LossTxtValue then
		self.LossTxtValue.Text = tostring(softAmount)
	end
	
	-- Show Rewards frame
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
	
	-- Always show PackSelectorFrame, but configure buttons based on slot availability
	if hasFreeSlot then
		-- Player has free slot - show PackSelectorFrame with Claim button
		self:ShowVictoryRewardsFreeSlot()
	else
		-- Player has no free slots - show PackSelectorFrame with Destroy button
		self:ShowVictoryRewardsNoSlot()
	end
end

function RewardsHandler:ShowVictoryRewardsFreeSlot()
	-- Show PackSelectorFrame, enable BtnClaim, disable BtnDestroy
	if self.PackSelectorFrame then self.PackSelectorFrame.Visible = true end
	if self.BtnClaim then
		self.BtnClaim.Visible = true
		self.BtnClaim.Active = true
	end
	if self.BtnDestroy then
		self.BtnDestroy.Visible = false
		self.BtnDestroy.Active = false
	end
	
	-- Setup PackSelector if not already set up
	self:SetupPackSelector()

	if self.LootboxHandler and self.LootboxHandler.UpdateLootboxStates then
		self.LootboxHandler:UpdateLootboxStates(nil, "PackSelector")
	end
	
	-- Update text visibility (hide texts when there's a free slot)
	self:UpdatePackSelectorTextVisibility()
	
	-- Show Rewards frame
	self:ShowRewardsFrame()
end

function RewardsHandler:ShowVictoryRewardsNoSlot()
	if self.PackSelectorFrame then self.PackSelectorFrame.Visible = true end
	if self.BtnClaim then
		self.BtnClaim.Visible = false
		self.BtnClaim.Active = false
	end
	if self.BtnDestroy then
		self.BtnDestroy.Visible = true
		self.BtnDestroy.Active = true
	end
	
	self:SetupPackSelector()
	
	if self.LootboxHandler and self.LootboxHandler.UpdateLootboxStates then
		self.LootboxHandler:UpdateLootboxStates(nil, "PackSelector")
	end
	
	-- Update text visibility (show texts when there's no free slot)
	self:UpdatePackSelectorTextVisibility()
	
	self:ShowRewardsFrame()
	
	self.isWaitingForSlot = true
	self.pendingLootboxReward = self.currentReward
end

function RewardsHandler:SetupPackSelector()
	-- Get LootboxUIHandler to reuse its logic
	if not self.LootboxHandler then
		self.LootboxHandler = self.Controller:GetLootboxHandler()
	end
	
	if not self.LootboxHandler then
		warn("RewardsHandler: LootboxHandler not available")
		return
	end
	
	-- Prevent multiple setups - check if PackSelector handlers already exist
	local containerData = self.LootboxHandler.packContainers["PackSelector"]
	if containerData and containerData.packs then
		local hasHandlers = false
		for i = 1, 4 do
			local pack = containerData.packs[i]
			if pack and pack._buttonConnections then
				if pack._buttonConnections.btnSpeedUp or pack._buttonConnections.btnOpen or pack._buttonConnections.btnUnlock then
					hasHandlers = true
					break
				end
			end
		end
		if hasHandlers then
			return
		end
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
		return
	end
	
	-- Use LootboxUIHandler's reusable setup method
	if self.LootboxHandler.SetupPacksForContainer then
		local success = self.LootboxHandler:SetupPacksForContainer("PackSelector", packsContainer)
		if success then
			-- Setup button handlers for PackSelector (since SetupPacksForContainer only sets up BottomPanel buttons)
			-- CRITICAL: Check if handlers already exist to prevent duplicates
			local containerData = self.LootboxHandler.packContainers["PackSelector"]
			if containerData then
				for i = 1, 4 do
					local pack = containerData.packs[i]
					if pack then
						-- Initialize button connections storage if not exists
						if not pack._buttonConnections then
							pack._buttonConnections = {}
						end
						
						-- Disconnect old handlers if they exist
						if pack._buttonConnections.btnUnlock then
							pack._buttonConnections.btnUnlock:Disconnect()
							pack._buttonConnections.btnUnlock = nil
						end
						if pack._buttonConnections.btnOpen then
							pack._buttonConnections.btnOpen:Disconnect()
							pack._buttonConnections.btnOpen = nil
						end
						if pack._buttonConnections.btnSpeedUp then
							pack._buttonConnections.btnSpeedUp:Disconnect()
							pack._buttonConnections.btnSpeedUp = nil
						end
						
						-- CRITICAL: Check if this button is also used by BottomPanel before creating handler
						-- If so, we should not create a duplicate handler
						local bottomPanelPack = self.LootboxHandler and self.LootboxHandler.lootboxPacks and self.LootboxHandler.lootboxPacks[pack.slotIndex]
						local isSameButton = bottomPanelPack and bottomPanelPack.btnSpeedUp == pack.btnSpeedUp
						
						-- Setup button handlers only if buttons exist and handlers don't and button is not shared with BottomPanel
						if pack.btnUnlock and pack.btnUnlock:IsA("TextButton") and not pack._buttonConnections.btnUnlock and not (bottomPanelPack and bottomPanelPack.btnUnlock == pack.btnUnlock) then
							local connection = pack.btnUnlock.MouseButton1Click:Connect(function()
								if self.NetworkClient then
									self.NetworkClient.requestStartUnlock(pack.slotIndex)
								end
							end)
							pack._buttonConnections.btnUnlock = connection
							table.insert(self.Connections, connection)
						end
						
						if pack.btnOpen and pack.btnOpen:IsA("TextButton") and not pack._buttonConnections.btnOpen and not (bottomPanelPack and bottomPanelPack.btnOpen == pack.btnOpen) then
							local connection = pack.btnOpen.MouseButton1Click:Connect(function()
								if self.NetworkClient then
									self.NetworkClient.requestOpenNow(pack.slotIndex)
								end
							end)
							pack._buttonConnections.btnOpen = connection
							table.insert(self.Connections, connection)
						end
						
						if pack.btnSpeedUp and pack.btnSpeedUp:IsA("TextButton") and not pack._buttonConnections.btnSpeedUp and not isSameButton then
							local connection = pack.btnSpeedUp.MouseButton1Click:Connect(function()
								if self.NetworkClient then
									self.NetworkClient.requestSpeedUp(pack.slotIndex)
								end
							end)
							pack._buttonConnections.btnSpeedUp = connection
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
end

function RewardsHandler:OnClaimButtonClicked()
	if not self.currentReward then
		return
	end
	
	-- Prevent multiple clicks
	if self.pendingClaimUpdate then
		return
	end
	
	-- Hide Claim button immediately to prevent repeated clicks
	if self.BtnClaim then
		self.BtnClaim.Visible = false
	end
	
	-- Set flag in LootboxUIHandler that reward has been claimed
	if self.LootboxHandler then
		self.LootboxHandler.isRewardClaimed = true
	end
	
	-- Request server to grant reward
	if not self.NetworkClient then
		warn("RewardsHandler: NetworkClient not available")
		-- Reset flag on error
		if self.LootboxHandler then
			self.LootboxHandler.isRewardClaimed = false
		end
		-- Show button again on error
		if self.BtnClaim then
			self.BtnClaim.Visible = true
		end
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
		-- Reset flag on error
		if self.LootboxHandler then
			self.LootboxHandler.isRewardClaimed = false
		end
		-- Show button again on error
		if self.BtnClaim then
			self.BtnClaim.Visible = true
		end
		return
	end
	
	-- Call server to grant reward
	if self.NetworkClient.requestClaimBattleReward then
		local success = self.NetworkClient.requestClaimBattleReward(requestData)
		if not success then
			-- Reset flag on error
			if self.LootboxHandler then
				self.LootboxHandler.isRewardClaimed = false
			end
			-- Show button again on error
			if self.BtnClaim then
				self.BtnClaim.Visible = true
			end
			return
		end
		
		-- Reset waiting state when claiming
		if self.isWaitingForSlot then
			self.isWaitingForSlot = false
			self.pendingLootboxReward = nil
		end
		
		-- Set flag to wait for ProfileUpdated event
		-- The ProfileUpdated handler will update the panel and close the window
		self.pendingClaimUpdate = true
	else
		warn("RewardsHandler: NetworkClient.requestClaimBattleReward not available")
		-- Reset flag on error
		if self.LootboxHandler then
			self.LootboxHandler.isRewardClaimed = false
		end
		-- Show button again on error
		if self.BtnClaim then
			self.BtnClaim.Visible = true
		end
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
	
	-- Reset waiting state
	self.pendingLootboxReward = nil
	self.isWaitingForSlot = false
	
	-- Note: UI update (hiding Destroy/PacksSelector, showing Claim) happens in SetupProfileUpdatedHandler
	-- CloseRewards will be called only when user clicks BtnClaim
end

function RewardsHandler:ShowRewardsFrame()
	if not self.RewardsFrame then
		warn("RewardsHandler: RewardsFrame not found!")
		return
	end
	
	self.RewardsFrame.Visible = true
	
	-- Use TweenUI if available
	if self.Utilities and self.Utilities.TweenUI and self.Utilities.TweenUI.FadeIn then
		self.Utilities.TweenUI.FadeIn(self.RewardsFrame, 0.3, function()
			-- Emit window opened event after animation completes
			EventBus:Emit("WindowOpened", "Reward")
		end)
	else
		-- Emit window opened event immediately if no animation
		EventBus:Emit("WindowOpened", "Reward")
	end
	
	if self.Utilities and self.Utilities.Blur then
		self.Utilities.Blur.Show()
	end
end

function RewardsHandler:CloseRewards()
	if not self.RewardsFrame then
		return
	end
	
	local function finalize()
		if self.UI then
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

		self.currentReward = nil
		self.isWaitingForSlot = false
		self.pendingLootboxReward = nil
		self.pendingClaimUpdate = false
		self.claimedReward = false
		-- Clear flag in LootboxUIHandler that reward has been claimed
		if self.LootboxHandler then
			self.LootboxHandler.isRewardClaimed = false
		end

		-- Clear battle active flag and current battle now that battle is fully complete
		local battleHandler = self.Controller and self.Controller:GetBattleHandler()
		if battleHandler then
			battleHandler.isBattleActive = false
			battleHandler.currentBattle = nil -- Clear battle data since battle is fully complete
		end
	end
	
	-- Use TweenUI if available
	if self.Utilities and self.Utilities.TweenUI and self.Utilities.TweenUI.FadeOut then
		self.Utilities.TweenUI.FadeOut(self.RewardsFrame, 0.3, function()
			self.RewardsFrame.Visible = false
			-- Emit window closed event after animation completes
			EventBus:Emit("WindowClosed", "Reward")
			-- Reset state
			finalize()
		end)
		if self.Utilities and self.Utilities.Blur then
			self.Utilities.Blur.Hide()
		end
	else
		self.RewardsFrame.Visible = false
		-- Emit window closed event immediately if no animation
		EventBus:Emit("WindowClosed", "Reward")
		-- Reset state
		finalize()
	end
end

function RewardsHandler:UpdatePackSelectorTextVisibility()
	if not self.PackSelectorFrame or not self.PackSelectorFrame.Visible then
		return
	end
	
	-- Check if there's a free slot and count free slots
	local hasFreeSlot = false
	local freeSlotCount = 0
	local profile = self.ClientState:getProfile()
	if profile and profile.lootboxes then
		local lootboxCount = #profile.lootboxes
		hasFreeSlot = lootboxCount < 4
		freeSlotCount = 4 - lootboxCount
	end
	
	-- Check if reward has been claimed
	local isRewardClaimed = false
	if self.LootboxHandler then
		isRewardClaimed = self.LootboxHandler.isRewardClaimed or false
	end
	
	-- Hide texts if there's a free slot OR if reward has been claimed
	-- Show texts only if no free slots AND reward hasn't been claimed
	local shouldHideTexts = hasFreeSlot or isRewardClaimed
	
	-- Update TxtDescription text instead of hiding it
	if self.TxtDescription then
		if shouldHideTexts then
			-- Show free slots count when there are free slots or reward is claimed
			self.TxtDescription.Text = "Free slots available: " .. tostring(freeSlotCount)
		else
			-- Show instruction text when no free slots and reward not claimed
			self.TxtDescription.Text = "Speed up or open any pack to claim a reward:"
		end
		self.TxtDescription.Visible = true -- Always visible, just text changes
	end
	
	-- Hide TxtOr if there's a free slot OR if reward has been claimed
	if self.TxtOr then
		self.TxtOr.Visible = not shouldHideTexts
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

