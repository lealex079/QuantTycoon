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

### Taker promotion

Decided:

- A **good call** is choosing the action with the highest expected value (buy, sell or skip) given the bot's quote and the player's fair value.
- Promote to the next tier after **5 consecutive good calls**.
- A bad call resets the streak to 0.
- No demotion.

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

### Maker findings

Source: `sim/level34_maker.py`, 100,000 rounds per setup, seed 12345, half-spread h from 0.25 to 6. Level 3 has 4 noise traders around your fair value. Level 4 has 4 noise traders anchored to dice x 3.5 plus 3 informed bots.

- **Level 3 best half-spread is 1.75 for every hidden count.** Analytic: mean = 4h(1 - h/3.5), peak at h = 1.75 (mean 3.5). Hidden count only adds noise, not a different optimum, so Level 3 teaches spread vs fill rate only.
- **Level 4 best half-spread is about 2.25-3.25 (measured), and tight quotes lose money in 6 of 8 configs** (at h = 0.5 the mean P&L is negative in 3/2, 4/2, 4/3, 5/2, 5/3, 5/4). Within each dice count, best achievable mean P&L and mean/SD fall monotonically as hidden count rises, and the cost of a tight quote grows with it. The best h does not move monotonically with hidden count.
- **Level 4 "optimum is a point on the grid, not a plateau" is unconfirmed and possibly a lattice artifact.** The earlier 2 SE result (3/1, 4/1, 4/3, 5/4) used strict-inequality informed bots whose estimates sit on a discrete lattice. The fine-grid test below shows the strict curve is a sawtooth with cliffs at lattice values, so the sharp peak is at least partly an artifact. Level 3 (continuous tolerances, analytic peak at 1.75) is unaffected.
- **Level 4 lattice test** (`sim/level34_maker.py`, h 1.0 to 4.0 step 0.05, configs 4/1, 4/3, 5/4). Strict bots: fills drop by 0.2 to 0.9 in one 0.05 step at h = 1.5, 2.5, 3.5 (4 dice) and 2, 3, 4 (5 dice), exactly where estimate minus fair value equals h (strict `>` loses the ties). Mean P&L rises until just before each cliff, so the strict best h sits at 2.45 / 2.45 / 2.95 and is inflated (4/1 peak 6.25 vs about 4.86 smooth). New variant: each informed bot also needs edge > U(0, 0.75) per round (common random numbers). Curves have no discontinuities (fills change at most about 0.09 per step, slope kinks only). Roughness of the mean curve falls from 0.38 / 0.064 / 0.039 to 0.020 / 0.009 / 0.009. Best h moves to 2.1 / 2.6 / 2.75 on the fine grid, and 4/3 is nearly flat from 2.45 to 2.65. Level 4 best h on the 0.25 grid: 2.0 to 3.25 (was 2.25 to 3.25). Tight quotes still lose in the same 6 of 8 configs. Best mean P&L and mean/SD still fall with hidden count in every dice group. Best h with hidden count now falls for 3 and 5 dice and still not monotone for 4 dice (2.0, 2.75, 2.5). Plateau width under the new variant is not yet tested with the paired 2 SE method. **Decided:** the edge-threshold variant is the Level 4 bot model (each informed bot's threshold ~ U(0, 0.75) per bot per round). Use it for Level 4 tuning and scoring.
- **Scoring: percent of best expected P&L**, `score = max(0, mean P&L at h / mean P&L at best h)`, shown alongside raw P&L. Risk-adjusted P&L (mean/SD) is rejected: it moves the Level 3 optimum from 1.75 to 2.0 and costs about 2% of mean P&L.
- **Raw P&L is not comparable across levels.** Level 4 pays more at easy setups (e.g. about +4.86 at 4 dice/1 hidden with the decided threshold bots vs 3.5 at Level 3). Hypothesis, untested: noise traders anchored to the dice average produce one-sided flow when your fair value differs from it.

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
- Add an informed bot to the fair-value-given level? (Maker scoring is decided: percent of best expected P&L.)
- Which themes and formats to try first?
- 16+ or all-ages release?

## Later

Park new ideas here so they don't derail the current step.

-
