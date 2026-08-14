class_name RunProgressionService
extends RefCounted

## Holds the single run-wide action counter and exposes progression decisions
## without coupling market or exploration to placement details.
signal action_count_changed(action_count: int)

const RunProgressionConfigScript := preload("res://scripts/game/run/run_progression_config.gd")

var _config: RunProgressionConfig
var _action_count := 0


func configure(config: RunProgressionConfig = null) -> bool:
    var resolved_config := config if config != null else RunProgressionConfigScript.new()
    if not resolved_config.validate().is_empty():
        return false
    _config = resolved_config
    _action_count = 0
    return true


func record_player_action(result: BoardPlacementResult) -> bool:
    if result == null or _is_guide_result(result):
        return false
    set_action_count(_action_count + 1)
    return true


func set_action_count(value: int) -> void:
    var clamped_value := maxi(0, value)
    if _action_count == clamped_value:
        return
    _action_count = clamped_value
    action_count_changed.emit(_action_count)


func get_action_count() -> int:
    return _action_count


func get_stage_index() -> int:
    return _config.get_stage_index(_action_count) if _config != null else 0


func get_card_rarity_weight(card_data: CardData) -> int:
    if card_data == null or _config == null:
        return 0
    return _config.get_rarity_weight(card_data.rarity, _action_count)


func is_card_available(card_data: CardData) -> bool:
    return get_card_rarity_weight(card_data) > 0


func _is_guide_result(result: BoardPlacementResult) -> bool:
    if result.kind == BoardPlacementResult.Kind.GUIDE_RESOLVED:
        return true
    var source_card: Card = result.source_card
    var source_inst: CardInstance = (
        source_card.get_card_inst() if source_card != null else null
    )
    return (
        source_inst != null
        and source_inst.card_data != null
        and source_inst.card_data.card_type == CardData.CardType.GUIDE
    )
