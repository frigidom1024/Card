class_name CombatEffectPresentationPlanBuilder
extends RefCounted

const GOLD_LOCK: StringName = &"hud:gold"
const PLAYER_HEALTH_LOCK: StringName = &"hud:player_hp"
const CHAIN_LAYOUT_LOCK: StringName = &"board_chain_layout"


func build_effect_plans(
	result: CombatEffectBatchResult,
	recommended_duration: float,
	requested_battle_speed: float
) -> Array[CombatEffectPresentationPlan]:
	var groups := _group_events_by_effect(result.events)
	var sorted_groups: Array[Dictionary] = []
	for effect_id in groups:
		var group: Dictionary = groups[effect_id]
		group["effect_id"] = effect_id
		sorted_groups.append(group)
	sorted_groups.sort_custom(_sort_groups_by_sequence)

	var plans: Array[CombatEffectPresentationPlan] = []
	var duration_per_effect := recommended_duration / maxf(float(sorted_groups.size()), 1.0)
	for group in sorted_groups:
		var plan := _build_plan(
			result.batch_id,
			group,
			duration_per_effect,
			requested_battle_speed
		)
		if not plans.is_empty():
			plan.starts_after_effect_keys = [plans.back().effect_key]
		plans.append(plan)
	return plans


func _group_events_by_effect(events: Array[CombatStateEvent]) -> Dictionary:
	var groups: Dictionary = {}
	for event in events:
		if event.effect_id.is_empty():
			continue
		if not groups.has(event.effect_id):
			groups[event.effect_id] = {
				"events": [],
				"sequence": event.sequence,
				"effect_type": &"",
				"effect_tags": [],
				"source_entity_id": event.source_entity_id,
				"target_entity_ids": event.target_entity_ids.duplicate(),
			}
		var group: Dictionary = groups[event.effect_id]
		var group_events: Array = group["events"]
		group_events.append(event)
		group["sequence"] = mini(int(group["sequence"]), event.sequence)
		if event.event_type == CombatEventTypes.EFFECT_APPLIED:
			group["effect_type"] = event.payload.get("effect_type", &"")
			group["effect_tags"] = event.payload.get("effect_tags", []).duplicate()
			group["source_entity_id"] = event.source_entity_id
			group["target_entity_ids"] = event.target_entity_ids.duplicate()
	return groups


func _build_plan(
	batch_id: String,
	group: Dictionary,
	recommended_duration: float,
	requested_battle_speed: float
) -> CombatEffectPresentationPlan:
	var plan := CombatEffectPresentationPlan.new()
	plan.batch_id = batch_id
	plan.effect_id = group["effect_id"]
	plan.effect_key = CombatEffectPresentationPlan.make_effect_key(batch_id, plan.effect_id)
	plan.effect_type = group["effect_type"]
	plan.effect_tags.assign(group["effect_tags"])
	plan.effect_sequence = group["sequence"]
	plan.source_entity_id = group["source_entity_id"]
	plan.target_entity_ids.assign(group["target_entity_ids"])
	plan.requested_battle_speed = maxf(requested_battle_speed, 0.01)
	plan.recommended_duration = recommended_duration

	_append_action_clips(plan)
	var events: Array = group["events"]
	_append_hit_clips(plan, events)
	_append_numeric_clips(plan, events)
	_append_chain_clips(plan, events)
	_append_death_clips(plan, events)
	_chain_clips(plan)
	return plan


func _append_action_clips(plan: CombatEffectPresentationPlan) -> void:
	if plan.effect_tags.has(CombatEffectTags.PRESENTATION_CARD_TRIGGER):
		_append_entity_clip(
			plan,
			CombatPresentationClipTypes.CARD_TRIGGER,
			plan.source_entity_id,
			plan.target_entity_ids
		)
	if plan.effect_tags.has(CombatEffectTags.PRESENTATION_CARD_ATTACK):
		_append_entity_clip(
			plan,
			CombatPresentationClipTypes.CARD_ATTACK,
			plan.source_entity_id,
			plan.target_entity_ids
		)
	if plan.effect_tags.has(CombatEffectTags.PRESENTATION_MONSTER_ATTACK):
		_append_entity_clip(
			plan,
			CombatPresentationClipTypes.MONSTER_ATTACK,
			plan.source_entity_id,
			plan.target_entity_ids
		)


func _append_hit_clips(plan: CombatEffectPresentationPlan, events: Array) -> void:
	var target_kind := _infer_effect_target_kind(plan, events)
	for event: CombatStateEvent in _sorted_events(events):
		if event.event_type != CombatEventTypes.DAMAGE_APPLIED:
			continue
		var target_id := _first_target_id(event, plan)
		if target_kind == &"card":
			_append_fact_entity_clip(
				plan,
				CombatPresentationClipTypes.CARD_HIT,
				event,
				target_id
			)
		elif target_kind == &"monster":
			_append_fact_entity_clip(
				plan,
				CombatPresentationClipTypes.MONSTER_HIT,
				event,
				target_id
			)


func _append_numeric_clips(plan: CombatEffectPresentationPlan, events: Array) -> void:
	for event: CombatStateEvent in _sorted_events(events):
		var clip_type := _numeric_clip_type(event)
		if clip_type == &"":
			continue
		var clip := _new_clip(plan, clip_type)
		clip.source_entity_id = event.source_entity_id
		clip.target_entity_ids.assign(event.target_entity_ids)
		clip.payload = event.payload.duplicate(true)
		var entity_id := _event_entity_id(event, plan)
		if clip_type == CombatPresentationClipTypes.GOLD_CHANGE:
			clip.resource_locks = [GOLD_LOCK]
		elif clip_type == CombatPresentationClipTypes.PLAYER_HEALTH_CHANGE:
			clip.resource_locks = [PLAYER_HEALTH_LOCK]
		elif not entity_id.is_empty():
			clip.resource_locks = [CombatPresentationClipTypes.entity_lock(entity_id)]
		plan.add_clip(clip)


func _append_chain_clips(plan: CombatEffectPresentationPlan, events: Array) -> void:
	for event: CombatStateEvent in _sorted_events(events):
		if event.event_type != CombatEventTypes.CHAIN_SPLIT:
			continue
		var split := _new_clip(plan, CombatPresentationClipTypes.CHAIN_SPLIT)
		split.source_entity_id = event.source_entity_id
		split.target_entity_ids.assign(event.target_entity_ids)
		split.resource_locks = [CHAIN_LAYOUT_LOCK]
		split.payload = event.payload.duplicate(true)
		plan.add_clip(split)

		var reflow := _new_clip(plan, CombatPresentationClipTypes.CHAIN_REFLOW)
		reflow.source_entity_id = event.source_entity_id
		reflow.target_entity_ids.assign(event.target_entity_ids)
		reflow.resource_locks = [CHAIN_LAYOUT_LOCK]
		reflow.payload = event.payload.duplicate(true)
		plan.add_clip(reflow)


func _append_death_clips(plan: CombatEffectPresentationPlan, events: Array) -> void:
	for event: CombatStateEvent in _sorted_events(events):
		var clip_type: StringName = &""
		var entity_id := ""
		if event.event_type == CombatEventTypes.CARD_DIED:
			clip_type = CombatPresentationClipTypes.CARD_DEATH
			entity_id = str(event.payload.get("card_id", _first_target_id(event, plan)))
		elif event.event_type == CombatEventTypes.MONSTER_DIED:
			clip_type = CombatPresentationClipTypes.MONSTER_DEATH
			entity_id = str(event.payload.get("monster_id", _first_target_id(event, plan)))
		if clip_type == &"":
			continue
		_append_fact_entity_clip(plan, clip_type, event, entity_id)


func _append_entity_clip(
	plan: CombatEffectPresentationPlan,
	clip_type: StringName,
	entity_id: String,
	target_entity_ids: Array[String]
) -> void:
	var clip := _new_clip(plan, clip_type)
	clip.source_entity_id = entity_id
	clip.target_entity_ids.assign(target_entity_ids)
	if not entity_id.is_empty():
		clip.resource_locks = [CombatPresentationClipTypes.entity_lock(entity_id)]
	plan.add_clip(clip)


func _append_fact_entity_clip(
	plan: CombatEffectPresentationPlan,
	clip_type: StringName,
	event: CombatStateEvent,
	entity_id: String
) -> void:
	var clip := _new_clip(plan, clip_type)
	clip.source_entity_id = event.source_entity_id
	clip.target_entity_ids.assign(event.target_entity_ids)
	clip.payload = event.payload.duplicate(true)
	if not entity_id.is_empty():
		clip.resource_locks = [CombatPresentationClipTypes.entity_lock(entity_id)]
	plan.add_clip(clip)


func _new_clip(
	plan: CombatEffectPresentationPlan,
	clip_type: StringName
) -> CombatPresentationClip:
	var clip := CombatPresentationClip.new()
	clip.clip_id = "%s:%s:%d" % [plan.effect_id, clip_type, plan.clips.size()]
	clip.clip_type = clip_type
	clip.channel = plan.channel
	return clip


func _chain_clips(plan: CombatEffectPresentationPlan) -> void:
	for index in range(1, plan.clips.size()):
		plan.clips[index].start_after = [plan.clips[index - 1].clip_id]


func _numeric_clip_type(event: CombatStateEvent) -> StringName:
	if event.event_type == CombatEventTypes.SHIELD_CHANGED:
		match _entity_kind(event):
			&"card":
				return CombatPresentationClipTypes.CARD_SHIELD_CHANGE
			&"monster":
				return CombatPresentationClipTypes.MONSTER_SHIELD_CHANGE
	elif event.event_type == CombatEventTypes.CARD_POINTS_CHANGED:
		return CombatPresentationClipTypes.CARD_POINTS_CHANGE
	elif event.event_type == CombatEventTypes.HEALTH_CHANGED:
		match _entity_kind(event):
			&"monster":
				return CombatPresentationClipTypes.MONSTER_HEALTH_CHANGE
			&"player":
				return CombatPresentationClipTypes.PLAYER_HEALTH_CHANGE
	elif event.event_type == CombatEventTypes.GOLD_CHANGED:
		return CombatPresentationClipTypes.GOLD_CHANGE
	return &""


func _infer_effect_target_kind(plan: CombatEffectPresentationPlan, events: Array) -> StringName:
	for event: CombatStateEvent in events:
		var kind := _entity_kind(event)
		if kind == &"card" or kind == &"monster":
			return kind
		if event.event_type == CombatEventTypes.CARD_DIED:
			return &"card"
		if event.event_type == CombatEventTypes.MONSTER_DIED:
			return &"monster"
	if plan.effect_tags.has(CombatEffectTags.PRESENTATION_CARD_ATTACK):
		return &"monster"
	if plan.effect_tags.has(CombatEffectTags.PRESENTATION_MONSTER_ATTACK):
		return &"card"
	return &""


func _event_entity_id(event: CombatStateEvent, plan: CombatEffectPresentationPlan) -> String:
	var path: Array = event.payload.get("path", [])
	if path.size() > 1 and path[0] == "cards":
		return str(path[1])
	return _first_target_id(event, plan)


func _first_target_id(event: CombatStateEvent, plan: CombatEffectPresentationPlan) -> String:
	if not event.target_entity_ids.is_empty():
		return event.target_entity_ids[0]
	if not plan.target_entity_ids.is_empty():
		return plan.target_entity_ids[0]
	return ""


static func _entity_kind(event: CombatStateEvent) -> StringName:
	var path: Array = event.payload.get("path", [])
	if path.size() > 0 and path[0] == "cards":
		return &"card"
	if path.size() > 0 and path[0] == "monster":
		return &"monster"
	if path.size() > 0 and path[0] == "player":
		return &"player"
	return &""


static func _sort_groups_by_sequence(left: Dictionary, right: Dictionary) -> bool:
	if int(left["sequence"]) == int(right["sequence"]):
		return str(left["effect_id"]) < str(right["effect_id"])
	return int(left["sequence"]) < int(right["sequence"])


static func _sort_events_by_sequence(left: CombatStateEvent, right: CombatStateEvent) -> bool:
	return left.sequence < right.sequence


func _sorted_events(events: Array) -> Array:
	var sorted := events.duplicate()
	sorted.sort_custom(_sort_events_by_sequence)
	return sorted
