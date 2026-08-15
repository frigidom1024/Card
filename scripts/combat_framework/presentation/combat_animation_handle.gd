class_name CombatAnimationHandle
extends RefCounted

signal finished

var _finished: bool = false
var _speed_scale: float = 1.0
var _tween: Tween = null


func complete() -> void:
	if _finished:
		return
	_finished = true
	_tween = null
	finished.emit()


func cancel(complete_immediately: bool = true) -> void:
	if _finished:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if complete_immediately:
		complete()


func set_speed_scale(speed_scale: float) -> void:
	_speed_scale = maxf(speed_scale, 0.0001)
	if _tween != null and _tween.is_valid():
		_tween.set_speed_scale(_speed_scale)


func get_speed_scale() -> float:
	return _speed_scale


func bind_tween(tween: Tween) -> void:
	if _finished:
		if tween != null and tween.is_valid():
			tween.kill()
		return
	_tween = tween
	if _tween == null or not _tween.is_valid():
		complete()
		return
	_tween.set_speed_scale(_speed_scale)
	_tween.finished.connect(complete, CONNECT_ONE_SHOT)


func is_finished() -> bool:
	return _finished
