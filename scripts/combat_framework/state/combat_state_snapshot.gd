class_name CombatStateSnapshot
extends RefCounted

var state_revision: int = 0
var chain_revision: int = 0
var phase: StringName = &"idle"
var data: Dictionary = {}


func get_value(path: Array, default_value: Variant = null) -> Variant:
	if path.is_empty():
		return data
	var cursor: Variant = data
	for key in path:
		if not cursor is Dictionary:
			return default_value
		var dictionary := cursor as Dictionary
		if not dictionary.has(key):
			return default_value
		cursor = dictionary[key]
	return cursor


func has_value(path: Array) -> bool:
	if path.is_empty():
		return true
	var cursor: Variant = data
	for key in path:
		if not cursor is Dictionary:
			return false
		var dictionary := cursor as Dictionary
		if not dictionary.has(key):
			return false
		cursor = dictionary[key]
	return true
