-- RovC Sandbox Init — place this Script in ServerScriptService
-- Creates tools, handles prop spawning, physgun, toolgun

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local PROP_TAG = "SandboxProp"

-- =====================================================================
-- Client script sources (embedded so one file deploys the whole system)
-- =====================================================================

local PHYSGUN_CLIENT_SRC = [[
local tool = script.Parent
local player = game:GetService("Players").LocalPlayer
local mouse = player:GetMouse()
local runService = game:GetService("RunService")
local events = game:GetService("ReplicatedStorage"):WaitForChild("SandboxEvents")

local holding = false
local holdDist = 10
local minDist, maxDist = 3, 50

local function getHit()
	local cam = workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = { player.Character }
	return workspace:Raycast(ray.Origin, ray.Direction * 500, params)
end

tool.Equipped:Connect(function()
	local handle = Instance.new("SelectionBox")
	handle.Name = "PhysgunBeam"
	handle.Adornee = nil
	handle.Color3 = Color3.fromRGB(0, 200, 255)
	handle.LineThickness = 0.05
	handle.Parent = tool
	tool:SetAttribute("Beam", handle)
end)

tool.Unequipped:Connect(function()
	if holding then events.ReleaseProp:FireServer(); holding = false end
	local beam = tool:GetAttribute("Beam")
	if beam then beam:Destroy() end
end)

tool.Activated:Connect(function()
	if holding then
		events.ReleaseProp:FireServer()
		holding = false
		return
	end
	local hit = getHit()
	if hit and hit.Instance and hit.Instance:IsA("BasePart") then
		events.PickupProp:FireServer(hit.Instance)
		holding = true
		holdDist = math.clamp((hit.Position - workspace.CurrentCamera.CFrame.Position).Magnitude, minDist, maxDist)
	end
end)

mouse.Button2Down:Connect(function()
	if holding then events.FreezeProp:FireServer() end
end)

mouse.WheelForward:Connect(function() holdDist = math.clamp(holdDist - 1, minDist, maxDist) end)
mouse.WheelBackward:Connect(function() holdDist = math.clamp(holdDist + 1, minDist, maxDist) end)

runService.Heartbeat:Connect(function()
	if not holding then return end
	local cam = workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
	events.PhysgunMove:FireServer(CFrame.new(ray.Origin + ray.Direction * holdDist))
end)
]]

local TOOLGUN_CLIENT_SRC = [[
local tool = script.Parent
local player = game:GetService("Players").LocalPlayer
local mouse = player:GetMouse()
local events = game:GetService("ReplicatedStorage"):WaitForChild("SandboxEvents")

local modes = { "Remove", "Weld" }
local modeIdx = 1
local weldingFirst = nil
local screenGui = player:WaitForChild("PlayerGui"):FindFirstChild("ToolgunHUD")

if not screenGui then
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ToolgunHUD"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player.PlayerGui
end

local modeLabel = Instance.new("TextLabel")
modeLabel.Size = UDim2.new(0, 120, 0, 24)
modeLabel.Position = UDim2.new(0.5, -60, 0, 12)
modeLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
modeLabel.BackgroundTransparency = 0.5
modeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
modeLabel.Font = Enum.Font.GothamBold
modeLabel.TextSize = 14
modeLabel.Text = "Mode: Remove"
modeLabel.Parent = screenGui

local function updateModeLabel()
	local m = modes[modeIdx]
	if m == "Weld" and weldingFirst then
		modeLabel.Text = "Weld: select 2nd"
	else
		modeLabel.Text = "Mode: " .. m
	end
end

tool.Equipped:Connect(function() modeLabel.Visible = true end)
tool.Unequipped:Connect(function() modeLabel.Visible = false; weldingFirst = nil; updateModeLabel() end)

mouse.Button2Down:Connect(function()
	modeIdx = modeIdx % #modes + 1
	weldingFirst = nil
	updateModeLabel()
end)

local function getHit()
	local cam = workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = { player.Character }
	return workspace:Raycast(ray.Origin, ray.Direction * 500, params)
end

tool.Activated:Connect(function()
	local hit = getHit()
	if not hit or not hit.Instance or not hit.Instance:IsA("BasePart") then
		if modes[modeIdx] == "Weld" and weldingFirst then
			weldingFirst = nil; updateModeLabel()
		end
		return
	end

	if modes[modeIdx] == "Remove" then
		events.RemoveProp:FireServer(hit.Instance)
	elseif modes[modeIdx] == "Weld" then
		if not weldingFirst then
			weldingFirst = hit.Instance
			updateModeLabel()
		else
			events.WeldProp:FireServer(weldingFirst, hit.Instance)
			weldingFirst = nil
			updateModeLabel()
		end
	end
end)
]]

local SPAWN_MENU_SRC = [[
local player = game:GetService("Players").LocalPlayer
local userInput = game:GetService("UserInputService")
local events = game:GetService("ReplicatedStorage"):WaitForChild("SandboxEvents")
local runService = game:GetService("RunService")

local PROPS = {
	{ Name = "Brick",		Shape = Enum.PartType.Block,	Size = Vector3.new(4,  2,  8),	Color = Color3.fromRGB(196, 40, 28) },
	{ Name = "Sphere",		Shape = Enum.PartType.Ball,		Size = Vector3.new(4,  4,  4),	Color = Color3.fromRGB(40, 118, 196) },
	{ Name = "Cylinder",	Shape = Enum.PartType.Cylinder,	Size = Vector3.new(4,  6,  4),	Color = Color3.fromRGB(212, 175, 55) },
	{ Name = "Wedge",		Shape = Enum.PartType.Wedge,	Size = Vector3.new(4,  4,  4),	Color = Color3.fromRGB(76, 175, 80) },
	{ Name = "Slab",		Shape = Enum.PartType.Block,	Size = Vector3.new(12, 1,  6),	Color = Color3.fromRGB(158, 158, 158) },
	{ Name = "Pillar",		Shape = Enum.PartType.Cylinder,	Size = Vector3.new(2,  10, 2),	Color = Color3.fromRGB(97, 97, 97) },
	{ Name = "Small Cube",	Shape = Enum.PartType.Block,	Size = Vector3.new(2,  2,  2),	Color = Color3.fromRGB(255, 152, 0) },
	{ Name = "Platform",	Shape = Enum.PartType.Block,	Size = Vector3.new(8,  1,  8),	Color = Color3.fromRGB(245, 245, 245) },
}

local menuOpen = false
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SpawnMenu"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 260, 0, 320)
frame.Position = UDim2.new(0.5, -130, 0.5, -160)
frame.BackgroundColor3 = Color3.fromRGB(22, 33, 62)
frame.BorderSizePixel = 0
frame.Parent = screenGui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.Text = "Spawn Menu  [Q]"
title.TextColor3 = Color3.fromRGB(233, 69, 96)
title.BackgroundColor3 = Color3.fromRGB(15, 25, 48)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.Parent = frame

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -8, 1, -38)
list.Position = UDim2.new(0, 4, 0, 34)
list.BackgroundTransparency = 1
list.ScrollBarThickness = 6
list.CanvasSize = UDim2.new(0, 0, 0, #PROPS * 42)
list.Parent = frame

for i, prop in ipairs(PROPS) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -8, 0, 36)
	btn.Position = UDim2.new(0, 4, 0, (i - 1) * 42)
	btn.BackgroundColor3 = Color3.fromRGB(15, 52, 96)
	btn.BorderSizePixel = 0
	btn.Text = prop.Name
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.Gotham
	btn.TextSize = 14
	btn.Parent = list

	local indicator = Instance.new("Frame")
	indicator.Size = UDim2.new(0, 4, 0, 36)
	indicator.BackgroundColor3 = prop.Color
	indicator.BorderSizePixel = 0
	indicator.Parent = btn

	btn.MouseButton1Click:Connect(function()
		local cam = workspace.CurrentCamera
		local spawnPos = cam.CFrame.Position + cam.CFrame.LookVector * 12
		events.SpawnProp:FireServer(i, CFrame.new(spawnPos))
	end)
end

userInput.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q then
		menuOpen = not menuOpen
		screenGui.Enabled = menuOpen
		if menuOpen then
			player:GetMouse().Icon = ""
		end
	end
end)

userInput.InputEnded:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.Q then return end
	if menuOpen and screenGui:FindFirstChild("Frame") then
	end
end)
]]

-- =====================================================================
-- Server setup
-- =====================================================================

local events = Instance.new("Folder")
events.Name = "SandboxEvents"
events.Parent = ReplicatedStorage

local spawnPropEvent = Instance.new("RemoteEvent")
spawnPropEvent.Name = "SpawnProp"; spawnPropEvent.Parent = events

local pickupPropEvent = Instance.new("RemoteEvent")
pickupPropEvent.Name = "PickupProp"; pickupPropEvent.Parent = events

local releasePropEvent = Instance.new("RemoteEvent")
releasePropEvent.Name = "ReleaseProp"; releasePropEvent.Parent = events

local freezePropEvent = Instance.new("RemoteEvent")
freezePropEvent.Name = "FreezeProp"; freezePropEvent.Parent = events

local physgunMoveEvent = Instance.new("RemoteEvent")
physgunMoveEvent.Name = "PhysgunMove"; physgunMoveEvent.Parent = events

local removePropEvent = Instance.new("RemoteEvent")
removePropEvent.Name = "RemoveProp"; removePropEvent.Parent = events

local weldPropEvent = Instance.new("RemoteEvent")
weldPropEvent.Name = "WeldProp"; weldPropEvent.Parent = events

-- === Tool creation ===

local function createTool(name, clientSrc)
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.Parent = ServerStorage
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = name

	local cs = Instance.new("LocalScript")
	cs.Name = "ClientLogic"
	cs.Source = clientSrc
	cs.Parent = tool

	return tool
end

createTool("Physgun", PHYSGUN_CLIENT_SRC)
createTool("Toolgun", TOOLGUN_CLIENT_SRC)

-- === Give tools on join ===

local function giveTools(player)
	local char = player.Character or player.CharacterAdded:Wait()
	task.wait(0.5)

	local physgun = ServerStorage:FindFirstChild("Physgun")
	if physgun then physgun:Clone().Parent = player.Backpack end

	local toolgun = ServerStorage:FindFirstChild("Toolgun")
	if toolgun then toolgun:Clone().Parent = player.Backpack end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		giveTools(player)
	end)
end)

for _, p in Players:GetPlayers() do
	task.spawn(giveTools, p)
end

-- === Prop definitions (server-authoritative) ===

local PROPS = {
	{ Name = "Brick",      Shape = Enum.PartType.Block,    Size = Vector3.new(4,  2,  8), Color = BrickColor.new("Bright red") },
	{ Name = "Sphere",     Shape = Enum.PartType.Ball,     Size = Vector3.new(4,  4,  4), Color = BrickColor.new("Bright blue") },
	{ Name = "Cylinder",   Shape = Enum.PartType.Cylinder, Size = Vector3.new(4,  6,  4), Color = BrickColor.new("Bright yellow") },
	{ Name = "Wedge",      Shape = Enum.PartType.Wedge,    Size = Vector3.new(4,  4,  4), Color = BrickColor.new("Bright green") },
	{ Name = "Slab",       Shape = Enum.PartType.Block,    Size = Vector3.new(12, 1,  6), Color = BrickColor.new("Medium stone grey") },
	{ Name = "Pillar",     Shape = Enum.PartType.Cylinder, Size = Vector3.new(2,  10, 2), Color = BrickColor.new("Dark stone grey") },
	{ Name = "Small Cube", Shape = Enum.PartType.Block,    Size = Vector3.new(2,  2,  2), Color = BrickColor.new("Bright orange") },
	{ Name = "Platform",   Shape = Enum.PartType.Block,    Size = Vector3.new(8,  1,  8), Color = BrickColor.new("White") },
}

-- === State ===

local heldProps = {}   -- player -> { part, mover, attachments, … }
local weldSel = {}     -- player -> first part for weld

-- === Spawn prop ===

spawnPropEvent.OnServerEvent:Connect(function(player, propIdx, cf)
	local def = PROPS[propIdx]
	if not def then return end

	local part = Instance.new("Part")
	part.Name = def.Name
	part.Shape = def.Shape
	part.Size = def.Size
	part.BrickColor = def.Color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = false
	part.CanCollide = true
	part.CFrame = cf

	CollectionService:AddTag(part, PROP_TAG)
	part.Parent = workspace
end)

-- === Physgun ===

pickupPropEvent.OnServerEvent:Connect(function(player, part)
	if heldProps[player] then return end
	if not part or not part:IsA("BasePart") then return end
	if part.Anchored then return end
	if not CollectionService:HasTag(part, PROP_TAG) then return end

	part.NetworkOwnership = Enum.NetworkOwnership.Manual

	local mover = Instance.new("Part")
	mover.Name = "PhysgunMover"
	mover.Anchored = true
	mover.Transparency = 1
	mover.CanCollide = false
	mover.Size = Vector3.new(0.5, 0.5, 0.5)
	mover.CFrame = part.CFrame
	mover.Parent = workspace

	local a0 = Instance.new("Attachment"); a0.Parent = part
	local a1 = Instance.new("Attachment"); a1.Parent = mover

	local align = Instance.new("AlignPosition")
	align.Parent = part
	align.Attachment0 = a0
	align.Attachment1 = a1
	align.MaxForce = 50000
	align.Responsiveness = 40
	align.RigidityEnabled = false

	heldProps[player] = { part = part, mover = mover, align = align, a0 = a0, a1 = a1 }
end)

releasePropEvent.OnServerEvent:Connect(function(player)
	local held = heldProps[player]
	if not held then return end

	held.align:Destroy(); held.a0:Destroy(); held.a1:Destroy()
	held.mover:Destroy()
	heldProps[player] = nil
end)

physgunMoveEvent.OnServerEvent:Connect(function(player, targetCF)
	local held = heldProps[player]
	if held then held.mover.CFrame = targetCF end
end)

freezePropEvent.OnServerEvent:Connect(function(player)
	local held = heldProps[player]
	if not held then return end
	held.part.Anchored = not held.part.Anchored
end)

-- === Toolgun: Remove ===

removePropEvent.OnServerEvent:Connect(function(player, part)
	if not part or not part:IsA("BasePart") then return end
	if not CollectionService:HasTag(part, PROP_TAG) then return end

	local held = heldProps[player]
	if held and held.part == part then
		held.align:Destroy(); held.a0:Destroy(); held.a1:Destroy()
		held.mover:Destroy()
		heldProps[player] = nil
	end

	part:Destroy()
end)

-- === Toolgun: Weld ===

weldPropEvent.OnServerEvent:Connect(function(player, partA, partB)
	if not partA or not partA:IsA("BasePart") then return end
	if not partB or not partB:IsA("BasePart") then return end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = partA
	weld.Part1 = partB
	weld.Parent = partA
end)

-- === Cleanup ===

Players.PlayerRemoving:Connect(function(player)
	local held = heldProps[player]
	if held then
		held.align:Destroy(); held.a0:Destroy(); held.a1:Destroy()
		held.mover:Destroy()
		heldProps[player] = nil
	end
	weldSel[player] = nil
end)
