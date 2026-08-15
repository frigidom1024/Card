class_name FakeCombatPresentationBridge
extends RefCounted

var started_clip_ids: Array[String] = []
var durations: Dictionary = {}
var handles: Dictionary = {}
var missing_clip_types: Array[StringName] = []


func execute_clip(clip: CombatPresentationClip, duration: float) -> CombatAnimationHandle:
	started_clip_ids.append(clip.clip_id)
	durations[clip.clip_id] = duration
	if missing_clip_types.has(clip.clip_type):
		return null
	var handle := CombatAnimationHandle.new()
	handles[clip.clip_id] = handle
	return handle


func finish(clip_id: String) -> void:
	var handle: CombatAnimationHandle = handles.get(clip_id)
	if handle != null:
		handle.complete()
