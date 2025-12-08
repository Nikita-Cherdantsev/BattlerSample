--[[
	TutorialConfig - Configuration for tutorial steps
	
	Defines all tutorial steps with their conditions, highlights, arrows, and text.
]]

local TutorialConfig = {}

-- Tutorial step structure:
-- {
--   startCondition = { 
--     type = "window_open" | "button_click" | "conditional",
--     target = "WindowName" | "ButtonName",  -- For window_open/button_click
--     condition = "conditionName",  -- For conditional (e.g., "collection_count", "playtime_reward_available")
--     execute = "methodName"  -- For conditional (e.g., "HandleAddCardToDeck", "HandlePlaytimeRewardAvailable")
--   },
--   highlightObjects = { "ObjectName1", "ObjectName2" | "conditional" },  -- List of UI object names to highlight, "conditional" means computed in execute method
--   arrow = { objectName = "ObjectName" | "conditional", side = "left" | "right" },  -- Optional
--   path = "TargetName",  -- Optional: creates Beam from player to target object
--   text = "Tutorial text here",  -- Optional
--   completeCondition = { 
--     type = "window_open" | "window_close" | "button_click" | "prompt_click",
--     target = "WindowName" | "ButtonName" | "conditional",
--     force = true  -- Optional: force complete step if condition fails
--   }
-- }

TutorialConfig.Steps = {
    -- 1 Claim daily reward
    {
        startCondition = { type = "window_open", target = "Daily" },
        highlightObjects = { "Daily.Frame.Main", "Daily.Frame.Buttons.BtnClaim" },
		arrow = { objectName = "Daily.Frame.Buttons.BtnClaim", side = "left" },
        text = "Welcome to <b>ANIME!</b>\nClaim your first <b>daily bonus</b> and see what happens…",
        completeCondition = { type = "button_click", target = "Daily.Frame.Buttons.BtnClaim" }
    },
	-- 2 Claim card
	{
		startCondition = { type = "conditional", condition = "lootbox_claim_available", execute = "HandleLootboxClaimAvailable" },
		arrow = { objectName = "LootboxOpening.BtnClaim", side = "left" },
		text = "Wow! A <b>new card</b> for your <b>collection</b>! Ready to get another one?",
		completeCondition = { type = "button_click", target = "LootboxOpening.BtnClaim" }
	},
	-- 3 Open first lootbox
	{
		startCondition = { type = "window_open", target = "BottomPanel" },
		highlightObjects = { "BottomPanel.Packs.Outline.Content.Pack1" },
		arrow = { objectName = "BottomPanel.Packs.Outline.Content.Pack1.BtnOpen", side = "left" },
		text = "You have a <b>card capsule</b> in your <b>inventory</b>... Open it!",
		completeCondition = { type = "button_click", target = "BottomPanel.Packs.Outline.Content.Pack1.BtnOpen" }
	},
	-- 4 Claim card
	{
		startCondition = { type = "conditional", condition = "lootbox_claim_available", execute = "HandleLootboxClaimAvailable" },
		arrow = { objectName = "LootboxOpening.BtnClaim", side = "left" },
		completeCondition = { type = "button_click", target = "LootboxOpening.BtnClaim" }
	},
	-- 5 Open Deck window
	{
		startCondition = { type = "window_open", target = "LeftPanel" }, 
		highlightObjects = { "LeftPanel.BtnDeck" },
		arrow = { objectName = "BtnDeck", side = "right" },
		text = "Time to check your <b>deck</b>!",
		completeCondition = { type = "button_click", target = "LeftPanel.BtnDeck" }
	},
	-- 6 Select card
	{
		startCondition = { type = "window_open", target = "Deck" },
		highlightObjects = { "Deck.Deck.Content.Content.DeckCard_card_600_1" },
		arrow = { objectName = "Deck.Deck.Content.Content.DeckCard_card_600_1", side = "left" },
		text = "Nice! You can <b>level up</b> the card!",
		completeCondition = { type = "button_click", target = "Deck.Deck.Content.Content.DeckCard_card_600_1.BtnInfo" }
	},
	-- 7 Card selected - level up
	{
		startCondition = { type = "window_open", target = "CardInfo" },
		highlightObjects = { "CardInfo.Main.Content.Content", "CardInfo.Buttons.BtnLevelUp" },  
		arrow = { objectName = "CardInfo.Buttons.BtnLevelUp", side = "left" },
		text = "The higher the <b>level</b>, the stronger the card.",
		completeCondition = { type = "button_click", target = "CardInfo.Buttons.BtnLevelUp" }  
	},
	-- 8 CardInfo closed
	{
		startCondition = { type = "window_open", target = "CardInfo" },
		completeCondition = { type = "window_close", target = "CardInfo" }
	},
	-- 9 Add another card to the deck
	{
		startCondition = { type = "conditional", condition = "collection_count", execute = "HandleAddCardToDeck" },
		highlightObjects = { "conditional" },
		arrow = { objectName = "conditional", side = "left" },
		text = "Now let’s <b>add another card to the deck</b>.",
		completeCondition = { type = "button_click", target = "conditional", force = true }
	},
	-- 10 Card selected - to deck
	{
		startCondition = { type = "window_open", target = "CardInfo" },
		highlightObjects = { "CardInfo.Main.Content.Content", "CardInfo.Buttons.BtnDeck" },  
		arrow = { objectName = "CardInfo.Buttons.BtnDeck", side = "left" },
		text = "A deck can have <b>no fewer than 1 and no more than 6 cards</b>.",
		completeCondition = { type = "button_click", target = "CardInfo.Buttons.BtnDeck", force = true }  
	},
	-- 11 First battle
	{
		startCondition = { type = "window_open", target = "BottomPanel" },
		path = "Workspace.Noob",
		text = "Time for your <b>first battle!</b> Follow the arrow.",
		completeCondition = { type = "prompt_click", target = "conditional" }
	},
	-- 12 Start battle
	{
		startCondition = { type = "window_open", target = "StartBattle" },
		highlightObjects = { "StartBattle.Main.Content.RivalsDeck", "StartBattle.Main.Content.Rewards", "StartBattle.Buttons.BtnStart" },
		arrow = { objectName = "StartBattle.Buttons.BtnStart", side = "left" },
		text = "This is your <b>rival’s deck</b>. Beat them to earn a <b>card capsule</b>. Let’s go!",
		completeCondition = { type = "button_click", target = "StartBattle.Buttons.BtnStart" }
	},
	-- 13 Claim lootbox
	{
		startCondition = { type = "window_open", target = "Reward" },
		highlightObjects = { "Reward.Victory", "Reward.PacksSelector.Packs", "Reward.Buttons.BtnClaim" },
		arrow = { objectName = "Reward.Buttons.BtnClaim", side = "left" },
		text = "Your first <b>victory!</b> Capsules go straight to <b>your inventory</b>. Try claming one.",
		completeCondition = { type = "button_click", target = "Reward.Buttons.BtnClaim" }
	},
	-- 14 Unlock lootbox
	{
		startCondition = { type = "window_open", target = "BottomPanel" },
		highlightObjects = { "BottomPanel.Packs.Outline.Content.Pack1" },
		arrow = { objectName = "BottomPanel.Packs.Outline.Content.Pack1.BtnUnlock", side = "left" },
		text = "<b>The better</b> the capsule, <b>the rarer</b> the cards inside. But first, you need to <b>unlock it</b>.",
		completeCondition = { type = "button_click", target = "BottomPanel.Packs.Outline.Content.Pack1.BtnUnlock" }
	},
	-- 15 Second battle
	{
		startCondition = { type = "window_open", target = "BottomPanel" },
		path = "Workspace.Noob",
		text = "While waiting the capsule to unlock, let’s jump into another battle!",
		completeCondition = { type = "prompt_click", target = "conditional" }
	},
	-- 16 Start second battle
	{
		startCondition = { type = "window_open", target = "StartBattle" },
		highlightObjects = { "StartBattle.Main.Content.RivalsDeck", "StartBattle.Buttons.BtnStart" },
		arrow = { objectName = "StartBattle.Buttons.BtnStart", side = "left" },
		text = "The rival’s deck <b>changes after every battle</b>.",
		completeCondition = { type = "button_click", target = "StartBattle.Buttons.BtnStart" }
	},
	-- 17 Boss battle
	{
		startCondition = { type = "window_open", target = "BottomPanel" },
		path = "Workspace.Rubber King",
		text = "You’re doing great! Ready to take on <b>the boss?</b>",
		completeCondition = { type = "prompt_click", target = "conditional" }
	},
	-- 18 Start boss battle
	{
		startCondition = { type = "window_open", target = "StartBattle" },
		highlightObjects = { "StartBattle.Main.Content.TxtRival.TxtDifficulty", "StartBattle.Main.Content.RivalsDeck", "StartBattle.Main.Content.Rewards", "StartBattle.Buttons.BtnStart" },
		arrow = { objectName = "StartBattle.Buttons.BtnStart", side = "left" },
		text = "Each boss win makes <b>the next battle harder</b>. But you’ll earn <b>a themed capsule</b> as a reward!",
		completeCondition = { type = "button_click", target = "StartBattle.Buttons.BtnStart" }
	},
	-- 19 Claim boss reward
	{
		startCondition = { type = "window_open", target = "Reward" },
		highlightObjects = { "Reward.Victory", "Reward.PacksSelector.Packs", "Reward.Buttons.BtnClaim" },
		arrow = { objectName = "Reward.Buttons.BtnClaim", side = "left" },
		completeCondition = { type = "button_click", target = "Reward.Buttons.BtnClaim" }
	},
	-- 20 Go to playtime rewards
	{
		startCondition = { type = "conditional", condition = "playtime_reward_available", execute = "HandlePlaytimeRewardAvailable" },
		highlightObjects = { "LeftPanel.BtnPlaytime" },  
		arrow = { objectName = "LeftPanel.BtnPlaytime", side = "right" },
		text = "You can claim <b>rewards</b> for the time <b>you spend in-game</b>!",
		completeCondition = { type = "button_click", target = "LeftPanel.BtnPlaytime" }  
	},
	-- 21 Claim playtime reward
	{
		startCondition = { type = "conditional", condition = "playtime_reward_claimable", execute = "HandleClaimPlaytimeReward" },
		highlightObjects = { "conditional" },
		arrow = { objectName = "conditional", side = "left" },
		text = "These rewards are <b>infinite</b> – just keep <b>coming back and playing</b>.",
		completeCondition = { type = "button_click", target = "conditional" }
	},
	--[[
	-- Step 4: Shop tutorial
	{
		startCondition = { type = "window_open", target = "Shop" },
		highlightObjects = { "Shop.Main" },
		text = "Visit the Shop to purchase packs and lootboxes with premium currency.",
		completeCondition = { type = "window_open", target = "Shop" }  -- Complete when shop closes
	},
	
	-- Step 5: Daily rewards
	{
		startCondition = { type = "window_open", target = "Daily" },
		highlightObjects = { "BtnDaily" },
		text = "Claim your daily rewards! Log in every day to get better rewards.",
		completeCondition = { type = "button_click", target = "BtnClaim" }
	}]]
}

-- Get the total number of tutorial steps
function TutorialConfig.GetStepCount()
	return #TutorialConfig.Steps
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
function TutorialConfig.GetNextStepIndex(currentStep)
	if currentStep >= TutorialConfig.GetStepCount() then
		return nil  -- Tutorial is complete
	end
	return currentStep + 1
end

return TutorialConfig

