-- MatchTestHarness.client.lua
-- Lightweight client dev harness for testing matches
-- Toggle on/off for development testing

local MatchTestHarness = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Configuration
local ENABLED = true -- Toggle this to enable/disable the harness
local AUTO_RUN = true -- Auto-run on script start
local RERUN_DELAY = 5 -- Seconds to wait before re-running for determinism test
local LOG_ENTRIES_TO_SHOW = 10 -- Number of battle log entries to display

-- Wait for Network folder
local NetworkFolder = ReplicatedStorage:WaitForChild("Network")

-- Remote Events
local RequestProfile = NetworkFolder:WaitForChild("RequestProfile")
local ProfileUpdated = NetworkFolder:WaitForChild("ProfileUpdated")
local RequestStartMatch = NetworkFolder:WaitForChild("RequestStartMatch")

-- State
local isRunning = false
local lastMatchResult = nil
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
			print(string.format("  %s: %d copies", card.cardId, card.count))
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
		table.insert(differences, "Winner differs: " .. result1.result.winner .. " vs " .. result2.result.winner)
	end
	
	if result1.result.rounds ~= result2.result.rounds then
		table.insert(differences, "Rounds differ: " .. result1.result.rounds .. " vs " .. result2.result.rounds)
	end
	
	if result1.result.survivorsA ~= result2.result.survivorsA then
		table.insert(differences, "Survivors A differ: " .. result1.result.survivorsA .. " vs " .. result2.result.survivorsA)
	end
	
	if result1.result.survivorsB ~= result2.result.survivorsB then
		table.insert(differences, "Survivors B differ: " .. result1.result.survivorsB .. " vs " .. result2.result.survivorsB)
	end
	
	-- Compare log entries
	if #result1.log ~= #result2.log then
		table.insert(differences, "Log length differs: " .. #result1.log .. " vs " .. #result2.log)
	else
		for i = 1, math.min(10, #result1.log) do
			local entry1 = result1.log[i]
			local entry2 = result2.log[i]
			
			if entry1.t ~= entry2.t then
				table.insert(differences, "Log entry " .. i .. " type differs")
			elseif entry1.t == "a" then
				if entry1.as ~= entry2.as or entry1.ds ~= entry2.ds or entry1.d ~= entry2.d then
					table.insert(differences, "Log entry " .. i .. " attack details differ")
				end
			end
		end
	end
	
	if #differences == 0 then
		LogSuccess("Determinism test PASSED - identical results")
		return true
	else
		LogError("Determinism test FAILED:")
		for _, diff in ipairs(differences) do
			LogError("  %s", diff)
		end
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
	
	LogInfo("Starting match...")
	RequestStartMatch:FireServer({mode = "PvE"})
end

local function OnMatchResult(result)
	if not isRunning then return end
	
	LogSuccess("Match result received")
	PrintMatchResult(result)
	
	-- Store result for determinism test
	lastMatchResult = result
	
	-- Schedule re-run for determinism test
	if result.ok then
		LogInfo("Scheduling determinism test in %d seconds...", RERUN_DELAY)
		task.delay(RERUN_DELAY, function()
			if isRunning then
				LogInfo("Running determinism test...")
				RequestStartMatch:FireServer({mode = "PvE"})
			end
		end)
	end
end

local function OnInputBegan(input, gameProcessed)
	if not isRunning or gameProcessed then return end
	
	-- Hotkey: R to re-run match
	if input.KeyCode == Enum.KeyCode.R then
		LogInfo("Hotkey pressed: Re-running match")
		RequestStartMatch:FireServer({mode = "PvE"})
	end
	
	-- Hotkey: D to run determinism test
	if input.KeyCode == Enum.KeyCode.D and lastMatchResult and lastMatchResult.ok then
		LogInfo("Hotkey pressed: Running determinism test")
		RequestStartMatch:FireServer({mode = "PvE"})
	end
	
	-- Hotkey: P to request profile
	if input.KeyCode == Enum.KeyCode.P then
		LogInfo("Hotkey pressed: Requesting profile")
		RequestProfile:FireServer({})
	end
	
	-- Hotkey: T to toggle harness
	if input.KeyCode == Enum.KeyCode.T then
		MatchTestHarness.Toggle()
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
	lastMatchResult = nil
	
	LogInfo("Starting Match Test Harness")
	print("=" .. string.rep("=", 60))
	
	-- Connect event handlers
	connections.profileUpdated = ProfileUpdated.OnClientEvent:Connect(OnProfileUpdated)
	connections.matchResult = RequestStartMatch.OnClientEvent:Connect(OnMatchResult)
	connections.inputBegan = UserInputService.InputBegan:Connect(OnInputBegan)
	
	-- Start by requesting profile
	LogInfo("Requesting player profile...")
	RequestProfile:FireServer({})
	
	LogInfo("Test started. Hotkeys:")
	LogInfo("  R - Re-run match")
	LogInfo("  D - Determinism test")
	LogInfo("  P - Request profile")
	LogInfo("  T - Toggle harness")
end

function MatchTestHarness.StopTest()
	if not isRunning then
		LogWarning("Test not running")
		return
	end
	
	isRunning = false
	
	-- Disconnect all connections
	for _, connection in pairs(connections) do
		if connection then
			connection:Disconnect()
		end
	end
	connections = {}
	
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
