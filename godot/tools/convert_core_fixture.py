#!/usr/bin/env python3
"""Build the first Godot CN quest fixture from canonical client evidence.

The converter combines the CN service emulator tables, the public CN 1.4.54
master-data extraction, and curve tables bundled in the supplied 1.8.1 APK.
The original terrain binary is not present in the APK bootstrap bundle, so the
fixture records its verified logical/hash path and keeps collision placement as
an explicit presentation fallback.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import struct
import subprocess
import zlib
import zipfile
from pathlib import Path
from typing import Any, Callable

DEFAULT_QUEST_ID = "1001002"
CATEGORY = 1
ASSET_SALT = "K6R9T9Hz22OpeIGEWB0ui6c6PYFQnJGy"
MAX_ACTION_DELAY_FRAMES = (1 << 53) - 1
ELEMENT_NAMES = ["fire", "water", "thunder", "wind", "light", "dark"]
DEFAULT_PARTY_IDS = ["141005", "121002", "131004"]
DEFAULT_EQUIPMENT_IDS = ["1010001", "100001"]
GENERAL_BOSS_VARIABLE_PATH = Path("orderedmap/battle/boss/general_boss_variable.json")

GENERAL_ENEMY_ADAPTERS = {
    "fox": {"state_difficulty": "1"},
    "one_eyed_rabbit": {"state_difficulty": "1"},
    "slango": {"state_difficulty": "1"},
    "spirit": {"state_difficulty": "1"},
}

FALLBACK_TERRAIN_MARKERS = {
    "p0": [360.0, 300.0],
    "p1": [220.0, 300.0],
    "p2": [500.0, 300.0],
    "p3": [360.0, 220.0],
    "p4": [360.0, 140.0],
}

PARTY_ATK_CURVE_PATH = "master/battle/enemy/party/party_atk_curve_iosbundled.orderedmap"
HIT_HP_BASIC_CURVE_PATH = "master/battle/enemy/hp/hit_hp_basic_curve_iosbundled.orderedmap"
HIT_HP_CORRECTION_CURVE_PATH = "master/battle/enemy/hp/hit_hp_correction_curve_iosbundled.orderedmap"
PARTY_HP_CURVE_PATH = "master/battle/enemy/party/party_hp_curve_iosbundled.orderedmap"
ATK_BASIC_CURVE_PATH = "master/battle/enemy/atk/atk_basic_curve_iosbundled.orderedmap"
ATK_CORRECTION_CURVE_PATH = "master/battle/enemy/atk/atk_correction_curve_iosbundled.orderedmap"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def hashed_asset_path(logical_path: str) -> str:
    normalized = logical_path.replace("\\", "/")
    while "//" in normalized:
        normalized = normalized.replace("//", "/")
    normalized = normalized.lstrip("/")
    digest = hashlib.sha1((normalized + ASSET_SALT).encode("utf-8")).hexdigest()
    return f"{digest[:2]}/{digest[2:]}"


def git_revision(repo: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(repo), "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def parse_ordered_map(data: bytes, key_cast: Callable[[str], Any]) -> dict[Any, bytes]:
    if len(data) < 4:
        raise ValueError("ordered-map data is shorter than its header")
    header_size = struct.unpack_from("<i", data, 0)[0]
    if header_size <= 0 or 4 + header_size > len(data):
        raise ValueError("ordered-map header length is invalid")
    header = zlib.decompress(data[4 : 4 + header_size])
    if len(header) < 4:
        raise ValueError("ordered-map header is truncated")
    count = struct.unpack_from("<i", header, 0)[0]
    pair_bytes = 4 + count * 8
    if count < 0 or pair_bytes > len(header):
        raise ValueError("ordered-map entry count is invalid")

    key_ends: list[int] = []
    value_ends: list[int] = []
    offset = 4
    for _ in range(count):
        key_end, value_end = struct.unpack_from("<ii", header, offset)
        offset += 8
        key_ends.append(key_end)
        value_ends.append(value_end)

    key_blob = header[pair_bytes:]
    keys: list[Any] = []
    previous = 0
    for end in key_ends:
        if end < previous or end > len(key_blob):
            raise ValueError("ordered-map key offsets are invalid")
        keys.append(key_cast(key_blob[previous:end].decode("utf-8")))
        previous = end

    value_blob = data[4 + header_size :]
    values: dict[Any, bytes] = {}
    previous = 0
    for key, end in zip(keys, value_ends, strict=True):
        if end < previous or end > len(value_blob):
            raise ValueError("ordered-map value offsets are invalid")
        if key in values:
            raise ValueError(f"duplicate ordered-map key: {key}")
        values[key] = value_blob[previous:end]
        previous = end
    return values


def parse_ordered_map_row(data: bytes) -> list[str]:
    text = zlib.decompress(data).decode("utf-8-sig")
    rows = list(csv.reader(io.StringIO(text)))
    if len(rows) != 1:
        raise ValueError(f"expected one ordered-map row, got {len(rows)}")
    return rows[0]


def read_apk_curve_tables(apk_path: Path) -> tuple[
    dict[int, float],
    dict[str, dict[int, float]],
    dict[str, dict[int, float]],
    dict[int, float],
    dict[str, dict[int, float]],
    dict[str, dict[int, float]],
    set[str],
]:
    with zipfile.ZipFile(apk_path) as apk:
        bundle_data = apk.read("assets/bundle.zip")
    with zipfile.ZipFile(io.BytesIO(bundle_data)) as bundle:
        names = set(bundle.namelist())

        def read_logical(logical_path: str) -> bytes:
            entry = f"production/android_bundle/{hashed_asset_path(logical_path)}"
            if entry not in names:
                raise FileNotFoundError(f"APK bundle entry not found: {logical_path} -> {entry}")
            return bundle.read(entry)

        party_raw = parse_ordered_map(read_logical(PARTY_ATK_CURVE_PATH), int)
        party_atk = {level: float(parse_ordered_map_row(row)[0]) for level, row in party_raw.items()}
        party_hp_raw = parse_ordered_map(read_logical(PARTY_HP_CURVE_PATH), int)
        party_hp = {level: float(parse_ordered_map_row(row)[0]) for level, row in party_hp_raw.items()}

        def read_nested_curves(logical_path: str) -> dict[str, dict[int, float]]:
            outer = parse_ordered_map(read_logical(logical_path), str)
            curves: dict[str, dict[int, float]] = {}
            for curve_id, nested_data in outer.items():
                inner = parse_ordered_map(nested_data, int)
                curves[curve_id] = {
                    level: float(parse_ordered_map_row(row)[0])
                    for level, row in inner.items()
                }
            return curves

        return (
            party_atk,
            read_nested_curves(HIT_HP_BASIC_CURVE_PATH),
            read_nested_curves(HIT_HP_CORRECTION_CURVE_PATH),
            party_hp,
            read_nested_curves(ATK_BASIC_CURVE_PATH),
            read_nested_curves(ATK_CORRECTION_CURVE_PATH),
            names,
        )


def threshold_value(values: dict[int, Any], level: int) -> Any:
    for key in sorted(values):
        if key >= level:
            return values[key]
    raise ValueError(f"no threshold value for level {level}")


def threshold_row(values: dict[str, list[list[str]]], level: int) -> list[str]:
    rows = {int(key): value for key, value in values.items()}
    selected = threshold_value(rows, level)
    if len(selected) != 1:
        raise ValueError("expected one threshold master row")
    return selected[0]


def calculate_hit_hp(
    level: int,
    level_row: list[str],
    party_atk: dict[int, float],
    basic_curves: dict[str, dict[int, float]],
    correction_curves: dict[str, dict[int, float]],
    quest_correction: float,
) -> tuple[int, dict[str, float | str]]:
    if level_row[0] != "0":
        raise ValueError("the selected enemy does not use hit-based HP")
    basic_curve_id = level_row[1]
    hit_count = float(level_row[2])
    row_correction = float(level_row[3])
    correction_curve_id = level_row[4]
    party_multiplier = float(threshold_value(party_atk, level))
    basic_multiplier = float(threshold_value(basic_curves[basic_curve_id], level))
    curve_correction = float(threshold_value(correction_curves[correction_curve_id], level))
    hp = math.floor(
        375.0
        * party_multiplier
        * basic_multiplier
        * hit_count
        * row_correction
        * curve_correction
        * quest_correction
    )
    return hp, {
        "party_atk_level_1": 375.0,
        "party_atk_multiplier": party_multiplier,
        "basic_curve_id": basic_curve_id,
        "basic_multiplier": basic_multiplier,
        "hit_count": hit_count,
        "row_correction": row_correction,
        "correction_curve_id": correction_curve_id,
        "curve_correction": curve_correction,
        "quest_correction": quest_correction,
    }



def calculate_enemy_atk(
    level: int,
    level_row: list[str],
    party_hp: dict[int, float],
    basic_curves: dict[str, dict[int, float]],
    correction_curves: dict[str, dict[int, float]],
    quest_correction: float,
) -> tuple[int, dict[str, float | str]]:
    basic_curve_id = level_row[7]
    hit_count = float(level_row[8])
    row_correction = float(level_row[9])
    correction_curve_id = level_row[10]
    party_multiplier = float(threshold_value(party_hp, level))
    basic_multiplier = float(threshold_value(basic_curves[basic_curve_id], level))
    curve_correction = float(threshold_value(correction_curves[correction_curve_id], level))
    atk = math.floor(
        645.0
        * party_multiplier
        * basic_multiplier
        * curve_correction
        * row_correction
        * quest_correction
        / hit_count
    )
    return atk, {
        "party_hp_level_1": 645.0,
        "party_hp_multiplier": party_multiplier,
        "basic_curve_id": basic_curve_id,
        "basic_multiplier": basic_multiplier,
        "hit_count": hit_count,
        "row_correction": row_correction,
        "correction_curve_id": correction_curve_id,
        "curve_correction": curve_correction,
        "quest_correction": quest_correction,
    }

def option_value(value: str) -> str | None:
    if value in ("", "(None)"):
        return None
    return value


def parse_zone(zone_id: int, row: list[str], action_rows: list[list[str]]) -> dict[str, Any]:
    objective_kind = row[0]
    if objective_kind == "0":
        objective = {"kind": "zako_kill", "count": int(row[1])}
    elif objective_kind == "1":
        objective = {"kind": "boss_clear"}
    elif objective_kind == "2":
        objective = {"kind": "unspecified"}
    else:
        raise ValueError(f"unknown zone objective kind: {objective_kind}")

    zako_emitters = []
    for index in range(2, 22, 2):
        enemy_id = option_value(row[index])
        if enemy_id is None:
            continue
        interval = option_value(row[index + 1])
        zako_emitters.append(
            {
                "enemy_id": enemy_id,
                "interval_frames": None if interval is None else int(interval),
            }
        )

    boss_kind_names = {"0": "standard_boss", "1": "general_boss"}

    def parse_boss(kind_value: str, enemy_value: str) -> dict[str, str] | None:
        kind = option_value(kind_value)
        enemy_id = option_value(enemy_value)
        if kind is None or enemy_id is None:
            return None
        return {"enemy_id": enemy_id, "kind": boss_kind_names.get(kind, f"boss_kind_{kind}")}

    bosses = [boss for boss in (parse_boss(row[23], row[24]), parse_boss(row[27], row[28]), parse_boss(row[31], row[32])) if boss]
    multiplayer_bosses = [boss for boss in (parse_boss(row[25], row[26]), parse_boss(row[29], row[30]), parse_boss(row[33], row[34])) if boss]

    action_kind_names = {
        "0": "replay",
        "1": "hint_tap",
        "2": "request_touch",
        "3": "request_dash",
        "4": "request_skill",
        "5": "movie_dialog",
        "6": "enable_skill",
        "7": "enable_control_board",
        "8": "complete_zone_objective",
        "9": "scenario",
    }
    actions = []
    for action_row in action_rows:
        action = {
            "trigger": "start" if action_row[0] == "0" else f"trigger_{action_row[0]}",
            "delay_frames": int(action_row[3]),
            "kind": action_kind_names.get(action_row[4], f"action_{action_row[4]}"),
        }
        payload = option_value(action_row[6] if action_row[4] == "5" else action_row[7])
        if payload is not None:
            action["payload"] = payload
        actions.append(action)

    return {
        "id": zone_id,
        "objective": objective,
        "zako_emitters": zako_emitters,
        "boss_group_kind": int(row[22]),
        "bosses": bosses,
        "multiplayer_bosses": multiplayer_bosses,
        "actions": actions,
        "field_objects": {
            "outhole_animation": row[35],
            "dash_panel_directory": option_value(row[36]),
            "rotation_panel_animation": option_value(row[37]),
            "instant_item_odds": option_value(row[38]),
            "breakable_block_odds": option_value(row[39]),
            "breakable_decoration_odds": option_value(row[40]),
        },
    }


def iter_action_commands(value: Any):
    if isinstance(value, list):
        if len(value) >= 2 and value[0] == "Command" and isinstance(value[1], list) and value[1]:
            yield value[1]
        for item in value:
            yield from iter_action_commands(item)
    elif isinstance(value, dict):
        for item in value.values():
            yield from iter_action_commands(item)


def fixed_range_value(value: Any) -> float:
    if not isinstance(value, list) or len(value) != 1 or not isinstance(value[0], dict):
        raise ValueError(f"unsupported action DSL numeric range: {value!r}")
    minimum = float(value[0]["min"])
    maximum = float(value[0]["max"])
    if minimum != maximum:
        raise ValueError(f"non-deterministic action DSL range is not supported: {value!r}")
    return minimum


def normalize_projectile_pattern(command: list[Any]) -> dict[str, Any]:
    if len(command) < 24 or command[0] != "CreateHitArea":
        raise ValueError("CreateHitArea command is truncated")
    shape = command[9]
    if not isinstance(shape, list) or len(shape) < 2 or shape[0] != "Circle":
        raise ValueError(f"unsupported hit-area shape: {shape!r}")
    distribution = command[12]
    if not isinstance(distribution, list) or not distribution:
        raise ValueError("hit-area distribution is missing")
    distribution_kind = str(distribution[0])
    if distribution_kind == "Single":
        normalized_distribution = {"kind": "single", "count": 1, "spread_radians": 0.0}
    elif distribution_kind == "NWay":
        normalized_distribution = {
            "kind": "n_way",
            "count": int(distribution[1]),
            "spread_radians": float(distribution[2]),
        }
    elif distribution_kind == "Circle":
        normalized_distribution = {
            "kind": "circle",
            "count": int(distribution[1]),
            "spread_radians": math.tau,
        }
    else:
        raise ValueError(f"unsupported hit-area distribution: {distribution!r}")

    nested_commands = list(iter_action_commands(command[20])) + list(iter_action_commands(command[23]))
    move = next((nested for nested in nested_commands if nested[0] == "MoveHitArea"), None)
    attack = next((nested for nested in nested_commands if nested[0] == "CreateNormalAttack"), None)
    effect = next((nested for nested in nested_commands if nested[0] == "ShowEffect"), None)
    if move is None or attack is None:
        raise ValueError("projectile action is missing movement or attack data")
    effect_path = None
    if effect is not None and len(effect) > 2 and isinstance(effect[2], list) and len(effect[2]) > 1:
        effect_path = str(effect[2][1])
    return {
        "kind": "projectile",
        "hit_area_name": str(command[1]),
        "radius": fixed_range_value(shape[1]),
        "angle_offset_radians": float(command[6]),
        "distribution": normalized_distribution,
        "lifetime_frames": int(command[13][1]),
        "min_hit_interval_frames": int(command[14][1]),
        "speed_per_frame": float(move[4]),
        "attack_multiplier": fixed_range_value(attack[6]),
        "effect_path": effect_path,
    }


def normalize_action_runtime(data: Any) -> list[dict[str, Any]]:
    runtime: list[dict[str, Any]] = []
    for delay_frames, command in iter_action_commands_with_delay(data):
        if command[0] == "CreateHitArea":
            record = normalize_projectile_pattern(command)
            if delay_frames > 0:
                record["delay_frames"] = delay_frames
            runtime.append(record)
        elif command[0] == "SpawnFunnel":
            target = command[1]
            group = command[3]
            record = {
                "kind": "spawn_funnel",
                "enemy_kind": str(target[0]).lower(),
                "enemy_id": str(target[1]),
                "level": int(command[2]),
                "group_id": int(group[1]),
            }
            if delay_frames > 0:
                record["delay_frames"] = delay_frames
            runtime.append(record)
    return runtime


def action_asset_record(wf_assets_root: Path, logical_path: str) -> tuple[dict[str, Any], tuple[str, Path]]:
    relative = Path("assets") / f"{logical_path}.action.dsl.json"
    source_path = wf_assets_root / relative
    if not source_path.is_file():
        raise FileNotFoundError(f"action DSL is missing: {source_path}")
    data = load_json(source_path)
    commands = {str(command[0]) for command in iter_action_commands(data)}
    runtime = normalize_action_runtime(data)
    if not runtime:
        raise ValueError(f"action DSL has no supported runtime commands: {source_path}")
    return (
        {
            "id": logical_path,
            "commands": sorted(commands),
            "runtime": runtime,
            "sha256": sha256(source_path),
        },
        (relative.as_posix(), source_path),
    )



def wait_frame_count(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"invalid Wait frame count: {value!r}")
    if value < 0 or value > MAX_ACTION_DELAY_FRAMES:
        raise ValueError(f"invalid Wait frame count: {value!r}")
    return value


def iter_action_commands_with_delay(node: Any, delay_frames: int = 0):
    delay_frames = wait_frame_count(delay_frames)
    if not isinstance(node, list):
        return
    if node and node[0] == "Event":
        if len(node) != 2 or not isinstance(node[1], list):
            raise ValueError(f"malformed Event node: {node!r}")
        event = node[1]
        if event and event[0] == "Wait":
            if len(event) != 4 or not isinstance(event[3], list):
                raise ValueError(f"malformed Wait event: {event!r}")
            nested_delay = wait_frame_count(event[1])
            if delay_frames > MAX_ACTION_DELAY_FRAMES - nested_delay:
                raise ValueError(
                    f"invalid Wait frame count after nesting: {delay_frames}+{nested_delay}"
                )
            yield from iter_action_commands_with_delay(event[3], delay_frames + nested_delay)
            return
    if len(node) == 2 and node[0] == "Command" and isinstance(node[1], list):
        yield delay_frames, node[1]
    for child in node:
        yield from iter_action_commands_with_delay(child, delay_frames)


ABILITY_CONTENT_NAMES = {
    4: "ResistanceAllElement", 9: "ResistanceWhite", 31: "ResistanceYellowDownPrevent", 32: "DirectDamage", 33: "SkillDamage",
    51: "CharacterSlayer", 117: "ParalysisSlayer", 145: "ParalysisDirectDamageSlayer",
    191: "PowerFlipDamageUpExtend", 205: "FixedHeal", 211: "AddFeverPoint",
    213: "DirectDamageDownPrevent", 223: "AdditionalDirectAtttackExtend", 309: "ResistanceToFrozenEnemy",
    512: "FrozenAttackSlayer",
}
ABILITY_TRIGGER_NAMES = {0: "None", 4: "Dash1", 8: "MultiballAppear", 20: "DamageCount", 23: "SkillMax", 58: "ElementVariety"}


def normalize_ability_soul_rows(rows: list[list[str]]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for row_index, row in enumerate(rows):
        if row[44]:
            content_index, power_index, trigger_kind = 44, 48, "Instant"
        elif row[94]:
            content_index, power_index, trigger_kind = 94, 110, "During"
        else:
            continue
        code = int(row[content_index])
        raw = float(row[power_index]) if row[power_index] else 0.0
        records.append({"row_index": row_index, "trigger_kind": trigger_kind, "content_code": code, "content_kind": ABILITY_CONTENT_NAMES.get(code, f"Unsupported:{code}"), "target_code": int(row[content_index + 1]) if row[content_index + 1] else 0, "power1_raw": raw, "power1": raw / 100000.0})
    return records


def normalize_character_abilities(ability_master: dict[str, Any], ability_ids: list[str]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for ability_id in ability_ids:
        for row_index, row in enumerate(ability_master.get(ability_id, [])):
            content_index = 47 if row[47] else 97 if row[97] else -1
            if content_index < 0:
                continue
            content_code = int(row[content_index])
            trigger_code = int(row[27]) if row[27] else 0
            power_index = content_index + 4
            power1_raw = float(row[power_index]) if row[power_index] else 0.0
            first_max_raw = float(row[power_index + 1]) if row[power_index + 1] else power1_raw
            records.append({
                "ability_id": ability_id,
                "row_index": row_index,
                "unisonable": str(row[1]).lower() == "true",
                "statue_group_id": str(row[2]),
                "trigger_code": trigger_code,
                "trigger_kind": ABILITY_TRIGGER_NAMES.get(trigger_code, f"Unsupported:{trigger_code}"),
                "trigger_threshold_raw": float(row[30]) if row[30] else 0.0,
                "trigger_threshold": (float(row[30]) / 100000.0) if row[30] else 0.0,
                "content_code": content_code,
                "content_kind": ABILITY_CONTENT_NAMES.get(content_code, f"Unsupported:{content_code}"),
                "target_code": int(row[content_index + 1]) if row[content_index + 1] else 0,
                "power1_raw": power1_raw,
                "first_max_raw": first_max_raw,
                "power1": power1_raw / 100000.0,
                "first_max": first_max_raw / 100000.0,
            })
    return records


def player_skill_record(wf_assets_root: Path, skill_master: dict[str, Any], asset_id: str) -> tuple[dict[str, Any], tuple[str, Path]]:
    rows = skill_master.get(asset_id, {}).get("1", [])
    if len(rows) != 1:
        raise ValueError(f"default party skill lookup is ambiguous: {asset_id}")
    row = rows[0]
    logical_path = str(row[7])
    relative = Path("assets") / f"{logical_path}.action.dsl.json"
    source_path = wf_assets_root / relative
    data = load_json(source_path)
    delayed_commands = list(iter_action_commands_with_delay(data))
    hit_entry = next(((delay, c) for delay, c in delayed_commands if c[0] == "CreateHitArea"), None)
    hit_area = hit_entry[1] if hit_entry else None
    hit_delay = hit_entry[0] if hit_entry else 0
    attack = next((c for _, c in delayed_commands if c[0] == "CreateNormalAttack"), None)
    if hit_area is None or attack is None:
        raise ValueError(f"player skill lacks supported hit runtime: {logical_path}")
    shape = hit_area[9]
    max_hits = hit_area[14]
    multiplier = attack[6]
    if shape[0] != "Circle" or max_hits[0] != "CalculatedUsingMaxNumOfHits":
        raise ValueError(f"unsupported player skill hit geometry: {logical_path}")
    conditions: list[dict[str, Any]] = []
    for condition_delay, command in delayed_commands:
        if command[0] != "CreateCondition":
            continue
        for condition in command[2]:
            kind = str(condition[0])
            values = condition[1:]
            record: dict[str, Any] = {"delay_frames": condition_delay, "source_kind": kind}
            if kind == "ACFlying":
                record.update({"kind": "flying", "target": "party", "duration_frames": int(values[0][0]["max"])})
            elif kind == "ACAttackPoint":
                record.update({"kind": "attack_up", "target": "party", "duration_frames": int(values[0][0]["max"]), "amount": float(values[1][0]["max"])})
            elif kind == "ACPoison":
                record.update({"kind": "poison", "target": "enemy", "duration_frames": int(values[0][0]["max"]), "strength_raw": float(values[1][0]["max"]), "interval_raw": float(values[2][0]["max"]), "tick_frames": 60, "tick_status": "adapter pending exact poison interval unit recovery"})
            else:
                continue
            conditions.append(record)
    return ({
        "name": str(row[0]),
        "description": str(row[1]),
        "max_skill_point": int(row[4]),
        "action_id": logical_path,
        "runtime": {
            "kind": "area_attack",
            "delay_frames": hit_delay,
            "radius": float(shape[1][0]["max"]),
            "max_hits": int(max_hits[1]),
            "attack_multiplier": float(multiplier[0]["max"]),
            "conditions": conditions,
            "status": "canonical hit delay/core parameters/condition payloads; visual effects and full target semantics pending",
        },
        "sha256": sha256(source_path),
    }, (relative.as_posix(), source_path))

def action_paths_from_row(row: list[str]) -> list[str]:
    return [
        value
        for value in row
        if isinstance(value, str) and value.startswith("battle/action/")
    ]


def boss_action_by_marker(action_paths: list[str]) -> dict[str, str]:
    marker_actions: dict[str, str] = {}
    for action_path in action_paths:
        action_name = action_path.rsplit("/", 1)[-1]
        if "_funnel_" in action_name:
            marker_name = "funnel1_fire"
        elif "_skill_" in action_name:
            marker_name = "skill1_fire"
        elif action_name.endswith("_shot1"):
            marker_name = "shot1_fire"
        else:
            continue
        if marker_name in marker_actions:
            raise ValueError(f"duplicate boss action marker binding: {marker_name}")
        marker_actions[marker_name] = action_path
    return marker_actions


def select_general_boss_variables(
    variable_master: dict[str, Any],
    routine_id: str,
    enemy_level: int,
) -> dict[str, float]:
    level_groups = variable_master.get(routine_id, {})
    if not level_groups:
        return {}
    selected = threshold_value({int(key): value for key, value in level_groups.items()}, enemy_level)
    variables: dict[str, float] = {}
    for variable_name, rows in selected.items():
        if len(rows) != 1 or len(rows[0]) != 1:
            raise ValueError(f"general boss variable lookup is ambiguous: {routine_id}.{variable_name}")
        variables[str(variable_name)] = float(rows[0][0])
    return variables


def normalize_general_boss_state_machine(
    routine_id: str,
    initial_state_id: str,
    state_difficulty: str,
    state_master: dict[str, Any],
    action_paths: list[str],
    variables: dict[str, float],
) -> dict[str, Any]:
    state_rows = state_master[routine_id][state_difficulty]
    action_by_marker = boss_action_by_marker(action_paths)
    states: dict[str, dict[str, Any]] = {}
    current = initial_state_id
    visited: set[str] = set()
    while current not in visited:
        visited.add(current)
        rows = state_rows.get(current, [])
        if len(rows) != 1:
            raise ValueError(f"{routine_id} state lookup is ambiguous: {current}")
        row = rows[0]
        if row[29] != "0" or not row[31]:
            raise ValueError(f"{routine_id} core state is not an unconditional transition: {current}")
        termination_kind = row[46]
        if termination_kind == "2":
            termination = {"kind": "time", "value": int(row[47])}
        elif termination_kind == "3":
            termination = {"kind": "animation_loop", "value": int(row[47])}
        elif termination_kind == "4":
            termination = {
                "kind": "move",
                "distance": float(row[47]),
                "target": row[50],
                "easing": int(row[52]),
                "fallback_frames": 90,
                "status": "fallback duration pending terrain marker coordinates and animation speed recovery",
            }
        elif termination_kind == "6":
            variable_name = row[47]
            if variable_name not in variables:
                raise ValueError(f"missing {routine_id} time variable: {variable_name}")
            variable_value = variables[variable_name]
            if not variable_value.is_integer() or variable_value <= 0:
                raise ValueError(f"invalid {routine_id} time variable: {variable_name}={variable_value}")
            termination = {
                "kind": "time",
                "value": int(variable_value),
                "source_variable": variable_name,
            }
        else:
            raise ValueError(f"unsupported {routine_id} termination kind {termination_kind}: {current}")
        state = {
            "id": current,
            "animation_sequence_name": option_value(row[2]),
            "marker_sequence_name": option_value(row[3]),
            "next_state": row[31],
            "termination": termination,
        }
        marker_name = option_value(row[3])
        if marker_name in action_by_marker:
            state["action_id"] = action_by_marker[marker_name]
        states[current] = state
        current = row[31]
    if current != initial_state_id or len(states) != len(state_rows):
        raise ValueError(
            f"unexpected {routine_id} state cycle: return={current} "
            f"visited={len(states)} master={len(state_rows)}"
        )
    return {
        "initial_state_id": initial_state_id,
        "states": states,
        "status": "canonical unconditional state chain; movement durations use explicit fallback frames",
    }


def verify_emulator_projection(
    repo_root: Path,
    quest_id: str,
    row: list[str],
) -> list[tuple[str, Path]]:
    paths = [
        ("assets/main_quest.json", repo_root / "assets/main_quest.json"),
        ("assets/quest_lookup.json", repo_root / "assets/quest_lookup.json"),
        ("assets/quest_entry_costs.json", repo_root / "assets/quest_entry_costs.json"),
    ]
    main_quest = load_json(paths[0][1])[quest_id]
    quest_name = load_json(paths[1][1])[f"{CATEGORY}_{quest_id}"]
    entry_cost = load_json(paths[2][1])[f"{CATEGORY}_{quest_id}"]
    expected = {
        "name": row[1],
        "stamina": int(row[69]),
        "clearRewardId": int(row[3]),
        "scoreRewardGroupId": int(row[70]),
        "bRankTime": round(float(row[84]) * 1000),
        "aRankTime": round(float(row[85]) * 1000),
        "sRankTime": round(float(row[86]) * 1000),
        "sPlusRankTime": round(float(row[87]) * 1000),
        "characterExpReward": int(row[94]),
        "manaReward": int(row[95]),
        "poolExpReward": int(row[96]),
    }
    actual = {
        "name": quest_name,
        "stamina": int(entry_cost["stamina"]),
        "clearRewardId": int(main_quest["clearRewardId"]),
        "scoreRewardGroupId": int(main_quest["scoreRewardGroupId"]),
        "bRankTime": int(main_quest["bRankTime"]),
        "aRankTime": int(main_quest["aRankTime"]),
        "sRankTime": int(main_quest["sRankTime"]),
        "sPlusRankTime": int(main_quest["sPlusRankTime"]),
        "characterExpReward": int(main_quest["characterExpReward"]),
        "manaReward": int(main_quest["manaReward"]),
        "poolExpReward": int(main_quest["poolExpReward"]),
    }
    if actual != expected:
        raise ValueError(f"emulator quest projection differs from CN master row: {actual} != {expected}")
    return paths


def build_fixture(
    repo_root: Path,
    wf_assets_root: Path,
    apk_path: Path,
    quest_id: str = DEFAULT_QUEST_ID,
) -> dict[str, Any]:
    wf_paths = {
        "version": Path("VERSION"),
        "main_quest": Path("orderedmap/quest/main_quest.json"),
        "field_data": Path("orderedmap/battle/field_data.json"),
        "field": Path("orderedmap/battle/field.json"),
        "zone": Path("orderedmap/battle/zone.json"),
        "zone_action": Path("orderedmap/battle/zone_action.json"),
        "general_zako": Path("orderedmap/battle/zako/general_zako.json"),
        "zako_level": Path("orderedmap/battle/zako/zako_level.json"),
        "general_boss": Path("orderedmap/battle/boss/general_boss.json"),
        "boss_level": Path("orderedmap/battle/boss/boss_level.json"),
        "general_boss_state": Path("orderedmap/battle/boss/general_boss_state.json"),
        "character": Path("orderedmap/character/character.json"),
        "character_status": Path("orderedmap/character/character_status.json"),
        "character_level": Path("orderedmap/character/character_level.json"),
        "evolution_status": Path("orderedmap/character/evolution_status.json"),
        "character_text": Path("orderedmap/character/character_text.json"),
        "action_skill": Path("orderedmap/skill/action_skill.json"),
        "ability": Path("orderedmap/ability/ability.json"),
        "equipment": Path("orderedmap/item/equipment.json"),
        "equipment_status": Path("orderedmap/item/equipment_status.json"),
        "ability_soul": Path("orderedmap/ability/ability_soul.json"),
        "mana_board": Path("orderedmap/generated/mana_board.json"),
        "mana_node": Path("orderedmap/mana_board/mana_node.json"),
        "level_required_mana_node": Path("orderedmap/mana_board/level_required_mana_node.json"),
    }
    for relative in wf_paths.values():
        if not (wf_assets_root / relative).is_file():
            raise FileNotFoundError(f"CN asset source is missing: {wf_assets_root / relative}")

    quest_number = int(quest_id)
    chapter_key = str(quest_number // 1_000_000)
    stage_key = str((quest_number // 1000) % 1000)
    quest_key = str(quest_number % 1000)
    main_master = load_json(wf_assets_root / wf_paths["main_quest"])
    quest_rows = main_master[chapter_key][stage_key][quest_key]
    if len(quest_rows) != 1 or quest_rows[0][0] != quest_id:
        raise ValueError("CN main quest row lookup is ambiguous")
    row = quest_rows[0]
    emulator_paths = verify_emulator_projection(repo_root, quest_id, row)

    enemy_level = int(row[108])
    field_data_id = row[109]
    field_data_master = load_json(wf_assets_root / wf_paths["field_data"])
    field_data_rows = field_data_master[field_data_id]
    if len(field_data_rows) != 1:
        raise ValueError("field-data lookup is ambiguous")
    field_id, terrain_asset, zone_master_id = field_data_rows[0]

    field_master = load_json(wf_assets_root / wf_paths["field"])
    field_rows = field_master[field_id]
    if len(field_rows) != 1:
        raise ValueError("field lookup is ambiguous")
    field_assets = [value for value in field_rows[0] if option_value(value) is not None]

    zone_master = load_json(wf_assets_root / wf_paths["zone"])[zone_master_id]
    zone_action_master = load_json(wf_assets_root / wf_paths["zone_action"]).get(zone_master_id, {})
    zones = []
    for zone_key in sorted(zone_master, key=int):
        zone_rows = zone_master[zone_key]
        if len(zone_rows) != 1:
            raise ValueError(f"zone {zone_key} lookup is ambiguous")
        zones.append(parse_zone(int(zone_key), zone_rows[0], zone_action_master.get(zone_key, [])))

    required_enemy_kinds: dict[str, set[str]] = {}
    for zone in zones:
        for emitter in zone["zako_emitters"]:
            required_enemy_kinds.setdefault(emitter["enemy_id"], set()).add("zako")
        for boss in zone["bosses"] + zone["multiplayer_bosses"]:
            required_enemy_kinds.setdefault(boss["enemy_id"], set()).add(boss["kind"])
    missing_adapters = sorted(set(required_enemy_kinds) - set(GENERAL_ENEMY_ADAPTERS))
    if missing_adapters:
        raise ValueError(f"unsupported enemy adapters for {quest_id}: {missing_adapters}")
    unsupported_kinds = sorted(
        {
            kind
            for kinds in required_enemy_kinds.values()
            for kind in kinds
            if kind not in {"zako", "general_boss"}
        }
    )
    if unsupported_kinds:
        raise ValueError(f"unsupported enemy kinds for {quest_id}: {unsupported_kinds}")

    character_master = load_json(wf_assets_root / wf_paths["character"])
    character_status_master = load_json(wf_assets_root / wf_paths["character_status"])
    character_level_master = load_json(wf_assets_root / wf_paths["character_level"])
    evolution_status_master = load_json(wf_assets_root / wf_paths["evolution_status"])
    character_text_master = load_json(wf_assets_root / wf_paths["character_text"])
    action_skill_master = load_json(wf_assets_root / wf_paths["action_skill"])
    ability_master = load_json(wf_assets_root / wf_paths["ability"])
    equipment_master = load_json(wf_assets_root / wf_paths["equipment"])
    equipment_status_master = load_json(wf_assets_root / wf_paths["equipment_status"])
    ability_soul_master = load_json(wf_assets_root / wf_paths["ability_soul"])
    mana_board_master = load_json(wf_assets_root / wf_paths["mana_board"])
    mana_node_master = load_json(wf_assets_root / wf_paths["mana_node"])
    required_level_master = load_json(wf_assets_root / wf_paths["level_required_mana_node"])
    equipments: dict[str, dict[str, Any]] = {}
    for equipment_id in DEFAULT_EQUIPMENT_IDS:
        equipment_row = equipment_master[equipment_id][0]
        status_curve = {level: {"hp": int(rows[0][0]), "atk": int(rows[0][1])} for level, rows in equipment_status_master[equipment_id].items()}
        equipments[equipment_id] = {
            "id": equipment_id, "asset_id": equipment_row[0], "name": equipment_row[1],
            "kind": "weapon" if equipment_row[2] == "0" else "orb", "max_level": int(equipment_row[8]),
            "ability_soul_id": str(equipment_row[10]), "rarity": int(equipment_row[11]),
            "status_curve": status_curve, "ability_soul": normalize_ability_soul_rows(ability_soul_master.get(str(equipment_row[10]), [])),
        }
    characters: dict[str, dict[str, Any]] = {}
    player_skill_source_paths: list[tuple[str, Path]] = []
    for character_id in DEFAULT_PARTY_IDS:
        character_rows = character_master.get(character_id, [])
        status_rows = character_status_master.get(character_id, {}).get("1", [])
        text_rows = character_text_master.get(character_id, [])
        if len(character_rows) != 1 or len(status_rows) != 1 or len(text_rows) != 1:
            raise ValueError(f"default party character lookup is ambiguous: {character_id}")
        character_row = character_rows[0]
        status_row = status_rows[0]
        text_row = text_rows[0]
        hp = int(status_row[0])
        atk = int(status_row[1])
        status_curve = {level: {"hp": int(rows[0][0]), "atk": int(rows[0][1])} for level, rows in character_status_master[character_id].items()}
        exp_curve_id = str(character_row[1])
        exp_curve = {level: int(rows[0][0]) for level, rows in character_level_master[exp_curve_id].items()}
        evolution_row = evolution_status_master[str(character_row[2])][0]
        skill, skill_source = player_skill_record(wf_assets_root, action_skill_master, str(character_row[0]))
        ability_ids = [str(value) for value in character_row[19:25] if value]
        abilities = normalize_character_abilities(ability_master, ability_ids)
        required_levels = required_level_master[str(character_row[2])][0]
        mana_boards: dict[str, list[dict[str, Any]]] = {}
        for board_id, board_nodes in mana_board_master[character_id].items():
            normalized_nodes: list[dict[str, Any]] = []
            for node_index, board_rows in board_nodes.items():
                board_row = board_rows[0]
                node_row = mana_node_master[character_id][board_id][node_index][0]
                effect_code = int(node_row[5]) if node_row[1] == "0" else -1
                slot = int(node_row[6]) if effect_code == 0 and node_row[6] else 0
                required_level = None
                if effect_code == 0 and slot > 0 and required_levels[slot - 1] != "(None)": required_level = int(required_levels[slot - 1])
                elif effect_code in [1, 2] and required_levels[6] != "(None)": required_level = int(required_levels[6])
                item_ids = [int(v) for v in node_row[2].split(",") if v]
                item_counts = [int(v) for v in node_row[3].split(",") if v]
                normalized_nodes.append({
                    "id": str(node_row[0]), "board_id": int(board_id), "index": int(node_index),
                    "parent_id": None if board_row[5] == "(None)" else str(board_row[5]),
                    "kind": "episode" if node_row[1] == "1" else "ability",
                    "required_items": dict(zip([str(v) for v in item_ids], item_counts, strict=True)),
                    "required_mana": int(node_row[4]), "effect_kind": {0: "ability", 1: "action_skill_level", 2: "action_skill_evolution"}.get(effect_code, "episode"),
                    "ability_slot": slot, "required_level": required_level,
                })
            mana_boards[board_id] = normalized_nodes
        player_skill_source_paths.append(skill_source)
        characters[character_id] = {
            "id": character_id,
            "asset_id": character_row[0],
            "name": text_row[0],
            "level": 1,
            "rarity": int(character_row[2]),
            "element": int(character_row[3]),
            "gender": character_row[7],
            "races": [value for value in character_row[4].split(",") if value],
            "speciality": character_row[26],
            "hp": hp,
            "atk": atk,
            "main_hp": hp,
            "unison_hp": 0,
            "main_atk": atk,
            "unison_atk": 0,
            "max_level": max(int(level) for level in status_curve),
            "status_curve": status_curve,
            "exp_curve_id": exp_curve_id,
            "exp_curve": exp_curve,
            "evolution_bonus": {"atk_1": int(evolution_row[0]), "hp_1": int(evolution_row[1]), "atk_2": int(evolution_row[2]), "hp_2": int(evolution_row[3])},
            "skill": skill,
            "ability_ids": ability_ids,
            "abilities": abilities,
            "mana_boards": mana_boards,
        }

    (
        party_atk,
        basic_curves,
        correction_curves,
        party_hp,
        atk_basic_curves,
        atk_correction_curves,
        apk_bundle_names,
    ) = read_apk_curve_tables(apk_path)
    general_zako_master = load_json(wf_assets_root / wf_paths["general_zako"])
    zako_level_master = load_json(wf_assets_root / wf_paths["zako_level"])
    general_boss_master = load_json(wf_assets_root / wf_paths["general_boss"])
    boss_level_master = load_json(wf_assets_root / wf_paths["boss_level"])
    general_boss_state_master = load_json(wf_assets_root / wf_paths["general_boss_state"])

    zako_rows: dict[str, list[str]] = {}
    boss_rows: dict[str, list[str]] = {}
    action_path_set: set[str] = set()
    for enemy_id in sorted(required_enemy_kinds):
        kinds = required_enemy_kinds[enemy_id]
        if "zako" in kinds:
            zako_rows[enemy_id] = threshold_row(general_zako_master[enemy_id], enemy_level)
            action_path_set.update(action_paths_from_row(zako_rows[enemy_id]))
        if "general_boss" in kinds:
            boss_rows[enemy_id] = threshold_row(general_boss_master[enemy_id], enemy_level)
            action_path_set.update(action_paths_from_row(boss_rows[enemy_id]))

    action_records_by_id: dict[str, dict[str, Any]] = {}
    action_sources_by_id: dict[str, tuple[str, Path]] = {}

    def add_action_asset(logical_path: str) -> None:
        if logical_path in action_records_by_id:
            return
        record, source = action_asset_record(wf_assets_root, logical_path)
        action_records_by_id[logical_path] = record
        action_sources_by_id[logical_path] = source

    for logical_path in sorted(action_path_set):
        add_action_asset(logical_path)

    funnel_specs: dict[str, dict[str, Any]] = {}
    scanned_action_ids: set[str] = set()
    while True:
        pending_action_ids = sorted(set(action_records_by_id) - scanned_action_ids)
        if not pending_action_ids:
            break
        for action_id in pending_action_ids:
            scanned_action_ids.add(action_id)
            for runtime in action_records_by_id[action_id]["runtime"]:
                if runtime["kind"] != "spawn_funnel":
                    continue
                if runtime["enemy_kind"] != "zako":
                    raise ValueError(f"unsupported funnel enemy kind: {runtime}")
                funnel_enemy_id = runtime["enemy_id"]
                if funnel_enemy_id not in GENERAL_ENEMY_ADAPTERS:
                    raise ValueError(f"unsupported funnel enemy adapter: {funnel_enemy_id}")
                previous = funnel_specs.get(funnel_enemy_id)
                if previous is not None and int(previous["level"]) != int(runtime["level"]):
                    raise ValueError(f"multiple funnel levels are unsupported: {funnel_enemy_id}")
                funnel_specs[funnel_enemy_id] = runtime
                if funnel_enemy_id not in zako_rows:
                    zako_rows[funnel_enemy_id] = threshold_row(
                        general_zako_master[funnel_enemy_id],
                        enemy_level,
                    )
                for logical_path in action_paths_from_row(zako_rows[funnel_enemy_id]):
                    add_action_asset(logical_path)

    action_assets = [
        action_records_by_id[logical_path]
        for logical_path in sorted(action_records_by_id)
    ]
    action_source_paths = [
        action_sources_by_id[logical_path]
        for logical_path in sorted(action_sources_by_id)
    ]

    variable_master: dict[str, Any] = {}
    variable_master_consumed = False
    enemies: dict[str, dict[str, Any]] = {}
    all_enemy_ids = sorted(set(required_enemy_kinds) | set(funnel_specs))
    for enemy_id in all_enemy_ids:
        kinds = required_enemy_kinds.get(enemy_id, set())
        needs_zako_data = "zako" in kinds or enemy_id in funnel_specs
        zako_level_row: list[str] = []
        zako_actions: list[str] = []
        if needs_zako_data:
            zako_level_row = zako_level_master[enemy_id][0]
            zako_actions = action_paths_from_row(zako_rows[enemy_id])
            if not zako_actions:
                raise ValueError(f"general zako has no action asset: {enemy_id}")

        if "zako" in kinds:
            zako_row = zako_rows[enemy_id]
            zako_hp, zako_hp_formula = calculate_hit_hp(
                enemy_level,
                zako_level_row,
                party_atk,
                basic_curves,
                correction_curves,
                float(row[98]),
            )
            zako_atk, zako_atk_formula = calculate_enemy_atk(
                enemy_level,
                zako_level_row,
                party_hp,
                atk_basic_curves,
                atk_correction_curves,
                float(row[101]),
            )
            enemies[f"{enemy_id}_zako"] = {
                "master_id": enemy_id,
                "kind": "zako",
                "level": enemy_level,
                "max_hp": zako_hp,
                "hp_formula": zako_hp_formula,
                "atk": zako_atk,
                "atk_formula": zako_atk_formula,
                "pixel_art_by_element": dict(zip(ELEMENT_NAMES, zako_row[2:8], strict=True)),
                "initial_position_name": zako_row[16],
                "routine_id": zako_row[17],
                "initial_state_id": zako_row[18],
                "action_assets": zako_actions,
                "action_schedule": {
                    "status": "minimum deterministic adapter pending the complete general_zako state-machine port",
                    "initial_delay_frames": 180,
                    "interval_frames": 300,
                    "sequence": [zako_actions[0]],
                },
            }

        if enemy_id in funnel_specs:
            funnel_level = int(funnel_specs[enemy_id]["level"])
            funnel_hp, funnel_hp_formula = calculate_hit_hp(
                funnel_level,
                zako_level_row,
                party_atk,
                basic_curves,
                correction_curves,
                float(row[99]),
            )
            funnel_atk, funnel_atk_formula = calculate_enemy_atk(
                funnel_level,
                zako_level_row,
                party_hp,
                atk_basic_curves,
                atk_correction_curves,
                float(row[102]),
            )
            enemies[f"{enemy_id}_funnel"] = {
                "master_id": enemy_id,
                "kind": "funnel",
                "level": funnel_level,
                "max_hp": funnel_hp,
                "hp_formula": funnel_hp_formula,
                "atk": funnel_atk,
                "atk_formula": funnel_atk_formula,
                "action_assets": zako_actions,
                "action_schedule": {
                    "status": "minimum orbiting-funnel adapter pending the complete general_funnel state-machine port",
                    "initial_delay_frames": 120,
                    "interval_frames": 180,
                    "sequence": [zako_actions[0]],
                },
            }

        if "general_boss" in kinds:
            boss_row = boss_rows[enemy_id]
            boss_level_row = boss_level_master[enemy_id][0]
            boss_actions = action_paths_from_row(boss_row)
            boss_hp, boss_hp_formula = calculate_hit_hp(
                enemy_level,
                boss_level_row,
                party_atk,
                basic_curves,
                correction_curves,
                float(row[97]),
            )
            boss_atk, boss_atk_formula = calculate_enemy_atk(
                enemy_level,
                boss_level_row,
                party_hp,
                atk_basic_curves,
                atk_correction_curves,
                float(row[100]),
            )
            routine_id = boss_row[42]
            state_difficulty = GENERAL_ENEMY_ADAPTERS[enemy_id]["state_difficulty"]
            routine_states = general_boss_state_master[routine_id][state_difficulty]
            uses_variables = any(
                state_rows[0][46] in {"6", "7", "8"}
                for state_rows in routine_states.values()
            )
            selected_variables: dict[str, float] = {}
            if uses_variables:
                if not variable_master:
                    variable_path = wf_assets_root / GENERAL_BOSS_VARIABLE_PATH
                    if not variable_path.is_file():
                        raise FileNotFoundError(f"CN asset source is missing: {variable_path}")
                    variable_master = load_json(variable_path)
                    variable_master_consumed = True
                selected_variables = select_general_boss_variables(
                    variable_master,
                    routine_id,
                    enemy_level,
                )
            boss_state_machine = normalize_general_boss_state_machine(
                routine_id,
                boss_row[43],
                state_difficulty,
                general_boss_state_master,
                boss_actions,
                selected_variables,
            )
            enemies[f"{enemy_id}_boss"] = {
                "master_id": enemy_id,
                "kind": "general_boss",
                "level": enemy_level,
                "max_hp": boss_hp,
                "hp_formula": boss_hp_formula,
                "atk": boss_atk,
                "atk_formula": boss_atk_formula,
                "display_name_by_element": dict(zip(ELEMENT_NAMES, boss_row[3:15:2], strict=True)),
                "pixel_art_by_element": dict(zip(ELEMENT_NAMES, boss_row[4:15:2], strict=True)),
                "initial_position_name": boss_row[41],
                "routine_id": routine_id,
                "initial_state_id": boss_row[43],
                "action_assets": boss_actions,
                "action_state_machine": boss_state_machine,
            }

    terrain_markers = {
        marker_name: marker_position.copy()
        for marker_name, marker_position in FALLBACK_TERRAIN_MARKERS.items()
        if marker_name in {"p1", "p2", "p3"}
    }
    for enemy_definition in enemies.values():
        state_machine = enemy_definition.get("action_state_machine", {})
        for state in state_machine.get("states", {}).values():
            termination = state.get("termination", {})
            if termination.get("kind") != "move":
                continue
            marker_name = str(termination.get("target", ""))
            if marker_name not in FALLBACK_TERRAIN_MARKERS:
                raise ValueError(f"missing fallback terrain marker: {marker_name}")
            terrain_markers.setdefault(
                marker_name,
                FALLBACK_TERRAIN_MARKERS[marker_name].copy(),
            )

    terrain_logical_path = f"{terrain_asset}.amf3.deflate"
    terrain_hashed_path = hashed_asset_path(terrain_logical_path)
    terrain_bundle_entry = f"production/android_bundle/{terrain_hashed_path}"

    source_files: list[dict[str, str]] = []
    for display, source_path in emulator_paths:
        source_files.append({"role": "service_emulator", "path": display, "sha256": sha256(source_path)})
    for role, relative in wf_paths.items():
        source_path = wf_assets_root / relative
        source_files.append({"role": f"cn_master_{role}", "path": relative.as_posix(), "sha256": sha256(source_path)})
    if variable_master_consumed:
        variable_path = wf_assets_root / GENERAL_BOSS_VARIABLE_PATH
        source_files.append({
            "role": "cn_master_general_boss_variable",
            "path": GENERAL_BOSS_VARIABLE_PATH.as_posix(),
            "sha256": sha256(variable_path),
        })
    for display, source_path in action_source_paths:
        source_files.append({"role": "cn_action_dsl", "path": display, "sha256": sha256(source_path)})
    for display, source_path in player_skill_source_paths:
        source_files.append({"role": "cn_player_skill_dsl", "path": display, "sha256": sha256(source_path)})
    source_files.append({"role": "client_apk", "path": apk_path.name, "sha256": sha256(apk_path)})

    cn_resource_version = (wf_assets_root / wf_paths["version"]).read_text(encoding="utf-8").strip()

    representative_enemy_id = ""
    representative_enemy_kind = ""
    for zone in zones:
        if zone["zako_emitters"]:
            representative_enemy_id = zone["zako_emitters"][0]["enemy_id"]
            representative_enemy_kind = "zako"
            break
        if zone["bosses"]:
            representative_enemy_id = zone["bosses"][0]["enemy_id"]
            representative_enemy_kind = zone["bosses"][0]["kind"]
            break
    if not representative_enemy_id:
        raise ValueError(f"quest has no representative enemy: {quest_id}")
    representative_suffix = "boss" if representative_enemy_kind == "general_boss" else representative_enemy_kind
    representative_source_key = f"{representative_enemy_id}_{representative_suffix}"
    representative_definition = enemies[representative_source_key]

    return {
        "schema_version": 2,
        "id": quest_id,
        "category": CATEGORY,
        "name": row[1],
        "entry_stamina": int(row[69]),
        "clear_reward_id": int(row[3]),
        "score_reward_group_id": int(row[70]),
        "rank_times_ms": {
            "b": round(float(row[84]) * 1000),
            "a": round(float(row[85]) * 1000),
            "s": round(float(row[86]) * 1000),
            "s_plus": round(float(row[87]) * 1000),
        },
        "character_exp": int(row[94]),
        "pool_exp": int(row[96]),
        "rewards": {"free_mana": int(row[95]), "free_vmoney": 0},
        "battle": {
            "field_data_id": field_data_id,
            "field_id": field_id,
            "terrain_asset": terrain_asset,
            "terrain_logical_path": terrain_logical_path,
            "terrain_hashed_path": terrain_hashed_path,
            "terrain_present_in_apk_bundle": terrain_bundle_entry in apk_bundle_names,
            "zone_master_id": zone_master_id,
            "bgm_prefix": row[110],
            "time_limit_frames": int(row[111]),
            "enemy_level": enemy_level,
            "recommended_element": int(row[72]),
            "quest_rank": int(row[107]),
            "hp_corrections": {
                "boss": float(row[97]),
                "zako": float(row[98]),
                "funnel": float(row[99]),
            },
            "atk_corrections": {
                "boss": float(row[100]),
                "zako": float(row[101]),
                "funnel": float(row[102]),
            },
            "tp_corrections": {
                "boss": float(row[103]),
                "zako": float(row[104]),
                "funnel": float(row[105]),
            },
            "field_assets": field_assets,
        },
        "zones": zones,
        "enemies": enemies,
        "characters": characters,
        "equipments": equipments,
        "battle_source_defaults": {
            "default_party": DEFAULT_PARTY_IDS,
            "player_role_kind": 1,
            "player_rank": 1,
            "degree_id": 1,
            "allow_heal_from_other_players": True,
            "battle_behavior_data": {
                "skill_ability_behavior_mode": 1,
                "dash_behavior_mode": 1,
            },
            "direct_attack_reference_atk": sum(character["atk"] for character in characters.values()),
            "skill_point_gain_per_direct_attack": 50,
            "skill_point_gain_status": "deterministic adapter pending exact member skill-point gain event recovery",
            "power_flip_combo_thresholds": [9, 15, 39],
            "default_ability_levels": {character_id: {ability_id: 1 for ability_id in characters[character_id]["ability_ids"][:3]} for character_id in DEFAULT_PARTY_IDS},
        },
        "action_assets": action_assets,
        "arena": {
            "width": 720,
            "height": 1280,
            "gravity_y": 980.0,
            "floor_y": 1180.0,
            "collision_status": "fallback walls pending recovery of the verified terrain AMF3 binary",
        },
        "terrain_runtime": {
            "status": "fallback",
            "source": "hand-authored adapter pending recovery of the verified terrain AMF3 binary",
            "segments": [
                {"id": "lower-left-slope", "start": [80.0, 1040.0], "end": [250.0, 1120.0], "restitution": 0.9},
                {"id": "lower-right-slope", "start": [470.0, 1120.0], "end": [640.0, 1040.0], "restitution": 0.9},
            ],
            "markers": terrain_markers,
        },
        "enemy": {
            "id": representative_enemy_id,
            "source_enemy_key": representative_source_key,
            "kind": representative_enemy_kind,
            "level": int(representative_definition["level"]),
            "max_hp": int(representative_definition["max_hp"]),
            "radius": 36.0,
            "position": [360.0, 280.0],
            "placement_status": "representative first-zone spawn pending terrain object coordinates",
        },
        "source": {
            "client_version": f"CN APK 1.8.1; CN resource {cn_resource_version}",
            "cn_master_repository": "https://github.com/blead/wf-assets-cn",
            "cn_master_revision": git_revision(wf_assets_root),
            "battle_fixture_status": "canonical CN quest/field/zone/enemy/action graph; terrain collision geometry remains unavailable",
            "files": source_files,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--wf-assets-root", type=Path, required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--quest-id", default=DEFAULT_QUEST_ID)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    fixture = build_fixture(
        args.repo_root.resolve(),
        args.wf_assets_root.resolve(),
        args.apk.resolve(),
        args.quest_id,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(fixture, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
