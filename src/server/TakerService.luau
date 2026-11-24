--!strict
-- Server-side Taker level. The core takes a numeric key (UserId), not a Player.
-- Hidden dice and the true total stay in server memory until settlement.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelConfig = require(Shared:WaitForChild("LevelConfig"))
local TakerMath = require(Shared:WaitForChild("TakerMath"))

export type Visible = {
	roundId: number,
	tier: number,
	seen: { number },
	hiddenCount: number,
	bid: number,
	ask: number,
}

export type Settlement = {
	roundId: number,
	trueTotal: number,
	hidden: { number },
	action: TakerMath.Action,
	pnl: number,
	edge: number, -- expected edge of the action taken, versus fair value
	bestAction: TakerMath.Action,
	goodCall: boolean,
	streak: number,
	newTier: number?, -- set only when this call promoted the player
}

export type SubmitResult = { ok: boolean, reason: string?, result: Settlement? }

type Round = {
	id: number,
	seen: { number },
	hidden: { number },
	bid: number,
	ask: number,
	answered: boolean,
}

type PlayerState = {
	tier: number,
	streak: number,
	nextRoundId: number,
	round: Round?,
}

local rng = Random.new() -- unseeded, server-only, never exposed
-- TakerMath wants an object with NextNumber(self, min, max); Random's own signature has optional args
local mathRng: TakerMath.Rng = {
	NextNumber = function(_self: any, min: number, max: number): number
		return rng:NextNumber(min, max)
	end,
}
local players: { [number]: PlayerState } = {}

local TakerService = {}

local function getState(key: number): PlayerState
	local state = players[key]
	if not state then
		state = { tier = 1, streak = 0, nextRoundId = 1, round = nil }
		players[key] = state
	end
	return state
end

local function sum(values: { number }): number
	local total = 0
	for _, v in values do
		total += v
	end
	return total
end

function TakerService.startRound(key: number): Visible
	local state = getState(key)
	local tierConfig = LevelConfig.tiers[state.tier]

	local hiddenCount = rng:NextInteger(tierConfig.hiddenMin, tierConfig.hiddenMax)
	local seen: { number } = {}
	local hidden: { number } = {}
	for i = 1, tierConfig.dice do
		local roll = rng:NextInteger(1, LevelConfig.sides)
		if i <= tierConfig.dice - hiddenCount then
			table.insert(seen, roll)
		else
			table.insert(hidden, roll)
		end
	end
	local quote = TakerMath.makeQuote(tierConfig.dice, mathRng)

	local id = state.nextRoundId
	state.nextRoundId += 1
	state.round = { id = id, seen = seen, hidden = hidden, bid = quote.bid, ask = quote.ask, answered = false }

	-- copy seen so the client-facing table shares nothing with stored state
	return {
		roundId = id,
		tier = state.tier,
		seen = table.clone(seen),
		hiddenCount = hiddenCount,
		bid = quote.bid,
		ask = quote.ask,
	}
end

local function reject(reason: string): SubmitResult
	return { ok = false, reason = reason, result = nil }
end

function TakerService.submitAction(key: number, roundId: any, action: any): SubmitResult
	if action ~= "buy" and action ~= "sell" and action ~= "skip" then
		return reject("invalid action")
	end
	local state = players[key]
	local round = if state then state.round else nil
	if not state or not round then
		return reject("no open round")
	end
	if typeof(roundId) ~= "number" or roundId ~= round.id then
		return reject("wrong round")
	end
	if round.answered then
		return reject("already answered")
	end
	round.answered = true

	local taken: TakerMath.Action = action
	local hiddenCount = #round.hidden
	local fair = TakerMath.fairValue(sum(round.seen), hiddenCount)
	local trueTotal = sum(round.seen) + sum(round.hidden)
	local best: TakerMath.Action = TakerMath.bestAction(fair, round.bid, round.ask)
	local goodCall = taken == best

	local newTier: number? = nil
	if goodCall then
		state.streak += 1
		local promo = LevelConfig.promotion
		if state.streak >= promo.goodCalls and LevelConfig.tiers[state.tier + 1] then
			state.tier += 1
			state.streak = 0
			newTier = state.tier
		end
	else
		state.streak = 0
	end

	return {
		ok = true,
		reason = nil,
		result = {
			roundId = round.id,
			trueTotal = trueTotal,
			hidden = table.clone(round.hidden),
			action = taken,
			pnl = TakerMath.settle(taken, round.bid, round.ask, trueTotal),
			edge = TakerMath.edge(taken, fair, round.bid, round.ask),
			bestAction = best,
			goodCall = goodCall,
			streak = state.streak,
			newTier = newTier,
		},
	}
end

function TakerService.removePlayer(key: number)
	players[key] = nil
end

return TakerService
