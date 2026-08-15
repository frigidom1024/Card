class_name CombatEffectHandlerRegistry
extends RefCounted

var _handlers: Dictionary = {}


func register(handler: CombatEffectHandler) -> void:
	if handler == null or handler.effect_type == &"":
		return
	_handlers[handler.effect_type] = handler


func unregister(effect_type: StringName) -> void:
	_handlers.erase(effect_type)


func has_handler(effect_type: StringName) -> bool:
	return _handlers.has(effect_type)


func get_handler(effect_type: StringName) -> CombatEffectHandler:
	return _handlers.get(effect_type) as CombatEffectHandler
