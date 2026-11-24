"""Level 2 (Taker) simulation.

n dice, some hidden. A bot quotes a bid/ask centered on a mid = n x 3.5 plus a random
continuous shift uniform in [-2, +2], with a per-tier full spread (TIER_SPREAD, 1.0 for all
tiers: bid = mid - 0.5, ask = mid + 0.5).
The mid is then rounded to the nearest MID_ROUNDING (0.5) before the spread is applied, so
quotes end in .0 or .5. Ties on a .25/.75 boundary round half up: floor(mid / step + 0.5) * step.
The sim runs both the continuous and the rounded quote on the same rolls and shifts.
The player knows fair value = seen total + hidden x 3.5 and can buy at the ask,
sell at the bid, or skip. P&L is settled against the true total:
    buy:  true - ask      sell: bid - true      skip: 0

Strategies: always buy, always sell, always skip, and edge
(buy if fair > ask, sell if fair < bid, otherwise skip).

Setups come from the taker tiers in DESIGN.md. Run: python3 sim/level2_taker.py
Pass --spread 2.0 to force one full spread on every tier (the old setting, for comparison).
"""

import argparse

import numpy as np

SEED = 12345
ROUNDS = 100_000
SIDES = 6
MEAN_DIE = (SIDES + 1) / 2  # 3.5
SHIFT_MAX = 2
# Full spread (ask - bid) per tier. Exported to LevelConfig tiers[].spread. Decided 1.0 (was 2.0).
TIER_SPREAD = {1: 1.0, 2: 1.0, 3: 1.0}
MID_ROUNDING = 0.5  # 0 = continuous mid


def round_mid(mid: np.ndarray, step: float) -> np.ndarray:
    if step <= 0:
        return mid
    return np.floor(mid / step + 0.5) * step

# (tier, dice, hidden counts) from DESIGN.md taker tiers
TIERS = [
    (1, 3, [1, 2]),
    (2, 4, [1, 2, 3]),
    (3, 5, [2, 3, 4]),
]


def settle(true_total, fair, center: np.ndarray, rounds: int, spread: float) -> dict:
    bid = center - spread / 2
    ask = center + spread / 2
    buy_pnl = true_total - ask
    sell_pnl = bid - true_total
    do_buy = fair > ask
    do_sell = fair < bid
    edge_pnl = np.where(do_buy, buy_pnl, np.where(do_sell, sell_pnl, 0.0))

    pnls = {
        "buy": buy_pnl,
        "sell": sell_pnl,
        "skip": np.zeros(rounds),
        "edge": edge_pnl,
    }
    out = {name: (float(p.mean()), float(p.std())) for name, p in pnls.items()}
    out["trade_rate"] = float((do_buy | do_sell).mean())
    out["edge_win"] = float((edge_pnl > 0).mean())
    return out


def simulate(rng: np.random.Generator, dice: int, hidden: int, rounds: int, spread: float) -> dict:
    """Returns {"continuous": stats, "rounded": stats}, both on the same rolls and shifts."""
    rolls = rng.integers(1, SIDES + 1, size=(rounds, dice))
    true_total = rolls.sum(axis=1)
    fair = rolls[:, hidden:].sum(axis=1) + hidden * MEAN_DIE

    shift = rng.uniform(-SHIFT_MAX, SHIFT_MAX, size=rounds)
    center = dice * MEAN_DIE + shift
    return {
        "continuous": settle(true_total, fair, center, rounds, spread),
        "rounded": settle(true_total, fair, round_mid(center, MID_ROUNDING), rounds, spread),
    }


def main(spread_override: float | None = None) -> None:
    rng = np.random.default_rng(SEED)
    print(f"Taker sim: {ROUNDS:,} rounds per setup, seed {SEED}")
    spreads = {t: (spread_override if spread_override is not None else TIER_SPREAD[t]) for t in TIER_SPREAD}
    spread_text = ", ".join(f"tier {t} {v:g}" for t, v in spreads.items())
    print(f"Quote: mid = dice x 3.5 + continuous shift uniform in [-{SHIFT_MAX}, +{SHIFT_MAX}], full spread {spread_text}.")
    print(f"'rounded' snaps the mid to the nearest {MID_ROUNDING:g} (half up) before the spread; 'continuous' does not.")
    print("Each cell is mean / SD of P&L per round. Trade% = share of rounds edge trades.")
    print("Seen = dice - hidden. Win% = share of all rounds where edge P&L > 0 (skips count as not winning).\n")

    cols = ["buy", "sell", "skip", "edge"]
    header = f"{'Tier':>4} {'Dice':>4} {'Hid':>3} {'Seen':>4} | " + " | ".join(f"{c:^15}" for c in cols) + f" | {'Trade%':>7} | {'Win%':>6}"
    by_seen: dict = {"continuous": {}, "rounded": {}}
    results = {}
    for tier, dice, hidden_options in TIERS:
        for hidden in hidden_options:
            results[(tier, dice, hidden)] = simulate(rng, dice, hidden, ROUNDS, spreads[tier])
    for mode in ["continuous", "rounded"]:
        print(f"=== {mode} ===")
        print(header)
        print("-" * len(header))
        for (tier, dice, hidden), both in results.items():
            r = both[mode]
            cells = " | ".join(f"{r[c][0]:>+7.3f} /{r[c][1]:>5.2f}" for c in cols)
            print(f"{tier:>4} {dice:>4} {hidden:>3} {dice - hidden:>4} | {cells} | {r['trade_rate']:>6.1%} | {r['edge_win']:>5.1%}")
            by_seen[mode].setdefault(dice - hidden, []).append(r)
        print()

    print("=== Averaged over setups, by dice seen (equal weight per setup) ===")
    print(f"{'Seen':>4} | {'mode':^10} | {'buy':>7} | {'sell':>7} | {'edge':>7} | {'trade%':>7}")
    for seen in sorted(by_seen["continuous"]):
        for mode in ["continuous", "rounded"]:
            rs = by_seen[mode][seen]
            m = lambda key: float(np.mean([x[key][0] if isinstance(x[key], tuple) else x[key] for x in rs]))
            print(f"{seen:>4} | {mode:^10} | {m('buy'):>+7.3f} | {m('sell'):>+7.3f} | {m('edge'):>+7.3f} | {m('trade_rate'):>6.1%}")
    print("\n=== Overall means across all 8 setups ===")
    for mode in ["continuous", "rounded"]:
        rs = [both[mode] for both in results.values()]
        print(f"{mode:>10}: always-buy {np.mean([x['buy'][0] for x in rs]):+.3f}, always-sell {np.mean([x['sell'][0] for x in rs]):+.3f}")
    best_action_report()


BEST_ACTION_SPREADS = [2.0, 1.5, 1.0]


def best_actions(fair: np.ndarray, center: np.ndarray, spread: float) -> np.ndarray:
    """0 = buy, 1 = sell, 2 = skip. Same rule as TakerMath.bestAction (ties go to skip)."""
    bid = center - spread / 2
    ask = center + spread / 2
    buy = (fair > ask) & (fair - ask >= bid - fair)
    sell = ~buy & (fair < bid)
    return np.where(buy, 0, np.where(sell, 1, 2))


def run_lengths(is_skip: np.ndarray) -> np.ndarray:
    """Lengths of maximal runs of consecutive True values, in round order."""
    padded = np.concatenate(([0], is_skip.astype(np.int8), [0]))
    edges = np.flatnonzero(np.diff(padded))
    return edges[1::2] - edges[0::2]


def best_action_report() -> None:
    """Best-action shares and consecutive-skip runs per tier, for several spreads.

    Each round draws its hidden count uniformly from the tier's range, as the game does. Uses its own
    RNG (same seed) so the tables above are unchanged. Rounds are in play order, so runs are real
    streaks of skips. All spreads share the same rolls, hidden counts and shifts.
    """
    rng = np.random.default_rng(SEED)
    print(f"\n=== Best action by tier: {ROUNDS:,} rounds per tier, seed {SEED}, rounded mid, hidden count uniform in tier range ===")
    print("Run = consecutive rounds whose best action is skip. Run columns are shares of runs; 'reach' = run length >= N.")
    header = (
        f"{'Tier':>4} {'Spread':>6} | {'Buy%':>6} {'Sell%':>6} {'Skip%':>6} | {'Runs':>6} | "
        + " ".join(f"{'len=' + str(n):>6}" for n in (1, 2, 3, 4))
        + f" {'len>=5':>6} | {'reach3':>6} {'reach4':>6} {'reach5':>6} | {'Max':>3}"
    )
    print(header)
    print("-" * len(header))
    for tier, dice, hidden_options in TIERS:
        rolls = rng.integers(1, SIDES + 1, size=(ROUNDS, dice))
        hidden = np.array(hidden_options)[rng.integers(0, len(hidden_options), size=ROUNDS)]
        shift = rng.uniform(-SHIFT_MAX, SHIFT_MAX, size=ROUNDS)
        seen_mask = np.arange(dice)[None, :] >= hidden[:, None]
        fair = (rolls * seen_mask).sum(axis=1) + hidden * MEAN_DIE
        center = round_mid(dice * MEAN_DIE + shift, MID_ROUNDING)
        for spread in BEST_ACTION_SPREADS:
            best = best_actions(fair, center, spread)
            runs = run_lengths(best == 2)
            n = len(runs)
            share = lambda mask: float(mask.sum()) / n if n else 0.0
            cells = " ".join(f"{share(runs == k):>6.1%}" for k in (1, 2, 3, 4))
            print(
                f"{tier:>4} {spread:>6.1f} | {(best == 0).mean():>6.1%} {(best == 1).mean():>6.1%} {(best == 2).mean():>6.1%} | {n:>6} | "
                f"{cells} {share(runs >= 5):>6.1%} | {share(runs >= 3):>6.1%} {share(runs >= 4):>6.1%} {share(runs >= 5):>6.1%} | {int(runs.max()) if n else 0:>3}"
            )
        print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--spread", type=float, default=None, help="full spread for every tier (default: TIER_SPREAD)")
    main(parser.parse_args().spread)
