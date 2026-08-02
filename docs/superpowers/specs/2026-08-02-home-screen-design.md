# 首页与新局准备界面设计

- **日期：** 2026-08-02
- **状态：** 已确认，等待文档复核
- **范围：** 游戏启动后的初始牌组选择首页，以及从首页创建一局探索的流程

## 目标

游戏启动后先展示首页，而不是立即进入棋盘。玩家在首页选择一套包含牌根的初始牌组，查看其牌根、玩法标签和起始卡构成，然后点击“开始探索”进入既有森林棋盘流程。

首版优先支持一套可用的“复苏套组”，但 UI、数据和流程必须能自然扩展到多套牌组与未来解锁条件。

## 非目标

首版不包含：

- 继续游戏、存档选择、图鉴、成就、牌库或营地大厅；
- 独立的“仅选择牌根”流程；
- 在首页编辑、替换、升级或购买初始卡牌；
- 在首页结算战斗、事件、奖励或怪物逻辑；
- 为首页复制一套独立的卡牌视觉组件；
- 完整的本局结束页或返回首页交互。仅预留返回接口。

## 核心体验

首页采用“图鉴式牌组选择”布局：左侧提供牌组列表，右侧展示当前选择的牌根和套组说明。玩家只需完成一个明确决策：选择自己希望围绕哪种牌根与卡牌协同进入森林。

```text
启动游戏
→ 首页选择初始牌组
→ 查看牌根、玩法说明与起始卡
→ 点击“开始探索”
→ 进入当前森林棋盘、手牌与事件流程
```

## 场景职责与页面流程

采用 `Main` 管理页面切换、`GameManager` 管理单局探索的结构。不要新增全局运行状态单例，也不要把首页选择结果写回静态 `PlayerData` 资源。

```text
Main
├── BackgroundLayer                 # 始终填充窗口的背景
├── HomeScreen                      # 选择牌组并发出开始请求
└── GameManager（按需实例化）        # 一次探索的棋盘、手牌、事件和战斗
```

### 首页到探索的流程

1. `HomeScreen` 加载一组 `StartingDeckData` 预设，默认选择第一个已解锁且有效的预设；
2. 玩家在左侧选择一个已解锁预设，首页刷新右侧信息；
3. 玩家点击“开始探索”后，`HomeScreen` 只发射 `start_requested(preset)` 信号；
4. `Main` 接收该预设、销毁首页实例，并实例化 `GameManager`；
5. `Main` 必须在 `GameManager` 开始初始化本局前注入同一个预设；
6. `GameManager` 根据该预设创建新的运行时玩家和卡牌实例，再初始化棋盘、手牌和事件；
7. 后续本局结束时，`GameManager` 可发射 `run_finished`，由 `Main` 清理本局并重新实例化首页。首版允许暂不实现完整返回交互，但接口边界应保留。

`HomeScreen` 不直接加载场景、不实例化卡牌到游戏区域、不创建战斗服务；`GameManager` 不读取首页 UI 节点。

## 初始牌组数据

新增 `StartingDeckData` Resource，用于描述“玩家带什么进入本局”。它不包含战斗过程、事件、商店或奖励内容。

建议字段：

| 字段 | 语义 |
|---|---|
| `deck_id` | 稳定唯一标识，供未来存档、统计和解锁使用。 |
| `display_name` | 首页显示的套组名称。 |
| `description` | 套组整体玩法说明。 |
| `root_card` | 必填且唯一的牌根 `CardData`。 |
| `starter_cards` | 必填数组；除牌根外的固定起始普通卡，可有重复项。 |
| `playstyle_tags` | 首页展示用标签，例如“治疗 / 延续 / 武器连锁”。 |
| `is_unlocked` | 是否可开始。首版所有正式预设可设为 `true`。 |

### 固定规则

- `root_card` 必须存在，且 `card_type` 必须为 `ROOT`；
- `starter_cards` 不包含 `root_card`，因此本局起始卡总数恒为 `1 + starter_cards.size()`；
- 每局开始时，`GameManager` 为牌根和每张起始卡创建新的 `CardInstance`；
- `.tres` 中的 `CardData` 与 `StartingDeckData` 仅作为静态定义，运行时绝不修改；
- 允许 `starter_cards` 中存在相同 `CardData` 的多次引用，以表达同名卡的起始副本；
- 既有 `CardLibrary` 继续承担全局卡牌索引、商店和奖励候选池职责，不再作为正式初始牌组的随机生成来源；
- 既有 `CardManager.get_init_cards()` 需要被替换或改造成“由 `StartingDeckData` 创建起始 `CardInstance`”的明确接口，禁止在正式开局中隐藏随机抽卡规则。

### 牌根与战斗服务

首页只传递所选套组。牌根决定的全局规则和不同 `CombatService` 的选择仍属于本局玩法初始化：`GameManager` 在读取选中预设的 `root_card` 后，创建默认或该牌根专用的战斗服务。

这样首页无需了解根牌的战斗实现，且未来增加新牌根时只需新增预设和相应战斗服务，不需要修改首页的选择逻辑。

## 首页场景布局

首页使用独立的全屏 `Control` 场景，不放入 `GameplayCanvas`。玩法棋盘继续遵循 1920×1080 等比画布；首页则以普通 UI 容器适应窗口大小。

```text
HomeScreen (Control，全屏、鼠标输入入口)
└── SafeArea (MarginContainer，全屏，统一留白)
    └── Content (VBoxContainer，居中，最大宽度约 1500px)
        ├── Header (HBoxContainer)
        │   ├── TitleBlock (VBoxContainer)
        │   │   ├── LogoLabel：MONOCARD
        │   │   └── SubtitleLabel：选择初始牌组，开始新的森林探索
        │   └── UtilityBlock (HBoxContainer)
        │       ├── VersionLabel
        │       └── SettingsButton
        └── MainArea (HBoxContainer)
            ├── DeckListPanel (PanelContainer，约 32% 宽)
            │   └── VBoxContainer
            │       ├── SectionTitle：初始牌组
            │       └── DeckPresetList (ScrollContainer / VBoxContainer)
            │           └── DeckPresetEntry × N
            └── DeckDetailPanel (PanelContainer，约 68% 宽)
                └── VBoxContainer
                    ├── DetailHeader
                    │   ├── DeckNameLabel
                    │   └── TagsRow
                    ├── HeroArea (HBoxContainer)
                    │   ├── RootPreviewSlot
                    │   └── RootDescription
                    │       ├── RootNameLabel
                    │       ├── RootEffectLabel
                    │       └── DeckDescriptionLabel
                    ├── Divider
                    ├── StartingDeckSummary
                    │   ├── InitialCardCountLabel
                    │   └── StartingCardPreviewRow
                    └── Footer (HBoxContainer)
                        ├── UnlockHintLabel
                        └── StartExploreButton
```

### 页面信息与交互

#### 左侧牌组列表

每个 `DeckPresetEntry` 显示套组名称、牌根名称、简短玩法标签，以及选中态、锁定态或异常态。

- 点击已解锁预设：切换当前选择，并立即刷新右侧详情；
- 点击锁定预设：不更改当前选择，显示锁定提示；
- 配置无效预设：不显示在正常牌组列表中；开发环境输出带资源路径的错误；
- 即使首版只有一套复苏套组，也保留列表结构，避免以后多套组时重做首页。

#### 右侧详情

右侧展示当前已选预设的名称、玩法标签、牌根效果、套组说明、起始卡总数和起始普通卡预览。

`开始探索` 始终只针对当前有效且已解锁的预设：

- 无可用预设时按钮禁用，并显示“暂无可开始的牌组”；
- 第一次点击后进入 `is_starting` 状态，按钮禁用并改为“正在进入森林…”；
- `is_starting` 状态下忽略重复点击，防止创建多个 `GameManager`。

#### 设置与版本

首版保留设置按钮和版本号的位置。设置按钮可以暂时是无业务功能的占位入口；不得阻塞开始新局流程。

## 真实卡牌预览复用

牌根和起始卡预览必须复用现有 `CardEntity` 渲染，以保持插画、名称、标签、数值和描述与游戏内一致。

为此，`CardEntity` 需要具有明确的展示模式，而不是让首页预览沿用默认可交互状态：

```text
交互模式：可拖拽、可放大、响应棋盘相关输入。
展示模式：不可拖拽、不可放大、不进入 DragLayer、不接收鼠标事件。
```

首页预览规则：

1. 每次刷新预览时，为对应的 `CardData` 创建临时 `CardInstance`；
2. 临时实例仅供卡面绑定与渲染，不加入手牌、棋盘或牌链；
3. 实例化出的 `CardEntity` 显式进入展示模式；
4. 切换套组时清理旧预览节点，再创建新预览；
5. 预览卡保持实际的 1:2 卡面比例，不试图填充棋盘格或参与网格布局。

## 响应式与视觉层级

- `Main/BackgroundLayer` 继续独立于玩法画布，始终覆盖任意窗口；
- `HomeScreen` 以全屏 `Control` 布局，内容区居中且最大宽度约 1500px，超宽窗口不无限拉伸面板；
- 1920×1080 基准窗口使用左右双栏；
- 当 `Content` 可用宽度低于 980px 时，`MainArea` 切换为上下布局；若可用高度不足，`SafeArea` 作为唯一的纵向滚动容器；
- 进入探索后，首页实例已销毁；既有 `GameplayCanvas`、`EventModalLayer` 和背景填充机制继续工作；
- 视觉层级固定为：背景 → 首页或玩法内容 → 事件弹窗。

## 资源组织

```text
res://
├── scenes/
│   ├── main.tscn
│   └── home/
│       ├── home_screen.tscn
│       └── deck_preset_entry.tscn
├── scripts/
│   ├── home/
│   │   ├── home_screen.gd
│   │   └── deck_preset_entry.gd
│   └── run/
│       └── starting_deck_data.gd
└── data/
    └── starting_decks/
        └── revival_starting_deck.tres
```

## 错误处理与保护

### 资源校验

首页读取预设时执行轻量校验：

1. `deck_id` 和 `display_name` 非空；
2. `root_card` 非空且为 `ROOT`；
3. `starter_cards` 不含 `null`；
4. `starter_cards` 不含与 `root_card` 相同的卡牌引用；
5. 至少有一个已解锁且校验通过的预设，才能开始新局。

校验失败时：

- 开发环境使用 `push_error` 输出资源路径、预设 ID 和失败字段；
- 无效预设不显示在正常牌组列表中；
- 全部预设无效时，禁用开始按钮并说明没有可用牌组；
- 页面保持可加载，不能因单个坏资源而崩溃。

### 启动失败处理

`Main` 在收到开始请求后再次校验预设。若 `GameManager` 无法创建本局运行时卡牌：

1. 不保留半初始化的棋盘或手牌；
2. 清理本次创建的 `GameManager`；
3. 重新显示首页；
4. 输出或显示开发期错误提示。

本局开始时必须从配置的基础 `PlayerData` 创建深度运行时副本；其金币、生命、卡牌位置和牌链状态均属于该副本，不回写静态资源。

## 测试与验收

实现采用测试驱动开发：先添加失败测试，确认失败原因是首页 / 初始牌组功能尚不存在，再以最小实现逐项通过。

| 层级 | 用例输入 | 预期步骤与结果 |
|---|---|---|
| Resource 单元测试 | 有效复苏套组 | 读取预设 → 校验通过 → 根卡存在且为 `ROOT` → 起始普通卡均有效 → 起始总数为 `1 + starter_cards.size()`。 |
| Resource 单元测试 | 根卡为空、根卡为普通卡、起始数组含 `null` | 读取预设 → 校验失败 → 返回具体错误信息 → 预设不成为可开始候选。 |
| 首页交互测试 | 两套已解锁预设 | 创建首页 → 默认选择第一套 → 点击第二套 → 右侧名称、标签、根卡预览、起始卡数量全部切换为第二套数据 → 开始按钮保持可用。 |
| 锁定态测试 | 一套已解锁预设与一套锁定预设 | 创建首页 → 点击锁定项 → 当前选择保持已解锁预设 → 显示锁定说明 → 开始请求仍携带原有效预设。 |
| 只读预览测试 | 有效牌根与起始卡 | 刷新首页 → 生成独立临时 `CardInstance` → `CardEntity` 显示正确数据 → 进入展示模式 → 拖拽、放大、加入 `DragLayer` 均不发生。 |
| 启动流程集成测试 | 选择复苏套组后点击开始 | 选择预设 → 仅发射一次 `start_requested(preset)` → `Main` 实例化 `GameManager` 并注入同一预设 → `GameManager` 创建牌根加起始普通卡的运行时实例 → 正常进入探索状态。 |
| 资源隔离测试 | 连续两局选择同一预设 | 第 1 局移动或消耗卡牌 → 结束并回到首页 → 第 2 局重新选择相同预设 → 第 2 局为全新初始卡状态 → 预设资源和第 1 局状态未被污染。 |
| 重复开始测试 | 对开始按钮快速连点 | 第一次点击 → 按钮禁用并进入启动态 → 后续点击被忽略 → 场景树仅存在一个 `GameManager`。 |
| 回归测试 | 既有棋盘、事件、战斗和响应式布局测试 | 执行已有测试脚本 → 所有测试继续通过 → 首页引入不影响当前事件弹窗、棋盘放置和 GameplayCanvas 缩放行为。 |

## 首版验收标准

以下全部满足时，首页 / 新局准备功能达到首版可用：

- 游戏启动后先显示首页，而不是直接显示棋盘；
- 玩家可以选择至少一套包含牌根的初始牌组；
- 牌根和起始卡预览与游戏内卡面一致，但不具备拖拽或放大等玩法交互；
- 点击开始后，本局实际卡牌严格来自所选套组，不再走旧的随机初始牌逻辑；
- 背景在任意窗口下填充，首页内容保持可读且不会在超宽窗口无控制拉伸；
- 单个预设配置错误不会导致页面崩溃、无法进入半初始化游戏；
- 快速重复点击开始按钮不会创建多局探索。

## 后续扩展点

- 多套初始牌组、锁定状态与解锁条件；
- 选择套组后的确认弹窗、难度或地图种子选择；
- 完整的远征结算与返回首页流程；
- 存档中持久化最近选择的 `deck_id`；
- 牌根专用 `CombatService` 与首页的更详细规则说明；
- 套组插画、牌根背景动画和音效。
