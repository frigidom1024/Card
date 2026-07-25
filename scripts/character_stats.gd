class_name CharacterStats
extends RefCounted

var max_hp: int = 0          # 最大生命
var hp: int = 0              # 当前生命
var attack: int = 0          # 攻击力
var defense: int = 0         # 防御力

func is_alive() -> bool:
	return hp > 0

func take_damage(damage: int) -> void:
	damage -= defense
	defense = max(defense - damage, 0)
	if damage > 0:
		hp = max(hp - damage, 0)
