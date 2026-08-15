class_name CombatTargetEffectHandler
extends CombatEffectHandler


func _target_id(effect: CombatBatchEffect) -> String:
	return effect.target_entity_ids[0] if effect != null and not effect.target_entity_ids.is_empty() else ""


func _resolve_target(effect: CombatBatchEffect, reader: Variant) -> Dictionary:
	var target_id := _target_id(effect)
	if target_id.is_empty() or reader == null:
		return {}
	if str(reader.get_value(["player", "entity_id"], "")) == target_id:
		return {"entity_id": target_id, "kind": &"player", "path": ["player"], "vitality_key": "hp"}
	if str(reader.get_value(["monster", "entity_id"], "")) == target_id:
		return {"entity_id": target_id, "kind": &"monster", "path": ["monster"], "vitality_key": "hp"}
	if reader.has_method("has_value") and reader.has_value(["cards", target_id]):
		return {"entity_id": target_id, "kind": &"card", "path": ["cards", target_id], "vitality_key": "points"}
	if reader.get_value(["cards", target_id], null) is Dictionary:
		return {"entity_id": target_id, "kind": &"card", "path": ["cards", target_id], "vitality_key": "points"}
	return {}
