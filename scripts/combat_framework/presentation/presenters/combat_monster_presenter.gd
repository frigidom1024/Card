class_name CombatMonsterPresenter
extends Node

@export var visual_root: CanvasItem
@export var health_label: Label
@export var shield_label: Label


func play_attack(_clip: CombatPresentationClip, duration: float) -> CombatAnimationHandle:
	if not _has_visual_root() or not _supports_transform(visual_root):
		return _completed_handle()
	var original_position: Vector2 = visual_root.get("position")
	var tween_data := _tween_handle(duration)
	var tween: Tween = tween_data[0]
	var handle: CombatAnimationHandle = tween_data[1]
	if tween == null:
		return handle
	var half_duration := duration * 0.5
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		visual_root,
		^"position",
		original_position + Vector2(-24.0, 0.0),
		half_duration
	)
	tween.tween_property(visual_root, ^"position", original_position, half_duration)
	return handle


func play_hit(_clip: CombatPresentationClip, duration: float) -> CombatAnimationHandle:
	if not _has_visual_root():
		return _completed_handle()
	var original_modulate := visual_root.modulate
	var dimmed_modulate := original_modulate
	dimmed_modulate.a = original_modulate.a * 0.35
	var tween_data := _tween_handle(duration)
	var tween: Tween = tween_data[0]
	var handle: CombatAnimationHandle = tween_data[1]
	if tween == null:
		return handle
	var half_duration := duration * 0.5
	tween.tween_property(visual_root, ^"modulate", dimmed_modulate, half_duration)
	tween.tween_property(visual_root, ^"modulate", original_modulate, half_duration)
	return handle


func animate_health_change(
	clip: CombatPresentationClip,
	duration: float
) -> CombatAnimationHandle:
	return _animate_number(health_label, clip, duration)


func animate_shield_change(
	clip: CombatPresentationClip,
	duration: float
) -> CombatAnimationHandle:
	return _animate_number(shield_label, clip, duration)


func play_death(_clip: CombatPresentationClip, duration: float) -> CombatAnimationHandle:
	if not _has_visual_root():
		return _completed_handle()
	var tween_data := _tween_handle(duration)
	var tween: Tween = tween_data[0]
	var handle: CombatAnimationHandle = tween_data[1]
	if tween == null:
		return handle
	var death_modulate := visual_root.modulate
	death_modulate.a = 0.0
	tween.set_parallel(true)
	if _supports_transform(visual_root):
		var original_scale: Vector2 = visual_root.get("scale")
		tween.tween_property(visual_root, ^"scale", original_scale * 0.7, duration)
	tween.tween_property(visual_root, ^"modulate", death_modulate, duration)
	return handle


func _animate_number(
	label: Label,
	clip: CombatPresentationClip,
	duration: float
) -> CombatAnimationHandle:
	if label == null or not is_instance_valid(label):
		return _completed_handle()
	var before := int(clip.payload.get("before", 0))
	var after := int(clip.payload.get("after", before))
	label.text = str(before)
	var tween_data := _tween_handle(duration)
	var tween: Tween = tween_data[0]
	var handle: CombatAnimationHandle = tween_data[1]
	if tween == null:
		label.text = str(after)
		return handle
	tween.tween_method(
		func(value: float) -> void:
			if is_instance_valid(label):
				label.text = str(roundi(value)),
		float(before),
		float(after),
		duration
	)
	tween.tween_callback(
		func() -> void:
			if is_instance_valid(label):
				label.text = str(after)
	)
	return handle


func _tween_handle(duration: float) -> Array:
	var handle := CombatAnimationHandle.new()
	if not is_inside_tree() or duration <= 0.0:
		handle.call_deferred("complete")
		return [null, handle]
	var tween := create_tween()
	handle.bind_tween(tween)
	tree_exiting.connect(
		func() -> void:
			handle.cancel(true),
		CONNECT_ONE_SHOT
	)
	return [tween, handle]


func _completed_handle() -> CombatAnimationHandle:
	var handle := CombatAnimationHandle.new()
	handle.call_deferred("complete")
	return handle


func _has_visual_root() -> bool:
	return visual_root != null and is_instance_valid(visual_root)


func _supports_transform(item: CanvasItem) -> bool:
	return item is Node2D or item is Control
