class_name CombatEffectBatchQueue
extends RefCounted

var _entries: Array[Dictionary] = []
var _next_sequence: int = 0


func enqueue(batch: CombatEffectBatch) -> void:
	if batch == null:
		return
	batch.enqueue_sequence = _next_sequence
	_entries.append({"batch": batch, "sequence": _next_sequence})
	_next_sequence += 1


func pop_next() -> CombatEffectBatch:
	if _entries.is_empty():
		return null
	var best_index := 0
	for index in range(1, _entries.size()):
		if _comes_before(_entries[index], _entries[best_index]):
			best_index = index
	var entry: Dictionary = _entries[best_index]
	_entries.remove_at(best_index)
	return entry["batch"] as CombatEffectBatch


func peek_next() -> CombatEffectBatch:
	if _entries.is_empty():
		return null
	var best_index := 0
	for index in range(1, _entries.size()):
		if _comes_before(_entries[index], _entries[best_index]):
			best_index = index
	return _entries[best_index]["batch"] as CombatEffectBatch


func size() -> int:
	return _entries.size()


func is_empty() -> bool:
	return _entries.is_empty()


func clear() -> void:
	_entries.clear()


static func _comes_before(left: Dictionary, right: Dictionary) -> bool:
	var left_batch := left["batch"] as CombatEffectBatch
	var right_batch := right["batch"] as CombatEffectBatch
	if left_batch.priority != right_batch.priority:
		return left_batch.priority > right_batch.priority
	return int(left["sequence"]) < int(right["sequence"])
