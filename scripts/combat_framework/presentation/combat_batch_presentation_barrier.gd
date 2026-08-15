class_name CombatBatchPresentationBarrier
extends RefCounted

signal completed(batch_id: String)

var _batch_id: String = ""
var _pending_effect_keys: Dictionary = {}
var _completed: bool = false


func configure(batch_id: String, effect_keys: Array[String]) -> void:
	_batch_id = batch_id
	_pending_effect_keys.clear()
	_completed = false
	for effect_key in effect_keys:
		if not effect_key.is_empty():
			_pending_effect_keys[effect_key] = true


func mark_effect_finished(effect_key: String) -> void:
	if _completed or not _pending_effect_keys.has(effect_key):
		return
	_pending_effect_keys.erase(effect_key)
	if _pending_effect_keys.is_empty():
		_complete_once()


func complete_empty_deferred() -> void:
	if _completed or not _pending_effect_keys.is_empty():
		return
	call_deferred("_complete_once")


func cancel_and_complete() -> void:
	_pending_effect_keys.clear()
	_complete_once()


func is_completed() -> bool:
	return _completed


func _complete_once() -> void:
	if _completed:
		return
	_completed = true
	completed.emit(_batch_id)
