extends SceneTree

const RibwoodEventLib = preload("res://data/levels/ribwood/event_lib.tres")
const EventDataScript = preload("res://scripts/game/event/core/event_data.gd")
const ShopEventContentScript = preload("res://scripts/game/event/shop/shop_event_content.gd")
const TreasureEventContentScript = preload("res://scripts/game/event/treasure/treasure_event_content.gd")
const EncounterEventContentScript = preload("res://scripts/game/event/encounter/encounter_event_content.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_event_library_contains_only_ribwood_events()
	_test_event_entries_are_singletons()
	_test_content_is_scoped_to_ribwood()
	quit(1 if _failure_count > 0 else 0)


func _test_event_library_contains_only_ribwood_events() -> void:
	_expect(RibwoodEventLib != null, "Ribwood EventLib loads")
	var ids: Array[String] = []
	for entry in RibwoodEventLib.entries:
		if entry != null and entry.event_data != null:
			ids.append(entry.event_data.event_id)
	var expected := [
		"ribwood_marrow_lamp",
		"ribwood_marrow_rat",
		"ribwood_broken_banner_shop",
		"ribwood_fallen_rib_wolf",
		"ribwood_bone_stitcher",
		"ribwood_white_horn_hart",
	]
	_expect(ids.size() == expected.size(), "Ribwood EventLib has exactly six entries")
	for event_id in expected:
		_expect(event_id in ids, "Ribwood EventLib includes %s" % event_id)


func _test_event_entries_are_singletons() -> void:
	for entry in RibwoodEventLib.entries:
		_expect(entry != null, "Ribwood EventLib has no null entry")
		if entry == null:
			continue
		_expect(entry.min_count == 1 and entry.max_count == 1, "each Ribwood event is generated once")


func _test_content_is_scoped_to_ribwood() -> void:
	var monster_count := 0
	for entry in RibwoodEventLib.entries:
		if entry == null or entry.event_data == null:
			continue
		var content := entry.event_data.content
		_expect(content != null, "%s has content" % entry.event_data.event_id)
		if entry.event_data.event_type == EventDataScript.EventType.MONSTER:
			monster_count += 1
			_expect(content is EncounterEventContentScript, "%s uses encounter content" % entry.event_data.event_id)
		if content is ShopEventContentScript:
			for item in content.items:
				_expect(item != null and item.card_data != null, "shop item has a Ribwood card")
				if item != null and item.card_data != null:
					_expect(item.card_data.resource_path.begins_with("res://data/levels/ribwood/"), "shop card is scoped to Ribwood")
		if content is TreasureEventContentScript:
			for card in content.card_rewards:
				_expect(card != null and card.resource_path.begins_with("res://data/levels/ribwood/"), "treasure card is scoped to Ribwood")
	_expect(monster_count == 2, "Ribwood EventLib has two ordinary monster templates")
	_expect(RibwoodEventLib.get_templates_of_type(EventDataScript.EventType.BOSS).size() == 1, "Ribwood EventLib has one boss template")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
