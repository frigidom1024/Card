class_name CombatBatchEffect
extends RefCounted

## 批次内部最小的效果协议。这里只描述“要做什么”，不直接修改状态。
var effect_id: String = ""
var effect_type: StringName = &""
var source_entity_id: String = ""
var target_entity_ids: Array[String] = []
var parameters: Dictionary = {}
var tags: Array[StringName] = []


func _init(
	p_effect_type: StringName = &"",
	p_effect_id: String = "",
	p_source_entity_id: String = "",
	p_target_entity_ids: Array[String] = [],
	p_parameters: Dictionary = {}
) -> void:
	effect_type = p_effect_type
	effect_id = p_effect_id
	source_entity_id = p_source_entity_id
	target_entity_ids = p_target_entity_ids.duplicate()
	parameters = p_parameters.duplicate(true)


func add_tag(tag: StringName) -> CombatBatchEffect:
	if not tags.has(tag):
		tags.append(tag)
	return self


func get_parameter(key: Variant, default_value: Variant = null) -> Variant:
	return parameters.get(key, default_value)
