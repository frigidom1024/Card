class_name CombatPresentationClip
extends RefCounted

var clip_id: String = ""
var clip_type: StringName = &""
var source_entity_id: String = ""
var target_entity_ids: Array[String] = []
var channel: StringName = CombatPresentationClipTypes.MAIN_BATTLE
var resource_locks: Array[StringName] = []
var start_after: Array[String] = []
var duration_weight: float = 1.0
var payload: Dictionary = {}


func duplicate_clip() -> CombatPresentationClip:
	var copy := CombatPresentationClip.new()
	copy.clip_id = clip_id
	copy.clip_type = clip_type
	copy.source_entity_id = source_entity_id
	copy.target_entity_ids.assign(target_entity_ids)
	copy.channel = channel
	copy.resource_locks.assign(resource_locks)
	copy.start_after.assign(start_after)
	copy.duration_weight = duration_weight
	copy.payload = payload.duplicate(true)
	return copy
