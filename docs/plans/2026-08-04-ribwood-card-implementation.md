# 《肋骨林地》第一关卡牌与残响实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 将《肋骨林地》设计稿落地为可运行的第一关卡牌资源、少量牌链规则、残响数据和回归测试，使玩家可以用牌根加两张配合牌击败啮髓鼠群，并在更长遭遇中体验攻击、防御、治疗三种构筑方向。

**Architecture:** 保留现有 `CardData`、`CardRule`、`MobData` 和事件资源体系，不新建独立卡牌系统。卡牌效果继续通过 `CardResolutionContext` 读取上一张牌和牌链末位，通过 `CardResolutionDraft` 以加法修改伤害、防御和治疗；残响继续通过 `MobAction` 和 `MobInstance.enhancement_stacks` 表达行动与回潮强化。第一关使用独立的 `data/levels/ribwood/event_lib.tres` 及其子目录；通用事件结构保持不变，信仰值和 `RETREAT` 机制保持现有边界，不与卡牌规则耦合。

**Tech Stack:** Godot 4.x、GDScript、`.tres` Resource 数据、现有 headless `SceneTree` 测试脚本。

## Global Constraints

- 设计文档以 `D:/project/MonoCard/mono-card/docs/design/2026-08-04-ribwood-card-design.md` 为唯一数值基准。
- 不在 `superpower` 或 `superpowers` 目录新增本功能文档；实施计划保存在 `D:/project/MonoCard/mono-card/docs/plans/`。每个关卡的事件库、事件模板、内容池和残响数据必须放在 `data/levels/<level_id>/` 下。
- 游戏代码不新增名为 Curse、Tide、CurseOutcome 或 TideOutcome 的函数、字段或枚举；牌链结束但未击杀继续使用 `CombatResult.Outcome.RETREAT`。
- “回潮强化”只能作为注释、叙事描述或设计术语；代码层使用既有 `enhancement_stacks` 和英文 `strengthen` 相关命名。
- `PlayerData.faith` 是信仰值唯一真值；卡牌资源不能直接读写信仰值。
- 不执行 `git reset`、工作区清理或全量暂存；当前工作区存在大量与本计划无关的用户改动。
- 每个任务结束都必须运行对应的最小测试；提交时只暂存该任务拥有的文件。

## 文件边界总览

### 第一关资源目录

第一关资源必须按关卡聚合，避免未来第二关继续把事件和残响写入全局目录：

```text
D:/project/MonoCard/mono-card/data/levels/ribwood/
├── event_lib.tres
├── cards/
├── events/
├── event_content/
└── mobs/
```

`event_lib.tres` 收录六个事件模板：熄灭的骨髓灯、啮髓鼠群、断旗巡礼营、腐肋幼狼、缝骨者的祭坛和抱肋者·白角守墓鹿。动态信仰残响也只能从当前关卡注入的 `EventLib` 中筛选普通 `MONSTER` 模板。全局 `data/event/event_lib.tres` 不在本次实现中覆盖或追加第一关数据。
### 卡牌规则

- Create: `D:/project/MonoCard/mono-card/scripts/combatv2/card/rules/previous_weapon_damage_bonus_rule.gd` — 上一张武器时的加法伤害规则。
- Create: `D:/project/MonoCard/mono-card/scripts/combatv2/card/rules/previous_defense_damage_bonus_rule.gd` — 上一张提供防御时的加法伤害规则。
- Create: `D:/project/MonoCard/mono-card/scripts/combatv2/card/rules/previous_defense_heal_bonus_rule.gd` — 上一张提供防御时的加法治疗规则。
- Create: `D:/project/MonoCard/mono-card/scripts/combatv2/card/rules/last_card_defense_bonus_rule.gd` — 牌链末位的固定护甲加成规则。
- Keep: `D:/project/MonoCard/mono-card/scripts/combatv2/card/rules/previous_weapon_damage_double_rule.gd`、`first_card_damage_double_rule.gd`、`last_card_defense_double_rule.gd` — 保留旧测试资源兼容性，不再用于肋骨林地新卡牌。

### 卡牌资源与初始牌组

- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_guardian_root.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_rib_blade.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_old_tinder.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_folded_rib_shield.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_warm_marrow_flask.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_rib_nail.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_shield_fragment.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_amber_marrow_bottle.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_bone_armor_round_shield.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_ember_blade.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_warmth_charm.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_scabbed_potion.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_grave_beetle.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_bone_stitching_needle.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_old_chest_cloak.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_last_resort_strike.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_white_horn_relic.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_sternum_plate.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_guardian_ember.tres`
- Modify: `D:/project/MonoCard/mono-card/data/starting_decks/revival_starting_deck.tres` — 将 starter cards 指向五张肋骨林地初始卡，保留 deck_id 供现有运行入口使用。

### 第一关独立事件库与事件资源

- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_lib.tres` — 第一关独立 `EventLib`，只收录本关六个事件模板。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/events/ribwood_marrow_lamp_treasure_event.tres` — 熄灭的骨髓灯。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/events/ribwood_marrow_rat_event.tres` — 啮髓鼠群。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/events/ribwood_broken_banner_shop_event.tres` — 断旗巡礼营。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/events/ribwood_fallen_rib_wolf_event.tres` — 腐肋幼狼。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/events/ribwood_bone_stitcher_treasure_event.tres` — 缝骨者的祭坛。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/events/ribwood_white_horn_hart_boss_event.tres` — 抱肋者·白角守墓鹿。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_content/ribwood_marrow_lamp_treasure_content.tres` — 三张首宝藏奖励卡。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_content/ribwood_broken_banner_shop_content.tres` — 五张商品和价格。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_content/ribwood_marrow_rat_content.tres` — 啮髓鼠群事件内容。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_content/ribwood_fallen_rib_wolf_content.tres` — 腐肋幼狼事件内容。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_content/ribwood_bone_stitcher_treasure_content.tres` — 三张第二宝藏奖励卡。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_content/ribwood_white_horn_hart_boss_content.tres` — Boss 行动和三张 Boss 奖励卡。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/mobs/ribwood_marrow_rat_echo.tres` — 4 HP、1 伤害、最多 2 层强化、8 金币和基础奖励卡池。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/mobs/ribwood_fallen_rib_wolf_echo.tres` — 10 HP、2 伤害 / 2 防御行动循环、最多 2 层强化、12 金币和攻击或防御奖励卡池。
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/mobs/ribwood_white_horn_hart_boss.tres` — 26 HP、3/3/4 行动循环、最多 3 层强化、20 金币和三张 Boss 奖励卡。

### 测试

- Create: `D:/project/MonoCard/mono-card/tests/ribwood_card_rules_test.gd` — 新规则的正向、边界和空上下文测试。
- Create: `D:/project/MonoCard/mono-card/tests/ribwood_card_data_test.gd` — 资源数值、标签、描述和初始牌组组成测试。
- Create: `D:/project/MonoCard/mono-card/tests/ribwood_echo_data_test.gd` — 三类残响 HP、行动循环、奖励和强化上限测试。
- Modify: `D:/project/MonoCard/mono-card/tests/combatv2_service_test.gd` — 增加完整三牌链击杀、RETREAT 后保留生命并强化的覆盖；保留原有旧规则测试。

## 实施任务

### Task 1: 锁定资源 ID、标签和规则接口

**Files:**
- No production code change required in `D:/project/MonoCard/mono-card/scripts/card/card_data.gd`; only add the resource contract test.
- Test: `D:/project/MonoCard/mono-card/tests/ribwood_card_data_test.gd`

**Interfaces:**
- Consumes: 现有 `CardData.CardTag`、`CardData.CardType` 和 `StartingDeckData`。
- Produces: 一份由资源文件直接使用的标签约定：`WEAPON` 用于武器前牌检查，`DEFENSE` 用于防御前牌检查，`HEAL` 用于治疗牌识别，`ROOT` 仅用于牌根。

- [x] **Step 1: 写资源契约测试**：读取五张预期初始资源路径，断言名称、类型、基础伤害/护甲/治疗、关键标签和规则数量。
- [x] **Step 2: 运行测试确认失败**：

```powershell
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/ribwood_card_data_test.gd
```

Expected: FAIL，因为肋骨林地资源尚未创建。

- [x] **Step 3: 确认不扩展 `CardData` 字段**：所有第一关效果都能由现有数值字段、标签和 `CardRule` 表达；不要添加通用脚本字符串或 UI 专用字段。
- [x] **Step 4: 保持旧规则测试兼容**：不删除旧的倍增规则资源和其测试依赖，正式卡牌只引用新的加法规则。
- [x] **Step 5: 运行资源契约测试**：测试在后续资源任务完成后转为 PASS。

### Task 2: 实现四个可复用的加法规则

**Files:**
- Create: `D:/project/MonoCard/mono-card/scripts/combatv2/card/rules/previous_weapon_damage_bonus_rule.gd`
- Create: `D:/project/MonoCard/mono-card/scripts/combatv2/card/rules/previous_defense_damage_bonus_rule.gd`
- Create: `D:/project/MonoCard/mono-card/scripts/combatv2/card/rules/previous_defense_heal_bonus_rule.gd`
- Create: `D:/project/MonoCard/mono-card/scripts/combatv2/card/rules/last_card_defense_bonus_rule.gd`
- Test: `D:/project/MonoCard/mono-card/tests/ribwood_card_rules_test.gd`

**Interfaces:**
- Consumes: `CardResolutionContext.get_previous_resolved_card()`, `CardResolutionContext.is_last_card()`, `CardResolutionDraft.damage`, `CardResolutionDraft.heal` 和 `CardResolutionDraft.defense`。
- Produces: 四个 `CardRule.execute(context, draft) -> CardResolutionDraft` 实现；规则都必须原地修改传入 draft 后返回同一个 draft。

- [x] **Step 1: 写失败测试**：覆盖上一张是武器时 `damage += 1`、上一张不是武器时不变、上一张提供防御时 `damage += 2`、上一张提供防御时 `heal += 1`、末位时 `defense += 1/2`，以及 null context/draft 不崩溃。
- [x] **Step 2: 运行单文件测试确认失败**：

```powershell
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/ribwood_card_rules_test.gd
```

Expected: FAIL，因为四个规则脚本不存在。

- [x] **Step 3: 实现最小规则逻辑**：只检查紧邻上一张牌；不扫描整条牌链，不叠加重复条件，不读写玩家或残响运行时状态。
- [x] **Step 4: 为每个规则补充 `description` 默认文案**：文案必须与数值一致，例如“若上一张牌是武器，伤害 +1”。
- [x] **Step 5: 运行单文件规则测试**：Expected: PASS。
- [x] **Step 6: 运行旧战斗规则测试**：

```powershell
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/combatv2_card_rule_test.gd
```

Expected: PASS，证明新规则没有破坏旧规则类。

### Task 3: 创建第一关卡牌资源

**Files:**
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_guardian_root.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_rib_blade.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_old_tinder.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_folded_rib_shield.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_warm_marrow_flask.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_rib_nail.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_shield_fragment.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_amber_marrow_bottle.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_bone_armor_round_shield.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_ember_blade.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_warmth_charm.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_scabbed_potion.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_grave_beetle.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_bone_stitching_needle.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_old_chest_cloak.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_last_resort_strike.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_white_horn_relic.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_sternum_plate.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/cards/ribwood_guardian_ember.tres`
- Modify: `D:/project/MonoCard/mono-card/data/starting_decks/revival_starting_deck.tres`
- Test: `D:/project/MonoCard/mono-card/tests/ribwood_card_data_test.gd`

**Interfaces:**
- Consumes: Task 2 rule scripts and existing `CardData` resource serialization.
- Produces: 19 loadable `CardData` resources with exact design values and an initial deck containing exactly the five initial cards.

- [x] **Step 1: 为每张卡牌建立资源契约表**：填写唯一 `card_id`、英文资源文件名、中文显示名、标签、基础数值、描述、稀有度和规则资源引用。
- [x] **Step 2: 创建五张初始卡**：
  - `守护之根`: ROOT，0/2/0。
  - `肋骨短刃`: 2/0/0，WEAPON。
  - `旧火绒`: 1/0/0，ITEM，引用上一张武器伤害 +1 规则。
  - `折叠肋盾`: 0/2/0，DEFENSE，引用末位 +2 防御规则。
  - `温髓水囊`: 0/0/2，HEAL。
- [x] **Step 3: 创建宝藏卡**：肋骨穿钉 3 伤害、肋盾残片 3 防御、琥珀骨髓瓶 3 治疗。
- [x] **Step 4: 创建商店卡**：骨甲圆盾 3 防御、余烬短刃 3 伤害、余温护符 1 防御 + 2 治疗、结痂药瓶 3 治疗、守墓甲虫 2 伤害 + 3 防御。
- [x] **Step 5: 创建第二宝藏和 Boss 奖励卡**：按设计文档中的 1/0/0 +2、0/2/2、4/0/0 以及 2/2/0、0/4/0、1/0/4 配置。
- [x] **Step 6: 更新 `revival_starting_deck.tres`**：只替换五个 starter card 外部资源引用，保留 `deck_id = "revival"`，避免影响根选择入口。
- [x] **Step 7: 运行资源契约与启动牌组测试**：

```powershell
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/ribwood_card_data_test.gd
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/starting_deck_data_test.gd
```

Expected: PASS；不得出现资源脚本解析错误或失效外部引用。

### Task 4: 接入宝藏和商店资源池

**Files:**
- Modify: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_content/ribwood_marrow_lamp_treasure_content.tres`
- Modify: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_content/ribwood_broken_banner_shop_content.tres`
- Test: `D:/project/MonoCard/mono-card/tests/ribwood_card_data_test.gd`
- Test: `D:/project/MonoCard/mono-card/tests/event_runtime_test.gd`

**Interfaces:**
- Consumes: Task 3 的 `CardData` 资源。
- Produces: 宝藏池包含三张首宝藏卡；商店池包含五件商品，价格为 8、10、10、8、14；运行时仍由现有 resolver 负责抽取和购买。

- [x] **Step 1: 为宝藏池写失败断言**：加载 `ribwood_marrow_lamp_treasure_content.tres`，断言卡池名称集合等于肋骨穿钉、肋盾残片、琥珀骨髓瓶，并保持现有金币奖励行为。
- [x] **Step 2: 为商店池写失败断言**：加载 `ribwood_broken_banner_shop_content.tres`，断言五件商品及价格完全匹配设计文档。
- [x] **Step 3: 替换事件资源外部引用**：不修改宝藏和商店 resolver 的随机/购买算法，不引入新的事件类型。
- [x] **Step 4: 运行事件运行时测试**：

```powershell
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/event_runtime_test.gd
```

Expected: PASS，并确认购买商品扣除金币、宝藏领取卡牌和金币的现有行为不变。

### Task 5: 创建第一关独立 EventLib 与六个事件模板

**Files:**
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_lib.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/events/*.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_content/*.tres`
- Test: `D:/project/MonoCard/mono-card/tests/ribwood_event_lib_test.gd`

**Interfaces:**
- Consumes: Task 3 的卡牌资源；Task 6 的残响资源；现有 EventData、EventEntry、EventLib 和各类 EventContent。
- Produces: 仅包含肋骨林地六个事件的关卡专属事件库；旧 `data/event/event_lib.tres` 保持不变。

- [x] **Step 1: 为事件库写契约测试**：断言事件库路径存在、事件 ID 集合正好包含六个第一关事件，普通残响池不含 Boss，宝藏与商店内容引用均来自 `data/levels/ribwood/`。
- [x] **Step 2: 创建六个事件模板和六份内容资源**：所有关卡特有配置放在 `data/levels/ribwood/`，通用脚本仍复用 `scripts/game/event/`。
- [x] **Step 3: 配置 EventEntry**：每个事件默认生成一次，确保首图可生成完整结构；动态信仰残响只能从普通 MONSTER 模板中筛选。
- [x] **Step 4: 运行事件库契约测试**。

```powershell
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/ribwood_event_lib_test.gd
```

Expected: PASS。

### Task 6: 创建第一关残响与行动资源

**Files:**
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/mobs/ribwood_marrow_rat_echo.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/mobs/ribwood_fallen_rib_wolf_echo.tres`
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/mobs/ribwood_white_horn_hart_boss.tres`
- Modify: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_content/ribwood_marrow_rat_content.tres`
- Modify: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_content/ribwood_fallen_rib_wolf_content.tres`
- Modify: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_content/ribwood_white_horn_hart_boss_content.tres`
- Test: `D:/project/MonoCard/mono-card/tests/ribwood_echo_data_test.gd`

**Interfaces:**
- Consumes: Task 3 的奖励卡资源和现有 `MobData`、`MobAction` 序列化结构。
- Produces: 三个可实例化的 `MobData`；普通残响 `max_enhancement_stacks = 2`，Boss 为 3；行动顺序稳定且不引入特殊状态。

- [x] **Step 1: 写残响资源失败测试**：分别断言 HP、基础防御、行动数量、行动数值、金币奖励、强化上限和 Boss 奖励池。
- [x] **Step 2: 创建啮髓鼠群资源**：4 HP，行动列表仅包含 1 点 ATTACK，奖励 8 金币，最多 2 层强化。
- [x] **Step 3: 创建腐肋幼狼资源**：10 HP，行动列表为 ATTACK 2 → DEFEND 2，奖励 12 金币，最多 2 层强化。
- [x] **Step 4: 创建抱肋者·白角守墓鹿资源**：26 HP，行动列表为 ATTACK 3 → DEFEND 3 → ATTACK 4，奖励 20 金币，最多 3 层强化，奖励池引用三张 Boss 奖励卡。
- [x] **Step 5: 修改第一关事件内容资源引用**：让现有地图事件继续使用既有事件类型和流程，只更换 MobData。
- [x] **Step 6: 运行残响数据测试**：

```powershell
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/ribwood_echo_data_test.gd
```

Expected: PASS。

### Task 7: 覆盖完整牌链与 RETREAT 平衡行为

**Files:**
- Modify: `D:/project/MonoCard/mono-card/tests/combatv2_service_test.gd`
- Test: `D:/project/MonoCard/mono-card/tests/ribwood_card_rules_test.gd`

**Interfaces:**
- Consumes: Task 2 的规则脚本、Task 3 的 CardData 资源、Task 6 的 MobData。
- Produces: 可重复验证的战斗平衡样例，不修改 `RETREAT` 枚举，不改变现有自动回手和手动拆链信号的边界。

- [x] **Step 1: 增加“根牌 + 两牌击杀”测试**：加载三张实际肋骨林地卡牌，创建 4 HP 啮髓鼠群，断言结果为 VICTORY、怪物 HP 为 0，且残响没有行动步骤发生在致死牌之后。
- [x] **Step 2: 增加无配合链测试**：使用根牌、肋骨短刃和温髓水囊，断言啮髓鼠群未被击杀时返回 RETREAT，而不是 VICTORY。
- [x] **Step 3: 增加 RETREAT 状态测试**：断言残响已损失的 HP 保留、临时防御归零、行动索引保留、强化层数增加 1，且现有 GameManager 流程只返还最后一张非根牌。
- [x] **Step 4: 增加强化上限测试**：普通残响连续 RETREAT 后不超过 2 层，Boss 不超过 3 层；每层行动值按 +1 应用。
- [x] **Step 5: 运行战斗测试**：

```powershell
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/combatv2_service_test.gd
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/ribwood_card_rules_test.gd
```

Expected: PASS。

### Task 8: 全局资源、运行入口和回归验证

**Files:**
- Create: `D:/project/MonoCard/mono-card/data/levels/ribwood/event_lib.tres` — 第一关独立事件库，仅收录本关六类事件。`D:/project/MonoCard/mono-card/data/event/event_lib.tres` 保留为旧兼容资源，不再作为第一关默认库。
- Modify: `D:/project/MonoCard/mono-card/scenes/game/game_manager.tscn` — 将 `event_lib` 外部引用改为 `res://data/levels/ribwood/event_lib.tres`。
- Modify: `D:/project/MonoCard/mono-card/tests/game_manager_run_setup_test.gd`（仅当默认牌组或默认事件断言需要更新时）
- Test: `D:/project/MonoCard/mono-card/tests/ribwood_card_data_test.gd`
- Test: `D:/project/MonoCard/mono-card/tests/ribwood_echo_data_test.gd`
- Test: `D:/project/MonoCard/mono-card/tests/combatv2_service_test.gd`
- Test: `D:/project/MonoCard/mono-card/tests/event_runtime_test.gd`
- Test: `D:/project/MonoCard/mono-card/tests/game_manager_faith_test.gd`
- Test: `D:/project/MonoCard/mono-card/tests/game_manager_combat_routing_test.gd`
- Test: `D:/project/MonoCard/mono-card/tests/game_manager_run_setup_test.gd`

**Interfaces:**
- Consumes: Tasks 1–6 的资源和规则。
- Produces: 默认运行入口加载肋骨林地初始牌组和第一关事件数据，同时不回归现有 RETREAT、信仰值、事件路由和资源加载行为。

- [x] **Step 1: 检查默认事件池**：确认动态生成普通残响时仍能从 `EventLib.get_templates_of_type(MONSTER)` 找到啮髓鼠群或腐肋幼狼模板，不选中 Boss。
- [x] **Step 2: 运行全部相关 headless 测试**：

```powershell
$tests = @(
  'tests/ribwood_card_rules_test.gd',
  'tests/ribwood_card_data_test.gd',
  'tests/ribwood_echo_data_test.gd',
  'tests/combatv2_service_test.gd',
  'tests/event_runtime_test.gd',
  'tests/game_manager_faith_test.gd',
  'tests/game_manager_combat_routing_test.gd',
  'tests/game_manager_run_setup_test.gd'
)
foreach ($test in $tests) {
  godot --headless --path D:/project/MonoCard/mono-card --script "res://$test"
  if ($LASTEXITCODE -ne 0) { throw "FAILED: $test" }
}
```

Expected: 所有测试退出码为 0；`game_manager_run_setup_test.gd` 可以继续输出故意覆盖的 invalid StartingDeckData 错误，但不能导致非零退出码。

- [x] **Step 3: 做资源扫描**：检查所有新 `.tres` 外部引用存在、CardRule 脚本可解析、没有重复资源 ID 引用导致运行时加载失败。
- [x] **Step 4: 运行格式检查**：

```powershell
git diff --check -- data/levels/ribwood data/starting_decks scripts/combatv2/card/rules tests scenes/game/game_manager.tscn
```

Expected: 无空白错误。

- [x] **Step 5: 精确检查工作区变更**：只查看本计划拥有的文件，不触碰用户已有 UI、FaithService、DragLayer 和 GameManager 未相关改动。

## 完成定义

实现完成必须同时满足：

1. 新卡牌资源可在 Godot headless 下全部加载。
2. 初始牌组正好包含守护之根、肋骨短刃、旧火绒、折叠肋盾、温髓水囊。
3. 守护之根 → 肋骨短刃 → 旧火绒能击杀 4 HP 啮髓鼠群。
4. 腐肋幼狼和白角守墓鹿行动循环与设计稿一致。
5. 所有牌链条件都为固定加法效果，不使用第一关禁用的复杂机制。
6. RETREAT 和信仰值已有测试全部继续通过。
7. 不新增额外战斗 Outcome，不使用 Curse/Tide 作为代码命名。
8. 相关资源和测试通过后，再由执行代理按任务顺序实现并进行代码审查。
