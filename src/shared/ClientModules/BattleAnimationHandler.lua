--[[
	BattleAnimationHandler - Battle card animation system
	
	Handles card attack animations with damage effects.
]]

--// Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

--// Module
local BattleAnimationHandler = {}

--// Constants
local CONSTANTS = {
	HIGH_Z_INDEX = 1000,
	EFFECT_START_SIZE = UDim2.new(0, 0, 0, 0),
	EFFECT_DEFAULT_SIZE = UDim2.new(1, 0, 1, 0),
	TRANSPARENCY_VISIBLE = 0,
	TRANSPARENCY_HIDDEN = 1,
	UISTROKE_VISIBLE_TRANSPARENCY = 0.5,
}

local EFFECT_ELEMENTS = {
	DAMAGE = "Damage",
	BLOCK = "Block",
	REDUCE = "Reduce",
	DEATH = "Death",
	TEXT_VALUE = "TxtValue",
}

--// State
BattleAnimationHandler._initialized = false
BattleAnimationHandler.GameUI = nil

--// Configuration
BattleAnimationHandler.Config = {
	-- Animation timers (in seconds)
	ATTACK_MOVE_DURATION = 0.3,
	IMPACT_DURATION = 0.3,
	RETURN_DURATION = 0.3,
	EFFECT_FADE_DURATION = 0.3,
	DELAY_BEFORE_IMPACT = 0.1,
	
	-- Offsets (in pixels)
	ATTACKER_OFFSET = 50,
	TARGET_OFFSET = 20,
	CONTACT_DISTANCE = 10,
	
	-- Easing styles
	MOVE_EASING = Enum.EasingStyle.Quad,
	MOVE_DIRECTION = Enum.EasingDirection.Out,
	RETURN_EASING = Enum.EasingStyle.Quad,
	RETURN_DIRECTION = Enum.EasingDirection.In,
}

--// Initialization
function BattleAnimationHandler:Init()
	if self._initialized then
		return true
	end
	
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui", 10)
	if not playerGui then
		warn("BattleAnimationHandler: PlayerGui not found")
		return false
	end
	
	local gameUI = playerGui:WaitForChild("GameUI", 10)
	if not gameUI then
		warn("BattleAnimationHandler: GameUI not found")
		return false
	end
	
	self.GameUI = gameUI
	self._initialized = true
	
	print("✅ BattleAnimationHandler initialized")
	return true
end

--// Helper Functions

-- Set TxtValue transparency and its UIStroke transparency
-- When text is visible: UIStroke.Transparency = UISTROKE_VISIBLE_TRANSPARENCY
-- When text is hidden: UIStroke.Transparency = 1
local function setTxtValueTransparency(txtValue, transparency)
	if not txtValue then return end
	
	txtValue.TextTransparency = transparency
	
	local uiStroke = txtValue:FindFirstChild("UIStroke")
	if uiStroke then
		if transparency == CONSTANTS.TRANSPARENCY_HIDDEN then
			uiStroke.Transparency = CONSTANTS.TRANSPARENCY_HIDDEN
		else
			uiStroke.Transparency = CONSTANTS.UISTROKE_VISIBLE_TRANSPARENCY
		end
	end
end

-- Get opposite role
local function getOppositeRole(role)
	return (role == "player") and "rival" or "player"
end

-- Create UDim2 position with offset
local function offsetPosition(basePosition, offsetX, offsetY)
	offsetY = offsetY or 0
	return UDim2.new(
		basePosition.X.Scale,
		basePosition.X.Offset + offsetX,
		basePosition.Y.Scale,
		basePosition.Y.Offset + offsetY
	)
end

-- Helper to safely find child with warning
local function findChildWithWarning(parent, childName, context)
	local child = parent and parent:FindFirstChild(childName)
	if not child then
		warn("BattleAnimationHandler: " .. childName .. " not found" .. (context and (" in " .. context) or ""))
	end
	return child
end

-- Get card frame by role and ID
function BattleAnimationHandler:GetCardFrame(role, cardId)
	if not self.GameUI then
		warn("BattleAnimationHandler: GameUI not initialized")
		return nil
	end
	
	local roleName = (role == "player") and "Player" or "Rival"
	local battleFrame = findChildWithWarning(self.GameUI, "Battle")
	if not battleFrame then return nil end
	
	local roleFrame = findChildWithWarning(battleFrame, roleName)
	if not roleFrame then return nil end
	
	local contentFrame = findChildWithWarning(roleFrame, "Content", roleName)
	if not contentFrame then return nil end
	
	local innerContent = findChildWithWarning(contentFrame, "Content", roleName)
	if not innerContent then return nil end
	
	local placeholderName = "Placeholder" .. cardId
	local placeholder = findChildWithWarning(innerContent, placeholderName)
	if not placeholder then return nil end

	local card = findChildWithWarning(placeholder, "Card", placeholderName)
	return card
end

-- Reset effect to initial state
function BattleAnimationHandler:ResetEffect(effectFrame)
	if not effectFrame then return end
	
	effectFrame.Visible = false
	effectFrame.Size = CONSTANTS.EFFECT_START_SIZE
	
	local txtValue = effectFrame:FindFirstChild(EFFECT_ELEMENTS.TEXT_VALUE)
	
	for _, child in ipairs(effectFrame:GetDescendants()) do
		if child:IsA("ImageLabel") or child:IsA("ImageButton") then
			child.ImageTransparency = CONSTANTS.TRANSPARENCY_VISIBLE
		elseif child:IsA("TextLabel") or child:IsA("TextButton") then
			child.TextTransparency = CONSTANTS.TRANSPARENCY_VISIBLE
			child.TextStrokeTransparency = CONSTANTS.TRANSPARENCY_VISIBLE
			-- Handle TxtValue UIStroke separately
			if child == txtValue then
				local uiStroke = child:FindFirstChild("UIStroke")
				if uiStroke then
					uiStroke.Transparency = CONSTANTS.UISTROKE_VISIBLE_TRANSPARENCY
				end
			end
		elseif child:IsA("Frame") then
			child.Visible = false
		end
	end
end

-- Reset all effects for all cards (player and rival)
function BattleAnimationHandler:ResetAllEffects()
	if not self._initialized then
		warn("BattleAnimationHandler: Not initialized. Call Init() first.")
		return
	end
	
	-- Reset effects for all player cards (1-6)
	for cardId = 1, 6 do
		local cardFrame = self:GetCardFrame("player", cardId)
		if cardFrame then
			local effectFrame = cardFrame:FindFirstChild("Effect")
			if effectFrame then
				self:ResetEffect(effectFrame)
			end
		end
	end
	
	-- Reset effects for all rival cards (1-6)
	for cardId = 1, 6 do
		local cardFrame = self:GetCardFrame("rival", cardId)
		if cardFrame then
			local effectFrame = cardFrame:FindFirstChild("Effect")
			if effectFrame then
				self:ResetEffect(effectFrame)
			end
		end
	end
end

-- Show effect based on damage type
function BattleAnimationHandler:ShowEffect(effectFrame, damageType, damageValue, isDeath)
	if not effectFrame then return end
	
	local damageImage = effectFrame:FindFirstChild(EFFECT_ELEMENTS.DAMAGE)
	local blockImage = effectFrame:FindFirstChild(EFFECT_ELEMENTS.BLOCK)
	local reduceImage = effectFrame:FindFirstChild(EFFECT_ELEMENTS.REDUCE)
	local deathImage = effectFrame:FindFirstChild(EFFECT_ELEMENTS.DEATH)
	local txtValue = effectFrame:FindFirstChild(EFFECT_ELEMENTS.TEXT_VALUE)
	
	-- Mapping damage type to image
	local damageTypeMap = {
		damage = damageImage,
		block = blockImage,
		reduce = reduceImage,
	}
	
	-- Hide all elements by default
	for _, image in pairs({damageImage, blockImage, reduceImage, deathImage}) do
		if image then
			image.ImageTransparency = CONSTANTS.TRANSPARENCY_HIDDEN
		end
	end
	setTxtValueTransparency(txtValue, CONSTANTS.TRANSPARENCY_HIDDEN)
	
	if isDeath then
		if deathImage then
			deathImage.ImageTransparency = CONSTANTS.TRANSPARENCY_VISIBLE
		end
		return
	end
	
	-- Show appropriate effect based on damage type
	local effectImage = damageTypeMap[damageType]
	if effectImage then
		effectImage.ImageTransparency = CONSTANTS.TRANSPARENCY_VISIBLE
	end
	
	-- Show damage value in format "-N" if > 0 and not Block
	if damageValue > 0 and txtValue and damageType ~= "block" then
		txtValue.Text = "-" .. tostring(damageValue)
		setTxtValueTransparency(txtValue, CONSTANTS.TRANSPARENCY_VISIBLE)
	end
end

-- Hide effect via alpha fade
-- skipFrameHide: if true, doesn't hide effectFrame.Visible (used for Death)
function BattleAnimationHandler:HideEffect(effectFrame, duration, callback, skipFrameHide)
	if not effectFrame then 
		if callback then callback() end
		return 
	end
	
	local objectsToFade = {}
	
	for _, child in ipairs(effectFrame:GetDescendants()) do
		if child:IsA("ImageLabel") or child:IsA("ImageButton") then
			table.insert(objectsToFade, {obj = child, props = {"ImageTransparency"}})
		elseif child:IsA("TextLabel") or child:IsA("TextButton") then
			table.insert(objectsToFade, {obj = child, props = {"TextTransparency", "TextStrokeTransparency"}})
			
			-- Also fade UIStroke if it exists
			local uiStroke = child:FindFirstChild("UIStroke")
			if uiStroke then
				table.insert(objectsToFade, {obj = uiStroke, props = {"Transparency"}})
			end
		end
	end
	
	if #objectsToFade == 0 then
		if not skipFrameHide then
			effectFrame.Visible = false
		end
		if callback then callback() end
		return
	end
	
	local tweens = {}
	for _, entry in ipairs(objectsToFade) do
		local goal = {}
		for _, prop in ipairs(entry.props) do
			goal[prop] = CONSTANTS.TRANSPARENCY_HIDDEN
		end
		local tween = TweenService:Create(entry.obj, TweenInfo.new(duration), goal)
		tween:Play()
		table.insert(tweens, tween)
	end
	
	local finishedCount = 0
	local totalTweens = #tweens
	
	for _, tween in ipairs(tweens) do
		tween.Completed:Connect(function()
			finishedCount = finishedCount + 1
			if finishedCount == totalTweens then
				if not skipFrameHide then
					effectFrame.Visible = false
				end
				if callback then callback() end
			end
		end)
	end
end

--// Animation Phase Functions

-- Calculate contact position for attacker card
-- task.wait() ensures UI updates before reading AbsolutePosition (needed after ZIndex changes)
local function calculateContactPosition(attackerFrame, targetFrame, attackerStartPosition, directionMultiplier, config)
	task.wait()
	
	local attackerAbsolutePos = attackerFrame.AbsolutePosition
	local attackerAbsoluteSize = attackerFrame.AbsoluteSize
	local targetAbsolutePos = targetFrame.AbsolutePosition
	local targetAbsoluteSize = targetFrame.AbsoluteSize
	
	local attackerCenter = Vector2.new(
		attackerAbsolutePos.X + attackerAbsoluteSize.X / 2,
		attackerAbsolutePos.Y + attackerAbsoluteSize.Y / 2
	)
	local targetCenter = Vector2.new(
		targetAbsolutePos.X + targetAbsoluteSize.X / 2,
		targetAbsolutePos.Y + targetAbsoluteSize.Y / 2
	)
	
	local requiredDistance = attackerAbsoluteSize.X + config.CONTACT_DISTANCE
	local attackerCenterXTarget = targetCenter.X - (requiredDistance * directionMultiplier)
	
	local contactOffsetXPixels = attackerCenterXTarget - attackerCenter.X
	local contactOffsetYPixels = targetCenter.Y - attackerCenter.Y
	
	return offsetPosition(attackerStartPosition, contactOffsetXPixels, contactOffsetYPixels)
end

-- Play move animation phase
local function playMoveAnimation(attackerFrame, contactPosition, config, onComplete)
	local moveTween = TweenService:Create(
		attackerFrame,
		TweenInfo.new(
			config.ATTACK_MOVE_DURATION,
			config.MOVE_EASING,
			config.MOVE_DIRECTION
		),
		{Position = contactPosition}
	)
	
	moveTween:Play()
	moveTween.Completed:Connect(onComplete)
end

-- Play impact animation phase
local function playImpactAnimation(attackerFrame, targetFrame, contactPosition, targetStartPosition, directionMultiplier, effectFrame, damageType, damageValue, config, onComplete)
	local attackerOffsetPosition = offsetPosition(contactPosition, config.ATTACKER_OFFSET * directionMultiplier)
	local targetOffsetPosition = offsetPosition(targetStartPosition, config.TARGET_OFFSET * directionMultiplier)
	
	local attackerImpactTween = TweenService:Create(
		attackerFrame,
		TweenInfo.new(config.IMPACT_DURATION, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
		{Position = attackerOffsetPosition}
	)
	
	local targetImpactTween = TweenService:Create(
		targetFrame,
		TweenInfo.new(config.IMPACT_DURATION, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
		{Position = targetOffsetPosition}
	)
	
	effectFrame.Visible = true
	BattleAnimationHandler:ShowEffect(effectFrame, damageType, damageValue, false)
	
	local effectOriginalSize = effectFrame.Size
	if effectOriginalSize.X.Scale == 0 and effectOriginalSize.X.Offset == 0 then
		effectOriginalSize = CONSTANTS.EFFECT_DEFAULT_SIZE
	end
	effectFrame.Size = CONSTANTS.EFFECT_START_SIZE
	
	local effectScaleTween = TweenService:Create(
		effectFrame,
		TweenInfo.new(config.IMPACT_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = effectOriginalSize}
	)
	
	attackerImpactTween:Play()
	targetImpactTween:Play()
	effectScaleTween:Play()
	
	attackerImpactTween.Completed:Connect(onComplete)
end

-- Play return animation phase
local function playReturnAnimation(attackerFrame, targetFrame, attackerStartPosition, targetStartPosition, config, onComplete)
	local attackerReturnTween = TweenService:Create(
		attackerFrame,
		TweenInfo.new(config.RETURN_DURATION, config.RETURN_EASING, config.RETURN_DIRECTION),
		{Position = attackerStartPosition}
	)
	
	local targetReturnTween = TweenService:Create(
		targetFrame,
		TweenInfo.new(config.RETURN_DURATION, config.RETURN_EASING, config.RETURN_DIRECTION),
		{Position = targetStartPosition}
	)
	
	local finishedCount = 0
	local function onTweenComplete()
		finishedCount = finishedCount + 1
		if finishedCount == 2 then
			onComplete()
		end
	end
	
	attackerReturnTween.Completed:Connect(onTweenComplete)
	targetReturnTween.Completed:Connect(onTweenComplete)
	
	attackerReturnTween:Play()
	targetReturnTween:Play()
end

-- Handle death effect
local function handleDeathEffect(effectFrame, config)
	BattleAnimationHandler:HideEffect(effectFrame, config.EFFECT_FADE_DURATION, function()
		local deathImage = effectFrame:FindFirstChild(EFFECT_ELEMENTS.DEATH)
		if deathImage then
			deathImage.ImageTransparency = CONSTANTS.TRANSPARENCY_VISIBLE
		end
	end, true)
end

--// Main Animation Method

-- Attack animation
-- Parameters:
--   attackerRole: "player" or "rival"
--   attackerId: card ID (1-6)
--   targetId: card ID (1-6)
--   damageType: "damage", "block", or "reduce"
--   damageValue: number (can be 0)
--   isDeath: boolean
--   onComplete: optional callback function called when animation completes
function BattleAnimationHandler:Attack(attackerRole, attackerId, targetId, damageType, damageValue, isDeath, onComplete)
	if not self._initialized then
		warn("BattleAnimationHandler: Not initialized. Call Init() first.")
		return
	end
	
	local targetRole = getOppositeRole(attackerRole)
	local attackerFrame = self:GetCardFrame(attackerRole, attackerId)
	local targetFrame = self:GetCardFrame(targetRole, targetId)
	
	if not attackerFrame or not targetFrame then
		warn("BattleAnimationHandler: Could not find card frames")
		return
	end
	
	local effectFrame = targetFrame:FindFirstChild("Effect")
	if not effectFrame then
		warn("BattleAnimationHandler: Effect frame not found in target card")
		return
	end
	
	-- Hide attacker's Effect frame before animation starts
	local attackerEffectFrame = attackerFrame:FindFirstChild("Effect")
	if attackerEffectFrame then
		attackerEffectFrame.Visible = false
	end
	
	-- Get parent container (Player or Rival frame) for ZIndex management
	local battleFrame = self.GameUI:FindFirstChild("Battle")
	local roleName = (attackerRole == "player") and "Player" or "Rival"
	local targetRoleName = (targetRole == "player") and "Player" or "Rival"
	local roleFrame = battleFrame and battleFrame:FindFirstChild(roleName)
	local targetRoleFrame = battleFrame and battleFrame:FindFirstChild(targetRoleName)
	
	self:ResetEffect(effectFrame)
	
	local attackerStartPosition = attackerFrame.Position
	local targetStartPosition = targetFrame.Position
	local attackerOriginalZIndex = attackerFrame.ZIndex
	local roleOriginalZIndex = roleFrame and roleFrame.ZIndex or 1
	local targetRoleOriginalZIndex = targetRoleFrame and targetRoleFrame.ZIndex or 1
	
	-- Set high ZIndex for attacker's card and its parent container BEFORE any calculations
	attackerFrame.ZIndex = CONSTANTS.HIGH_Z_INDEX
	if roleFrame then
		roleFrame.ZIndex = CONSTANTS.HIGH_Z_INDEX
	end
	
	-- Ensure target's container has lower ZIndex
	if targetRoleFrame and targetRoleFrame.ZIndex >= CONSTANTS.HIGH_Z_INDEX then
		targetRoleFrame.ZIndex = CONSTANTS.HIGH_Z_INDEX - 1
	end
	
	local directionMultiplier = (attackerRole == "player") and 1 or -1
	local contactPosition = calculateContactPosition(attackerFrame, targetFrame, attackerStartPosition, directionMultiplier, self.Config)
	
	playMoveAnimation(attackerFrame, contactPosition, self.Config, function()
		task.wait(self.Config.DELAY_BEFORE_IMPACT)
		playImpactAnimation(attackerFrame, targetFrame, contactPosition, targetStartPosition, directionMultiplier, effectFrame, damageType, damageValue, self.Config, function()
			-- Start return animation and effect handling simultaneously
			playReturnAnimation(attackerFrame, targetFrame, attackerStartPosition, targetStartPosition, self.Config, function()
				-- Restore original ZIndex values
				attackerFrame.ZIndex = attackerOriginalZIndex
				if roleFrame then
					roleFrame.ZIndex = roleOriginalZIndex
				end
				if targetRoleFrame then
					targetRoleFrame.ZIndex = targetRoleOriginalZIndex
				end
				
				-- Call completion callback if provided
				if onComplete then
					onComplete()
				end
			end)
			
			-- Handle death effect or fade out effect simultaneously with return animation
			if isDeath then
				handleDeathEffect(effectFrame, self.Config)
			else
				BattleAnimationHandler:HideEffect(effectFrame, self.Config.EFFECT_FADE_DURATION, function() end)
			end
		end)
	end)
end

--// Test Function

BattleAnimationHandler._testAttackerRole = "player"

function BattleAnimationHandler:TestAttack()
	if not self._initialized then
		self:Init()
	end
	
	local attackerRole = self._testAttackerRole
	self._testAttackerRole = (attackerRole == "player") and "rival" or "player"
	
	local attackerId = math.random(1, 6)
	local targetId
	repeat
		targetId = math.random(1, 6)
	until targetId ~= attackerId
	
	local damageTypes = {"damage", "block", "reduce"}
	local damageType = damageTypes[math.random(1, #damageTypes)]
	local damageValue = math.random(0, 99)
	local isDeath = damageType ~= "block" and math.random() > 0.5
	
	local targetRole = getOppositeRole(attackerRole)
	print(string.format("Test Attack: %s(%d) -> %s(%d), type=%s, value=%d, death=%s",
		attackerRole, attackerId, targetRole, targetId,
		damageType, damageValue, tostring(isDeath)
	))
	
	self:Attack(attackerRole, attackerId, targetId, damageType, damageValue, isDeath)
end

return BattleAnimationHandler
