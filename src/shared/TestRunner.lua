-- TestRunner.lua
-- Execute this script to run all self-checks for Step 2A (Consistency Patch)
-- Usage: require(script.Parent.TestRunner).RunTests()

local TestRunner = {}

-- Import the self-check module
local SelfCheck = require(script.Parent.Modules.SelfCheck)

function TestRunner.RunTests()
	print("🎮 Card Battler MVP - Step 2A Consistency Patch Test Runner")
	print("=" .. string.rep("=", 50))
	
	-- Run all tests
	local success = SelfCheck.RunAllTests()
	
	if success then
		print("\n🎉 SUCCESS: All Step 2A consistency patch tests passed!")
		print("Ready to proceed to Step 2B (PlayerDataService + Persistence)")
	else
		print("\n❌ FAILURE: Some Step 2A consistency patch tests failed!")
		print("Please review the implementation before proceeding.")
	end
	
	return success
end

-- Quick test functions for individual modules
function TestRunner.TestCardCatalog()
	print("🔍 Testing Card Catalog (Canon Enums)...")
	SelfCheck.TestCardCatalog()
end

function TestRunner.TestDeckValidation()
	print("🔍 Testing Deck Validation (1-based Indexing)...")
	SelfCheck.TestDeckValidation()
end

function TestRunner.TestSeededRNG()
	print("🔍 Testing Seeded RNG...")
	SelfCheck.TestSeededRNG()
end

function TestRunner.TestCombatTypes()
	print("🔍 Testing Combat Types...")
	SelfCheck.TestCombatTypes()
end

function TestRunner.TestGameConstants()
	print("🔍 Testing Game Constants (Updated)...")
	SelfCheck.TestGameConstants()
end

-- Auto-run tests when script is executed
if script.Parent then
	print("🚀 Auto-running Step 2A consistency patch tests...")
	TestRunner.RunTests()
end

return TestRunner
