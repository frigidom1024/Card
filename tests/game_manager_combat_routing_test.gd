extends SceneTree

const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const EventScene = preload("res://scenes/game/event.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_game_manager_delegates_combat_settlement_to_run_flow()
	await _test_monster_victory_resolves_event_and_unlocks_exploration()
	await _test_boss_victory_removes_the_intercepting_event()
	await _test_retreat_preserves_encounter_and_returns_the_real_tail_card()
	await _test_defeat_emits_failure_and_keeps_exploration_locked()
	await _test_shop_event_routes_purchase_and_close()
	await _test_treasure_event_routes_claim_and_resolves()
	quit(0 if _failure_count == 0 else 1)


func _test_game_manager_delegates_combat_settlement_to_run_flow() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game_manager.gd")
	_expect(
		not source.contains("_on_modal_combat_settlement_confirmed"),
		"GameManager does not consume combat settlement confirmations"
	)
	_expect(
		not source.contains("_encounter_resolution.apply("),
		"GameManager does not apply combat settlements"
	)
	_expect(
		source.contains("_run_flow.handle_card_return_requested(card)"),
		"GameManager guide-return compatibility entry delegates to RunFlowCoordinator"
	)


func _test_monster_victory_resolves_event_and_unlocks_exploration() -> void:
	var manager := await _make_game_manager()
	if not _require_combat_signals(manager):
		_cleanup_manager(manager)
		return

	var board: Board = manager.board
	var event_node := _attach_encounter_event(
		board, EventData.EventType.MONSTER, Vector2i(3, 0), 2, []
	)
	var started: Array[MobInstance] = []
	var outcomes: Array[CombatResult] = []
	manager.connect("combat_started", func(_instance, monster): started.append(monster))
	manager.connect("combat_resolved", func(_instance, result): outcomes.append(result))

	_expect(
		(
			_place_card(
				manager,
				_horizontal_card_center(board, Vector2i(0, 0)),
				90.0,
				CardData.CardType.ROOT,
				0
			)
			!= null
		),
		"victory setup places root"
	)
	_expect(
		(
			_place_card(
				manager,
				_horizontal_card_center(board, Vector2i(2, 0)),
				90.0,
				CardData.CardType.NORMAL,
				2
			)
			!= null
		),
		"victory setup places weapon"
	)

	var combat_view := _combat_view(manager)
	_expect(combat_view != null and combat_view.visible, "victory opens the combat modal")
	_expect(
		not event_node.event_instance.is_resolved,
		"victory stays unresolved until settlement confirmation"
	)
	_expect(started.size() == 1, "victory emits one combat-start signal")
	_expect(outcomes.is_empty(), "victory does not emit combat result before confirmation")
	_expect(
		manager.drag_layer.is_interaction_locked(),
		"victory keeps exploration locked before confirmation"
	)

	_confirm_combat_settlement(manager)
	_expect(event_node.event_instance.is_resolved, "confirmed victory resolves the encounter event")
	_expect(outcomes.size() == 1, "confirmed victory emits one combat result")
	_expect(
		outcomes.size() == 1 and outcomes[0].outcome == CombatResult.Outcome.VICTORY,
		"confirmed victory result has VICTORY outcome"
	)
	_expect(not manager.drag_layer.is_interaction_locked(), "confirmed victory unlocks exploration")
	_expect(
		combat_view != null and not combat_view.visible, "confirmed victory hides the combat modal"
	)
	_cleanup_manager(manager)


func _test_boss_victory_removes_the_intercepting_event() -> void:
	var manager := await _make_game_manager()
	if not _require_combat_signals(manager):
		_cleanup_manager(manager)
		return

	var board: Board = manager.board
	var event_node := _attach_encounter_event(
		board, EventData.EventType.BOSS, Vector2i(3, 0), 2, []
	)
	var finished_instances: Array[EventInstance] = []
	manager._event_interaction_controller.interaction_finished.connect(
		func(instance: EventInstance) -> void: finished_instances.append(instance)
	)

	_expect(
		(
			_place_card(
				manager,
				_horizontal_card_center(board, Vector2i(0, 0)),
				90.0,
				CardData.CardType.ROOT,
				0
			)
			!= null
		),
		"boss victory setup places root"
	)
	_expect(
		(
			_place_card(
				manager,
				_horizontal_card_center(board, Vector2i(2, 0)),
				90.0,
				CardData.CardType.NORMAL,
				2
			)
			!= null
		),
		"boss victory setup places a card that contacts the boss"
	)
	_expect(
		event_node in board.events,
		"intercepting boss remains attached before settlement confirmation"
	)

	_confirm_combat_settlement(manager)
	_expect(event_node.event_instance.is_resolved, "confirmed boss victory resolves the boss event")
	_expect(
		event_node not in board.events,
		"confirmed boss victory removes the boss event from the board"
	)
	_expect(
		finished_instances == [event_node.event_instance],
		"boss event is removed before its interaction lifecycle finishes"
	)
	_cleanup_manager(manager)


func _test_retreat_preserves_encounter_and_returns_the_real_tail_card() -> void:
	var manager := await _make_game_manager()
	if not _require_combat_signals(manager):
		_cleanup_manager(manager)
		return

	var runtime_player_stats: CombatStats = manager.get_run_context().player_stats
	runtime_player_stats.max_hp = 10
	runtime_player_stats.hp = 10
	runtime_player_stats.attack = 0
	runtime_player_stats.defense = 0
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

	_expect(
		(
			_place_card(
				manager,
				_horizontal_card_center(board, Vector2i(0, 0)),
				90.0,
				CardData.CardType.ROOT,
				0
			)
			!= null
		),
		"retreat setup places root"
	)
	_expect(
		(
			_place_card(
				manager,
				_horizontal_card_center(board, Vector2i(2, 0)),
				90.0,
				CardData.CardType.NORMAL,
				3
			)
			!= null
		),
		"retreat setup places first weapon"
	)
	var tail := _place_card(
		manager, _horizontal_card_center(board, Vector2i(4, 0)), 90.0, CardData.CardType.NORMAL, 1
	)
	_expect(tail != null, "retreat setup places tail weapon")

	var runtime_state := event_node.event_instance.runtime_state as EncounterRuntimeState
	var combat_view := _combat_view(manager)
	_expect(combat_view != null and combat_view.visible, "retreat opens the combat modal")
	_expect(
		not event_node.event_instance.is_resolved,
		"retreat leaves the encounter unresolved before confirmation"
	)
	_expect(outcomes.is_empty(), "retreat does not emit combat result before confirmation")
	_expect(
		manager.player_stats.hp == 10, "retreat does not apply player state before confirmation"
	)
	_expect(
		runtime_state.mob_instance.stats.hp == 20,
		"retreat does not persist monster damage before confirmation"
	)
	_expect(
		board.cards.size() == 3, "retreat does not return the board tail card before confirmation"
	)
	_expect(tail in board.cards, "retreat retains the real final CardEntity before confirmation")
	_expect(
		manager.drag_layer.is_interaction_locked(),
		"retreat keeps exploration locked before confirmation"
	)

	_confirm_combat_settlement(manager)
	_expect(
		not event_node.event_instance.is_resolved,
		"confirmed retreat leaves the encounter unresolved"
	)
	_expect(outcomes.size() == 1, "confirmed retreat emits one combat result")
	_expect(
		outcomes.size() == 1 and outcomes[0].outcome == CombatResult.Outcome.RETREAT,
		"confirmed retreat result has RETREAT outcome"
	)
	_expect(manager.player_stats.hp == 7, "confirmed retreat persists player damage")
	_expect(manager.player_stats.defense == 0, "confirmed retreat clears player encounter defense")
	_expect(
		runtime_state.mob_instance.stats.hp == 16, "confirmed retreat persists monster HP damage"
	)
	_expect(
		runtime_state.mob_instance.stats.defense == 0,
		"confirmed retreat clears monster encounter defense"
	)
	_expect(
		runtime_state.mob_instance.action_index == 0,
		"confirmed retreat preserves the next monster action"
	)
	_expect(
		runtime_state.mob_instance.enhancement_stacks == 1,
		"confirmed retreat adds one enhancement stack"
	)
	_expect(board.cards.size() == 2, "confirmed retreat removes one board tail card")
	_expect(
		tail not in board.cards, "confirmed retreat removes the actual final CardEntity from Board"
	)
	_expect(
		tail.card_instance.cur_zone == CardInstance.ZONE.HAND,
		"confirmed retreat moves the tail instance to hand"
	)
	_expect(
		tail in manager.hand_area.cards, "confirmed retreat returns the actual tail entity to hand"
	)
	_expect(
		tail in manager.card_entities, "confirmed retreat preserves returned tail entity ownership"
	)
	_expect(
		tail.card_instance in manager.cards_inst,
		"confirmed retreat preserves returned tail instance ownership"
	)
	_expect(
		not manager.drag_layer.is_interaction_locked(),
		"confirmed retreat unlocks exploration for another challenge"
	)

	if tail != null and manager.hand_area.remove_card(tail):
		tail.global_position = board.to_global(_horizontal_card_center(board, Vector2i(4, 0)))
		tail.rotation_degrees = 90.0
		_expect(
			board.add_card(tail),
			"returned tail can be placed to challenge the same encounter again"
		)
		await process_frame
		var next_result: CombatResult = (
			manager._event_interaction_controller.get_pending_combat_result()
		)
		_expect(
			next_result != null and next_result.outcome == CombatResult.Outcome.RETREAT,
			"second challenge opens another retreat result"
		)
		_expect(
			(
				next_result != null
				and next_result.steps.size() >= 3
				and next_result.steps[2].effects[0].value == 4
			),
			"strengthening adds one to the next monster action"
		)
	_cleanup_manager(manager)


func _test_defeat_emits_failure_and_keeps_exploration_locked() -> void:
	var manager := await _make_game_manager()
	if not _require_combat_signals(manager):
		_cleanup_manager(manager)
		return

	var runtime_player_stats: CombatStats = manager.get_run_context().player_stats
	runtime_player_stats.max_hp = 10
	runtime_player_stats.hp = 10
	runtime_player_stats.attack = 0
	runtime_player_stats.defense = 0
	var board: Board = manager.board
	var event_node := _attach_encounter_event(
		board, EventData.EventType.BOSS, Vector2i(3, 0), 20, [_action(MobAction.Type.ATTACK, 10)]
	)
	var failures: Array[CombatResult] = []
	manager.connect("exploration_failed", func(result): failures.append(result))

	_expect(
		(
			_place_card(
				manager,
				_horizontal_card_center(board, Vector2i(0, 0)),
				90.0,
				CardData.CardType.ROOT,
				0
			)
			!= null
		),
		"defeat setup places root"
	)
	_expect(
		(
			_place_card(
				manager,
				_horizontal_card_center(board, Vector2i(2, 0)),
				90.0,
				CardData.CardType.NORMAL,
				1
			)
			!= null
		),
		"defeat setup places weapon"
	)

	var combat_view := _combat_view(manager)
	_expect(combat_view != null and combat_view.visible, "defeat opens the combat modal")
	_expect(
		not event_node.event_instance.is_resolved,
		"defeat does not resolve the encounter event before confirmation"
	)
	_expect(failures.is_empty(), "defeat does not emit exploration failure before confirmation")
	_expect(manager.player_stats.hp == 10, "defeat does not persist player HP before confirmation")
	_expect(
		manager.drag_layer.is_interaction_locked(),
		"defeat keeps exploration locked before confirmation"
	)

	_confirm_combat_settlement(manager)
	_expect(
		not event_node.event_instance.is_resolved,
		"confirmed defeat does not resolve the encounter event"
	)
	_expect(failures.size() == 1, "confirmed defeat emits one exploration failure")
	_expect(
		failures.size() == 1 and failures[0].outcome == CombatResult.Outcome.DEFEAT,
		"confirmed defeat result has DEFEAT outcome"
	)
	_expect(manager.player_stats.hp == 0, "confirmed defeat persists player HP at zero")
	_expect(manager.player_stats.defense == 0, "confirmed defeat clears player encounter defense")
	_expect(manager.drag_layer.is_interaction_locked(), "confirmed defeat keeps exploration locked")
	_cleanup_manager(manager)


func _test_shop_event_routes_purchase_and_close() -> void:
	var manager := await _make_game_manager()
	manager.player_data.gold = 10
	manager.hand_area.max_hand_size = manager.hand_area.cards.size() + 1
	var shop_content := ShopEventContent.new()
	shop_content.items = [_shop_item(_make_card_data(2), 5)]
	var event_node := _attach_event(
		manager.board, EventData.EventType.SHOP, Vector2i(1, 0), shop_content
	)
	var hand_before: int = manager.hand_area.cards.size()

	_expect(
		(
			_place_card(
				manager,
				_horizontal_card_center(manager.board, Vector2i(1, 0)),
				90.0,
				CardData.CardType.ROOT,
				0
			)
			!= null
		),
		"shop setup places root over shop"
	)
	var cards_before: int = manager.cards_inst.size()
	await process_frame

	var shop_view := manager.get_node_or_null("EventModalLayer/ShopEventView") as Control
	var treasure_view := manager.get_node_or_null("EventModalLayer/TreasureEventView") as Control
	_expect(shop_view != null, "GameManager exposes ShopEventView")
	_expect(treasure_view != null, "GameManager exposes TreasureEventView")
	if shop_view == null or treasure_view == null:
		_cleanup_manager(manager)
		return
	_expect(shop_view.visible, "shop overlap opens the shop modal")
	_expect(not treasure_view.visible, "shop overlap keeps treasure modal hidden")
	_expect(manager.drag_layer.is_interaction_locked(), "shop modal locks exploration")
	var gold_label := shop_view.find_child("GoldLabel", true, false) as Label
	_expect(
		gold_label != null and gold_label.text == "GOLD  10",
		"shop displays the current player gold"
	)

	var buy_button := (
		shop_view.find_child("OfferSlot1", true, false).find_child("ActionButton", true, false)
		as Button
	)
	_expect(buy_button != null, "shop first offer exposes a purchase button")
	if buy_button != null:
		buy_button.pressed.emit()
		await process_frame
	_expect(manager.player_data.gold == 5, "shop purchase deducts the item price")
	var shop_state := event_node.event_instance.runtime_state as ShopRuntimeState
	_expect(
		shop_state != null and shop_state.sold_flags.size() > 0 and shop_state.sold_flags[0],
		"shop purchase marks the item sold"
	)
	_expect(
		manager.cards_inst.size() == cards_before + 1,
		"shop purchase grants a persistent card instance"
	)
	_expect(
		manager.hand_area.cards.size() == hand_before + 1, "shop purchase adds the card to hand"
	)
	_expect(
		buy_button != null and buy_button.disabled and buy_button.text == "SOLD OUT",
		"sold shop item is disabled and labelled sold out"
	)
	_expect(
		shop_view.visible and manager.drag_layer.is_interaction_locked(),
		"shop remains open and locked after a purchase"
	)

	var close_button := shop_view.find_child("CloseButton", true, false) as Button
	_expect(close_button != null, "shop exposes a close button")
	if close_button != null:
		close_button.pressed.emit()
		await process_frame
	_expect(not event_node.event_instance.is_resolved, "closing shop does not resolve its event")
	_expect(not shop_view.visible, "closing shop hides the modal")
	_expect(not manager.drag_layer.is_interaction_locked(), "closing shop unlocks exploration")
	_cleanup_manager(manager)


func _test_treasure_event_routes_claim_and_resolves() -> void:
	var manager := await _make_game_manager()
	manager.hand_area.max_hand_size = manager.hand_area.cards.size() + 1
	var treasure_content := TreasureEventContent.new()
	treasure_content.card_rewards = [_make_card_data(3), _make_card_data(4)]
	treasure_content.gold_range = Vector2i(7, 7)
	var event_node := _attach_event(
		manager.board, EventData.EventType.TREASURE, Vector2i(1, 0), treasure_content
	)
	var hand_before: int = manager.hand_area.cards.size()

	_expect(
		(
			_place_card(
				manager,
				_horizontal_card_center(manager.board, Vector2i(1, 0)),
				90.0,
				CardData.CardType.ROOT,
				0
			)
			!= null
		),
		"treasure setup places root over treasure"
	)
	var cards_before: int = manager.cards_inst.size()
	await process_frame

	var treasure_view := manager.get_node_or_null("EventModalLayer/TreasureEventView") as Control
	_expect(treasure_view != null, "GameManager exposes TreasureEventView")
	if treasure_view == null:
		_cleanup_manager(manager)
		return
	_expect(treasure_view.visible, "treasure overlap opens the treasure modal")
	_expect(manager.drag_layer.is_interaction_locked(), "treasure modal locks exploration")
	_expect(
		(event_node.event_instance.runtime_state as TreasureRuntimeState).options.size() == 3,
		"treasure creates two card rewards and one gold reward"
	)

	var close_button := treasure_view.find_child("CloseButton", true, false) as Button
	_expect(close_button != null, "treasure exposes a close button")
	if close_button != null:
		close_button.pressed.emit()
		await process_frame
	_expect(treasure_view.visible, "closing treasure keeps the reward selection open")
	_expect(
		not event_node.event_instance.is_resolved,
		"closing treasure does not discard the unresolved reward"
	)
	_expect(
		manager.drag_layer.is_interaction_locked(),
		"closing treasure keeps exploration locked until a reward is claimed"
	)

	var claim_button := (
		treasure_view.find_child("OfferSlot1", true, false).find_child("ActionButton", true, false)
		as Button
	)
	_expect(claim_button != null, "treasure first offer exposes a claim button")
	if claim_button != null:
		claim_button.pressed.emit()
		await process_frame
	_expect(event_node.event_instance.is_resolved, "claiming a treasure reward resolves the event")
	_expect(
		manager.cards_inst.size() == cards_before + 1,
		"treasure card reward grants a persistent card instance"
	)
	_expect(
		manager.hand_area.cards.size() == hand_before + 1,
		"treasure card reward adds the card to hand"
	)
	_expect(not treasure_view.visible, "claiming treasure hides the modal")
	_expect(not manager.drag_layer.is_interaction_locked(), "claiming treasure unlocks exploration")
	_cleanup_manager(manager)


func _combat_view(manager: Node) -> CombatEventView:
	return manager.get_node_or_null("EventModalLayer/CombatEventView") as CombatEventView


func _confirm_combat_settlement(manager: Node) -> void:
	const MAX_PROGRESS_STEPS := 32
	var view := _combat_view(manager)
	_expect(view != null, "GameManager owns a CombatEventView")
	if view == null:
		return
	var progress_button := view.find_child("ProgressButton", true, false) as Button
	var confirm_button := view.find_child("ConfirmButton", true, false) as Button
	_expect(progress_button != null, "combat view exposes a progress button")
	_expect(confirm_button != null, "combat view exposes a confirmation button")
	if progress_button == null or confirm_button == null:
		return
	var progress_steps := 0
	while progress_button.text != "查看结算" and progress_steps < MAX_PROGRESS_STEPS:
		progress_button.pressed.emit()
		progress_steps += 1
	_expect(
		progress_button.text == "查看结算",
		"combat settlement becomes available within %d progress steps" % MAX_PROGRESS_STEPS
	)
	if progress_button.text != "查看结算":
		return
	progress_button.pressed.emit()
	confirm_button.pressed.emit()


func _make_game_manager() -> Node:
	var manager := GameManagerScene.instantiate()
	_expect(manager.configure_run(RevivalDeck), "combat routing setup configures a starting deck")
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
	var content: EncounterEventContent = (
		MonsterEventContent.new()
		if event_type == EventData.EventType.MONSTER
		else BossEventContent.new()
	)
	content.mob = _make_mob(monster_hp, actions)
	return _attach_event(board, event_type, origin, content)


func _attach_non_combat_event(
	board: Board, event_type: EventData.EventType, origin: Vector2i
) -> BoardEvent:
	return _attach_event(board, event_type, origin, EventContent.new())


func _attach_event(
	board: Board, event_type: EventData.EventType, origin: Vector2i, content: EventContent
) -> BoardEvent:
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


func _shop_item(card_data: CardData, price: int) -> ShopItemData:
	var item := ShopItemData.new()
	card_data.value = price
	item.card_data = card_data
	return item


func _make_card_data(damage: int) -> CardData:
	var data := CardData.new()
	data.card_type = CardData.CardType.NORMAL
	data.damage = damage
	return data


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
