--!strict
-- Every player-facing string for the Taker screen. Change wording here only.
local UiText = {}

UiText.loading = "Loading round..."
UiText.hiddenTile = "?"
UiText.totalHidden = "Total: ?"
UiText.bidCaption = "Bot bids (you sell)"
UiText.askCaption = "Bot asks (you buy)"
UiText.skip = "Skip"
UiText.skipped = "Skip"
UiText.continue = "Continue"
UiText.bestMove = "Best move!"
UiText.topTierStreak = "Top tier reached"

local function round2(value: number): number
	return math.round(value * 100) / 100
end

function UiText.number(value: number): string
	return string.format("%.2f", round2(value))
end

-- "+1.25", "-0.50", "0.00"
function UiText.signed(value: number): string
	local rounded = round2(value)
	if rounded == 0 then
		return "0.00"
	end
	return string.format("%+.2f", rounded)
end

function UiText.tier(tier: number): string
	return string.format("Tier %d", tier)
end

function UiText.buy(ask: number): string
	return "Buy at " .. UiText.number(ask)
end

function UiText.sell(bid: number): string
	return "Sell at " .. UiText.number(bid)
end

function UiText.total(total: number): string
	return string.format("Total: %d", total)
end

function UiText.youChose(actionText: string): string
	return "You chose: " .. actionText
end

function UiText.pnl(pnl: number): string
	return "P&L " .. UiText.signed(pnl)
end

function UiText.notBest(bestText: string): string
	return "Not the best move. Best was: " .. bestText
end

function UiText.streak(streak: number, target: number, nextTier: number): string
	return string.format("Streak to %s: %d/%d", UiText.tier(nextTier), streak, target)
end

function UiText.topStreak(streak: number): string
	return string.format("%s. Streak: %d", UiText.topTierStreak, streak)
end

function UiText.promoted(tier: number): string
	return string.format("Promoted to %s!", UiText.tier(tier))
end

function UiText.session(pnl: number): string
	return "Session P&L " .. UiText.signed(pnl)
end

return UiText
