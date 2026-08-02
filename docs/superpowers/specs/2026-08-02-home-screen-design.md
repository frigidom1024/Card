# 主菜单、牌根选择与新局准备界面设计

- **日期：** 2026-08-02
- **状态：** 已确认，已按“主菜单 → 选择牌根 → 探索”流程修订，等待文档复核
- **范围：** 游戏启动后的主菜单、牌根选择页，以及从牌根选择创建一局探索的流程

## 目标

游戏启动后先进入标准主菜单：顶部显示游戏 LOGO，中部只提供一个明确的 `开始游戏` 操作按钮。玩家点击后进入独立的“选择牌根”页面，选择本局的牌根与其对应的起始构成，最后点击 `开始探索` 才进入既有森林棋盘流程。

首版优先提供一张可选牌根及其完整起始牌组，但 UI、数据和流程必须能自然扩展到多张牌根、不同起始构成和未来解锁条件。

```text
启动游戏
→ 主菜单
→ 点击「开始游戏」
→ 选择牌根
→ 查看牌根效果与完整起始牌组
→ 点击「开始探索」
→ 进入森林棋盘、手牌与事件流程
```

## 非目标

首版不包含：

- 继续游戏、存档选择、图鉴、成就、牌库或营地大厅；
- 在主菜单直接选择起始卡或直接进入棋盘；
- 在选择牌根页面编辑、替换、升级或购买起始卡牌；
- 在主菜单或选择牌根页面结算战斗、事件、奖励或怪物逻辑；
- 为菜单与牌根预览复制一套独立的卡牌视觉组件；
- 完整的本局结束页或返回主菜单交互。仅预留返回接口。

## 页面职责与流程

采用 `Main` 管理页面切换、`GameManager` 管理单局探索的结构。不新增全局运行状态单例，也不把玩家的当前选择写回静态 `PlayerData` 资源。

```text
Main
├── BackgroundLayer                 # 始终填充窗口的背景
├── MainMenuScreen                  # 标准主菜单：LOGO 与「开始游戏」
├── RootSelectionScreen             # 本局牌根与起始牌组选择
└── GameManager（按需实例化）        # 一次探索的棋盘、手牌、事件和战斗
```

### 页面状态

`Main` 在同一时刻只显示下列其中一个主页面：

1. `MainMenuScreen`；
2. `RootSelectionScreen`；
3. `GameManager` 所在的探索页面。

页面切换时销毁前一主页面实例，避免被隐藏页面继续接收输入或保留旧的预览卡节点。`BackgroundLayer` 不销毁，持续覆盖窗口。

### 流程步骤

1. 启动时，`Main` 实例化并显示 `MainMenuScreen`；
2. 玩家点击 `开始游戏`，`MainMenuScreen` 只发射 `start_game_requested` 信号；
3. `Main` 销毁主菜单并实例化 `RootSelectionScreen`；此时不得创建 `GameManager`；
4. 玩家在牌根选择页选择一个有效、已解锁的牌根选项；
5. 玩家点击 `开始探索`，`RootSelectionScreen` 只发射 `exploration_requested(preset)` 信号；
6. `Main` 销毁牌根选择页，实例化 `GameManager`，并在本局初始化前注入同一个预设；
7. `GameManager` 根据该预设完整的 `starter_cards` 创建新的运行时玩家和卡牌实例，再初始化棋盘、手牌和事件；
8. 本局结束时，`GameManager` 可发射 `run_finished`，由 `Main` 清理本局并重新实例化 `MainMenuScreen`。首版允许暂不实现完整返回交互，但接口边界应保留。

`MainMenuScreen` 不加载场景、不实例化游戏卡牌；`RootSelectionScreen` 不实例化游戏区域、不创建战斗服务；`GameManager` 不读取菜单 UI 节点。

## 主菜单设计

主菜单是纯入口页，首版避免向玩家展示尚不存在的系统。它只有一个可执行操作：`开始游戏`。

```text
MainMenuScreen (Control，全屏)
└── SafeArea (MarginContainer，全屏，统一留白)
    └── Layout (Control)
        ├── LogoBlock (VBoxContainer，顶部水平居中)
        │   ├── GameLogo              # MONOCARD 图形或文字 LOGO
        │   └── TaglineLabel          # 可选：一行简短世界观文案
        ├── ActionBlock (CenterContainer，视觉中心)
        │   └── StartGameButton       # 开始游戏
        └── FooterBlock (HBoxContainer，底部)
            └── VersionLabel
```

### 主菜单交互规则

- `StartGameButton` 显示文本为 `开始游戏`；
- 点击一次后立即禁用，防止重复创建牌根选择页；
- 成功进入牌根选择页后，主菜单实例已销毁；
- 首版不显示不可用的商店、图鉴、继续游戏或退出按钮；
- 版本号可显示在底部，但不占用中部主操作区域；
- 键盘确认键可以触发 `开始游戏`，以支持最基础的键盘导航。

## 牌根选择页设计

牌根选择页承接“开始游戏”，是本局唯一的构筑选择页面。虽然内部数据仍使用 `StartingDeckData`，但玩家面对的是**牌根选项**，而不是抽象的牌组名称：每个选项以牌根名称、标签与效果作为识别核心。

```text
RootSelectionScreen (Control，全屏、鼠标输入入口)
└── SafeArea (MarginContainer，全屏，统一留白)
    └── Content (VBoxContainer，居中，最大宽度约 1500px)
        ├── Header (HBoxContainer)
        │   ├── BackButton：返回主菜单
        │   ├── TitleBlock (VBoxContainer)
        │   │   ├── TitleLabel：选择牌根
        │   │   └── SubtitleLabel：牌根将决定本局的全局战斗规则与起始构成
        │   └── Spacer
        └── MainArea (HBoxContainer)
            ├── RootListPanel (PanelContainer，约 32% 宽)
            │   └── VBoxContainer
            │       ├── SectionTitle：可用牌根
            │       └── RootOptionList (ScrollContainer / VBoxContainer)
            │           └── RootOptionEntry × N
            └── RootDetailPanel (PanelContainer，约 68% 宽)
                └── VBoxContainer
                    ├── DetailHeader
                    │   ├── RootNameLabel
                    │   └── TagsRow
                    ├── HeroArea (HBoxContainer)
                    │   ├── RootPreviewSlot
                    │   └── RootDescription
                    │       ├── RootEffectLabel
                    │       └── StartingDeckDescriptionLabel
                    ├── Divider
                    ├── StartingDeckSummary
                    │   ├── InitialCardCountLabel
                    │   └── RemainingStarterCardPreviewRow
                    └── Footer (HBoxContainer)
                        ├── UnlockHintLabel
                        └── StartExplorationButton
```

### 牌根选择交互

每个 `RootOptionEntry` 显示：

- 牌根名称；
- 一行玩法标签；
- 选中态、锁定态或异常态；
- 可选的小型牌根图标或卡面缩略图。

交互规则：

- 默认选择第一张有效、已解锁的牌根；
- 点击已解锁选项：立即更新右侧牌根效果、套组说明和起始卡预览；
- 点击锁定选项：不更改当前选择，只显示解锁提示；
- 点击 `返回主菜单`：销毁选择页并重新实例化主菜单，不创建 `GameManager`；
- 点击 `开始探索`：只针对当前有效、已解锁的牌根选项；第一次点击后按钮禁用并显示 `正在进入森林…`，忽略重复点击；
- 没有可用牌根时禁用 `开始探索`，并显示“暂无可选择的牌根”。

### 详情与起始牌预览

右侧主视觉区域突出显示所选牌根。它展示根牌效果、该牌根的套组说明、玩法标签与完整起始卡数量。

`starter_cards` 的总数包含牌根。由于牌根已经在上方的大尺寸主预览中展示，下方 `RemainingStarterCardPreviewRow` 仅展示其余起始卡，以避免同一张牌根卡被重复渲染；文案必须明确为“其余起始卡”。

## 初始牌组数据

`StartingDeckData` 是每个牌根选项的静态配置，描述“选择该牌根后，玩家带什么进入本局”。它不包含战斗过程、事件、商店或奖励内容。

建议字段：

| 字段 | 语义 |
|---|---|
| `deck_id` | 稳定唯一标识，供未来存档、统计和解锁使用。 |
| `display_name` | 配置显示名称；根选择 UI 优先展示解析出的牌根名称。 |
| `description` | 该牌根及其起始构成的玩法说明。 |
| `starter_cards` | 必填数组；完整固定起始牌组，必须包含且只包含一张牌根；普通卡可重复。 |
| `playstyle_tags` | 首页展示用标签，例如“治疗 / 延续 / 武器连锁”。 |
| `is_unlocked` | 是否可选择。首版所有正式预设可设为 `true`。 |

### 固定规则

- `starter_cards` 必须非空，且其中必须恰好有一张 `card_type == ROOT` 的牌根；
- 牌根由 `StartingDeckData` 从 `starter_cards` 解析得到，作为牌根选择页主预览和本局战斗服务选择的唯一来源；
- 同一批可用预设不得解析出相同 `card_id` 的牌根，保证“选择牌根”页面中每个选项都无歧义；
- 本局起始卡总数恒为 `starter_cards.size()`；
- 每局开始时，`GameManager` 为 `starter_cards` 中的每张卡创建新的 `CardInstance`，不得额外补入或重复创建牌根；
- `.tres` 中的 `CardData` 与 `StartingDeckData` 仅作为静态定义，运行时绝不修改；
- 允许 `starter_cards` 中存在相同普通 `CardData` 的多次引用，以表达同名卡的起始副本；
- 既有 `CardLibrary` 继续承担全局卡牌索引、商店和奖励候选池职责，不再作为正式初始牌组的随机生成来源；
- 既有 `CardManager.get_init_cards()` 需要被替换或改造成“由 `StartingDeckData` 创建起始 `CardInstance`”的明确接口，禁止在正式开局中隐藏随机抽卡规则。

### 牌根与战斗服务

`RootSelectionScreen` 只传递所选预设。牌根决定的全局规则和不同 `CombatService` 的选择仍属于本局玩法初始化：`GameManager` 在从选中预设的 `starter_cards` 解析牌根后，创建默认或该牌根专用的战斗服务。

因此选择页面无需了解根牌的战斗实现；未来增加新牌根时，只需新增预设和相应战斗服务，不需要修改主菜单或选择页面的核心流程。

## 真实卡牌预览复用

牌根和其余起始卡预览必须复用现有 `CardEntity` 渲染，以保持插画、名称、标签、数值和描述与游戏内一致。

为此，`CardEntity` 需要具有明确的展示模式，而不是让菜单预览沿用默认可交互状态：

```text
交互模式：可拖拽、可放大、响应棋盘相关输入。
展示模式：不可拖拽、不可放大、不进入 DragLayer、不接收鼠标事件。
```

预览规则：

1. 每次切换根牌时，从 `starter_cards` 解析牌根，并为牌根和其余要展示的卡创建临时 `CardInstance`；
2. 临时实例仅供卡面绑定与渲染，不加入手牌、棋盘或牌链；
3. 实例化出的 `CardEntity` 显式进入展示模式；
4. 切换选项时清理旧预览节点，再创建新预览；
5. 预览卡保持实际的 1:2 卡面比例，不试图填充棋盘格或参与网格布局。

## 响应式与视觉层级

- `Main/BackgroundLayer` 独立于玩法画布，始终覆盖任意窗口；
- `MainMenuScreen` 与 `RootSelectionScreen` 都使用全屏 `Control` 布局，不进入 `GameplayCanvas`；
- 根选择页内容区居中且最大宽度约 1500px，超宽窗口不无限拉伸面板；
- 1920×1080 基准窗口下，根选择页使用左右双栏；
- 当 `Content` 可用宽度低于 980px 时，`MainArea` 切换为上下布局；若可用高度不足，`SafeArea` 作为唯一的纵向滚动容器；
- 主菜单始终保持“顶部 LOGO + 中部开始游戏按钮 + 底部版本号”的视觉层级，不随超宽窗口拉开关键元素之间的距离；
- 进入探索后，菜单与根选择页实例均已销毁；既有 `GameplayCanvas`、`EventModalLayer` 和背景填充机制继续工作；
- 视觉层级固定为：背景 → 主菜单或根选择页或玩法内容 → 事件弹窗。

## 资源组织

```text
res://
├── scenes/
│   ├── main.tscn
│   └── home/
│       ├── main_menu_screen.tscn
│       ├── root_selection_screen.tscn
│       └── root_option_entry.tscn
├── scripts/
│   ├── home/
│   │   ├── main_menu_screen.gd
│   │   ├── root_selection_screen.gd
│   │   └── root_option_entry.gd
│   └── run/
│       └── starting_deck_data.gd
└── data/
    └── starting_decks/
        └── revival_starting_deck.tres
```

## 错误处理与保护

### 配置校验

牌根选择页读取预设时执行轻量校验：

1. `deck_id` 和 `display_name` 非空；
2. `starter_cards` 非空；
3. `starter_cards` 不含 `null`；
4. `starter_cards` 中恰好存在一张 `ROOT` 类型卡牌；
5. 所有有效且已解锁的预设解析出的根牌 `card_id` 互不重复；
6. 至少有一个已解锁且校验通过的预设，才能开始探索。

校验失败时：

- 开发环境使用 `push_error` 输出资源路径、预设 ID 和失败字段；
- 无效预设不显示在正常根牌列表中；
- 全部预设无效时，禁用 `开始探索` 并说明没有可用牌根；
- 页面保持可加载，不能因单个坏资源而崩溃。

### 页面与启动保护

- `MainMenuScreen` 和 `RootSelectionScreen` 都在触发页面跳转后进入一次性禁用状态，忽略后续重复点击；
- `Main` 在收到 `exploration_requested` 后再次校验预设；
- 若 `GameManager` 无法创建本局运行时卡牌：不保留半初始化棋盘或手牌，清理本次创建的 `GameManager`，重新实例化 `MainMenuScreen`，并输出或显示开发期错误提示；
- 本局开始时必须从配置的基础 `PlayerData` 创建深度运行时副本；其金币、生命、卡牌位置和牌链状态均属于该副本，不回写静态资源。

## 测试与验收

实现采用测试驱动开发：先添加失败测试，确认失败原因是菜单、牌根选择或起始卡预设功能尚不存在，再以最小实现逐项通过。

| 层级 | 用例输入 | 预期步骤与结果 |
|---|---|---|
| 主菜单场景测试 | 加载主菜单 | 场景可实例化 → 顶部存在 LOGO 节点 → 中部存在唯一可执行的 `开始游戏` 按钮 → 底部存在版本号节点。 |
| 主菜单路由测试 | 点击 `开始游戏` | 主菜单按钮进入禁用状态 → 仅发射一次 `start_game_requested` → `Main` 销毁主菜单并创建牌根选择页 → 场景树中尚不存在 `GameManager`。 |
| 返回路由测试 | 在牌根选择页点击返回 | 牌根选择页发射返回请求 → `Main` 销毁选择页并重新创建主菜单 → 场景树中仍不存在 `GameManager`。 |
| Resource 单元测试 | 有效复苏预设 | 读取预设 → 校验通过 → `starter_cards` 含且仅含一张 `ROOT` → 所有起始卡有效 → 起始总数为 `starter_cards.size()`。 |
| Resource 单元测试 | 起始牌组没有牌根、含多张牌根、含 `null` | 读取预设 → 校验失败 → 返回具体错误信息 → 预设不成为可选择根牌。 |
| 根牌唯一性测试 | 两个预设解析为同一根牌 | 读取预设集合 → 检测到重复根牌 `card_id` → 两者均不作为正常根牌选项 → 开发环境输出明确错误。 |
| 选择页交互测试 | 两张已解锁根牌 | 创建选择页 → 默认选择第一张 → 点击第二张 → 右侧根牌名称、标签、根牌预览、完整起始牌数量和其余起始卡预览均切换 → `开始探索` 保持可用。 |
| 锁定态测试 | 一张已解锁根牌与一张锁定根牌 | 创建选择页 → 点击锁定项 → 当前选择保持已解锁根牌 → 显示锁定说明 → 开始请求仍携带原有效预设。 |
| 只读预览测试 | 有效牌根与其余起始卡 | 刷新选择页 → 生成独立临时 `CardInstance` → `CardEntity` 显示正确数据 → 进入展示模式 → 拖拽、放大、加入 `DragLayer` 均不发生。 |
| 启动流程集成测试 | 点击开始游戏、选择复苏根牌、点击开始探索 | 主菜单跳转到根选择页 → 选择预设 → 仅发射一次 `exploration_requested(preset)` → `Main` 实例化 `GameManager` 并注入同一预设 → `GameManager` 按 `starter_cards` 创建运行时实例且不额外添加牌根 → 正常进入探索状态。 |
| 资源隔离测试 | 连续两局选择同一根牌 | 第 1 局移动或消耗卡牌 → 结束并回到主菜单 → 第 2 局重复进入选择页并选择相同根牌 → 第 2 局为全新初始卡状态 → 预设资源和第 1 局状态未被污染。 |
| 重复点击测试 | 快速连点开始游戏或开始探索 | 第一次点击对应按钮 → 按钮禁用并进入跳转状态 → 后续点击被忽略 → 每次路由只创建一个目标页面或一个 `GameManager`。 |
| 回归测试 | 既有棋盘、事件、战斗和响应式布局测试 | 执行已有测试脚本 → 所有测试继续通过 → 菜单引入不影响当前事件弹窗、棋盘放置和 `GameplayCanvas` 缩放行为。 |

## 首版验收标准

以下全部满足时，主菜单与牌根选择功能达到首版可用：

- 游戏启动后先显示顶部 LOGO 和中部 `开始游戏` 按钮构成的主菜单；
- 主菜单首版只有一个可执行操作：`开始游戏`；
- 点击开始游戏只会进入选择牌根页面，不会直接创建棋盘或 `GameManager`；
- 玩家能在牌根选择页选择至少一张可用牌根，并明确看到其效果和完整起始卡数量；
- `starter_cards` 始终包含且只包含一张牌根；
- 牌根和其余起始卡预览与游戏内卡面一致，但不具备拖拽或放大等玩法交互；
- 点击开始探索后，本局实际卡牌严格来自所选预设，不再走旧的随机初始牌逻辑；
- 背景在任意窗口下填充，主菜单与选择页内容保持可读且不会在超宽窗口无控制拉伸；
- 单个预设配置错误不会导致页面崩溃、无法进入半初始化游戏；
- 快速重复点击开始游戏或开始探索不会创建重复页面或多局探索。

## 后续扩展点

- 主菜单的继续游戏、设置、图鉴和退出按钮；
- 多张牌根、锁定状态与解锁条件；
- 选择牌根后的难度、地图种子或确认弹窗；
- 完整的远征结算与返回主菜单流程；
- 存档中持久化最近选择的根牌 / 预设 `deck_id`；
- 牌根专用 `CombatService` 与选择页更详细的规则说明；
- 套组插画、牌根背景动画和音效。
