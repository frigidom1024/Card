# 新卡牌交互迁移与优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `res://scenes/card/card.tscn` 中已经验证的 Button、悬浮、缩放、透视倾斜和阴影交互迁移到正式的 `CardEntity` 卡牌架构，同时保留棋盘、手牌、商店、拖拽、信息浮层和战斗标签的现有接口。

**Architecture:** `CardEntity` 继续作为游戏玩法层的稳定外壳，保持 `Area2D`、碰撞体、卡牌数据绑定和公开信号不变。新的 Button 卡面作为 `CardSurface` 视觉/指针交互层嵌入 `CardEntity`，由 `CardInteractionController` 统一协调悬浮、缩放、倾斜、拖拽和模式切换；`CardDisplayController` 负责尺寸、卡面内容和视觉状态，`CardInfoController` 与 `CardTagController` 保持独立。禁止让棋盘、手牌或商店直接依赖 Button 节点。

**Tech Stack:** Godot 4.7、GDScript、`.tscn` 场景、CanvasItem Shader、SceneTree 回归测试。

## Global Constraints

- 保留 `CardEntity` 的 `Area2D` 类型，不能直接把正式卡牌根节点替换为 `Button`。
- 保留现有公开信号和玩法调用：`hovered`、`unhovered`、`clicked`、`bind_instance()`、`set_display_only()`、`set_market_offer_mode()`、`set_on_board()`、拖拽和旋转兼容方法。
- 新卡面不得依赖硬编码的屏幕坐标；卡面尺寸统一由 `LayoutConfig` 和 `CardDisplayController` 驱动。
- 视觉子节点必须设置 `mouse_filter = MOUSE_FILTER_IGNORE`，除负责卡牌交互的 Button/Surface 外不能拦截输入。
- 每个卡牌实例必须拥有独立的 `ShaderMaterial`，避免一张卡牌倾斜影响其它卡牌。
- 拖拽、棋盘放置、商店购买/回收仍由现有游戏层服务处理，卡面只发出语义化的交互信号。
- 不在本次迁移中重做战斗规则、卡牌数据、拖拽规则或商店业务。
- 不删除旧场景和脚本，直到所有引用迁移完成且回归测试通过。
- 每个迁移任务完成后先运行测试和场景检查，未经确认不自动提交或合并提交。

## Target File Map

### 新增或整理的文件

- Create/rename: `scenes/card/card_surface.tscn`
  - 新 Button 卡面场景的正式名称。
  - 只包含卡面底图、阴影、合成纹理、Shader 和指针输入入口。
  - 根节点建议命名为 `CardSurface`，不要继续使用 `Card2`。
- Create: `scripts/card/card_surface.gd`
  - 负责 Surface 自身的悬浮、中心轴缩放、透视参数更新和鼠标离开复位。
  - 通过信号向 `CardInteractionController` 报告输入，不处理棋盘放置和金币等玩法逻辑。
- Modify: `scenes/card_view/card_entity.tscn`
  - 将旧 `CardView` 替换或包裹为新的 `CardSurface` 实例。
  - 保留四个 Controller、标签锚点和碰撞体。
- Modify: `scenes/card_view/card_view.tscn` 或迁移为 `scenes/card/card_content.tscn`
  - 根据实际复用情况决定是否保留旧显示场景。
  - 仅保留卡框、插画、数值标签、头部指示器等内容，不再重复实现输入逻辑。
- Modify: `scripts/card/card_entity.gd`
  - 继续作为兼容 façade，负责绑定 Surface 与 Controller。
  - 不把新卡面逻辑重新塞回该文件。
- Modify: `scripts/card/card_interaction_controller.gd`
  - 接收 Surface 的 hover、press、release、gui input 信号。
  - 统一处理不同交互模式和拖拽状态。
- Modify: `scripts/card/card_display_controller.gd`
  - 负责 Surface 的布局尺寸、CardInstance 内容刷新和视觉高亮。
- Modify: `scripts/card/card_view.gd`
  - 如果旧 `CardView` 不再作为输入层，删除其交互相关逻辑，仅保留显示与阴影同步。
- Modify: `scripts/game/layout_config.gd`
  - 将卡面尺寸、Surface 偏移、阴影偏移集中为唯一配置来源。

### 需要重点验证、通常不应修改的文件

- `scripts/game/hand.gd`
- `scripts/game/drag_layer.gd`
- `scripts/game/board.gd`
- `scripts/game/market/persistent_market.gd`
- `scripts/game/market/persistent_market_coordinator.gd`
- 各遭遇、奖励和商店场景

这些文件继续只依赖 `CardEntity` 的公开接口。

---

## Task 1: 固化现有卡牌交互行为

**Files:**
- Test: `tests/card_surface_interaction_contract_test.gd`
- Test: `tests/card_entity_card_surface_contract_test.gd`
- Read-only reference: `scenes/card/card.tscn`, `scenes/card/card.gd`

**目标:** 在迁移前把当前新卡牌原型的行为记录下来，避免迁移过程中“看起来差不多”但交互细节改变。

- [ ] **Step 1: 写失败测试**

测试至少覆盖：

```gdscript
func test_surface_has_button_input_and_shader() -> void:
    var surface := SurfaceScene.instantiate() as Button
    expect(surface != null)
    expect(surface.get_node("CardTexture") != null)
    expect(surface.get_node("CardTexture").material is ShaderMaterial)
```

以及：

```gdscript
func test_hover_scale_pivot_is_centered() -> void:
    var surface := SurfaceScene.instantiate() as Button
    await process_frame
    expect(surface.pivot_offset.is_equal_approx(surface.size * 0.5))
```

- [ ] **Step 2: 运行测试确认失败原因正确**

运行：

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/card_surface_interaction_contract_test.gd
```

预期：测试因为正式 Surface 场景尚未建立而失败，不应出现脚本语法错误。

- [ ] **Step 3: 记录当前行为基准**

记录以下值作为迁移验收基线：

- 卡面默认尺寸：`84×154` 原型尺寸，正式运行时由 `LayoutConfig` 覆盖。
- 最大倾斜角：默认 `8°`。
- 悬浮缩放：`Vector2(1.2, 1.2)`。
- 缩放轴：卡牌中心。
- 鼠标离开时：倾斜归零、缩放归一。
- `ShaderMaterial`：每个实例独立复制。
- 卡面子层：不拦截事件。

---

## Task 2: 将原型整理为正式 CardSurface 场景

**Files:**
- Create: `scenes/card/card_surface.tscn`
- Create: `scripts/card/card_surface.gd`
- Modify: `shaders/card_perspective.gdshader` only if validation finds a shader issue
- Test: `tests/card_surface_interaction_contract_test.gd`

**目标:** 把当前 `card.tscn` 原型从“实验场景”整理为可复用的纯视觉交互组件。

- [ ] **Step 1: 建立稳定的场景结构**

目标结构：

```text
CardSurface (Button)
├── Shadow (Panel)
└── CardTexture (SubViewportContainer)
    └── SubViewport
        ├── Card (Panel)
        └── Artwork (TextureRect)
```

要求：

- 根节点 `CardSurface` 不保留硬编码屏幕坐标。
- 根节点使用 `custom_minimum_size` 或由父级设置尺寸。
- `CardTexture` 覆盖整个 Surface。
- `Shadow` 与卡面同尺寸，并通过局部偏移表现右下阴影。
- 所有 SubViewport 内的展示节点使用 `MOUSE_FILTER_IGNORE`。
- `SubViewport.size` 由脚本跟随卡面尺寸更新，而不是永远固定 `84×154`。

- [ ] **Step 2: 把交互脚本从通用 `card.gd` 中拆出**

`card_surface.gd` 提供明确接口：

```gdscript
signal surface_hovered(surface: CardSurface)
signal surface_unhovered(surface: CardSurface)
signal surface_pressed(surface: CardSurface, event: InputEventMouseButton)
signal surface_released(surface: CardSurface, event: InputEventMouseButton)
signal surface_motion(surface: CardSurface, event: InputEventMouseMotion)

func set_interaction_enabled(value: bool) -> void
func set_hover_scale(value: Vector2) -> void
func reset_visual_state(animated: bool = true) -> void
func set_tilt_enabled(value: bool) -> void
func set_card_size(value: Vector2) -> void
```

- [ ] **Step 3: 统一角度单位**

外部配置全部使用“度”。Shader 参数也继续使用度。不要再把度数直接传给 `lerp_angle()`；如使用 `lerp_angle()`，必须显式 `deg_to_rad()` 后再转换回来。

- [ ] **Step 4: 运行 Surface 回归测试**

确认：

- 鼠标移动到中心时 `x_rot/y_rot` 接近 0。
- 边缘倾斜不超过配置上限。
- 鼠标离开后参数回到 0。
- 缩放中心为 `size * 0.5`。
- 修改尺寸后 SubViewport 和阴影尺寸同步。

---

## Task 3: 把 CardSurface 嵌入 CardEntity

**Files:**
- Modify: `scenes/card_view/card_entity.tscn`
- Modify: `scripts/card/card_entity.gd`
- Modify: `scripts/card/card_display_controller.gd`
- Test: `tests/card_entity_card_surface_contract_test.gd`

**目标:** 正式卡牌使用新交互，但玩法层仍看到 `CardEntity`。

- [ ] **Step 1: 先添加 Surface 作为并行视觉层**

在 `CardEntity` 中先保留旧 `CardView`，新增：

```text
CardEntity (Area2D)
├── CollisionShape2D
├── CardSurface (CardSurface instance)
├── CardViewLegacy 或 CardContent
├── CardInteractionController
├── CardDisplayController
├── CardInfoController
├── CardTagController
└── CombatTagAnchor
```

此阶段只让 Surface 接管鼠标视觉反馈，不删除旧 CardView。

- [ ] **Step 2: 统一尺寸和中心坐标**

`CardDisplayController.apply_layout()` 继续读取：

```gdscript
LayoutConfig.card_view_rect(LayoutConfig.CELL_SIZE)
```

但输出应同时应用给：

- `CardSurface.position/size`
- `CardContent.position/size`
- 阴影和标签锚点
- `CollisionShape2D.shape.size`

不得在场景中继续保留 `82, 63, 166, 185` 或类似旧试验值。

- [ ] **Step 3: 明确坐标责任**

- `CardEntity`：世界坐标、旋转、碰撞。
- `CardSurface`：自身局部坐标下的放大、倾斜和视觉阴影。
- `CardDisplayController`：卡面相对 `CardEntity` 的矩形。
- `CardInteractionController`：交互状态和拖拽，不直接修改卡牌数据。
- `CardInfoController`：详情和放大预览。
- `CardTagController`：战斗标签位置。

- [ ] **Step 4: 运行 CardEntity 组合测试**

至少验证：

- `CardEntity` 仍然是 `Area2D`。
- 碰撞大小仍为 `CELL_SIZE × CELL_SIZE * 2`。
- Surface 存在且尺寸与 `CardView` 相同。
- Surface 的子节点不会拦截 CardEntity 所需的输入。
- 绑定 `CardInstance` 后卡面内容仍会刷新。

---

## Task 4: 统一输入路由，避免重复触发

**Files:**
- Modify: `scripts/card/card_interaction_controller.gd`
- Modify: `scripts/card/card_entity.gd`
- Modify: `scenes/card_view/card_entity.tscn`
- Test: `tests/card_entity_input_routing_test.gd`

**目标:** 新 Button 交互和旧 Area2D 输入不能同时各自处理同一个动作，否则会出现点击两次、拖拽启动后立即结束、商店购买重复等问题。

- [ ] **Step 1: 定义唯一输入入口**

推荐方案：

```text
CardSurface.gui_input
    → CardInteractionController
        → CardEntity 的 hovered/unhovered/clicked
        → DragLayer / InfoController
```

Area2D 的 `input_event` 只作为兼容入口，迁移期间由 Controller 做去重；不要让 `CardEntity` 和 Surface 各自启动拖拽。

- [ ] **Step 2: 增加输入来源和消费状态**

Controller 内部记录：

```gdscript
var _input_source: InputSource
var _press_frame: int = -1
var _drag_started := false
```

同一帧相同按钮事件只允许处理一次。`display_only` 和 `market_offer` 必须在 Controller 层统一判断。

- [ ] **Step 3: 保持旧 façade 方法**

以下方法继续存在，内部改为调用 Controller：

```gdscript
_start_drag()
_end_drag()
cancel_drag()
cancel_drag_for_interaction_lock()
rotate_while_dragging()
_show_zoom()
_hide_zoom()
```

- [ ] **Step 4: 测试关键交互路径**

覆盖：

1. 手牌卡牌悬浮只触发一次 hover。
2. 左键拖拽只启动一次。
3. 棋盘放置失败后卡牌可回到手牌并继续交互。
4. 商店预览点击只触发购买一次。
5. 右键详情/放大不会启动拖拽。
6. `display_only` 卡牌不启动拖拽，但可按配置显示信息。
7. 同一输入不会同时触发 Surface 和 Area2D 两次。

---

## Task 5: 迁移卡面显示内容

**Files:**
- Modify: `scripts/card/card_display_controller.gd`
- Modify: `scripts/card/card_view.gd`
- Modify: `scenes/card_view/card_view.tscn` 或新建 `scenes/card/card_content.tscn`
- Modify: `scripts/card/card_tag_controller.gd`
- Tests: `tests/card_entity_display_mode_test.gd`, `tests/card_entity_tag_layout_test.gd`

**目标:** 新 Surface 负责基础卡面渲染，正式内容仍能显示卡名、点数、护甲、治疗、头部指示器和战斗标签。

- [ ] **Step 1: 明确内容层和交互层分离**

推荐最终结构：

```text
CardEntity (Area2D)
├── CollisionShape2D
├── CardSurface (Button, 交互+基础合成渲染)
│   └── CardTexture/SubViewport/...
├── CardContent (Control, 数值/文本/可选插画覆盖)
├── CardInteractionController
├── CardDisplayController
├── CardInfoController
├── CardTagController
└── CombatTagAnchor
```

如果标签和文本需要进入 Shader 透视效果，则把它们放入 SubViewport 的合成层；否则保留为 `CardContent` 覆盖层，并明确它们跟随 `CardEntity` 变换。

- [ ] **Step 2: 统一数据刷新入口**

所有卡牌内容只能通过：

```gdscript
CardEntity.bind_instance(instance)
CardDisplayController.bind_instance(instance)
```

不得由 Hand、Market 或 Board 直接修改卡面 Label。

- [ ] **Step 3: 统一视觉状态**

`NORMAL/HOVER/DRAGGING/ZOOMED` 的视觉变化由 DisplayController 或 Surface 提供方法实现，CardEntity 只切换状态，不直接操作材质细节。

- [ ] **Step 4: 回归预览模式**

验证宝藏、商店、奖励和常驻商店中的卡牌：

- 使用新卡面资源和中文卡牌说明。
- 预览模式不会拖拽。
- 商店模式仍然可购买/回收。
- 放大查看不改变原卡牌状态。
- 卡牌数值标签和战斗标签位置正确。

---

## Task 6: 迁移所有场景和资源引用

**Files:**
- Modify: 所有直接实例化旧 `CardView` 或旧卡牌场景的 `.tscn`
- Modify: 所有直接加载卡牌展示场景的 `.gd`
- Test: `tests/card_scene_reference_audit_test.gd`

**目标:** 让正式游戏路径只通过 `CardEntity` 创建卡牌，避免存在多个视觉卡牌实现。

- [ ] **Step 1: 建立引用清单**

使用：

```powershell
rg -n 'card_view\.tscn|card\.tscn|card2\.tscn|CardView|CardSurface' scripts scenes tests -g '*.gd' -g '*.tscn'
```

将引用分成：

- 正式玩法实例：必须使用 `CardEntity`。
- 纯展示/详情实例：可以使用 `CardSurface` 或 `CardContent`，但不能依赖拖拽业务。
- 测试实例：根据测试目标选择正式 CardEntity 或纯 Surface。

- [ ] **Step 2: 迁移正式玩法引用**

Hand、Board、DragLayer、Market、Encounter、Treasure 不直接 preload 新 Button 卡面；它们继续 preload：

```gdscript
res://scenes/card_view/card_entity.tscn
```

新 Button 只作为 CardEntity 的内部组件。

- [ ] **Step 3: 清理实验命名和重复引用**

- 根节点 `Card2` 改为 `CardSurface`。
- 删除或停用 `card2.tscn` 的正式引用。
- 统一 `card.tscn` 的用途：要么作为 `CardSurface` 正式场景，要么改名为 `card_surface.tscn` 并保留兼容转发场景。
- 不要同时维护 `card.tscn`、`card2.tscn`、旧 `CardView` 三套交互实现。

- [ ] **Step 4: 运行引用审计**

审计测试应确保：

```gdscript
# 玩法层不直接实例化 Button 卡面
# 正式卡牌场景仍然是 CardEntity
```

并确认没有遗留 `card2.tscn` 的运行时引用。

---

## Task 7: 处理尺寸、布局、缩放和阴影优化

**Files:**
- Modify: `scripts/game/layout_config.gd`
- Modify: `scripts/card/card_display_controller.gd`
- Modify: `scripts/card/card_surface.gd`
- Modify: `scenes/card/card_surface.tscn`
- Test: `tests/card_layout_consistency_test.gd`

**目标:** 解决新原型中硬编码坐标、尺寸不同步和悬浮放大影响布局的问题。

- [ ] **Step 1: 单一尺寸来源**

从 `LayoutConfig` 生成：

```gdscript
var card_rect := LayoutConfig.card_view_rect(LayoutConfig.CELL_SIZE)
```

所有以下对象使用同一尺寸：

- Surface 根 Button。
- SubViewport。
- 卡框和插画。
- Shadow。
- CardEntity 碰撞体。
- CombatTagAnchor。

- [ ] **Step 2: 区分逻辑尺寸和视觉尺寸**

- 逻辑碰撞区：保持 1×2 格，供 Board 放置和事件接触使用。
- 视觉卡面：使用 `LayoutConfig.card_view_rect()` 的紧凑矩形。
- 悬浮放大：只改变视觉层或由交互层临时改变 `z_index`，不改变棋盘占格和碰撞形状。

- [ ] **Step 3: 避免缩放改变卡牌布局锚点**

悬浮时：

- `pivot_offset = size * 0.5`。
- 提升 `z_index`，不要通过修改父容器布局位置补偿。
- Hand 的排列逻辑不要把放大后的尺寸重新当作卡牌基础尺寸。
- 拖拽开始时记录原始 transform，结束/取消时恢复。

- [ ] **Step 4: 阴影职责归一**

二选一并全局统一：

1. 阴影作为 Surface 的子节点，跟随 Shader 透视；或
2. 阴影作为 CardView/Content 的子节点，通过屏幕方向偏移同步。

推荐方案：阴影放入 Surface 的合成层，让卡牌翻转时阴影保持在卡面右下；如果视觉设计要求阴影永远是屏幕右下，则保留 `card_view.gd` 的屏幕偏移算法，但不得同时绘制两份阴影。

---

## Task 8: 优化 Shader 与材质生命周期

**Files:**
- Modify: `shaders/card_perspective.gdshader`
- Modify: `scripts/card/card_surface.gd`
- Tests: `tests/card_surface_shader_test.gd`

**目标:** 保证大量卡牌实例下材质独立、参数稳定、无异常裁切。

- [ ] **Step 1: 规范 Shader 参数单位和范围**

统一约定：

```text
fov: 40–55 degrees
x_rot/y_rot: degrees, default 0, max around ±8–12
inset: 0.18–0.25
```

- [ ] **Step 2: 实例级材质复制**

在 Surface `_ready()` 中只复制一次 `ShaderMaterial`，避免每帧复制资源。所有参数写入复制后的材质。

- [ ] **Step 3: 安全边界**

增加或验证：

- `size` 不为零。
- `fov` 被限制在合法范围。
- 旋转参数被 `clampf` 限制。
- 背面剔除不会在正常悬浮角度误删卡面。
- 材质为空时只报一次 warning，不让输入回调抛错。

- [ ] **Step 4: 运行 Shader 回归测试**

测试：

- 中心点为零旋转。
- 四个边角都不超过旋转上限。
- 鼠标离开后回零。
- 两张卡牌修改参数互不影响。
- 卡牌尺寸变化后仍能正常渲染。

---

## Task 9: 迁移和回归验证

**Files:**
- Test: 现有 `tests/card_entity_*`
- Test: `tests/card_surface_*`
- Optional: `tests/card_migration_smoke_test.gd`

- [ ] **Step 1: 运行卡牌单元/场景测试**

至少运行：

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/card_surface_interaction_contract_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/card_texture_tilt_bounds_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/card_entity_controller_composition_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/card_entity_display_mode_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/card_entity_drag_state_sync_test.gd
```

- [ ] **Step 2: 运行完整玩法路径检查**

手动或通过 Godot MCP 验证：

1. 手牌悬浮：卡牌以中心放大，阴影不跳动。
2. 手牌拖拽：新卡面仍可拖到棋盘。
3. 棋盘卡牌：放置后不因视觉放大改变逻辑位置。
4. 商店卡牌：点击购买只发生一次。
5. 宝藏奖励：卡牌预览、选择和确认正常。
6. 右键详情/缩放：返回后原卡牌仍可交互。
7. 多张卡牌同时存在：材质倾斜互不串联。
8. 窗口缩放：卡面、碰撞区和标签仍对齐。

- [ ] **Step 3: 检查日志**

确认没有新增：

- Invalid get index / null material。
- Shader parameter not found。
- Control size 为 0。
- 已释放节点仍被 Controller 访问。
- 重复信号连接或重复购买。

- [ ] **Step 4: 删除旧交互实现**

只有在所有测试通过后：

- 删除 `card2.tscn` 及旧原型引用，或保留一个明确标记为实验/兼容的场景。
- 删除旧 CardView 中重复的 Shader/hover 逻辑。
- 保留 `CardEntity` façade 和 Controller 公开接口。

---

## 推荐执行顺序

```text
1. 固化原型行为测试
2. 提取 CardSurface
3. 嵌入 CardEntity 并行验证
4. 统一输入路由
5. 迁移卡面内容和标签
6. 迁移引用与清理命名
7. 统一尺寸、阴影和布局
8. 优化 Shader/材质生命周期
9. 全量回归后删除旧实现
```

## 迁移完成定义

满足以下条件才算完成：

- 正式玩法仍通过 `CardEntity` 工作，不需要任何系统知道 Button 卡面内部结构。
- 新卡面能够在手牌、棋盘、商店、宝藏和奖励预览中统一显示。
- 悬浮缩放以卡牌中心为轴，倾斜不超过配置范围，鼠标离开后复位。
- 拖拽、旋转、详情、放大、商店购买/回收没有重复触发。
- 卡牌逻辑占格、碰撞区和视觉尺寸互不混淆。
- 多张卡牌的 Shader 参数互相独立。
- 旧 `card2.tscn` 和旧 CardView 交互逻辑不再被正式运行路径使用。
- 关键卡牌测试和至少一条完整游戏流程通过。
