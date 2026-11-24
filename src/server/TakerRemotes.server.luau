--!strict
-- Thin network wrapper around TakerService. All game logic lives in the service.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TakerService = require(script.Parent:WaitForChild("TakerService"))

local MIN_SUBMIT_INTERVAL = 0.25 -- seconds between SubmitAction calls per player

local function makeRemote(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

local roundStarted = makeRemote("RoundStarted")
local submitAction = makeRemote("SubmitAction")
local roundResult = makeRemote("RoundResult")
local requestRound = makeRemote("RequestRound")

local lastSubmit: { [number]: number } = {}

-- The client asks for a round: it gets its open one again, or a fresh one if none is open.
requestRound.OnServerEvent:Connect(function(player: Player)
	roundStarted:FireClient(player, TakerService.requestRound(player.UserId))
end)

local function onPlayerRemoving(player: Player)
	TakerService.removePlayer(player.UserId)
	lastSubmit[player.UserId] = nil
end

submitAction.OnServerEvent:Connect(function(player: Player, roundId: unknown, action: unknown)
	if typeof(roundId) ~= "number" or typeof(action) ~= "string" then
		return
	end
	local now = os.clock()
	local last = lastSubmit[player.UserId]
	if last and now - last < MIN_SUBMIT_INTERVAL then
		return
	end
	lastSubmit[player.UserId] = now

	local submitted = TakerService.submitAction(player.UserId, roundId, action)
	roundResult:FireClient(player, submitted)
end)

Players.PlayerRemoving:Connect(onPlayerRemoving)
