extends SceneTree

const BoardScene = preload("res://scenes/game/board.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)

	var tail := CardEntityScene.instantiate() as CardEntity
	board.add_child(tail)
	tail.position = Vector2(520, 364)
	tail.rotation_degrees = -90.0
	board.cards.append(tail)

	var candidate := CardEntityScene.instantiate() as CardEntity
	board.add_child(candidate)
	candidate.position = Vector2(364, 312)
	candidate.rotation_degrees = 0.0

	var candidate_cells := board.get_card_cells(candidate.global_position, candidate.rotation_degrees)
	_expect(
		board.get_placement_cell(tail) == Vector2i(3, 3),
		"a -90 degree tail exposes its left-side connection cell"
	)
	_expect(
		board.can_place_card(candidate_cells, candidate),
		"a card covering the left-side connection cell can be placed after a -90 degree tail"
	)

	board.queue_free()
	quit(1 if _failure_count > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)