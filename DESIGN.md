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

- Score Maker by risk-adjusted P&L, or add an informed bot to the fair-value-given level?
- Which themes and formats to try first?
- 16+ or all-ages release?

## Later

Park new ideas here so they don't derail the current step.

-
