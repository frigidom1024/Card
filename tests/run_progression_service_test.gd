extends SceneTree

const RunProgressionConfigScript := preload("res://scripts/game/run/run_progression_config.gd")
const RunProgressionServiceScript := preload("res://scripts/game/run/run_progression_service.gd")
const CardDataScript := preload("res://scripts/card/card_data.gd")
const BoardPlacementResultScript := preload("res://scripts/game/board_placement_result.gd")

var _failure_count := 0

func _init() -> void:
    call_deferred("_run_tests")

func _run_tests() -> void:
    _test_action_count_ignores_guide()
    _test_rarity_weights_progress_with_actions()
    _test_card_availability_follows_weight()
    quit(1 if _failure_count > 0 else 0)

func _test_action_count_ignores_guide() -> void:
    var service := RunProgressionServiceScript.new()
    service.configure(RunProgressionConfigScript.new())
    var guide := BoardPlacementResultScript.new(
        BoardPlacementResult.Kind.GUIDE_RESOLVED, null, null, [], []
    )
    _expect(not service.record_player_action(guide), "GUIDE placement does not count as an action")
    _expect(service.get_action_count() == 0, "GUIDE placement keeps action count at zero")
    var normal := BoardPlacementResultScript.new(
        BoardPlacementResult.Kind.CHAIN_EXTENDED, null, null, [], []
    )
    _expect(service.record_player_action(normal), "ordinary placement records an action")
    _expect(service.get_action_count() == 1, "ordinary placement increments action count")

func _test_rarity_weights_progress_with_actions() -> void:
    var service := RunProgressionServiceScript.new()
    service.configure(RunProgressionConfigScript.new())
    var common := CardDataScript.new()
    common.rarity = CardData.Rarity.COMMON
    var rare := CardDataScript.new()
    rare.rarity = CardData.Rarity.RARE
    _expect(service.get_card_rarity_weight(common) == 100, "early common weight is 100")
    _expect(service.get_card_rarity_weight(rare) == 0, "early rare weight is locked")
    service.set_action_count(4)
    _expect(service.get_card_rarity_weight(rare) > 0, "rare unlocks at the configured action threshold")
    _expect(service.get_card_rarity_weight(rare) < service.get_card_rarity_weight(common), "common remains more likely than rare at first unlock")

func _test_card_availability_follows_weight() -> void:
    var service := RunProgressionServiceScript.new()
    service.configure(RunProgressionConfigScript.new())
    var card := CardDataScript.new()
    card.rarity = CardData.Rarity.EPIC
    _expect(not service.is_card_available(card), "epic card is unavailable early")
    service.set_action_count(8)
    _expect(service.is_card_available(card), "epic card becomes available after progression")

func _expect(condition: bool, message: String) -> void:
    if not condition:
        _failure_count += 1
        push_error(message)
