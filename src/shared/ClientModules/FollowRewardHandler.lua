local FollowRewardHandler = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

local TWEEN_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MESSAGE_DURATION = 5

local function waitForChildRecursive(parent, childName, timeout)
	local child = parent:FindFirstChild(childName)
	local waited = 0
	while not child and (not timeout or waited < timeout) do
		child = parent:WaitForChild(childName, timeout and math.max(timeout - waited, 0) or nil)
		if child then
			break
		end
		waited = waited + (timeout or 0)
	end
	return child
end

function FollowRewardHandler:Init()
	local rootContainer = Workspace:FindFirstChild("Folder")
	if not rootContainer then
		warn("[FollowRewardHandler] Workspace/Folder container not found")
		return
	end

	local rootFolder = rootContainer:FindFirstChild("FollowPresent")
	if not rootFolder then
		rootFolder = rootContainer:FindFirstChild("FollowPresent", true)
	end
	if not rootFolder then
		warn("[FollowRewardHandler] FollowPresent folder not found in Workspace")
		return
	end

	local triggerPart = rootFolder:FindFirstChild("FollowTriggerPart") or rootFolder:FindFirstChild("FollowTriggerPart", true)
	if not triggerPart or not triggerPart:IsA("BasePart") then
		warn("[FollowRewardHandler] FollowTriggerPart missing or not a BasePart")
		return
	end

	local playerGui = localPlayer:WaitForChild("PlayerGui", 10)
	if not playerGui then
		warn("[FollowRewardHandler] PlayerGui not available")
		return
	end

	local gameUI = waitForChildRecursive(playerGui, "GameUI", 10)
	if not gameUI then
		warn("[FollowRewardHandler] GameUI not found in PlayerGui")
		return
	end

	local followFrame = waitForChildRecursive(gameUI, "FollowText", 10)
	if not followFrame or not followFrame:IsA("Frame") then
		warn("[FollowRewardHandler] FollowText Frame not found in GameUI")
		return
	end

	local followLabel = followFrame:FindFirstChildOfClass("TextLabel")
	if not followLabel then
		warn("[FollowRewardHandler] FollowText Label not found inside FollowText Frame")
		return
	end

	followFrame.Visible = false
	followFrame.BackgroundTransparency = 1
	followLabel.TextTransparency = 1

	local followRewardRemote = ReplicatedStorage:WaitForChild("Network"):WaitForChild("RequestClaimFollowReward")
	local profileUpdatedRemote = ReplicatedStorage:WaitForChild("Network"):WaitForChild("ProfileUpdated")

	local currentMessageToken = 0

	local function fadeIn()
		followFrame.Visible = true
		followFrame.BackgroundTransparency = 1
		followLabel.TextTransparency = 1

		local frameTween = TweenService:Create(followFrame, TWEEN_INFO, { BackgroundTransparency = 0.2 })
		local labelTween = TweenService:Create(followLabel, TWEEN_INFO, { TextTransparency = 0 })
		frameTween:Play()
		labelTween:Play()
	end

	local function fadeOut(token)
		local frameTween = TweenService:Create(followFrame, TWEEN_INFO, { BackgroundTransparency = 1 })
		local labelTween = TweenService:Create(followLabel, TWEEN_INFO, { TextTransparency = 1 })

		frameTween:Play()
		labelTween:Play()

		labelTween.Completed:Connect(function()
			if currentMessageToken == token then
				followFrame.Visible = false
			end
		end)
	end

	local function showStatus(message)
		currentMessageToken += 1
		local token = currentMessageToken

		followLabel.Text = message
		fadeIn()

		return token
	end

	local function showTimed(message, duration)
		duration = duration or MESSAGE_DURATION
		local token = showStatus(message)

		task.delay(duration, function()
			if currentMessageToken == token then
				fadeOut(token)
			end
		end)
	end

	local prompt = triggerPart:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "FollowRewardPrompt"
		prompt.ActionText = "Claim Follow Reward"
		prompt.ObjectText = "Follow Gift"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.Parent = triggerPart
	end

	prompt.Triggered:Connect(function(player)
		if player ~= localPlayer then
			return
		end

		showStatus("Checking follow status...")
		followRewardRemote:FireServer()
	end)

	profileUpdatedRemote.OnClientEvent:Connect(function(payload)
		if not payload or not payload.followReward then
			return
		end

		local status = payload.followReward.status or "UNKNOWN"
		status = string.upper(status)

		if status == "GRANTED" then
			showTimed("Thank you for following! Reward delivered.", 5)
		elseif status == "ALREADY_CLAIMED" then
			showTimed("You already got the reward.", 5)
		elseif status == "NOT_FOLLOWING" then
			showTimed("You should like and follow the game to get the reward.", 5)
		elseif status == "HTTP_DISABLED" then
			showTimed("Follow check unavailable. Please try again later.", 5)
		elseif status == "HTTP_ERROR" or status == "JSON_ERROR" or status == "INVALID_RESPONSE" then
			showTimed("Unable to verify follow. Please try again later.", 5)
		else
			showTimed("Unable to grant follow reward. Please try again later.", 5)
		end
	end)
end

return FollowRewardHandler

