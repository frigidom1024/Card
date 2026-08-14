extends SceneTree

const BOARD_SCENE := preload("res://scenes/game/board.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")
const EVENT_SCENE := preload("res://scenes/game/event.tscn")
const EVENT_DATA := preload("res://scripts/game/event/core/event_data.gd")
const BOSS_PRESSURE_SERVICE := preload("res://scripts/game/exploration/boss_pressure_service.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var board := BOARD_SCENE.instantiate() as Board
	root.add_child(board)
	var tail := _make_card(CardData.CardType.ROOT)
	_move_card_to_anchor(board.board_zone, tail, Vector2i(4, 4), 0)
	_expect(board.board_zone.add_card(tail), "root card establishes a chain tail")

	var boss := _make_boss_event(Vector2i(0, 0))
	_expect(board.attach_event(boss), "Boss event attaches before pursuit configuration is evaluated")
	var original_origin := boss.event_instance.origin

	var service := BOSS_PRESSURE_SERVICE.new()
	service.configure(false, 1, 1)
	service.register_boss(boss)
	service.record_card_placed(board)
	service.record_card_placed(board)

	_expect(
		service.get_phase() == BOSS_PRESSURE_SERVICE.Phase.ACTIVE,
		"disabled pursuit keeps the Boss in its normal active event state"
	)
	_expect(
		boss.event_instance.origin == original_origin,
		"disabled pursuit never changes the ordinary Boss event origin"
	)
	board.queue_free()
	await process_frame
	quit(1 if _failure_count > 0 else 0)


func _make_card(card_type: CardData.CardType) -> Card:
	var card := CARD_SCENE.instantiate() as Card
	var data := CardData.new()
	data.card_type = card_type
	card.bind_card_inst(CardInstance.new(data))
	return card


func _move_card_to_anchor(
	board_zone: BoardZone,
	card: Card,
	anchor: Vector2i,
	direction: int
) -> void:
	var background := board_zone.back_ground
	var cell_size := background.cell_size
	var local_center := Vector2(
		(float(anchor.x) + 0.5) * cell_size,
		(float(anchor.y) + 1.0) * cell_size
	)
	var center := background.to_global(local_center)
	card.global_position = center - card.size * 0.5
	card.target_position = card.position
	card.get_card_inst().direction = direction


func _make_boss_event(origin: Vector2i) -> BoardEvent:
	var data := EVENT_DATA.new()
	data.event_id = "test_boss"
	data.event_type = EVENT_DATA.EventType.BOSS
	data.size = Vector2i.ONE
	var instance := data.create_instance()
	instance.origin = origin
	var event_node := EVENT_SCENE.instantiate() as BoardEvent
	event_node.setup(instance, 80)
	return event_node


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
