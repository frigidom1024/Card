extends SceneTree

const CombatStatsDataScript = preload("res://scripts/combat/combat_stats_data.gd")
const CombatStatsScript = preload("res://scripts/combat/combat_stats.gd")
const MobDataScript = preload("res://scripts/game/event/mob_data.gd")
const PlayerDataScript = preload("res://scripts/player/player_data.gd")
const MobActionScript = preload("res://scripts/game/event/mob_action.gd")
const CardDataScript = preload("res://scripts/card/card_data.gd")
const BoardEventScene = preload("res://scenes/game/event.tscn")

var _failure_count := 0

func _init() -> void:
	var data = CombatStatsDataScript.new()
	data.max_hp = 10
	data.attack = 3
	data.defense = 2

	var stats = CombatStatsScript.new()
	stats.reset_from_data(data)
	_expect(stats.hp == 10, "new runtime stats start at maximum HP")
	_expect(stats.attack == 3, "runtime attack copies base attack")
	_expect(stats.take_damage(5) == 3, "defense absorbs two damage")
	_expect(stats.hp == 7, "only unabsorbed damage reduces HP")
	stats.heal(99)
	_expect(stats.hp == 10, "healing cannot exceed maximum HP")
	stats.add_defense(4)
	stats.modify_attack(-1)
	_expect(stats.defense == 4, "damage consumes existing defense before new defense is added")
	_expect(stats.attack == 2, "attack modifiers use the shared runtime API")

	var mob_data = MobDataScript.new()
	mob_data.base_stats = data
	var first = mob_data.create_instance()
	var second = mob_data.create_instance()
	first.take_damage(12)
	_expect(not first.is_alive(), "first encounter can be defeated")
	_expect(second.is_alive(), "second encounter has independent runtime HP")
	_expect(second.stats.hp == 10, "definition resources are not mutated by encounters")

	var player_data = PlayerDataScript.new()
	player_data.base_stats = data
	var player_stats = CombatStatsScript.new()
	player_stats.reset_from_data(player_data.base_stats)
	_expect(player_stats.take_damage(2) == 0, "player stats use the same defense rule as monsters")
	_expect(player_stats.is_alive(), "player stats use the same alive-state API as monsters")

	var wolf = load("res://data/event/mobs/wolf_mob.tres") as MobData
	_expect(wolf != null, "wolf resource loads")
	if wolf:
		_expect(wolf.base_stats != null, "wolf resource includes inline base stats")
		_expect(wolf.create_instance().is_alive(), "loaded wolf creates a valid encounter")

	_expect_mob("res://data/event/mobs/rotwood_gnawer_mob.tres", "Rotwood Gnawer", 8, 2, 0, 1, 0)
	_expect_mob("res://data/event/mobs/wolf_mob.tres", "Forest Wolf", 12, 3, 1, 2, 0)
	_expect_mob("res://data/event/mobs/miasma_shadow_lizard_mob.tres", "Miasma Shadow Lizard", 16, 4, 1, 4, 0)
	_expect_mob("res://data/event/mobs/miasma_grove_guardian_boss.tres", "Miasma Grove Guardian", 30, 5, 2, 16, 1)
	var guardian = load("res://data/event/mobs/miasma_grove_guardian_boss.tres") as MobData
	if guardian and guardian.card_rewards.size() == 1:
		var boss_card = guardian.card_rewards[0] as CardDataScript
		_expect(boss_card != null and boss_card.card_name == "World Tree Branch Cleaver", "boss reward is WorldTreeBranchCleaver")

	var event_lib = load("res://data/event/event_lib.tres") as EventLib
	_expect(event_lib != null, "enemy event library loads")
	if event_lib:
		var expected_event_ids := [
			"rotwood_gnawer",
			"forest_wolf",
			"miasma_shadow_lizard",
			"miasma_grove_guardian",
		]
		var expected_event_types := [
			EventData.EventType.MONSTER,
			EventData.EventType.MONSTER,
			EventData.EventType.MONSTER,
			EventData.EventType.BOSS,
		]
		var expected_mob_resource_paths := [
			"res://data/event/mobs/rotwood_gnawer_mob.tres",
			"res://data/event/mobs/wolf_mob.tres",
			"res://data/event/mobs/miasma_shadow_lizard_mob.tres",
			"res://data/event/mobs/miasma_grove_guardian_boss.tres",
		]
		_expect(event_lib.entries.size() == expected_event_ids.size(), "enemy event library configures four fixed roster entries")
		if event_lib.entries.size() == expected_event_ids.size():
			for index in range(expected_event_ids.size()):
				var entry: EventEntry = event_lib.entries[index]
				var expected_event_id: String = expected_event_ids[index]
				_expect(entry != null, "configured roster entry %d is present" % (index + 1))
				if entry:
					_expect(entry.min_count == 1, "%s entry has a minimum count of one" % expected_event_id)
					_expect(entry.max_count == 1, "%s entry has a maximum count of one" % expected_event_id)
					var configured_event: EventData = entry.event_data
					_expect(configured_event != null, "%s entry has event data" % expected_event_id)
					if configured_event:
						_expect(configured_event.event_id == expected_event_id, "%s configured event has expected roster ID" % expected_event_id)
						_expect(configured_event.event_type == expected_event_types[index], "%s configured event has correct type" % expected_event_id)
						_expect(configured_event.size == Vector2i.ONE, "%s configured event uses default one-cell size" % expected_event_id)
						var configured_content = configured_event.content as EventMonsterContent
						_expect(configured_content != null, "%s configured event has monster content" % expected_event_id)
						if configured_content:
							_expect(configured_content.count == 1, "%s configured content spawns one mob" % expected_event_id)
							_expect(configured_content.mob != null, "%s configured content resolves its mob" % expected_event_id)
							if configured_content.mob:
								_expect(configured_content.mob.resource_path == expected_mob_resource_paths[index], "%s configured content maps to the expected mob resource" % expected_event_id)

		var generated_events = event_lib.generate_event_datas()
		_expect(generated_events.size() == expected_event_ids.size(), "enemy event library generates four fixed events")
		if generated_events.size() == expected_event_ids.size():
			for index in range(expected_event_ids.size()):
				var generated_event: EventData = generated_events[index]
				var expected_event_id: String = expected_event_ids[index]
				_expect(generated_event != null, "generated event %d is present" % (index + 1))
				if generated_event:
					_expect(generated_event.event_id == expected_event_id, "generated event %d has expected roster ID" % (index + 1))
					_expect(generated_event.event_type == expected_event_types[index], "%s generated event has correct type" % expected_event_id)
					var generated_content = generated_event.content as EventMonsterContent
					_expect(generated_content != null, "%s generated event has monster content" % expected_event_id)
					if generated_content:
						_expect(generated_content.count == 1, "%s generated event spawns one mob" % expected_event_id)
						_expect(generated_content.mob != null, "%s generated event resolves its mob" % expected_event_id)
						if generated_content.mob:
							_expect(generated_content.mob.resource_path == expected_mob_resource_paths[index], "%s generated event maps to the expected mob resource" % expected_event_id)
	call_deferred("_run_deferred_tests")

	var card = load("res://data/cards/AllThingsRevival.tres")
	_expect(card != null, "migrated card resource loads")
	if card:
		_expect(int(card.get("card_id")) == 28, "migrated card data preserves its ID")

func _expect_mob(
	resource_path: String,
	expected_name: String,
	expected_hp: int,
	expected_attack: int,
	expected_defense: int,
	expected_gold: int,
	expected_reward_count: int
) -> void:
	var mob = load(resource_path) as MobData
	_expect(mob != null, "%s loads" % resource_path)
	if mob == null:
		return
	_expect(mob.mob_name == expected_name, "%s keeps its display name" % resource_path)
	_expect(mob.base_stats != null, "%s has inline base stats" % resource_path)
	if mob.base_stats:
		_expect(mob.base_stats.max_hp == expected_hp, "%s has expected HP" % resource_path)
		_expect(mob.base_stats.attack == expected_attack, "%s has expected attack" % resource_path)
		_expect(mob.base_stats.defense == expected_defense, "%s has expected defense" % resource_path)
	_expect(mob.gold_reward == expected_gold, "%s has expected gold reward" % resource_path)
	_expect(mob.actions.size() == 1, "%s has one action" % resource_path)
	if mob.actions.size() == 1:
		_expect(mob.actions[0].type == MobActionScript.Type.ATTACK, "%s action is attack" % resource_path)
		_expect(mob.actions[0].value == expected_attack, "%s action value matches attack" % resource_path)
	_expect(mob.card_rewards.size() == expected_reward_count, "%s has expected fixed reward count" % resource_path)
	_expect(mob.create_instance().is_alive(), "%s creates a live encounter" % resource_path)


func _run_deferred_tests() -> void:
	_test_board_event_binding()
	_finish_tests()


func _test_board_event_binding() -> void:
	var template := EventData.new()
	template.event_id = "forest_wolf"
	template.event_type = EventData.EventType.MONSTER
	template.size = Vector2i(2, 1)
	var instance := template.create_instance(Vector2i(2, 3))
	var board_event := BoardEventScene.instantiate() as BoardEvent
	root.add_child(board_event)
	_expect(board_event.event_instance != null, "unconfigured board events bind a preview instance")
	if board_event.event_instance:
		_expect(board_event.event_instance.template.event_id == "forest_wolf", "preview instance uses the forest wolf event")
	_expect(board_event.position == Vector2(160, 160), "preview event honors its configured board origin")
	_expect(board_event.size == Vector2(80, 80), "preview event uses one visible board cell")

	var preview_property_names: Array[StringName] = []
	for property in board_event.get_property_list():
		preview_property_names.append(property.name)
	_expect(&"preview_event" in preview_property_names, "scene preview event can be selected in the inspector")
	_expect(&"preview_origin" in preview_property_names, "scene preview origin can be adjusted in the inspector")
	_expect(&"preview_cell_size" in preview_property_names, "scene preview cell size can be adjusted in the inspector")

	var configured_preview := BoardEventScene.instantiate() as BoardEvent
	var configured_preview_data := EventData.new()
	configured_preview_data.event_id = "wide_preview"
	configured_preview_data.size = Vector2i(2, 1)
	configured_preview.set("preview_event", configured_preview_data)
	configured_preview.set("preview_origin", Vector2i(3, 1))
	configured_preview.set("preview_cell_size", 64)
	root.add_child(configured_preview)
	_expect(configured_preview.event_instance != null and configured_preview.event_instance.template == configured_preview_data, "scene preview uses its selected event data")
	_expect(configured_preview.position == Vector2(192, 64), "scene preview honors its configured origin and cell size")
	_expect(configured_preview.size == Vector2(128, 64), "scene preview size follows the selected event data")
	configured_preview.queue_free()

	var name_bar := board_event.get_node_or_null("NameBar") as ColorRect
	var type_badge := board_event.get_node_or_null("TypeBadge") as Label
	var icon := board_event.get_node("Icon") as TextureRect
	var type_label := board_event.get_node("TypeLabel") as Label
	var name_label := board_event.get_node("NameLabel") as Label
	_expect(name_bar != null, "event cards have a bottom name bar")
	_expect(type_badge != null, "icon-backed event cards have a type badge")
	_expect(name_label.autowrap_mode == TextServer.AUTOWRAP_OFF, "event names stay on one line")
	_expect(name_label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "long event names are truncated with an ellipsis")

	template.icon = GradientTexture2D.new()
	board_event.setup(instance, 80)
	_expect(icon.visible, "event icons are shown when configured")
	_expect(type_badge != null and type_badge.visible, "icon-backed events show a compact type badge")
	_expect(not type_label.visible, "icon-backed events hide the centered fallback marker")

	template.icon = null
	board_event.setup(instance, 80)
	_expect(not icon.visible, "events without icons hide the icon region")
	_expect(type_badge != null and not type_badge.visible, "events without icons hide the compact type badge")
	_expect(type_label.visible, "events without icons show the centered fallback marker")

	var selected_instances: Array[EventInstance] = []
	board_event.event_selected.connect(func(selected: EventInstance) -> void:
		selected_instances.append(selected)
	)
	board_event.event_instance = null
	board_event._refresh()
	board_event.get_node("SelectButton").pressed.emit()
	_expect(selected_instances.is_empty(), "unbound events cannot be selected")
	board_event.setup(instance, 80)
	board_event.get_node("SelectButton").pressed.emit()
	_expect(selected_instances.size() == 1 and selected_instances[0] == instance, "event click emits its runtime instance")
	instance.resolve()
	board_event.setup(instance, 80)
	selected_instances.clear()
	board_event.get_node("SelectButton").pressed.emit()
	_expect(selected_instances.is_empty(), "resolved events cannot be selected again")
	_expect(board_event.get_node("ResolvedOverlay").visible, "resolved events show their completion state")
	_expect(board_event.position == Vector2(160, 240), "event aligns to its board origin")
	_expect(board_event.size == Vector2(160, 80), "event spans its configured board cells")
	_expect(board_event.event_instance == instance, "event keeps the supplied runtime instance")
	board_event.queue_free()

func _finish_tests() -> void:
	quit(1 if _failure_count > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
