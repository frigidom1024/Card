# 情绪回潮诅咒实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有遭遇结算惩罚系统中，将“合法牌链结算完但未击杀残响”改为可续战的「情绪回潮」诅咒，并保留本次遭遇的生命、行动循环与强化状态。

**Architecture:** `CombatService2` 继续在运行时副本上计算战斗，并将残响行动索引写入 `CombatResult`。牌链耗尽时返回独立的 `CURSED` outcome 和组合型 `CombatPenaltyEmotionalTide`；确认结算后，`GameManager` 将结果写回遭遇运行时状态、执行诅咒、将实际尾牌实体移回手牌，并解除交互锁以便玩家重建链条。`MobInstance` 保存回潮层数与层数上限，行动转换根据层数增加数值而不修改静态 `MobAction` Resource。

**Tech Stack:** Godot 4 / GDScript、现有 SceneTree 测试脚本、Git。

## Global Constraints

- 不修改或清理用户已有的无关工作区改动；只暂存本功能涉及的明确文件。
- 不实现尚未定稿的信仰值、肋弓共鸣、第一关卡牌/怪物重做或忘川回声专属偷牌。
- 合法牌链耗尽且双方存活时：玩家与残响生命保留，双方护甲清零，尾牌回到手牌，残响获得 1 层回潮。
- 每层回潮使 ATTACK、DEFEND、HEAL 行动值 +1；普通残响最多 2 层，Boss 最多 3 层。
- 回潮后保留残响行动索引；不能把 `MobAction.value` Resource 原地改写。
- 根牌是唯一牌桌卡时不移除根牌；仍可触发回潮并允许玩家再补牌挑战。
- UI 必须将该 outcome 表述为「情绪回潮」而不是撤离或战败。

---

## File Structure

- `scripts/combatv2/combat_result.gd` — 增加 `CURSED` outcome 与残响行动索引快照。
- `scripts/combatv2/combat_service.gd` — 产生情绪回潮结果，并把回潮层数传入怪物行动转换。
- `scripts/combatv2/mob_action_resolver.gd` — 接受非破坏性的数值加成参数。
- `scripts/game/event/encounter/mob_instance.gd` — 保存回潮层数、上限及复制后的状态。
- `scripts/game/event/encounter/encounter_event_resolver.gd` — 为 Boss 遭遇设定 3 层上限。
- `scripts/combatv2/penalty/penalty_context.gd` — 提供诅咒执行所需的手牌、玩家与残响运行时引用。
- `scripts/combatv2/penalty/combat_penalty.gd` — 注册 `EMOTIONAL_TIDE` 类型。
- `scripts/combatv2/penalty/combat_penalty_emotional_tide.gd` — 组合执行清甲、尾牌回手与残响强化。
- `scripts/game_manager.gd` — 在确认诅咒结算时写回 HP/行动索引、执行惩罚并将 `CardEntity` 回手。
- `scripts/game/event/encounter/combat_event_view.gd` — 渲染回潮标题、文案与确认按钮。
- `tests/combatv2_service_test.gd` — 覆盖 CURSED outcome、惩罚语义、行动数值强化和层数上限。
- `tests/game_manager_combat_routing_test.gd` — 覆盖真实尾牌回手、HP/行动索引/层数跨续战保持。
- `tests/combat_event_ui_scene_test.gd` — 覆盖回潮结算文案。

## Task 1: 战斗结果、残响状态与诅咒模型

**Files:**
- Modify: `scripts/combatv2/combat_result.gd`
- Modify: `scripts/game/event/encounter/mob_instance.gd`
- Modify: `scripts/game/event/encounter/encounter_event_resolver.gd`
- Modify: `scripts/combatv2/penalty/combat_penalty.gd`
- Modify: `scripts/combatv2/penalty/penalty_context.gd`
- Create: `scripts/combatv2/penalty/combat_penalty_emotional_tide.gd`
- Test: `tests/combatv2_service_test.gd`

**Interfaces:**
- Produces `CombatResult.Outcome.CURSED`.
- Produces `CombatResult.monster_action_index_after: int`.
- Produces `MobInstance.echo_tide_stacks: int`, `MobInstance.max_echo_tide_stacks: int`, `MobInstance.gain_echo_tide() -> bool`.
- Produces `CombatPenalty.Type.EMOTIONAL_TIDE` and `CombatPenaltyEmotionalTide.execute(context: PenaltyContext) -> bool`.

- [ ] **Step 1: Add failing model tests.**

```gdscript
func _test_emotional_tide_penalty_returns_tail_clears_defense_and_caps_stacks() -> void:
    var monster := _make_monster("Echo", 10, 0, [])
    var root := _make_card("Root", CardData.CardType.ROOT)
    var tail := _make_card("Tail", CardData.CardType.NORMAL)
    var player := _make_stats(10, 8, 0, 3)
    monster.stats.defense = 4
    var context := PenaltyContext.new()
    context.cards_on_board = [root, tail]
    context.cards_in_hand = []
    context.player_stats = player
    context.monster = monster

    var penalty := CombatPenaltyEmotionalTide.new()
    penalty.execute(context)
    penalty.execute(context)
    penalty.execute(context)

    _expect(context.cards_on_board == [root], "tide keeps root on board")
    _expect(context.cards_in_hand == [tail], "tide returns tail to hand")
    _expect(player.defense == 0 and monster.stats.defense == 0, "tide clears both defenses")
    _expect(monster.echo_tide_stacks == 2, "normal echo tide caps at two stacks")
```

- [ ] **Step 2: Run the focused SceneTree test and verify it fails because the emotional-tide model does not exist.**

Run: `godot --headless --path . --script res://tests/combatv2_service_test.gd`

Expected: failure mentioning the missing `EMOTIONAL_TIDE` enum/type or `CombatPenaltyEmotionalTide` class.

- [ ] **Step 3: Implement the minimum state and penalty model.**

```gdscript
# MobInstance
var echo_tide_stacks := 0
var max_echo_tide_stacks := 2

func gain_echo_tide() -> bool:
    var before := echo_tide_stacks
    echo_tide_stacks = mini(echo_tide_stacks + 1, max_echo_tide_stacks)
    return echo_tide_stacks > before
```

```gdscript
# CombatPenaltyEmotionalTide.execute
if context.player_stats != null:
    context.player_stats.defense = 0
if context.monster != null and context.monster.stats != null:
    context.monster.stats.defense = 0
if context.cards_on_board.size() > 1:
    context.cards_in_hand.append(context.cards_on_board.pop_back())
if context.monster != null:
    context.monster.gain_echo_tide()
return true
```

`MobInstance.duplicate_for_encounter()` and `CombatContext._duplicate_monster()` must copy action index, tide stacks and tide cap. `EncounterEventResolver.begin()` must set the cap to 3 when `instance.get_event_type() == EventData.EventType.BOSS`.

- [ ] **Step 4: Re-run the focused test and verify it passes.**

Run: `godot --headless --path . --script res://tests/combatv2_service_test.gd`

Expected: exit code 0 for the test script after updating its old card-chain-exhaustion expectations in Task 2.

## Task 2: 战斗服务产生可续战诅咒并强化残响行动

**Files:**
- Modify: `scripts/combatv2/combat_service.gd`
- Modify: `scripts/combatv2/mob_action_resolver.gd`
- Modify: `scripts/combatv2/combat_result.gd`
- Test: `tests/combatv2_service_test.gd`

**Interfaces:**
- `MobActionResolver.to_effects(action: MobAction, source_name: String, value_bonus: int = 0) -> Array[CombatEffect]`.
- `CombatResult` constructor accepts optional `monster_action_index_after: int = 0`.
- Legal exhausted chains produce `CombatResult.Outcome.CURSED` with one `EMOTIONAL_TIDE` penalty.

- [ ] **Step 1: Change existing exhausted-chain assertions and add the new behavior test before production edits.**

```gdscript
_expect_result(result, CombatResult.Outcome.CURSED, 3, 1, "card chain exhaustion triggers emotional tide")
_expect(result.penalties.size() == 1, "tide result has one curse")
_expect(result.penalties[0].type == CombatPenalty.Type.EMOTIONAL_TIDE, "tide result has emotional-tide penalty")
_expect(result.monster_action_index_after == 1, "tide snapshots the next monster action")
```

Also add a monster with `echo_tide_stacks = 1`, one ATTACK, one DEFEND and one HEAL action across three resolutions; assert emitted effect values are base value + 1 and source `MobAction.value` remains unchanged.

- [ ] **Step 2: Run the test script and verify the CURSED assertions fail against the current RETREAT implementation.**

Run: `godot --headless --path . --script res://tests/combatv2_service_test.gd`

Expected: assertion failure that reports RETREAT where CURSED is expected.

- [ ] **Step 3: Implement only the required service changes.**

```gdscript
# chain end in CombatService2
return _build_result(context, CombatResult.Outcome.CURSED, _emotional_tide_penalties())

# monster action conversion
for effect in MobActionResolverScript.to_effects(
    action, source_name, context.monster.echo_tide_stacks
):
```

`_build_result()` must pass the runtime copy's current `action_index` into `CombatResult`; never mutate `MobAction.value`.

- [ ] **Step 4: Run the combat service script and verify all assertions pass.**

Run: `godot --headless --path . --script res://tests/combatv2_service_test.gd`

Expected: exit code 0; all former legal exhausted-chain tests now assert CURSED rather than RETREAT.

## Task 3: 确认结算后写回遭遇状态并使尾牌实体回手

**Files:**
- Modify: `scripts/game_manager.gd`
- Test: `tests/game_manager_combat_routing_test.gd`

**Interfaces:**
- `_apply_monster_combat_state(instance: EventInstance, result_stats: CombatStats, action_index: int = -1) -> void` writes HP, clears defense, and writes action index when it is non-negative.
- `_apply_penalties(instance: EventInstance, penalties: Array[CombatPenalty]) -> void` executes model penalties then applies required `CardEntity` movement.
- `_return_tail_card_to_hand() -> void` removes only a non-root board tail and reparents it to `HandArea` without deleting its persistent card instance/entity.

- [ ] **Step 1: Convert the old retreat routing test into a failing emotional-tide continuation test.**

```gdscript
_expect(outcomes[0].outcome == CombatResult.Outcome.CURSED, "confirmed curse emits CURSED")
_expect(manager.player_stats.hp == 7, "curse preserves player damage")
_expect(runtime_state.mob_instance.stats.hp == 19, "curse preserves monster damage")
_expect(runtime_state.mob_instance.action_index == 1, "curse preserves next action index")
_expect(runtime_state.mob_instance.echo_tide_stacks == 1, "curse adds one tide stack")
_expect(tail in manager.hand_area.cards, "curse returns the real tail entity to hand")
_expect(tail.card_instance.cur_zone == CardInstance.ZONE.HAND, "returned tail is marked as hand")
_expect(tail in manager.card_entities and tail.card_instance in manager.cards_inst, "returned tail remains owned")
```

After re-adding `tail` over the event, inspect the pending result's monster-action step and assert its DEFEND value is `6` (base 5 + one tide stack), proving the action index and tide both carry into the next challenge.

- [ ] **Step 2: Run the routing script and verify it fails because the current flow treats the result as RETREAT and discards the tail.**

Run: `godot --headless --path . --script res://tests/game_manager_combat_routing_test.gd`

Expected: failures for outcome, player HP preservation, hand ownership and action strength.

- [ ] **Step 3: Implement the CURSED branch.**

```gdscript
CombatResult.Outcome.CURSED:
    _apply_player_combat_state(result.player_stats_after)
    _apply_monster_combat_state(instance, result.monster_stats_after, result.monster_action_index_after)
    _apply_penalties(instance, result.penalties)
    _refresh_event_display(instance)
    _finish_encounter()
```

For `EMOTIONAL_TIDE`, build a `PenaltyContext` around the current player, encounter monster, board chain and hand chain; execute it, then call `_return_tail_card_to_hand()` to move the actual board entity. Temporarily allow one extra hand slot when the hand is full, matching existing interaction-lock recovery behavior; do not discard or remove the returned card from `cards_inst` or `card_entities`.

- [ ] **Step 4: Re-run the routing script and verify all assertions pass.**

Run: `godot --headless --path . --script res://tests/game_manager_combat_routing_test.gd`

Expected: exit code 0; the same unresolved encounter can be re-triggered by placing the returned tail again.

## Task 4: 回潮结算 UI

**Files:**
- Modify: `scripts/game/event/encounter/combat_event_view.gd`
- Test: `tests/combat_event_ui_scene_test.gd`

**Interfaces:**
- `CombatEventView._show_settlement()` handles `CombatResult.Outcome.CURSED`.

- [ ] **Step 1: Add a failing UI test.**

```gdscript
view.call("show_combat", null, _make_mob("森林狼"), _result(CombatResult.Outcome.CURSED, [], [CombatPenaltyEmotionalTide.new()]))
progress_button.pressed.emit()
_expect(result_title.text == "情绪回潮", "curse settlement uses emotional-tide title")
_expect(result_body.text.contains("重新布置牌链"), "curse settlement explains retry")
_expect(confirm_button.text == "重整牌链", "curse settlement names retry action")
```

- [ ] **Step 2: Run the UI script and verify it fails due to the unhandled outcome.**

Run: `godot --headless --path . --script res://tests/combat_event_ui_scene_test.gd`

Expected: empty/incorrect title and confirmation text for CURSED.

- [ ] **Step 3: Add the dedicated UI branch.**

```gdscript
CombatResult.Outcome.CURSED:
    _result_title_label.text = "情绪回潮"
    _result_body_label.text = "残响未被击败，情绪重新回涨。\n最后一张牌返回手牌；残响行动已强化。重新布置牌链后可再次挑战。"
    _confirm_button.text = "重整牌链"
```

- [ ] **Step 4: Re-run the UI script and verify it passes.**

Run: `godot --headless --path . --script res://tests/combat_event_ui_scene_test.gd`

Expected: exit code 0.

## Task 5: 综合验证与安全提交

**Files:**
- Modify: `docs/plans/2026-08-03-emotional-tide-penalty-implementation.md` (mark checked implementation steps only after evidence exists)
- Test: `tests/combatv2_service_test.gd`, `tests/game_manager_combat_routing_test.gd`, `tests/combat_event_ui_scene_test.gd`

- [ ] **Step 1: Run the three focused scripts from a clean test invocation.**

Run:

```powershell
$godot = (Get-Command godot -ErrorAction Stop).Source
& $godot --headless --path . --script res://tests/combatv2_service_test.gd
& $godot --headless --path . --script res://tests/game_manager_combat_routing_test.gd
& $godot --headless --path . --script res://tests/combat_event_ui_scene_test.gd
```

Expected: every process exits 0.

- [ ] **Step 2: Inspect the diff and confirm scope.**

Run: `git diff --check` and `git status --short`.

Expected: no whitespace errors; only the files enumerated above plus this plan are staged for this feature.

- [ ] **Step 3: Commit only the feature files.**

```powershell
git add -- scripts/combatv2/combat_result.gd scripts/combatv2/combat_service.gd scripts/combatv2/mob_action_resolver.gd scripts/combatv2/penalty/combat_penalty.gd scripts/combatv2/penalty/penalty_context.gd scripts/combatv2/penalty/combat_penalty_emotional_tide.gd scripts/game/event/encounter/mob_instance.gd scripts/game/event/encounter/encounter_event_resolver.gd scripts/game/event/encounter/combat_event_view.gd scripts/game_manager.gd tests/combatv2_service_test.gd tests/game_manager_combat_routing_test.gd tests/combat_event_ui_scene_test.gd docs/plans/2026-08-03-emotional-tide-penalty-implementation.md
git commit -m "feat: add emotional tide encounter curse"
```

Expected: commit contains no unrelated user modifications.

## Plan Self-Review

- Spec coverage: legal-chain CURSED outcome, preserved HP/action index, tail-to-hand, defense clearing, stack bonus and caps, Boss cap, UI and repeat challenge are all mapped to Tasks 1–4.
- Scope: belief/faith, rib-arch shields, map/card/monster redesign and unique echo mechanics are explicitly excluded.
- Placeholder scan: no TBD/TODO items; each code task has concrete affected files, API shape and expected test command.
- Type consistency: all tasks use `CURSED`, `EMOTIONAL_TIDE`, `monster_action_index_after`, `echo_tide_stacks`, and `_return_tail_card_to_hand` consistently.

