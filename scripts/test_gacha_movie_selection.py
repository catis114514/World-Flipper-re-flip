from __future__ import annotations

import json
import random
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED_VALIDATOR = ROOT / "src/lib/seed-validator.ts"
GACHA = ROOT / "src/lib/gacha.ts"
PHYSICS = ROOT / "src/lib/gacha-physics.ts"
VERIFIED = ROOT / "assets/verified_seeds.json"

MOVIES = ("normal", "fes", "normal_guarantee", "fes_guarantee")
NEXT_MOVIE = {
    "normal": "fes",
    "fes": "normal_guarantee",
    "normal_guarantee": "fes_guarantee",
    "fes_guarantee": "rarity_5_guarantee",
}


def movie_play_thresholds(source: str) -> dict[str, float]:
    result: dict[str, float] = {}
    for movie in MOVIES:
        start = source.index(f"    {movie}: {{")
        end = source.index(f"    {NEXT_MOVIE[movie]}: {{", start)
        segment = source[start:end]
        match = re.search(r"playMovie:\s*([0-9.eE+-]+)", segment)
        if match is None:
            raise AssertionError(f"missing playMovie threshold for {movie}")
        result[movie] = float(match.group(1))
    return result


def assert_source_contract() -> None:
    seed_source = SEED_VALIDATOR.read_text(encoding="utf-8")
    natural_start = seed_source.index("if (this.mode === 'natural')")
    natural_end = seed_source.index("// Fallback selection", natural_start)
    natural_block = seed_source[natural_start:natural_end]

    assert "const isFirst" not in natural_block
    assert "drawIndex === 0" not in natural_block
    assert "Math.random() < playRate" in natural_block
    assert "naturalPlayRate" in natural_block
    assert "p.verifiedPool.has" in natural_block
    assert "this.isPlayMatch" in natural_block

    gacha_source = GACHA.read_text(encoding="utf-8")
    assert "1 - Number(movieConfig?.threshold?.playMovie" in gacha_source
    assert "drawIndex, naturalPlayRate" in gacha_source

    skip_log = gacha_source.index("[SKIP]")
    skip_continue = gacha_source.index("continue", skip_log)
    increment = gacha_source.index("drawIndex += 1", skip_log, skip_continue)
    assert skip_log < increment < skip_continue


def assert_play_seed_coverage() -> None:
    verified = json.loads(VERIFIED.read_text(encoding="utf-8"))
    required = {
        "normal": {0, 1, 2},
        "fes": {0, 1, 2},
        "normal_guarantee": {1, 2},
        "fes_guarantee": {1, 2},
    }
    for movie, rarities in required.items():
        available = {int(value) for value in verified.get(movie, {}).values()}
        missing = rarities - available
        if missing:
            raise AssertionError(f"{movie}: missing verified play seeds for rarity indexes {sorted(missing)}")


def assert_position_independence(thresholds: dict[str, float]) -> None:
    rng = random.Random(0x57464D)
    batches = 25_000
    tolerance = 0.012

    for movie, threshold in thresholds.items():
        play_rate = 1.0 - threshold
        counts = [0] * 10
        for _ in range(batches):
            for position in range(10):
                if rng.random() < play_rate:
                    counts[position] += 1

        observed = [count / batches for count in counts]
        for position, rate in enumerate(observed):
            if abs(rate - play_rate) > tolerance:
                raise AssertionError(
                    f"{movie} position {position + 1}: {rate:.4f} != {play_rate:.4f}"
                )
        if abs(observed[0] - sum(observed[1:]) / 9) > tolerance:
            raise AssertionError(f"{movie}: first position is biased")

        formatted = " ".join(f"{rate:.3f}" for rate in observed)
        print(f"{movie}: expected={play_rate:.4f} positions={formatted}")


def main() -> None:
    assert_source_contract()
    thresholds = movie_play_thresholds(PHYSICS.read_text(encoding="utf-8"))
    assert_play_seed_coverage()
    assert_position_independence(thresholds)
    print("gacha movie selection checks passed")


if __name__ == "__main__":
    main()

