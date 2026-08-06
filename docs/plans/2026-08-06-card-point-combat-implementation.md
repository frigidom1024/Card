# 卡牌点数持续消耗战斗实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 将遭遇战斗改为从牌链末尾向牌根结算的卡牌点数比较，并保持卡牌当前点数、牌根重置回手、RETREAT 惩罚和特殊残响效果。

**Architecture:** `CombatService2` 只计算战斗，不直接修改棋盘节点、手牌或地图；它返回残响状态、逐卡结算步骤和卡牌状态变更。`EncounterResolutionCoordinator` 应用卡牌状态变更并执行事件结果、奖励和惩罚。卡牌配合集中在独立的点数/配合解析器中，使用反向结算上下文读取已经结算的后置卡牌。

**Tech Stack:** Godot 4、GDScript、现有 `combatv2` 服务、Godot headless SceneTree 测试。

## Global Constraints

- 不修改棋盘尺寸、卡牌连接规则、事件接触触发方式、商店/宝藏总体流程和 Boss 追击移动逻辑。
- 普通战斗不再执行怪物行动队列；`RETREAT` 只表示当前牌链未击杀残响。
- 普通卡牌只有当前点数归零才移除；未参与结算的卡牌留在牌桌。
- 牌根归零时重置为最大点数并返回手牌区。
- 卡牌配合只改变当前卡牌本次比较点数，不直接改地图、玩家资源或其它卡牌状态。
- 现有 `CombatResult.penalties` 保留，惩罚处理与点数归零处理分离。
- 不覆盖工作区已有未提交修改：`data/levels/ribwood/exploration_spawn_config.tres`、`scripts/game_manager.gd`，也不处理插件 DLL 删除状态。

---

## Task 1: 建立卡牌点数运行时模型

**Files:**
- Modify: `scripts/card/card_data.gd`
- Modify: `scripts/card/card_instance.gd`
- Create: `scripts/combatv2/combat_card_change.gd`
- Test: `tests/card_point_state_test.gd`

**Interfaces:**
- `CardData.max_points: int`：静态卡牌最大点数；`value` 继续作为商店价格，不复用。
- `CardInstance.current_points: int`：运行时当前点数，初始化为 `card_data.max_points`。
- `CardInstance.reset_points() -> void`
- `CardInstance.consume_points(amount: int) -> int`：扣除非负点数并返回实际扣除值。
- `CardInstance.is_depleted() -> bool`
- `CombatCardChange`：记录 `card`, `points_before`, `effective_points`, `points_after`, `depleted`, `returned_to_hand`。

- [ ] **Step 1: Write the failing test**

在 `tests/card_point_state_test.gd` 覆盖：

```gdscript
var data := CardData.new()
data.max_points = 5
var card := CardInstance.new(data)
_expect(card.current_points == 5, "new card starts at max points")
_expect(card.consume_points(2) == 2, "consume returns actual amount")
_expect(card.current_points == 3, "card keeps remaining points")
_expect(not card.is_depleted(), "card with points remains active")
_expect(card.consume_points(3) == 3, "card can reach zero")
_expect(card.is_depleted(), "zero-point card is depleted")
```

同时测试牌根重置逻辑由调用方控制，`CardInstance.reset_points()` 只负责把当前点数恢复到最大点数，不负责移动区域。

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
godot --headless --path . --script tests/card_point_state_test.gd
```

Expected: FAIL because `max_points`, `current_points` and point methods do not exist.

- [ ] **Step 3: Implement the minimal data model**

在 `CardData` 增加：

```gdscript
@export_range(1, 999, 1) var max_points: int = 1
```

在 `CardInstance` 增加运行时字段和方法。初始化时将 `current_points` 设为 `max_points`，并在运行时复制方法中复制当前点数、区域、坐标和方向。

不要删除现有 `damage`、`defense`、`heal` 字段；本次战斗不再读取它们，但保留字段以避免无关 UI 和资源加载回归。

- [ ] **Step 4: Implement `CombatCardChange`**

该类型只保存计算结果，不执行棋盘操作。`returned_to_hand` 只由牌根状态变更设置，普通卡牌归零只设置 `depleted`。

- [ ] **Step 5: Run test to verify it passes**

```powershell
godot --headless --path . --script tests/card_point_state_test.gd
```

Expected: PASS。

- [ ] **Step 6: Commit**

```powershell
git add scripts/card/card_data.gd scripts/card/card_instance.gd scripts/combatv2/combat_card_change.gd tests/card_point_state_test.gd
git commit -m "feat(combat): add persistent card point state"
```

---

## Task 2: 拆分卡牌配合与本次比较点数解析

**Files:**
- Modify: `scripts/combatv2/card/card_resolution_context.gd`
- Create: `scripts/combatv2/card/card_point_resolver.gd`
- Create: `scripts/combatv2/card/card_synergy_resolver.gd`
- Modify: `scripts/combatv2/card/card_rule.gd`
- Create: `tests/card_point_resolver_test.gd`
- Modify: `tests/combatv2_card_rule_test.gd`

**Interfaces:**
- `CardSynergyResolver.resolve_bonus(context: CardResolutionContext) -> int`
- `CardPointResolver.resolve(card: CardInstance, context: CardResolutionContext) -> Dictionary`，返回 `points_before`、`synergy_bonus` 和 `effective_points`。
- `CardResolutionContext.get_current_card()`、`get_post_resolved_card()`、`get_resolved_cards()`、`get_remaining_cards()`。

- [ ] **Step 1: Write failing tests for reverse context**

构造牌链 `[root, card_a, card_b]`，按 `card_b`、`card_a`、`root` 顺序建立上下文，验证：

- `card_b` 没有后置卡牌；
- `card_a` 的后置卡牌是 `card_b`；
- `card_a` 可以读取 `card_b` 结算后的剩余点数；
- 未结算卡牌仍出现在 `get_remaining_cards()` 中。

- [ ] **Step 2: Run focused tests to verify failure**

```powershell
godot --headless --path . --script tests/card_point_resolver_test.gd
godot --headless --path . --script tests/combatv2_card_rule_test.gd
```

Expected: reverse-context assertions fail because the context still assumes forward order and old damage rules.

- [ ] **Step 3: Replace ambiguous previous-card access**

将 `_previous_resolved_card` 和 `get_previous_resolved_card()` 改为反向语义的 `post_resolved_card` / `get_post_resolved_card()`，避免“上一张”在末尾优先结算下产生歧义。

规则只能读取上下文快照，不直接修改其它卡牌。上下文复制时必须包含 `current_points`。

- [ ] **Step 4: Implement point and synergy resolvers**

`CardPointResolver` 使用：

```gdscript
effective_points = max(card.current_points + synergy_bonus, 0)
```

第一版配合规则只产生整数加成，允许读取：

- 后置卡牌仍有点数；
- 后置卡牌刚好归零；
- 同类型标签；
- 牌链长度。

不要在该模块处理奖励、惩罚、地图、信仰值或牌桌节点。

- [ ] **Step 5: Update rule contracts and tests**

旧的 `damage` / `defense` / `heal` 规则不再参与新战斗主流程。保留旧规则资源的加载兼容，但新增点数规则测试，确保配合加成只影响本次比较值。

- [ ] **Step 6: Run focused tests**

```powershell
godot --headless --path . --script tests/card_point_resolver_test.gd
godot --headless --path . --script tests/combatv2_card_rule_test.gd
```

Expected: PASS。

- [ ] **Step 7: Commit**

```powershell
git add scripts/combatv2/card/card_resolution_context.gd scripts/combatv2/card/card_point_resolver.gd scripts/combatv2/card/card_synergy_resolver.gd scripts/combatv2/card/card_rule.gd tests/card_point_resolver_test.gd tests/combatv2_card_rule_test.gd
git commit -m "feat(combat): resolve reverse card-chain synergy"
```

---

## Task 3: 重写 CombatService2 的末尾优先结算

**Files:**
- Modify: `scripts/combatv2/combat_service.gd`
- Modify: `scripts/combatv2/combat_context.gd`
- Modify: `scripts/combatv2/combat_result.gd`
- Modify: `scripts/combatv2/combat_step.gd`
- Modify: `tests/combatv2_service_test.gd`
- Modify: `tests/ribwood_combat_balance_test.gd`

**Interfaces:**
- `CombatService2.resolve_encounter(player_stats, card_chain, monster) -> CombatResult` 保持调用签名。
- 新结果字段 `card_changes: Array[CombatCardChange]`。
- `CombatResult.processed_card_count` 表示实际参与比较的卡牌数量，牌根是否参与按实际情况计数。
- `CombatStep` 记录卡牌名称、点数前值、配合加成、最终比较点数、点数后值、残响生命前后值。

- [ ] **Step 1: Write failing combat tests**

在 `tests/combatv2_service_test.gd` 增加以下用例：

```gdscript
# [root 2, card 3, card 7] vs 4 HP:
# tail card 7 resolves first, monster dies, tail card keeps 3 points,
# earlier cards are untouched, root is untouched.

# [root 2, card 3] vs 8 HP:
# tail card 3 depletes, root 2 depletes, monster remains 3 HP,
# result is RETREAT.

# card equal to monster HP depletes and kills.

# card less than monster HP depletes and removes.

# root depletes: result contains root reset and return-to-hand change.

# cards after the lethal card in the reverse order are not processed.
```

- [ ] **Step 2: Run focused tests to verify failure**

```powershell
godot --headless --path . --script tests/combatv2_service_test.gd
```

Expected: old action-order and damage assertions fail.

- [ ] **Step 3: Replace the combat loop**

删除或停止使用 `action_queue`、`resolve_monster_action()`、`MobActionResolver` 在普通遭遇中的路径。使用反向游标：

```gdscript
var index := context.cards.size() - 1
while index >= 0 and _is_monster_alive(context):
    var card := context.cards[index]
    var change := _resolve_card_against_monster(context, card, index)
    context.card_changes.append(change)
    if change.depleted:
        context.remaining_cards.erase(card)
    if _is_monster_defeated(context):
        break
    index -= 1
```

卡牌结算必须按设计公式更新模拟副本，而不是直接删除 `CardEntity`。牌根归零时，在 `CombatCardChange` 中记录 `returned_to_hand = true` 和重置后的点数。

- [ ] **Step 4: Update result and step snapshots**

`CombatResult` 继续返回玩家状态、残响状态、步骤、惩罚和结果；新增卡牌变更数组。普通怪物行动索引字段保留兼容读取或标记为不再由新服务更新，不能再驱动战斗。

- [ ] **Step 5: Run focused tests**

```powershell
godot --headless --path . --script tests/combatv2_service_test.gd
godot --headless --path . --script tests/ribwood_combat_balance_test.gd
```

Expected: new reverse-point tests PASS；旧的逐行动测试需要按新规则更新，不得保留“每张卡后怪物行动”的断言。

- [ ] **Step 6: Commit**

```powershell
git add scripts/combatv2/combat_service.gd scripts/combatv2/combat_context.gd scripts/combatv2/combat_result.gd scripts/combatv2/combat_step.gd tests/combatv2_service_test.gd tests/ribwood_combat_balance_test.gd
git commit -m "feat(combat): resolve encounters by reverse card points"
```

---

## Task 4: 应用卡牌变更并保留牌桌逻辑

**Files:**
- Modify: `scripts/game/event/encounter/encounter_resolution_coordinator.gd`
- Modify: `scripts/game/event/encounter/encounter_combat_flow_coordinator.gd`
- Modify: `scripts/game/card_manager.gd` only if a shared card-state application helper is needed
- Modify: `tests/game_manager_combat_routing_test.gd`
- Create: `tests/encounter_card_change_application_test.gd`

**Interfaces:**
- `EncounterCombatFlowCoordinator.resolve(...) -> CombatResult` 继续只计算结果。
- `EncounterResolutionCoordinator.apply_card_changes(result.card_changes) -> bool` 负责把结果应用到真实 `CardInstance` 和牌桌实体。
- 普通卡牌归零：从 Board 移除并进入现有弃置/销毁流程。
- 牌根归零：从 Board 移除，重置当前点数，通过 `RunCardService` 返回手牌。

- [ ] **Step 1: Write failing application tests**

验证：

- 高点数末尾卡击杀后，真实实例保留差值；
- 归零普通卡牌从牌桌移除；
- 未参与结算卡牌仍在牌桌；
- 归零牌根重置点数并回到手牌；
- `RETREAT` 不自动把所有未使用卡牌回手。

- [ ] **Step 2: Run focused tests to verify failure**

```powershell
godot --headless --path . --script tests/encounter_card_change_application_test.gd
godot --headless --path . --script tests/game_manager_combat_routing_test.gd
```

Expected: current coordinator still only applies玩家/怪物属性，并在 `RETREAT` 中把尾牌直接回手。

- [ ] **Step 3: Apply card changes before result-specific side effects**

在 `EncounterResolutionCoordinator.apply()` 中，先应用 `result.card_changes`，再执行 `VICTORY` 奖励、`RETREAT` 惩罚或 `DEFEAT` 失败流程。

删除 `_return_tail_card_to_hand()` 作为 RETREAT 默认行为。若需要返回或移除尾牌，必须通过 `result.penalties` 的明确条目执行。

- [ ] **Step 4: Keep node and instance operations outside CombatService2**

由协调器根据 `CombatCardChange` 找到对应 `CardEntity`，执行 Board 移除和手牌转移。服务层不得调用 `Board.remove_card()`、`RunCardService` 或 `queue_free()`。

- [ ] **Step 5: Run focused tests**

```powershell
godot --headless --path . --script tests/encounter_card_change_application_test.gd
godot --headless --path . --script tests/game_manager_combat_routing_test.gd
```

Expected: PASS。

- [ ] **Step 6: Commit**

```powershell
git add scripts/game/event/encounter/encounter_resolution_coordinator.gd scripts/game/event/encounter/encounter_combat_flow_coordinator.gd scripts/game/card_manager.gd tests/encounter_card_change_application_test.gd tests/game_manager_combat_routing_test.gd
git commit -m "feat(encounter): apply persistent card point changes"
```

---

## Task 5: 接入残响结果效果与现有惩罚

**Files:**
- Modify: `scripts/game/event/encounter/mob_data.gd`
- Modify: `scripts/game/event/encounter/mob_instance.gd`
- Modify: `scripts/game/event/encounter/encounter_resolution_coordinator.gd`
- Create: `scripts/game/event/encounter/mob_result_effect.gd`
- Create: `tests/mob_result_effect_test.gd`
- Modify: `tests/ribwood_echo_data_test.gd`

**Interfaces:**
- `MobData.on_retreat_effects: Array[MobResultEffect]`
- `MobData.on_defeat_effects: Array[MobResultEffect]`
- `MobData.on_victory_effects: Array[MobResultEffect]`
- `MobResultEffect.Type { HEAL_SELF, GAIN_ENHANCEMENT, APPEND_PENALTY }`
- `MobResultEffect.value: int` and `MobResultEffect.penalty: CombatPenalty`.
- `MobInstance` continues owning runtime HP and enhancement stacks.
- Result effects receive the encounter instance and `CombatResult` through the coordinator, not through `CombatService2`.

- [ ] **Step 1: Write failing tests**

覆盖：

- `RETREAT` 执行配置的回潮强化/现有惩罚；
- `DEFEAT` 只执行特殊残响战败效果；
- 普通啮髓鼠没有额外战败效果；
- Boss 的效果不会改变普通点数比较流程。

- [ ] **Step 2: Run focused tests to verify failure**

```powershell
godot --headless --path . --script tests/mob_result_effect_test.gd
godot --headless --path . --script tests/ribwood_echo_data_test.gd
```

Expected: outcome effect fields and dispatch are missing.

- [ ] **Step 3: Add configuration and dispatcher**

创建 `MobResultEffect` Resource：`HEAL_SELF` 将当前残响生命恢复 `value`（不超过最大生命），`GAIN_ENHANCEMENT` 调用 `MobInstance.gain_enhancement()`，`APPEND_PENALTY` 将配置的 `CombatPenalty` 追加到本次结果惩罚执行队列。协调器按 `result.outcome` 选择对应数组并顺序执行。效果执行失败时记录错误，但不重复发放奖励或重复完成事件。

- [ ] **Step 4: Keep existing RETREAT penalty path**

保留 `CombatResult.penalties` 的执行入口。卡牌点数归零和惩罚主动移除分别记录、分别执行，避免一次 RETREAT 同时把未使用卡牌误当作已消耗卡牌。

- [ ] **Step 5: Run tests and commit**

```powershell
godot --headless --path . --script tests/mob_result_effect_test.gd
godot --headless --path . --script tests/ribwood_echo_data_test.gd
git add scripts/game/event/encounter/mob_data.gd scripts/game/event/encounter/mob_instance.gd scripts/game/event/encounter/encounter_resolution_coordinator.gd scripts/combatv2/penalty tests/mob_result_effect_test.gd tests/ribwood_echo_data_test.gd
git commit -m "feat(encounter): support configurable echo result effects"
```

---

## Task 6: 迁移肋骨林地卡牌和残响数值

**Files:**
- Modify: `data/levels/ribwood/cards/*.tres`
- Modify: `data/levels/ribwood/mobs/*.tres`
- Modify: `data/levels/ribwood/event_lib.tres`
- Modify: `data/levels/ribwood/events/ribwood_marrow_rat_event.tres`
- Modify: `data/levels/ribwood/events/ribwood_fallen_rib_wolf_event.tres`
- Modify: `data/levels/ribwood/events/ribwood_white_horn_hart_boss_event.tres`
- Modify: `tests/ribwood_card_data_test.gd`
- Modify: `tests/ribwood_combat_balance_test.gd`
- Modify: `tests/ribwood_echo_data_test.gd`

**Interfaces:**
- Ribwood card resources provide `max_points` values.
- Ribwood mob resources provide current design HP and no required ordinary action loop.
- Existing gold/card drops remain unchanged.

- [ ] **Step 1: Write balance assertions**

至少覆盖：

```text
啮髓鼠群生命为 3～4；
腐肋巨狼生命为 8～10；
白角守墓鹿生命为 18～22；
牌根点数为 2；
普通卡牌点数为 1～5；
```

并用三组牌链验证：

- 低点数牌链只能削弱啮髓鼠群；
- 购买一张 3～5 点卡牌后能明显缩短腐肋巨狼的击杀链；
- Boss 需要多个高点数卡牌或配合才能稳定击杀。

- [ ] **Step 2: Run failing/current balance tests**

```powershell
godot --headless --path . --script tests/ribwood_card_data_test.gd
godot --headless --path . --script tests/ribwood_combat_balance_test.gd
godot --headless --path . --script tests/ribwood_echo_data_test.gd
```

Expected: old damage/action-based assertions fail until resources and fixtures migrate.

- [ ] **Step 3: Migrate resources**

把旧的战斗伤害数值迁移到 `max_points`；`value` 保持商店价格；不删除资源中无关的兼容字段，避免商店和卡牌详情加载失败。

- [ ] **Step 4: Update tests and run them**

```powershell
godot --headless --path . --script tests/ribwood_card_data_test.gd
godot --headless --path . --script tests/ribwood_combat_balance_test.gd
godot --headless --path . --script tests/ribwood_echo_data_test.gd
```

Expected: PASS。

- [ ] **Step 5: Commit**

```powershell
git add data/levels/ribwood tests/ribwood_card_data_test.gd tests/ribwood_combat_balance_test.gd tests/ribwood_echo_data_test.gd
git commit -m "data(ribwood): balance card points and echo health"
```

---

## Task 7: 更新战斗步骤展示和回归兼容

**Files:**
- Modify: `scripts/game/event/encounter/combat_event_view.gd`
- Modify: `scripts/card/card_detail_format.gd`
- Modify: `scenes/card_view/card_combat_tag_bar.tscn`
- Modify: `scenes/card_view/card_detail_stat_seal.tscn`
- Modify: `scenes/card_view/card_info.tscn`
- Modify: `scenes/card_view/zoom_view.tscn`
- Modify: `tests/combat_event_ui_scene_test.gd`
- Modify: `tests/card_detail_ui_test.gd`
- Modify: `tests/game_manager_combat_routing_test.gd`

**Interfaces:**
- 战斗步骤展示卡牌点数前值、配合加成、最终比较点数、残响生命前后值。
- 不再展示普通怪物行动队列作为战斗主流程。
- 卡牌详情展示最大点数；运行时牌桌卡牌可显示当前点数，但本任务不改变棋盘布局。

- [ ] **Step 1: Write failing UI assertions**

验证战斗结果步骤包含点数变化字段，卡牌详情包含点数而非仅依赖旧的 damage/defense/heal 字段。

- [ ] **Step 2: Run focused UI tests**

```powershell
godot --headless --path . --script tests/combat_event_ui_scene_test.gd
godot --headless --path . --script tests/card_detail_ui_test.gd
```

Expected: current UI仍读取旧 `CombatEffect` 和旧三属性展示。

- [ ] **Step 3: Update presentation adapters**

只修改展示层读取方式；不要让 UI 重新计算战斗结果。所有点数变化以 `CombatStep` / `CombatCardChange` 为准。

- [ ] **Step 4: Run UI and routing tests**

```powershell
godot --headless --path . --script tests/combat_event_ui_scene_test.gd
godot --headless --path . --script tests/card_detail_ui_test.gd
godot --headless --path . --script tests/game_manager_combat_routing_test.gd
```

Expected: PASS。

- [ ] **Step 5: Commit**

```powershell
git add scripts/game/event/encounter/combat_event_view.gd scripts/card/card_detail_format.gd scenes/card_view tests/combat_event_ui_scene_test.gd tests/card_detail_ui_test.gd tests/game_manager_combat_routing_test.gd
git commit -m "feat(ui): present card point combat results"
```

---

## Task 8: 全量验证和清理旧战斗路径

**Files:**
- Test: all scripts under `tests/`

- [ ] **Step 1: Run combat and Ribwood suites**

```powershell
godot --headless --path . --script tests/combatv2_service_test.gd
godot --headless --path . --script tests/combatv2_card_rule_test.gd
godot --headless --path . --script tests/ribwood_combat_balance_test.gd
godot --headless --path . --script tests/encounter_card_change_application_test.gd
```

- [ ] **Step 2: Run all existing SceneTree tests one by one**

```powershell
Get-ChildItem tests -Filter '*.gd' | ForEach-Object {
    godot --headless --path . --script $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $($_.Name)" }
}
```

Expected: all tests exit with code 0. Python-only tests remain run by the existing Python test command if present.

- [ ] **Step 3: Search for stale combat assumptions**

```powershell
Get-ChildItem scripts,data,tests -Recurse -File | Select-String -Pattern 'next_action\(|MobActionResolver|MONSTER_ACTION|_return_tail_card_to_hand|damage.*monster|previous_resolved_card'
```

Every remaining match must either be a compatibility path explicitly covered by tests or be removed from the new ordinary encounter flow.

- [ ] **Step 4: Run git diff and inspect only owned files**

```powershell
git status --short
git diff --check
```

Do not stage or reset the existing user modifications or the plugin DLL deletion.

- [ ] **Step 5: Verify clean feature staging boundary**

```powershell
git status --short
```

Expected: only the files owned by Tasks 1–7 are staged or committed; do not stage `data/levels/ribwood/exploration_spawn_config.tres`, `scripts/game_manager.gd`, or the plugin DLL deletion.

