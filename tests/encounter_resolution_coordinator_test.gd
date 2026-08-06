extends SceneTree

const EncounterResolutionCoordinatorPath := "res://scripts/game/event/encounter/encounter_resolution_coordinator.gd"
const BoardScene = preload("res://scenes/game/board.tscn")
const EventScene = preload("res://scenes/game/event.tscn")
const HandScene = preload("res://scenes/game/hand.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const CardManagerScript = preload("res://scripts/game/card_manager.gd")

var _failure_count := 0
var _player_state_change_count := 0
var _boss_dismissal_count := 0
var _event_display_refresh_count := 0
var _dismissed_instances: Array[EventInstance] = []
var _refreshed_instances: Array[EventInstance] = []
var _active_fixture: Dictionary = {}


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_victory_grants_gold_and_card_then_resolves_normal_event()
	await _test_retreat_returns_tail_and_grants_no_rewards()
	await _test_defeat_grants_no_rewards()
	await _test_boss_victory_reuses_reward_pipeline_before_removal()
	await _test_resolved_victory_cannot_be_applied_twice()
	quit(1 if _failure_count > 0 else 0)


func _test_victory_grants_gold_and_card_then_resolves_normal_event() -> void:
	var fixture := _create_fixture(EventData.EventType.MONSTER)
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture)
		return
	_add_guaranteed_gold_and_card_drops(fixture.content)
	fixture.hand_area.max_hand_size = 0
	_player_state_change_count = 0
	if not _configure_coordinator(coordinator, fixture):
		await _free_fixture(fixture)
		return

	_expect(
		coordinator.apply(fixture.instance, _result(CombatResult.Outcome.VICTORY, 8, 0)),
		"victory applies"
	)
	_expect(fixture.instance.is_resolved, "victory resolves an ordinary encounter")
	_expect(fixture.monster.stats.hp == 0, "victory writes monster hp")
	_expect(fixture.player_stats.hp == 8, "victory writes player hp")
	_expect(fixture.player_stats.defense == 0, "victory clears transient player defense")
	_expect(fixture.player_data.gold == 38, "victory adds guaranteed encounter gold to PlayerData")
	_expect(
		fixture.card_service.get_entities().size() == 1, "victory owns a guaranteed encounter card"
	)
	_expect(
		fixture.card_service.get_entities()[0] in fixture.hand_area.cards,
		"victory keeps a reward card in a full hand"
	)
	_expect(
		fixture.hand_area.max_hand_size == 0,
		"reward card overflow restores the normal hand capacity"
	)
	_expect(
		_player_state_change_count == 1,
		"victory refreshes player state once after HP and rewards change"
	)
	_expect(_boss_dismissal_count == 0, "normal victory does not use the Boss dismissal port")
	_expect(
		_event_display_refresh_count == 1, "normal victory refreshes through the event-display port"
	)
	_expect(
		_refreshed_instances == [fixture.instance],
		"normal victory refreshes its own event instance"
	)

	await _free_fixture(fixture)


func _test_retreat_returns_tail_and_grants_no_rewards() -> void:
	var fixture := _create_fixture(EventData.EventType.MONSTER)
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture)
		return
	_add_guaranteed_gold_and_card_drops(fixture.content)
	_player_state_change_count = 0
	if not _configure_coordinator(coordinator, fixture):
		await _free_fixture(fixture)
		return
	var tail := _place_tail_card(fixture)
	_expect(tail != null, "retreat fixture places an owned tail card")
	fixture.hand_area.max_hand_size = fixture.hand_area.cards.size()

	_expect(
		coordinator.apply(fixture.instance, _result(CombatResult.Outcome.RETREAT, 7, 16, 1)),
		"retreat applies"
	)
	_expect(not fixture.instance.is_resolved, "retreat leaves the encounter unresolved")
	_expect(tail in fixture.hand_area.cards, "retreat returns the final card to hand")
	_expect(tail not in fixture.board.cards, "retreat removes the final card from the board")
	_expect(
		tail.card_instance.cur_zone == CardInstance.ZONE.HAND,
		"retreat marks the returned card as in hand"
	)
	_expect(fixture.monster.stats.hp == 16, "retreat preserves monster damage")
	_expect(fixture.monster.action_index == 1, "retreat preserves the next monster action")
	_expect(fixture.monster.enhancement_stacks == 1, "retreat strengthens the surviving encounter")
	_expect(fixture.player_data.gold == 30, "retreat does not grant encounter gold")
	_expect(
		fixture.card_service.get_entities().size() == 1,
		"retreat does not create encounter reward cards"
	)
	_expect(_player_state_change_count == 1, "retreat refreshes player state once")
	_expect(_boss_dismissal_count == 0, "retreat does not use the Boss dismissal port")
	_expect(_event_display_refresh_count == 1, "retreat refreshes through the event-display port")
	_expect(_refreshed_instances == [fixture.instance], "retreat refreshes its own event instance")

	await _free_fixture(fixture)


func _test_defeat_grants_no_rewards() -> void:
	var fixture := _create_fixture(EventData.EventType.MONSTER)
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture)
		return
	_add_guaranteed_gold_and_card_drops(fixture.content)
	_player_state_change_count = 0
	if not _configure_coordinator(coordinator, fixture):
		await _free_fixture(fixture)
		return

	_expect(
		coordinator.apply(fixture.instance, _result(CombatResult.Outcome.DEFEAT, 0, 14)),
		"defeat applies"
	)
	_expect(not fixture.instance.is_resolved, "defeat does not resolve an encounter as a victory")
	_expect(fixture.player_data.gold == 30, "defeat does not grant encounter gold")
	_expect(
		fixture.card_service.get_entities().is_empty(),
		"defeat does not create encounter reward cards"
	)
	_expect(_player_state_change_count == 1, "defeat refreshes player state once")
	_expect(_boss_dismissal_count == 0, "defeat does not use the Boss dismissal port")
	_expect(_event_display_refresh_count == 0, "defeat does not refresh the event display")

	await _free_fixture(fixture)


func _test_boss_victory_reuses_reward_pipeline_before_removal() -> void:
	var fixture := _create_fixture(EventData.EventType.BOSS)
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture)
		return
	fixture.content.drop_entries.append(_gold_drop(6))
	_player_state_change_count = 0
	if not _configure_coordinator(coordinator, fixture):
		await _free_fixture(fixture)
		return

	_expect(
		coordinator.apply(fixture.instance, _result(CombatResult.Outcome.VICTORY, 10, 0)),
		"boss victory applies"
	)
	_expect(fixture.instance.is_resolved, "boss victory resolves the boss instance")
	_expect(fixture.player_data.gold == 36, "boss victory uses the encounter reward pipeline")
	_expect(
		fixture.event_node not in fixture.board.events,
		"boss victory delegates event removal through the Boss dismissal port"
	)
	_expect(_boss_dismissal_count == 1, "boss victory invokes the Boss dismissal port once")
	_expect(
		_dismissed_instances == [fixture.instance], "boss victory dismisses its own event instance"
	)
	_expect(
		_event_display_refresh_count == 0,
		"boss victory does not refresh through the normal event port"
	)
	_expect(_player_state_change_count == 1, "boss victory refreshes player state once")

	await _free_fixture(fixture)


func _test_resolved_victory_cannot_be_applied_twice() -> void:
	var fixture := _create_fixture(EventData.EventType.MONSTER)
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture)
		return
	_add_guaranteed_gold_and_card_drops(fixture.content)
	_player_state_change_count = 0
	if not _configure_coordinator(coordinator, fixture):
		await _free_fixture(fixture)
		return

	var victory_result := _result(CombatResult.Outcome.VICTORY, 8, 0)
	_expect(coordinator.apply(fixture.instance, victory_result), "initial victory applies")
	var gold_after_first_apply: int = fixture.player_data.gold
	var cards_after_first_apply: int = fixture.card_service.get_entities().size()
	_expect(
		not coordinator.apply(fixture.instance, victory_result),
		"a resolved encounter rejects duplicate settlement"
	)
	_expect(
		fixture.player_data.gold == gold_after_first_apply, "duplicate victory grants no extra gold"
	)
	_expect(
		fixture.card_service.get_entities().size() == cards_after_first_apply,
		"duplicate victory grants no extra cards"
	)
	_expect(_event_display_refresh_count == 1, "duplicate victory does not refresh the event twice")
	_expect(
		_player_state_change_count == 1, "duplicate victory does not refresh player state twice"
	)

	await _free_fixture(fixture)


func _create_coordinator():
	var coordinator_script = ResourceLoader.load(EncounterResolutionCoordinatorPath)
	_expect(coordinator_script != null, "encounter resolution coordinator script exists")
	return coordinator_script.new() if coordinator_script != null else null


func _configure_coordinator(coordinator, fixture: Dictionary) -> bool:
	_reset_ports(fixture)
	_expect(
		_configure_argument_count(coordinator) == 8,
		"encounter resolution accepts explicit settlement callback ports"
	)
	if _configure_argument_count(coordinator) != 8:
		return false
	return coordinator.configure(
		fixture.board,
		fixture.player_stats,
		fixture.player_data,
		fixture.card_service,
		Callable(self, "_on_boss_dismissed"),
		Callable(self, "_on_player_state_changed"),
		Callable(self, "_on_event_display_refresh"),
		fixture.reward_rng
	)


func _configure_argument_count(coordinator) -> int:
	for method: Dictionary in coordinator.get_method_list():
		if method.get("name", "") == "configure":
			return (method.get("args", []) as Array).size()
	return -1


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
	_expect(
		card_service.configure(card_manager, hand_area, drag_layer),
		"fixture configures card ownership"
	)

	var content: EncounterEventContent = (
		MonsterEventContent.new()
		if event_type == EventData.EventType.MONSTER
		else BossEventContent.new()
	)
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

	var player_data := PlayerData.new()
	player_data.gold = 30
	var reward_rng := RandomNumberGenerator.new()
	reward_rng.seed = 41
	return {
		"board": board,
		"hand_area": hand_area,
		"drag_layer": drag_layer,
		"card_service": card_service,
		"player_stats": _stats(20, 20, 4),
		"player_data": player_data,
		"instance": instance,
		"content": content,
		"monster": monster,
		"event_node": event_node,
		"reward_rng": reward_rng,
	}


func _add_guaranteed_gold_and_card_drops(content: EncounterEventContent) -> void:
	var reward_card := CardData.new()
	reward_card.card_name = "Resolution Reward"
	content.drop_entries.append(_gold_drop(8))
	var card_drop := EncounterDropEntry.new()
	card_drop.kind = EncounterDropEntry.Kind.CARD
	card_drop.chance = 1.0
	card_drop.card_data = reward_card
	content.drop_entries.append(card_drop)


func _gold_drop(amount: int) -> EncounterDropEntry:
	var drop := EncounterDropEntry.new()
	drop.kind = EncounterDropEntry.Kind.GOLD
	drop.chance = 1.0
	drop.gold_amount = amount
	return drop


func _place_tail_card(fixture: Dictionary) -> CardEntity:
	var root_data := CardData.new()
	root_data.card_type = CardData.CardType.ROOT
	var root_card := CardEntityScene.instantiate() as CardEntity
	root_card.bind_instance(CardInstance.new(root_data))
	root.add_child(root_card)
	root_card.global_position = fixture.board.to_global(
		_horizontal_card_center(fixture.board, Vector2i(0, 0))
	)
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
	tail.global_position = fixture.board.to_global(
		_horizontal_card_center(fixture.board, Vector2i(2, 0))
	)
	tail.rotation_degrees = 90.0
	return tail if fixture.board.add_card(tail) else null


func _result(
	outcome: CombatResult.Outcome, player_hp: int, monster_hp: int, action_index := 0
) -> CombatResult:
	return CombatResult.new(
		outcome, _stats(20, player_hp, 6), _stats(20, monster_hp, 5), [], 0, [], action_index
	)


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
	return board.to_local(
		(board.grid_to_world_center(left_cell) + board.grid_to_world_center(right_cell)) / 2.0
	)


func _reset_ports(fixture: Dictionary) -> void:
	_active_fixture = fixture
	_boss_dismissal_count = 0
	_event_display_refresh_count = 0
	_dismissed_instances.clear()
	_refreshed_instances.clear()


func _on_boss_dismissed(instance: EventInstance) -> void:
	_boss_dismissal_count += 1
	_dismissed_instances.append(instance)
	if _active_fixture.is_empty():
		return
	var board: Board = _active_fixture.board
	var event_node: BoardEvent = _active_fixture.event_node
	if board != null and event_node != null:
		board.remove_event(event_node)


func _on_event_display_refresh(instance: EventInstance) -> void:
	_event_display_refresh_count += 1
	_refreshed_instances.append(instance)


func _on_player_state_changed() -> void:
	_player_state_change_count += 1


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
