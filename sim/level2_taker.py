"""Level 2 (Taker) simulation.

n dice, some hidden. A bot quotes a bid/ask centered on a mid = n x 3.5 plus a random
continuous shift uniform in [-2, +2], with a spread of 2 (bid = mid - 1, ask = mid + 1).
The mid is then rounded to the nearest MID_ROUNDING (0.5) before the spread is applied, so
quotes end in .0 or .5. Ties on a .25/.75 boundary round half up: floor(mid / step + 0.5) * step.
The sim runs both the continuous and the rounded quote on the same rolls and shifts.
The player knows fair value = seen total + hidden x 3.5 and can buy at the ask,
sell at the bid, or skip. P&L is settled against the true total:
    buy:  true - ask      sell: bid - true      skip: 0

Strategies: always buy, always sell, always skip, and edge
(buy if fair > ask, sell if fair < bid, otherwise skip).

Setups come from the taker tiers in DESIGN.md. Run: python3 sim/level2_taker.py
"""

import numpy as np

SEED = 12345
ROUNDS = 100_000
SIDES = 6
MEAN_DIE = (SIDES + 1) / 2  # 3.5
SHIFT_MAX = 2
SPREAD = 2.0
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


def settle(true_total, fair, center: np.ndarray, rounds: int) -> dict:
    bid = center - SPREAD / 2
    ask = center + SPREAD / 2
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


def simulate(rng: np.random.Generator, dice: int, hidden: int, rounds: int) -> dict:
    """Returns {"continuous": stats, "rounded": stats}, both on the same rolls and shifts."""
    rolls = rng.integers(1, SIDES + 1, size=(rounds, dice))
    true_total = rolls.sum(axis=1)
    fair = rolls[:, hidden:].sum(axis=1) + hidden * MEAN_DIE

    shift = rng.uniform(-SHIFT_MAX, SHIFT_MAX, size=rounds)
    center = dice * MEAN_DIE + shift
    return {
        "continuous": settle(true_total, fair, center, rounds),
        "rounded": settle(true_total, fair, round_mid(center, MID_ROUNDING), rounds),
    }


def main() -> None:
    rng = np.random.default_rng(SEED)
    print(f"Taker sim: {ROUNDS:,} rounds per setup, seed {SEED}")
    print(f"Quote: mid = dice x 3.5 + continuous shift uniform in [-{SHIFT_MAX}, +{SHIFT_MAX}], spread {SPREAD:g}.")
    print(f"'rounded' snaps the mid to the nearest {MID_ROUNDING:g} (half up) before the spread; 'continuous' does not.")
    print("Each cell is mean / SD of P&L per round. Trade% = share of rounds edge trades.")
    print("Seen = dice - hidden. Win% = share of all rounds where edge P&L > 0 (skips count as not winning).\n")

    cols = ["buy", "sell", "skip", "edge"]
    header = f"{'Tier':>4} {'Dice':>4} {'Hid':>3} {'Seen':>4} | " + " | ".join(f"{c:^15}" for c in cols) + f" | {'Trade%':>7} | {'Win%':>6}"
    by_seen: dict = {"continuous": {}, "rounded": {}}
    results = {}
    for tier, dice, hidden_options in TIERS:
        for hidden in hidden_options:
            results[(tier, dice, hidden)] = simulate(rng, dice, hidden, ROUNDS)
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


if __name__ == "__main__":
    main()
