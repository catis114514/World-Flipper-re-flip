#!/usr/bin/env python3
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "godot/content/catalogs/offline_catalogs.json"

def sha256():
    return hashlib.sha256(OUTPUT.read_bytes()).hexdigest()

subprocess.run(["python3", str(ROOT / "godot/tools/convert_offline_catalogs.py")], check=True)
first = sha256()
subprocess.run(["python3", str(ROOT / "godot/tools/convert_offline_catalogs.py")], check=True)
assert sha256() == first, "offline catalog conversion must be deterministic"
data = json.loads(OUTPUT.read_text(encoding="utf-8"))
assert data["schema_version"] == 2
assert data["counts"] == {
    "chapters": 12,
    "stage_nodes": 139,
    "quests": 419,
    "characters": 505,
    "equipments": 436,
    "gacha_banners": 584,
    "gacha_pools": 581,
}
assert data["chapters"][0]["name"] == "第1章精灵的乐园"
assert data["chapters"][0]["stage_node_ids"][0] == 1001
assert data["stage_nodes"]["1"][1]["need_stage_node_id"] == "1001"
assert data["quests"]["1001002"]["stage_node_id"] == 1001
assert data["quests"]["1001002"]["viewable_prerequisite_ids"] == ["1001001"]
assert data["quests"]["1001002"]["kind"] == "battle"
assert data["gacha_banners"]["1699"]["has_projected_pool"] is False
assert data["characters"]["141005"]["name"] == "西微"
assert data["equipments"]["100001"]["name"] == "精灵的微笑"
print("offline catalog converter checks passed", first)
