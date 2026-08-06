class_name FogService
extends RefCounted

## Owns only fog state. It never creates events or starts interactions.
signal cells_revealed(cells: Array[Vector2i])

var _width := 0
var _height := 0
var _revealed: Dictionary[Vector2i, bool] = {}


func configure(map_width: int, map_height: int) -> void:
	_width = maxi(0, map_width)
	_height = maxi(0, map_height)
	_revealed.clear()


func reveal_for_placement(board: Board, result: BoardPlacementResult) -> Array[Vector2i]:
	if board == null or result == null:
		return []
	var card_cells := result.newly_occupied_cells
	if _is_root_placement(result):
		return reveal_cells(_root_reveal_area(card_cells))
	return reveal_cells(_expanded_reveal_area(card_cells))


func reveal_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var newly_revealed: Array[Vector2i] = []
	for cell in cells:
		if not _is_in_bounds(cell) or _revealed.has(cell):
			continue
		_revealed[cell] = true
		newly_revealed.append(cell)
	if not newly_revealed.is_empty():
		cells_revealed.emit(newly_revealed)
	return newly_revealed


func is_revealed(cell: Vector2i) -> bool:
	return _revealed.has(cell)


func get_revealed_count() -> int:
	return _revealed.size()


func get_revealed_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in _revealed:
		cells.append(cell)
	return cells


func _is_root_placement(result: BoardPlacementResult) -> bool:
	return result.source_card != null \
		and result.source_card.card_instance != null \
		and result.source_card.card_instance.card_data != null \
		and result.source_card.card_instance.card_data.card_type == CardData.CardType.ROOT


func _root_reveal_area(card_cells: Array[Vector2i]) -> Array[Vector2i]:
	if card_cells.is_empty():
		return []
	var minimum := card_cells[0]
	for cell in card_cells:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
	var area: Array[Vector2i] = []
	for x in range(minimum.x, minimum.x + 2):
		for y in range(minimum.y, minimum.y + 2):
			area.append(Vector2i(x, y))
	return area


func _expanded_reveal_area(card_cells: Array[Vector2i]) -> Array[Vector2i]:
	var area: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [
		Vector2i.LEFT,
		Vector2i.UP,
		Vector2i.ZERO,
		Vector2i.RIGHT,
		Vector2i.DOWN,
	]
	for cell in card_cells:
		for offset in offsets:
			var candidate := cell + offset
			if candidate not in area:
				area.append(candidate)
	return area


func _is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < _width and cell.y >= 0 and cell.y < _height
