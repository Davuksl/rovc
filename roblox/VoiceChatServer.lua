-- RovC Voice Chat — Server script (place in ServerScriptService)
-- Requires HttpService.HttpEnabled = true in Game Settings

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CONFIG = {
	BackendUrl = "https://YOUR-APP.onrender.com",  -- CHANGE THIS
	UpdateInterval = 0.1,  -- 100 ms between position batches
}

local sessions = {}  -- [Player] -> sessionId

-- Create a single RemoteEvent for sending sessionId to clients
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sessionEvent = ReplicatedStorage:FindFirstChild("VoiceChatSessionEvent")
if not sessionEvent then
	sessionEvent = Instance.new("RemoteEvent")
	sessionEvent.Name = "VoiceChatSessionEvent"
	sessionEvent.Parent = ReplicatedStorage
end

local function registerSession(player)
	local sessionId = HttpService:GenerateGUID(false)
	local body = HttpService:JSONEncode({
		sessionId = sessionId,
		robloxUserId = player.UserId,
		roomId = game.JobId,
	})

	local ok, resp = pcall(function()
		return HttpService:PostAsync(
			CONFIG.BackendUrl .. "/api/session/register",
			body,
			Enum.HttpContentType.ApplicationJson,
			false
		)
	end)

	if ok then
		sessions[player] = sessionId
		sessionEvent:FireClient(player, sessionId)
		print("[VoiceChat] Registered", player.Name, sessionId)
	else
		warn("[VoiceChat] Register failed for", player.Name, resp)
	end
end

local function unregisterSession(player)
	local sessionId = sessions[player]
	if not sessionId then return end

	pcall(function()
		HttpService:PostAsync(
			CONFIG.BackendUrl .. "/api/session/unregister",
			HttpService:JSONEncode({ sessionId = sessionId }),
			Enum.HttpContentType.ApplicationJson,
			false
		)
	end)

	sessions[player] = nil
	print("[VoiceChat] Unregistered", player.Name)
end

-- Register each player on join
Players.PlayerAdded:Connect(function(player)
	task.wait(1)  -- let character fully load
	registerSession(player)
end)

-- Unregister on leave
Players.PlayerRemoving:Connect(function(player)
	unregisterSession(player)
end)

-- Position batching loop (every ~100 ms)
local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed = elapsed + dt
	if elapsed < CONFIG.UpdateInterval then return end
	elapsed = 0

	local positions = {}
	for player, sessionId in pairs(sessions) do
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			local hrp = char.HumanoidRootPart
			local cf = hrp.CFrame
			local lv = cf.LookVector
			local rv = cf.RightVector
			local uv = cf.UpVector

			table.insert(positions, {
				sessionId = sessionId,
				x = cf.X, y = cf.Y, z = cf.Z,
				lookX = lv.X, lookY = lv.Y, lookZ = lv.Z,
				rightX = rv.X, rightY = rv.Y, rightZ = rv.Z,
				upX = uv.X, upY = uv.Y, upZ = uv.Z,
			})
		end
	end

	if #positions > 0 then
		pcall(function()
			HttpService:PostAsync(
				CONFIG.BackendUrl .. "/api/positions/update",
				HttpService:JSONEncode({ roomId = game.JobId, positions = positions }),
				Enum.HttpContentType.ApplicationJson,
				false
			)
		end)
	end
end)
