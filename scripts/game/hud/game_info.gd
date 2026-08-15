class_name GameInfo
extends Panel

var _current_hp := 0
var _max_hp := 1
var _current_gold := 0
var _player_data: PlayerData
var _player_stats: CombatStats


func _ready() -> void:
	_set_mouse_transparent(self)
	_update_vitality_label()
	_update_gold_label()


func bind_player(player_data: PlayerData, player_stats: CombatStats) -> void:
	_disconnect_player_sources()
	_player_data = player_data
	_player_stats = player_stats
	if _player_data != null:
		_player_data.gold_changed.connect(_on_gold_changed)
		set_gold(_player_data.gold)
	if _player_stats != null:
		_player_stats.vitality_changed.connect(_on_vitality_changed)
		set_vitality(_player_stats.hp, _player_stats.max_hp)


func set_vitality(current_hp: int, max_hp: int) -> void:
	_max_hp = maxi(1, max_hp)
	_current_hp = clampi(current_hp, 0, _max_hp)
	_update_vitality_label()


func set_gold(current_gold: int) -> void:
	_current_gold = maxi(0, current_gold)
	_update_gold_label()


func _disconnect_player_sources() -> void:
	if _player_data != null and _player_data.gold_changed.is_connected(_on_gold_changed):
		_player_data.gold_changed.disconnect(_on_gold_changed)
	if _player_stats != null and _player_stats.vitality_changed.is_connected(_on_vitality_changed):
		_player_stats.vitality_changed.disconnect(_on_vitality_changed)


func _on_vitality_changed(current_hp: int, max_hp: int) -> void:
	set_vitality(current_hp, max_hp)


func _on_gold_changed(current_gold: int) -> void:
	set_gold(current_gold)


func _update_vitality_label() -> void:
	var health_number := get_node_or_null("HeartContainer/HealthNumber") as Label
	if health_number != null:
		health_number.text = "%d / %d" % [_current_hp, _max_hp]


func _update_gold_label() -> void:
	var gold_number := get_node_or_null("GoldNumber") as Label
	if gold_number != null:
		gold_number.text = str(_current_gold)


func _set_mouse_transparent(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_mouse_transparent(child)
