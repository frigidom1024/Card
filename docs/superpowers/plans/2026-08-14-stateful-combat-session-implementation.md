# 有状态战斗会话实施计划

> **架构更新（2026-08-15）：** 本文中的多队列 `CombatSession` 方案已由“战斗驱动 + 统一效果批次处理器”方案取代。当前实现与后续接入以 `docs/design/2026-08-15-combat-batch-driver-architecture.md` 为准。


> **给 Codex：** 使用 `superpowers:test-driven-development` 逐项执行本计划，不要合并多个任务。每完成一个任务，都要运行对应测试、检查差异，并创建该任务列出的提交。

**目标：** 用按事件逐步推进的有状态战斗会话替代同步计算整场战斗的方式，并提供明确的触发时序、彼此独立的玩家/怪物攻击批次、通用战斗操作卡、面向棋盘的表现事件，以及由玩家控制的战斗速度。

**架构：** `CombatSession` 是唯一权威的战斗状态机。命令和触发器以待处理请求进入系统；`CombatIntentResolver` 将一个主要行为原子提交为不可变的 `CombatEventBatch` 输出。表现确认（ACK）、结算延迟和交互占用共同控制下一次推进。UI 适配器可以预览目标和提交命令，但绝不能直接修改战斗状态。

**技术栈：** Godot 4.7、GDScript、`RefCounted` 领域对象、场景/控制器边界信号，以及无界面的 `SceneTree` 测试。

**设计规格：** `docs/superpowers/specs/2026-08-14-combat-session-and-operation-cards-design.md`

## 全局执行规则

- 保留工作区中所有无关修改，尤其不得覆盖或暂存用户当前对卡牌、场景、棋盘、手牌区或拖拽层的修改。
- 测试使用 `extends SceneTree`；断言失败时必须以非零退出码退出。
- 定向测试命令：

```powershell
$godot = (Get-Command Godot_v4.7.1-stable_win64_console.exe).Source
& $godot --headless --path . --script res://tests/<test_file>.gd
```

- 修改脚本或资源后的导入/编译检查：

```powershell
& $godot --headless --editor --path . --quit
```

- 每次提交前执行：

```powershell
git diff --check
git status --short
git diff -- <paths owned by the task>
```

- 只暂存当前任务负责的路径。
- 批次必须先提交再发出。批次是已经发生的历史事实，动画播放期间也不能回滚。
- 队列中保存请求，而不是已经计算好的伤害、目标数值或结果。请求出队时必须重新读取可变的目标和状态数值。

---

## 任务 1：添加稳定的战斗实体 ID 与不可变协议 DTO

**文件**

- 修改：`scripts/card/card_instance.gd`
- 新建：`scripts/combat_framework/protocol/combat_command.gd`
- 新建：`scripts/combat_framework/protocol/play_combat_operation_command.gd`
- 新建：`scripts/combat_framework/protocol/combat_trigger_request.gd`
- 新建：`scripts/combat_framework/protocol/combat_intent.gd`
- 新建：`scripts/combat_framework/protocol/combat_domain_event.gd`
- 新建：`scripts/combat_framework/protocol/combat_event_batch.gd`
- 新建：`scripts/combat_framework/protocol/combat_command_result.gd`
- 测试：`tests/combat_protocol_test.gd`

**输入接口**

```gdscript
CardInstance.new(data: CardData, explicit_instance_id: StringName = &"")
```

**输出接口**

```gdscript
CardInstance.instance_id: StringName
CardInstance.duplicate_for_combat() -> CardInstance
CombatEventBatch.new(sequence: int, kind: Kind, events: Array[CombatDomainEvent], cause_snapshot: Dictionary)
CombatEventBatch.duplicate_runtime() -> CombatEventBatch
PlayCombatOperationCommand.new(command_id: StringName, operation_card_id: StringName, target_id: StringName)
CombatCommandResult.accepted(command_id: StringName) -> CombatCommandResult
CombatCommandResult.rejected(command_id: StringName, reason: StringName) -> CombatCommandResult
```

### 步骤 1：编写失败的协议测试

新建 `tests/combat_protocol_test.gd`：

```gdscript
extends SceneTree

const CardDataScript = preload("res://scripts/card/card_data.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const BatchScript = preload("res://scripts/combat_framework/protocol/combat_event_batch.gd")
const EventScript = preload("res://scripts/combat_framework/protocol/combat_domain_event.gd")
const CommandScript = preload("res://scripts/combat_framework/protocol/play_combat_operation_command.gd")

var _failures := 0

func _init() -> void:
    var data := CardDataScript.new()
    data.card_name = "Root"
    var card := CardInstanceScript.new(data, &"card-root")
    card.current_points = 4
    card.current_armor = 2
    var copy := card.duplicate_for_combat()
    _expect(copy != card, "combat copy is independent")
    _expect(copy.instance_id == &"card-root", "combat copy preserves stable id")
    _expect(copy.current_points == 4 and copy.current_armor == 2, "combat copy preserves runtime values")

    var event := EventScript.new(EventScript.Type.CARD_POINTS_CHANGED, &"card-root", {&"before": 4, &"after": 2})
    var batch := BatchScript.new(7, BatchScript.Kind.PLAYER_ATTACK, [event], {&"source_id": &"card-root"})
    var cloned := batch.duplicate_runtime()
    batch.cause_snapshot[&"source_id"] = &"changed"
    _expect(cloned.sequence == 7, "batch keeps sequence")
    _expect(cloned.cause_snapshot[&"source_id"] == &"card-root", "batch snapshot is copied")

    var command := CommandScript.new(&"cmd-1", &"retreat-card", &"card-root")
    _expect(command.operation_card_id == &"retreat-card" and command.target_id == &"card-root", "command carries ids only")
    quit(1 if _failures > 0 else 0)

func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    _failures += 1
    push_error(message)
```

### 步骤 2：运行测试并确认失败

```powershell
$godot = (Get-Command Godot_v4.7.1-stable_win64_console.exe).Source
& $godot --headless --path . --script res://tests/combat_protocol_test.gd
```

预期：以非零退出码退出，因为协议脚本和支持显式 ID 的 `CardInstance` 构造函数尚不存在。

### 步骤 3：实现最小协议 DTO

使用强类型 `RefCounted` 类，并且仅在构造函数中写入载荷。严格定义以下枚举：

```gdscript
# combat_event_batch.gd
enum Kind {
    COMBAT_START,
    PLAYER_ATTACK,
    CARD_TRIGGER,
    COMBAT_OPERATION,
    MONSTER_ATTACK,
    COMBAT_END,
    COMMAND_REJECTED,
}
```

```gdscript
# combat_trigger_request.gd
enum Type {
    COMBAT_STARTED,
    PLAYER_ATTACK_FINISHED,
    MONSTER_ATTACK_FINISHED,
    CARD_TRIGGER_FINISHED,
    FRONT_CARD_DEPLETED,
}
```

```gdscript
# combat_intent.gd
enum Type {
    DAMAGE_MONSTER,
    DAMAGE_CARD,
    ADD_CARD_POINTS,
    ADD_CARD_SHIELD,
    SPEND_RESOURCE,
    CUT_CHAIN_FROM_TARGET,
    MOVE_CARDS_TO_HAND,
    CONSUME_OPERATION_CARD,
    END_COMBAT,
}
```

```gdscript
# combat_domain_event.gd
enum Type {
    COMBAT_STARTED,
    PLAYER_ATTACK_FINISHED,
    MONSTER_ATTACK_FINISHED,
    CARD_POINTS_CHANGED,
    CARD_SHIELD_CHANGED,
    CARD_DEPLETED,
    CARD_TRIGGER_FINISHED,
    CHAIN_STRUCTURE_CHANGED,
    RESOURCE_CHANGED,
    OPERATION_CARD_CONSUMED,
    COMBAT_OPERATION_RESOLVED,
    COMMAND_REJECTED,
    COMBAT_ENDED,
}
```

`CardInstance` 的最小改动：

```gdscript
var instance_id: StringName

func _init(data: CardData, explicit_instance_id: StringName = &"") -> void:
    card_data = data
    instance_id = explicit_instance_id if explicit_instance_id != &"" else StringName(str(ResourceUID.create_id()))
    # Preserve the existing runtime initialization below this point.

func duplicate_for_combat() -> CardInstance:
    var copy := CardInstance.new(card_data, instance_id)
    copy.cur_zone = cur_zone
    copy.battlefield_pos = battlefield_pos
    copy.direction = direction
    copy.current_points = current_points
    copy.current_armor = current_armor
    copy._rule_trigger_counts = _rule_trigger_counts.duplicate(true)
    return copy
```

`CombatEventBatch.duplicate_runtime()` 必须深拷贝每个事件和 `cause_snapshot`；外部调用方绝不能拿到会话持有的数组或字典。

### 步骤 4：运行定向测试和回归测试

```powershell
& $godot --headless --path . --script res://tests/combat_protocol_test.gd
& $godot --headless --path . --script res://tests/combatv2_service_test.gd
& $godot --headless --editor --path . --quit
```

预期：所有命令均以退出码 `0` 结束。

### 步骤 5：提交

```powershell
git add scripts/card/card_instance.gd scripts/combat_framework/protocol tests/combat_protocol_test.gd
git commit -m "feat: define combat session protocol"
```

---

## 任务 2：构建 `CombatSessionState` 与原子意图解析器

**文件**

- 新建：`scripts/combatv2/session/combat_session_state.gd`
- 新建：`scripts/combatv2/session/combat_intent_resolver.gd`
- 新建：`tests/helpers/combat_test_fixtures.gd`
- 测试：`tests/combat_session_state_test.gd`
- 测试：`tests/combat_intent_resolver_test.gd`

**输入接口**

```gdscript
CombatSessionState.new(player_stats: CombatStats, monster: MobInstance, chain: Array[CardInstance], resources: Dictionary, operation_cards: Array[CardInstance])
CombatIntentResolver.resolve(state: CombatSessionState, intents: Array[CombatIntent]) -> Array[CombatDomainEvent]
```

**输出接口**

```gdscript
CombatSessionState.get_card(card_id: StringName) -> CardInstance
CombatSessionState.get_chain_ids() -> Array[StringName]
CombatSessionState.get_resource(resource_id: StringName) -> int
CombatSessionState.is_terminal() -> bool
CombatSessionState.duplicate_result_snapshot() -> Dictionary
```

### 步骤 1：编写失败的状态与解析器测试

新建 `tests/combat_session_state_test.gd`，加入以下核心断言：

```gdscript
extends SceneTree

const StateScript = preload("res://scripts/combatv2/session/combat_session_state.gd")

func _init() -> void:
    var fixtures := load("res://tests/helpers/combat_test_fixtures.gd")
    var root: CardInstance = fixtures.make_card("Root", 4, &"root")
    var head: CardInstance = fixtures.make_card("Head", 2, &"head")
    var monster: MobInstance = fixtures.make_monster("Echo", 5)
    var state := StateScript.new(null, monster, [root, head], {&"gold": 9}, [])
    assert(state.get_chain_ids() == [&"root", &"head"])
    root.current_points = 0
    assert(state.get_card(&"root").current_points == 4)
    assert(state.get_resource(&"gold") == 9)
    quit(0)
```

新建 `tests/helpers/combat_test_fixtures.gd`，提供两个测试共用的显式 ID 辅助函数：

```gdscript
extends RefCounted

static func make_card(display_name: String, points: int, instance_id: StringName) -> CardInstance:
    var data := CardData.new()
    data.card_name = display_name
    data.max_points = points
    return CardInstance.new(data, instance_id)

static func make_monster(display_name: String, health: int) -> MobInstance:
    var stats := CombatStatsData.new()
    stats.max_hp = health
    var data := MobData.new()
    data.mob_name = display_name
    data.base_stats = stats
    return MobInstance.new(data)
```

新建 `tests/combat_intent_resolver_test.gd`：

```gdscript
extends SceneTree

const IntentScript = preload("res://scripts/combat_framework/protocol/combat_intent.gd")
const EventScript = preload("res://scripts/combat_framework/protocol/combat_domain_event.gd")
const ResolverScript = preload("res://scripts/combatv2/session/combat_intent_resolver.gd")
const StateScript = preload("res://scripts/combatv2/session/combat_session_state.gd")

func _init() -> void:
    var fixtures := load("res://tests/helpers/combat_test_fixtures.gd")
    var card: CardInstance = fixtures.make_card("Head", 3, &"head")
    var state := StateScript.new(null, fixtures.make_monster("Echo", 5), [card], {&"gold": 7}, [])
    var intents: Array[CombatIntent] = [
        IntentScript.new(IntentScript.Type.DAMAGE_MONSTER, &"head", &"monster", {&"amount": 3}),
        IntentScript.new(IntentScript.Type.ADD_CARD_SHIELD, &"head", &"head", {&"amount": 2}),
    ]
    var events := ResolverScript.new().resolve(state, intents)
    assert(state.monster.stats.hp == 2)
    assert(state.get_card(&"head").current_armor == 2)
    assert(events.size() == 2)
    assert(events[0].type == EventScript.Type.PLAYER_ATTACK_FINISHED)
    assert(events[1].type == EventScript.Type.CARD_SHIELD_CHANGED)
    quit(0)
```

### 步骤 2：运行测试并确认失败

```powershell
& $godot --headless --path . --script res://tests/combat_session_state_test.gd
& $godot --headless --path . --script res://tests/combat_intent_resolver_test.gd
```

预期：两个测试都失败，因为会话状态和解析器尚不存在。

### 步骤 3：实现状态所有权与原子意图应用

`CombatSessionState` 构造时必须复制怪物、牌链卡牌、操作卡、属性和资源字典。维护 ID 到卡牌的映射，以支持 O(1) 查找。绝不能保存场景 `Node` 引用。

解析器轮廓：

```gdscript
func resolve(state: CombatSessionState, intents: Array[CombatIntent]) -> Array[CombatDomainEvent]:
    var events: Array[CombatDomainEvent] = []
    for intent in intents:
        match intent.type:
            CombatIntent.Type.DAMAGE_MONSTER:
                events.append(_damage_monster(state, intent))
            CombatIntent.Type.DAMAGE_CARD:
                events.append_array(_damage_card(state, intent))
            CombatIntent.Type.ADD_CARD_POINTS:
                events.append(_add_card_points(state, intent))
            CombatIntent.Type.ADD_CARD_SHIELD:
                events.append(_add_card_shield(state, intent))
            CombatIntent.Type.SPEND_RESOURCE:
                events.append(_spend_resource(state, intent))
            _:
                push_error("Unsupported combat intent: %s" % intent.type)
    return events
```

每个事件都保存变更前后的值。伤害卡牌意图先发出 `CARD_SHIELD_CHANGED`，再发出 `CARD_POINTS_CHANGED`；点数变为零时继续发出 `CARD_DEPLETED`。资源不足时，资源消耗必须在任何修改发生前拒绝；任务 6 的通用操作事务会在调用此解析器前验证完整意图集合。

### 步骤 4：运行定向测试

```powershell
& $godot --headless --path . --script res://tests/combat_session_state_test.gd
& $godot --headless --path . --script res://tests/combat_intent_resolver_test.gd
& $godot --headless --path . --script res://tests/combat_effect_pipeline_test.gd
& $godot --headless --editor --path . --quit
```

预期：所有命令均以退出码 `0` 结束。

### 步骤 5：提交

```powershell
git add scripts/combatv2/session/combat_session_state.gd scripts/combatv2/session/combat_intent_resolver.gd tests/combat_session_state_test.gd tests/combat_intent_resolver_test.gd tests/helpers/combat_test_fixtures.gd
git commit -m "feat: add atomic combat state resolver"
```

---

## 任务 3：实现有状态 `CombatSession` 与表现确认协议

**文件**

- 新建：`scripts/combatv2/session/combat_trigger_queue.gd`
- 新建：`scripts/combatv2/session/combat_session.gd`
- 测试：`tests/combat_session_test.gd`

**输入接口**

```gdscript
CombatSession.new(state: CombatSessionState, intent_resolver: CombatIntentResolver)
CombatSession.start() -> CombatEventBatch
CombatSession.advance_one_event() -> CombatEventBatch
CombatSession.acknowledge_batch(sequence: int) -> bool
CombatSession.submit_command(command: CombatCommand) -> CombatCommandResult
CombatSession.close_operation_window() -> void
```

**输出接口**

```gdscript
CombatSession.get_phase() -> Phase
CombatSession.get_pending_batch() -> CombatEventBatch
CombatSession.can_advance() -> bool
CombatSession.is_finished() -> bool
CombatSession.build_result() -> CombatResult
```

### 步骤 1：编写失败的会话测试

新建 `tests/combat_session_test.gd`：

```gdscript
extends SceneTree

const SessionScript = preload("res://scripts/combatv2/session/combat_session.gd")
const StateScript = preload("res://scripts/combatv2/session/combat_session_state.gd")
const ResolverScript = preload("res://scripts/combatv2/session/combat_intent_resolver.gd")
const BatchScript = preload("res://scripts/combat_framework/protocol/combat_event_batch.gd")

func _init() -> void:
    var fixtures := load("res://tests/helpers/combat_test_fixtures.gd")
    var state := StateScript.new(null, fixtures.make_monster("Echo", 5), [fixtures.make_card("Head", 3, &"head")], {}, [])
    var session := SessionScript.new(state, ResolverScript.new())

    var started := session.start()
    assert(started.kind == BatchScript.Kind.COMBAT_START)
    assert(session.advance_one_event() == null)
    assert(not session.acknowledge_batch(started.sequence + 1))
    assert(session.acknowledge_batch(started.sequence))

    var attack := session.advance_one_event()
    assert(attack != null)
    assert(attack.sequence == started.sequence + 1)
    assert(session.get_pending_batch().sequence == attack.sequence)
    quit(0)
```

### 步骤 2：运行测试并确认失败

```powershell
& $godot --headless --path . --script res://tests/combat_session_test.gd
```

预期：以非零退出码退出，因为 `CombatSession` 及其确认状态尚不存在。

### 步骤 3：实现最小阶段状态机

使用以下阶段枚举：

```gdscript
enum Phase {
    CREATED,
    COMBAT_START,
    PLAYER_ATTACK,
    PLAYER_OPERATION_WINDOW,
    POST_PLAYER_TRIGGERS,
    MONSTER_ATTACK,
    POST_MONSTER_TRIGGERS,
    COMBAT_END,
    FINISHED,
    FAULTED,
}
```

会话不变量：

```gdscript
func advance_one_event() -> CombatEventBatch:
    if _pending_batch != null or _phase in [Phase.CREATED, Phase.FINISHED, Phase.FAULTED]:
        return null
    var batch := _resolve_next_request()
    if batch == null:
        return null
    _pending_batch = batch.duplicate_runtime()
    return _pending_batch.duplicate_runtime()

func acknowledge_batch(sequence: int) -> bool:
    if _pending_batch == null or _pending_batch.sequence != sequence:
        return false
    _pending_batch = null
    _transition_after_ack()
    return true
```

`start()` 是离开 `CREATED` 的唯一合法转换；它原子创建 `COMBAT_START` 批次并将其标记为待表现。`advance_one_event()` 每次最多提交一个主要行为。`submit_command()` 只将已接受的命令入队，绝不立即修改状态。

在本任务中，`_resolve_next_request()` 可以只支持战斗开始和一个基础玩家攻击占位实现。任务 4～7 将用完整的攻击、触发和操作结算替换该占位实现。

### 步骤 4：运行定向测试

```powershell
& $godot --headless --path . --script res://tests/combat_session_test.gd
& $godot --headless --path . --script res://tests/combat_protocol_test.gd
& $godot --headless --editor --path . --quit
```

预期：所有命令均以退出码 `0` 结束。

### 步骤 5：提交

```powershell
git add scripts/combatv2/session/combat_trigger_queue.gd scripts/combatv2/session/combat_session.gd tests/combat_session_test.gd
git commit -m "feat: add stateful combat session"
```

---

## 任务 4：将玩家攻击和怪物攻击拆分为独立批次

**文件**

- 修改：`scripts/combatv2/session/combat_session.gd`
- 修改：`scripts/combatv2/session/combat_intent_resolver.gd`
- 修改：`scripts/combatv2/combat_service.gd`
- 测试：`tests/combat_attack_order_test.gd`
- 修改测试：`tests/combatv2_service_test.gd`

**输入接口**

```gdscript
CombatSession.advance_one_event() -> CombatEventBatch
MobInstance.next_action() -> MobAction
```

**输出接口**

```gdscript
CombatSession._build_player_attack_intents(card_id: StringName) -> Array[CombatIntent]
CombatSession._build_monster_attack_intents(card_id: StringName) -> Array[CombatIntent]
```

### 步骤 1：编写失败的攻击顺序测试

新建 `tests/combat_attack_order_test.gd`：

```gdscript
extends SceneTree

const SessionScript = preload("res://scripts/combatv2/session/combat_session.gd")
const StateScript = preload("res://scripts/combatv2/session/combat_session_state.gd")
const ResolverScript = preload("res://scripts/combatv2/session/combat_intent_resolver.gd")
const BatchScript = preload("res://scripts/combat_framework/protocol/combat_event_batch.gd")
const EventScript = preload("res://scripts/combat_framework/protocol/combat_domain_event.gd")

func _init() -> void:
    _test_attacks_are_distinct_batches()
    _test_lethal_player_attack_skips_monster_attack()
    quit(0)

func _test_attacks_are_distinct_batches() -> void:
    var session := _make_session(3, 5)
    _ack(session, session.start())
    var player_batch := session.advance_one_event()
    assert(player_batch.kind == BatchScript.Kind.PLAYER_ATTACK)
    assert(_count(player_batch, EventScript.Type.MONSTER_ATTACK_FINISHED) == 0)
    _ack(session, player_batch)

    session.close_operation_window()
    var monster_batch := _advance_until_kind(session, BatchScript.Kind.MONSTER_ATTACK)
    assert(monster_batch != null)
    assert(_count(monster_batch, EventScript.Type.PLAYER_ATTACK_FINISHED) == 0)

func _test_lethal_player_attack_skips_monster_attack() -> void:
    var session := _make_session(5, 5)
    _ack(session, session.start())
    _ack(session, session.advance_one_event())
    session.close_operation_window()
    var terminal := _advance_until_kind(session, BatchScript.Kind.COMBAT_END)
    assert(terminal != null)
    assert(session.state.monster.stats.hp == 0)

func _ack(session, batch) -> void:
    assert(batch != null and session.acknowledge_batch(batch.sequence))

func _advance_until_kind(session, kind: int):
    for index in range(8):
        var batch = session.advance_one_event()
        if batch == null:
            continue
        if batch.kind == kind:
            return batch
        _ack(session, batch)
    return null

func _count(batch, type: int) -> int:
    return batch.events.filter(func(event): return event.type == type).size()

func _make_session(card_points: int, monster_health: int):
    var fixtures := load("res://tests/helpers/combat_test_fixtures.gd")
    var state := StateScript.new(null, fixtures.make_monster("Echo", monster_health), [fixtures.make_card("Head", card_points, &"head")], {}, [])
    return SessionScript.new(state, ResolverScript.new())
```

将代码片段需要的辅助函数直接添加到该测试中，不要依赖测试框架的隐式行为。

### 步骤 2：运行测试并确认失败

```powershell
& $godot --headless --path . --script res://tests/combat_attack_order_test.gd
```

预期：以非零退出码退出，因为玩家伤害与怪物反击仍在一起结算，或者尚未实现操作窗口转换。

### 步骤 3：将交战行为拆分到不同请求类型之后

要求的顺序：

```text
PLAYER_ATTACK
→ immediate terminal check
→ PLAYER_OPERATION_WINDOW
→ POST_PLAYER_TRIGGERS
→ MONSTER_ATTACK
```

玩家批次中的意图只能伤害怪物；怪物批次中的意图只能伤害当前目标卡牌。批次的 `cause_snapshot` 记录来源卡牌 ID、目标 ID、请求数值和攻击阶段，不保存任何可变卡牌引用。

移除 `combat_service.gd` 的 `_resolve_card_clash()` 中混合玩家与怪物行为的 `CombatEffectDraft` 构建逻辑。暂时保留 `resolve_encounter()` 作为兼容适配器：重复推进并确认会话，直到能够构建 `CombatResult`。在文档注释中将其标记为内部/旧接口；调用方在任务 11 中迁移。

终局检查规则：

```gdscript
func _after_player_attack_committed() -> void:
    if state.monster.stats.hp <= 0:
        _enqueue_combat_end(CombatResult.Outcome.VICTORY)
        return
    _phase = Phase.PLAYER_OPERATION_WINDOW
```

在玩家操作窗口关闭且玩家攻击后的触发全部处理完之前，不得将怪物攻击入队。

### 步骤 4：运行定向测试和战斗回归测试

```powershell
& $godot --headless --path . --script res://tests/combat_attack_order_test.gd
& $godot --headless --path . --script res://tests/combatv2_service_test.gd
& $godot --headless --path . --script res://tests/ribwood_combat_balance_test.gd
& $godot --headless --editor --path . --quit
```

预期：所有命令均以退出码 `0` 结束；虽然内部事件批次已经拆分，但现有数值平衡结果保持不变。

### 步骤 5：提交

```powershell
git add scripts/combatv2/session/combat_session.gd scripts/combatv2/session/combat_intent_resolver.gd scripts/combatv2/combat_service.gd tests/combat_attack_order_test.gd tests/combatv2_service_test.gd
git commit -m "refactor: separate combat attack phases"
```

---

## 任务 5：用显式触发队列和分发器替代隐式规则时序

**文件**

- 新建：`scripts/combatv2/session/combat_rule_dispatcher.gd`
- 修改：`scripts/combatv2/session/combat_trigger_queue.gd`
- 修改：`scripts/combatv2/session/combat_session.gd`
- 修改：`scripts/combat_framework/protocol/combat_trigger_request.gd`
- 修改：`scripts/combatv2/card/card_rule.gd`
- 修改：`scripts/combatv2/card/rules/armored_next_card_point_bonus_rule.gd`
- 修改：`scripts/combatv2/card/rules/behind_head_pre_trigger_rule.gd`
- 修改：`scripts/combatv2/card/rules/card_damage_multiplier_rule.gd`
- 修改：`scripts/combatv2/card/rules/chain_length_head_armor_bonus_rule.gd`
- 修改：`scripts/combatv2/card/rules/chain_length_head_point_bonus_rule.gd`
- 修改：`scripts/combatv2/card/rules/combat_start_point_bonus_rule.gd`
- 修改：`scripts/combatv2/card/rules/first_card_damage_double_rule.gd`
- 修改：`scripts/combatv2/card/rules/last_card_defense_bonus_rule.gd`
- 修改：`scripts/combatv2/card/rules/last_card_defense_double_rule.gd`
- 修改：`scripts/combatv2/card/rules/next_card_armor_bonus_rule.gd`
- 修改：`scripts/combatv2/card/rules/next_card_point_bonus_rule.gd`
- 修改：`scripts/combatv2/card/rules/previous_defense_damage_bonus_rule.gd`
- 修改：`scripts/combatv2/card/rules/previous_defense_heal_bonus_rule.gd`
- 修改：`scripts/combatv2/card/rules/previous_weapon_damage_bonus_rule.gd`
- 修改：`scripts/combatv2/card/rules/previous_weapon_damage_double_rule.gd`
- 修改：`scripts/combatv2/mob_effect.gd`
- 修改：`scripts/combatv2/mob_effects/mob_effect_rear_shock.gd`
- 修改：`scripts/combatv2/mob_effects/mob_effect_shield_break.gd`
- 测试：`tests/combat_trigger_queue_test.gd`
- 修改测试：`tests/combatv2_card_rule_test.gd`

**输入接口**

```gdscript
CombatTriggerQueue.enqueue(request: CombatTriggerRequest) -> void
CombatTriggerQueue.dequeue() -> CombatTriggerRequest
CombatTriggerRequest.survival_policy: int
CombatTriggerRequest.root_cause_id: StringName
CombatRuleDispatcher.collect(state: CombatSessionState, request: CombatTriggerRequest) -> Array[CombatTriggerRequest]
CombatRuleDispatcher.build_intents(state: CombatSessionState, request: CombatTriggerRequest) -> Array[CombatIntent]
```

**输出接口**

```gdscript
CardRule.get_supported_triggers() -> Array[int]
CardRule.matches_trigger(context: Dictionary) -> bool
CardRule.build_intents(context: Dictionary) -> Array[CombatIntent]
MobEffect.get_supported_triggers() -> Array[int]
MobEffect.build_intents(context: Dictionary) -> Array[CombatIntent]
```

### 步骤 1：编写失败的触发队列测试

新建 `tests/combat_trigger_queue_test.gd`：

```gdscript
extends SceneTree

const QueueScript = preload("res://scripts/combatv2/session/combat_trigger_queue.gd")
const TriggerScript = preload("res://scripts/combat_framework/protocol/combat_trigger_request.gd")

func _init() -> void:
    var queue := QueueScript.new()
    queue.enqueue(TriggerScript.new(TriggerScript.Type.COMBAT_STARTED, &"root", {}, 20))
    queue.enqueue(TriggerScript.new(TriggerScript.Type.FRONT_CARD_DEPLETED, &"head", {}, 10))
    queue.enqueue(TriggerScript.new(TriggerScript.Type.CARD_TRIGGER_FINISHED, &"scout", {}, 10))

    assert(queue.dequeue().source_id == &"head")
    assert(queue.dequeue().source_id == &"scout")
    assert(queue.dequeue().source_id == &"root")
    assert(queue.is_empty())
    quit(0)
```

在同一文件中补充存活策略和循环保护用例：

```gdscript
func _test_depleted_source_obeys_survival_policy() -> void:
    var queue := QueueScript.new()
    queue.enqueue(TriggerScript.new(TriggerScript.Type.FRONT_CARD_DEPLETED, &"head", {}, 10, TriggerScript.SurvivalPolicy.ALLOW_SOURCE_DEPLETED))
    var state := _make_state_with_depleted_card(&"head")
    assert(queue.dequeue_next_valid(state).source_id == &"head")

    queue.enqueue(TriggerScript.new(TriggerScript.Type.CARD_TRIGGER_FINISHED, &"head", {}, 10, TriggerScript.SurvivalPolicy.REQUIRE_SOURCE_ACTIVE))
    assert(queue.dequeue_next_valid(state) == null)

func _test_trigger_chain_limit_faults_instead_of_looping() -> void:
    var session := _make_self_repeating_trigger_session()
    session.max_triggers_per_atomic_chain = 4
    _ack(session, session.start())
    for index in range(8):
        var batch := session.advance_one_event()
        if batch == null:
            break
        _ack(session, batch)
    assert(session.get_phase() == CombatSession.Phase.FAULTED)
    assert(session.get_fault()[&"reason"] == &"trigger_chain_limit_exceeded")
```

在 `CombatTriggerRequest` 上定义以下存活策略标志：`REQUIRE_SOURCE_ACTIVE`、`REQUIRE_SOURCE_PRESENT`、`ALLOW_SOURCE_DEPLETED`、`REQUIRE_TARGET_ACTIVE`、`REQUIRE_TARGET_PRESENT`、`RETARGET_ON_RESOLVE`、`CANCEL_ON_COMBAT_END` 和 `EXECUTE_DURING_COMBAT_END`。

在 `tests/combatv2_card_rule_test.gd` 中添加会话级用例：

```gdscript
func _test_finished_trigger_can_enqueue_follow_up_trigger() -> void:
    var session := _make_chain_reaction_session()
    _ack(session, session.start())
    var first_trigger := _advance_until_kind(session, CombatEventBatch.Kind.CARD_TRIGGER)
    _ack(session, first_trigger)
    var second_trigger := _advance_until_kind(session, CombatEventBatch.Kind.CARD_TRIGGER)
    _expect(first_trigger.cause_snapshot[&"source_id"] == &"starter", "starter resolves first")
    _expect(second_trigger.cause_snapshot[&"source_id"] == &"follower", "completion trigger resolves second")
```

测试夹具使用两条测试规则：一条响应 `COMBAT_STARTED`；另一条响应来源为 `starter` 的 `CARD_TRIGGER_FINISHED`。

### 步骤 2：运行测试并确认失败

```powershell
& $godot --headless --path . --script res://tests/combat_trigger_queue_test.gd
& $godot --headless --path . --script res://tests/combatv2_card_rule_test.gd
```

预期：测试失败，因为队列优先级/顺序以及完成后触发链尚未实现。

### 步骤 3：实现确定性的触发调度

队列顺序为 `(priority 升序, insertion_sequence 升序)`。触发请求包含类型、来源 ID、原因快照、优先级和插入序号，不包含已经结算的数值。

分发器算法：

```gdscript
func collect(state: CombatSessionState, request: CombatTriggerRequest) -> Array[CombatTriggerRequest]:
    var matches: Array[CombatTriggerRequest] = []
    for card_id in state.get_chain_ids():
        var card := state.get_card(card_id)
        for rule_index in range(card.card_data.effect_rules.size()):
            var rule: CardRule = card.card_data.effect_rules[rule_index]
            if request.type not in rule.get_supported_triggers():
                continue
            var context := _build_context(state, request, card, rule_index)
            if rule.matches_trigger(context) and card.can_trigger_rule(rule_index, rule.effective_count):
                matches.append(CombatTriggerRequest.new(request.type, card_id, request.cause_snapshot, rule.priority))
    return matches
```

卡牌规则结算后，记录其触发次数，发出 `CARD_TRIGGER_FINISHED`，随后将新的 `CARD_TRIGGER_FINISHED` 请求入队；其原因快照包含已完成的来源卡牌/规则 ID。前方或当前卡牌耗尽时，将 `FRONT_CARD_DEPLETED` 入队。构建事件时不得递归执行触发器；每次规则结算都必须形成独立的 `CARD_TRIGGER` 批次。

请求出队前，必须依据最新会话状态检查其存活策略。普通持续效果默认要求来源和目标仍有效，并使用 `CANCEL_ON_COMBAT_END`；死亡效果必须显式使用 `ALLOW_SOURCE_DEPLETED`。只有标记了 `EXECUTE_DURING_COMBAT_END` 的请求才能在结束阶段继续存在。`RETARGET_ON_RESOLVE` 必须显式启用；固定目标的操作卡绝不能使用它。

跟踪单调递增的触发序号、`root_cause_id`、原子链深度和单场战斗触发总数。默认限制为每条原子链最多 64 次触发、每场战斗最多 512 次。超过任一限制时，以 `trigger_chain_limit_exceeded` 将会话置为故障状态，而不是继续递归或卡死。

改造 **文件** 列表中的所有现有卡牌规则和怪物效果，使其发出意图而不是修改草案。保留已有导出字段，确保 `.tres` 资源继续正常加载。如需逐个迁移资源，可以仅在本任务期间保留临时的草案到意图兼容辅助函数，但必须在提交本任务前删除。

### 步骤 4：运行定向测试和规则回归测试

```powershell
& $godot --headless --path . --script res://tests/combat_trigger_queue_test.gd
& $godot --headless --path . --script res://tests/combatv2_card_rule_test.gd
& $godot --headless --path . --script res://tests/combat_effect_pipeline_test.gd
& $godot --headless --path . --script res://tests/ribwood_combat_balance_test.gd
& $godot --headless --editor --path . --quit
```

预期：所有命令均以退出码 `0` 结束；规则顺序确定，并且每次触发都可以被独立观察。

### 步骤 5：提交

```powershell
git add scripts/combatv2/session/combat_rule_dispatcher.gd scripts/combatv2/session/combat_trigger_queue.gd scripts/combatv2/session/combat_session.gd scripts/combat_framework/protocol/combat_trigger_request.gd scripts/combatv2/card/card_rule.gd scripts/combatv2/card/rules scripts/combatv2/mob_effect.gd scripts/combatv2/mob_effects tests/combat_trigger_queue_test.gd tests/combatv2_card_rule_test.gd
git commit -m "refactor: make combat trigger timing explicit"
```

---

## 任务 6：定义通用战斗操作卡与事务式结算

**文件**

- 修改：`scripts/card/card_data.gd`
- 新建：`scripts/combatv2/operation/combat_operation_definition.gd`
- 新建：`scripts/combatv2/operation/combat_target_spec.gd`
- 新建：`scripts/combatv2/operation/combat_cost_spec.gd`
- 新建：`scripts/combatv2/operation/card_disposition_spec.gd`
- 新建：`scripts/combatv2/operation/combat_operation_effect.gd`
- 新建：`scripts/combatv2/operation/combat_operation_resolver.gd`
- 修改：`scripts/combatv2/session/combat_session.gd`
- 新建：`tests/helpers/combat_operation_test_fixture.gd`
- 测试：`tests/combat_operation_resolver_test.gd`
- 测试：`tests/combat_pending_request_revalidation_test.gd`

**输入接口**

```gdscript
CardData.combat_operation: CombatOperationDefinition
CombatOperationResolver.validate(state: CombatSessionState, command: PlayCombatOperationCommand) -> CombatCommandResult
CombatOperationResolver.resolve(state: CombatSessionState, command: PlayCombatOperationCommand, sequence: int) -> CombatEventBatch
```

**输出接口**

```gdscript
CombatOperationDefinition.target_spec: CombatTargetSpec
CombatOperationDefinition.cost_spec: CombatCostSpec
CombatOperationDefinition.disposition_spec: CardDispositionSpec
CombatOperationDefinition.effects: Array[CombatOperationEffect]
CombatSessionState.get_operation_card(card_id: StringName) -> CardInstance
CombatOperationEffect.build_intents(context: Dictionary) -> Array[CombatIntent]
```

### 步骤 1：编写失败的操作解析器测试

新建 `tests/combat_operation_resolver_test.gd`：

```gdscript
extends SceneTree

const ResolverScript = preload("res://scripts/combatv2/operation/combat_operation_resolver.gd")
const CommandScript = preload("res://scripts/combat_framework/protocol/play_combat_operation_command.gd")
const BatchScript = preload("res://scripts/combat_framework/protocol/combat_event_batch.gd")

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_operation_test_fixture.gd").new()
    var state: CombatSessionState = fixture.make_state_with_operation_card(10)
    var command := CommandScript.new(&"cmd-1", &"operation-1", &"head")
    var resolver := ResolverScript.new()

    var validation := resolver.validate(state, command)
    assert(validation.is_accepted)
    var batch := resolver.resolve(state, command, 1)
    assert(batch.kind == BatchScript.Kind.COMBAT_OPERATION)
    assert(state.get_resource(&"gold") == 7)
    assert(state.get_card(&"head").current_armor == 2)
    assert(state.get_operation_card(&"operation-1") == null)

    var second := resolver.validate(state, command)
    assert(not second.is_accepted)
    assert(second.reason == &"operation_card_missing")
    quit(0)
```

`combat_operation_test_fixture.gd` 创建一个操作定义：消耗 3 金币、固定卡牌目标、成功后消耗操作卡，并附带增加 2 点护盾的测试效果。

新建 `tests/combat_pending_request_revalidation_test.gd`：

```gdscript
extends SceneTree

const CommandScript = preload("res://scripts/combat_framework/protocol/play_combat_operation_command.gd")
const BatchScript = preload("res://scripts/combat_framework/protocol/combat_event_batch.gd")

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_operation_test_fixture.gd").new()
    var session: CombatSession = fixture.make_queued_monster_attack_session()
    _ack(session, session.start())

    var committed_player_attack := session.advance_one_event()
    var historical_cause := committed_player_attack.cause_snapshot.duplicate(true)
    _ack(session, committed_player_attack)

    assert(session.submit_command(CommandScript.new(&"shield-1", &"shield-card", &"head")).is_accepted)
    session.close_operation_window()
    var operation := session.advance_one_event()
    _ack(session, operation)
    var monster_attack := _advance_until_kind(session, BatchScript.Kind.MONSTER_ATTACK)

    assert(committed_player_attack.cause_snapshot == historical_cause)
    assert(monster_attack.cause_snapshot[&"target_shield_before"] == 3)
    assert(session.state.get_card(&"head").current_armor == 1)
    quit(0)
```

测试夹具让操作增加 `3` 点护盾，并让待处理的怪物攻击造成 `2` 点伤害。该断言用于证明：已经提交的玩家批次保持不变，而尚未提交的怪物请求会在出队时读取最新护盾值。

在 `tests/combat_operation_resolver_test.gd` 中再添加一个用例：可见金币为 5 时，依次提交两个各消耗 3 金币的命令。第一个命令成功结算；第二个命令发出原因是 `insufficient_resource` 的 `COMMAND_REJECTED`，不消耗第二张卡，也不自动重新选择目标。

### 步骤 2：运行测试并确认失败

```powershell
& $godot --headless --path . --script res://tests/combat_operation_resolver_test.gd
& $godot --headless --path . --script res://tests/combat_pending_request_revalidation_test.gd
```

预期：以非零退出码退出，因为操作定义和解析器尚不存在。

### 步骤 3：实现“先验证、后提交”的操作结算

向 `CardData` 添加：

```gdscript
@export_group("Combat Operation")
@export var combat_operation: CombatOperationDefinition
```

验证顺序：

1. 命令 ID 尚未被接受过。
2. 会话处于 `PLAYER_OPERATION_WINDOW`。
3. 操作卡存在于会话的操作卡映射中。
4. 卡牌具有 `combat_operation` 定义。
5. 目标存在且符合 `CombatTargetSpec`。
6. 当前资源足以支付费用。
7. 每个效果都能针对当前状态构建有效意图。
8. 卡牌去向合法。

随后，解析器构建完整意图数组，在不修改状态的情况下验证整个数组，并通过 `CombatIntentResolver` 一次性提交。失败时返回 `CombatCommandResult.rejected(...)`，且不得消耗资源、移动卡牌、消耗卡牌或进行任何状态修改。

解析器的最小结构：

```gdscript
func resolve(state: CombatSessionState, command: PlayCombatOperationCommand, sequence: int) -> CombatEventBatch:
    var validation := validate(state, command)
    if not validation.is_accepted:
        return _rejection_batch(sequence, command, validation.reason)
    var operation_card := state.get_operation_card(command.operation_card_id)
    var definition := operation_card.card_data.combat_operation
    var context := _build_context(state, command, operation_card, definition)
    var intents: Array[CombatIntent] = []
    intents.append_array(definition.cost_spec.build_intents(context))
    for effect in definition.effects:
        intents.append_array(effect.build_intents(context))
    intents.append_array(definition.disposition_spec.build_intents(context))
    var events := _intent_resolver.resolve(state, intents)
    events.append(CombatDomainEvent.new(CombatDomainEvent.Type.COMBAT_OPERATION_RESOLVED, command.operation_card_id, {&"command_id": command.command_id, &"target_id": command.target_id}))
    return CombatEventBatch.new(sequence, CombatEventBatch.Kind.COMBAT_OPERATION, events, {&"command_id": command.command_id, &"operation_card_id": command.operation_card_id, &"target_id": command.target_id})
```

`CombatSession.submit_command()` 按提交顺序接受有效命令，并保存命令 ID 以保证幂等性。请求出队时必须再次验证，因为更早的命令可能已经改变目标、费用或牌链状态。固定目标失效时直接拒绝，绝不自动重新选择目标。

### 步骤 4：运行定向测试

```powershell
& $godot --headless --path . --script res://tests/combat_operation_resolver_test.gd
& $godot --headless --path . --script res://tests/combat_pending_request_revalidation_test.gd
& $godot --headless --path . --script res://tests/combat_session_test.gd
& $godot --headless --path . --script res://tests/combat_protocol_test.gd
& $godot --headless --editor --path . --quit
```

预期：所有命令均以退出码 `0` 结束。

### 步骤 5：提交

```powershell
git add scripts/card/card_data.gd scripts/combatv2/operation scripts/combatv2/session/combat_session.gd tests/combat_operation_resolver_test.gd tests/combat_pending_request_revalidation_test.gd tests/helpers/combat_operation_test_fixture.gd
git commit -m "feat: add generic combat operation pipeline"
```

---

## 任务 7：实现撤退和金币强化护盾操作效果

**文件**

- 新建：`scripts/combatv2/operation/retreat_operation_effect.gd`
- 新建：`scripts/combatv2/operation/add_card_shield_operation_effect.gd`
- 修改：`scripts/combatv2/session/combat_intent_resolver.gd`
- 修改：`scripts/combatv2/session/combat_session.gd`
- 修改：`tests/helpers/combat_operation_test_fixture.gd`
- 测试：`tests/combat_retreat_operation_test.gd`
- 测试：`tests/combat_gold_shield_operation_test.gd`

**输入接口**

```gdscript
RetreatOperationEffect.build_intents(context: Dictionary) -> Array[CombatIntent]
AddCardShieldOperationEffect.build_intents(context: Dictionary) -> Array[CombatIntent]
```

**输出接口**

```gdscript
CombatSessionState.returned_card_ids: Array[StringName]
CombatSessionState.consumed_operation_card_ids: Array[StringName]
CombatSessionState.retreat_requested: bool
```

### 步骤 1：编写失败的撤退测试

新建 `tests/combat_retreat_operation_test.gd`：

```gdscript
extends SceneTree

const CommandScript = preload("res://scripts/combat_framework/protocol/play_combat_operation_command.gd")
const BatchScript = preload("res://scripts/combat_framework/protocol/combat_event_batch.gd")

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_operation_test_fixture.gd").new()
    var session: CombatSession = fixture.make_retreat_session([&"root", &"b", &"a", &"c", &"head"])
    _ack(session, session.start())
    var attack := session.advance_one_event()
    _ack(session, attack)

    var accepted := session.submit_command(CommandScript.new(&"retreat-1", &"retreat-card", &"a"))
    assert(accepted.is_accepted)
    session.close_operation_window()
    var operation := session.advance_one_event()
    assert(operation.kind == BatchScript.Kind.COMBAT_OPERATION)
    assert(session.state.get_chain_ids() == [&"root", &"b"])
    assert(session.state.returned_card_ids == [&"a", &"c", &"head"])
    assert(session.state.consumed_operation_card_ids == [&"retreat-card"])
    _ack(session, operation)

    var ending := _advance_until_kind(session, BatchScript.Kind.COMBAT_END)
    assert(ending != null)
    assert(session.build_result().outcome == CombatResult.Outcome.RETREAT)
    assert(session.state.monster.enhancement_stacks == 1)
    assert(not _session_emitted_kind(session, BatchScript.Kind.MONSTER_ATTACK))
    quit(0)
```

添加第二个用例，目标 ID 不存在于当前牌链中，并断言：产生拒绝批次、牌链不变、怪物强化层数不变、撤退卡未被消耗。

### 步骤 2：编写失败的金币强化护盾测试

新建 `tests/combat_gold_shield_operation_test.gd`：

```gdscript
extends SceneTree

const CommandScript = preload("res://scripts/combat_framework/protocol/play_combat_operation_command.gd")
const EventScript = preload("res://scripts/combat_framework/protocol/combat_domain_event.gd")

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_operation_test_fixture.gd").new()
    var session: CombatSession = fixture.make_gold_shield_session(5, 3)
    _ack(session, session.start())
    _ack(session, session.advance_one_event())

    assert(session.submit_command(CommandScript.new(&"shield-1", &"shield-card", &"head")).is_accepted)
    session.close_operation_window()
    var batch := session.advance_one_event()
    assert(session.state.get_resource(&"gold") == 2)
    assert(session.state.get_card(&"head").current_armor == 3)
    assert(_has_event(batch, EventScript.Type.RESOURCE_CHANGED))
    assert(_has_event(batch, EventScript.Type.CARD_SHIELD_CHANGED))
    assert(_has_event(batch, EventScript.Type.OPERATION_CARD_CONSUMED))
    quit(0)
```

添加金币不足和目标过期用例。两种情况都必须拒绝，并且不能产生部分修改。

### 步骤 3：运行测试并确认失败

```powershell
& $godot --headless --path . --script res://tests/combat_retreat_operation_test.gd
& $godot --headless --path . --script res://tests/combat_gold_shield_operation_test.gd
```

预期：两个测试都失败，因为具体操作效果和断开牌链意图尚不存在。

### 步骤 4：实现具体效果与撤退终止逻辑

撤退效果按以下顺序生成意图：

```gdscript
return [
    CombatIntent.new(CombatIntent.Type.CUT_CHAIN_FROM_TARGET, source_id, target_id),
    CombatIntent.new(CombatIntent.Type.MOVE_CARDS_TO_HAND, source_id, target_id),
    CombatIntent.new(CombatIntent.Type.CONSUME_OPERATION_CARD, source_id, source_id),
    CombatIntent.new(CombatIntent.Type.END_COMBAT, source_id, &"combat", {&"outcome": CombatResult.Outcome.RETREAT}),
]
```

解析器应用 `CUT_CHAIN_FROM_TARGET` 时计算目标索引，保存按顺序移除的 ID，并将这些 ID 原样用于 `MOVE_CARDS_TO_HAND`。对于 `root → B → A → C → head` 且目标为 `A` 的情况，保留的 ID 是 `root, B`，返回手牌的 ID 是 `A, C, head`。

撤退成功后：

- 保留已经提交的伤害。
- 跳过后续所有触发和怪物攻击。
- 已经耗尽的卡牌仍纳入最终结算。
- 不发放胜利奖励。
- 只调用一次 `MobInstance.gain_enhancement()`。
- 消耗撤退操作卡。

金币强化护盾操作先构建 `SPEND_RESOURCE`，再构建 `ADD_CARD_SHIELD`；其操作定义还会加入通用的“成功后消耗卡牌”去向意图。在提交任何意图前，必须验证费用可支付且目标仍然存在。

### 步骤 5：运行定向测试和回归测试

```powershell
& $godot --headless --path . --script res://tests/combat_retreat_operation_test.gd
& $godot --headless --path . --script res://tests/combat_gold_shield_operation_test.gd
& $godot --headless --path . --script res://tests/combat_operation_resolver_test.gd
& $godot --headless --path . --script res://tests/combat_attack_order_test.gd
& $godot --headless --path . --script res://tests/combatv2_service_test.gd
& $godot --headless --editor --path . --quit
```

预期：所有命令均以退出码 `0` 结束。

### 步骤 6：提交

```powershell
git add scripts/combatv2/operation/retreat_operation_effect.gd scripts/combatv2/operation/add_card_shield_operation_effect.gd scripts/combatv2/session/combat_intent_resolver.gd scripts/combatv2/session/combat_session.gd tests/combat_retreat_operation_test.gd tests/combat_gold_shield_operation_test.gd tests/helpers/combat_operation_test_fixture.gd
git commit -m "feat: add in-combat retreat and shield operations"
```

---

## 任务 8：添加战斗速度、推进门控与结算调度

**文件**

- 新建：`scripts/combat_framework/runtime/combat_speed_controller.gd`
- 新建：`scripts/combat_framework/runtime/combat_advance_gate.gd`
- 新建：`scripts/combat_framework/runtime/combat_scheduler.gd`
- 测试：`tests/combat_speed_controller_test.gd`
- 测试：`tests/combat_scheduler_test.gd`

**输入接口**

```gdscript
CombatSpeedController.set_speed_multiplier(value: float) -> void
CombatAdvanceGate.set_presentation_ready(ready: bool) -> void
CombatAdvanceGate.set_interaction_hold(owner: StringName, active: bool) -> void
CombatScheduler.begin_wait(base_duration_seconds: float) -> void
CombatScheduler.advance(delta_seconds: float) -> bool
```

**输出接口**

```gdscript
CombatSpeedController.speed_multiplier: float
CombatSpeedController.speed_changed(multiplier: float)
CombatAdvanceGate.can_advance() -> bool
CombatScheduler.get_remaining_real_seconds() -> float
CombatScheduler.delay_ready: bool
```

### 步骤 1：编写失败的战斗速度控制器测试

新建 `tests/combat_speed_controller_test.gd`：

```gdscript
extends SceneTree

const SpeedScript = preload("res://scripts/combat_framework/runtime/combat_speed_controller.gd")

func _init() -> void:
    var speed := SpeedScript.new()
    assert(is_equal_approx(speed.speed_multiplier, 1.0))
    speed.set_speed_multiplier(2.0)
    assert(is_equal_approx(speed.scale_duration(1.5), 0.75))
    speed.set_speed_multiplier(0.0)
    assert(is_equal_approx(speed.speed_multiplier, SpeedScript.MIN_SPEED))
    speed.set_speed_multiplier(99.0)
    assert(is_equal_approx(speed.speed_multiplier, SpeedScript.MAX_SPEED))
    quit(0)
```

### 步骤 2：编写失败的调度器/门控测试

新建 `tests/combat_scheduler_test.gd`：

```gdscript
extends SceneTree

const SpeedScript = preload("res://scripts/combat_framework/runtime/combat_speed_controller.gd")
const GateScript = preload("res://scripts/combat_framework/runtime/combat_advance_gate.gd")
const SchedulerScript = preload("res://scripts/combat_framework/runtime/combat_scheduler.gd")

func _init() -> void:
    var speed := SpeedScript.new()
    var gate := GateScript.new()
    var scheduler := SchedulerScript.new(speed, gate)
    scheduler.begin_wait(4.0)
    scheduler.advance(1.0)
    assert(is_equal_approx(scheduler.progress, 0.25))

    speed.set_speed_multiplier(2.0)
    assert(is_equal_approx(scheduler.get_remaining_real_seconds(), 1.5))
    scheduler.advance(1.5)
    assert(scheduler.delay_ready)

    gate.set_presentation_ready(false)
    assert(not scheduler.can_advance())
    gate.set_presentation_ready(true)
    gate.set_interaction_hold(&"operation_drag", true)
    assert(not scheduler.can_advance())
    gate.set_interaction_hold(&"operation_drag", false)
    assert(scheduler.can_advance())
    quit(0)
```

### 步骤 3：运行测试并确认失败

```powershell
& $godot --headless --path . --script res://tests/combat_speed_controller_test.gd
& $godot --headless --path . --script res://tests/combat_scheduler_test.gd
```

预期：两个测试都失败，因为运行时计时类尚不存在。

### 步骤 4：将战斗速度实现为战斗时间缩放

所有面向 UI 的属性和方法统一命名为“战斗速度”/`combat_speed`，不得称为“播放速度”。建议范围：

```gdscript
const MIN_SPEED := 0.25
const MAX_SPEED := 4.0
var speed_multiplier := 1.0

func scale_duration(base_seconds: float) -> float:
    return maxf(base_seconds, 0.0) / speed_multiplier
```

使用归一化战斗时间跟踪调度进度：

```gdscript
func advance(real_delta: float) -> bool:
    if delay_ready:
        return true
    _elapsed_combat_seconds += maxf(real_delta, 0.0) * _speed.speed_multiplier
    progress = clampf(_elapsed_combat_seconds / _base_duration, 0.0, 1.0)
    delay_ready = progress >= 1.0
    return delay_ready

func get_remaining_real_seconds() -> float:
    return maxf(_base_duration - _elapsed_combat_seconds, 0.0) / _speed.speed_multiplier
```

因此，改变战斗速度会保留已经经过的进度比例，只重新缩放剩余的现实时间。

门控条件：

```gdscript
func can_advance() -> bool:
    return settlement_delay_ready and presentation_ready and _interaction_holds.is_empty()
```

交互占用以所有者为键，使重复的开始/结束调用保持幂等。正在进行的操作卡拖拽使用所有者 `&"operation_drag"`。

### 步骤 5：运行定向测试

```powershell
& $godot --headless --path . --script res://tests/combat_speed_controller_test.gd
& $godot --headless --path . --script res://tests/combat_scheduler_test.gd
& $godot --headless --editor --path . --quit
```

预期：所有命令均以退出码 `0` 结束。

### 步骤 6：提交

```powershell
git add scripts/combat_framework/runtime tests/combat_speed_controller_test.gd tests/combat_scheduler_test.gd
git commit -m "feat: add combat speed and advancement gates"
```

---

## 任务 9：添加仅显示目标的操作预览与通用拖拽适配器

**文件**

- 新建：`scripts/combatv2/operation/combat_operation_target_preview.gd`
- 新建：`scripts/game/event/encounter/combat_operation_drag_adapter.gd`
- 修改：`scripts/game/drag_layer/dragger_layer.gd`
- 新建：`tests/helpers/combat_drag_test_fixture.gd`
- 测试：`tests/combat_operation_drag_adapter_test.gd`
- 修改测试：`tests/dragger_layer_test.gd`
- 修改测试：`tests/drag_layer_retraction_test.gd`

**输入接口**

```gdscript
CombatOperationDragAdapter.configure(board_zone: BoardZone, preview_provider: Callable, command_sink: Callable)
CombatOperationDragAdapter.begin_drag(card: CardEntity) -> bool
CombatOperationDragAdapter.update_drag(global_position: Vector2) -> CombatOperationTargetPreview
CombatOperationDragAdapter.finish_drag(global_position: Vector2) -> CombatCommandResult
BoardZone.get_cards() -> Array[Card]
CardEntity.get_card_view_screen_rect() -> Rect2
```

**输出接口**

```gdscript
CombatOperationTargetPreview.target_id: StringName
CombatOperationTargetPreview.is_valid: bool
CombatOperationTargetPreview.highlight_style: StringName
CombatOperationTargetPreview.rejection_reason: StringName
DraggerLayer.combat_operation_submitted(command: PlayCombatOperationCommand)
DraggerLayer.combat_operation_drag_hold_changed(active: bool)
DraggerLayer.configure_combat_operation_adapter(adapter: CombatOperationDragAdapter) -> void
```

### 步骤 1：编写失败的拖拽适配器测试

新建 `tests/combat_operation_drag_adapter_test.gd`：

```gdscript
extends SceneTree

const AdapterScript = preload("res://scripts/game/event/encounter/combat_operation_drag_adapter.gd")

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_drag_test_fixture.gd").new()
    var root := fixture.make_board_card(&"root", Rect2(0, 0, 100, 100))
    var head := fixture.make_board_card(&"head", Rect2(50, 0, 100, 100))
    var board := fixture.make_board([root, head])
    var submitted: Array[PlayCombatOperationCommand] = []
    var adapter := AdapterScript.new()
    adapter.configure(
        board,
        func(operation_id: StringName, target_id: StringName): return fixture.valid_preview(target_id),
        func(command: PlayCombatOperationCommand): submitted.append(command); return CombatCommandResult.accepted(command.command_id)
    )

    assert(adapter.begin_drag(fixture.make_operation_card(&"retreat-card")))
    var preview := adapter.update_drag(Vector2(75, 50))
    assert(preview.target_id == &"head")
    assert(preview.is_valid)
    assert(not _has_property(preview, &"returned_card_ids"))
    assert(not _has_property(preview, &"shield_delta"))
    adapter.finish_drag(Vector2(75, 50))
    assert(submitted.size() == 1 and submitted[0].target_id == &"head")
    quit(0)

func _has_property(value: Object, property_name: StringName) -> bool:
    return value.get_property_list().any(func(entry: Dictionary): return entry[&"name"] == property_name)
```

重叠点同时位于尾部卡牌和头部卡牌的矩形范围内。预期目标是头部卡牌，因为适配器按照牌链/绘制顺序的逆序遍历 `BoardZone.get_cards()`。

添加无效目标和无目标用例。两种情况都不得提交命令，预览只能暴露 `target_id`、有效性、高亮样式和拒绝原因。

### 步骤 2：运行测试并确认失败

```powershell
& $godot --headless --path . --script res://tests/combat_operation_drag_adapter_test.gd
```

预期：以非零退出码退出，因为预览 DTO 和适配器尚不存在。

### 步骤 3：实现仅负责 UI 的适配器

预览 DTO：

```gdscript
class_name CombatOperationTargetPreview
extends RefCounted

var target_id: StringName
var is_valid: bool
var highlight_style: StringName
var rejection_reason: StringName
```

其中不得包含撤退牌段、护盾变化量、未来金币、伤害、结果或来源卡牌去向。

命中测试：

```gdscript
func _find_target(global_position: Vector2) -> CardEntity:
    var cards := _board_zone.get_cards()
    for index in range(cards.size() - 1, -1, -1):
        var card := cards[index] as CardEntity
        if card != null and card.get_card_view_screen_rect().has_point(global_position):
            return card
    return null
```

适配器可以高亮/取消高亮目标，并构建 `PlayCombatOperationCommand`。它不得消耗货币、修改牌链、增加护盾、消耗卡牌或执行战斗结算。

在棋盘/市场的普通放置处理之前，将其接入 `DraggerLayer`。如果 `begin_drag()` 返回 `false`，必须保留现有全部拖拽行为。操作拖拽被接受时发出 `combat_operation_drag_hold_changed(true)`，并在所有完成/取消路径发出 `false`。必须谨慎合并用户当前尚未提交的 `dragger_layer.gd` 修改，不能整文件覆盖。

### 步骤 4：运行定向测试和拖拽回归测试

```powershell
& $godot --headless --path . --script res://tests/combat_operation_drag_adapter_test.gd
& $godot --headless --path . --script res://tests/dragger_layer_test.gd
& $godot --headless --path . --script res://tests/drag_layer_retraction_test.gd
& $godot --headless --path . --script res://tests/hand_zone_drag_cancel_test.gd
& $godot --headless --editor --path . --quit
```

预期：所有命令均以退出码 `0` 结束；普通拖拽行为保持不变。

### 步骤 5：提交

```powershell
git add scripts/combatv2/operation/combat_operation_target_preview.gd scripts/game/event/encounter/combat_operation_drag_adapter.gd scripts/game/drag_layer/dragger_layer.gd tests/combat_operation_drag_adapter_test.gd tests/dragger_layer_test.gd tests/drag_layer_retraction_test.gd tests/helpers/combat_drag_test_fixture.gd
git commit -m "feat: add combat operation target dragging"
```

---

## 任务 10：添加棋盘表现端口与卡牌动画接口

**文件**

- 新建：`scripts/game/event/encounter/combat_presentation_port.gd`
- 新建：`scripts/game/event/encounter/combat_presentation_coordinator.gd`
- 修改：`scripts/game/event/encounter/combat_event_view.gd`
- 修改：`scripts/card/card_entity.gd`
- 新建：`tests/helpers/combat_presentation_test_fixture.gd`
- 测试：`tests/combat_presentation_coordinator_test.gd`
- 修改测试：`tests/combat_event_ui_scene_test.gd`
- 修改测试：`tests/board_scene_composition_test.gd`

**输入接口**

```gdscript
CombatPresentationCoordinator.configure(port: CombatPresentationPort, speed: CombatSpeedController)
CombatPresentationCoordinator.present(batch: CombatEventBatch) -> void
CombatPresentationPort.find_card(card_id: StringName) -> CardEntity
CombatPresentationPort.show_monster_value(value_id: StringName, before: int, after: int, speed: float) -> void
```

**输出接口**

```gdscript
CombatPresentationCoordinator.batch_presented(sequence: int)
CardEntity.request_combat_trigger_feedback(speed_multiplier: float) -> void
CardEntity.request_points_change(before: int, after: int, speed_multiplier: float) -> void
CardEntity.request_shield_change(before: int, after: int, speed_multiplier: float) -> void
CombatEventView.begin_combat(instance: EventInstance, monster: MobInstance) -> void
CombatEventView.show_batch(batch: CombatEventBatch) -> void
CombatEventView.show_settlement(result: CombatResult) -> void
CombatEventView.set_combat_speed(speed_multiplier: float) -> void
```

### 步骤 1：编写失败的表现层测试

新建 `tests/combat_presentation_coordinator_test.gd`：

```gdscript
extends SceneTree

const CoordinatorScript = preload("res://scripts/game/event/encounter/combat_presentation_coordinator.gd")
const BatchScript = preload("res://scripts/combat_framework/protocol/combat_event_batch.gd")
const EventScript = preload("res://scripts/combat_framework/protocol/combat_domain_event.gd")

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_presentation_test_fixture.gd").new()
    var card_view := fixture.make_card_view(&"head")
    var port := fixture.make_port({&"head": card_view})
    var coordinator := CoordinatorScript.new()
    coordinator.configure(port, fixture.make_speed(2.0))

    var events: Array[CombatDomainEvent] = [
        EventScript.new(EventScript.Type.CARD_POINTS_CHANGED, &"head", {&"before": 4, &"after": 2}),
        EventScript.new(EventScript.Type.CARD_SHIELD_CHANGED, &"head", {&"before": 0, &"after": 3}),
        EventScript.new(EventScript.Type.CARD_TRIGGER_FINISHED, &"head", {}),
    ]
    var batch := BatchScript.new(3, BatchScript.Kind.CARD_TRIGGER, events, {})
    coordinator.present(batch)

    assert(card_view.point_requests == [[4, 2, 2.0]])
    assert(card_view.shield_requests == [[0, 3, 2.0]])
    assert(card_view.trigger_feedback_speeds == [2.0])
    assert(coordinator.is_presenting())
    card_view.complete_all_requests()
    assert(not coordinator.is_presenting())
    quit(0)
```

### 步骤 2：运行测试并确认失败

```powershell
& $godot --headless --path . --script res://tests/combat_presentation_coordinator_test.gd
```

预期：命令以非零状态退出，因为表现路由与卡牌反馈钩子尚不存在。

### 步骤 3：实现事件到视图的路由，但暂不制作具体动画

`CombatPresentationPort` 是适配器接口/脚本，而不是领域层依赖。其具体实现通过稳定的 `instance_id` 定位棋盘卡牌，并提供怪物、日志和结算相关的视图方法。

协调器路由：

```gdscript
match event.type:
    CombatDomainEvent.Type.CARD_POINTS_CHANGED:
        _port.find_card(event.subject_id).request_points_change(event.data[&"before"], event.data[&"after"], _speed.speed_multiplier)
    CombatDomainEvent.Type.CARD_SHIELD_CHANGED:
        _port.find_card(event.subject_id).request_shield_change(event.data[&"before"], event.data[&"after"], _speed.speed_multiplier)
    CombatDomainEvent.Type.CARD_TRIGGER_FINISHED:
        _port.find_card(event.subject_id).request_combat_trigger_feedback(_speed.speed_multiplier)
```

本任务中的卡牌钩子可以立即更新标签并发出完成信号。必须保留方法/信号边界，以便后续动画实现替换当前的立即完成逻辑：

```gdscript
signal combat_feedback_finished(request_id: int)

func request_points_change(before: int, after: int, speed_multiplier: float) -> void:
    _set_points_label(after)
    combat_feedback_finished.emit(_next_feedback_request_id())
```

护盾变化和触发抖动使用等价的钩子。只有属于该批次的全部表现请求完成后，协调器才进行 ACK。缺失或过期的卡牌视图只记录警告并按立即完成处理，绝不能导致战斗死锁。

使用上方 **输出接口** 中列出的五个方法替换 `CombatEventView` 的完整结果回放接口。将每个批次增量转换为日志行，以继续提供现有战斗日志。

### 步骤 4：运行定向测试和 UI 回归测试

```powershell
& $godot --headless --path . --script res://tests/combat_presentation_coordinator_test.gd
& $godot --headless --path . --script res://tests/combat_event_ui_scene_test.gd
& $godot --headless --path . --script res://tests/board_scene_composition_test.gd
& $godot --headless --editor --path . --quit
```

预期：所有命令均以 `0` 状态退出；即使当前视觉动画仍为立即完成的最小实现，棋盘卡牌也已经提供动画接口。

### 步骤 5：提交

```powershell
git add scripts/game/event/encounter/combat_presentation_port.gd scripts/game/event/encounter/combat_presentation_coordinator.gd scripts/game/event/encounter/combat_event_view.gd scripts/card/card_entity.gd tests/combat_presentation_coordinator_test.gd tests/combat_event_ui_scene_test.gd tests/board_scene_composition_test.gd tests/helpers/combat_presentation_test_fixture.gd
git commit -m "feat: route combat batches to board presentation"
```

---

## 任务 11：接入遭遇战生命周期、调度器、拖拽操作与最终结算

**文件**

- 修改：`scripts/game/event/encounter/encounter_combat_flow_coordinator.gd`
- 修改：`scripts/game/event/event_interaction_controller.gd`
- 修改：`scripts/game/event/event_modal_coordinator.gd`
- 修改：`scripts/game/run/run_flow_coordinator.gd`
- 修改：`scripts/game/event/encounter/combat_event_view.gd`
- 测试：`tests/event_interaction_controller_test.gd`
- 测试：`tests/event_modal_coordinator_test.gd`
- 测试：`tests/encounter_resolution_coordinator_test.gd`
- 测试：`tests/run_flow_coordinator_test.gd`
- 测试：`tests/game_manager_combat_routing_test.gd`

**输入接口**

```gdscript
EncounterCombatFlowCoordinator.create_session(player_stats: CombatStats, chain: Array[CardInstance], monster: MobInstance, operation_cards: Array[CardInstance], resources: Dictionary) -> CombatSession
EventInteractionController.begin(instance: EventInstance, player_stats: CombatStats, chain: Array[CardInstance], operation_cards: Array[CardInstance] = [], resources: Dictionary = {}) -> void
EventInteractionController.acknowledge_combat_batch(sequence: int) -> void
EventInteractionController.submit_combat_command(command: CombatCommand) -> CombatCommandResult
EventInteractionController.set_combat_speed(multiplier: float) -> void
```

**输出接口**

```gdscript
EventInteractionController.combat_started(instance: EventInstance, monster: MobInstance)
EventInteractionController.combat_batch_ready(instance: EventInstance, batch: CombatEventBatch)
EventInteractionController.combat_result_ready(instance: EventInstance, result: CombatResult)
EventInteractionController.combat_speed_changed(multiplier: float)
EventInteractionController.get_active_combat_session() -> CombatSession
```

### 步骤 1：用失败的会话测试替换同步控制器预期

修改 `tests/event_interaction_controller_test.gd`，使战斗测试验证增量式行为：

```gdscript
func _test_monster_event_streams_batches_before_result() -> void:
    var flow := FakeEncounterCombatFlow.new()
    var controller := EventInteractionController.new()
    controller.configure(flow)
    var batches: Array[CombatEventBatch] = []
    var results: Array[CombatResult] = []
    controller.combat_batch_ready.connect(func(_instance, batch): batches.append(batch))
    controller.combat_result_ready.connect(func(_instance, result): results.append(result))

    controller.begin(_make_monster_event(), _make_stats(), _make_chain(), [], {&"gold": 6})
    assert(controller.get_active_combat_session() != null)
    assert(batches.size() == 1)
    assert(batches[0].kind == CombatEventBatch.Kind.COMBAT_START)
    assert(results.is_empty())

    controller.acknowledge_combat_batch(batches[0].sequence)
    controller.advance_combat_if_ready(999.0)
    assert(batches.size() == 2)
    assert(results.is_empty())
```

增加终局用例：反复执行 ACK/推进，断言最终只发出一次 `combat_result_ready`，随后调用 `confirm_combat_settlement()` 并观察到 `interaction_finished`。

### 步骤 2：添加失败的模态层接线测试

修改 `tests/event_modal_coordinator_test.gd`：

```gdscript
func _test_modal_passes_hand_operation_cards_and_gold_to_combat() -> void:
    var fixture := ModalFixture.new()
    fixture.hand_zone.cards = [fixture.make_operation_card(&"retreat-card")]
    fixture.player.gold = 8
    fixture.modal.begin(fixture.monster_event, fixture.stats, fixture.chain)
    assert(fixture.interaction.last_operation_card_ids == [&"retreat-card"])
    assert(fixture.interaction.last_resources == {&"gold": 8})
```

### 步骤 3：运行测试并确认失败

```powershell
& $godot --headless --path . --script res://tests/event_interaction_controller_test.gd
& $godot --headless --path . --script res://tests/event_modal_coordinator_test.gd
```

预期：测试失败，因为控制器仍在调用同步的 `resolve()`，并立即发出完整结果。

### 步骤 4：实现增量式编排

`EncounterCombatFlowCoordinator.begin(instance)` 仍负责创建并返回遭遇怪物。将运行时调用点的 `resolve(...)` 替换为 `create_session(...)`，结算职责仍保留在现有遭遇结算层。

`EventInteractionController` 持有：

```gdscript
var _active_combat_session: CombatSession
var _combat_speed := CombatSpeedController.new()
var _advance_gate := CombatAdvanceGate.new()
var _scheduler := CombatScheduler.new(_combat_speed, _advance_gate)
```

控制器循环：

```gdscript
func acknowledge_combat_batch(sequence: int) -> void:
    if _active_combat_session == null:
        return
    if not _active_combat_session.acknowledge_batch(sequence):
        return
    _advance_gate.set_presentation_ready(true)
    _scheduler.begin_wait(_base_delay_for_phase(_active_combat_session.get_phase()))

func advance_combat_if_ready(delta: float) -> void:
    if _active_combat_session == null:
        return
    _scheduler.advance(delta)
    if not _scheduler.can_advance():
        return
    var batch := _active_combat_session.advance_one_event()
    if batch == null:
        return
    _advance_gate.set_presentation_ready(false)
    combat_batch_ready.emit(_active_event, batch)
```

当终局批次完成 ACK 且会话进入结束状态时，只构建一次结果，将其保存到 `_pending_combat_result`，清空 `_active_combat_session`，并发出 `combat_result_ready`。`confirm_combat_settlement()` 保持现有职责：在棋盘、玩家和怪物结算成功后结束事件交互。

`EventModalCoordinator` 从 `_hand_zone.get_cards()` 收集操作卡牌，将其映射为 `card_instance`，并传入 `{&"gold": _player.gold}`。它负责连接：

- `combat_batch_ready` → `CombatEventView.show_batch()` / 表现协调器。
- 表现层的 `batch_presented` → `acknowledge_combat_batch()`。
- 拖拽适配器命令 → `submit_combat_command()`。
- 拖拽保持状态 → 推进门控的交互保持状态。
- 战斗速度控件 → `set_combat_speed()`。

尽可能保持 `RunFlowCoordinator` 的外部调用形式不变：

```gdscript
_modal.begin(instance, _context.player_stats, _board.board_zone.get_combat_card_chain())
```

模态层已经持有手牌和玩家依赖，不应向领域协议中加入场景节点。

### 步骤 5：运行集成回归测试

```powershell
& $godot --headless --path . --script res://tests/event_interaction_controller_test.gd
& $godot --headless --path . --script res://tests/event_modal_coordinator_test.gd
& $godot --headless --path . --script res://tests/encounter_resolution_coordinator_test.gd
& $godot --headless --path . --script res://tests/run_flow_coordinator_test.gd
& $godot --headless --path . --script res://tests/game_manager_combat_routing_test.gd
& $godot --headless --editor --path . --quit
```

预期：所有命令均以 `0` 状态退出；在终局批次完成表现并被 ACK 之前，不会发布最终结果。

### 步骤 6：提交

```powershell
git add scripts/game/event/encounter/encounter_combat_flow_coordinator.gd scripts/game/event/event_interaction_controller.gd scripts/game/event/event_modal_coordinator.gd scripts/game/run/run_flow_coordinator.gd scripts/game/event/encounter/combat_event_view.gd tests/event_interaction_controller_test.gd tests/event_modal_coordinator_test.gd tests/encounter_resolution_coordinator_test.gd tests/run_flow_coordinator_test.gd tests/game_manager_combat_routing_test.gd
git commit -m "refactor: stream encounter combat sessions"
```

---

## 任务 12：移除旧的完整回放、强化故障处理并运行完整回归测试

**文件**

- 修改：`scripts/combatv2/combat_service.gd`
- 修改：`scripts/game/event/encounter/combat_event_view.gd`
- 修改：`scripts/game/event/event_interaction_controller.gd`
- 修改：`scripts/game/event/event_modal_coordinator.gd`
- 新建：`tests/helpers/combat_session_test_fixture.gd`
- 测试：`tests/combat_fault_handling_test.gd`
- 测试：`tests/combat_session_end_to_end_test.gd`
- 根据已删除的旧 API 按需修改测试：
  - `tests/combatv2_service_test.gd`
  - `tests/combat_event_ui_scene_test.gd`
  - `tests/game_manager_combat_routing_test.gd`

**输入接口**

```gdscript
CombatSession.fail(reason: StringName, details: Dictionary = {}) -> CombatEventBatch
EventInteractionController.cancel_combat(reason: StringName) -> void
```

**输出接口**

```gdscript
CombatSession.get_fault() -> Dictionary
CombatResult generated only from a terminal session snapshot
No runtime caller of CombatService.resolve_encounter()
No runtime caller of CombatEventView.show_combat(..., result)
```

### 步骤 1：编写失败的故障处理测试

新建 `tests/combat_fault_handling_test.gd`：

```gdscript
extends SceneTree

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_session_test_fixture.gd").new()
    var session: CombatSession = fixture.make_session()
    _ack(session, session.start())

    var bad := CombatIntent.new(999, &"source", &"target", {})
    var batch := session.commit_test_intents([bad])
    assert(batch.kind == CombatEventBatch.Kind.COMBAT_END)
    assert(session.get_phase() == CombatSession.Phase.FAULTED)
    assert(session.get_fault()[&"reason"] == &"unsupported_intent")
    assert(session.advance_one_event() == null)
    quit(0)
```

仅通过测试子类/夹具暴露 `commit_test_intents()`；不要将其加入生产环境的会话 API。

### 步骤 2：编写失败的端到端场景测试

新建 `tests/combat_session_end_to_end_test.gd`：

```gdscript
extends SceneTree

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_session_test_fixture.gd").new()
    var session: CombatSession = fixture.make_trigger_and_operation_session()
    var kinds: Array[int] = []
    var batch := session.start()
    while batch != null:
        kinds.append(batch.kind)
        assert(session.acknowledge_batch(batch.sequence))
        if session.get_phase() == CombatSession.Phase.PLAYER_OPERATION_WINDOW:
            assert(session.submit_command(fixture.make_shield_command()).is_accepted)
            session.close_operation_window()
        batch = session.advance_one_event()

    assert(kinds == [
        CombatEventBatch.Kind.COMBAT_START,
        CombatEventBatch.Kind.CARD_TRIGGER,
        CombatEventBatch.Kind.PLAYER_ATTACK,
        CombatEventBatch.Kind.COMBAT_OPERATION,
        CombatEventBatch.Kind.CARD_TRIGGER,
        CombatEventBatch.Kind.MONSTER_ATTACK,
        CombatEventBatch.Kind.COMBAT_END,
    ])
    assert(session.is_finished())
    assert(session.build_result() != null)
    quit(0)
```

夹具数值必须保证该精确序列具有确定性，并且在怪物攻击完成之前不会产生致死结果。

### 步骤 3：运行测试并确认失败

```powershell
& $godot --headless --path . --script res://tests/combat_fault_handling_test.gd
& $godot --headless --path . --script res://tests/combat_session_end_to_end_test.gd
```

预期：测试失败，因为故障转换和完整事件顺序尚未得到强制保证。

### 步骤 4：强化会话失败行为并移除旧运行时路径

发生内部结算错误时：

1. 停止接受命令。
2. 清空待处理的命令请求和触发请求。
3. 记录结构化故障字典。
4. 若当前没有待确认批次，则发出一个终局/故障 `COMBAT_END` 批次。
5. 不再应用任何额外状态变更。
6. 在终局批次完成表现后，允许 UI/控制器安全退出战斗。

搜索并移除以下运行时用法：

```powershell
rg "resolve_encounter\(|\.resolve\(player_stats|show_combat\(" scripts scenes
```

迁移后的预期结果：任何遭遇运行时调用都不会同步计算完整战斗，任何视图都不会回放预先计算的 `CombatResult`。只有仍有价值的独立服务测试确有需要时，才可保留范围受限的兼容方法；应在说明中将其标记为 `@deprecated`，并确保没有场景或控制器引用它。

确保命令拒绝表现为普通的 `COMMAND_REJECTED` 批次，而不是会话故障。表现过程中遇到过期视图目标时，应记录警告并立即视为视觉完成，而不是将其判定为会话故障。

### 步骤 5：运行完整战斗与集成测试套件

```powershell
$tests = @(
  'combat_protocol_test.gd',
  'combat_session_state_test.gd',
  'combat_intent_resolver_test.gd',
  'combat_session_test.gd',
  'combat_attack_order_test.gd',
  'combat_trigger_queue_test.gd',
  'combat_operation_resolver_test.gd',
  'combat_pending_request_revalidation_test.gd',
  'combat_retreat_operation_test.gd',
  'combat_gold_shield_operation_test.gd',
  'combat_speed_controller_test.gd',
  'combat_scheduler_test.gd',
  'combat_operation_drag_adapter_test.gd',
  'combat_presentation_coordinator_test.gd',
  'combat_fault_handling_test.gd',
  'combat_session_end_to_end_test.gd',
  'combatv2_service_test.gd',
  'combat_effect_pipeline_test.gd',
  'combatv2_card_rule_test.gd',
  'ribwood_combat_balance_test.gd',
  'event_interaction_controller_test.gd',
  'event_modal_coordinator_test.gd',
  'combat_event_ui_scene_test.gd',
  'game_manager_combat_routing_test.gd',
  'encounter_resolution_coordinator_test.gd',
  'run_flow_coordinator_test.gd',
  'dragger_layer_test.gd',
  'drag_layer_retraction_test.gd',
  'hand_zone_drag_cancel_test.gd',
  'card_chain_coordinator_test.gd',
  'board_zone_test.gd',
  'board_scene_composition_test.gd'
)
$godot = (Get-Command Godot_v4.7.1-stable_win64_console.exe).Source
foreach ($test in $tests) {
  & $godot --headless --path . --script ("res://tests/" + $test)
  if ($LASTEXITCODE -ne 0) { throw "Failed: $test" }
}
& $godot --headless --editor --path . --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot import/compile check failed' }
```

预期：所有测试以及最终导入/编译检查均以 `0` 状态退出。

### 步骤 6：检查架构不变量

```powershell
rg "resolve_encounter\(|show_combat\(" scripts scenes
rg "DAMAGE_MONSTER|DAMAGE_CARD" scripts/combatv2/session
rg "combat_speed|speed_multiplier" scripts/combatv2 scripts/game/event
rg "CUT_CHAIN_FROM_TARGET|ADD_CARD_SHIELD" scripts/combatv2
```

手动确认：

- 玩家攻击与怪物攻击由不同的请求处理器创建，并分别进入独立批次。
- 任何操作卡拖拽适配器都不直接修改领域状态。
- 预览 DTO 只暴露目标表现信息。
- 每个已接受的操作都必须在出队时重新校验。
- 提交下一批次前必须完成当前批次的 ACK。
- 战斗速度会影响结算延迟、表现调用以及操作窗口的实际持续时间。
- 正在进行的拖拽会阻止战斗推进。
- 只有终局批次完成 ACK 后才开始最终结算。

### 步骤 7：提交

```powershell
git add scripts/combatv2/combat_service.gd scripts/game/event/encounter/combat_event_view.gd scripts/game/event/event_interaction_controller.gd scripts/game/event/event_modal_coordinator.gd tests/helpers/combat_session_test_fixture.gd tests/combat_fault_handling_test.gd tests/combat_session_end_to_end_test.gd tests/combatv2_service_test.gd tests/combat_event_ui_scene_test.gd tests/game_manager_combat_routing_test.gd
git commit -m "test: complete stateful combat migration"
```

---

## 最终验收清单

### 协议与时序

- [ ] `CombatSession` 是唯一权威的战斗状态机。
- [ ] `advance_one_event()` 每次最多提交一个主要原子行为。
- [ ] 批次是不可变副本，并拥有单调递增的序列 ID。
- [ ] 当前批次完成 ACK 前不能提交下一批次。
- [ ] 玩家攻击和怪物攻击使用独立阶段、意图集合及批次。
- [ ] 玩家攻击造成致死结果时，不会再创建怪物攻击。
- [ ] 触发请求会显式表示战斗开始、攻击完成、触发完成以及头部卡牌耗尽。

### 玩家操作

- [ ] 操作卡牌共用定义、目标、消耗、处置、效果、命令和解析器类型。
- [ ] 命令只影响未来尚未提交的请求。
- [ ] 提交顺序必须确定；出队时必须重新校验。
- [ ] 固定目标失效时应拒绝命令，不得自动改选目标。
- [ ] 被拒绝的操作不会造成部分状态变更，也不会消耗卡牌。
- [ ] 撤退会从选中卡牌向头部方向切断牌链、消耗自身、跳过剩余战斗，并仅强化怪物一次。
- [ ] 金币换护盾操作会以原子方式扣除金币并更新护盾。
- [ ] 预览只暴露目标、有效性、高亮和原因。

### 表现与时间控制

- [ ] 棋盘卡牌 ID 能将领域事件映射到正确的 `CardEntity`。
- [ ] 即使动画主体仍是最小实现，也已提供点数、护盾和触发动画钩子。
- [ ] 缺失的表现目标不会导致 ACK 死锁。
- [ ] 设置名称统一使用“战斗速度”（`combat speed`）。
- [ ] 实时调整战斗速度时会保留已完成进度，并重新缩放剩余实际时间。
- [ ] 结算延迟、表现动画请求和操作窗口持续时间均使用战斗速度。
- [ ] 正在进行的拖拽会暂停会话推进。

### 集成与安全性

- [ ] 领域协议中不包含场景 `Node` 引用。
- [ ] 遭遇控制器以增量方式发出批次，并且只发出一次最终结果。
- [ ] 只有终局表现完成 ACK 后才生成最终结果并执行结算。
- [ ] 不存在回放预计算完整战斗结果的运行时路径。
- [ ] 用户工作区中无关的修改保持原样且不被暂存。
- [ ] 完整战斗、拖拽、棋盘、事件和运行流程回归测试全部通过。
