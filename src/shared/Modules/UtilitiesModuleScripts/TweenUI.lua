local TweenService = game:GetService("TweenService")

local TweenUI = {}

local propertyMap = {
	TextLabel = {"TextTransparency", "TextStrokeTransparency", "BackgroundTransparency"},
	TextButton = {"TextTransparency", "TextStrokeTransparency", "BackgroundTransparency"},
	ImageLabel = {"ImageTransparency", "BackgroundTransparency"},
	ImageButton = {"ImageTransparency", "BackgroundTransparency"},
	Frame = {"BackgroundTransparency"},
	UIStroke = {"Transparency"},
}

local baseTransparencyMap = {}

local function getTweenables(root)
	local list = {}
	for _, obj in ipairs(root:GetDescendants()) do
		local props = propertyMap[obj.ClassName]
		if props then
			table.insert(list, {instance = obj, properties = props})
		end
	end
	local rootProps = propertyMap[root.ClassName]
	if rootProps then
		table.insert(list, {instance = root, properties = rootProps})
	end
	return list
end

local function storeBaseTransparency(frame, objects)
	baseTransparencyMap[frame] = {}
	for _, entry in ipairs(objects) do
		local obj = entry.instance
		local props = entry.properties
		baseTransparencyMap[frame][obj] = {}
		for _, prop in ipairs(props) do
			baseTransparencyMap[frame][obj][prop] = obj[prop]
		end
	end
end

local function applyTransparencyFromMap(frame)
	local saved = baseTransparencyMap[frame]
	if not saved then return end
	for obj, props in pairs(saved) do
		for prop, value in pairs(props) do
			if obj and obj[prop] ~= nil then
				obj[prop] = value
			end
		end
	end
end

local function setAllToHidden(objects)
	for _, entry in ipairs(objects) do
		local obj = entry.instance
		for _, prop in ipairs(entry.properties) do
			obj[prop] = 1
		end
	end
end

local function tweenToTarget(objects, targetMap, duration)
	local tweens = {}
	for _, entry in ipairs(objects) do
		local obj = entry.instance
		local props = entry.properties
		local goal = {}
		for _, prop in ipairs(props) do
			local value = targetMap[obj] and targetMap[obj][prop]
			if value ~= nil then
				goal[prop] = value
			end
		end
		local tween = TweenService:Create(obj, TweenInfo.new(duration), goal)
		tween:Play()
		table.insert(tweens, tween)
	end
	return tweens
end

local function runCallbackAfterTweens(tweens, callback)
	if not callback then return end
	local finishedCount = 0
	for _, tween in ipairs(tweens) do
		tween.Completed:Connect(function()
			finishedCount += 1
			if finishedCount == #tweens then
				callback()
			end
		end)
	end
end

function TweenUI.FadeIn(frame, duration, callback)
	frame.Visible = true
	local objects = getTweenables(frame)
	storeBaseTransparency(frame, objects)
	setAllToHidden(objects)
	local tweens = tweenToTarget(objects, baseTransparencyMap[frame], duration)
	runCallbackAfterTweens(tweens, callback)
end

function TweenUI.FadeOut(frame, duration, callback)
	local objects = getTweenables(frame)
	if not baseTransparencyMap[frame] then
		storeBaseTransparency(frame, objects)
	end
	local targetMap = {}
	for _, entry in ipairs(objects) do
		targetMap[entry.instance] = {}
		for _, prop in ipairs(entry.properties) do
			targetMap[entry.instance][prop] = 1
		end
	end
	local tweens = tweenToTarget(objects, targetMap, duration)
	runCallbackAfterTweens(tweens, function()
		frame.Visible = false
		applyTransparencyFromMap(frame)
		if callback then callback() end
	end)
end

return TweenUI