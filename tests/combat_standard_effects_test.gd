extends SceneTree

const STATE_SCHEMA_PATH := "res://scripts/combat_framework/state/combat_state_schema.gd"
const STANDARD_LIBRARY_PATH := "res://scripts/combat_framework/effects/combat_standard_effect_library.gd"

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_snapshot_has_value_supports_dictionary_values()
	_test_schema_builds_stable_combat_state()
	_test_schema_preserves_card_points_above_starting_maximum()
	_test_damage_consumes_card_shield_before_points()
	_test_card_death_event_keeps_pre_death_chain_relation()
	_test_monster_death_produces_committed_fact_event()
	_test_standard_numeric_and_phase_effects()
	_test_retreat_operation_splits_chain_before_target()
	_test_gold_shield_operation_commits_cost_and_bonus_atomically()
	_test_gold_shield_operation_rolls_back_when_gold_is_insufficient()
	_test_operation_target_must_still_be_in_chain()
	_test_player_operation_changes_already_queued_attack_resolution()
	quit(1 if _failure_count > 0 else 0)


func _test_snapshot_has_value_supports_dictionary_values() -> void:
	var snapshot := CombatStateSnapshot.new()
	snapshot.data = {"cards": {"card_a": {"points": 3}}}
	_expect(snapshot.has_value(["cards", "card_a"]), "状态快照应能判断 Dictionary 类型的路径存在")
	_expect(not snapshot.has_value(["cards", "missing"]), "状态快照应能判断路径不存在")

func _test_schema_builds_stable_combat_state() -> void:
	var schema = _require_script(STATE_SCHEMA_PATH, "标准战斗状态结构脚本必须存在")
	if schema == null:
		return
	var state: Dictionary = schema.create_initial_state(
		{"entity_id": "player", "hp": 8, "max_hp": 10, "shield": 2, "gold": 7},
		{"entity_id": "monster_a", "hp": 6, "max_hp": 9, "shield": 1, "attack": 3},
		{
			"card_a": {"points": 4, "max_points": 5, "shield": 2},
			"card_b": {"points": 0, "max_points": 3, "shield": 0},
		},
		["card_a", "card_b"]
	)
	_expect(state["player"]["alive"] == true, "状态结构会根据玩家生命派生存活状态")
	_expect(state["monster"]["entity_id"] == "monster_a", "状态结构保留怪物稳定实体 ID")
	_expect(state["cards"]["card_a"]["alive"] == true, "正点数卡牌初始化为存活")
	_expect(state["cards"]["card_b"]["alive"] == false, "零点数卡牌初始化为死亡")
	_expect(state["chain"]["card_ids"] == ["card_a", "card_b"], "状态结构保留牌链稳定 ID 顺序")


func _test_schema_preserves_card_points_above_starting_maximum() -> void:
	var schema = _require_script(STATE_SCHEMA_PATH, "标准战斗状态结构脚本必须存在")
	if schema == null:
		return
	var state: Dictionary = schema.create_initial_state(
		{"entity_id": "player", "hp": 10, "max_hp": 10},
		{"entity_id": "monster", "hp": 5, "max_hp": 5},
		{"boosted_card": {"points": 8, "max_points": 5, "shield": 0}},
		["boosted_card"]
	)
	_expect(state["cards"]["boosted_card"]["points"] == 8, "状态装载不得截断高于初始上限的规则强化点数")

func _test_damage_consumes_card_shield_before_points() -> void:
	var processor: CombatEffectBatchProcessor = _make_standard_processor()
	if processor == null:
		return
	var effect := CombatBatchEffect.new(
		&"damage",
		"damage_card_b",
		"monster_a",
		["card_b"],
		{"amount": 5}
	)
	var batch := CombatBatchFactory.create_monster_attack("monster_hits_card", "monster_a", [effect])
	processor.enqueue(batch)
	var result: CombatEffectBatchResult = processor.process_next()
	var snapshot: CombatStateSnapshot = processor.create_snapshot()
	_expect(result != null and result.is_committed(), "标准伤害效果可以通过批次处理器提交")
	_expect(snapshot.get_value(["cards", "card_b", "shield"], -1) == 0, "卡牌护盾先吸收伤害")
	_expect(snapshot.get_value(["cards", "card_b", "points"], -1) == 1, "剩余伤害再扣除卡牌点数")
	_expect(_has_event(result.events, &"shield_changed"), "护盾变化产生独立表现事件")
	_expect(_has_event(result.events, &"card_points_changed"), "卡牌点数变化产生独立表现事件")
	var damage_event := _find_event(result.events, &"damage_applied")
	_expect(damage_event != null and damage_event.source_entity_id == "monster_a", "伤害事实保留效果来源实体")
	_expect(damage_event != null and damage_event.target_entity_ids == ["card_b"], "伤害事实保留效果目标实体")


func _test_card_death_event_keeps_pre_death_chain_relation() -> void:
	var processor: CombatEffectBatchProcessor = _make_standard_processor()
	if processor == null:
		return
	var effect := CombatBatchEffect.new(
		&"damage",
		"kill_card_b",
		"monster_a",
		["card_b"],
		{"amount": 20}
	)
	var batch := CombatBatchFactory.create_monster_attack("monster_kills_card", "monster_a", [effect])
	processor.enqueue(batch)
	var result: CombatEffectBatchResult = processor.process_next()
	var snapshot: CombatStateSnapshot = processor.create_snapshot()
	var death_event := _find_event(result.events, &"card_died")
	_expect(snapshot.get_value(["cards", "card_b", "alive"], true) == false, "卡牌点数归零后由状态规则确认死亡")
	_expect(death_event != null, "卡牌死亡产生可供触发规划器消费的事实事件")
	if death_event != null:
		_expect(death_event.payload.get("chain_index_before", -1) == 1, "死亡事件记录死亡前牌链下标")
		_expect(death_event.payload.get("previous_card_id_before", "") == "card_a", "死亡事件记录前一张卡牌")
		_expect(death_event.payload.get("next_card_id_before", "") == "card_c", "死亡事件记录后一张卡牌")


func _test_monster_death_produces_committed_fact_event() -> void:
	var processor: CombatEffectBatchProcessor = _make_standard_processor()
	if processor == null:
		return
	var effect := CombatBatchEffect.new(&"damage", "kill_monster", "card_a", ["monster_a"], {"amount": 30})
	processor.enqueue(CombatBatchFactory.create_player_attack("player_kills_monster", "card_a", [effect]))
	var result: CombatEffectBatchResult = processor.process_next()
	_expect(processor.create_snapshot().get_value(["monster", "alive"], true) == false, "怪物生命归零后由状态规则确认死亡")
	_expect(_has_event(result.events, &"monster_died"), "怪物死亡产生独立事实事件")


func _test_standard_numeric_and_phase_effects() -> void:
	var processor: CombatEffectBatchProcessor = _make_standard_processor()
	if processor == null:
		return
	var effects: Array[CombatBatchEffect] = [
		CombatBatchEffect.new(&"modify_shield", "raise_card_shield", "card_a", ["card_b"], {"amount": 3}),
		CombatBatchEffect.new(&"modify_card_points", "lower_card_points", "card_a", ["card_b"], {"amount": -2}),
		CombatBatchEffect.new(&"gain_gold", "reward_gold", "monster_a", ["player"], {"amount": 4}),
		CombatBatchEffect.new(&"set_phase", "enter_resolution", "battle", [], {"phase": &"resolution"}),
	]
	processor.enqueue(CombatBatchFactory.create_card_trigger("standard_numeric_effects", "card_a", "cause", effects))
	var result: CombatEffectBatchResult = processor.process_next()
	var snapshot := processor.create_snapshot()
	_expect(result.is_committed(), "标准数值和阶段效果可以在同一原子批次中提交")
	_expect(snapshot.get_value(["cards", "card_b", "shield"], -1) == 5, "护盾修改效果写入最新草稿")
	_expect(snapshot.get_value(["cards", "card_b", "points"], -1) == 2, "卡牌点数修改效果支持有符号增减")
	_expect(snapshot.get_value(["player", "gold"], -1) == 12, "金币增加效果写入玩家资源")
	_expect(snapshot.phase == &"resolution", "阶段效果通过 StateWriter 修改正式战斗阶段")


func _test_retreat_operation_splits_chain_before_target() -> void:
	var factory = _require_script(
		"res://scripts/combat_framework/protocol/combat_operation_batch_factory.gd",
		"玩家操作批次工厂脚本必须存在"
	)
	var processor: CombatEffectBatchProcessor = _make_standard_processor()
	if factory == null or processor == null:
		return
	var batch: CombatEffectBatch = factory.create_retreat_batch(
		"retreat_before_card_b", "retreat_card", "card_b", 0
	)
	processor.enqueue(batch)
	var result: CombatEffectBatchResult = processor.process_next()
	var snapshot := processor.create_snapshot()
	var split_event := _find_event(result.events, &"chain_split")
	_expect(result.is_committed(), "撤退操作通过玩家操作批次提交")
	_expect(snapshot.get_value(["chain", "card_ids"], []) == ["card_a"], "撤退从目标卡牌前断开，目标及其后继不再参与战斗")
	_expect(snapshot.chain_revision == 1, "撤退拆链只增加一次牌链版本")
	_expect(split_event != null and split_event.payload.get("detached_card_ids", []) == ["card_b", "card_c"], "拆链事件记录被断开的目标和后继卡牌")


func _test_gold_shield_operation_commits_cost_and_bonus_atomically() -> void:
	var factory = _require_script(
		"res://scripts/combat_framework/protocol/combat_operation_batch_factory.gd",
		"玩家操作批次工厂脚本必须存在"
	)
	var processor: CombatEffectBatchProcessor = _make_standard_processor()
	if factory == null or processor == null:
		return
	var batch: CombatEffectBatch = factory.create_gold_shield_batch(
		"gold_for_shield", "forge_card", "card_b", 3, 4, 0
	)
	processor.enqueue(batch)
	var result: CombatEffectBatchResult = processor.process_next()
	var snapshot := processor.create_snapshot()
	_expect(result.is_committed(), "金币强化操作作为单个原子批次提交")
	_expect(snapshot.get_value(["player", "gold"], -1) == 5, "金币强化先扣除执行时的最新金币")
	_expect(snapshot.get_value(["cards", "card_b", "shield"], -1) == 6, "扣费成功后在同一批次强化目标卡牌护盾")
	var gold_event := _find_event(result.events, &"gold_changed")
	_expect(gold_event != null, "金币扣除产生独立表现事件")
	_expect(gold_event != null and gold_event.source_entity_id == "forge_card", "金币变化事件保留操作卡来源")
	_expect(gold_event != null and gold_event.target_entity_ids == ["player"], "金币变化事件保留玩家目标")
	_expect(batch.metadata.get("preview_mode") == &"target_only", "操作批次只声明目标预览，不预测结算结果")


func _test_gold_shield_operation_rolls_back_when_gold_is_insufficient() -> void:
	var factory = _require_script(
		"res://scripts/combat_framework/protocol/combat_operation_batch_factory.gd",
		"玩家操作批次工厂脚本必须存在"
	)
	var processor: CombatEffectBatchProcessor = _make_standard_processor()
	if factory == null or processor == null:
		return
	var batch: CombatEffectBatch = factory.create_gold_shield_batch(
		"insufficient_gold", "forge_card", "card_b", 99, 4, 0
	)
	processor.enqueue(batch)
	var result: CombatEffectBatchResult = processor.process_next()
	var snapshot := processor.create_snapshot()
	_expect(result.status == CombatEffectBatchResult.Status.CANCELED, "金币不足时操作在执行边界取消")
	_expect(result.reason_code == &"insufficient_gold", "取消结果说明金币不足")
	_expect(snapshot.get_value(["player", "gold"], -1) == 8, "取消操作不会扣除金币")
	_expect(snapshot.get_value(["cards", "card_b", "shield"], -1) == 2, "同一批次后续护盾强化不会部分提交")
	_expect(snapshot.state_revision == 0, "金币不足的原子操作不增加状态版本")

func _test_operation_target_must_still_be_in_chain() -> void:
	var factory = _require_script(
		"res://scripts/combat_framework/protocol/combat_operation_batch_factory.gd",
		"玩家操作批次工厂脚本必须存在"
	)
	var processor: CombatEffectBatchProcessor = _make_standard_processor()
	if factory == null or processor == null:
		return
	var batch: CombatEffectBatch = factory.create_gold_shield_batch(
		"off_chain_target", "forge_card", "card_d", 3, 4, 0
	)
	processor.enqueue(batch)
	var result: CombatEffectBatchResult = processor.process_next()
	_expect(result.status == CombatEffectBatchResult.Status.CANCELED, "操作卡只能作用于当前牌链目标")
	_expect(result.reason_code == &"target_not_in_chain", "目标离开牌链时给出明确取消原因")
	_expect(processor.create_snapshot().get_value(["player", "gold"], -1) == 8, "无效目标不会先行扣费")


func _test_player_operation_changes_already_queued_attack_resolution() -> void:
	var factory = _require_script(
		"res://scripts/combat_framework/protocol/combat_operation_batch_factory.gd",
		"玩家操作批次工厂脚本必须存在"
	)
	var processor: CombatEffectBatchProcessor = _make_standard_processor()
	if factory == null or processor == null:
		return
	var queued_damage := CombatBatchEffect.new(
		&"damage", "queued_damage", "monster_a", ["card_b"], {"amount": 5}
	)
	processor.enqueue(CombatBatchFactory.create_monster_attack("queued_monster_attack", "monster_a", [queued_damage]))
	processor.enqueue(factory.create_gold_shield_batch(
		"operation_before_attack", "forge_card", "card_b", 3, 4, 0
	))
	var results := processor.process_all()
	var snapshot := processor.create_snapshot()
	_expect(results.size() == 2 and results[0].batch_id == "operation_before_attack", "玩家操作在批次边界优先于已经排队的自动攻击")
	_expect(snapshot.get_value(["cards", "card_b", "shield"], -1) == 1, "后续攻击从玩家操作提交后的最新护盾状态结算")
	_expect(snapshot.get_value(["cards", "card_b", "points"], -1) == 4, "新增护盾足够时后续攻击不会扣除卡牌点数")

func _make_standard_processor() -> CombatEffectBatchProcessor:
	var schema = _require_script(STATE_SCHEMA_PATH, "标准战斗状态结构脚本必须存在")
	var library = _require_script(STANDARD_LIBRARY_PATH, "标准效果注册入口脚本必须存在")
	if schema == null or library == null:
		return null
	var state_data: Dictionary = schema.create_initial_state(
		{"entity_id": "player", "hp": 10, "max_hp": 10, "shield": 0, "gold": 8},
		{"entity_id": "monster_a", "hp": 12, "max_hp": 12, "shield": 0, "attack": 5},
		{
			"card_a": {"points": 3, "max_points": 3, "shield": 0},
			"card_b": {"points": 4, "max_points": 4, "shield": 2},
			"card_c": {"points": 5, "max_points": 5, "shield": 0},
			"card_d": {"points": 2, "max_points": 2, "shield": 1},
		},
		["card_a", "card_b", "card_c"]
	)
	return library.create_processor(state_data, &"combat")


func _require_script(path: String, message: String):
	if not ResourceLoader.exists(path):
		_expect(false, message)
		return null
	return load(path)


func _has_event(events: Array[CombatStateEvent], event_type: StringName) -> bool:
	return _find_event(events, event_type) != null


func _find_event(events: Array[CombatStateEvent], event_type: StringName) -> CombatStateEvent:
	for event in events:
		if event != null and event.event_type == event_type:
			return event
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
