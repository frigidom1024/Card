class_name CombatChainPresenter
extends Node

signal split_requested(
	active_card_ids: Array[String],
	detached_card_ids: Array[String],
	target_card_id: String
)
signal reflow_requested(active_card_ids: Array[String])


func play_chain_split(clip: CombatPresentationClip, duration: float) -> CombatAnimationHandle:
	var active_card_ids := _read_string_array(clip.payload.get("active_card_ids", []))
	var detached_card_ids := _read_string_array(clip.payload.get("detached_card_ids", []))
	var target_card_id := str(clip.payload.get("target_card_id", ""))
	split_requested.emit(active_card_ids, detached_card_ids, target_card_id)
	return _delay_handle(duration)


func play_chain_reflow(clip: CombatPresentationClip, duration: float) -> CombatAnimationHandle:
	var active_card_ids := _read_string_array(clip.payload.get("active_card_ids", []))
	reflow_requested.emit(active_card_ids)
	return _delay_handle(duration)


func _read_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is not Array:
		return result
	for item in value:
		result.append(str(item))
	return result


func _delay_handle(duration: float) -> CombatAnimationHandle:
	var handle := CombatAnimationHandle.new()
	if not is_inside_tree() or duration <= 0.0:
		handle.call_deferred("complete")
		return handle
	var tween := create_tween()
	tween.tween_interval(duration)
	handle.bind_tween(tween)
	tree_exiting.connect(
		func() -> void:
			handle.cancel(true),
		CONNECT_ONE_SHOT
	)
	return handle
