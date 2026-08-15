class_name CombatHudPresenter
extends Node


func animate_gold_change(
	_clip: CombatPresentationClip,
	_duration: float
) -> CombatAnimationHandle:
	return _completed_handle()


func animate_player_health_change(
	_clip: CombatPresentationClip,
	_duration: float
) -> CombatAnimationHandle:
	return _completed_handle()


func _completed_handle() -> CombatAnimationHandle:
	var handle := CombatAnimationHandle.new()
	handle.call_deferred("complete")
	return handle
