# 战斗表现与动画系统实现计划

> **供执行代理使用：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，按任务逐项实现；所有步骤使用复选框跟踪。

**目标：** 在现有惰性战斗框架上实现以 `CombatBatchEffect` 为动画执行单位的棋盘表现系统，同时保留 Batch 的原子状态提交和 `acknowledge_presentation(batch_id)` 门控边界。

**架构：** `CombatEffectBatchProcessor` 先原子提交 Batch，再由 Builder 按 `batch_id/effect_id` 聚合事实事件并为每个 Effect 构建独立 Plan。Scheduler 只接收 Effect Plan，按 Effect 依赖和资源锁播放 Clip；`CombatBatchPresentationBarrier` 聚合一个 Batch 的全部 Effect 完成状态，最后只确认一次 Batch。

**技术栈：** Godot 4.7、GDScript、`RefCounted` 协议对象、Signal、Tween/AnimationPlayer 占位实现、现有 headless `SceneTree` 测试。

**规格：** `docs/superpowers/specs/2026-08-15-combat-presentation-animation-system-design.md`

## 全局约束

- 动画构建、排序、资源锁、播放和完成必须以 Effect 为单位，禁止以 Batch 为动画执行单位。
- Batch 仅作为原子状态提交边界、自动流程门控边界和兼容确认边界。
- 玩家攻击和怪物攻击保持两个独立 Batch，并分别等待各自 Batch 屏障完成。
- Builder 和 Scheduler 禁止通过 `batch_type` 推导 `card_attack`、`monster_attack` 或 `card_trigger`。
- 玩家攻击、怪物攻击和卡牌触发动作由 Effect 标签声明。
- 一个 Batch 可生成零个或多个 `CombatEffectPresentationPlan`；每个 Effect 必须对应一个独立 Plan，无可见 Clip 时也保留空 Plan。
- 同一 Batch 的 Effect 第一阶段按最小事实事件 `sequence` 串行；不同 Batch 在资源不冲突时可以并行。
- 作用于同一实体的局部动画必须通过 `entity:<stable_id>` 资源锁串行。
- 玩家操作 Batch 在主战斗 Effect 播放期间仍可立即提交、结算并产生表现。
- 战斗系统不提供拖拽、碰撞检测、目标预览、高亮、菜单或普通 UI 动画接口。
- 战斗速度同时影响 Driver 的结算间隔和表现动画；修改后必须立即作用于正在播放的句柄。
- Presenter 缺失、Tween 取消、空 Effect、循环依赖或场景退出均不得永久阻塞 Batch 确认。
- 表现层只读取已提交事实，不写 `CombatRuntimeState`，不重新计算伤害、死亡、拆链或战斗结果。
- 不引入“有效伤害”概念；数字动画直接读取事实事件中的 before/after/delta 等字段。

---

## 文件结构

```text
scripts/combat_framework/
├── protocol/
│   └── combat_effect_tags.gd
├── batch/
│   └── combat_effect_batch_processor.gd
├── runtime/
│   ├── combat_linear_chain_flow_provider.gd
│   └── combat_battle_session.gd
└── presentation/
    ├── combat_presentation_clip_types.gd
    ├── combat_presentation_clip.gd
    ├── combat_effect_presentation_plan.gd
    ├── combat_batch_presentation_barrier.gd
    ├── combat_animation_handle.gd
    ├── combat_effect_presentation_plan_builder.gd
    ├── combat_effect_presentation_scheduler.gd
    ├── combat_board_presentation_bridge.gd
    ├── combat_presentation_coordinator.gd
    └── presenters/
        ├── combat_card_presenter.gd
        ├── combat_monster_presenter.gd
        ├── combat_chain_presenter.gd
        └── combat_hud_presenter.gd

tests/
├── combat_effect_presentation_protocol_test.gd
├── combat_effect_presentation_scheduler_test.gd
├── combat_effect_presentation_plan_builder_test.gd
├── combat_board_presentation_bridge_test.gd
├── combat_presenter_smoke_test.gd
├── combat_presentation_coordinator_test.gd
└── combat_animation_speed_integration_test.gd
```

---

### Task 1：补强 Effect 身份协议和动作语义标签

**Files:**
- Create: `scripts/combat_framework/protocol/combat_effect_tags.gd`
- Modify: `scripts/combat_framework/batch/combat_effect_batch_processor.gd`
- Modify: `scripts/combat_framework/runtime/combat_linear_chain_flow_provider.gd`
- Modify: `scripts/combat_framework/protocol/combat_batch_factory.gd`
- Create: `tests/combat_effect_presentation_protocol_test.gd`

**Interfaces:**
- Consumes: `CombatBatchEffect.effect_id`、`effect_type`、`tags`，以及现有 `CombatStateWriter` 自动写入的 `CombatStateEvent.effect_id`。
- Produces: `CombatEffectTags.PRESENTATION_CARD_ATTACK`、`PRESENTATION_MONSTER_ATTACK`、`PRESENTATION_CARD_TRIGGER`；`EFFECT_APPLIED.payload.effect_tags`；批次内唯一 `effect_id` 约束。

- [ ] **Step 1：写入 Effect 协议失败测试**

在 `tests/combat_effect_presentation_protocol_test.gd` 中创建独立 `SceneTree` 测试，至少覆盖以下断言：

```gdscript
extends SceneTree

var _failures := 0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _test_duplicate_effect_id_is_rejected()
    _test_effect_applied_exposes_type_and_tags()
    _test_flow_damage_effects_have_action_tags()
    _test_card_trigger_marks_only_first_visible_effect()
    quit(1 if _failures > 0 else 0)

func _test_duplicate_effect_id_is_rejected() -> void:
    var processor := CombatStandardEffectLibrary.create_processor(_initial_state())
    var first := CombatBatchEffect.new(
        CombatEffectTypes.MODIFY_SHIELD,
        "same",
        "card_a",
        ["card_a"],
        {"amount": 1}
    )
    var second := CombatBatchEffect.new(
        CombatEffectTypes.MODIFY_CARD_POINTS,
        "same",
        "card_a",
        ["card_a"],
        {"amount": 1}
    )
    var effects: Array[CombatBatchEffect] = [first, second]
    var batch := CombatBatchFactory.create_player_operation("duplicate", "operation", effects)
    processor.enqueue(batch)
    var result := processor.process_next()
    _expect(
        result.status == CombatEffectBatchResult.Status.CANCELED,
        "重复 effect_id 必须在提交前被拒绝"
    )
    _expect(result.reason_code == &"duplicate_effect_id", "重复 effect_id 使用稳定错误码")

func _test_effect_applied_exposes_type_and_tags() -> void:
    var processor := CombatStandardEffectLibrary.create_processor(_initial_state())
    var effect := CombatBatchEffect.new(
        CombatEffectTypes.MODIFY_SHIELD,
        "shield",
        "card_a",
        ["card_a"],
        {"amount": 2}
    )
    effect.add_tag(CombatEffectTags.PRESENTATION_CARD_TRIGGER)
    var effects: Array[CombatBatchEffect] = [effect]
    processor.enqueue(CombatBatchFactory.create_player_operation("operation", "operation", effects))
    var result := processor.process_next()
    var applied := _find_event(result.events, CombatEventTypes.EFFECT_APPLIED)
    _expect(applied != null, "提交后必须存在 EFFECT_APPLIED")
    if applied == null:
        return
    _expect(applied.effect_id == "shield", "EFFECT_APPLIED 保留 effect_id")
    _expect(applied.payload["effect_type"] == CombatEffectTypes.MODIFY_SHIELD, "暴露 effect_type")
    _expect(
        applied.payload["effect_tags"] == [CombatEffectTags.PRESENTATION_CARD_TRIGGER],
        "暴露 effect_tags"
    )

func _test_flow_damage_effects_have_action_tags() -> void:
    var processor := CombatStandardEffectLibrary.create_processor(_initial_state())
    var flow := CombatLinearChainFlowProvider.new()
    var snapshot := processor.create_snapshot()
    flow.start(snapshot)

    var player_batch := flow.build_next_batch(snapshot, null)
    _expect(player_batch != null, "必须生成玩家攻击 Batch")
    if player_batch == null:
        return
    _expect(player_batch.effects.size() == 1, "基础玩家攻击只有一个 Damage Effect")
    _expect(
        player_batch.effects[0].tags.has(CombatEffectTags.PRESENTATION_CARD_ATTACK),
        "玩家 Damage Effect 声明卡牌攻击表现"
    )

    processor.enqueue(player_batch)
    var player_result := processor.process_next()
    snapshot = processor.create_snapshot()
    flow.on_batch_finished(player_result, snapshot)

    var monster_batch := flow.build_next_batch(snapshot, player_result)
    _expect(monster_batch != null, "必须独立生成怪物攻击 Batch")
    if monster_batch == null:
        return
    _expect(monster_batch.effects.size() == 1, "基础怪物攻击只有一个 Damage Effect")
    _expect(
        monster_batch.effects[0].tags.has(CombatEffectTags.PRESENTATION_MONSTER_ATTACK),
        "怪物 Damage Effect 声明怪物攻击表现"
    )

func _test_card_trigger_marks_only_first_visible_effect() -> void:
    var first := CombatBatchEffect.new(
        CombatEffectTypes.MODIFY_SHIELD,
        "trigger:shield",
        "card_a",
        ["card_a"],
        {"amount": 1}
    )
    var second := CombatBatchEffect.new(
        CombatEffectTypes.MODIFY_CARD_POINTS,
        "trigger:points",
        "card_a",
        ["card_a"],
        {"amount": 1}
    )
    var effects: Array[CombatBatchEffect] = [first, second]
    var batch := CombatBatchFactory.create_card_trigger(
        "trigger_batch",
        "card_a",
        "cause_event",
        effects
    )
    _expect(
        batch.effects[0].tags.has(CombatEffectTags.PRESENTATION_CARD_TRIGGER),
        "首个 Effect 声明一次卡牌触发表现"
    )
    _expect(
        not batch.effects[1].tags.has(CombatEffectTags.PRESENTATION_CARD_TRIGGER),
        "同一触发 Batch 的后续 Effect 不重复触发卡牌抖动"
    )

func _find_event(events: Array[CombatStateEvent], event_type: StringName) -> CombatStateEvent:
    for event in events:
        if event.event_type == event_type:
            return event
    return null

func _initial_state() -> Dictionary:
    return {
        "player": {"entity_id": "player", "hp": 10, "alive": true, "gold": 10},
        "monster": {"entity_id": "monster", "hp": 10, "shield": 0, "alive": true},
        "cards": {"card_a": {"points": 3, "shield": 0, "alive": true}},
        "chain": {"card_ids": ["card_a"], "detached_card_ids": []},
    }

func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    _failures += 1
    push_error(message)
```

- [ ] **Step 2：运行测试并确认失败原因正确**

```powershell
$godot = (Get-Command Godot_v4.7.1-stable_win64_console.exe).Source
& $godot --headless --path . --script res://tests/combat_effect_presentation_protocol_test.gd
```

Expected: FAIL，至少包含 `CombatEffectTags` 未定义或重复 `effect_id` 未被拒绝。

- [ ] **Step 3：定义 Effect 表现标签**

```gdscript
# scripts/combat_framework/protocol/combat_effect_tags.gd
class_name CombatEffectTags
extends RefCounted

const PRESENTATION_CARD_ATTACK: StringName = &"presentation/card_attack"
const PRESENTATION_MONSTER_ATTACK: StringName = &"presentation/monster_attack"
const PRESENTATION_CARD_TRIGGER: StringName = &"presentation/card_trigger"
```

- [ ] **Step 4：在 Processor 中校验唯一 ID 并暴露标签**

在 `_validate_batch()` 中加入批次内去重：

```gdscript
var effect_ids: Dictionary = {}
for effect in batch.effects:
    if effect == null:
        continue
    if effect.effect_id.is_empty():
        return CombatValidationResult.rejected(&"missing_effect_id", "批次内效果必须具有稳定 ID")
    if effect_ids.has(effect.effect_id):
        return CombatValidationResult.rejected(
            &"duplicate_effect_id",
            "同一批次内 effect_id 必须唯一：%s" % effect.effect_id
        )
    effect_ids[effect.effect_id] = true
```

将 `EFFECT_APPLIED` payload 改为：

```gdscript
writer.emit_event(CombatEventTypes.EFFECT_APPLIED, effect.source_entity_id, {
    "effect_type": effect.effect_type,
    "effect_tags": effect.tags.duplicate(),
}, effect.target_entity_ids)
```

- [ ] **Step 5：在 Effect 创建处设置动作标签**

玩家和怪物攻击 Damage Effect 在 `CombatLinearChainFlowProvider` 中分别添加：

```gdscript
effect.add_tag(CombatEffectTags.PRESENTATION_CARD_ATTACK)
```

```gdscript
effect.add_tag(CombatEffectTags.PRESENTATION_MONSTER_ATTACK)
```

`CombatBatchFactory.create_card_trigger()` 只给第一个非空 Effect 添加触发标签：

```gdscript
for effect in effects:
    if effect == null:
        continue
    effect.add_tag(CombatEffectTags.PRESENTATION_CARD_TRIGGER)
    break
```

该逻辑发生在工厂内，但 Builder 仍只看 Effect 标签，不看 Batch 类型。

- [ ] **Step 6：运行协议与现有战斗测试**

```powershell
& $godot --headless --path . --script res://tests/combat_effect_presentation_protocol_test.gd
& $godot --headless --path . --script res://tests/combat_effect_pipeline_test.gd
& $godot --headless --path . --script res://tests/combat_lazy_battle_flow_test.gd
```

Expected: 三个测试均退出码 `0`。

- [ ] **Step 7：提交协议变更**

```powershell
git add scripts/combat_framework/protocol/combat_effect_tags.gd `
        scripts/combat_framework/batch/combat_effect_batch_processor.gd `
        scripts/combat_framework/runtime/combat_linear_chain_flow_provider.gd `
        scripts/combat_framework/protocol/combat_batch_factory.gd `
        tests/combat_effect_presentation_protocol_test.gd
git commit -m "feat: define effect presentation semantics"
```

---

### Task 2：实现 Effect 表现值对象、Batch 确认屏障和统一动画句柄

**Files:**
- Create: `scripts/combat_framework/presentation/combat_presentation_clip_types.gd`
- Create: `scripts/combat_framework/presentation/combat_presentation_clip.gd`
- Create: `scripts/combat_framework/presentation/combat_effect_presentation_plan.gd`
- Create: `scripts/combat_framework/presentation/combat_batch_presentation_barrier.gd`
- Create: `scripts/combat_framework/presentation/combat_animation_handle.gd`
- Extend: `tests/combat_effect_presentation_protocol_test.gd`

**Interfaces:**
- Produces: `CombatPresentationClip`、`CombatEffectPresentationPlan.make_effect_key()`、`CombatBatchPresentationBarrier.configure()`、`mark_effect_finished()`、`complete_empty_deferred()`、`CombatAnimationHandle.complete()`、`cancel()`、`set_speed_scale()`。
- Constraint: `CombatEffectPresentationPlan` 不保存 `batch_type`，防止后续调度器退化为按 Batch 选择动画。

- [ ] **Step 1：追加失败测试**

```gdscript
func _test_effect_plan_identity_and_deep_copy() -> void:
    var clip := CombatPresentationClip.new()
    clip.clip_id = "shield"
    clip.clip_type = CombatPresentationClipTypes.CARD_SHIELD_CHANGE
    clip.target_entity_ids = ["card_a"]
    clip.payload = {"before": 0, "after": 2}

    var plan := CombatEffectPresentationPlan.new()
    plan.batch_id = "batch_a"
    plan.effect_id = "effect_a"
    plan.effect_key = CombatEffectPresentationPlan.make_effect_key(plan.batch_id, plan.effect_id)
    plan.add_clip(clip)

    var copy := plan.duplicate_plan()
    _expect(plan.effect_key == "batch_a/effect_a", "Effect 使用复合键")
    _expect(copy.clips[0] != clip, "Plan 副本不共享 Clip")
    var property_names: Array[String] = []
    for property in plan.get_property_list():
        property_names.append(str(property["name"]))
    _expect(not property_names.has("batch_type"), "Effect Plan 不携带 batch_type")

func _test_batch_barrier_waits_for_all_effects_once() -> void:
    var completed_count := 0
    var barrier := CombatBatchPresentationBarrier.new()
    barrier.completed.connect(func(_batch_id: String) -> void: completed_count += 1)
    barrier.configure("batch_a", ["batch_a/a", "batch_a/b"])
    barrier.mark_effect_finished("batch_a/a")
    _expect(completed_count == 0, "单个 Effect 完成不能确认 Batch")
    barrier.mark_effect_finished("batch_a/a")
    barrier.mark_effect_finished("batch_a/b")
    barrier.mark_effect_finished("batch_a/b")
    _expect(completed_count == 1, "全部 Effect 完成后只完成一次")

func _test_animation_handle_is_idempotent() -> void:
    var completed_count := 0
    var handle := CombatAnimationHandle.new()
    handle.finished.connect(func() -> void: completed_count += 1)
    handle.complete()
    handle.cancel()
    _expect(completed_count == 1, "句柄完成和取消幂等")
```

- [ ] **Step 2：运行测试确认新类型不存在**

```powershell
& $godot --headless --path . --script res://tests/combat_effect_presentation_protocol_test.gd
```

Expected: FAIL，错误包含 `CombatEffectPresentationPlan`、`CombatBatchPresentationBarrier` 或 `CombatAnimationHandle` 未定义。

- [ ] **Step 3：实现 Clip 类型和值对象**

`CombatPresentationClipTypes` 至少定义：

```gdscript
const CARD_TRIGGER: StringName = &"card_trigger"
const CARD_ATTACK: StringName = &"card_attack"
const CARD_HIT: StringName = &"card_hit"
const CARD_POINTS_CHANGE: StringName = &"card_points_change"
const CARD_SHIELD_CHANGE: StringName = &"card_shield_change"
const CARD_DEATH: StringName = &"card_death"
const MONSTER_ATTACK: StringName = &"monster_attack"
const MONSTER_HIT: StringName = &"monster_hit"
const MONSTER_HEALTH_CHANGE: StringName = &"monster_health_change"
const MONSTER_SHIELD_CHANGE: StringName = &"monster_shield_change"
const MONSTER_DEATH: StringName = &"monster_death"
const CHAIN_SPLIT: StringName = &"chain_split"
const CHAIN_REFLOW: StringName = &"chain_reflow"
const GOLD_CHANGE: StringName = &"gold_change"
const PLAYER_HEALTH_CHANGE: StringName = &"player_health_change"

const MAIN_BATTLE: StringName = &"main_battle"
const PLAYER_OPERATION: StringName = &"player_operation"

static func entity_lock(entity_id: String) -> StringName:
    return StringName("entity:%s" % entity_id)
```

`CombatPresentationClip` 使用规格中的字段，并在 `duplicate_clip()` 中深复制数组和 `payload`。

- [ ] **Step 4：实现不含 Batch 类型的 Effect Plan**

```gdscript
class_name CombatEffectPresentationPlan
extends RefCounted

var batch_id := ""
var effect_id := ""
var effect_key := ""
var effect_type: StringName = &""
var effect_tags: Array[StringName] = []
var effect_sequence := -1
var source_entity_id := ""
var target_entity_ids: Array[String] = []
var channel: StringName = CombatPresentationClipTypes.MAIN_BATTLE
var starts_after_effect_keys: Array[String] = []
var requested_battle_speed := 1.0
var recommended_duration := 0.0
var clips: Array[CombatPresentationClip] = []

static func make_effect_key(batch_id: String, effect_id: String) -> String:
    return "%s/%s" % [batch_id, effect_id]

func add_clip(clip: CombatPresentationClip) -> void:
    if clip != null:
        clips.append(clip)
```

同时实现 `get_clip(clip_id)` 和 `duplicate_plan()`；复制时不得共享 Clip、标签、目标或依赖数组。

- [ ] **Step 5：实现 Batch 聚合屏障**

屏障内部维护 `_pending_effect_keys: Dictionary` 和 `_completed`。`configure()` 去重；`mark_effect_finished()` 只删除已登记键；集合为空时发出一次 `completed(batch_id)`。`complete_empty_deferred()` 使用 `call_deferred("_complete_once")`，确保空 Batch 不在信号连接前同步完成。

- [ ] **Step 6：实现统一动画句柄**

`CombatAnimationHandle` 必须：

```gdscript
signal finished()

func complete() -> void
func cancel(complete_immediately: bool = true) -> void
func set_speed_scale(speed_scale: float) -> void
func bind_tween(tween: Tween) -> void
func is_finished() -> bool
```

`bind_tween()` 连接 Tween 的 `finished`；`cancel(true)` 停止 Tween 后完成；`set_speed_scale()` 保存最新倍率并调用活动 Tween 的 `set_speed_scale()`。所有完成路径必须幂等。

- [ ] **Step 7：运行协议测试并提交**

```powershell
& $godot --headless --path . --script res://tests/combat_effect_presentation_protocol_test.gd
git add scripts/combat_framework/presentation tests/combat_effect_presentation_protocol_test.gd
git commit -m "feat: add effect presentation protocol"
```

Expected: 测试退出码 `0`；提交仅包含本 Task 文件。

---
### Task 3：实现只接收 Effect Plan 的依赖与资源锁调度器

**Files:**
- Create: `scripts/combat_framework/presentation/combat_effect_presentation_scheduler.gd`
- Create: `tests/helpers/fake_combat_presentation_bridge.gd`
- Create: `tests/combat_effect_presentation_scheduler_test.gd`

**Interfaces:**
- Consumes: `CombatEffectPresentationPlan`、`CombatPresentationClip`、`CombatBoardPresentationBridge.execute_clip()`。`CombatEffectPresentationScheduler._init(p_bridge = null)` 允许测试和场景注入 Bridge。
- Produces:

```gdscript
signal effect_plan_finished(batch_id: String, effect_id: String, effect_key: String)

func enqueue_effect_plan(plan: CombatEffectPresentationPlan) -> void
func set_battle_speed(speed: float) -> void
func cancel_all() -> void
func is_presenting_effect(effect_key: String) -> bool
```

- Forbidden: 不提供 `enqueue_batch()`、`enqueue_plan(result)` 或 `plan_finished(batch_id)`；Scheduler 不接收 `CombatEffectBatchResult`。

- [ ] **Step 1：创建可控的 Fake Bridge**

```gdscript
# tests/helpers/fake_combat_presentation_bridge.gd
class_name FakeCombatPresentationBridge
extends RefCounted

var started_clip_ids: Array[String] = []
var durations: Dictionary = {}
var handles: Dictionary = {}
var missing_clip_types: Array[StringName] = []

func execute_clip(clip: CombatPresentationClip, duration: float) -> CombatAnimationHandle:
    started_clip_ids.append(clip.clip_id)
    durations[clip.clip_id] = duration
    if missing_clip_types.has(clip.clip_type):
        return null
    var handle := CombatAnimationHandle.new()
    handles[clip.clip_id] = handle
    return handle

func finish(clip_id: String) -> void:
    var handle: CombatAnimationHandle = handles.get(clip_id)
    if handle != null:
        handle.complete()
```

- [ ] **Step 2：写入失败的 Effect 调度测试**

测试必须构造三个 Effect Plan，而不是三个 Batch 动画：

```gdscript
func _test_same_batch_effects_follow_effect_dependency() -> void:
    var first := _plan("batch", "first", "clip_first", [&"entity:card_a"])
    var second := _plan("batch", "second", "clip_second", [&"entity:monster"])
    second.starts_after_effect_keys = [first.effect_key]
    scheduler.enqueue_effect_plan(first)
    scheduler.enqueue_effect_plan(second)
    _expect(bridge.started_clip_ids == ["clip_first"], "后一个 Effect 尚未启动")
    bridge.finish("clip_first")
    _expect(bridge.started_clip_ids == ["clip_first", "clip_second"], "前一个 Effect 完成后启动")

func _test_different_batches_run_when_locks_do_not_conflict() -> void:
    var attack := _plan("attack_batch", "damage", "attack", [&"entity:monster"])
    var gold := _plan("operation_batch", "spend_gold", "gold", [&"hud:gold"])
    scheduler.enqueue_effect_plan(attack)
    scheduler.enqueue_effect_plan(gold)
    _expect(bridge.started_clip_ids.has("attack"), "主战斗 Effect 已启动")
    _expect(bridge.started_clip_ids.has("gold"), "操作 Effect 可并行")

func _test_same_entity_lock_serializes_across_batches() -> void:
    var damage := _plan("attack_batch", "damage", "damage", [&"entity:card_a"])
    var shield := _plan("operation_batch", "shield", "shield", [&"entity:card_a"])
    scheduler.enqueue_effect_plan(damage)
    scheduler.enqueue_effect_plan(shield)
    _expect(not bridge.started_clip_ids.has("shield"), "同实体 Effect 等待资源锁")
    bridge.finish("damage")
    _expect(bridge.started_clip_ids.has("shield"), "锁释放后启动")
```

还必须覆盖：一个 Effect 内 `start_after`、空 Effect 下一帧完成、Bridge 返回 `null` 时安全跳过、重复完成、`cancel_all()` 释放锁、活动句柄立即收到变速。

- [ ] **Step 3：运行测试确认 Scheduler 不存在**

```powershell
& $godot --headless --path . --script res://tests/combat_effect_presentation_scheduler_test.gd
```

Expected: FAIL，错误包含 `CombatEffectPresentationScheduler` 未定义。

- [ ] **Step 4：实现 Effect 调度状态**

调度器内部按 `effect_key` 保存：

```gdscript
var _pending_plans: Dictionary = {}
var _running_plans: Dictionary = {}
var _finished_effect_keys: Dictionary = {}
var _held_locks: Dictionary = {}
var _active_handles: Dictionary = {}
var _battle_speed := 1.0
var _bridge: CombatBoardPresentationBridge
```

每个运行 Plan 的内部状态至少包含：

```gdscript
{
    "plan": plan,
    "pending_clip_ids": {clip_id: true},
    "running_clip_ids": {clip_id: true},
    "finished_clip_ids": {clip_id: true},
}
```

- [ ] **Step 5：实现 Effect 启动条件**

`_can_start_effect(plan)` 必须同时满足：

```gdscript
for dependency_key in plan.starts_after_effect_keys:
    if not _finished_effect_keys.has(dependency_key):
        return false
return true
```

Effect 启动不要求一次拿到全部 Clip 锁；每个 Clip 在自身依赖完成且全部资源锁可用时独立启动，从而允许同一 Effect 的多目标 Clip 并行。

- [ ] **Step 6：实现 Clip 启动、完成和 Effect 完成**

启动 Clip 时：

1. 检查 `start_after` 中的 Clip 均已完成；
2. 检查 `resource_locks` 均未被其他活动 Clip 持有；
3. 原子占用全部锁；
4. 计算 `duration = plan.recommended_duration * clip.duration_weight / total_weight`；
5. 调用 `_bridge.execute_clip(clip, duration)`；
6. 返回 `null` 时立刻按完成处理；
7. 返回句柄时调用 `handle.set_speed_scale(_battle_speed / plan.requested_battle_speed)` 并连接 `finished`。

一个 Clip 完成时释放它持有的锁并继续调度。一个 Plan 的 pending/running Clip 都为空时发出：

```gdscript
effect_plan_finished.emit(plan.batch_id, plan.effect_id, plan.effect_key)
```

信号只允许发出一次。

- [ ] **Step 7：实现空计划、防循环和取消安全路径**

- 空 Plan 使用 `call_deferred()` 完成，避免同步信号丢失；
- 如果一个运行 Effect 仍有 pending Clip，但没有 running Clip，且所有 pending Clip 都被未完成的内部依赖阻塞，则输出包含 `effect_key` 的错误并安全完成该 Effect；
- 如果所有 pending Effect 都未运行，且依赖只指向已登记但互相等待的 Effect，则安全完成相关 Effect；
- `cancel_all()` 对全部活动句柄调用 `cancel(true)`，清空队列和锁，并为尚未发出完成信号的 Effect 发出一次完成。

- [ ] **Step 8：实现战斗速度即时传递**

```gdscript
func set_battle_speed(speed: float) -> void:
    _battle_speed = maxf(speed, 0.01)
    for effect_key in _active_handles:
        var plan: CombatEffectPresentationPlan = _running_plans[effect_key]["plan"]
        var scale := _battle_speed / maxf(plan.requested_battle_speed, 0.01)
        for handle in _active_handles[effect_key].values():
            handle.set_speed_scale(scale)
```

这里的参数和属性统一命名为“战斗速度”，不得新增“播放速度”设置。

- [ ] **Step 9：运行测试并提交**

```powershell
& $godot --headless --path . --script res://tests/combat_effect_presentation_scheduler_test.gd
git add scripts/combat_framework/presentation/combat_effect_presentation_scheduler.gd `
        tests/helpers/fake_combat_presentation_bridge.gd `
        tests/combat_effect_presentation_scheduler_test.gd
git commit -m "feat: schedule presentation by effect"
```

Expected: 测试退出码 `0`。

---

### Task 4：按 Effect 聚合事实事件并构建独立 Plan

**Files:**
- Create: `scripts/combat_framework/presentation/combat_effect_presentation_plan_builder.gd`
- Create: `tests/combat_effect_presentation_plan_builder_test.gd`

**Interfaces:**
- Consumes: 已提交的 `CombatEffectBatchResult.events`、`EFFECT_APPLIED.payload.effect_type`、`effect_tags`。
- Produces:

```gdscript
func build_effect_plans(
    result: CombatEffectBatchResult,
    recommended_duration: float,
    requested_battle_speed: float
) -> Array[CombatEffectPresentationPlan]
```

- Forbidden: 不允许 `match result.batch_type`；不允许创建“整批攻击 Plan”。

- [ ] **Step 1：写入一个 Batch 多 Effect 的失败测试**

构造一个 committed Result，其中包含生命周期事件、`spend_gold` Effect 和 `modify_shield` Effect：

```gdscript
func _test_one_batch_builds_one_plan_per_effect() -> void:
    var result := CombatEffectBatchResult.new()
    result.status = CombatEffectBatchResult.Status.COMMITTED
    result.batch_id = "operation"
    result.batch_type = CombatEffectBatch.Type.PLAYER_OPERATION
    result.events = [
        _event(CombatEventTypes.PLAYER_OPERATION_STARTED, "", 0),
        _effect_applied("spend", 1, CombatEffectTypes.SPEND_GOLD, []),
        _event(CombatEventTypes.GOLD_CHANGED, "spend", 2, {"path": ["player", "gold"], "before": 10, "after": 7, "delta": -3}),
        _effect_applied("shield", 3, CombatEffectTypes.MODIFY_SHIELD, []),
        _event(CombatEventTypes.SHIELD_CHANGED, "shield", 4, {"path": ["cards", "card_a", "shield"], "before": 0, "after": 3, "delta": 3}),
        _event(CombatEventTypes.PLAYER_OPERATION_FINISHED, "", 5),
    ]
    var plans := builder.build_effect_plans(result, 0.6, 1.0)
    _expect(plans.size() == 2, "一个 Batch 的两个 Effect 生成两个 Plan")
    _expect(plans[0].effect_key == "operation/spend", "第一个 Effect 身份正确")
    _expect(plans[1].effect_key == "operation/shield", "第二个 Effect 身份正确")
    _expect(plans[1].starts_after_effect_keys == [plans[0].effect_key], "同 Batch Effect 默认串行")
```

- [ ] **Step 2：写入禁止按 batch_type 推导动作的测试**

使用相同 `batch_type` 构造两个 Result：一个 Damage Effect 有 `presentation/card_attack` 标签，一个没有。断言只有带标签的 Effect Plan 包含 `CARD_ATTACK`。再把带标签 Effect 放进 `PLAYER_OPERATION` Batch，断言仍生成 `CARD_ATTACK`，证明动作来自 Effect 而不是 Batch。

- [ ] **Step 3：写入 Damage Effect 内部 Clip 顺序测试**

玩家 Damage Effect 的事件包含 `SHIELD_CHANGED`、`HEALTH_CHANGED`、`DAMAGE_APPLIED`、`MONSTER_DIED` 时，断言：

```text
card_attack
    -> monster_hit
        -> monster_shield_change
        -> monster_health_change
            -> monster_death
```

怪物 Damage Effect 则断言：

```text
monster_attack
    -> card_hit
        -> card_shield_change
        -> card_points_change
            -> card_death（若存在）
```

数字 Clip 的 payload 必须直接复制事实事件的 `before`、`after`、`delta`；`DAMAGE_APPLIED` 只用于受击语义，不再生成第二份数值变化 Clip。

- [ ] **Step 4：写入拆链和生命周期过滤测试**

- `CHAIN_SPLIT` 只根据已提交 payload 构建 `CHAIN_SPLIT` 和 `CHAIN_REFLOW`；
- 生命周期事件 `PLAYER_ATTACK_STARTED/FINISHED`、`MONSTER_ATTACK_STARTED/FINISHED`、`BATCH_STARTED/FINISHED` 不生成 Effect Plan 或 Clip；
- `effect_id` 为空的事件不得进入 Effect 分组；
- 不生成 drag、hover、preview、highlight、target_confirm 类型。

- [ ] **Step 5：运行 Builder 测试确认失败**

```powershell
& $godot --headless --path . --script res://tests/combat_effect_presentation_plan_builder_test.gd
```

Expected: FAIL，错误包含 `CombatEffectPresentationPlanBuilder` 未定义。

- [ ] **Step 6：实现事件分组与 Effect 元数据提取**

核心分组结构：

```gdscript
var groups: Dictionary = {}
for event in result.events:
    if event.effect_id.is_empty():
        continue
    if not groups.has(event.effect_id):
        groups[event.effect_id] = {
            "events": [],
            "sequence": event.sequence,
            "effect_type": &"",
            "effect_tags": [],
        }
    groups[event.effect_id]["events"].append(event)
    groups[event.effect_id]["sequence"] = mini(groups[event.effect_id]["sequence"], event.sequence)
    if event.event_type == CombatEventTypes.EFFECT_APPLIED:
        groups[event.effect_id]["effect_type"] = event.payload.get("effect_type", &"")
        groups[event.effect_id]["effect_tags"] = event.payload.get("effect_tags", []).duplicate()
```

按 `sequence` 升序构建 Plan；`effect_key` 使用 `CombatEffectPresentationPlan.make_effect_key(result.batch_id, effect_id)`。第 N 个 Plan 的 `starts_after_effect_keys` 指向第 N-1 个 Plan，从而实现同 Batch Effect 串行而不把它们合并。

- [ ] **Step 7：实现动作标签到 Clip 的映射**

```gdscript
if plan.effect_tags.has(CombatEffectTags.PRESENTATION_CARD_TRIGGER):
    _append_action_clip(plan, CombatPresentationClipTypes.CARD_TRIGGER, plan.source_entity_id)
if plan.effect_tags.has(CombatEffectTags.PRESENTATION_CARD_ATTACK):
    _append_action_clip(plan, CombatPresentationClipTypes.CARD_ATTACK, plan.source_entity_id)
if plan.effect_tags.has(CombatEffectTags.PRESENTATION_MONSTER_ATTACK):
    _append_action_clip(plan, CombatPresentationClipTypes.MONSTER_ATTACK, plan.source_entity_id)
```

`source_entity_id` 和 `target_entity_ids` 优先取该 Effect 的 `EFFECT_APPLIED` 事件；不得读取 `result.batch_type`。

- [ ] **Step 8：实现事实事件到数字、受击、死亡和牌链 Clip 的映射**

实体类型通过事件 `payload.path` 判断：

```gdscript
static func _entity_kind(event: CombatStateEvent) -> StringName:
    var path: Array = event.payload.get("path", [])
    if path.size() > 0 and path[0] == "cards":
        return &"card"
    if path.size() > 0 and path[0] == "monster":
        return &"monster"
    if path.size() > 0 and path[0] == "player":
        return &"player"
    return &""
```

映射规则：

| 事实事件 | Clip |
|---|---|
| `SHIELD_CHANGED` + card | `CARD_SHIELD_CHANGE` |
| `SHIELD_CHANGED` + monster | `MONSTER_SHIELD_CHANGE` |
| `CARD_POINTS_CHANGED` | `CARD_POINTS_CHANGE` |
| `HEALTH_CHANGED` + monster | `MONSTER_HEALTH_CHANGE` |
| `HEALTH_CHANGED` + player | `PLAYER_HEALTH_CHANGE` |
| `GOLD_CHANGED` | `GOLD_CHANGE` |
| `DAMAGE_APPLIED` + card target | `CARD_HIT` |
| `DAMAGE_APPLIED` + monster target | `MONSTER_HIT` |
| `CARD_DIED` | `CARD_DEATH` |
| `MONSTER_DIED` | `MONSTER_DEATH` |
| `CHAIN_SPLIT` | `CHAIN_SPLIT`，随后 `CHAIN_REFLOW` |

每个 Clip 的资源锁必须来自稳定 ID：实体 Clip 使用 `entity:<id>`，金币使用 `hud:gold`，玩家生命使用 `hud:player_hp`，牌链使用 `board_chain_layout`。

- [ ] **Step 9：实现 Effect 时长预算和空 Effect**

把 `recommended_duration` 按 Plan 数量平均分配，再在 Scheduler 内按 Clip 权重分配：

```gdscript
var duration_per_effect := recommended_duration / maxf(float(sorted_groups.size()), 1.0)
plan.recommended_duration = duration_per_effect
plan.requested_battle_speed = maxf(requested_battle_speed, 0.01)
```

即使某 Effect 没有可见 Clip，也必须返回空 Plan，让 Scheduler 下一帧完成该 Effect，不能从 Batch 屏障的 Effect 集合中悄悄丢失。

- [ ] **Step 10：运行 Builder 与协议测试并提交**

```powershell
& $godot --headless --path . --script res://tests/combat_effect_presentation_plan_builder_test.gd
& $godot --headless --path . --script res://tests/combat_effect_presentation_protocol_test.gd
git add scripts/combat_framework/presentation/combat_effect_presentation_plan_builder.gd `
        tests/combat_effect_presentation_plan_builder_test.gd
git commit -m "feat: build animation plans per effect"
```

Expected: 两个测试均退出码 `0`。

---
### Task 5：实现稳定 ID 到棋盘 Presenter 的表现桥

**Files:**
- Create: `scripts/combat_framework/presentation/combat_board_presentation_bridge.gd`
- Create（接口桩）: `scripts/combat_framework/presentation/presenters/combat_card_presenter.gd`
- Create（接口桩）: `scripts/combat_framework/presentation/presenters/combat_monster_presenter.gd`
- Create（接口桩）: `scripts/combat_framework/presentation/presenters/combat_chain_presenter.gd`
- Create（接口桩）: `scripts/combat_framework/presentation/presenters/combat_hud_presenter.gd`
- Create: `tests/combat_board_presentation_bridge_test.gd`

**Interfaces:**
- Consumes: `CombatPresentationClip`。
- Produces:

```gdscript
func register_card(card_id: String, presenter: CombatCardPresenter) -> void
func unregister_card(card_id: String, presenter: CombatCardPresenter = null) -> void
func register_monster(monster_id: String, presenter: CombatMonsterPresenter) -> void
func unregister_monster(monster_id: String, presenter: CombatMonsterPresenter = null) -> void
func set_chain_presenter(presenter: CombatChainPresenter) -> void
func set_hud_presenter(presenter: CombatHudPresenter) -> void
func execute_clip(clip: CombatPresentationClip, duration: float) -> CombatAnimationHandle
func clear() -> void
```

- Constraint: 战斗协议和状态对象只保存稳定 ID；Node 映射只存在于 Bridge。

- [ ] **Step 1：写入路由失败测试**

测试使用轻量 Fake Presenter 记录调用：

```gdscript
func _test_routes_effect_clips_by_stable_id() -> void:
    var card := FakeCardPresenter.new()
    var monster := FakeMonsterPresenter.new()
    bridge.register_card("card_a", card)
    bridge.register_monster("monster", monster)

    var attack := _clip(CombatPresentationClipTypes.CARD_ATTACK, "card_a", ["monster"])
    bridge.execute_clip(attack, 0.2)
    _expect(card.calls == [&"card_attack"], "卡牌攻击路由到来源卡牌")

    var hit := _clip(CombatPresentationClipTypes.MONSTER_HIT, "card_a", ["monster"])
    bridge.execute_clip(hit, 0.2)
    _expect(monster.calls == [&"monster_hit"], "怪物受击路由到目标怪物")
```

还要覆盖护盾/点数/生命、金币、牌链以及缺失 Presenter。缺失 Presenter 返回已经完成的句柄或 `null`，两者都必须允许 Scheduler 安全推进。

- [ ] **Step 2：运行测试确认 Bridge 不存在**

```powershell
& $godot --headless --path . --script res://tests/combat_board_presentation_bridge_test.gd
```

Expected: FAIL，错误包含 `CombatBoardPresentationBridge` 未定义。

- [ ] **Step 3：先创建可编译的 Presenter 接口桩**

四个 Presenter 在本 Task 只建立 Task 5 所需的公开方法。每个方法都返回下一帧完成的 `CombatAnimationHandle`，让 Bridge 的提交能够独立解析、测试和回滚；Task 6 再把这些接口桩替换为占位 Tween。

```gdscript
# combat_card_presenter.gd
class_name CombatCardPresenter
extends Node

func play_trigger(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
    return _completed_handle()

func play_attack(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
    return _completed_handle()

func play_hit(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
    return _completed_handle()

func animate_points_change(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
    return _completed_handle()

func animate_shield_change(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
    return _completed_handle()

func play_death(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
    return _completed_handle()

func _completed_handle() -> CombatAnimationHandle:
    var handle := CombatAnimationHandle.new()
    handle.call_deferred("complete")
    return handle
```

```gdscript
# combat_monster_presenter.gd
class_name CombatMonsterPresenter
extends Node

func play_attack(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
    return _completed_handle()

func play_hit(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
    return _completed_handle()

func animate_health_change(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
    return _completed_handle()

func animate_shield_change(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
    return _completed_handle()

func play_death(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
    return _completed_handle()

func _completed_handle() -> CombatAnimationHandle:
    var handle := CombatAnimationHandle.new()
    handle.call_deferred("complete")
    return handle
```

```gdscript
# combat_chain_presenter.gd
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
```

```gdscript
# combat_hud_presenter.gd
class_name CombatHudPresenter
extends Node

func animate_gold_change(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
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
```

- [ ] **Step 4：实现注册表并自动清理失效节点**

```gdscript
class_name CombatBoardPresentationBridge
extends Node

var _cards: Dictionary = {}
var _monsters: Dictionary = {}
var _chain_presenter: CombatChainPresenter
var _hud_presenter: CombatHudPresenter

func register_card(card_id: String, presenter: CombatCardPresenter) -> void:
    if card_id.is_empty() or presenter == null:
        push_warning("注册卡牌 Presenter 时必须提供稳定 ID 和节点")
        return
    _cards[card_id] = presenter

func unregister_card(card_id: String, presenter: CombatCardPresenter = null) -> void:
    if not _cards.has(card_id):
        return
    if presenter != null and _cards.get(card_id) != presenter:
        return
    _cards.erase(card_id)

func register_monster(monster_id: String, presenter: CombatMonsterPresenter) -> void:
    if monster_id.is_empty() or presenter == null:
        push_warning("注册怪物 Presenter 时必须提供稳定 ID 和节点")
        return
    _monsters[monster_id] = presenter

func unregister_monster(
    monster_id: String,
    presenter: CombatMonsterPresenter = null
) -> void:
    if not _monsters.has(monster_id):
        return
    if presenter != null and _monsters.get(monster_id) != presenter:
        return
    _monsters.erase(monster_id)

func set_chain_presenter(presenter: CombatChainPresenter) -> void:
    _chain_presenter = presenter

func set_hud_presenter(presenter: CombatHudPresenter) -> void:
    _hud_presenter = presenter

func clear() -> void:
    _cards.clear()
    _monsters.clear()
    _chain_presenter = null
    _hud_presenter = null

func _card(card_id: String) -> CombatCardPresenter:
    var presenter: CombatCardPresenter = _cards.get(card_id)
    if not _is_live_presenter(presenter):
        _cards.erase(card_id)
        return null
    return presenter

func _monster(monster_id: String) -> CombatMonsterPresenter:
    var presenter: CombatMonsterPresenter = _monsters.get(monster_id)
    if not _is_live_presenter(presenter):
        _monsters.erase(monster_id)
        return null
    return presenter

func _target_card(clip: CombatPresentationClip) -> CombatCardPresenter:
    return _card(_first_target_id(clip))

func _target_monster(clip: CombatPresentationClip) -> CombatMonsterPresenter:
    return _monster(_first_target_id(clip))

func _chain() -> CombatChainPresenter:
    if not _is_live_presenter(_chain_presenter):
        _chain_presenter = null
    return _chain_presenter

func _hud() -> CombatHudPresenter:
    if not _is_live_presenter(_hud_presenter):
        _hud_presenter = null
    return _hud_presenter

func _first_target_id(clip: CombatPresentationClip) -> String:
    return clip.target_entity_ids[0] if not clip.target_entity_ids.is_empty() else ""

func _is_live_presenter(presenter: Node) -> bool:
    return presenter != null and is_instance_valid(presenter) and presenter.is_inside_tree()
```

`unregister_*()` 带 presenter 参数时只删除相同实例，避免旧节点退出时误删新注册节点。实体、牌链和 HUD 的 getter 都同时检查空引用、失效实例和是否仍在场景树中。

- [ ] **Step 5：按 clip_type 路由，不读取 Batch 信息**

```gdscript
match clip.clip_type:
    CombatPresentationClipTypes.CARD_TRIGGER:
        var source_card := _card(clip.source_entity_id)
        return source_card.play_trigger(clip, duration) if source_card != null else _missing(clip)
    CombatPresentationClipTypes.CARD_ATTACK:
        var attacking_card := _card(clip.source_entity_id)
        return attacking_card.play_attack(clip, duration) if attacking_card != null else _missing(clip)
    CombatPresentationClipTypes.CARD_HIT:
        var hit_card := _target_card(clip)
        return hit_card.play_hit(clip, duration) if hit_card != null else _missing(clip)
    CombatPresentationClipTypes.CARD_POINTS_CHANGE:
        var points_card := _target_card(clip)
        return points_card.animate_points_change(clip, duration) if points_card != null else _missing(clip)
    CombatPresentationClipTypes.CARD_SHIELD_CHANGE:
        var shield_card := _target_card(clip)
        return shield_card.animate_shield_change(clip, duration) if shield_card != null else _missing(clip)
    CombatPresentationClipTypes.CARD_DEATH:
        var dead_card := _target_card(clip)
        return dead_card.play_death(clip, duration) if dead_card != null else _missing(clip)
    CombatPresentationClipTypes.MONSTER_ATTACK:
        var attacking_monster := _monster(clip.source_entity_id)
        return attacking_monster.play_attack(clip, duration) if attacking_monster != null else _missing(clip)
    CombatPresentationClipTypes.MONSTER_HIT:
        var hit_monster := _target_monster(clip)
        return hit_monster.play_hit(clip, duration) if hit_monster != null else _missing(clip)
    CombatPresentationClipTypes.MONSTER_HEALTH_CHANGE:
        var health_monster := _target_monster(clip)
        return health_monster.animate_health_change(clip, duration) if health_monster != null else _missing(clip)
    CombatPresentationClipTypes.MONSTER_SHIELD_CHANGE:
        var shield_monster := _target_monster(clip)
        return shield_monster.animate_shield_change(clip, duration) if shield_monster != null else _missing(clip)
    CombatPresentationClipTypes.MONSTER_DEATH:
        var dead_monster := _target_monster(clip)
        return dead_monster.play_death(clip, duration) if dead_monster != null else _missing(clip)
    CombatPresentationClipTypes.CHAIN_SPLIT:
        var chain := _chain()
        return chain.play_chain_split(clip, duration) if chain != null else _missing(clip)
    CombatPresentationClipTypes.CHAIN_REFLOW:
        var reflow_chain := _chain()
        return reflow_chain.play_chain_reflow(clip, duration) if reflow_chain != null else _missing(clip)
    CombatPresentationClipTypes.GOLD_CHANGE:
        var gold_hud := _hud()
        return gold_hud.animate_gold_change(clip, duration) if gold_hud != null else _missing(clip)
    CombatPresentationClipTypes.PLAYER_HEALTH_CHANGE:
        var health_hud := _hud()
        return health_hud.animate_player_health_change(clip, duration) if health_hud != null else _missing(clip)
    _:
        return _missing(clip)
```

`_chain()` 与 `_hud()` 和实体注册表 getter 使用相同的有效性检查：`null`、失效实例或已离开场景树都返回 `null` 并清理引用。`_missing(clip)` 输出包含 `clip.clip_id` 的 warning 并返回安全完成句柄。Bridge 不接受 Result、Batch、`batch_type` 或 Effect 标签；这些已经由 Builder 转换成 Clip。

- [ ] **Step 6：实现安全完成帮助函数**

```gdscript
func _missing(clip: CombatPresentationClip) -> CombatAnimationHandle:
    push_warning("跳过无法路由的战斗表现 Clip：%s" % clip.clip_id)
    return _completed_handle()

func _completed_handle() -> CombatAnimationHandle:
    var handle := CombatAnimationHandle.new()
    handle.call_deferred("complete")
    return handle
```

Presenter 缺失、目标 ID 为空、Clip 类型未知时统一调用 `_missing(clip)`，不得返回一个永远不会结束的等待对象。

- [ ] **Step 7：运行 Bridge 和 Scheduler 测试并提交**

```powershell
& $godot --headless --path . --script res://tests/combat_board_presentation_bridge_test.gd
& $godot --headless --path . --script res://tests/combat_effect_presentation_scheduler_test.gd
git add scripts/combat_framework/presentation/combat_board_presentation_bridge.gd `
        scripts/combat_framework/presentation/presenters `
        tests/combat_board_presentation_bridge_test.gd
git commit -m "feat: route effect clips to board presenters"
```

Expected: 两个测试均退出码 `0`。

---

### Task 6：实现卡牌、怪物、牌链和 HUD 占位动画接口

**Files:**
- Modify: `scripts/combat_framework/presentation/presenters/combat_card_presenter.gd`
- Modify: `scripts/combat_framework/presentation/presenters/combat_monster_presenter.gd`
- Modify: `scripts/combat_framework/presentation/presenters/combat_chain_presenter.gd`
- Modify: `scripts/combat_framework/presentation/presenters/combat_hud_presenter.gd`
- Create: `tests/combat_presenter_smoke_test.gd`

**Interfaces:**
- Card: `play_trigger()`、`play_attack()`、`play_hit()`、`animate_points_change()`、`animate_shield_change()`、`play_death()`。
- Monster: `play_attack()`、`play_hit()`、`animate_health_change()`、`animate_shield_change()`、`play_death()`。
- Chain: `play_chain_split()`、`play_chain_reflow()`。
- HUD: `animate_gold_change()`、`animate_player_health_change()`。
- 所有方法签名统一为 `(clip: CombatPresentationClip, duration: float) -> CombatAnimationHandle`。

- [ ] **Step 1：写入 Presenter 冒烟失败测试**

测试动态创建 Presenter 和最小显示节点：

```gdscript
func _test_card_number_clip_uses_committed_after_value() -> void:
    var card := CombatCardPresenter.new()
    var points_label := Label.new()
    card.points_label = points_label
    root.add_child(card)
    card.add_child(points_label)

    var clip := CombatPresentationClip.new()
    clip.clip_id = "points"
    clip.clip_type = CombatPresentationClipTypes.CARD_POINTS_CHANGE
    clip.payload = {"before": 5, "after": 2, "delta": -3}
    var handle := card.animate_points_change(clip, 0.01)
    await handle.finished
    _expect(points_label.text == "2", "点数显示已提交 after，不重新计算")
```

还要分别调用卡牌触发、双方攻击、受击、护盾、生命、金币、拆链和死亡接口，断言每个方法都返回最终会完成的 `CombatAnimationHandle`。

- [ ] **Step 2：运行测试确认接口桩尚未实现动画和最终值写入**

```powershell
& $godot --headless --path . --script res://tests/combat_presenter_smoke_test.gd
```

Expected: FAIL，因为接口桩尚未更新 Label、未创建 Tween，也未保证动画结束后的最终显示值。

- [ ] **Step 3：实现公共 Tween 句柄模式**

每个 Presenter 的 Tween 方法遵循相同模式：

```gdscript
func _tween_handle(duration: float) -> Array:
    var handle := CombatAnimationHandle.new()
    if not is_inside_tree() or duration <= 0.0:
        handle.call_deferred("complete")
        return [null, handle]
    var tween := create_tween()
    handle.bind_tween(tween)
    tree_exiting.connect(func() -> void: handle.cancel(true), CONNECT_ONE_SHOT)
    return [tween, handle]
```

不得把 Tween 暴露给 Scheduler。节点退出、Tween 被 kill 或没有显示节点时必须完成句柄。

- [ ] **Step 4：实现卡牌触发、攻击和受击占位动作**

`CombatCardPresenter` 暴露可替换的显示根节点：

```gdscript
@export var visual_root: CanvasItem
@export var points_label: Label
@export var shield_label: Label
```

占位动作：

- `play_trigger()`：`visual_root.scale` 在原值和 `1.06` 倍之间往返；
- `play_attack()`：沿局部 X 方向短移后归位；
- `play_hit()`：短暂降低 `modulate.a` 后恢复；
- `play_death()`：缩放和透明度归零。

每个方法只改显示节点，不修改任何战斗对象或 `CardInstance`。

- [ ] **Step 5：实现数字变化接口**

数字接口立即读取并保存：

```gdscript
var before := int(clip.payload.get("before", 0))
var after := int(clip.payload.get("after", before))
```

Tween 可以从 `before` 插值到 `after`，但最终必须显式设置 `label.text = str(after)`。没有 Label 时返回安全完成句柄。禁止使用 `incoming - absorbed` 等公式重新计算结果。

- [ ] **Step 6：实现怪物、牌链和 HUD Presenter**

- `CombatMonsterPresenter` 与卡牌相同，生命字段使用 `health_label`；
- `CombatChainPresenter.play_chain_split()` 只读取 `active_card_ids`、`detached_card_ids`、`target_card_id`；
- `play_chain_reflow()` 调用一个可注入的布局回调或发出 `reflow_requested(active_card_ids)` 信号；
- `CombatHudPresenter` 只更新 `gold_label` 和 `player_health_label`。

牌链 Presenter 不负责拖拽、碰撞、目标预览或高亮，也不预测拆链后的数组。

- [ ] **Step 7：运行 Presenter、Bridge 和格式测试**

```powershell
& $godot --headless --path . --script res://tests/combat_presenter_smoke_test.gd
& $godot --headless --path . --script res://tests/combat_board_presentation_bridge_test.gd
& $godot --headless --path . --script res://tests/combat_effect_presentation_scheduler_test.gd
```

Expected: 三个测试均退出码 `0`，并且没有 orphan Node 报告。

- [ ] **Step 8：提交 Presenter 占位实现**

```powershell
git add scripts/combat_framework/presentation/presenters `
        tests/combat_presenter_smoke_test.gd
git commit -m "feat: add combat board animation presenters"
```

---
### Task 7：接入 Session 战斗速度信号和 Effect 表现总协调器

**Files:**
- Modify: `scripts/combat_framework/runtime/combat_battle_session.gd`
- Create: `scripts/combat_framework/presentation/combat_presentation_coordinator.gd`
- Create: `tests/combat_presentation_coordinator_test.gd`

**Interfaces:**
- Session 新增：

```gdscript
signal battle_speed_changed(speed: float)
func get_battle_speed() -> float
```

- Coordinator 新增：

```gdscript
func configure(
    session: CombatBattleSession,
    builder: CombatEffectPresentationPlanBuilder,
    scheduler: CombatEffectPresentationScheduler
) -> void
func shutdown() -> void
func get_pending_batch_ids() -> Array[String]
```

- Constraint: Coordinator 是唯一把多个 Effect 完成聚合回 `acknowledge_presentation(batch_id)` 的组件；Scheduler 不得直接确认 Batch。

- [ ] **Step 1：写入 Coordinator 失败测试**

```gdscript
func _test_batch_ack_waits_for_every_effect_plan() -> void:
    var session := FakeCombatBattleSession.new()
    var builder := FakeEffectPlanBuilder.new()
    var scheduler := FakeEffectScheduler.new()
    var coordinator := CombatPresentationCoordinator.new()
    coordinator.configure(session, builder, scheduler)

    var result := _result_with_two_effects("batch_a", "first", "second")
    session.presentation_requested.emit(result, 0.4)
    _expect(scheduler.enqueued_effect_keys == ["batch_a/first", "batch_a/second"], "逐 Effect 入队")

    scheduler.effect_plan_finished.emit("batch_a", "first", "batch_a/first")
    _expect(session.acknowledged_batch_ids.is_empty(), "一个 Effect 完成不确认 Batch")
    scheduler.effect_plan_finished.emit("batch_a", "second", "batch_a/second")
    _expect(session.acknowledged_batch_ids == ["batch_a"], "全部 Effect 完成后确认一次 Batch")
```

还必须覆盖：空 Batch 下一帧确认、空 Effect Plan 也被屏障登记、重复 Effect 完成不重复确认、两个 Batch 的屏障彼此独立、`shutdown()` 最终确认并清理所有屏障。

- [ ] **Step 2：写入 Session 战斗速度失败测试**

```gdscript
func _test_session_emits_clamped_battle_speed() -> void:
    var session := CombatBattleSession.new(_initial_state())
    var emitted: Array[float] = []
    session.battle_speed_changed.connect(func(speed: float) -> void: emitted.append(speed))
    session.set_battle_speed(4.0)
    _expect(is_equal_approx(session.get_battle_speed(), 4.0), "Session 暴露战斗速度")
    _expect(emitted == [4.0], "战斗速度变化向表现层广播")
```

- [ ] **Step 3：运行测试确认接口不存在**

```powershell
& $godot --headless --path . --script res://tests/combat_presentation_coordinator_test.gd
```

Expected: FAIL，错误包含 `CombatPresentationCoordinator` 或 `battle_speed_changed` 未定义。

- [ ] **Step 4：实现 Session 战斗速度查询与信号**

```gdscript
signal battle_speed_changed(speed: float)

func set_battle_speed(speed: float) -> void:
    var before := driver.get_battle_speed()
    driver.set_battle_speed(speed)
    var after := driver.get_battle_speed()
    if not is_equal_approx(before, after):
        battle_speed_changed.emit(after)

func get_battle_speed() -> float:
    return driver.get_battle_speed()
```

信号发送的是 `CombatBattleClock` 限制到 `[0.05, 16.0]` 后的真实战斗速度。

- [ ] **Step 5：实现 committed Result 到多个 Effect Plan 的协调流程**

```gdscript
func _on_presentation_requested(
    result: CombatEffectBatchResult,
    recommended_duration: float
) -> void:
    var plans := _builder.build_effect_plans(
        result,
        recommended_duration,
        _session.get_battle_speed()
    )
    var effect_keys: Array[String] = []
    for plan in plans:
        effect_keys.append(plan.effect_key)

    var barrier := CombatBatchPresentationBarrier.new()
    barrier.configure(result.batch_id, effect_keys)
    barrier.completed.connect(_on_batch_barrier_completed, CONNECT_ONE_SHOT)
    _barriers[result.batch_id] = barrier

    if plans.is_empty():
        barrier.complete_empty_deferred()
        return
    for plan in plans:
        _scheduler.enqueue_effect_plan(plan)
```

这一方法可以看见 Batch Result 以便创建屏障，但它绝不创建 Batch 动画；交给 Scheduler 的对象只能是 Effect Plan。

- [ ] **Step 6：把 Effect 完成映射到所属 Batch 屏障**

```gdscript
func _on_effect_plan_finished(
    batch_id: String,
    _effect_id: String,
    effect_key: String
) -> void:
    var barrier: CombatBatchPresentationBarrier = _barriers.get(batch_id)
    if barrier != null:
        barrier.mark_effect_finished(effect_key)

func _on_batch_barrier_completed(batch_id: String) -> void:
    if not _barriers.has(batch_id):
        return
    _barriers.erase(batch_id)
    _session.acknowledge_presentation(batch_id)
```

`acknowledge_presentation()` 只能出现在屏障完成回调和 shutdown 的安全收尾中，不能出现在单个 Effect/Clip 完成回调中。

- [ ] **Step 7：连接战斗速度和关闭流程**

`configure()` 连接：

```gdscript
_session.presentation_requested.connect(_on_presentation_requested)
_session.battle_speed_changed.connect(_scheduler.set_battle_speed)
_scheduler.effect_plan_finished.connect(_on_effect_plan_finished)
_scheduler.set_battle_speed(_session.get_battle_speed())
```

`shutdown()` 顺序：

1. 断开 Session 新请求和速度信号；
2. 调用 Scheduler `cancel_all()`；
3. 对仍存在的 Barrier 调用 `cancel_and_complete()`；
4. 清空 Barrier 字典；
5. 断开 Scheduler 完成信号。

所有步骤幂等。

- [ ] **Step 8：运行 Coordinator、Session 和既有惰性流程测试**

```powershell
& $godot --headless --path . --script res://tests/combat_presentation_coordinator_test.gd
& $godot --headless --path . --script res://tests/combat_lazy_battle_flow_test.gd
& $godot --headless --path . --script res://tests/combat_batch_runtime_framework_test.gd
```

Expected: 三个测试均退出码 `0`。

- [ ] **Step 9：提交协调器和 Session 接口**

```powershell
git add scripts/combat_framework/runtime/combat_battle_session.gd `
        scripts/combat_framework/presentation/combat_presentation_coordinator.gd `
        tests/combat_presentation_coordinator_test.gd
git commit -m "feat: coordinate effect presentation barriers"
```

---

### Task 8：验证操作 Effect 并行、动态战斗速度和自动流程门控

**Files:**
- Create: `tests/combat_animation_speed_integration_test.gd`
- Modify: `tests/combat_lazy_battle_flow_test.gd`
- Modify: `scripts/combat_framework/README.md`

**Interfaces:**
- Consumes: `CombatBattleSession`、Coordinator、Builder、Scheduler、Fake Bridge、`CombatOperationBatchFactory`。
- Produces: 可运行的端到端惰性战斗表现框架，以及中文组装示例。

- [ ] **Step 1：写入玩家攻击 Effect 播放期间提交操作 Batch 的集成测试**

测试步骤必须严格区分 Batch 提交和 Effect 动画：

```gdscript
session.driver.require_presentation_acknowledgement = true
coordinator.configure(session, builder, scheduler)
session.start()
session.advance(0.0) # 提交并结算玩家攻击 Batch，Damage Effect 开始表现

var operation := CombatOperationBatchFactory.create_gold_shield_batch(
    "operation:shield",
    "forge_card",
    "card_a",
    2,
    3,
    session.create_snapshot().chain_revision
)
_expect(session.submit_player_operation(operation), "主战斗 Effect 播放时允许提交操作")
session.advance(0.0) # 即刻结算操作 Batch

_expect(fake_bridge.started_clip_ids.has("...gold..."), "金币 Effect 可与主战斗 Effect 并行")
_expect(not fake_bridge.started_clip_ids.has("...shield..."), "同卡牌实体锁冲突时护盾 Effect 等待")
```

测试不要断言具体自动生成的 clip_id 字面量；通过 Plan 的 `effect_key` 和 Clip 类型定位句柄，避免把 ID 格式误当协议。

- [ ] **Step 2：验证所有待确认 Batch 完成前不生成怪物攻击**

分别完成玩家 Damage Effect 和操作 Batch 的两个 Effect：

1. 玩家 Damage Effect 完成后，只确认玩家攻击 Batch；
2. `spend_gold` 和 `modify_shield` 都完成后，才确认操作 Batch；
3. 任一 Batch 仍在 Driver 的 `_pending_presentation_ids` 中时，`advance()` 不得生成怪物攻击 Batch；
4. 两个 Batch 均确认且逻辑间隔到期后，才生成独立的怪物攻击 Batch。

断言使用公开信号 `automatic_batch_submitted` 和 `is_waiting_for_presentation()`，不得读取私有数组。

- [ ] **Step 3：验证玩家攻击与怪物攻击是不同 Effect 表现请求**

记录自动 Batch：

```gdscript
var automatic_types: Array[CombatEffectBatch.Type] = []
session.automatic_batch_submitted.connect(
    func(batch: CombatEffectBatch) -> void: automatic_types.append(batch.batch_type)
)
```

断言顺序包含独立的 `PLAYER_ATTACK`、`MONSTER_ATTACK`。再检查 Builder 输出：玩家攻击 Damage Effect 带 `CARD_ATTACK` Clip；怪物攻击 Damage Effect 带 `MONSTER_ATTACK` Clip。不得出现综合 `attack_round` Plan 或把两个 Batch 合并确认。

- [ ] **Step 4：验证两批次之间的加盾真实影响怪物攻击表现事实**

玩家攻击提交后、怪物攻击生成前提交金币加盾操作；完成所有表现确认并推进怪物攻击。断言怪物 Damage Effect 产生的 `SHIELD_CHANGED` 和 `CARD_POINTS_CHANGED` 事实中的 `before/after` 反映最新护盾。Builder 只把这些已提交字段复制到 Clip，不计算任何伤害值。

- [ ] **Step 5：验证撤退操作只播放提交后的拆链事实**

创建拆链操作 Batch，目标为当前牌链卡牌：

- 提交前不调用 Coordinator/Builder，不存在拆链 Clip；
- Processor committed 后出现 `CHAIN_SPLIT`；
- Builder 为该 Effect 生成 `CHAIN_SPLIT` 和 `CHAIN_REFLOW`；
- payload 与事实事件中的 `active_card_ids`、`detached_card_ids` 完全一致；
- 牌链没有可战斗卡牌后，Session outcome 自然成为 `retreat`；
- 测试中不得出现预览目标、拖拽或碰撞接口。

- [ ] **Step 6：写入动态战斗速度失败测试**

```gdscript
func _test_speed_change_updates_active_effect_handles() -> void:
    session.set_battle_speed(1.0)
    _start_player_attack_effect()
    var active_handle := fake_bridge.find_active_handle_by_type(CombatPresentationClipTypes.CARD_ATTACK)
    session.set_battle_speed(4.0)
    _expect(is_equal_approx(active_handle.get_speed_scale(), 4.0), "活动战斗动画立即变速")

func _test_battle_speed_also_changes_driver_interval() -> void:
    session.set_battle_speed(4.0)
    _finish_all_presentations()
    session.advance(session.driver.base_batch_interval / 4.0)
    _expect(_next_automatic_batch_was_submitted(), "同一战斗速度控制结算间隔")
```

交互层未连接 `battle_speed_changed`，因此拖拽、碰撞、目标高亮、菜单和普通 UI 不会被变速。

- [ ] **Step 7：运行完整战斗框架回归测试**

```powershell
$tests = @(
    'combat_effect_presentation_protocol_test.gd',
    'combat_effect_presentation_scheduler_test.gd',
    'combat_effect_presentation_plan_builder_test.gd',
    'combat_board_presentation_bridge_test.gd',
    'combat_presenter_smoke_test.gd',
    'combat_presentation_coordinator_test.gd',
    'combat_animation_speed_integration_test.gd',
    'combat_effect_pipeline_test.gd',
    'combat_standard_effects_test.gd',
    'combat_batch_runtime_framework_test.gd',
    'combat_lazy_battle_flow_test.gd'
)
foreach ($test in $tests) {
    & $godot --headless --path . --script "res://tests/$test"
    if ($LASTEXITCODE -ne 0) { throw "$test failed" }
}
```

Expected: 所有测试退出码 `0`。

- [ ] **Step 8：在 README 写入游戏层组装示例**

```gdscript
var session := CombatBattleSession.new(initial_state)
session.driver.require_presentation_acknowledgement = true

var bridge := CombatBoardPresentationBridge.new()
add_child(bridge)
bridge.register_card("card_a", card_presenter)
bridge.register_monster("monster", monster_presenter)
bridge.set_chain_presenter(chain_presenter)
bridge.set_hud_presenter(hud_presenter)

var builder := CombatEffectPresentationPlanBuilder.new()
var scheduler := CombatEffectPresentationScheduler.new(bridge)
var coordinator := CombatPresentationCoordinator.new()
coordinator.configure(session, builder, scheduler)

session.set_battle_speed(2.0)
session.start()
```

场景控制器 `_process(delta)` 只调用：

```gdscript
session.advance(delta)
```

操作卡系统只提交已经构建好的 Batch：

```gdscript
session.submit_player_operation(operation_batch)
```

README 必须明确：动画由 Effect Plan 执行；Batch 屏障仅负责最终确认；操作卡输入交互不属于本模块。

- [ ] **Step 9：执行静态检查和场景生命周期检查**

```powershell
& $godot --headless --path . --editor --quit
```

Expected: 无 GDScript 解析错误。随后运行一个测试场景，在 Effect 播放中调用 `coordinator.shutdown()` 并释放 Bridge，断言 Driver 不再永久等待表现确认且没有 orphan Node。

- [ ] **Step 10：提交集成测试和文档**

```powershell
git add tests/combat_animation_speed_integration_test.gd `
        tests/combat_lazy_battle_flow_test.gd `
        scripts/combat_framework/README.md
git commit -m "test: verify effect based combat presentation"
```

---

## 完成标准

- [ ] `CombatEffectBatchProcessor` 拒绝同一 Batch 内重复 `effect_id`。
- [ ] `EFFECT_APPLIED` 暴露 `effect_type` 和 `effect_tags`。
- [ ] 玩家攻击、怪物攻击和卡牌触发动作由 Effect 标签声明。
- [ ] 一个 Batch 的每个 Effect 都生成独立 `CombatEffectPresentationPlan`；无可见 Clip 的 Effect 也保留空 Plan。
- [ ] `CombatEffectPresentationScheduler` 的公开入口只接受 Effect Plan。
- [ ] Builder 和 Scheduler 中不存在按 `batch_type` 选择动画的逻辑。
- [ ] 同一 Batch 的 Effect 默认按事实 `sequence` 串行，不同 Batch 的 Effect 可在资源不冲突时并行。
- [ ] 同实体、牌链布局和 HUD 资源锁按定义工作。
- [ ] 每个 Effect 独立完成后由 `CombatBatchPresentationBarrier` 聚合；一个 Batch 最多确认一次。
- [ ] 玩家攻击和怪物攻击保持独立 Batch、独立 Effect 表现和独立 Batch 确认。
- [ ] 玩家操作可以在主战斗 Effect 播放时提交和结算。
- [ ] 战斗速度同时控制 Driver 间隔和活动/排队 Effect 动画。
- [ ] Presenter 缺失、Tween 取消、空 Effect、循环依赖和场景退出不会造成永久等待。
- [ ] 表现层不写战斗状态，不重新计算伤害，不实现拖拽、预览或目标高亮。
- [ ] 所有新增测试和现有战斗框架回归测试通过。
