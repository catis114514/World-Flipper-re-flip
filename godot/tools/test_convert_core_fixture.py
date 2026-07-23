#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CONVERTER = PROJECT_ROOT / "godot/tools/convert_core_fixture.py"
CHECKED_FIXTURES = {
    "1001002": PROJECT_ROOT / "godot/content/fixtures/quest_1001002.json",
    "1002001": PROJECT_ROOT / "godot/content/fixtures/quest_1002001.json",
}
DEFAULT_WF_ASSETS = Path(os.environ.get("WF_ASSETS_CN_ROOT", "/home/codex/work/wf-assets-cn"))
DEFAULT_APK = Path(os.environ.get("WF_CLIENT_APK", "/home/codex/work/client-v1.8.1.apk"))


class ConvertCoreFixtureTest(unittest.TestCase):
    def load_converter_module(self):
        spec = importlib.util.spec_from_file_location("convert_core_fixture_test_module", CONVERTER)
        if spec is None or spec.loader is None:
            self.fail("converter module spec is unavailable")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def run_converter(self, output: Path, quest_id: str = "1001002") -> None:
        subprocess.run(
            [
                sys.executable,
                str(CONVERTER),
                "--repo-root",
                str(PROJECT_ROOT),
                "--wf-assets-root",
                str(DEFAULT_WF_ASSETS),
                "--apk",
                str(DEFAULT_APK),
                "--quest-id",
                quest_id,
                "--output",
                str(output),
            ],
            check=True,
        )

    def test_converter_matches_checked_golden_fixture(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "quest_1001002.json"
            self.run_converter(output)
            self.assertEqual(output.read_bytes(), CHECKED_FIXTURES["1001002"].read_bytes())

    def test_second_quest_converter_matches_checked_golden_fixture(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "quest_1002001.json"
            self.run_converter(output, "1002001")
            self.assertEqual(output.read_bytes(), CHECKED_FIXTURES["1002001"].read_bytes())

    def test_fixture_contains_canonical_cn_battle_graph(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "quest_1001002.json"
            self.run_converter(output)
            fixture = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual(fixture["schema_version"], 2)
        self.assertEqual(fixture["battle"]["field_data_id"], "tutorial_main_1_1_2")
        self.assertEqual(fixture["battle"]["field_id"], "tree_grass01_1_2")
        self.assertEqual(
            fixture["battle"]["terrain_asset"],
            "battle/terrain/main_quest/chapter_01/main_chapter_01_01_02",
        )
        self.assertEqual(fixture["battle"]["enemy_level"], 12)
        self.assertEqual(fixture["zones"][0]["objective"], {"kind": "zako_kill", "count": 18})
        self.assertEqual(fixture["zones"][0]["zako_emitters"][0], {"enemy_id": "slango", "interval_frames": 60})
        self.assertEqual(fixture["zones"][1]["bosses"][0], {"enemy_id": "slango", "kind": "general_boss"})
        self.assertEqual(fixture["enemies"]["slango_zako"]["max_hp"], 148)
        self.assertEqual(fixture["enemies"]["slango_boss"]["max_hp"], 13009)
        self.assertEqual(fixture["enemies"]["slango_zako"]["atk"], 19)
        self.assertEqual(fixture["enemies"]["slango_boss"]["atk"], 30)
        self.assertEqual(fixture["enemies"]["slango_funnel"]["level"], 15)
        self.assertEqual(fixture["enemies"]["slango_funnel"]["max_hp"], 132)
        self.assertEqual(fixture["enemies"]["slango_funnel"]["atk"], 23)
        state_machine = fixture["enemies"]["slango_boss"]["action_state_machine"]
        self.assertEqual(state_machine["initial_state_id"], "neutral1")
        self.assertEqual(len(state_machine["states"]), 36)
        self.assertEqual(state_machine["states"]["neutral1"]["termination"], {"kind": "time", "value": 30})
        self.assertEqual(state_machine["states"]["neutral1"]["next_state"], "funnel1_start1")
        self.assertEqual(
            state_machine["states"]["funnel_fire1"]["action_id"],
            "battle/action/enemy/action/general_boss/boss_slango$difficulity10_funnel_shot1_single",
        )
        self.assertEqual(fixture["enemy"]["id"], "slango")
        self.assertEqual(fixture["enemy"]["max_hp"], 148)
        self.assertTrue(fixture["action_assets"])
        action_by_id = {action["id"]: action for action in fixture["action_assets"]}
        zako_shot = action_by_id["battle/action/enemy/action/zako/zako_slango$difficulity10_shot1"]["runtime"][0]
        self.assertEqual(zako_shot["distribution"], {"kind": "single", "count": 1, "spread_radians": 0.0})
        self.assertEqual(zako_shot["radius"], 12.0)
        self.assertEqual(zako_shot["speed_per_frame"], 10.0)
        self.assertEqual(zako_shot["attack_multiplier"], 0.9)
        self.assertEqual(fixture["battle_source_defaults"]["default_party"], ["141005", "121002", "131004"])
        self.assertEqual(fixture["battle_source_defaults"]["direct_attack_reference_atk"], 30)
        self.assertEqual(fixture["characters"]["141005"]["name"], "西微")
        self.assertEqual(fixture["characters"]["141005"]["hp"], 52)
        self.assertEqual(fixture["characters"]["141005"]["atk"], 11)
        self.assertNotIn("migration_enemy", json.dumps(fixture))
        self.assertNotIn("migration harness", json.dumps(fixture))

    def test_second_fixture_contains_spirit_and_multi_emitter_graph(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "quest_1002001.json"
            self.run_converter(output, "1002001")
            fixture = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual(fixture["id"], "1002001")
        self.assertEqual(fixture["name"], "追蘑菇1")
        self.assertEqual(fixture["battle"]["field_data_id"], "main_1_2_1")
        self.assertEqual(fixture["battle"]["field_id"], "tree_grass01_2_1")
        self.assertEqual(
            fixture["battle"]["terrain_asset"],
            "battle/terrain/main_quest/chapter_01/main_chapter_01_02_01",
        )
        self.assertEqual(fixture["zones"][0]["objective"], {"kind": "zako_kill", "count": 20})
        self.assertEqual(
            fixture["zones"][0]["zako_emitters"],
            [
                {"enemy_id": "slango", "interval_frames": 60},
                {"enemy_id": "spirit", "interval_frames": 120},
            ],
        )
        self.assertEqual(
            fixture["zones"][1]["bosses"],
            [{"enemy_id": "spirit", "kind": "general_boss"}],
        )
        self.assertEqual(fixture["enemies"]["slango_zako"]["max_hp"], 148)
        self.assertEqual(fixture["enemies"]["spirit_zako"]["max_hp"], 742)
        self.assertEqual(fixture["enemies"]["spirit_zako"]["atk"], 26)
        self.assertEqual(fixture["enemies"]["spirit_funnel"]["level"], 3)
        self.assertEqual(fixture["enemies"]["spirit_funnel"]["max_hp"], 101)
        self.assertEqual(fixture["enemies"]["spirit_funnel"]["atk"], 5)
        self.assertEqual(fixture["enemies"]["spirit_boss"]["max_hp"], 18295)
        self.assertEqual(fixture["enemies"]["spirit_boss"]["atk"], 36)
        state_machine = fixture["enemies"]["spirit_boss"]["action_state_machine"]
        self.assertEqual(state_machine["initial_state_id"], "neutral1")
        self.assertEqual(len(state_machine["states"]), 31)
        self.assertEqual(
            state_machine["states"]["skill1_charge1"]["termination"],
            {"kind": "time", "value": 240, "source_variable": "charge1"},
        )
        self.assertEqual(state_machine["states"]["move3"]["next_state"], "neutral1")
        action_by_id = {action["id"]: action for action in fixture["action_assets"]}
        spirit_zako = action_by_id[
            "battle/action/enemy/action/zako/zako_spirit$difficulity10_shot1_dark"
        ]["runtime"][0]
        self.assertEqual(
            spirit_zako["distribution"],
            {"kind": "n_way", "count": 3, "spread_radians": 1.0471975511965976},
        )
        spirit_skill = action_by_id[
            "battle/action/enemy/action/general_boss/boss_spirit$difficulity10_skill_shot1"
        ]["runtime"]
        self.assertEqual([pattern["distribution"]["count"] for pattern in spirit_skill], [3, 6, 8])
        self.assertEqual([pattern["attack_multiplier"] for pattern in spirit_skill], [2.75, 2.75, 2.75])

    def test_delayed_enemy_action_is_rejected_until_runtime_scheduling_exists(self) -> None:
        converter = self.load_converter_module()
        delayed_spawn = [
            "Event",
            ["Wait", 5, None, ["Command", ["SpawnFunnel"]]],
        ]
        with self.assertRaisesRegex(ValueError, "delayed enemy action command"):
            converter.normalize_action_runtime(delayed_spawn)


if __name__ == "__main__":
    unittest.main()
