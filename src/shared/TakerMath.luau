--!strict
-- Pure Taker math. No Roblox services; the only input from outside is an rng
-- object with NextNumber(min, max). Semantics mirror sim/level2_taker.py.
local LevelConfig = require(script.Parent.LevelConfig)

export type Action = "buy" | "sell" | "skip"
export type Quote = { bid: number, ask: number }
export type Rng = { NextNumber: (any, number, number) -> number }

local TakerMath = {}

local function meanSide(): number
	return (LevelConfig.sides + 1) / 2
end

-- seen total + hidden x mean side
function TakerMath.fairValue(seenSum: number, hiddenCount: number): number
	return seenSum + hiddenCount * meanSide()
end

-- Round to the nearest step, ties half up (same rule as sim/level2_taker.py). step <= 0 means no rounding.
local function roundToStep(x: number, step: number): number
	if step <= 0 then
		return x
	end
	return math.floor(x / step + 0.5) * step
end

-- mid = round(dice x mean side + U(-midNoiseMax, +midNoiseMax), midRounding); bid/ask = mid -/+ spread / 2
function TakerMath.makeQuote(diceCount: number, rng: Rng): Quote
	local level2 = LevelConfig.level2
	local shift = rng:NextNumber(-level2.midNoiseMax, level2.midNoiseMax)
	local mid = roundToStep(diceCount * meanSide() + shift, level2.midRounding)
	return { bid = mid - level2.spread / 2, ask = mid + level2.spread / 2 }
end

-- Expected edge of an action versus the quote, given fair value.
-- buy: fair - ask, sell: bid - fair, skip: 0
function TakerMath.edge(action: Action, fair: number, bid: number, ask: number): number
	if action == "buy" then
		return fair - ask
	elseif action == "sell" then
		return bid - fair
	end
	return 0
end

-- Highest expected-value action. Ties go to skip (buy only if fair > ask, sell only if fair < bid).
function TakerMath.bestAction(fair: number, bid: number, ask: number): Action
	if fair > ask and fair - ask >= bid - fair then
		return "buy"
	elseif fair < bid then
		return "sell"
	end
	return "skip"
end

local EDGE_EPSILON = 1e-9

-- A good call is any action whose expected edge equals the best edge (within a tiny epsilon).
-- Buying or selling at a zero-edge quote ties with skipping, so it counts.
function TakerMath.isGoodCall(action: Action, fair: number, bid: number, ask: number): boolean
	local best: Action = TakerMath.bestAction(fair, bid, ask)
	return TakerMath.edge(action, fair, bid, ask) >= TakerMath.edge(best, fair, bid, ask) - EDGE_EPSILON
end

-- Realized P&L against the true total. buy: true - ask, sell: bid - true, skip: 0
function TakerMath.settle(action: Action, bid: number, ask: number, trueTotal: number): number
	if action == "buy" then
		return trueTotal - ask
	elseif action == "sell" then
		return bid - trueTotal
	end
	return 0
end

return TakerMath
