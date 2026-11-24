# Quant Tycoon: Design

## Goal

Learn and show a shipped project first, fun second, revenue only as upside.

## Core engine idea

- **Hidden value:** each round has a value the player can't see directly.
- **Partial information:** the player sees some of the inputs, not all of them.
- **Quotes:** prices are quoted (bid/ask), and trades happen against those quotes.
- **Bots:** two kinds.
  - *Informed* bots know something about the hidden value and trade on it.
  - *Noise* bots trade at random, with no information.

## Starting levels (dice-based)

1. **Hidden Value:** estimate the total of the dice when some are hidden.
2. **Taker:** accept or reject a quote from a bot.
3. **Maker with fair value given:** post quotes around a fair value the game tells you.
4. **Maker with informed bots:** post quotes while some bots know more than you.

### Taker tiers

| Tier | Dice | Hidden |
|------|------|--------|
| 1 | 3 | 1 or 2 |
| 2 | 4 | 1 to 3 |
| 3 | 5 | 2 to 4 |

The hidden count re-rolls each round. Tier 2 and 3 ranges are a first guess to tune in the Python sim.

### Fair value

`fair value = seen total + hidden dice x 3.5`

### Hidden Value scoring

Decision: score each guess continuously, scaled by the uncertainty of the hidden dice, instead of fixed +/-1 and +/-2 bands.

- `error SD = 1.708 x sqrt(hidden dice)`
- `score = max(0, 1 - |true - guess| / (2 x error SD))`
- Full score at zero error, zero score at 2 SD or more. The formula is a starting point to tune.

Why: with an odd number of hidden dice the best guess is a half-number (e.g. 10.5), so fixed bands give inconsistent hit rates (25% within +/-1 at 3 hidden versus 32.9% at 4 hidden). Scaling by SD makes difficulty read the same at every hidden count.

### Level 1 sim results

Source: `sim/level1_hidden_value.py`, 100,000 rounds per setup, seed 12345.

Error SD by hidden count (matches `1.708 x sqrt(hidden)`):

| Hidden | Error SD |
|--------|----------|
| 1 | 1.71 |
| 2 | 2.41-2.42 |
| 3 | 2.96 |
| 4 | 3.42 |

Share of rounds within +/-1 and +/-2 of the true total, using the best guess:

| Tier | Dice | Hidden | Within +/-1 | Within +/-2 |
|------|------|--------|-------------|-------------|
| 1 | 3 | 1 | 33.4% | 66.6% |
| 1 | 3 | 2 | 44.5% | 66.7% |
| 2 | 4 | 1 | 33.3% | 66.5% |
| 2 | 4 | 2 | 44.3% | 66.4% |
| 2 | 4 | 3 | 25.0% | 48.3% |
| 3 | 5 | 2 | 44.5% | 66.7% |
| 3 | 5 | 3 | 25.0% | 48.1% |
| 3 | 5 | 4 | 32.9% | 52.0% |

These confirm the fair value formula (seen total + hidden x 3.5) as the best guess. Error depends only on the hidden count, not the number of dice.

### Level 2 sim results

Source: `sim/level2_taker.py`, 100,000 rounds per setup, seed 12345. The bot quotes around dice x 3.5 plus a continuous shift uniform in [-2, +2], with a spread of 2. Seen = dice - hidden. Cells are mean P&L per round (SD in the sim output). Win% = share of all rounds where the edge strategy has positive P&L (skips count as not winning).

| Tier | Dice | Hidden | Seen | Buy | Sell | Edge | Trade% | Win% |
|------|------|--------|------|-----|------|------|--------|------|
| 1 | 3 | 1 | 2 | -1.00 | -1.00 | +1.32 | 72.2% | 55.7% |
| 1 | 3 | 2 | 1 | -1.01 | -1.00 | +0.88 | 66.6% | 46.3% |
| 2 | 4 | 1 | 3 | -0.99 | -1.01 | +1.70 | 76.5% | 61.2% |
| 2 | 4 | 2 | 2 | -1.03 | -0.97 | +1.34 | 72.5% | 53.6% |
| 2 | 4 | 3 | 1 | -1.00 | -1.00 | +0.88 | 66.5% | 43.4% |
| 3 | 5 | 2 | 3 | -1.00 | -1.00 | +1.68 | 76.2% | 58.8% |
| 3 | 5 | 3 | 2 | -1.01 | -0.99 | +1.34 | 72.2% | 50.9% |
| 3 | 5 | 4 | 1 | -0.99 | -1.01 | +0.87 | 66.7% | 43.0% |

Findings:

- Always buy or always sell loses about the half-spread (1.0 per round) in every setup. Without information, trading against the quote has no edge.
- The edge strategy's mean P&L depends on dice seen, not total dice or hidden count: about +0.87 at 1 seen, +1.34 at 2, +1.68 at 3, whatever the tier.
- Single-round P&L is dominated by luck. Edge SD (2.0 to 3.0) is larger than its mean (0.9 to 1.7), and the edge strategy has positive P&L in only 43% to 61% of rounds. The game should show a decision-quality score alongside P&L.

## Candidate later concepts (not decided)

- Calibration
- Sizing
- Diversification
- Hedging
- Stat arb
- Winner's curse
- Overfitting
- Execution

## Candidate themes (not decided)

- Trading-card shop
- Detective / treasure hunt
- Farm
- Merchant caravan
- Two-town price gap
- Auction house

## Candidate formats (not decided)

- Daily puzzle
- Arcade speed mode
- Campaign
- Sandbox

## Open questions

- Taker tiers overlap by error SD (Tier 1 up to 2.41, Tier 2 up to 2.96, Tier 3 from 2.41 to 3.42). Narrow Tier 3 to 3-4 hidden for cleaner difficulty steps? Keeping the current ranges for now.
- Define taker tiers by dice seen as well as hidden count? Edge depends on seen, so tiers with the same hidden count can differ in how much the player can win.
- Score Maker by risk-adjusted P&L, or add an informed bot to the fair-value-given level?
- Which themes and formats to try first?
- 16+ or all-ages release?

## Later

Park new ideas here so they don't derail the current step.

-
