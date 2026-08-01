# 事件分类目录与运行时状态重构设计

**日期：** 2026-08-01  
**状态：** 已确认，等待用户评审  
**范围：** 整理 `res://scripts/game/event/`，将商店、宝藏、怪物遭遇和 Boss 的配置、运行时状态与结算职责分离。

## 1. 背景与问题

当前事件目录中，`EventInstance` 同时持有：

- 通用事件生命周期数据：模板、棋盘位置、揭示状态、解决状态；
- 商店专属状态：商品售罄标记；
- 宝藏专属状态：奖励选项缓存、已领取选项索引。

这种设计使通用实例随事件类型增加而不断增加无关字段。后续增加休整、剧情、陷阱等事件时，会继续扩大该问题，也会使通用解析器累积按事件类型分支的逻辑。

此外，事件完成必须以 `EventInstance.is_resolved` 为唯一真相。`resolve()` 必须同时将事件置为已揭示和已解决，防止已完成事件被再次触发或重复领取奖励。

## 2. 目标与非目标

### 目标

1. 建立四类首版事件：商店、宝藏、怪物遭遇、Boss。
2. 将所有事件共有的生命周期与类型专属运行时状态分离。
3. 让新增事件类型时不需要向 `EventInstance` 添加专属字段。
4. 让商店、宝藏、遭遇和 Boss 分别拥有清晰的结算入口。
5. Boss 首版复用怪物遭遇的战斗流程，同时保留独立的配置与状态扩展空间。
6. 保持现有棋盘生成、卡牌重叠触发、交互锁定和商店/宝藏奖励行为的对外结果不变。

### 非目标

- 不在本次重构中实现商店或宝藏的正式 UI 面板。
- 不在本次重构中实现多怪物、Boss 多阶段或特殊胜负条件。
- 不迁移整个战斗域；`MobData`、`MobInstance`、`MobAction` 先保留在事件遭遇子域。
- 不改变事件触发条件：事件仍在新卡牌合法落位并重叠事件圈后触发。

## 3. 事件分类

| 分类 | 职责 | 首版运行时状态 |
| --- | --- | --- |
| 商店事件 | 展示静态商品、检查金币和手牌容量、完成购买 | 各商品售罄标记 |
| 宝藏事件 | 首次生成并缓存奖励选项、领取唯一奖励 | 奖励选项、已选索引 |
| 怪物遭遇事件 | 创建普通怪物实例并调用战斗服务 | 当前怪物、战斗是否开始、战斗结果/日志 |
| Boss 事件 | 使用遭遇战流程，但携带 Boss 专属配置 | 复用遭遇状态；未来可增加阶段和专属规则状态 |

Boss 不复制普通怪物的战斗流程。普通怪物与 Boss 均使用遭遇层提供的创建怪物与调用 `CombatService` 的能力；差异通过各自内容配置和未来的 Boss 扩展表达。

## 4. 推荐目录

```text
res://scripts/game/event/
├── core/
│   ├── event_data.gd
│   ├── event_content.gd
│   ├── event_instance.gd
│   ├── event_runtime_state.gd
│   ├── event_entry.gd
│   ├── event_lib.gd
│   ├── event_placement_service.gd
│   └── event_resolution_result.gd
│
├── shop/
│   ├── shop_event_content.gd
│   ├── shop_runtime_state.gd
│   ├── shop_item_data.gd
│   └── shop_event_resolver.gd
│
├── treasure/
│   ├── treasure_event_content.gd
│   ├── treasure_runtime_state.gd
│   ├── treasure_reward_option.gd
│   └── treasure_event_resolver.gd
│
└── encounter/
    ├── encounter_event_content.gd
    ├── monster_event_content.gd
    ├── boss_event_content.gd
    ├── encounter_runtime_state.gd
    ├── encounter_event_resolver.gd
    ├── mob_data.gd
    ├── mob_instance.gd
    └── mob_action.gd
```

目录命名使用单数领域名。每种事件类型的静态配置、可变状态和行为放在同一子目录中；`core/` 仅容纳所有事件类型都依赖的抽象和基础服务。

## 5. 类型协议与职责边界

### 5.1 EventContent

新增 `EventContent`，继承 `Resource`，作为全部事件内容配置的基类。它至少提供：

```gdscript
func create_runtime_state() -> EventRuntimeState:
    return EventRuntimeState.new()
```

`ShopEventContent`、`TreasureEventContent`、`MonsterEventContent` 与 `BossEventContent` 分别继承该基类，并返回自身对应的运行时状态。

`EventData.content` 改为 `EventContent` 类型。`EventData.EventType` 继续保留，供事件生成、图标、UI 分类和分发使用；内容类型与 `EventType` 必须匹配，解析器不匹配时返回 `INVALID_EVENT`，不得崩溃或写入状态。

### 5.2 EventInstance

`EventInstance` 只拥有所有事件共有的数据：

```gdscript
var template: EventData
var origin: Vector2i
var is_revealed := false
var is_resolved := false
var runtime_state: EventRuntimeState
```

创建实例时，`EventData.create_instance()` 调用内容的 `create_runtime_state()`。若没有内容配置，实例持有空的基础 `EventRuntimeState`，但任何类型专属结算都会返回 `INVALID_EVENT`。

`EventInstance` 不得再持有如下字段或未来任何等价的事件专属字段：

- `shop_sold_flags`；
- `treasure_options`；
- `selected_treasure_option`；
- 怪物当前生命、动作索引或战斗日志；
- Boss 阶段、怒气或特殊规则标记。

完成事件统一调用：

```gdscript
func resolve() -> void:
    is_revealed = true
    is_resolved = true
```

### 5.3 EventRuntimeState

`EventRuntimeState` 继承 `RefCounted`，表示单次事件实例的可变数据。它不持有静态资源配置，也不直接负责 UI 或棋盘操作。

具体状态：

- `ShopRuntimeState`：`sold_flags: Array[bool]`；
- `TreasureRuntimeState`：`options: Array[TreasureRewardOption]`、`selected_option_index := -1`；
- `EncounterRuntimeState`：为当前怪物实例、战斗开始标记和战斗结果预留字段。首版仅实现当前重构必需的最小字段，不预建 Boss 阶段系统。

### 5.4 各类型 Resolver

当前 `EventRewardResolver` 是商店与宝藏的共同实现。重构后按事件类型拆分：

- `ShopEventResolver.purchase_item(instance, item_index, player, hand_has_capacity)`；
- `TreasureEventResolver.ensure_options(instance, rng)`；
- `TreasureEventResolver.claim_reward(instance, option_index, player, hand_has_capacity, rng)`；
- `EncounterEventResolver` 作为怪物和 Boss 进入战斗服务的统一桥接层。

商店与宝藏 Resolver 只接受自己支持的 `Content + RuntimeState` 组合。检测到实例为空、内容类型不符、状态类型不符、已解决或索引非法时，返回 `EventResolutionResult` 的明确失败原因，并且不修改金币、奖励缓存、售罄状态或解决状态。遭遇 Resolver 首版只负责验证并创建怪物实例；它对非法遭遇返回 `null`，不引入尚未设计的战斗结果包装类型。

`EventResolutionResult` 留在 `core/`，作为各类型结算的通用返回对象。后续若战斗返回的信息明显超出它的能力，再新增战斗专属结果，而不是向奖励结果对象堆积战斗字段。

## 6. 运行时流程

```text
EventData.create_instance()
  -> content.create_runtime_state()
  -> EventInstance(runtime_state)

新卡合法落位并重叠未解决事件
  -> Board.event_triggered(instance)
  -> GameManager 按 EventType 打开事件入口
  -> 对应 Resolver 读取 Content + RuntimeState
  -> 返回 EventResolutionResult 或进入 CombatService
  -> 成功完成的单次事件调用 instance.resolve()
```

商店首次购买后仍可保持事件未解决，以支持购买多个商品；商店何时结束由后续 UI 的离开/关闭规则决定。宝藏在领取一个奖励后立即解决。遭遇和 Boss 在战斗得到最终结果后决定是否解决，并遵循战斗系统既有失败惩罚规则。

## 7. 现有文件迁移映射

| 当前文件 | 目标文件 | 处理 |
| --- | --- | --- |
| `event_zone.gd` | `core/event_instance.gd` | 重命名，移除类型专属字段，持有 `runtime_state`，修复 `resolve()`。 |
| `event_data.gd` | `core/event_data.gd` | 使 `content` 使用 `EventContent`，在创建实例时生成状态。 |
| 新增 | `core/event_content.gd` | 提供内容配置基类和状态创建钩子。 |
| 新增 | `core/event_runtime_state.gd` | 提供运行时状态基类。 |
| `event_entry.gd` | `core/event_entry.gd` | 仅移动。 |
| `event_lib.gd` | `core/event_lib.gd` | 仅更新依赖路径。 |
| `event_placement_service.gd` | `core/event_placement_service.gd` | 仅更新依赖路径。 |
| `event_resolution_result.gd` | `core/event_resolution_result.gd` | 仅更新依赖路径。 |
| `event_shop_content.gd` | `shop/shop_event_content.gd` | 继承 `EventContent`，创建 `ShopRuntimeState`。 |
| `shop_item_data.gd` | `shop/shop_item_data.gd` | 仅移动。 |
| 新增 | `shop/shop_runtime_state.gd` | 承接商品售罄标记。 |
| 商店逻辑（原 `event_reward_resolver.gd`） | `shop/shop_event_resolver.gd` | 迁移商店购买逻辑。 |
| `event_treasure_content.gd` | `treasure/treasure_event_content.gd` | 继承 `EventContent`，创建 `TreasureRuntimeState`。 |
| `treasure_reward_option.gd` | `treasure/treasure_reward_option.gd` | 仅移动。 |
| 新增 | `treasure/treasure_runtime_state.gd` | 承接选项缓存与已领取索引。 |
| 宝藏逻辑（原 `event_reward_resolver.gd`） | `treasure/treasure_event_resolver.gd` | 迁移宝藏生成/领取逻辑。 |
| `event_monster_content.gd` | `encounter/monster_event_content.gd` | 继承遭遇内容基类。 |
| 新增 | `encounter/encounter_event_content.gd` | 表达普通怪物与 Boss 共享的遭遇配置。 |
| 新增 | `encounter/boss_event_content.gd` | 承载 Boss 独有静态配置，不复制战斗流程。 |
| 新增 | `encounter/encounter_runtime_state.gd` | 承接战斗过程状态。 |
| `mob_data.gd`、`mob_instance.gd`、`mob_action.gd` | `encounter/` 同名文件 | 仅移动并更新引用。 |
| `event_reward_resolver.gd` | 删除 | 先拆分逻辑并更新调用方后删除。 |

所有迁移必须同步更新 `preload`、场景脚本、测试脚本和 `.uid` 资源引用。不得为了保留旧路径创建双份逻辑；如有短期兼容层，必须是单向薄转发，且在同一重构中清除。

## 8. 兼容与数据策略

- 已保存的 `.tres` 资源必须重新解析；类名保持稳定时优先保持资源字段兼容。
- 文件移动后必须让 Godot 重新生成或校正 `.uid` 引用，不能手工复制造成重复 UID。
- `EventData.EventType` 枚举顺序不改变，避免现有资源中整数值被解释为其他类型。
- 现有商店和宝藏配置字段保持原语义：商品表、卡牌池、金币区间不改变。
- 首版不为不存在的 `BossEventContent` 制作实际 `.tres` 配置；仅建立可扩展的代码结构。

## 9. 验证与回归用例

### 9.1 结构与创建

1. **商店实例创建**
   - 输入：`EventData` 类型为 `SHOP`，内容为 `ShopEventContent`。
   - 预期：实例持有 `ShopRuntimeState`；售罄数组初始为空；`EventInstance` 无商店专属字段。

2. **宝藏实例创建**
   - 输入：`EventData` 类型为 `TREASURE`，内容为 `TreasureEventContent`。
   - 预期：实例持有 `TreasureRuntimeState`；选项数组为空，已选索引为 `-1`。

3. **类型或状态不匹配**
   - 输入：商店内容配合宝藏运行时状态，或 `SHOP` 模板使用宝藏内容。
   - 预期：对应 Resolver 返回 `INVALID_EVENT`；玩家金币、状态缓存和事件完成状态均不变化。

### 9.2 商店

1. **购买成功**
   - 输入：玩家金币充足、手牌有容量、目标商品未售罄。
   - 预期步骤：验证实例/内容/状态 → 验证索引 → 验证未解决 → 验证未售罄 → 验证手牌容量 → 验证金币 → 扣金币 → 对应 `sold_flags` 置真 → 返回成功与奖励卡；事件保持未解决。

2. **购买失败**
   - 输入：商品已售罄、金币不足、手牌已满、索引非法或事件已解决中的任一情况。
   - 预期：返回对应失败枚举；金币、售罄标记、奖励和事件状态均不改变。

### 9.3 宝藏

1. **选项缓存与领取普通卡**
   - 输入：至少两张不同卡牌的奖励池、确定性随机数、手牌有容量。
   - 预期步骤：第一次读取生成两张不同普通卡和一项金币，并写入 `TreasureRuntimeState.options`；领取卡牌时记录索引、返回卡牌奖励、调用 `resolve()`；随后任何领取请求返回 `ALREADY_RESOLVED`。

2. **手牌满时领取金币**
   - 输入：手牌无容量，选择金币选项。
   - 预期步骤：允许金币选项 → 增加金币 → 返回 `granted_card == null` 和正数 `gold_delta` → 调用 `resolve()`。

3. **手牌满时领取普通卡**
   - 输入：手牌无容量，选择普通卡选项。
   - 预期：返回 `HAND_FULL`；选项缓存、已选索引、金币和 `is_resolved` 均不改变。

### 9.4 生命周期与事件触发

1. **resolve 的完成语义**
   - 输入：任意未解决事件调用 `resolve()`。
   - 预期：`is_revealed == true` 且 `is_resolved == true`。

2. **已完成事件不能再次触发**
   - 输入：棋盘上已解决事件与新落位卡牌重叠。
   - 预期：`Board.event_triggered` 不发出该实例；不打开事件入口。

3. **现有触发保护不回归**
   - 输入：合法落牌、失败落牌、事件间隔生成、异常同时命中多个未解决事件。
   - 预期：保持现有 `event_trigger_test.gd` 的通过条件和防御性错误日志行为。

### 9.5 运行命令

在项目根目录执行：

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_runtime_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_trigger_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/combatv2_card_rule_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/combatv2_service_test.gd
```

`event_trigger_test.gd` 的多事件重叠与拖拽恢复失败防御日志为刻意构造的测试路径；只要进程退出码为 `0`，即视为通过。

## 10. 实施边界

本设计只整理事件域。若遭遇接入实际战斗后发现 `MobData` 已被多个非事件系统依赖，再单独设计将怪物模型迁移至 `res://scripts/combat/monster/` 的工作；该迁移不隐含在本次目录重构中。
