class_name CombatPenalty
extends RefCounted

enum Type { REMOVE_CARD }
enum Target { TAIL_OF_CARD_CHAIN }

var type: Type
var amount: int
var target: Target


func _init(type: Type, amount: int, target: Target) -> void:
	self.type = type
	self.amount = maxi(amount, 0)
	self.target = target


func duplicate_runtime() -> CombatPenalty:
	return CombatPenalty.new(type, amount, target)
