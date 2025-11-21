--[[

If you are looking for the actual emitter code, select the module inside this script instead.

If you're curious what this script is, it is a system that automatically runs code on objects
tagged with specific tags using CollectionService. In this case, it only listens for the tag "Emitter2D". 

Do not re-name or alter the attributes of the Emitter2D module unless you know what you're doing. 

--]]


local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = game.Players.LocalPlayer

local ID_Count = 0

local IsPlugin = script:IsA("LocalScript") == false

local Classes = {}
local Events = {}

local ActivateEntity
local DestroyEntity

ActivateEntity = function(Object, Class)
	if Class.Module:GetAttribute("Enabled") then
		local ExistingEntity = Class.EntityList[Object]
		if ExistingEntity then
			warn(Class.ClassName.." client entity for ["..Object:GetFullName().."] already exists ("..ExistingEntity.ID..")") 
			return ExistingEntity
		end

		ID_Count += 1

		--warn("Activating client entity "..ID_Count.." '"..Class.ClassName.."'")

		local Entity = Class.new()
		Entity.ID = ID_Count

		Class.EntityList[Object] = Entity

		function Entity:Deactivate()
			DestroyEntity(Object, Class)
		end

		Entity.Thread = task.spawn(function()
			Class.EntityLoadingCount += 1
			Entity.Loading = true
			Entity:Initiate(Object)
			Entity.Loading = false
			Class.EntityLoadingCount -= 1
		end)
	end
end

DestroyEntity = function(Object, Class)
	local Entity = Class.EntityList[Object]
	if Entity then
		--warn("Deactivating client entity '"..Class.ClassName.." "..Entity.ID.."'")

		Class.EntityList[Object] = nil

		Entity.Destroyed = true

		if coroutine.status(Entity.Thread) ~= "dead" then
			task.cancel(Entity.Thread)
			Entity.Loading = false
			Class.EntityLoadingCount -= 1
		end

		Entity:Destroy()
	end
end

-- Load classes

for i,Module in script:GetDescendants() do
	if Module:IsA("ModuleScript") then
		task.spawn(function()
			-- Set classname

			local ClassName = Module.Name

			if Module:GetAttribute("Require_UserId") then
				ClassName = ClassName.."_"..Player.UserId
			end

			-- Create class

			local Class = require(Module)

			Class.Module = Module
			Class.ClassName = ClassName
			
			Class.Destroyed = false

			Class.EntityList = {}
			Class.EntityCount = 0
			Class.EntityLoadingCount = 0

			-- Load entities

			table.insert(Events, CollectionService:GetInstanceAddedSignal(ClassName):Connect(function(Object)
				ActivateEntity(Object, Class)
			end))

			table.insert(Events, CollectionService:GetInstanceRemovedSignal(ClassName):Connect(function(Object)
				DestroyEntity(Object, Class)
			end))

			if Module:GetAttribute("Asynchronous") then
				for i,Object in CollectionService:GetTagged(ClassName) do
					ActivateEntity(Object, Class)
				end
			else
				for i,Object in CollectionService:GetTagged(ClassName) do
					task.spawn(ActivateEntity, Object, Class)
				end
			end

			table.insert(Events, Module:GetAttributeChangedSignal("Enabled"):Connect(function()
				local Enabled = Module:GetAttribute("Enabled")
				if Enabled then
					for i,Object in CollectionService:GetTagged(ClassName) do
						task.spawn(ActivateEntity, Object, Class)
					end
				else
					for i,Object in CollectionService:GetTagged(ClassName) do
						task.spawn(DestroyEntity, Object, Class)
					end
				end
			end))

			-- Add to class list

			Classes[ClassName] = Class
		end)
	end
end

if IsPlugin then
	table.insert(Events, script.Parent.Events.Deactivate.Event:Connect(function()
		--print("Deactivating Emitter2D client")
		for _,conn in Events do
			conn:Disconnect()
		end
		for _,class in Classes do
			for object in class.EntityList do
				task.spawn(DestroyEntity, object, class)
			end
		end
	end))
end