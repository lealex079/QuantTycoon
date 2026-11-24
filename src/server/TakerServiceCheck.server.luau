--!strict
-- TEMPORARY: exercises TakerService core with fake keys. Delete once real tests exist.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TakerService = require(script.Parent:WaitForChild("TakerService"))
local TakerMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TakerMath"))

local function report(name: string, ok: boolean)
	print((if ok then "PASS " else "FAIL ") .. name)
end

local function sumOf(values: { number }): number
	local total = 0
	for _, v in values do
		total += v
	end
	return total
end

-- the best action as a client could compute it from visible info only
local function bestFor(visible: TakerService.Visible): TakerMath.Action
	local fair = TakerMath.fairValue(sumOf(visible.seen), visible.hiddenCount)
	return TakerMath.bestAction(fair, visible.bid, visible.ask)
end

-- 1. valid round
do
	local v = TakerService.startRound(9001)
	local s = TakerService.submitAction(9001, v.roundId, bestFor(v))
	local r = s.result
	report("valid round", s.ok and r ~= nil and r.goodCall and #r.hidden == v.hiddenCount
		and r.trueTotal == sumOf(v.seen) + sumOf(r.hidden) and v.tier == 1)
end

-- 2. invalid action strings
do
	local v = TakerService.startRound(9002)
	local ok = true
	local badActions: { any } = { "BUY", "hold", "", 5, true }
	for _, bad in badActions do
		ok = ok and not TakerService.submitAction(9002, v.roundId, bad).ok
	end
	-- round stays answerable afterwards
	ok = ok and TakerService.submitAction(9002, v.roundId, "skip").ok
	report("invalid action", ok)
end

-- 3. wrong roundId
do
	local v = TakerService.startRound(9003)
	local ok = not TakerService.submitAction(9003, v.roundId + 1, "skip").ok
	ok = ok and not TakerService.submitAction(9003, "x", "skip").ok
	ok = ok and not TakerService.submitAction(9999, 1, "skip").ok -- unknown player
	report("wrong roundId", ok)
end

-- 4. double submit
do
	local v = TakerService.startRound(9004)
	local first = TakerService.submitAction(9004, v.roundId, "skip")
	local second = TakerService.submitAction(9004, v.roundId, "skip")
	report("double submit", first.ok and not second.ok and second.reason == "already answered")
end

-- 5. promotion after 5 good calls, and a bad call resets the streak
do
	local key = 9005
	local promoted = false
	local streakOk = true
	for i = 1, 5 do
		local v = TakerService.startRound(key)
		local s = TakerService.submitAction(key, v.roundId, bestFor(v))
		local r = s.result
		if not r then
			streakOk = false
			break
		end
		streakOk = streakOk and r.streak == (if i == 5 then 0 else i)
		promoted = r.newTier == 2
	end
	local nextRound = TakerService.startRound(key)
	report("promotion after 5 good calls", streakOk and promoted and nextRound.tier == 2)

	-- bad call resets
	local v = TakerService.startRound(key)
	local best = bestFor(v)
	TakerService.submitAction(key, v.roundId, best)
	local v2 = TakerService.startRound(key)
	local best2 = bestFor(v2)
	local bad: TakerMath.Action = if best2 == "skip" then "buy" else "skip"
	local s = TakerService.submitAction(key, v2.roundId, bad)
	local r = s.result
	report("bad call resets streak", r ~= nil and not r.goodCall and r.streak == 0 and r.newTier == nil)
end

-- 6. startRound exposes no hidden dice or true total
do
	local allowed = { roundId = true, tier = true, seen = true, hiddenCount = true, bid = true, ask = true }
	local clean = true
	for _ = 1, 50 do
		local v = TakerService.startRound(9006)
		for k in v :: any do
			clean = clean and allowed[k] == true
		end
	end
	report("startRound has no hidden fields", clean)
end

-- 7. requestRound resends the open round (not re-rolled), starts a new one once answered
do
	local first = TakerService.requestRound(9007)
	local again = TakerService.requestRound(9007)
	local same = again.roundId == first.roundId and again.tier == first.tier
		and again.hiddenCount == first.hiddenCount and again.bid == first.bid and again.ask == first.ask
		and table.concat(again.seen, ",") == table.concat(first.seen, ",")
	-- the resend is a copy: tampering with it must not change the stored round
	table.insert(again.seen, 99)
	local third = TakerService.requestRound(9007)
	same = same and #third.seen == #first.seen
	local settled = TakerService.submitAction(9007, first.roundId, "skip")
	local following = TakerService.requestRound(9007)
	local nextAgain = TakerService.requestRound(9007)
	report("requestRound resends open round", same and settled.ok and following.roundId == first.roundId + 1
		and nextAgain.roundId == following.roundId)
end

-- 8. session P&L accumulates across rounds on the server
do
	local expected = 0
	local last = 0
	for _ = 1, 3 do
		local v = TakerService.requestRound(9008)
		local r = TakerService.submitAction(9008, v.roundId, "buy").result
		if r then
			expected += r.pnl
			last = r.sessionPnl
		end
	end
	report("sessionPnl accumulates", math.abs(last - expected) < 1e-9)
end

TakerService.removePlayer(9007)
TakerService.removePlayer(9008)
TakerService.removePlayer(9001)
TakerService.removePlayer(9002)
TakerService.removePlayer(9003)
TakerService.removePlayer(9004)
TakerService.removePlayer(9005)
TakerService.removePlayer(9006)
