class_name CombatBattleClock
extends RefCounted

const MIN_SPEED := 0.05
const MAX_SPEED := 16.0

var battle_speed: float = 1.0
var _remaining_logical_seconds: float = 0.0


func set_battle_speed(value: float) -> void:
	battle_speed = clampf(value, MIN_SPEED, MAX_SPEED)


func schedule(base_logical_seconds: float) -> void:
	_remaining_logical_seconds = maxf(base_logical_seconds, 0.0)


func advance(real_delta: float) -> void:
	_remaining_logical_seconds = maxf(
		_remaining_logical_seconds - maxf(real_delta, 0.0) * battle_speed,
		0.0
	)


func is_ready() -> bool:
	return is_zero_approx(_remaining_logical_seconds)


func remaining_real_seconds() -> float:
	return _remaining_logical_seconds / battle_speed


func scale_duration(base_duration: float) -> float:
	return maxf(base_duration, 0.0) / battle_speed
