#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CN = Path("/home/codex/work/wf-assets-cn/orderedmap")
OUT = ROOT / "godot/content/catalogs/offline_catalogs.json"

def load(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    quest_path = CN / "quest/main_quest.json"
    character_path = CN / "character/character.json"
    text_path = CN / "character/character_text.json"
    equipment_path = CN / "item/equipment.json"
    gacha_path = ROOT / "assets/gacha.json"
    gacha_master_path = CN / "gacha/gacha.json"

    raw_quests = load(quest_path)
    quests = {}
    chapters = []
    stage_nodes = {}
    for chapter_key, chapter_value in sorted(raw_quests.items(), key=lambda pair: int(pair[0])):
        chapters.append({"id": int(chapter_key), "viewable": True})
        nodes = []
        for stage_key, stage_value in sorted(chapter_value.items(), key=lambda pair: int(pair[0])):
            quest_ids = []
            for order_key, rows in sorted(stage_value.items(), key=lambda pair: int(pair[0])):
                for row in rows:
                    quest_id = str(row[0])
                    prerequisite = str(row[10]) if len(row) > 10 and str(row[10]) not in ("", "0", "(None)") else ""
                    quest_kind = int(row[49]) if len(row) > 49 and str(row[49]) not in ("", "(None)") else 0
                    quests[quest_id] = {
                        "id": quest_id,
                        "name": str(row[1]),
                        "chapter_id": int(chapter_key),
                        "stage_node_id": int(chapter_key) * 100 + int(stage_key),
                        "order": int(order_key),
                        "prerequisite_id": prerequisite,
                        "kind": "story" if quest_kind == 0 else ("battle" if quest_kind == 1 else "special_battle"),
                        "viewable": True,
                        "summary": str(row[121]) if len(row) > 121 and quest_kind == 0 else "",
                        "scenario_path": str(row[124]) if len(row) > 124 and quest_kind == 0 else "",
                    }
                    quest_ids.append(quest_id)
            nodes.append({"id": int(chapter_key) * 100 + int(stage_key), "viewable": True, "quest_ids": quest_ids})
        stage_nodes[chapter_key] = nodes

    raw_characters = load(character_path)
    raw_text = load(text_path)
    characters = {}
    for character_id, rows in raw_characters.items():
        row = rows[0]
        text = raw_text.get(character_id, [[""]])[0]
        characters[str(character_id)] = {
            "id": str(character_id), "name": str(text[0]), "rarity": int(row[2]),
            "element": int(row[3]), "race": str(row[4]), "gender": str(row[7]),
            "role": str(row[26]), "skill_name": str(text[4]),
        }

    equipments = {}
    for equipment_id, rows in load(equipment_path).items():
        row = rows[0]
        equipments[str(equipment_id)] = {
            "id": str(equipment_id), "name": str(row[1]),
            "kind": "orb" if str(row[8]) == "1" else "weapon",
            "rarity": int(row[11]), "max_level": int(row[14]),
        }

    gachas = load(gacha_path)
    gacha_banners = {}
    for gacha_id, rows in load(gacha_master_path).items():
        row = rows[0]
        gacha_banners[str(gacha_id)] = {
            "id": str(gacha_id), "asset_id": str(row[0]), "name": str(row[1]),
            "type": int(row[4]), "single_cost": int(row[5]) if str(row[5]).isdigit() else 0,
            "multi_cost": int(row[6]) if str(row[6]).isdigit() else 0,
            "movie_id": str(row[17]), "guarantee_movie_id": str(row[18]),
            "start_at": str(row[29]), "end_at": str(row[30]),
            "has_projected_pool": str(gacha_id) in gachas,
        }
    result = {
        "schema_version": 1,
        "counts": {"quests": len(quests), "characters": len(characters), "equipments": len(equipments), "gacha_banners": len(gacha_banners), "gacha_pools": len(gachas)},
        "chapters": chapters, "stage_nodes": stage_nodes, "quests": quests,
        "characters": characters, "equipments": equipments, "gacha_banners": gacha_banners, "gachas": gachas,
        "source": {
            "cn_master": str(CN.parent),
            "files": {
                str(quest_path): digest(quest_path), str(character_path): digest(character_path),
                str(text_path): digest(text_path), str(equipment_path): digest(equipment_path),
                str(gacha_master_path): digest(gacha_master_path), str(gacha_path): digest(gacha_path),
            },
        },
    }
    expected = {"quests": 419, "characters": 505, "equipments": 436, "gacha_banners": 584, "gacha_pools": 581}
    if result["counts"] != expected:
        raise RuntimeError(f"catalog counts do not match CN sources: {result['counts']} != {expected}")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(json.dumps(result["counts"], ensure_ascii=False))

if __name__ == "__main__":
    main()
