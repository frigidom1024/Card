extends SceneTree

const EncounterResolutionCoordinatorPath := "res://scripts/game/event/encounter/encounter_resolution_coordinator.gd"
const BoardScene = preload("res://scenes/game/board.tscn")
const EventScene = preload("res://scenes/game/event.tscn")
const HandScene = preload("res://scenes/game/hand.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const CardManagerScript = preload("res://scripts/game/card_manager.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_victory_resolves_normal_event_and_preserves_monster_hp_snapshot()
	await _test_retreat_returns_tail_temporarily_and_strengthens_same_monster()
	await _test_boss_victory_delegates_removal_to_exploration_coordinator()
	quit(1 if _failure_count > 0 else 0)


func _test_victory_resolves_normal_event_and_preserves_monster_hp_snapshot() -> void:
	var fixture := _create_fixture(EventData.EventType.MONSTER)
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture)
		return
	_expect(
		coordinator.configure(
			fixture.board,
			fixture.player_stats,
			fixture.card_service,
			fixture.exploration,
			Callable(self, "_on_player_state_changed")
		),
		"encounter resolution accepts its runtime dependencies"
	)

	_expect(coordinator.apply(fixture.instance, _result(CombatResult.Outcome.VICTORY, 8, 0)), "victory applies")
	_expect(fixture.instance.is_resolved, "victory resolves an ordinary encounter")
	_expect(fixture.monster.stats.hp == 0, "victory writes monster hp")
	_expect(fixture.player_stats.hp == 8, "victory writes player hp")
	_expect(fixture.player_stats.defense == 0, "victory clears transient player defense")

	await _free_fixture(fixture)


func _test_retreat_returns_tail_temporarily_and_strengthens_same_monster() -> void:
	var fixture := _create_fixture(EventData.EventType.MONSTER)
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture)
		return
	_expect(
		coordinator.configure(
			fixture.board,
			fixture.player_stats,
			fixture.card_service,
			fixture.exploration,
			Callable(self, "_on_player_state_changed")
		),
		"encounter resolution configures before retreat"
	)
	var tail := _place_tail_card(fixture)
	_expect(tail != null, "retreat fixture places an owned tail card")
	fixture.hand_area.max_hand_size = fixture.hand_area.cards.size()

	_expect(coordinator.apply(fixture.instance, _result(CombatResult.Outcome.RETREAT, 7, 16, 1)), "retreat applies")
	_expect(not fixture.instance.is_resolved, "retreat leaves the encounter unresolved")
	_expect(tail in fixture.hand_area.cards, "retreat returns the final card to hand")
	_expect(tail not in fixture.board.cards, "retreat removes the final card from the board")
	_expect(tail.card_instance.cur_zone == CardInstance.ZONE.HAND, "retreat marks the returned card as in hand")
	_expect(fixture.monster.stats.hp == 16, "retreat preserves monster damage")
	_expect(fixture.monster.action_index == 1, "retreat preserves the next monster action")
	_expect(fixture.monster.enhancement_stacks == 1, "retreat strengthens the surviving encounter")

	await _free_fixture(fixture)


func _test_boss_victory_delegates_removal_to_exploration_coordinator() -> void:
	var fixture := _create_fixture(EventData.EventType.BOSS)
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture)
		return
	_expect(
		coordinator.configure(
			fixture.board,
			fixture.player_stats,
			fixture.card_service,
			fixture.exploration,
			Callable(self, "_on_player_state_changed")
		),
		"encounter resolution configures before boss victory"
	)

	_expect(coordinator.apply(fixture.instance, _result(CombatResult.Outcome.VICTORY, 10, 0)), "boss victory applies")
	_expect(fixture.instance.is_resolved, "boss victory resolves the boss instance")
	_expect(fixture.event_node not in fixture.board.events, "boss victory delegates event removal through exploration")

	await _free_fixture(fixture)


func _create_coordinator():
	var coordinator_script = ResourceLoader.load(EncounterResolutionCoordinatorPath)
	_expect(coordinator_script != null, "encounter resolution coordinator script exists")
	return coordinator_script.new() if coordinator_script != null else null


func _create_fixture(event_type: EventData.EventType) -> Dictionary:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	var hand_area := HandScene.instantiate() as HandArea
	root.add_child(hand_area)
	var drag_layer := Node2D.new()
	root.add_child(drag_layer)
	var card_manager := CardManagerScript.new()
	card_manager.card_scene = CardEntityScene
	var card_service := RunCardService.new()
	_expect(card_service.configure(card_manager, hand_area, drag_layer), "fixture configures card ownership")

	var content: EncounterEventContent = MonsterEventContent.new() if event_type == EventData.EventType.MONSTER else BossEventContent.new()
	content.mob = _make_mob(20)
	var data := EventData.new()
	data.event_id = "resolution-%s" % EventData.EventType.keys()[event_type].to_lower()
	data.event_type = event_type
	data.content = content
	var instance := data.create_instance()
	instance.origin = Vector2i(6, 6)
	var monster := EncounterEventResolver.new().begin(instance)
	var event_node := EventScene.instantiate() as BoardEvent
	event_node.setup(instance, board.cell_size)
	_expect(board.attach_event(event_node), "fixture attaches encounter event to board")

	var exploration := ExplorationCoordinator.new()
	_expect(exploration.configure(EventLib.new(), board, ExplorationConfig.new()), "fixture configures exploration facade")
	return {
		"board": board,
		"hand_area": hand_area,
		"drag_layer": drag_layer,
		"card_service": card_service,
		"player_stats": _stats(20, 20, 4),
		"exploration": exploration,
		"instance": instance,
		"monster": monster,
		"event_node": event_node,
	}


func _place_tail_card(fixture: Dictionary) -> CardEntity:
	var root_data := CardData.new()
	root_data.card_type = CardData.CardType.ROOT
	var root_card := CardEntityScene.instantiate() as CardEntity
	root_card.bind_instance(CardInstance.new(root_data))
	root.add_child(root_card)
	root_card.global_position = fixture.board.to_global(_horizontal_card_center(fixture.board, Vector2i(0, 0)))
	root_card.rotation_degrees = 90.0
	if not fixture.board.add_card(root_card):
		return null

	var tail_data := CardData.new()
	tail_data.card_type = CardData.CardType.NORMAL
	if not fixture.card_service.grant_to_hand(tail_data):
		return null
	var tail: CardEntity = fixture.card_service.get_entities().back()
	if not fixture.hand_area.remove_card(tail):
		return null
	tail.global_position = fixture.board.to_global(_horizontal_card_center(fixture.board, Vector2i(2, 0)))
	tail.rotation_degrees = 90.0
	return tail if fixture.board.add_card(tail) else null


func _result(outcome: CombatResult.Outcome, player_hp: int, monster_hp: int, action_index := 0) -> CombatResult:
	return CombatResult.new(outcome, _stats(20, player_hp, 6), _stats(20, monster_hp, 5), [], 0, [], action_index)


func _stats(max_hp: int, hp: int, defense: int) -> CombatStats:
	var stats := CombatStats.new()
	stats.max_hp = max_hp
	stats.hp = hp
	stats.defense = defense
	return stats


func _make_mob(hp: int) -> MobData:
	var stats := CombatStatsData.new()
	stats.max_hp = hp
	var mob := MobData.new()
	mob.mob_name = "Resolution Test Echo"
	mob.base_stats = stats
	return mob


func _horizontal_card_center(board: Board, left_cell: Vector2i) -> Vector2:
	var right_cell := left_cell + Vector2i.RIGHT
	return board.to_local((board.grid_to_world_center(left_cell) + board.grid_to_world_center(right_cell)) / 2.0)


func _on_player_state_changed() -> void:
	pass


func _free_fixture(fixture: Dictionary) -> void:
	var card_service: RunCardService = fixture.card_service
	if card_service != null:
		card_service.clear()
	for node_name in ["board", "hand_area", "drag_layer"]:
		var node = fixture[node_name]
		if is_instance_valid(node):
			node.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)