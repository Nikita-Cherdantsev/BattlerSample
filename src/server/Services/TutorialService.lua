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
function TutorialService.CompleteStep(playerId, stepIndex)
	if not playerId or type(playerId) ~= "number" then
		return { ok = false, error = TutorialService.ErrorCodes.INVALID_REQUEST }
	end
	
	if not stepIndex or type(stepIndex) ~= "number" or stepIndex < 1 then
		return { ok = false, error = TutorialService.ErrorCodes.INVALID_REQUEST }
	end
	
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
		-- Only update if this step is the next one to complete
		local currentStep = profile.tutorialStep or 0
		Logger.debug("TutorialService.CompleteStep (inside UpdateProfile): currentStep=%d, stepIndex=%d", currentStep, stepIndex)
		
		if stepIndex == currentStep + 1 then
			profile.tutorialStep = stepIndex
			Logger.debug("TutorialService.CompleteStep: Updated tutorialStep from %d to %d", currentStep, stepIndex)
		elseif stepIndex <= currentStep then
			-- Step already completed, no-op
			Logger.debug("TutorialService.CompleteStep: Step %d already completed (currentStep=%d), no-op", stepIndex, currentStep)
			return profile
		else
			-- Trying to skip steps - not allowed
			local errorMsg = string.format("Cannot skip tutorial steps: currentStep=%d, stepIndex=%d (expected %d)", currentStep, stepIndex, currentStep + 1)
			Logger.error("TutorialService.CompleteStep: %s", errorMsg)
			error(errorMsg)
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

