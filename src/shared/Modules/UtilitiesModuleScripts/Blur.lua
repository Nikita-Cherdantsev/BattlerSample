local Lighting = game:GetService("Lighting")

local blur = Lighting:FindFirstChildOfClass("BlurEffect") or Instance.new("BlurEffect", Lighting)
blur.Size = 0

local Blur = {}

function Blur.Show()
	blur.Size = 24
end

function Blur.Hide()
	blur.Size = 0
end

return Blur