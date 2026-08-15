class_name CombatEffectPresentationPlan
extends RefCounted

var batch_id: String = ""
var effect_id: String = ""
var effect_key: String = ""
var effect_type: StringName = &""
var effect_tags: Array[StringName] = []
var effect_sequence: int = -1
var source_entity_id: String = ""
var target_entity_ids: Array[String] = []
var channel: StringName = CombatPresentationClipTypes.MAIN_BATTLE
var starts_after_effect_keys: Array[String] = []
var requested_battle_speed: float = 1.0
var recommended_duration: float = 0.0
var clips: Array[CombatPresentationClip] = []


static func make_effect_key(batch_id_value: String, effect_id_value: String) -> String:
	return "%s/%s" % [batch_id_value, effect_id_value]


func add_clip(clip: CombatPresentationClip) -> void:
	if clip != null:
		clips.append(clip)


func get_clip(clip_id_value: String) -> CombatPresentationClip:
	for clip in clips:
		if clip.clip_id == clip_id_value:
			return clip
	return null


func duplicate_plan() -> CombatEffectPresentationPlan:
	var copy := CombatEffectPresentationPlan.new()
	copy.batch_id = batch_id
	copy.effect_id = effect_id
	copy.effect_key = effect_key
	copy.effect_type = effect_type
	copy.effect_tags.assign(effect_tags)
	copy.effect_sequence = effect_sequence
	copy.source_entity_id = source_entity_id
	copy.target_entity_ids.assign(target_entity_ids)
	copy.channel = channel
	copy.starts_after_effect_keys.assign(starts_after_effect_keys)
	copy.requested_battle_speed = requested_battle_speed
	copy.recommended_duration = recommended_duration
	for clip in clips:
		copy.add_clip(clip.duplicate_clip())
	return copy
