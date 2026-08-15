class_name CombatStats
extends RefCounted

signal vitality_changed(current_hp: int, max_hp: int)

var max_hp: int
var hp: int
var attack: int
var defense: int


static func from_data(data: Resource) -> CombatStats:
	var stats := CombatStats.new()
	stats.reset_from_data(data)
	return stats


func duplicate_runtime() -> CombatStats:
	var copy := CombatStats.new()
	copy.max_hp = max_hp
	copy.hp = hp
	copy.attack = attack
	copy.defense = defense
	return copy


func reset_from_data(data: Resource) -> void:
	max_hp = maxi(int(data.get("max_hp")), 1)
	hp = max_hp
	attack = maxi(int(data.get("attack")), 0)
	defense = maxi(int(data.get("defense")), 0)


func set_vitality(current_hp: int, maximum_hp: int) -> void:
	var normalized_max := maxi(maximum_hp, 1)
	var normalized_hp := clampi(current_hp, 0, normalized_max)
	if hp == normalized_hp and max_hp == normalized_max:
		return
	max_hp = normalized_max
	hp = normalized_hp
	vitality_changed.emit(hp, max_hp)


func take_damage(amount: int) -> int:
	var incoming: int = maxi(amount, 0)
	var absorbed: int = mini(defense, incoming)
	defense -= absorbed
	var applied: int = incoming - absorbed
	var previous_hp := hp
	hp = maxi(hp - applied, 0)
	if hp != previous_hp:
		vitality_changed.emit(hp, max_hp)
	return applied


func heal(amount: int) -> int:
	var before: int = hp
	hp = mini(hp + maxi(amount, 0), max_hp)
	if hp != before:
		vitality_changed.emit(hp, max_hp)
	return hp - before


func add_defense(amount: int) -> void:
	defense = maxi(defense + amount, 0)


func modify_attack(amount: int) -> void:
	attack = maxi(attack + amount, 0)


func is_alive() -> bool:
	return hp > 0
