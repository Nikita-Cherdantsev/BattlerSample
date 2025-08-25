-- MatchTestHarness.client.lua
-- Lightweight client dev harness for testing matches
-- Toggle on/off for development testing

local MatchTestHarness = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Configuration
local ENABLED = true -- Toggle this to enable/disable the harness
local AUTO_RUN = true -- Auto-run on script start
local RERUN_DELAY = 5 -- Seconds to wait before re-running for determinism test
local LOG_ENTRIES_TO_SHOW = 10 -- Number of battle log entries to display
local COOLDOWN_DELAY = 1.2 -- Minimum seconds between requests (server cooldown + buffer)
local RETRY_DELAY = 2.0 -- Seconds to wait before retrying after rate limit

-- Wait for Network folder
local NetworkFolder = ReplicatedStorage:WaitForChild("Network")

-- Remote Events
local RequestProfile = NetworkFolder:WaitForChild("RequestProfile")
local ProfileUpdated = NetworkFolder:WaitForChild("ProfileUpdated")
local RequestStartMatch = NetworkFolder:WaitForChild("RequestStartMatch")

-- State
local isRunning = false
local shouldAutoStartOnNextProfile = false
local lastMatchResult = nil
local lastRequestTime = 0
local lastMatchSeed = nil
local lastMatchMode = nil
local pendingRetry = false
local expectingDeterminismTest = false
local connections = {}

-- Utility functions
local function LogInfo(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("[MatchTest] %s", formattedMessage))
end

local function LogSuccess(message, ...)
	local formattedMessage = string.format(message, ...)
	print(string.format("✅ [MatchTest] %s", formattedMessage))
end

local function LogError(message, ...)
	local formattedMessage = string.format(message, ...)
	warn(string.format("❌ [MatchTest] %s", formattedMessage))
end

local function LogWarning(message, ...)
	local formattedMessage = string.format(message, ...)
	warn(string.format("⚠️ [MatchTest] %s", formattedMessage))
end

local function WaitForCooldown()
	local timeSinceLastRequest = tick() - lastRequestTime
	if timeSinceLastRequest < COOLDOWN_DELAY then
		local waitTime = COOLDOWN_DELAY - timeSinceLastRequest
		LogInfo("Waiting %.1f seconds for cooldown...", waitTime)
		task.wait(waitTime)
	end
end

local function SendMatchRequest(mode, seed)
	WaitForCooldown()
	
	local requestData = {mode = mode}
	if seed then
		requestData.seed = seed
		LogInfo("Sending match request with seed: %d", seed)
	else
		LogInfo("Sending match request (server will generate seed)")
	end
	
	lastRequestTime = tick()
	RequestStartMatch:FireServer(requestData)
end

local function PrintProfile(profileData)
	print("\n" .. string.rep("=", 50))
	print("📋 Player Profile")
	print("=" .. string.rep("=", 50))
	
	if profileData.deck then
		print("Active Deck:", table.concat(profileData.deck, ", "))
	else
		print("Active Deck: None")
	end
	
	if profileData.collectionSummary then
		print("Collection Size:", #profileData.collectionSummary, "card types")
		print("Sample Cards:")
		for i = 1, math.min(5, #profileData.collectionSummary) do
			local card = profileData.collectionSummary[i]
			local levelText = card.level and string.format(" (L%d)", card.level) or ""
			print(string.format("  %s: %d copies%s", card.cardId, card.count, levelText))
		end
	end
	
	if profileData.loginInfo then
		print("Login Streak:", profileData.loginInfo.loginStreak)
		print("Last Login:", os.date("%Y-%m-%d %H:%M:%S", profileData.loginInfo.lastLoginAt))
	end
	
	print("=" .. string.rep("=", 50))
end

local function PrintMatchResult(result)
	print("\n" .. string.rep("=", 50))
	print("🎮 Match Result")
	print("=" .. string.rep("=", 50))
	
	if result.ok then
		print("Status: SUCCESS")
		print("Match ID:", result.matchId)
		print("Seed:", result.seed)
		print("Winner:", result.result.winner)
		print("Rounds:", result.result.rounds)
		print("Survivors A:", result.result.survivorsA)
		print("Survivors B:", result.result.survivorsB)
		print("Total Actions:", result.result.totalActions)
		print("Total Damage:", result.result.totalDamage)
		print("Total KOs:", result.result.totalKOs)
		
		-- Show battle log entries
		if result.log and #result.log > 0 then
			print("\nBattle Log (first", LOG_ENTRIES_TO_SHOW, "entries):")
			for i = 1, math.min(LOG_ENTRIES_TO_SHOW, #result.log) do
				local entry = result.log[i]
				if entry.t == "a" then
					print(string.format("  %d: Attack - %s slot %d → %s slot %d, damage: %d%s", 
						i, entry.ap, entry.as, entry.dp, entry.ds, entry.d, entry.k and " (KO)" or ""))
				elseif entry.t == "r" then
					print(string.format("  %d: Round %d start", i, entry.r))
				end
			end
			
			if #result.log > LOG_ENTRIES_TO_SHOW then
				print(string.format("  ... and %d more entries", #result.log - LOG_ENTRIES_TO_SHOW))
			end
		else
			print("Battle Log: Empty")
		end
	else
		print("Status: FAILED")
		print("Error Code:", result.error.code)
		print("Error Message:", result.error.message)
	end
	
	print("=" .. string.rep("=", 50))
end

local function CompareMatchResults(result1, result2)
	if not result1.ok or not result2.ok then
		LogError("Cannot compare failed results")
		return false
	end
	
	local differences = {}
	
	-- Compare basic results
	if result1.result.winner ~= result2.result.winner then
		table.insert(differences, string.format("Winner: %s vs %s", result1.result.winner, result2.result.winner))
	end
	
	if result1.result.rounds ~= result2.result.rounds then
		table.insert(differences, string.format("Rounds: %d vs %d", result1.result.rounds, result2.result.rounds))
	end
	
	if result1.result.survivorsA ~= result2.result.survivorsA then
		table.insert(differences, string.format("Survivors A: %d vs %d", result1.result.survivorsA, result2.result.survivorsA))
	end
	
	if result1.result.survivorsB ~= result2.result.survivorsB then
		table.insert(differences, string.format("Survivors B: %d vs %d", result1.result.survivorsB, result2.result.survivorsB))
	end
	
	if result1.result.totalActions ~= result2.result.totalActions then
		table.insert(differences, string.format("Total Actions: %d vs %d", result1.result.totalActions, result2.result.totalActions))
	end
	
	if result1.result.totalDamage ~= result2.result.totalDamage then
		table.insert(differences, string.format("Total Damage: %d vs %d", result1.result.totalDamage, result2.result.totalDamage))
	end
	
	if result1.result.totalKOs ~= result2.result.totalKOs then
		table.insert(differences, string.format("Total KOs: %d vs %d", result1.result.totalKOs, result2.result.totalKOs))
	end
	
	-- Compare log entries
	if #result1.log ~= #result2.log then
		table.insert(differences, string.format("Log length: %d vs %d", #result1.log, #result2.log))
	else
		for i = 1, #result1.log do
			local entry1 = result1.log[i]
			local entry2 = result2.log[i]
			
			if entry1.t ~= entry2.t then
				table.insert(differences, string.format("Log[%d] type: %s vs %s", i, entry1.t, entry2.t))
				break -- Stop at first difference
			elseif entry1.t == "a" then
				if entry1.as ~= entry2.as or entry1.ap ~= entry2.ap or entry1.ds ~= entry2.ds or 
				   entry1.dp ~= entry2.dp or entry1.d ~= entry2.d or entry1.k ~= entry2.k then
					table.insert(differences, string.format("Log[%d] attack: %s%d→%s%d %d%s vs %s%d→%s%d %d%s", 
						i, entry1.ap, entry1.as, entry1.dp, entry1.ds, entry1.d, entry1.k and "(KO)" or "",
						entry2.ap, entry2.as, entry2.dp, entry2.ds, entry2.d, entry2.k and "(KO)" or ""))
					break -- Stop at first difference
				end
			elseif entry1.t == "r" and entry1.r ~= entry2.r then
				table.insert(differences, string.format("Log[%d] round: %d vs %d", i, entry1.r, entry2.r))
				break -- Stop at first difference
			end
		end
	end
	
	if #differences == 0 then
		LogSuccess("Determinism test PASSED - identical results")
		return true
	else
		LogError("Determinism test FAILED - first difference:")
		LogError("  %s", differences[1])
		return false
	end
end

-- Event handlers
local function OnProfileUpdated(profileData)
	if not isRunning then return end
	
	LogSuccess("Profile received")
	PrintProfile(profileData)
	
	-- Start match after profile is loaded
	task.wait(0.5) -- Small delay for readability
	
	if shouldAutoStartOnNextProfile then
		LogInfo("Starting match...")
		SendMatchRequest("PvE")
	else
		LogInfo("Profile received, but not starting match")
		shouldAutoStartOnNextProfile = true
	end
end

local function OnMatchResult(result)
	if not isRunning then return end
	
	LogSuccess("Match result received")
	PrintMatchResult(result)
	
	-- Handle rate limiting with retry
	if not result.ok and result.error and result.error.code == "RATE_LIMITED" then
		if not pendingRetry then
			LogWarning("Rate limited, retrying after %.1f seconds...", RETRY_DELAY)
			pendingRetry = true
			task.delay(RETRY_DELAY, function()
				if isRunning then
					LogInfo("Retry due to rate limit...")
					SendMatchRequest(lastMatchMode or "PvE", lastMatchSeed)
					pendingRetry = false
				end
			end)
		else
			LogError("Rate limited again, giving up")
			pendingRetry = false
		end
		return
	end
	
	-- Handle determinism test comparison
	if expectingDeterminismTest and result.ok then
		expectingDeterminismTest = false
		LogInfo("Comparing determinism test results...")
		CompareMatchResults(lastMatchResult, result)
		return
	end
	
	-- Store result and seed for determinism test
	lastMatchResult = result
	if result.ok then
		lastMatchSeed = result.seed
		lastMatchMode = "PvE" -- Store the mode used
		LogInfo("Stored seed %d for determinism test", result.seed)
		
		-- Schedule re-run for determinism test
		LogInfo("Scheduling determinism test in %d seconds...", RERUN_DELAY)
		task.delay(RERUN_DELAY, function()
			if isRunning then
				LogInfo("Running determinism test with seed %d...", lastMatchSeed)
				expectingDeterminismTest = true
				SendMatchRequest("PvE", lastMatchSeed)
			end
		end)
	end
end

local function OnInputBegan(input, gameProcessed)
	if not isRunning or gameProcessed then return end
	
	-- Hotkey: R to re-run match
	if input.KeyCode == Enum.KeyCode.R then
		LogInfo("Hotkey pressed: Re-running match")
		SendMatchRequest("PvE")
	end
	
	-- Hotkey: Ctrl+D to run determinism test
	if input.KeyCode == Enum.KeyCode.D and input:IsModifierKeyDown(Enum.ModifierKey.Ctrl) and lastMatchResult and lastMatchResult.ok and lastMatchSeed then
		LogInfo("Hotkey pressed: Running determinism test with seed %d", lastMatchSeed)
		expectingDeterminismTest = true
		SendMatchRequest("PvE", lastMatchSeed)
	elseif input.KeyCode == Enum.KeyCode.D and input:IsModifierKeyDown(Enum.ModifierKey.Ctrl) then
		LogWarning("Cannot run determinism test - no previous match result or seed available")
	end
	
	-- Hotkey: P to request profile
	if input.KeyCode == Enum.KeyCode.P then
		LogInfo("Hotkey pressed: Requesting profile")
		shouldAutoStartOnNextProfile = false
		RequestProfile:FireServer({})
	end
end

-- Main test function
function MatchTestHarness.RunTest()
	if not ENABLED then
		LogWarning("MatchTestHarness is disabled. Set ENABLED = true to enable.")
		return
	end
	
	if isRunning then
		LogWarning("Test already running")
		return
	end
	
	isRunning = true
	shouldAutoStartOnNextProfile = true
	lastMatchResult = nil
	lastRequestTime = 0
	lastMatchSeed = nil
	lastMatchMode = nil
	pendingRetry = false
	expectingDeterminismTest = false
	
	LogInfo("Starting Match Test Harness")
	print("=" .. string.rep("=", 60))
	
	-- Connect event handlers
	connections.profileUpdated = ProfileUpdated.OnClientEvent:Connect(OnProfileUpdated)
	connections.matchResult = RequestStartMatch.OnClientEvent:Connect(OnMatchResult)
	connections.testInput = UIS.InputBegan:Connect(OnInputBegan)
	
	-- Start by requesting profile
	LogInfo("Requesting player profile...")
	RequestProfile:FireServer({})
	
	LogInfo("Test started. Hotkeys:")
	LogInfo("  R - Re-run match")
	LogInfo("  Ctrl+D - Determinism test")
	LogInfo("  P - Request profile")
	LogInfo("  T - Toggle harness")
end

function MatchTestHarness.StopTest()
	if not isRunning then
		LogWarning("Test not running")
		return
	end
	
	isRunning = false
	
	-- Disconnect test-specific connections (but keep persistent ones)
	if connections.profileUpdated then
		connections.profileUpdated:Disconnect()
		connections.profileUpdated = nil
	end
	if connections.matchResult then
		connections.matchResult:Disconnect()
		connections.matchResult = nil
	end
	if connections.testInput then
		connections.testInput:Disconnect()
		connections.testInput = nil
	end
	
	LogInfo("Match Test Harness stopped")
end

function MatchTestHarness.Toggle()
	if isRunning then
		MatchTestHarness.StopTest()
	else
		MatchTestHarness.RunTest()
	end
end

function MatchTestHarness.GetStatus()
	return {
		enabled = ENABLED,
		running = isRunning,
		lastResult = lastMatchResult ~= nil
	}
end

-- Cleanup on script disable
local function OnScriptDisable()
	MatchTestHarness.StopTest()
end

-- Cleanup on player leaving
local function OnPlayerRemoving()
	MatchTestHarness.StopTest()
end

-- Connect cleanup events
connections.playerRemoving = Players.PlayerRemoving:Connect(OnPlayerRemoving)

-- Connect persistent input handler for toggle (always available)
connections.toggleInput = UIS.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.T then
		MatchTestHarness.Toggle()
	end
end)

-- Auto-run if enabled
if ENABLED and AUTO_RUN then
	-- Wait a bit for everything to load
	task.wait(1)
	MatchTestHarness.RunTest()
end

-- Public API
MatchTestHarness.ENABLED = ENABLED
MatchTestHarness.AUTO_RUN = AUTO_RUN
MatchTestHarness.RERUN_DELAY = RERUN_DELAY
MatchTestHarness.LOG_ENTRIES_TO_SHOW = LOG_ENTRIES_TO_SHOW

return MatchTestHarness
