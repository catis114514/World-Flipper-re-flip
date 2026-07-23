extends RefCounted

const ProfileFactory = preload("res://src/domain/profile_factory.gd")
const OfflineGameService = preload("res://src/domain/offline_game_service.gd")
const OfflineCatalogRepository = preload("res://src/content/offline_catalog_repository.gd")

func run(t) -> void:
    var service = OfflineGameService.new()
    var profile = ProfileFactory.create_default()
    profile.stamina_state = {"stored_value": 40, "heal_anchor_unix": 1000}
    t.assert_equal(service.settle_stamina(profile, 2500), 45, "stamina recovers from persisted anchor")
    t.assert_true(service.spend_stamina(profile, 6, 2500), "stamina spend succeeds atomically")
    t.assert_equal(profile.stamina_state["stored_value"], 39, "stamina spend updates state")
    profile.stamina_state = {"stored_value": 50, "heal_anchor_unix": 1000}
    t.assert_true(service.spend_stamina(profile, 6, 10000), "full stamina can be spent")
    t.assert_equal(profile.stamina_state["heal_anchor_unix"], 10000, "spending from cap resets the recovery anchor")
    t.assert_equal(service.settle_stamina(profile, 10001), 44, "time spent at cap cannot be reclaimed after spending")
    t.assert_true(service.save_party(profile, [121002, 141005]), "owned unique party is accepted")
    t.assert_equal(profile.party, [121002, 141005], "party order is persisted")
    t.assert_true(not service.save_party(profile, [121002, 121002]), "duplicate party member is rejected")
    var catalog = OfflineCatalogRepository.new()
    t.assert_equal(catalog.load_catalog("res://content/catalogs/offline_catalogs.json"), OK, "gacha test catalog loads")
    var before := int(profile.currencies["free_vmoney"])
    var result := service.draw_gacha(profile, catalog.get_gacha("1"), 10, "draw-1")
    t.assert_equal(result.get("results", []).size(), 10, "ten draw returns ten rewards")
    t.assert_equal(profile.currencies["free_vmoney"], before - 1500, "draw cost is deducted once")
    var replay := service.draw_gacha(profile, catalog.get_gacha("1"), 10, "draw-1")
    t.assert_equal(replay, result, "operation ledger makes draw idempotent")
    t.assert_equal(profile.currencies["free_vmoney"], before - 1500, "idempotent replay does not charge twice")
    t.assert_equal(service.draw_gacha(profile, catalog.get_gacha("1"), 1, "draw-1"), {}, "operation id conflict with different draw parameters is rejected")
    var malformed := catalog.get_gacha("1")
    malformed["pool"]["1"] = []
    t.assert_equal(service.draw_gacha(profile, malformed, 1, "bad-pool"), {}, "empty rank pool is rejected before mutation")
    t.assert_true(result["results"][0].has("play_movie"), "each draw independently records the optional special movie")
    t.assert_true(service.add_inbox_reward(profile, "launch-gift", "离线补偿", {"free_mana": 100}), "inbox accepts a unique reward grant")
    var before_mana := int(profile.currencies["free_mana"])
    var claimed := service.claim_inbox_reward(profile, "launch-gift", "claim-1")
    t.assert_equal(claimed["rewards"]["free_mana"], 100, "inbox reward is returned")
    t.assert_equal(profile.currencies["free_mana"], before_mana + 100, "inbox reward is granted once")
    t.assert_equal(service.claim_inbox_reward(profile, "launch-gift", "claim-1"), claimed, "inbox operation is idempotent")
    t.assert_equal(profile.currencies["free_mana"], before_mana + 100, "inbox replay does not duplicate rewards")
    var next := _next(service, catalog, profile)
    t.assert_equal(next["id"], "1001001", "progression starts at the first CN story")
    t.assert_equal(next["resolved_chapter"]["name"], "第1章精灵的乐园", "resolved quest carries original chapter metadata")
    t.assert_equal(next["resolved_stage_node"]["id"], 1001, "resolved quest carries the original multiplied stage-node ID")
    var story := service.complete_story(profile, next, "story-1001001")
    t.assert_equal(story["quest_id"], "1001001", "story completion returns the canonical quest")
    t.assert_equal(_next(service, catalog, profile)["id"], "1001002", "story completion unlocks the first battle")
    t.assert_equal(service.complete_story(profile, next, "story-1001001"), story, "story completion is idempotent")
    profile.quest_progress["1001002"] = {"cleared": true, "clear_count": 1}
    var after_battle := _next(service, catalog, profile)
    t.assert_equal(after_battle["id"], "1001003", "clearing the first battle resolves the following story")
    t.assert_equal(service.complete_story(profile, after_battle, "story-1001003")["quest_id"], "1001003", "following story completes locally")
    t.assert_equal(_next(service, catalog, profile)["id"], "1002001", "original stage-node chain advances to the next battle")

func _next(service, catalog, profile) -> Dictionary:
    return service.get_next_main_quest(
        catalog.chapters,
        catalog.stage_nodes,
        catalog.quests,
        profile.quest_progress,
        profile.roster,
        2000000000
    )
