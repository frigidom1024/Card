extends SceneTree

const PersistentMarketStateScript := preload("res://scripts/game/market/persistent_market_state.gd")
const RunProgressionConfigScript := preload("res://scripts/game/run/run_progression_config.gd")
const RunProgressionServiceScript := preload("res://scripts/game/run/run_progression_service.gd")
const CardLibraryScript := preload("res://scripts/card/card_lib.gd")
const CardDataScript := preload("res://scripts/card/card_data.gd")

var _failure_count := 0

func _init() -> void:
    call_deferred("_run_tests")

func _run_tests() -> void:
    _test_offers_follow_current_progression_stage()
    quit(1 if _failure_count > 0 else 0)

func _test_offers_follow_current_progression_stage() -> void:
    var config := RunProgressionConfigScript.new()
    config.stage_action_thresholds = [0, 1]
    config.rarity_weights_by_stage = [
        {CardData.Rarity.COMMON: 100, CardData.Rarity.RARE: 0, CardData.Rarity.EPIC: 0, CardData.Rarity.LEGENDARY: 0},
        {CardData.Rarity.COMMON: 0, CardData.Rarity.RARE: 100, CardData.Rarity.EPIC: 0, CardData.Rarity.LEGENDARY: 0},
    ]
    var progression := RunProgressionServiceScript.new()
    _expect(progression.configure(config), "progression configures for market test")
    var library := CardLibraryScript.new()
    library.cards = [_make_card("common", CardData.Rarity.COMMON), _make_card("rare", CardData.Rarity.RARE)]
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    var state := PersistentMarketStateScript.new()
    state.initialize(library, rng, progression)
    _expect(_all_offers_have_rarity(state, CardData.Rarity.COMMON), "initial market only offers common cards")
    progression.set_action_count(1)
    state.refresh_offers()
    _expect(_all_offers_have_rarity(state, CardData.Rarity.RARE), "later market refresh only offers unlocked rare cards")

func _make_card(name: String, rarity: CardData.Rarity) -> CardData:
    var card := CardDataScript.new()
    card.card_name = name
    card.rarity = rarity
    return card

func _all_offers_have_rarity(state, rarity: CardData.Rarity) -> bool:
    for card in state.offers:
        if card == null or card.rarity != rarity:
            return false
    return not state.offers.is_empty()

func _expect(condition: bool, message: String) -> void:
    if not condition:
        _failure_count += 1
        push_error(message)
