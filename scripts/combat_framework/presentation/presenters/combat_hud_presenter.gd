class_name CombatHudPresenter
extends Node

@export var gold_label: Label
@export var player_health_label: Label


func animate_gold_change(
	clip: CombatPresentationClip,
	duration: float
) -> CombatAnimationHandle:
	return _animate_number(gold_label, clip, duration)


func animate_player_health_change(
	clip: CombatPresentationClip,
	duration: float
) -> CombatAnimationHandle:
	return _animate_number(player_health_label, clip, duration)


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
