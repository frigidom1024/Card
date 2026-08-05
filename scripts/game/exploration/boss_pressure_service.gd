class_name BossPressureService
extends RefCounted

const BoardPlacementResultScript := preload("res://scripts/game/board_placement_result.gd")

## Boss 追猎阶段。这里的“顶部”指最后一张卡牌朝向的连接格，而不是视觉上方。
enum Phase {
	HIDDEN,
	ACTIVE,
	SURROUNDING,
	INTERCEPTING,
}

signal phase_changed(phase: Phase)

var pursuit_enabled := true
var cards_to_surround: int = 2
var cards_to_intercept: int = 2

var _phase: Phase = Phase.HIDDEN
var _cards_since_appearance := 0
var _boss_event: BoardEvent

func configure(
	enabled: bool = true,
	surround_threshold: int = 2,
	intercept_threshold: int = 2
) -> void:
	pursuit_enabled = enabled
	cards_to_surround = maxi(1, surround_threshold)
	cards_to_intercept = maxi(1, intercept_threshold)

func register_boss(boss_event: BoardEvent) -> void:
	_boss_event = boss_event
	_cards_since_appearance = 0
	_set_phase(Phase.ACTIVE)

func clear_boss() -> void:
	_boss_event = null
	_cards_since_appearance = 0
	_set_phase(Phase.HIDDEN)

func get_phase() -> Phase:
	return _phase

func is_intercepting() -> bool:
	return _phase == Phase.INTERCEPTING

## Records only ordinary chain extensions. GUIDE resolves space but never advances pursuit.
func record_placement(board: Board, result: BoardPlacementResult) -> void:
	if result == null or result.kind != BoardPlacementResultScript.Kind.CHAIN_EXTENDED:
		return
	record_card_placed(board)

## 在成功放置一张卡后调用。拆牌不会调用本方法，因此追猎进度不会倒退。
func record_card_placed(board: Board) -> void:
	if not pursuit_enabled or _boss_event == null or board == null or _phase == Phase.HIDDEN:
		return
	_cards_since_appearance += 1
	if _phase == Phase.ACTIVE and _cards_since_appearance >= cards_to_surround:
		if _move_to_surrounding(board):
			_set_phase(Phase.SURROUNDING)
	if _phase == Phase.SURROUNDING and _cards_since_appearance >= cards_to_surround + cards_to_intercept:
		var last_card: CardEntity = board.cards.back() if not board.cards.is_empty() else null
		if last_card != null:
			# 强制占据牌头连接格：下一张牌若想接上牌链，就必须覆盖这个格子。
			var forward_cell := board.get_placement_cell(last_card)
			if board.move_event(_boss_event, forward_cell):
				_set_phase(Phase.INTERCEPTING)

func _set_phase(value: Phase) -> void:
	if _phase == value:
		return
	_phase = value
	phase_changed.emit(_phase)

func _move_to_surrounding(board: Board) -> bool:
	if board.cards.is_empty() or _boss_event == null:
		return false
	var last_card: CardEntity = board.cards.back()
	var card_cells := board.get_card_cells(last_card.global_position, last_card.rotation_degrees)
	var candidates: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
	]
	for card_cell in card_cells:
		for offset in offsets:
			var candidate: Vector2i = card_cell + offset
			if candidate not in candidates:
				candidates.append(candidate)
	for candidate in candidates:
		if board.move_event(_boss_event, candidate):
			return true
	return false
