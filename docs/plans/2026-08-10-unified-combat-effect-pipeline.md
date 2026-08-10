# 统一战斗 Effect 管线

**状态：已实现（2026-08-10）**

## 目标

战斗中的每一次可见数值变化都以 `CombatEffect` 表达。卡牌规则和残响效果只负责对待结算的 Effect 列表进行添加、修改或取消；运行时对象的生命、护甲和卡牌点数只能由 `CombatEffectResolver` 改变。这样同一份记录同时服务于：

- 战斗日志；
- 后续逐效果动画；
- 回放、调试和数值验算；
- 新卡牌 / 新残响能力的扩展。

## 核心结构

```text
CombatService2
  └─ 每次牌链交锋创建 CombatEffectDraft
       ├─ 放入基础点数交锋 Effect
       │    卡牌 -> 残响：DAMAGE（当前卡牌点数）
       │    残响 -> 当前卡牌：DAMAGE（交锋前残响 HP）
       ├─ CardRule hooks（先执行）
       ├─ MobEffect hooks（后执行）
       └─ CombatEffectResolver（唯一状态写入点）
            └─ CombatStep.effects（最终快照，供日志/动画消费）
```

### 唯一效果模型：`CombatEffect`

位置：`scripts/combatv2/card/combat_effect.gd`

- 类型：`DAMAGE`、`ADD_DEFENSE`、`HEAL`；
- 目标：玩家、残响、指定卡牌；
- 来源：卡牌、牌根、残响普通动作、残响效果、系统；
- `base_value` 保存规则修改前的基础数值，`value` 为最终待结算数值；
- `sequence` 和 `phase` 保证一个步骤内的播放顺序与生命周期来源稳定；
- `parameters` 保存通用元数据（如 `armor_multiplier`、解析前后快照、实际结算量）；
- `tags` 用于展示、动画和后续效果联动；
- `cancelled` 允许规则拦截 Effect，而不丢失日志记录。

### 草稿与解析

- `CombatEffectDraft` 只包含交锋上下文与 `Array[CombatEffect]`，不是第二套伤害/治疗数据模型。
- 草稿添加 Effect 时会写入 `sequence`、`phase` 和稳定目标名称。
- `CombatEffectResolver` 是唯一会调用 `take_damage`、`heal`、`add_defense`、`consume_armor` 或 `consume_points` 的组件。
- 每个已解析 Effect 写入：
  - `applied`：实际 HP / 点数 / 护甲变化；
  - `absorbed`：目标护甲实际吸收量（玩家、残响和卡牌目标统一记录）；
  - `total`：本 Effect 的总消耗 / 结算量，通常为 `absorbed + applied`；
  - `resolved`：是否找到有效运行时目标并完成结算；取消、无效目标和不支持类型会保留在日志中，但标记为未结算；
  - `hp_before` / `hp_after`、`defense_before` / `defense_after`；
  - 卡牌目标的 `card_points_before` / `card_points_after`、`card_armor_before` / `card_armor_after`；
  - `resolved`：是否真正进行了解析。

## 规则钩子

### 卡牌：`CardRule`

保留放置阶段 `execute_on_card_added` 和牌链位置判断 `should_trigger_before_head`；战斗期统一使用：

```gdscript
func on_attack(draft) -> bool
func on_before_resolve(draft) -> bool
func on_card_depleted(draft, card: CardInstance) -> bool
```

返回 `true` 表示确实修改了草稿，所属 `CardInstance` 才消耗一次 `effective_count`。规则禁止直接修改玩家、残响或卡牌运行时状态。

### 残响：`MobEffect`

位置：`scripts/combatv2/mob_effect.gd`。残响配置不再为每一种能力增设 `MobData` 字段，只配置 `effects: Array[Resource]`。

```gdscript
func on_attack(draft) -> bool
func on_before_resolve(draft) -> bool
func on_card_depleted(draft, card: CardInstance) -> bool
```

`MobEffect` 也具备 `effective_count`；`MobInstance` 保存效果触发次数，并持有配置资源的运行时副本，避免未来有状态效果污染资源或其它残响实例。

## 当前可复用残响效果

| 效果 | 脚本 | 行为 |
| --- | --- | --- |
| 破盾 | `mob_effect_shield_break.gd` | 修改残响对当前卡牌伤害的 `armor_multiplier`；护甲更快消耗，但不把护甲吸收错误地当成额外点数伤害。 |
| 后排冲击 | `mob_effect_rear_shock.gd` | 为头部后方指定数量的卡牌追加 `Target.CARD` 的 `DAMAGE` Effect。 |

## 肋骨林地配置

- **啮髓鼠群**：不带特殊效果，维持首战教学压力。
- **腐肋幼狼**：`撕甲啃咬`，护甲损耗 ×2。
- **抱肋者·白角守墓鹿**：`空腔回响`，每场战斗首次交锋时对头部后方第一张卡造成 1 点伤害。

资源位于：`data/levels/ribwood/mob_effects/`。

## 当前非目标

- 普通 `MobAction` 保留为通用 Effect 生成器（`MobActionResolver`），但当前简化后的“点数对比”基础交锋不额外结算普通行动，避免改变既有基础怪物节奏。
- 卡牌放置阶段的数值变化仍由牌链放置服务处理；本文档的“统一 Effect”范围是战斗期及其可展示结算。

## 回归测试

- `tests/combat_effect_pipeline_test.gd`：Effect 元数据、护甲优先、取消、卡牌规则、残响效果、有效次数、结算前后快照、护甲吸收统计、无效目标与步骤记录。
- `tests/ribwood_mob_effect_data_test.gd`：第一关残响效果资源配置。
- `tests/combatv2_service_test.gd`、`tests/combatv2_card_rule_test.gd`：牌链顺序和旧卡牌规则兼容。
- `tests/combat_event_ui_scene_test.gd`：Effect 日志使用实际结算值、声明值、护甲吸收和稳定目标快照。
- `tests/ribwood_combat_balance_test.gd`、`tests/combat_event_ui_scene_test.gd`、`tests/game_manager_combat_routing_test.gd`、`tests/run_flow_coordinator_test.gd`：地图、UI 与流程回归。
