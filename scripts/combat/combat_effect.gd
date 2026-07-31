class_name CombatEffect
extends RefCounted

enum Type { DAMAGE, ADD_DEFENSE, HEAL }
enum Target { PLAYER, MONSTER }
enum SourceType { PLAYER_CARD, ROOT_CARD, MONSTER_ACTION, SYSTEM }

var type: Type
var target: Target
var value: int
var source_type: SourceType
var source_name: String


func _init(
	type: Type, target: Target, value: int, source_type: SourceType, source_name: String = ""
) -> void:
	self.type = type
	self.target = target
	self.value = maxi(value, 0)
	self.source_type = source_type
	self.source_name = source_name
