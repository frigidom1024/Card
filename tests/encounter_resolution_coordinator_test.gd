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
var _boss_dismissal_succeeds := true
var _active_fixture: Dictionary = {}


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_victory_discards_depleted_normal_card_and_grants_rewards()
	await _test_retreat_keeps_surviving_cards_and_strengthens_echo()
	await _test_retreat_resets_and_returns_depleted_root()
	await _test_defeat_discards_depleted_card_without_rewards()
	await _test_boss_victory_uses_standard_rewards_after_dismissal()
	await _test_boss_dismissal_failure_is_atomic()
	quit(1 if _failure_count > 0 else 0)


func _test_victory_discards_depleted_normal_card_and_grants_rewards() -> void:
	var fixture := _create_fixture(EventData.EventType.MONSTER)
	var coordinator = _configure_coordinator(fixture)
	if coordinator == null:
		await _free_fixture(fixture)
		return
	_add_guaranteed_gold_and_card_drops(fixture.content)
	_expect(_place_anchor_root(fixture, Vector2i(0, 0)) != null, "victory fixture places anchor root")
	var exhausted := _place_owned_card(fixture, false, Vector2i(2, 0), 2)
	_expect(exhausted != null, "victory fixture places an owned normal card")
	if exhausted != null:
		exhausted.card_instance.current_points = 0

	_expect(
		coordinator.apply(
			fixture.instance,
			_result(CombatResult.Outcome.VICTORY, 20, 0, 0, [exhausted.card_instance])
		),
		"victory applies"
	)
	_expect(fixture.instance.is_resolved, "victory resolves the encounter")
	_expect(fixture.monster.stats.hp == 0, "victory writes echo HP")
	_expect(fixture.player_data.gold == 38, "victory grants configured gold")
	_expect(exhausted not in fixture.board.cards, "victory removes exhausted normal card from board")
	_expect(
		exhausted.card_instance not in fixture.card_service.get_instances(),
		"victory stops tracking exhausted normal card"
	)
	_expect(
		fixture.card_service.get_entities().size() == 1,
		"victory tracks only the earned reward after discard"
	)
	_expect(
		fixture.card_service.get_entities()[0] in fixture.hand_area.cards,
		"victory places reward in hand"
	)
	_expect(_event_display_refresh_count == 1, "victory refreshes normal event display")

	await _free_fixture(fixture)


func _test_retreat_keeps_surviving_cards_and_strengthens_echo() -> void:
	var fixture := _create_fixture(EventData.EventType.MONSTER)
	var coordinator = _configure_coordinator(fixture)
	if coordinator == null:
		await _free_fixture(fixture)
		return
	_expect(_place_anchor_root(fixture, Vector2i(0, 0)) != null, "retreat fixture places anchor root")
	var survivor := _place_owned_card(fixture, false, Vector2i(2, 0), 3)
	_expect(survivor != null, "retreat fixture places a surviving card")

	_expect(
		coordinator.apply(fixture.instance, _result(CombatResult.Outcome.RETREAT, 20, 16)),
		"retreat applies"
	)
	_expect(not fixture.instance.is_resolved, "retreat leaves encounter unresolved")
	_expect(survivor in fixture.board.cards, "retreat keeps a card with remaining points on board")
	_expect(survivor not in fixture.hand_area.cards, "retreat does not return surviving cards to hand")
	_expect(
		survivor.card_instance in fixture.card_service.get_instances(),
		"retreat preserves surviving card ownership"
	)
	_expect(fixture.monster.enhancement_stacks == 1, "retreat adds one enhancement stack")
	_expect(
		fixture.monster.stats.max_hp == 21 and fixture.monster.stats.hp == 17,
		"retreat preserves prior damage then applies one configured health enhancement"
	)
	_expect(_event_display_refresh_count == 1, "retreat refreshes the existing event display")

	await _free_fixture(fixture)


func _test_retreat_resets_and_returns_depleted_root() -> void:
	var fixture := _create_fixture(EventData.EventType.MONSTER)
	var coordinator = _configure_coordinator(fixture)
	if coordinator == null:
		await _free_fixture(fixture)
		return
	var root_card := _place_owned_card(fixture, true, Vector2i(0, 0), 2, 2)
	_expect(root_card != null, "root fixture places an owned root card")
	if root_card != null:
		root_card.card_instance.current_points = 0
		root_card.card_instance.current_armor = 0

	_expect(
		coordinator.apply(
			fixture.instance,
			_result(CombatResult.Outcome.RETREAT, 20, 18, 0, [root_card.card_instance])
		),
		"depleted-root retreat applies"
	)
	_expect(root_card not in fixture.board.cards, "depleted root leaves board")
	_expect(root_card in fixture.hand_area.cards, "depleted root returns to hand")
	_expect(root_card.card_instance.cur_zone == CardInstance.ZONE.HAND, "returned root enters hand zone")
	_expect(root_card.card_instance.current_points == 2, "returned root resets point value")
	_expect(root_card.card_instance.current_armor == 2, "returned root resets armor")
	_expect(
		root_card.card_instance in fixture.card_service.get_instances(),
		"returned root stays owned for later placement"
	)

	await _free_fixture(fixture)


func _test_defeat_discards_depleted_card_without_rewards() -> void:
	var fixture := _create_fixture(EventData.EventType.MONSTER)
	var coordinator = _configure_coordinator(fixture)
	if coordinator == null:
		await _free_fixture(fixture)
		return
	_add_guaranteed_gold_and_card_drops(fixture.content)
	_expect(_place_anchor_root(fixture, Vector2i(0, 0)) != null, "defeat fixture places anchor root")
	var exhausted := _place_owned_card(fixture, false, Vector2i(2, 0), 1)
	_expect(exhausted != null, "defeat fixture places an owned normal card")
	if exhausted != null:
		exhausted.card_instance.current_points = 0

	_expect(
		coordinator.apply(
			fixture.instance,
			_result(CombatResult.Outcome.DEFEAT, 0, 16, 0, [exhausted.card_instance])
		),
		"defeat applies"
	)
	_expect(not fixture.instance.is_resolved, "defeat does not resolve the encounter")
	_expect(fixture.player_data.gold == 30, "defeat grants no encounter gold")
	_expect(exhausted not in fixture.board.cards, "defeat removes exhausted normal card")
	_expect(fixture.card_service.get_entities().is_empty(), "defeat grants no reward card")
	_expect(_event_display_refresh_count == 0, "defeat does not refresh encounter display")

	await _free_fixture(fixture)


func _test_boss_victory_uses_standard_rewards_after_dismissal() -> void:
	var fixture := _create_fixture(EventData.EventType.BOSS)
	var coordinator = _configure_coordinator(fixture)
	if coordinator == null:
		await _free_fixture(fixture)
		return
	fixture.content.drop_entries.append(_gold_drop(6))

	_expect(
		coordinator.apply(fixture.instance, _result(CombatResult.Outcome.VICTORY, 20, 0)),
		"boss victory applies"
	)
	_expect(_boss_dismissal_count == 1, "boss victory removes boss through dismissal port")
	_expect(fixture.instance.is_resolved, "boss victory resolves instance")
	_expect(fixture.player_data.gold == 36, "boss victory reuses encounter reward pipeline")
	_expect(_event_display_refresh_count == 0, "dismissed boss does not refresh a removed event display")

	await _free_fixture(fixture)


func _test_boss_dismissal_failure_is_atomic() -> void:
	var fixture := _create_fixture(EventData.EventType.BOSS)
	var coordinator = _configure_coordinator(fixture)
	if coordinator == null:
		await _free_fixture(fixture)
		return
	_boss_dismissal_succeeds = false
	fixture.content.drop_entries.append(_gold_drop(6))

	_expect(
		not coordinator.apply(fixture.instance, _result(CombatResult.Outcome.VICTORY, 20, 0)),
		"failed boss dismissal rejects settlement"
	)
	_expect(not fixture.instance.is_resolved, "failed boss dismissal leaves instance unresolved")
	_expect(fixture.player_data.gold == 30, "failed boss dismissal grants no rewards")
	_expect(fixture.monster.stats.hp == 20, "failed boss dismissal does not mutate echo state")
	_expect(_player_state_change_count == 0, "failed boss dismissal does not publish player state")

	await _free_fixture(fixture)


func _configure_coordinator(fixture: Dictionary):
	var coordinator_script = ResourceLoader.load(EncounterResolutionCoordinatorPath)
	_expect(coordinator_script != null, "encounter resolution coordinator script exists")
	if coordinator_script == null:
		return null
	var coordinator = coordinator_script.new()
	_reset_ports(fixture)
	_expect(
		coordinator.configure(
			fixture.board,
			fixture.player_stats,
			fixture.player_data,
			fixture.card_service,
			Callable(self, "_on_boss_dismissed"),
			Callable(self, "_on_player_state_changed"),
			Callable(self, "_on_event_display_refresh"),
			fixture.reward_rng
		),
		"fixture configures encounter settlement"
	)
	return coordinator


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


func _place_anchor_root(fixture: Dictionary, left_cell: Vector2i) -> CardEntity:
	var root_data := CardData.new()
	root_data.card_name = "Anchor Root"
	root_data.card_type = CardData.CardType.ROOT
	root_data.max_points = 1
	var root_card := CardEntityScene.instantiate() as CardEntity
	root_card.bind_instance(CardInstance.new(root_data))
	root.add_child(root_card)
	root_card.global_position = fixture.board.to_global(_horizontal_card_center(fixture.board, left_cell))
	root_card.rotation_degrees = 90.0
	return root_card if fixture.board.add_card(root_card) else null


func _place_owned_card(
	fixture: Dictionary, is_root: bool, left_cell: Vector2i, points: int, armor: int = 0
) -> CardEntity:
	var data := CardData.new()
	data.card_name = "Settlement Root" if is_root else "Settlement Card"
	data.card_type = CardData.CardType.ROOT if is_root else CardData.CardType.NORMAL
	data.max_points = points
	data.armor = armor
	if not fixture.card_service.grant_to_hand(data):
		return null
	var card: CardEntity = fixture.card_service.get_entities().back()
	if not fixture.hand_area.remove_card(card):
		return null
	card.global_position = fixture.board.to_global(_horizontal_card_center(fixture.board, left_cell))
	card.rotation_degrees = 90.0
	return card if fixture.board.add_card(card) else null


func _result(
	outcome: CombatResult.Outcome,
	player_hp: int,
	monster_hp: int,
	action_index := 0,
	depleted_cards: Array[CardInstance] = []
) -> CombatResult:
	return CombatResult.new(
		outcome,
		_stats(20, player_hp, 6),
		_stats(20, monster_hp, 5),
		[],
		0,
		[],
		action_index,
		depleted_cards
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
	mob.enhancement_hp_bonus = 1
	return mob


func _horizontal_card_center(board: Board, left_cell: Vector2i) -> Vector2:
	var right_cell := left_cell + Vector2i.RIGHT
	return board.to_local(
		(board.grid_to_world_center(left_cell) + board.grid_to_world_center(right_cell)) / 2.0
	)


func _reset_ports(fixture: Dictionary) -> void:
	_active_fixture = fixture
	_boss_dismissal_succeeds = true
	_boss_dismissal_count = 0
	_event_display_refresh_count = 0
	_player_state_change_count = 0


func _on_boss_dismissed(_instance: EventInstance) -> bool:
	_boss_dismissal_count += 1
	if not _boss_dismissal_succeeds or _active_fixture.is_empty():
		return false
	return _active_fixture.board.remove_event(_active_fixture.event_node)


func _on_event_display_refresh(_instance: EventInstance) -> void:
	_event_display_refresh_count += 1


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