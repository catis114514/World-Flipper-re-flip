extends RefCounted

const OfflineCatalogRepository = preload("res://src/content/offline_catalog_repository.gd")

func run(t) -> void:
    var repository = OfflineCatalogRepository.new()
    t.assert_equal(repository.load_catalog("res://content/catalogs/offline_catalogs.json"), OK, "offline CN catalog loads")
    t.assert_equal(repository.chapters.size(), 12, "all CN main chapters are cataloged")
    t.assert_equal(repository.counts["stage_nodes"], 139, "all CN main stage nodes are cataloged")
    t.assert_equal(repository.quests.size(), 419, "all CN main quests are cataloged")
    t.assert_equal(repository.characters.size(), 505, "all CN characters are cataloged")
    t.assert_equal(repository.equipments.size(), 436, "all CN equipments are cataloged")
    t.assert_equal(repository.gacha_banners.size(), 584, "all CN gacha banners are cataloged")
    t.assert_equal(repository.gachas.size(), 581, "all available projected gacha pools are cataloged")
    t.assert_equal(repository.chapters[0]["name"], "第1章精灵的乐园", "chapter metadata comes from the CN chapter master")
    t.assert_equal(repository.stage_nodes["1"][0]["id"], 1001, "stage-node multiplied IDs use the original x1000 contract")
    t.assert_equal(repository.stage_nodes["1"][1]["need_stage_node_id"], "1001", "stage-node visibility keeps its original predecessor")
    t.assert_equal(repository.quests["1001002"]["viewable_prerequisite_ids"], ["1001001"], "quest viewability keeps the original clear requirement")
    t.assert_equal(repository.quests["1001002"]["kind"], "battle", "CN battle quest kind uses the correct source column")
    t.assert_true(repository.gacha_banners.has("1699"), "latest CN holiday banner is not lost by the projected pool source")
    t.assert_equal(repository.get_character("141005")["name"], "西微", "starter character uses CN text")
    t.assert_equal(repository.get_equipment("100001")["name"], "精灵的微笑", "chapter orb uses CN text")
    t.assert_true(repository.get_gacha("1").has("pool"), "gacha pool entries are available offline")
    var malformed_path := "user://malformed_offline_catalog.json"
    var malformed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/catalogs/offline_catalogs.json"))
    malformed["stage_nodes"]["1"][1]["need_stage_node_id"] = "999999"
    var malformed_file := FileAccess.open(malformed_path, FileAccess.WRITE)
    malformed_file.store_string(JSON.stringify(malformed))
    malformed_file.close()
    t.assert_equal(OfflineCatalogRepository.new().load_catalog(malformed_path), ERR_INVALID_DATA, "missing stage-node prerequisites reject the entire catalog")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(malformed_path))
