class_name CombatEffectPresentationScheduler
extends RefCounted

signal effect_plan_finished(batch_id: String, effect_id: String, effect_key: String)

var _pending_plans: Dictionary = {}
var _running_plans: Dictionary = {}
var _finished_effect_keys: Dictionary = {}
var _held_locks: Dictionary = {}
var _active_handles: Dictionary = {}
var _battle_speed: float = 1.0
var _bridge: Object = null
var _is_pumping: bool = false
var _pump_requested: bool = false
var _canceling: bool = false


func _init(p_bridge: Object = null) -> void:
	_bridge = p_bridge


func enqueue_effect_plan(plan: CombatEffectPresentationPlan) -> void:
	if plan == null or plan.effect_key.is_empty():
		return
	if (
		_pending_plans.has(plan.effect_key)
		or _running_plans.has(plan.effect_key)
		or _finished_effect_keys.has(plan.effect_key)
	):
		return
	_pending_plans[plan.effect_key] = plan
	_pump()


func set_battle_speed(speed: float) -> void:
	_battle_speed = maxf(speed, 0.01)
	for effect_key_value in _active_handles.keys():
		var effect_key := str(effect_key_value)
		if not _running_plans.has(effect_key):
			continue
		var state: Dictionary = _running_plans[effect_key]
		var plan: CombatEffectPresentationPlan = state["plan"]
		var speed_scale := _battle_speed / maxf(plan.requested_battle_speed, 0.01)
		var handles: Dictionary = _active_handles[effect_key]
		for handle_value in handles.values():
			var handle: CombatAnimationHandle = handle_value
			if handle != null and not handle.is_finished():
				handle.set_speed_scale(speed_scale)


func cancel_all() -> void:
	if _canceling:
		return
	_canceling = true

	var plans_to_finish: Dictionary = {}
	for effect_key in _pending_plans.keys():
		plans_to_finish[effect_key] = _pending_plans[effect_key]
	for effect_key in _running_plans.keys():
		var state: Dictionary = _running_plans[effect_key]
		plans_to_finish[effect_key] = state["plan"]

	var handles_to_cancel: Array[CombatAnimationHandle] = []
	for handles_value in _active_handles.values():
		var handles: Dictionary = handles_value
		for handle_value in handles.values():
			var handle: CombatAnimationHandle = handle_value
			if handle != null:
				handles_to_cancel.append(handle)

	_pending_plans.clear()
	_running_plans.clear()
	_held_locks.clear()
	_active_handles.clear()

	for effect_key_value in plans_to_finish.keys():
		var effect_key := str(effect_key_value)
		if _finished_effect_keys.has(effect_key):
			continue
		var plan: CombatEffectPresentationPlan = plans_to_finish[effect_key]
		_finished_effect_keys[effect_key] = true
		effect_plan_finished.emit(plan.batch_id, plan.effect_id, plan.effect_key)

	for handle in handles_to_cancel:
		handle.cancel(true)

	_canceling = false


func is_presenting_effect(effect_key: String) -> bool:
	return _pending_plans.has(effect_key) or _running_plans.has(effect_key)


func _pump() -> void:
	if _canceling:
		return
	if _is_pumping:
		_pump_requested = true
		return
	_is_pumping = true

	while true:
		_pump_requested = false
		var made_progress := _start_ready_effects()
		if _start_ready_clips():
			made_progress = true
		if not made_progress and _resolve_internal_clip_deadlock():
			made_progress = true
		if not made_progress and _resolve_one_effect_dependency_cycle():
			made_progress = true
		if not made_progress and not _pump_requested:
			break

	_is_pumping = false
	if _pump_requested:
		_pump()


func _start_ready_effects() -> bool:
	var started_any := false
	for effect_key_value in _pending_plans.keys():
		var effect_key := str(effect_key_value)
		if not _pending_plans.has(effect_key):
			continue
		var plan: CombatEffectPresentationPlan = _pending_plans[effect_key]
		if not _can_start_effect(plan):
			continue
		_pending_plans.erase(effect_key)
		_running_plans[effect_key] = _create_effect_state(plan)
		_active_handles[effect_key] = {}
		started_any = true
		if plan.clips.is_empty():
			call_deferred("_finish_empty_effect", effect_key)
	return started_any


func _can_start_effect(plan: CombatEffectPresentationPlan) -> bool:
	for dependency_key in plan.starts_after_effect_keys:
		if not _finished_effect_keys.has(dependency_key):
			return false
	return true


func _create_effect_state(plan: CombatEffectPresentationPlan) -> Dictionary:
	var pending_clip_ids: Dictionary = {}
	for clip in plan.clips:
		if clip == null or clip.clip_id.is_empty():
			continue
		pending_clip_ids[clip.clip_id] = true
	return {
		"plan": plan,
		"pending_clip_ids": pending_clip_ids,
		"running_clip_ids": {},
		"finished_clip_ids": {},
	}


func _start_ready_clips() -> bool:
	var started_any := false
	for effect_key_value in _running_plans.keys():
		var effect_key := str(effect_key_value)
		if not _running_plans.has(effect_key):
			continue
		var state: Dictionary = _running_plans[effect_key]
		var pending_clip_ids: Dictionary = state["pending_clip_ids"]
		for clip_id_value in pending_clip_ids.keys():
			var clip_id := str(clip_id_value)
			if not _running_plans.has(effect_key):
				break
			state = _running_plans[effect_key]
			if not (state["pending_clip_ids"] as Dictionary).has(clip_id):
				continue
			var plan: CombatEffectPresentationPlan = state["plan"]
			var clip := plan.get_clip(clip_id)
			if clip == null or not _can_start_clip(state, clip):
				continue
			_start_clip(effect_key, state, clip)
			started_any = true
	return started_any


func _can_start_clip(state: Dictionary, clip: CombatPresentationClip) -> bool:
	var finished_clip_ids: Dictionary = state["finished_clip_ids"]
	for dependency_id in clip.start_after:
		if not finished_clip_ids.has(dependency_id):
			return false
	for resource_lock in clip.resource_locks:
		if _held_locks.has(resource_lock):
			return false
	return true


func _start_clip(
	effect_key: String,
	state: Dictionary,
	clip: CombatPresentationClip
) -> void:
	var owner_key := _clip_owner_key(effect_key, clip.clip_id)
	for resource_lock in clip.resource_locks:
		_held_locks[resource_lock] = owner_key

	(state["pending_clip_ids"] as Dictionary).erase(clip.clip_id)
	(state["running_clip_ids"] as Dictionary)[clip.clip_id] = true

	var plan: CombatEffectPresentationPlan = state["plan"]
	var duration := _calculate_clip_duration(plan, clip)
	var handle: CombatAnimationHandle = null
	if _bridge != null and _bridge.has_method("execute_clip"):
		handle = _bridge.call("execute_clip", clip, duration)
	if handle == null:
		_finish_clip(effect_key, clip.clip_id)
		return

	var handles: Dictionary = _active_handles[effect_key]
	handles[clip.clip_id] = handle
	handle.set_speed_scale(_battle_speed / maxf(plan.requested_battle_speed, 0.01))
	handle.finished.connect(
		_on_clip_finished.bind(effect_key, clip.clip_id),
		CONNECT_ONE_SHOT
	)
	if handle.is_finished():
		_finish_clip(effect_key, clip.clip_id)


func _calculate_clip_duration(
	plan: CombatEffectPresentationPlan,
	clip: CombatPresentationClip
) -> float:
	var total_weight := 0.0
	for candidate in plan.clips:
		total_weight += maxf(candidate.duration_weight, 0.0)
	if total_weight <= 0.0:
		return 0.0
	return plan.recommended_duration * maxf(clip.duration_weight, 0.0) / total_weight


func _on_clip_finished(effect_key: String, clip_id: String) -> void:
	_finish_clip(effect_key, clip_id)


func _finish_clip(effect_key: String, clip_id: String) -> void:
	if not _running_plans.has(effect_key):
		return
	var state: Dictionary = _running_plans[effect_key]
	var running_clip_ids: Dictionary = state["running_clip_ids"]
	if not running_clip_ids.has(clip_id):
		return
	running_clip_ids.erase(clip_id)
	(state["finished_clip_ids"] as Dictionary)[clip_id] = true

	var plan: CombatEffectPresentationPlan = state["plan"]
	var clip := plan.get_clip(clip_id)
	if clip != null:
		var owner_key := _clip_owner_key(effect_key, clip_id)
		for resource_lock in clip.resource_locks:
			if _held_locks.get(resource_lock) == owner_key:
				_held_locks.erase(resource_lock)

	if _active_handles.has(effect_key):
		(_active_handles[effect_key] as Dictionary).erase(clip_id)

	if (
		(state["pending_clip_ids"] as Dictionary).is_empty()
		and running_clip_ids.is_empty()
	):
		_finish_effect(effect_key)
	else:
		_pump()


func _finish_empty_effect(effect_key: String) -> void:
	if not _running_plans.has(effect_key):
		return
	var state: Dictionary = _running_plans[effect_key]
	var plan: CombatEffectPresentationPlan = state["plan"]
	if plan.clips.is_empty():
		_finish_effect(effect_key)


func _finish_effect(effect_key: String) -> void:
	if _finished_effect_keys.has(effect_key):
		return
	var plan: CombatEffectPresentationPlan = null
	if _running_plans.has(effect_key):
		var state: Dictionary = _running_plans[effect_key]
		plan = state["plan"]
		_running_plans.erase(effect_key)
	elif _pending_plans.has(effect_key):
		plan = _pending_plans[effect_key]
		_pending_plans.erase(effect_key)
	if plan == null:
		return

	_release_effect_locks(effect_key)
	_active_handles.erase(effect_key)
	_finished_effect_keys[effect_key] = true
	effect_plan_finished.emit(plan.batch_id, plan.effect_id, plan.effect_key)
	_pump()


func _release_effect_locks(effect_key: String) -> void:
	var owner_prefix := "%s/" % effect_key
	for resource_lock in _held_locks.keys():
		if str(_held_locks[resource_lock]).begins_with(owner_prefix):
			_held_locks.erase(resource_lock)


func _resolve_internal_clip_deadlock() -> bool:
	for effect_key_value in _running_plans.keys():
		var effect_key := str(effect_key_value)
		if not _running_plans.has(effect_key):
			continue
		var state: Dictionary = _running_plans[effect_key]
		var pending_clip_ids: Dictionary = state["pending_clip_ids"]
		var running_clip_ids: Dictionary = state["running_clip_ids"]
		if pending_clip_ids.is_empty() or not running_clip_ids.is_empty():
			continue
		if not _all_pending_clips_wait_for_internal_dependencies(state):
			continue
		push_error("Effect %s has cyclic or unresolved clip dependencies" % effect_key)
		_finish_effect(effect_key)
		return true
	return false


func _all_pending_clips_wait_for_internal_dependencies(state: Dictionary) -> bool:
	var plan: CombatEffectPresentationPlan = state["plan"]
	var pending_clip_ids: Dictionary = state["pending_clip_ids"]
	var finished_clip_ids: Dictionary = state["finished_clip_ids"]
	for clip_id_value in pending_clip_ids.keys():
		var clip := plan.get_clip(str(clip_id_value))
		if clip == null:
			continue
		var has_unfinished_dependency := false
		for dependency_id in clip.start_after:
			if not finished_clip_ids.has(dependency_id):
				has_unfinished_dependency = true
				break
		if not has_unfinished_dependency:
			return false
	return true


func _resolve_one_effect_dependency_cycle() -> bool:
	var visit_states: Dictionary = {}
	var stack: Array[String] = []
	for effect_key_value in _pending_plans.keys():
		var effect_key := str(effect_key_value)
		if int(visit_states.get(effect_key, 0)) != 0:
			continue
		var cycle := _find_pending_effect_cycle(effect_key, visit_states, stack)
		if cycle.is_empty():
			continue
		push_error("Effect dependency cycle: %s" % ", ".join(cycle))
		for cycle_key in cycle:
			_finish_effect(cycle_key)
		return true
	return false


func _find_pending_effect_cycle(
	effect_key: String,
	visit_states: Dictionary,
	stack: Array[String]
) -> Array[String]:
	visit_states[effect_key] = 1
	stack.append(effect_key)
	var plan: CombatEffectPresentationPlan = _pending_plans[effect_key]
	for dependency_key in plan.starts_after_effect_keys:
		if _finished_effect_keys.has(dependency_key) or not _pending_plans.has(dependency_key):
			continue
		var dependency_state := int(visit_states.get(dependency_key, 0))
		if dependency_state == 1:
			var cycle_start := stack.find(dependency_key)
			var cycle: Array[String] = []
			for index in range(cycle_start, stack.size()):
				cycle.append(stack[index])
			return cycle
		if dependency_state == 0:
			var nested_cycle := _find_pending_effect_cycle(dependency_key, visit_states, stack)
			if not nested_cycle.is_empty():
				return nested_cycle
	stack.pop_back()
	visit_states[effect_key] = 2
	return []


func _clip_owner_key(effect_key: String, clip_id: String) -> String:
	return "%s/%s" % [effect_key, clip_id]
