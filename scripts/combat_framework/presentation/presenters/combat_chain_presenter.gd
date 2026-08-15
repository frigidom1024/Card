class_name CombatChainPresenter
extends Node


func play_chain_split(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
	return _completed_handle()


func play_chain_reflow(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
	return _completed_handle()


func _completed_handle() -> CombatAnimationHandle:
	var handle := CombatAnimationHandle.new()
	handle.call_deferred("complete")
	return handle
