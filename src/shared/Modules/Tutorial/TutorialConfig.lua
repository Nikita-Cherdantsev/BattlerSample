--[[
	TutorialConfig - Configuration for tutorial steps
	
	Defines all tutorial steps with their conditions, highlights, arrows, and text.
]]

local TutorialConfig = {}

-- Tutorial step structure:
-- {
--   startCondition = { 
--     type = "window_open" | "hud_show" | "button_click" | "conditional",
--     target = "WindowName" | "PanelName" | "ButtonName",  -- For window_open/hud_show/button_click
--     condition = "conditionName",  -- For conditional (e.g., "collection_count", "playtime_reward_available")
--     execute = "methodName"  -- For conditional (e.g., "HandleAddCardToDeck", "HandlePlaytimeRewardAvailable")
--   },
--   highlightObjects = { "ObjectName1", "ObjectName2" | "conditional" },  -- List of UI object names to highlight, "conditional" means computed in execute method
--   arrow = { objectName = "ObjectName" | "conditional", side = "left" | "right" },  -- Optional
--   path = "TargetName",  -- Optional: creates Beam from player to target object (only one model)
--   promptTargets = { "NPCName1", "NPCName2" },  -- Optional: array of NPC names that can complete the step (for prompt_click)
--   text = "Tutorial text here",  -- Optional
--   altText = "Alternative text",  -- Optional: alternative text for conditional steps
--   forceStepOnGameLoad = number,  -- Optional: if startCondition is not met on game load, reset tutorial to this step and show it (ignored during normal step transitions)
--   nextStep = number,  -- Optional: custom next step index (overrides automatic increment, can be set dynamically by conditional handlers)
--   altNextStep = number,  -- Optional: alternative next step for conditional steps (e.g., loss case vs victory case)
--   completeCondition = { 
--     type = "window_open" | "window_close" | "button_click" | "prompt_click",
--     target = "WindowName" | "ButtonName" | "conditional",
--     force = true  -- Optional: force complete step if condition fails
--   }
-- }

TutorialConfig.Steps = {
    -- 1 Claim daily reward
    [1] = {
        startCondition = { type = "window_open", target = "Daily" },
        highlightObjects = { "Daily.Frame.Main", "Daily.Frame.Buttons.BtnClaim" },
		arrow = { objectName = "Daily.Frame.Buttons.BtnClaim", side = "left" },
        text = "Welcome to <b>ANIME!</b>\nClaim your first <b>daily bonus</b> and see what happens…",
        completeCondition = { type = "button_click", target = "Daily.Frame.Buttons.BtnClaim" },
    },
	-- 2 Claim card
	[2] = {
		forceStepOnGameLoad = 3,
		startCondition = { type = "conditional", condition = "lootbox_claim_available", execute = "HandleLootboxClaimAvailable" },
		arrow = { objectName = "LootboxOpening.BtnClaim", side = "left" },
		text = "Wow! A <b>new card</b> for your <b>collection</b>! Ready to get another one?",
		completeCondition = { type = "button_click", target = "LootboxOpening.BtnClaim" }
	},
	-- 3 Open first lootbox
	[3] = {
		startCondition = { type = "hud_show", target = "BottomPanel" },
		highlightObjects = { "BottomPanel.Packs.Outline.Content.Pack1" },
		arrow = { objectName = "BottomPanel.Packs.Outline.Content.Pack1.BtnOpen", side = "left" },
		text = "You have a <b>card capsule</b> in your <b>inventory</b>... Open it!",
		completeCondition = { type = "button_click", target = "BottomPanel.Packs.Outline.Content.Pack1.BtnOpen" }
	},
	-- 4 Claim card
	[4] = {
		forceStepOnGameLoad = 5,
		startCondition = { type = "conditional", condition = "lootbox_claim_available", execute = "HandleLootboxClaimAvailable" },
		arrow = { objectName = "LootboxOpening.BtnClaim", side = "left" },
		completeCondition = { type = "button_click", target = "LootboxOpening.BtnClaim" }
	},
	-- 5 Open Deck window
	[5] = {
		startCondition = { type = "hud_show", target = "LeftPanel" }, 
		highlightObjects = { "LeftPanel.BtnDeck" },
		arrow = { objectName = "BtnDeck", side = "right" },
		text = "Time to check your <b>deck</b>!",
		completeCondition = { type = "button_click", target = "LeftPanel.BtnDeck" }
	},
	-- 6 Select card
	[6] = {
		forceStepOnGameLoad = 5,
		startCondition = { type = "window_open", target = "Deck" },
		highlightObjects = { "Deck.Deck.Content.Content.DeckCard_card_600_1" },
		arrow = { objectName = "Deck.Deck.Content.Content.DeckCard_card_600_1", side = "left" },
		text = "Nice! You can <b>level up</b> the card!",
		completeCondition = { type = "button_click", target = "Deck.Deck.Content.Content.DeckCard_card_600_1.BtnInfo" }
	},
	-- 7 Card selected - level up
	[7] = {
		forceStepOnGameLoad = 5,
		startCondition = { type = "window_open", target = "CardInfo" },
		highlightObjects = { "CardInfo.Main.Content.Content", "CardInfo.Buttons.BtnLevelUp" },  
		arrow = { objectName = "CardInfo.Buttons.BtnLevelUp", side = "left" },
		text = "The higher the <b>level</b>, the stronger the card.",
		completeCondition = { type = "button_click", target = "CardInfo.Buttons.BtnLevelUp" }  
	},
	-- 8 CardInfo closed
	[8] = {
		startCondition = { type = "window_open", target = "CardInfo" },
		completeCondition = { type = "window_close", target = "CardInfo", force = true }
	},
	-- 9 Add another card to the deck
	[9] = {
		startCondition = { type = "conditional", condition = "collection_count", execute = "HandleAddCardToDeck" },
		highlightObjects = { "conditional" },
		arrow = { objectName = "conditional", side = "left" },
		text = "Now let’s <b>add another card to the deck</b>.",
		completeCondition = { type = "button_click", target = "conditional", force = true }
	},
	-- 10 Card selected - to deck
	[10] = {
		startCondition = { type = "window_open", target = "CardInfo" },
		highlightObjects = { "CardInfo.Main.Content.Content", "CardInfo.Buttons.BtnDeck" },  
		arrow = { objectName = "CardInfo.Buttons.BtnDeck", side = "left" },
		text = "A deck can have <b>no fewer than 1 and no more than 6 cards</b>.",
		completeCondition = { type = "button_click", target = "CardInfo.Buttons.BtnDeck", force = true }  
	},
	-- 11 First battle
	[11] = {
		startCondition = { type = "hud_show", target = "BottomPanel" },
		path = "Workspace.Noob",
		promptTargets = { "Noob", "Another Guy", "Master", "Master", "scrap cyborg noob" },
		text = "Time for your <b>first victory!</b> Follow the arrow.",
		completeCondition = { type = "prompt_click", target = "conditional" }
	},
	-- 12 Start battle
	[12] = {
		forceStepOnGameLoad = 11,
		startCondition = { type = "window_open", target = "StartBattle" },
		highlightObjects = { "StartBattle.Main.Content.RivalsDeck", "StartBattle.Main.Content.Rewards", "StartBattle.Buttons.BtnStart" },
		arrow = { objectName = "StartBattle.Buttons.BtnStart", side = "left" },
		text = "This is your <b>rival’s deck</b>. Beat them to earn a <b>card capsule</b>. Let’s go!",
		completeCondition = { type = "button_click", target = "StartBattle.Buttons.BtnStart" }
	},
	-- 13 Claim lootbox (conditional: handles both victory and loss)
	[13] = {
		forceStepOnGameLoad = 14,
		startCondition = { type = "conditional", condition = "reward_window_open", execute = "HandleRewardWindowOpen" },
		highlightObjects = { "conditional" },
		arrow = { objectName = "Reward.Buttons.BtnClaim", side = "left" },
		text = "Your first <b>victory!</b> Capsules go straight to <b>your inventory</b>. Try claiming one.",
		altText = "Don't worry! <b>You still get rewards</b> even when you lose.",
		nextStep = 14,      -- Next step for victory case
		altNextStep = 11,   -- Next step for loss case
		completeCondition = { type = "button_click", target = "conditional" }
	},
	-- 14 Unlock lootbox
	[14] = {
		startCondition = { type = "conditional", condition = "lootbox_available", execute = "HandleLootboxAvailable" },
		highlightObjects = { "BottomPanel.Packs.Outline.Content.Pack1" },
		arrow = { objectName = "BottomPanel.Packs.Outline.Content.Pack1.BtnUnlock", side = "left" },
		text = "<b>The better</b> the capsule, <b>the rarer</b> the cards inside. But first, you need to <b>unlock it</b>.",
		completeCondition = { type = "button_click", target = "BottomPanel.Packs.Outline.Content.Pack1.BtnUnlock" }
	},
	-- 15 Second battle
	[15] = {
		startCondition = { type = "hud_show", target = "BottomPanel" },
		path = "Workspace.Noob",
		promptTargets = { "Noob", "Another Guy", "Master", "Master", "scrap cyborg noob" },
		text = "While waiting the capsule to unlock, let’s jump into another battle!",
		completeCondition = { type = "prompt_click", target = "conditional" }
	},
	-- 16 Start second battle
	[16] = {
		forceStepOnGameLoad = 15,
		startCondition = { type = "window_open", target = "StartBattle" },
		highlightObjects = { "StartBattle.Main.Content.RivalsDeck", "StartBattle.Buttons.BtnStart" },
		arrow = { objectName = "StartBattle.Buttons.BtnStart", side = "left" },
		text = "The rival’s deck <b>changes after every battle</b>.",
		completeCondition = { type = "button_click", target = "StartBattle.Buttons.BtnStart" }
	},
	-- 17 Boss battle
	[17] = {
		startCondition = { type = "hud_show", target = "BottomPanel" },
		path = "Workspace.Rubber King",
		text = "You’re doing great! Ready to take on <b>the boss?</b>",
		completeCondition = { type = "prompt_click", target = "conditional" }
	},
	-- 18 Start boss battle
	[18] = {
		forceStepOnGameLoad = 17,
		startCondition = { type = "window_open", target = "StartBattle" },
		highlightObjects = { "StartBattle.Main.Content.TxtRival.TxtDifficulty", "StartBattle.Main.Content.RivalsDeck", "StartBattle.Main.Content.Rewards", "StartBattle.Buttons.BtnStart" },
		arrow = { objectName = "StartBattle.Buttons.BtnStart", side = "left" },
		text = "Each boss win makes <b>the next battle harder</b>. But you’ll earn <b>a themed capsule</b> as a reward!",
		completeCondition = { type = "button_click", target = "StartBattle.Buttons.BtnStart" }
	},
	-- 19 Claim boss reward
	[19] = {
		forceStepOnGameLoad = 20,
		startCondition = { type = "window_open", target = "Reward" },
		highlightObjects = { "Reward.Victory", "Reward.PacksSelector.Packs", "Reward.Buttons.BtnClaim" },
		arrow = { objectName = "Reward.Buttons.BtnClaim", side = "left" },
		completeCondition = { type = "button_click", target = "Reward.Buttons.BtnClaim" }
	},
	-- 20 Go to playtime rewards
	[20] = {
		startCondition = { type = "conditional", condition = "playtime_reward_available", execute = "HandlePlaytimeRewardAvailable" },
		highlightObjects = { "LeftPanel.BtnPlaytime" },  
		arrow = { objectName = "LeftPanel.BtnPlaytime", side = "right" },
		text = "You can claim <b>rewards</b> for the time <b>you spend in-game</b>!",
		completeCondition = { type = "button_click", target = "LeftPanel.BtnPlaytime" }  
	},
	-- 21 Claim playtime reward
	[21] = {
		forceStepOnGameLoad = 20,
		startCondition = { type = "conditional", condition = "playtime_reward_claimable", execute = "HandleClaimPlaytimeReward" },
		highlightObjects = { "conditional" },
		arrow = { objectName = "conditional", side = "left" },
		text = "These rewards are <b>infinite</b> – just keep <b>coming back and playing</b>.",
		completeCondition = { type = "button_click", target = "conditional" }
	},
}

-- Get the total number of tutorial steps
function TutorialConfig.GetStepCount()
	local maxIndex = 0
	for index in pairs(TutorialConfig.Steps) do
		if type(index) == "number" and index > maxIndex then
			maxIndex = index
		end
	end
	return maxIndex
end

-- Get a specific tutorial step (1-indexed)
function TutorialConfig.GetStep(stepIndex)
	if stepIndex < 1 or stepIndex > TutorialConfig.GetStepCount() then
		return nil
	end
	return TutorialConfig.Steps[stepIndex]
end

-- Check if tutorial is complete (all steps done)
function TutorialConfig.IsComplete(completedStep)
	return completedStep >= TutorialConfig.GetStepCount()
end

-- Get the next step index (returns nil if tutorial is complete)
-- If step has nextStep field, use it; otherwise use automatic increment
function TutorialConfig.GetNextStepIndex(currentStep)
	if currentStep >= TutorialConfig.GetStepCount() then
		return nil  -- Tutorial is complete
	end
	
	-- Check if current step has custom nextStep (may be set dynamically by conditional handlers)
	local currentStepConfig = TutorialConfig.GetStep(currentStep)
	if currentStepConfig and currentStepConfig.nextStep then
		return currentStepConfig.nextStep
	end
	
	-- Default: automatic increment
	return currentStep + 1
end

return TutorialConfig

