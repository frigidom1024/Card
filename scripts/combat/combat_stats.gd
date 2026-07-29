class_name CombatStats
extends RefCounted

var max_hp: int
var hp: int
var attack: int
var defense: int


static func from_data(data: Resource) -> CombatStats:
	var stats := CombatStats.new()
	stats.reset_from_data(data)
	return stats


func reset_from_data(data: Resource) -> void:
	max_hp = maxi(int(data.get("max_hp")), 1)
	hp = max_hp
	attack = maxi(int(data.get("attack")), 0)
	defense = maxi(int(data.get("defense")), 0)


func take_damage(amount: int) -> int:
	var incoming: int = maxi(amount, 0)
	var absorbed: int = mini(defense, incoming)
	defense -= absorbed
	var applied: int = incoming - absorbed
	hp = maxi(hp - applied, 0)
	return applied


func heal(amount: int) -> int:
	var before: int = hp
	hp = mini(hp + maxi(amount, 0), max_hp)
	return hp - before


func add_defense(amount: int) -> void:
	defense = maxi(defense + amount, 0)


func modify_attack(amount: int) -> void:
	attack = maxi(attack + amount, 0)


func is_alive() -> bool:
	return hp > 0
