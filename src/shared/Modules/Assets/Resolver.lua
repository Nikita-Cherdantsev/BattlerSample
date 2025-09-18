--[[
	Assets Resolver - Helper functions for asset resolution
	
	Provides pure functions to resolve assets with fallbacks.
	UI-agnostic: returns asset IDs and colors, no Instances.
]]

local Manifest = require(script.Parent.Manifest)

local Resolver = {}

-- Get card image with fallback
function Resolver.getCardImage(cardId)
	if not cardId then
		return Manifest.Placeholder.card
	end
	
	return Manifest.CardImages[cardId] or Manifest.Placeholder.card
end

-- Get class icon with fallback
function Resolver.getClassIcon(class)
	if not class then
		return Manifest.Placeholder.icon
	end
	
	return Manifest.ClassIcons[class] or Manifest.Placeholder.icon
end

-- Get rarity frame with fallback
function Resolver.getRarityFrame(rarity)
	if not rarity then
		return Manifest.Placeholder.frame
	end
	
	return Manifest.RarityFrames[rarity] or Manifest.Placeholder.frame
end

-- Get rarity color with fallback
function Resolver.getRarityColor(rarity)
	if not rarity then
		return Manifest.RarityColors["Uncommon"]
	end
	
	return Manifest.RarityColors[rarity] or Manifest.RarityColors["Uncommon"]
end

-- Get UI color
function Resolver.getUIColor(colorName)
	if not colorName then
		return Manifest.UIColors.textPrimary
	end
	
	return Manifest.UIColors[colorName] or Manifest.UIColors.textPrimary
end

-- Get button color
function Resolver.getButtonColor(state)
	if not state then
		return Manifest.ButtonColors.normal
	end
	
	return Manifest.ButtonColors[state] or Manifest.ButtonColors.normal
end

-- Get all card images
function Resolver.getAllCardImages()
	return Manifest.CardImages
end

-- Get all class icons
function Resolver.getAllClassIcons()
	return Manifest.ClassIcons
end

-- Get all rarity frames
function Resolver.getAllRarityFrames()
	return Manifest.RarityFrames
end

-- Get all rarity colors
function Resolver.getAllRarityColors()
	return Manifest.RarityColors
end

-- Check if asset exists
function Resolver.hasCardImage(cardId)
	return Manifest.CardImages[cardId] ~= nil
end

function Resolver.hasClassIcon(class)
	return Manifest.ClassIcons[class] ~= nil
end

function Resolver.hasRarityFrame(rarity)
	return Manifest.RarityFrames[rarity] ~= nil
end

-- Get reward asset by type and name
function Resolver.getRewardAsset(rewardType, rewardName, size)
	if not rewardType or not rewardName then
		return Manifest.Placeholder.icon
	end

	local asset = Manifest[rewardType][rewardName]
	if rewardType == "Currency" then
		asset = asset[size] or asset.Default
	end
	
	return asset
end

-- Get placeholder assets
function Resolver.getPlaceholders()
	return Manifest.Placeholder
end

return Resolver
