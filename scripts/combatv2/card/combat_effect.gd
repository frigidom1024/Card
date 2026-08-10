class_name CombatEffect
extends RefCounted

## The single runtime representation of a combat outcome or modifier.
##
## Rules only create or mutate these objects. CombatEffectResolver is the only
## layer that applies them to runtime state. This keeps combat logs, animation
## events, and future replay data on the same payload.
enum Type { DAMAGE, ADD_DEFENSE, HEAL, MODIFY_CARD_POINTS }
enum Target { PLAYER, MONSTER, CARD }
enum SourceType { PLAYER_CARD, ROOT_CARD, MONSTER_ACTION, MONSTER_EFFECT, SYSTEM }

var type: Type
var target: Target
var value: int
## Value before card/echo rules modify this effect.
var base_value: int
var source_type: SourceType
## Stable order inside the CombatStep and lifecycle stage that created it.
var sequence: int = -1
var phase: String = ""
var source_name: String
var target_card: CardInstance
var target_name: String
var parameters: Dictionary = {}
var tags: Array = []
var cancelled: bool = false


func _init(
	type: Type,
	target: Target,
	value: int,
	source_type: SourceType,
	source_name: String = "",
	target_card: CardInstance = null,
	parameters: Dictionary = {},
	tags: Array = []
) -> void:
	self.type = type
	self.target = target
	# Point modification is signed: positive grants points, negative removes a
	# temporary combat-only grant during encounter cleanup. Other effects remain
	# non-negative by contract.
	self.value = value if type == Type.MODIFY_CARD_POINTS else maxi(value, 0)
	self.base_value = self.value
	self.source_type = source_type
	self.source_name = source_name
	self.target_card = target_card
	self.parameters = parameters.duplicate(true)
	self.tags = []
	for tag in tags:
		self.tags.append(str(tag))


func duplicate_runtime() -> CombatEffect:
	var copy := CombatEffect.new(
		type, target, value, source_type, source_name, target_card, parameters, tags
	)
	copy.base_value = base_value
	copy.sequence = sequence
	copy.phase = phase
	copy.target_name = target_name
	copy.cancelled = cancelled
	return copy


func set_parameter(key: String, parameter_value: Variant) -> CombatEffect:
	parameters[key] = parameter_value
	return self


func get_parameter(key: String, default_value: Variant = null) -> Variant:
	return parameters.get(key, default_value)


func add_tag(tag: String) -> CombatEffect:
	if not tags.has(tag):
		tags.append(tag)
	return self
