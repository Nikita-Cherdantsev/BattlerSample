--[[
	TutorialService
	
	Manages tutorial progress on the server side.
	Handles tutorial step completion and persistence.
]]

local TutorialService = {}

-- Services
local Players = game:GetService("Players")

-- Modules
local ProfileManager = require(script.Parent.Parent.Persistence.ProfileManager)
local TutorialConfig = require(game.ReplicatedStorage.Modules.Tutorial.TutorialConfig)
local Logger = require(game.ReplicatedStorage.Modules.Logger)

-- Error codes
TutorialService.ErrorCodes = {
	INVALID_REQUEST = "INVALID_REQUEST",
	STEP_NOT_FOUND = "STEP_NOT_FOUND",
	ALREADY_COMPLETE = "ALREADY_COMPLETE",
	INTERNAL = "INTERNAL"
}

-- Complete a tutorial step
function TutorialService.CompleteStep(playerId, stepIndex, useAltNextStep)
	if not playerId or type(playerId) ~= "number" then
		return { ok = false, error = TutorialService.ErrorCodes.INVALID_REQUEST }
	end
	
	if not stepIndex or type(stepIndex) ~= "number" or stepIndex < 1 then
		return { ok = false, error = TutorialService.ErrorCodes.INVALID_REQUEST }
	end
	
	useAltNextStep = useAltNextStep == true
	
	-- Validate step exists
	local step = TutorialConfig.GetStep(stepIndex)
	if not step then
		return { ok = false, error = TutorialService.ErrorCodes.STEP_NOT_FOUND }
	end
	
	-- Load profile
	local profile = ProfileManager.GetCachedProfile(playerId)
	if not profile then
		profile = ProfileManager.LoadProfile(playerId)
	end
	
	if not profile then
		Logger.error("TutorialService.CompleteStep: Failed to load profile for player %d", playerId)
		return { ok = false, error = TutorialService.ErrorCodes.INTERNAL }
	end
	
	local currentStep = profile.tutorialStep or 0
	Logger.debug("TutorialService.CompleteStep: playerId=%d, currentStep=%d, stepIndex=%d", playerId, currentStep, stepIndex)
	
	-- Check if tutorial is already complete
	if TutorialConfig.IsComplete(currentStep) then
		return { ok = false, error = TutorialService.ErrorCodes.ALREADY_COMPLETE }
	end
	
	-- Update tutorial step atomically
	local success, result = ProfileManager.UpdateProfile(playerId, function(profile)
		local currentStep = profile.tutorialStep or 0
		Logger.debug("TutorialService.CompleteStep (inside UpdateProfile): currentStep=%d, stepIndex=%d", currentStep, stepIndex)
		
		if stepIndex > currentStep then
			-- Forward progress (normal progression or optimistic update)
			-- Check if the completed step has altNextStep (e.g., step 13 with loss -> step 11)
			local completedStepConfig = TutorialConfig.GetStep(stepIndex)
			if completedStepConfig and completedStepConfig.altNextStep and completedStepConfig.altNextStep < stepIndex then
				-- Special case for step 13: use client-provided useAltNextStep flag to determine victory/loss
				-- Client knows victory/loss from HandleRewardWindowOpen (stepOverrides[13])
				if stepIndex == 13 then
					if useAltNextStep then
						-- Loss case: use altNextStep (11)
						local targetStep = completedStepConfig.altNextStep - 1
						profile.tutorialStep = targetStep
						Logger.debug("TutorialService.CompleteStep: Step 13 completed with loss (useAltNextStep=true), setting tutorialStep to %d (altNextStep rollback)", targetStep)
					else
						-- Victory case: use normal nextStep (14)
						profile.tutorialStep = stepIndex
						Logger.debug("TutorialService.CompleteStep: Step 13 completed with victory (useAltNextStep=false), setting tutorialStep to %d", stepIndex)
					end
				elseif stepIndex == 14 then
					-- Special case for step 14: use client-provided useAltNextStep flag
					-- If useAltNextStep=true, it means lootbox was not available (condition not met)
					-- If useAltNextStep=false, it means lootbox was available and step was completed normally
					if useAltNextStep then
						-- No lootbox case: use altNextStep (11)
						local targetStep = completedStepConfig.altNextStep - 1
						profile.tutorialStep = targetStep
						Logger.debug("TutorialService.CompleteStep: Step 14 completed with no lootbox (useAltNextStep=true), setting tutorialStep to %d (altNextStep rollback)", targetStep)
					else
						-- Normal case: use normal nextStep (15)
						profile.tutorialStep = stepIndex
						Logger.debug("TutorialService.CompleteStep: Step 14 completed normally (useAltNextStep=false), setting tutorialStep to %d", stepIndex)
					end
				else
					-- Other steps with altNextStep: use altNextStep
					local targetStep = completedStepConfig.altNextStep - 1
					profile.tutorialStep = targetStep
					Logger.debug("TutorialService.CompleteStep: Step %d has altNextStep = %d (show step %d), setting tutorialStep to %d (rollback)", 
						stepIndex, completedStepConfig.altNextStep, completedStepConfig.altNextStep, targetStep)
				end
			else
				-- Normal forward progress
				profile.tutorialStep = stepIndex
				Logger.debug("TutorialService.CompleteStep: Updated tutorialStep from %d to %d", currentStep, stepIndex)
			end
		elseif stepIndex == currentStep then
			-- Step already completed - no-op (idempotent)
			-- This can happen on duplicate requests or when server already updated the step
			Logger.debug("TutorialService.CompleteStep: Step %d already completed, no-op", stepIndex)
			return profile
		else
			-- stepIndex < currentStep - this should not happen in normal flow
			-- Client always sends request to complete current step, not to rollback
			-- If this happened, it's either a bug or an attempt to cheat
			-- Ignore request (protection against bugs/cheats)
			Logger.warn("TutorialService.CompleteStep: Attempt to rollback from step %d to %d, ignoring (client should complete current step, not request rollback)", currentStep, stepIndex)
			return profile
		end
		return profile
	end)
	
	if not success then
		Logger.error("TutorialService.CompleteStep: UpdateProfile failed for player %d, stepIndex %d: %s", playerId, stepIndex, tostring(result))
		return { ok = false, error = TutorialService.ErrorCodes.INTERNAL }
	end
	
	-- Get updated profile
	local finalProfile = ProfileManager.GetCachedProfile(playerId)
	local newStep = finalProfile and finalProfile.tutorialStep or 0
	
	Logger.debug("Tutorial step %d completed for player %d (newStep=%d)", stepIndex, playerId, newStep)
	
	return { 
		ok = true, 
		tutorialStep = newStep,
		isComplete = TutorialConfig.IsComplete(newStep)
	}
end

-- Get tutorial progress for a player
function TutorialService.GetProgress(playerId)
	if not playerId or type(playerId) ~= "number" then
		return { ok = false, error = TutorialService.ErrorCodes.INVALID_REQUEST }
	end
	
	-- Load profile
	local profile = ProfileManager.GetCachedProfile(playerId)
	if not profile then
		profile = ProfileManager.LoadProfile(playerId)
	end
	
	if not profile then
		return { ok = false, error = TutorialService.ErrorCodes.INTERNAL }
	end
	
	local currentStep = profile.tutorialStep or 0
	local nextStepIndex = TutorialConfig.GetNextStepIndex(currentStep)
	
	-- Check if next step has forceStepOnGameLoad and should override current step
	if nextStepIndex then
		local nextStepConfig = TutorialConfig.GetStep(nextStepIndex)
		if nextStepConfig and nextStepConfig.forceStepOnGameLoad then
			local forceStepIndex = nextStepConfig.forceStepOnGameLoad
			-- If current step is at or past the force step, reset to forceStepIndex - 1
			-- This allows the force step to be shown again as if the player hasn't seen it
			if currentStep >= forceStepIndex - 1 then
				local targetStep = forceStepIndex - 1
				Logger.debug("TutorialService.GetProgress: Next step %d has forceStepOnGameLoad = %d, resetting tutorialStep from %d to %d", 
					nextStepIndex, forceStepIndex, currentStep, targetStep)
				
				-- Update profile with new tutorial step
				local success, updatedProfile = ProfileManager.UpdateProfile(playerId, function(profile)
					profile.tutorialStep = targetStep
					return profile
				end)
				
				if success and updatedProfile then
					currentStep = targetStep
					nextStepIndex = TutorialConfig.GetNextStepIndex(currentStep)
					Logger.debug("TutorialService.GetProgress: Successfully reset tutorialStep to %d", currentStep)
				else
					Logger.debug("TutorialService.GetProgress: Failed to reset tutorialStep, using original value %d", currentStep)
				end
			end
		end
	end
	
	return {
		ok = true,
		currentStep = currentStep,
		nextStepIndex = nextStepIndex,
		isComplete = TutorialConfig.IsComplete(currentStep),
		nextStep = nextStepIndex and TutorialConfig.GetStep(nextStepIndex) or nil
	}
end

-- Reset tutorial progress (for testing/debugging)
function TutorialService.ResetProgress(playerId)
	if not playerId or type(playerId) ~= "number" then
		return { ok = false, error = TutorialService.ErrorCodes.INVALID_REQUEST }
	end
	
	local success, updatedProfile = ProfileManager.UpdateProfile(playerId, function(profile)
		profile.tutorialStep = 0
		return profile
	end)
	
	if not success then
		return { ok = false, error = TutorialService.ErrorCodes.INTERNAL }
	end
	
	return { ok = true }
end

return TutorialService

