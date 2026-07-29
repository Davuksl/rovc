-- RovC Voice Chat — Client script (place in StarterPlayerScripts)

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for the RemoteEvent created by the server script
local sessionEvent = ReplicatedStorage:WaitForChild("VoiceChatSessionEvent")

-- Build GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VoiceChatGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 320, 0, 180)
frame.Position = UDim2.new(0.5, -160, 0, 40)
frame.BackgroundColor3 = Color3.fromRGB(22, 33, 62)
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.Parent = screenGui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.Text = "Voice Chat"
title.TextColor3 = Color3.fromRGB(233, 69, 96)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.Parent = frame

local instruction = Instance.new("TextLabel")
instruction.Size = UDim2.new(1, -20, 0, 36)
instruction.Position = UDim2.new(0, 10, 0, 32)
instruction.Text = "Go to the voice chat website and enter your code:"
instruction.TextColor3 = Color3.fromRGB(180, 180, 180)
instruction.BackgroundTransparency = 1
instruction.Font = Enum.Font.Gotham
instruction.TextSize = 13
instruction.TextWrapped = true
instruction.Parent = frame

local codeBox = Instance.new("TextBox")
codeBox.Size = UDim2.new(1, -40, 0, 36)
codeBox.Position = UDim2.new(0, 20, 0, 74)
codeBox.BackgroundColor3 = Color3.fromRGB(15, 52, 96)
codeBox.TextColor3 = Color3.fromRGB(255, 255, 255)
codeBox.Font = Enum.Font.Code
codeBox.TextSize = 22
codeBox.Text = "---"
codeBox.PlaceholderText = "Waiting for code..."
codeBox.Selectable = true
codeBox.TextXAlignment = Enum.TextXAlignment.Center
codeBox.ClearTextOnFocus = false
codeBox.Parent = frame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 24)
statusLabel.Position = UDim2.new(0, 10, 0, 118)
statusLabel.Text = "Status: Waiting for server..."
statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 12
statusLabel.Parent = frame

local instruction2 = Instance.new("TextLabel")
instruction2.Size = UDim2.new(1, -20, 0, 24)
instruction2.Position = UDim2.new(0, 10, 0, 144)
instruction2.Text = "Open web browser and navigate to the voice URL"
instruction2.TextColor3 = Color3.fromRGB(120, 120, 150)
instruction2.BackgroundTransparency = 1
instruction2.Font = Enum.Font.Gotham
instruction2.TextSize = 11
instruction2.Parent = frame

-- Receive sessionId from server
sessionEvent.OnClientEvent:Connect(function(sessionId)
	codeBox.Text = sessionId
	statusLabel.Text = "Status: Code ready! Use it on the voice website."
	statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
end)
