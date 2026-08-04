class_name CombatPenalty
extends RefCounted

enum Type { REMOVE_TAIL_CARD }

var type: Type
var description: String


func get_type() -> Type:
	return self.type


func get_description() -> String:
	return self.description
