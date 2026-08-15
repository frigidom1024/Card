class_name CombatCardPresenter
extends Node


func play_trigger(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
	return _completed_handle()


func play_attack(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
	return _completed_handle()


func play_hit(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
	return _completed_handle()


func animate_points_change(
	_clip: CombatPresentationClip,
	_duration: float
) -> CombatAnimationHandle:
	return _completed_handle()


func animate_shield_change(
	_clip: CombatPresentationClip,
	_duration: float
) -> CombatAnimationHandle:
	return _completed_handle()


func play_death(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
	return _completed_handle()


func _completed_handle() -> CombatAnimationHandle:
	var handle := CombatAnimationHandle.new()
	handle.call_deferred("complete")
	return handle
