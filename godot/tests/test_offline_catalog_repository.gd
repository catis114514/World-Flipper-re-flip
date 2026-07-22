extends RefCounted

const OfflineCatalogRepository = preload("res://src/content/offline_catalog_repository.gd")

func run(t) -> void:
    var repository = OfflineCatalogRepository.new()
    t.assert_equal(repository.load_catalog("res://content/catalogs/offline_catalogs.json"), OK, "offline CN catalog loads")
    t.assert_equal(repository.quests.size(), 419, "all CN main quests are cataloged")
    t.assert_equal(repository.characters.size(), 505, "all CN characters are cataloged")
    t.assert_equal(repository.equipments.size(), 436, "all CN equipments are cataloged")
    t.assert_equal(repository.gacha_banners.size(), 584, "all CN gacha banners are cataloged")
    t.assert_equal(repository.gachas.size(), 581, "all available projected gacha pools are cataloged")
    t.assert_equal(repository.quests["1001002"]["kind"], "battle", "CN battle quest kind uses the correct source column")
    t.assert_true(repository.gacha_banners.has("1699"), "latest CN holiday banner is not lost by the projected pool source")
    t.assert_equal(repository.get_character("141005")["name"], "西微", "starter character uses CN text")
    t.assert_equal(repository.get_equipment("100001")["name"], "精灵的微笑", "chapter orb uses CN text")
    t.assert_true(repository.get_gacha("1").has("pool"), "gacha pool entries are available offline")
