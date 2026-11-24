"""Level 3 and Level 4 (Maker) simulation.

n dice, some hidden. The player's fair value = seen total + hidden x 3.5 and quotes
    bid = fair - h,  ask = fair + h
for half-spreads h from 0.25 to 6 in steps of 0.25. Every trader that wants to trade
fills one unit against the quote. Settlement uses the true total:
    sell at ask: ask - true      buy at bid: true - bid

Level 3 (fair value given): 4 noise traders. Each picks buy or sell with p = 0.5 and a
tolerance uniform in [0, 3.5]. A buyer fills at the ask if ask <= fair + tol; a seller
fills at the bid if bid >= fair - tol.

Level 4 (estimate it yourself): the same 4 noise traders, but their reference is
n x 3.5 (the dice average), not the player's fair value, plus 3 informed bots. Each
informed bot sees ceil(n/2) random dice, estimates the total as seen sum + unseen x 3.5,
buys at the ask if its estimate is above the ask and sells at the bid if below the bid.

Setups use the taker tier ranges in DESIGN.md. Run: python3 sim/level34_maker.py
"""

import math

import numpy as np

SEED = 12345
ROUNDS = 100_000
SIDES = 6
MEAN_DIE = (SIDES + 1) / 2  # 3.5
N_NOISE = 4
N_INFORMED = 3
TOL_MAX = 3.5
HALF_SPREADS = np.arange(0.25, 6.0 + 1e-9, 0.25)
TIGHT = 0.5

# Part 1: full curves for these (mode, dice, hidden)
CURVE_CONFIGS = [(4, 3, 1), (4, 4, 1), (4, 4, 3), (4, 5, 4), (3, 4, 2)]
# Part 2: score columns
SCORE_HS = [0.5, 1.0, 1.75, 2.5, 3.5, 5.0]

# (dice, hidden counts) from the taker tiers in DESIGN.md
SETUPS = [
    (3, [1, 2]),
    (4, [1, 2, 3]),
    (5, [2, 3, 4]),
]
MODES = [3, 4]


def simulate(rng: np.random.Generator, mode: int, dice: int, hidden: int, rounds: int) -> dict:
    """Return per-half-spread arrays of mean P&L, SD P&L and mean fills."""
    rolls = rng.integers(1, SIDES + 1, size=(rounds, dice))
    true_total = rolls.sum(axis=1).astype(float)
    fair = rolls[:, hidden:].sum(axis=1) + hidden * MEAN_DIE

    # Noise traders: side and tolerance are independent of the quote, so draw once per round.
    is_buyer = rng.random((rounds, N_NOISE)) < 0.5
    tol = rng.uniform(0.0, TOL_MAX, size=(rounds, N_NOISE))
    noise_ref = fair[:, None] if mode == 3 else np.full((rounds, 1), dice * MEAN_DIE)

    # Informed bots (Level 4): each sees ceil(dice/2) randomly chosen dice.
    estimates = None
    if mode == 4:
        k = math.ceil(dice / 2)
        estimates = np.empty((rounds, N_INFORMED))
        for b in range(N_INFORMED):
            order = np.argsort(rng.random((rounds, dice)), axis=1)[:, :k]
            seen_sum = np.take_along_axis(rolls, order, axis=1).sum(axis=1)
            estimates[:, b] = seen_sum + (dice - k) * MEAN_DIE

    means = np.empty(len(HALF_SPREADS))
    sds = np.empty(len(HALF_SPREADS))
    fills = np.empty(len(HALF_SPREADS))
    pnl_all = np.empty((rounds, len(HALF_SPREADS)))  # per-round P&L, common random numbers across h
    for i, h in enumerate(HALF_SPREADS):
        bid = fair - h
        ask = fair + h
        t = true_total[:, None]

        buy_fill = is_buyer & (ask[:, None] <= noise_ref + tol)      # player sells at ask
        sell_fill = ~is_buyer & (bid[:, None] >= noise_ref - tol)    # player buys at bid
        pnl = (buy_fill * (ask[:, None] - t)).sum(axis=1) + (sell_fill * (t - bid[:, None])).sum(axis=1)
        n_fills = buy_fill.sum(axis=1) + sell_fill.sum(axis=1)

        if estimates is not None:
            inf_buy = estimates > ask[:, None]    # player sells at ask
            inf_sell = estimates < bid[:, None]   # player buys at bid
            pnl = pnl + (inf_buy * (ask[:, None] - t)).sum(axis=1) + (inf_sell * (t - bid[:, None])).sum(axis=1)
            n_fills = n_fills + inf_buy.sum(axis=1) + inf_sell.sum(axis=1)

        pnl_all[:, i] = pnl
        means[i] = pnl.mean()
        sds[i] = pnl.std()
        fills[i] = n_fills.mean()
    return {"mean": means, "sd": sds, "fills": fills, "pnl": pnl_all}


def analyse(r: dict) -> dict:
    ratio = np.where(r["sd"] > 0, r["mean"] / np.where(r["sd"] > 0, r["sd"], 1.0), -np.inf)
    a = int(np.argmax(r["mean"]))
    b = int(np.argmax(ratio))
    tight = int(np.argmin(np.abs(HALF_SPREADS - TIGHT)))
    return {
        "a": a, "b": b, "ratio": ratio,
        "tight_mean": float(r["mean"][tight]),
    }


def trend(values: list[float]) -> str:
    if all(b > a for a, b in zip(values, values[1:])):
        return "rises"
    if all(b >= a for a, b in zip(values, values[1:])) and values[-1] > values[0]:
        return "rises (with ties)"
    if all(b < a for a, b in zip(values, values[1:])):
        return "falls"
    if all(b <= a for a, b in zip(values, values[1:])) and values[-1] < values[0]:
        return "falls (with ties)"
    if all(b == a for a, b in zip(values, values[1:])):
        return "flat"
    return "does not move monotonically"


def main() -> None:
    rng = np.random.default_rng(SEED)
    print(f"Maker sim: {ROUNDS:,} rounds per (mode, dice, hidden, half-spread), seed {SEED}.")
    print(f"Half-spreads {HALF_SPREADS[0]:g} to {HALF_SPREADS[-1]:g} step 0.25. "
          f"Best-spread columns show h*, mean P&L, SD, avg fills per round.")
    print(f"'Mean@{TIGHT:g}' = mean P&L at half-spread {TIGHT:g}.\n")

    best: dict[tuple[int, int, int], tuple[float, float]] = {}
    results: dict[tuple[int, int, int], dict] = {}
    for mode in MODES:
        desc = ("4 noise traders, reference = your fair value" if mode == 3
                else "4 noise traders (reference dice x 3.5) + 3 informed bots")
        print(f"=== Level {mode}: {desc} ===")
        hdr = (f"{'Dice':>4} {'Hid':>3} | {'(a) max mean P&L':^34} | {'(b) max mean/SD':^42} | {'Mean@' + format(TIGHT, 'g'):>8}")
        sub = (f"{'':>4} {'':>3} | {'h*':>5} {'mean':>8} {'SD':>7} {'fills':>6}   | "
               f"{'h*':>5} {'mean':>8} {'SD':>7} {'m/SD':>7} {'fills':>6}   | {'':>8}")
        print(hdr)
        print(sub)
        print("-" * len(sub))
        for dice, hiddens in SETUPS:
            for hidden in hiddens:
                r = simulate(rng, mode, dice, hidden, ROUNDS)
                if (mode, dice, hidden) not in CURVE_CONFIGS:
                    r = {k: v for k, v in r.items() if k != "pnl"}
                results[(mode, dice, hidden)] = r
                s = analyse(r)
                a, b = s["a"], s["b"]
                best[(mode, dice, hidden)] = (float(HALF_SPREADS[a]), float(HALF_SPREADS[b]))
                print(f"{dice:>4} {hidden:>3} | "
                      f"{HALF_SPREADS[a]:>5.2f} {r['mean'][a]:>+8.3f} {r['sd'][a]:>7.3f} {r['fills'][a]:>6.2f}   | "
                      f"{HALF_SPREADS[b]:>5.2f} {r['mean'][b]:>+8.3f} {r['sd'][b]:>7.3f} {s['ratio'][b]:>7.4f} {r['fills'][b]:>6.2f}   | "
                      f"{s['tight_mean']:>+8.3f}")
            print()

    print("=== Does the best half-spread rise with hidden count? ===")
    print("Checked within each dice count (hidden count varies, dice fixed), then across all setups of a mode.")
    for mode in MODES:
        for idx, name in ((0, "(a) mean P&L"), (1, "(b) mean/SD")):
            parts = []
            for dice, hiddens in SETUPS:
                vals = [best[(mode, dice, h)][idx] for h in hiddens]
                parts.append(f"{dice} dice {[f'{v:g}' for v in vals]} -> {trend(vals)}")
            print(f"Level {mode}, {name}: " + "; ".join(parts))

    print_curves(results)
    print_scores(results)


def print_curves(results: dict) -> None:
    print("\n=== Part 1: full curves ===")
    print("SE(diff) = SE of the mean of per-round (P&L at h minus P&L at best h), paired.")
    print("'in2SE' marks h whose mean is within 2 SE of the best.")
    for key in CURVE_CONFIGS:
        mode, dice, hidden = key
        r = results[key]
        a = int(np.argmax(r["mean"]))
        diff = r["pnl"] - r["pnl"][:, [a]]
        se = diff.std(axis=0, ddof=1) / math.sqrt(diff.shape[0])
        gap = r["mean"] - r["mean"][a]
        within = [i for i in range(len(HALF_SPREADS)) if i == a or -gap[i] <= 2 * se[i]]
        print(f"\nLevel {mode}, {dice} dice, {hidden} hidden (best h = {HALF_SPREADS[a]:g})")
        print(f"{'h':>5} {'mean':>8} {'SD':>7} {'fills':>6} {'SE(diff)':>9} {'in2SE':>6}")
        for i, h in enumerate(HALF_SPREADS):
            flag = "yes" if i in within else ""
            print(f"{h:>5.2f} {r['mean'][i]:>+8.3f} {r['sd'][i]:>7.3f} {r['fills'][i]:>6.2f} {se[i]:>9.4f} {flag:>6}")
        print("Within 2 SE of best: " + ", ".join(f"{HALF_SPREADS[i]:g}" for i in within))


def print_scores(results: dict) -> None:
    print("\n=== Part 2: score = max(0, mean at h / mean at best h) ===")
    idx = [int(np.argmin(np.abs(HALF_SPREADS - h))) for h in SCORE_HS]
    print(f"{'Lvl':>3} {'Dice':>4} {'Hid':>3} {'best h':>6} {'best mean':>9} | "
          + " ".join(f"{'h=' + format(h, 'g'):>7}" for h in SCORE_HS))
    for (mode, dice, hidden), r in results.items():
        a = int(np.argmax(r["mean"]))
        bm = float(r["mean"][a])
        scores = [max(0.0, float(r["mean"][i]) / bm) for i in idx]
        print(f"{mode:>3} {dice:>4} {hidden:>3} {HALF_SPREADS[a]:>6.2f} {bm:>+9.3f} | "
              + " ".join(f"{sc:>7.3f}" for sc in scores))


if __name__ == "__main__":
    main()
