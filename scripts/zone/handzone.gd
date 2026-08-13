extends CardZone
class_name HandZone

var cards: Array[Card] = []
@export var card_overlap: float = 10
@export var card_row_y: float = 0.0
@export var rot_max: float = 8.0
@export_range(0.0, 1.0, 0.05) var rot_growth: float = 0.5
@export_group("Floating")
@export var float_amplitude: float = 4.0
@export var float_speed: float = 2.0
@export var float_phase_offset: float = 0.5

var _float_time: float = 0.0
func _process(delta: float) -> void:
	if float_amplitude == 0.0 or cards.is_empty():
		return
	_float_time += delta * float_speed
	refresh_hand()


func _ready() -> void:
	_register_existing_cards()
	refresh_hand()
	call_deferred("refresh_hand")


func _register_existing_cards() -> void:
	for child in get_children():
		if child is Card and not cards.has(child):
			cards.append(child)
			child.cur_zone = self


func add_card(card: Card, keep_global_position: bool = true) -> bool:
	if card == null:
		return false

	var insert_index := cards.size()
	if card.get_parent() != null:
		insert_index = _get_insert_index(card)
	var existing_index := cards.find(card)
	if existing_index != -1:
		cards.remove_at(existing_index)
		if existing_index < insert_index:
			insert_index -= 1

	if card.get_parent() == null:
		add_child(card)
	elif card.get_parent() != self:
		card.reparent(self, keep_global_position)

	insert_index = clampi(insert_index, 0, cards.size())
	cards.insert(insert_index, card)
	card.cur_zone = self
	refresh_hand()
	return true


func _get_insert_index(card: Card) -> int:
	var card_center_x := card.global_position.x + card.size.x * 0.5
	for index in range(cards.size()):
		var current := cards[index]
		if not is_instance_valid(current) or current == card:
			continue

		var current_center_x := current.global_position.x + current.size.x * 0.5
		if current.get_parent() == self:
			var target_center := current.target_position + current.size * 0.5
			current_center_x = (get_global_transform_with_canvas() * target_center).x

		if card_center_x < current_center_x:
			return index
	return cards.size()


func remove_card(card: Card) -> bool:
	var index := cards.find(card)
	if index == -1:
		return false
	cards.remove_at(index)
	if card.cur_zone == self:
		card.cur_zone = null
	refresh_hand()
	return true


func refresh_hand() -> void:
	var valid_cards: Array[Card] = []
	for card in cards:
		if is_instance_valid(card):
			valid_cards.append(card)
	cards = valid_cards

	var count := cards.size()
	if count == 0:
		return

	var card_width := cards[0].size.x
	var step := maxf(0.0, card_width - card_overlap)
	var total_width := card_width + step * float(count - 1)
	var start_x := (size.x - total_width) * 0.5

	var center_index := (count - 1) * 0.5
	var rotation_growth := minf(1.0, maxf(0.0, float(count - 1) * rot_growth))
	var side_rotation := deg_to_rad(rot_max) * rotation_growth

	for index in range(count):
		var card := cards[index]
		if not card.dragging:
			var float_offset := sin(_float_time + float(index) * float_phase_offset) * float_amplitude
			card.target_position = Vector2(start_x + step * index, card_row_y + float_offset)

		var normalized_distance := 0.0
		if center_index > 0.0:
			normalized_distance = (float(index) - center_index) / center_index
		card.rotation = normalized_distance * side_rotation
		card.z_index = index
		
