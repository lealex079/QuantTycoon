"""Level 1 (Hidden Value) simulation.

Value = sum of n six-sided dice. Some dice are hidden; the player sees the rest
and guesses the total. Best guess is the expected value:
    seen total + hidden * 3.5

Setups come from the taker tiers in DESIGN.md. Run: python3 sim/level1_hidden_value.py
"""

import numpy as np

SEED = 12345
ROUNDS = 100_000
SIDES = 6
MEAN_DIE = (SIDES + 1) / 2  # 3.5

# (tier, dice, hidden counts) from DESIGN.md taker tiers
TIERS = [
    (1, 3, [1, 2]),
    (2, 4, [1, 2, 3]),
    (3, 5, [2, 3, 4]),
]


def simulate(rng: np.random.Generator, dice: int, hidden: int, rounds: int) -> dict:
    rolls = rng.integers(1, SIDES + 1, size=(rounds, dice))
    seen_total = rolls[:, hidden:].sum(axis=1)
    true_total = rolls.sum(axis=1)
    guess = seen_total + hidden * MEAN_DIE  # best guess = expected value
    err = true_total - guess
    abs_err = np.abs(err)
    return {
        "std": float(err.std()),
        "within1": float((abs_err <= 1).mean()),
        "within2": float((abs_err <= 2).mean()),
    }


def main() -> None:
    rng = np.random.default_rng(SEED)
    header = f"{'Tier':>4} {'Dice':>4} {'Hidden':>6} {'Best guess':<24} {'Err SD':>7} {'+/-1':>7} {'+/-2':>7}"
    print(f"Hidden Value sim: {ROUNDS:,} rounds per setup, seed {SEED}")
    print("Best guess = seen total + hidden x 3.5.  +/-k = share of rounds with |true - guess| <= k.\n")
    print(header)
    print("-" * len(header))
    for tier, dice, hidden_options in TIERS:
        for hidden in hidden_options:
            r = simulate(rng, dice, hidden, ROUNDS)
            rule = f"seen + {hidden} x 3.5 (+{hidden * MEAN_DIE:g})"
            print(
                f"{tier:>4} {dice:>4} {hidden:>6} {rule:<24} "
                f"{r['std']:>7.3f} {r['within1']:>6.1%} {r['within2']:>6.1%}"
            )
        print()


if __name__ == "__main__":
    main()
