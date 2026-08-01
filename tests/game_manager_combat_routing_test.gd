extends SceneTree

const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const EventScene = preload("res://scenes/game/event.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_monster_victory_resolves_event_and_unlocks_exploration()
	await _test_retreat_preserves_monster_hp_and_removes_the_real_tail_card()
	await _test_defeat_emits_failure_and_keeps_exploration_locked()
	await _test_shop_event_is_ignored_by_combat_routing()
	quit(0 if _failure_count == 0 else 1)


func _test_monster_victory_resolves_event_and_unlocks_exploration() -> void:
	var manager := await _make_game_manager()
	if not _require_combat_signals(manager):
		_cleanup_manager(manager)
		return

	var board: Board = manager.board
	var event_node := _attach_encounter_event(board, EventData.EventType.MONSTER, Vector2i(3, 0), 2, [])
	var started: Array[MobInstance] = []
	var outcomes: Array[CombatResult] = []
	manager.connect("combat_started", func(_instance, monster): started.append(monster))
	manager.connect("combat_resolved", func(_instance, result): outcomes.append(result))

	_expect(_place_card(manager, _horizontal_card_center(board, Vector2i(0, 0)), 90.0, CardData.CardType.ROOT, 0) != null, "victory setup places root")
	_expect(_place_card(manager, _horizontal_card_center(board, Vector2i(2, 0)), 90.0, CardData.CardType.NORMAL, 2) != null, "victory setup places weapon")

	_expect(event_node.event_instance.is_resolved, "victory resolves the encounter event")
	_expect(started.size() == 1, "victory emits one combat-start signal")
	_expect(outcomes.size() == 1, "victory emits one combat result")
	_expect(
		outcomes.size() == 1 and outcomes[0].outcome == CombatResult.Outcome.VICTORY,
		"victory result has VICTORY outcome"
	)
	_expect(not manager.drag_layer.is_interaction_locked(), "victory unlocks exploration")
	_cleanup_manager(manager)


func _test_retreat_preserves_monster_hp_and_removes_the_real_tail_card() -> void:
	var manager := await _make_game_manager()
	if not _require_combat_signals(manager):
		_cleanup_manager(manager)
		return

	manager.player_stats = _make_stats(10, 10, 0, 0)
	var board: Board = manager.board
	var event_node := _attach_encounter_event(
		board,
		EventData.EventType.MONSTER,
		Vector2i(5, 0),
		20,
		[_action(MobAction.Type.ATTACK, 3), _action(MobAction.Type.DEFEND, 5)]
	)
	var outcomes: Array[CombatResult] = []
	manager.connect("combat_resolved", func(_instance, result): outcomes.append(result))

	_expect(_place_card(manager, _horizontal_card_center(board, Vector2i(0, 0)), 90.0, CardData.CardType.ROOT, 0) != null, "retreat setup places root")
	_expect(_place_card(manager, _horizontal_card_center(board, Vector2i(2, 0)), 90.0, CardData.CardType.NORMAL, 3) != null, "retreat setup places first weapon")
	var tail := _place_card(manager, _horizontal_card_center(board, Vector2i(4, 0)), 90.0, CardData.CardType.NORMAL, 1)
	_expect(tail != null, "retreat setup places tail weapon")

	var runtime_state := event_node.event_instance.runtime_state as EncounterRuntimeState
	_expect(not event_node.event_instance.is_resolved, "retreat leaves the encounter unresolved")
	_expect(outcomes.size() == 1, "retreat emits one combat result")
	_expect(
		outcomes.size() == 1 and outcomes[0].outcome == CombatResult.Outcome.RETREAT,
		"retreat result has RETREAT outcome"
	)
	_expect(manager.player_stats.hp == 10, "retreat restores the player HP from before combat")
	_expect(runtime_state.mob_instance.stats.hp == 16, "retreat persists monster HP damage")
	_expect(runtime_state.mob_instance.stats.defense == 0, "retreat clears monster encounter defense")
	_expect(board.cards.size() == 2, "retreat removes one board tail card")
	_expect(tail not in board.cards, "retreat removes the actual final CardEntity from Board")
	_expect(tail.card_instance.cur_zone == CardInstance.ZONE.DISCARD, "retreat moves the removed tail instance to discard")
	_expect(tail not in manager.card_entities, "retreat removes discarded tail entity from manager ownership")
	_expect(tail.card_instance not in manager.cards_inst, "retreat removes discarded tail instance from manager ownership")
	_expect(not manager.drag_layer.is_interaction_locked(), "retreat unlocks exploration")
	_cleanup_manager(manager)


func _test_defeat_emits_failure_and_keeps_exploration_locked() -> void:
	var manager := await _make_game_manager()
	if not _require_combat_signals(manager):
		_cleanup_manager(manager)
		return

	manager.player_stats = _make_stats(10, 10, 0, 0)
	var board: Board = manager.board
	var event_node := _attach_encounter_event(
		board, EventData.EventType.BOSS, Vector2i(3, 0), 20, [_action(MobAction.Type.ATTACK, 10)]
	)
	var failures: Array[CombatResult] = []
	manager.connect("exploration_failed", func(result): failures.append(result))

	_expect(_place_card(manager, _horizontal_card_center(board, Vector2i(0, 0)), 90.0, CardData.CardType.ROOT, 0) != null, "defeat setup places root")
	_expect(_place_card(manager, _horizontal_card_center(board, Vector2i(2, 0)), 90.0, CardData.CardType.NORMAL, 1) != null, "defeat setup places weapon")

	_expect(not event_node.event_instance.is_resolved, "defeat does not resolve the encounter event")
	_expect(failures.size() == 1, "defeat emits one exploration failure")
	_expect(
		failures.size() == 1 and failures[0].outcome == CombatResult.Outcome.DEFEAT,
		"defeat result has DEFEAT outcome"
	)
	_expect(manager.player_stats.hp == 0, "defeat persists player HP at zero")
	_expect(manager.player_stats.defense == 0, "defeat clears player encounter defense")
	_expect(manager.drag_layer.is_interaction_locked(), "defeat keeps exploration locked")
	_cleanup_manager(manager)


func _test_shop_event_is_ignored_by_combat_routing() -> void:
	var manager := await _make_game_manager()
	if not _require_combat_signals(manager):
		_cleanup_manager(manager)
		return

	var board: Board = manager.board
	var event_node := _attach_non_combat_event(board, EventData.EventType.SHOP, Vector2i(1, 0))
	var results: Array[CombatResult] = []
	manager.connect("combat_resolved", func(_instance, result): results.append(result))

	_expect(_place_card(manager, _horizontal_card_center(board, Vector2i(1, 0)), 90.0, CardData.CardType.ROOT, 0) != null, "shop setup places root over shop")

	_expect(not event_node.event_instance.is_resolved, "shop remains unresolved after overlap")
	_expect(results.is_empty(), "shop overlap does not emit a combat result")
	_expect(not manager.drag_layer.is_interaction_locked(), "shop overlap does not lock exploration")
	_cleanup_manager(manager)


func _make_game_manager() -> Node:
	var manager := GameManagerScene.instantiate()
	root.add_child(manager)
	await process_frame
	for event_node in manager.board.events.duplicate():
		manager.board.remove_event(event_node)
	return manager


func _require_combat_signals(manager: Node) -> bool:
	var available := true
	for signal_name in ["combat_started", "combat_resolved", "exploration_failed"]:
		var exists: bool = manager.has_signal(signal_name)
		_expect(exists, "GameManager exposes %s signal" % signal_name)
		available = available and exists
	return available


func _attach_encounter_event(
	board: Board,
	event_type: EventData.EventType,
	origin: Vector2i,
	monster_hp: int,
	actions: Array[MobAction]
) -> BoardEvent:
	var content: EncounterEventContent = (MonsterEventContent.new() if event_type == EventData.EventType.MONSTER else BossEventContent.new())
	content.mob = _make_mob(monster_hp, actions)
	return _attach_event(board, event_type, origin, content)


func _attach_non_combat_event(board: Board, event_type: EventData.EventType, origin: Vector2i) -> BoardEvent:
	return _attach_event(board, event_type, origin, EventContent.new())


func _attach_event(board: Board, event_type: EventData.EventType, origin: Vector2i, content: EventContent) -> BoardEvent:
	var data := EventData.new()
	data.event_id = "routing-%s" % EventData.EventType.keys()[event_type].to_lower()
	data.event_type = event_type
	data.content = content
	var instance := data.create_instance()
	instance.origin = origin
	var event_node := EventScene.instantiate() as BoardEvent
	event_node.setup(instance, board.cell_size)
	_expect(board.attach_event(event_node), "routing test event attaches to board")
	return event_node


func _horizontal_card_center(board: Board, left_cell: Vector2i) -> Vector2:
	var right_cell := left_cell + Vector2i.RIGHT
	return board.to_local(
		(board.grid_to_world_center(left_cell) + board.grid_to_world_center(right_cell)) / 2.0
	)


func _place_card(
	manager: Node,
	local_position: Vector2,
	rotation: float,
	card_type: CardData.CardType,
	damage: int
) -> CardEntity:
	var data := CardData.new()
	data.card_type = card_type
	data.damage = damage
	var instance := CardInstance.new(data)
	var card := CardEntityScene.instantiate() as CardEntity
	card.bind_instance(instance)
	card.drag_layer = manager.drag_layer
	root.add_child(card)
	card.global_position = manager.board.to_global(local_position)
	card.rotation_degrees = rotation
	manager.cards_inst.append(instance)
	manager.card_entities.append(card)
	if not manager.board.add_card(card):
		_expect(false, "test card can be added to Board")
	return card


func _make_mob(hp: int, actions: Array[MobAction]) -> MobData:
	var stats := CombatStatsData.new()
	stats.max_hp = hp
	var mob := MobData.new()
	mob.mob_name = "Routing Test Mob"
	mob.base_stats = stats
	mob.actions = actions
	return mob


func _make_stats(max_hp: int, hp: int, attack: int, defense: int) -> CombatStats:
	var stats := CombatStats.new()
	stats.max_hp = max_hp
	stats.hp = hp
	stats.attack = attack
	stats.defense = defense
	return stats


func _action(type: MobAction.Type, value: int) -> MobAction:
	var action := MobAction.new()
	action.type = type
	action.value = value
	return action


func _cleanup_manager(manager: Node) -> void:
	if is_instance_valid(manager):
		manager.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)