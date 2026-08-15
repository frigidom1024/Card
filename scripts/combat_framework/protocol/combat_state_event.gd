class_name CombatStateEvent
extends RefCounted

## 已经提交的战斗事实。跨层只传稳定 ID，不保存 Node 引用。
var event_id: String = ""
var event_type: StringName = &""
var batch_id: String = ""
var effect_id: String = ""
var cause_event_id: String = ""
var source_entity_id: String = ""
var target_entity_ids: Array[String] = []
var sequence: int = -1
var state_revision: int = -1
var chain_revision: int = -1
var payload: Dictionary = {}


func _init(p_event_type: StringName = &"", p_payload: Dictionary = {}) -> void:
	event_type = p_event_type
	payload = p_payload.duplicate(true)


func duplicate_event() -> CombatStateEvent:
	var copy := CombatStateEvent.new(event_type, payload)
	copy.event_id = event_id
	copy.batch_id = batch_id
	copy.effect_id = effect_id
	copy.cause_event_id = cause_event_id
	copy.source_entity_id = source_entity_id
	copy.target_entity_ids = target_entity_ids.duplicate()
	copy.sequence = sequence
	copy.state_revision = state_revision
	copy.chain_revision = chain_revision
	return copy
