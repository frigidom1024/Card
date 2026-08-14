# Board / BoardZone / BoardEventZone 重构设计

**日期：** 2026-08-13
**最近修订：** 2026-08-14
**状态：** 待用户复审

## 1. 背景

当前 `scripts/game/board.gd` 同时负责卡牌占格、牌链规则、拖拽预览、事件占格、事件节点生命周期和最终业务信号。它仍使用旧 `CardEntity`，而新的常驻 `Shop`、`ShopZone`、`ReclaimZone`、`HandZone` 与 `DraggerLayer` 已使用 `Card` + `CardInstance`。

本次重构将牌桌拆为三个边界明确的组件：

```text
Board
├── BoardZone
└── BoardEventZone
```

- `BoardZone` 只负责卡牌拖拽和卡牌空间。
- `BoardEventZone` 只负责事件空间。
- `Board` 只负责非卡牌拖拽的牌桌业务协调，并保留现有业务接口名称。

游戏页面最终使用以下常驻组件：

```text
GamePage
├── HUD
├── DraggerLayer
├── HandZone
├── Board
│   ├── BoardZone
│   └── BoardEventZone
├── Shop
│   └── ShopZone
└── ReclaimZone
```

## 2. 目标

1. 让新 `Board` 持有 `BoardZone` 和 `BoardEventZone`，但不重新承担二者的空间职责。
2. 让 `BoardZone` 完整兼容当前 `CardZone` 拖拽协议。
3. 保留普通牌链、ROOT、GUIDE、链段回手和事件覆盖的现有业务语义。
4. 将最终牌桌业务信号集中到 `Board`。
5. 删除 `Card.cur_zone`，由 `CardInstance` 成为业务区域、棋盘坐标和逻辑方向的唯一真值源。
6. 让 `DraggerLayer` 从注册区域中解析并缓存拖拽来源，不再读取 `Card.cur_zone`。
7. 保持现有目标先提交、来源后提交的拖拽协议，不新增 finalize 阶段、不 deferred、不增加回滚协议。
8. 迁移现有业务 DTO 和消费者从 `CardEntity` 到 `Card`。
9. 使用新常驻组件重新组装游戏页面。

## 3. 非目标

本次不负责：

- 修改商店定价、补货、刷新或购买规则；
- 修改回收区的金币收益规则；
- 增加 `finalize_drag_target()` 或其他拖拽协议阶段；
- 让 `DraggerLayer` 理解购买、回收、GUIDE、探索或事件业务；
- 在拖拽提交阶段增加 deferred、异步提交或业务回滚；
- 改名现有牌桌业务信号；
- 让 `Board` 重新代理所有空间查询和拖拽接口；
- 修改事件内容选择、随机事件生成、探索进度或事件结算规则；
- 在本次迁移中顺带重构与新组件装配无关的旧系统。

## 4. 架构与依赖方向

```text
GamePage
├── 将 DraggerLayer 注入 HandZone / BoardZone / ShopZone / ReclaimZone
├── 连接 Board.card_return_requested 到唯一回手处理器
├── 回手处理器统一调用 HandZone.add_card(card, true)
└── 将 Board 业务信号连接到现有运行流程

DraggerLayer
├── 只协调 CardZone 拖拽协议
└── 不依赖 Board、Shop 或业务服务

Board
├── 监听 BoardZone 的结构化空间结果
├── 调用 BoardEventZone 查询事件覆盖
├── 发布最终业务信号
└── 不参与 DraggerLayer 注册

BoardZone
├── 依赖 Card / CardInstance / CardZone
├── 管理牌链和卡牌占格
└── 不依赖探索、事件结算、商店或金币服务

BoardEventZone
├── 依赖 BoardEvent / EventInstance
├── 管理事件节点和事件占格
└── 不依赖卡牌拖拽、探索随机算法或事件结算
```

依赖必须保持单向：`Board` 可以读取两个子区域；两个区域不得反向调用 `Board` 的业务方法。区域通过结构化结果或返回值把完成的空间变化交给 `Board`。

## 5. Card 与 CardInstance 的状态所有权

### 5.1 删除 `Card.cur_zone`

`Card` 不再保存业务区域引用：

```gdscript
# 删除
var cur_zone: CardZone
```

`Card` 只保留视觉与交互引用：

```gdscript
var card_inst: CardInstance
var drag_layer: DraggerLayer

func bind_card_inst(value: CardInstance) -> void
func get_card_inst() -> CardInstance
func refresh_display() -> void
```

`Card` 的父节点、祖先节点、`position` 和 `rotation_degrees` 仅表示当前场景结构与视觉状态，不能作为持久业务状态保存。

### 5.2 CardInstance 是唯一业务真值源

```gdscript
enum ZONE {
    DRAW,
    HAND,
    BOARD,
    DISCARD,
    SHOP,
}

var cur_zone: ZONE
var battlefield_pos := Vector2i(-1, -1)
var direction: int = 0
```

移除未使用的 `ZONE.DRAGLAYER`，增加 `ZONE.SHOP`。

区域提交成功后的状态规则：

| 区域 | `cur_zone` | `battlefield_pos` | `direction` |
|---|---|---|---|
| `HandZone` | `HAND` | `(-1, -1)` | 保持业务定义；从棋盘回手时重置为 `0` |
| `ShopZone` | `SHOP` | `(-1, -1)` | `0` |
| `BoardZone` | `BOARD` | 放置锚点 | 已提交的逻辑方向 |
| `ReclaimZone` | `DISCARD` | `(-1, -1)` | `0` |

`CardInstance.direction` 是逻辑真值，`Card.rotation_degrees` 是视觉状态。拖拽旋转期间只改变视觉方向；`BoardZone` 成功提交后才写入新的逻辑方向。取消拖拽时，来源区使用开始拖拽时保存的 `CardInstance.direction` 恢复视觉方向。

### 5.3 实例绑定与显示刷新

所有可交互 `Card` 必须绑定精确 `CardInstance`：

```gdscript
card.bind_card_inst(card_inst)
```

禁止用卡牌数据重新创建一个替代实例。任何替换绑定实例或修改显示相关实例数据的代码，必须调用：

```gdscript
card.refresh_display()
```

刷新至少包括：

- 当前点数标签 `current_points`；
- 当前护甲标签 `current_armor`；
- `CardData.artwork_path` 对应的卡图。

区域只更新位置、区域、棋盘坐标或方向时不需要重载卡图；但新建卡牌、替换 `CardInstance` 或更新上述显示数据后必须刷新。

## 6. CardZone 所有权协议

`CardZone` 增加：

```gdscript
func owns_card(card: Card) -> bool:
    return false
```

每个具体区域按自身稳定成员集合实现该方法：

- `HandZone` 查询手牌集合；
- `BoardZone` 查询牌链集合；
- `ShopZone` 查询商品槽；
- `ReclaimZone` 不长期持有卡牌，通常返回 `false`。

`owns_card()` 表示“该区域当前是否拥有这张卡的成员资格”，不能只比较 `CardInstance.cur_zone`。同一张卡在稳定状态下最多只能被一个已注册区域拥有。

拖拽开始后，来源区会暂时撤销原成员资格，因此拖拽期间 `owns_card()` 可以返回 `false`。`DraggerLayer` 必须在此之前缓存来源。

## 7. DraggerLayer 来源解析与原子拖拽

### 7.1 来源解析

`DraggerLayer` 增加：

```gdscript
var _drag_source: CardZone
```

开始拖拽时：

1. 遍历有效的 `_registered_zones`；
2. 收集 `owns_card(card) == true` 的区域；
3. 恰好一个匹配时，将其缓存为 `_drag_source`；
4. 没有匹配时允许以无来源卡牌继续，由目标区决定是否接受；
5. 多个匹配表示区域所有权损坏，报告错误并拒绝开始拖拽；
6. 在来源仍拥有稳定成员资格时执行 `source.can_trans_from_source(card)`；
7. 通过后调用 `source.start_drag(card)`。

拖拽结束前不得重新解析来源，也不得根据父节点或 `CardInstance.cur_zone` 替换 `_drag_source`。

### 7.2 现有协议保持不变

提交顺序保持：

```gdscript
target.drag_end_target(card, true)
source.drag_end_source(card, true)
```

合法性检查在提交前完成：

```gdscript
target.can_trans_to_target(card)
source.can_trans_from_source(card)
```

整个同步调用视为一个原子拖拽事务：

- 预检查通过后，各区域的正常提交路径必须可完成；
- 目标先完成空间与实例状态提交；
- 随后来源完成自己的来源事务；
- 不增加 deferred；
- 不增加 finalize；
- 不设计跨区域回滚；
- 异常只作为内部一致性错误报告，不作为普通业务分支。

当来源和目标是同一区域时，也必须依次执行目标提交和来源提交。来源提交负责清理开始拖拽时的事务快照，不能跳过。

### 7.3 来源区事务语义

`start_drag(card)` 不再只是视觉通知。来源区必须：

1. 保存卡牌原成员位置、视觉状态和必要的业务状态快照；
2. 暂时从稳定成员集合中撤销该卡的原成员资格；
3. 保留 `CardInstance` 的原业务状态，直到目标提交或取消；
4. 让 `can_trans_from_source(card)` 在活动来源事务期间仍返回 `true`。

成功来源提交：

```gdscript
source.drag_end_source(card, true)
```

只完成开始拖拽时的来源事务，不得根据卡牌当前父节点、新区域或新成员资格再次删除卡牌。其主要职责是：

- 丢弃原成员快照；
- 完成来源特有结算，例如商店购买信号；
- 完成 Board 牌桌侧链段分离并发布待回手后继卡清单；
- 清理来源预览与事务状态。

取消来源提交：

```gdscript
source.drag_end_source(card, false)
```

使用快照恢复原成员位置、原视觉状态和原实例状态。

这项语义保证：目标同步提交后，即使卡牌已经被重新加入同一个 `HandZone`，来源提交也不会把新成员资格误删。

## 8. BoardZone

### 8.1 职责

`BoardZone` 只负责卡牌空间和卡牌拖拽：

- 卡牌占格与网格索引；
- ROOT / NORMAL 牌链合法性；
- 拖拽预览；
- 卡牌放置、移动与取消；
- GUIDE 引起的牌链空间移动；
- 玩家把棋盘牌拖回手牌时，从牌桌成员和网格中分离对应链段，并生成待回手后继卡清单；
- 更新仍属于牌桌的受影响 `CardInstance` 的 `cur_zone`、`battlefield_pos` 和 `direction`；
- 提供战斗牌链查询。

`BoardZone` 不负责：

- 探索计数；
- 事件结算；
- GUIDE 或链段后继卡的回手业务请求；
- 直接查找、调用或写入 `HandZone`；
- 链回手费用；
- 商店购买或回收收益；
- 最终 `BoardPlacementResult` 或 `ChainRetractionTransaction` 的发布。

### 8.2 公开空间接口

```gdscript
func owns_card(card: Card) -> bool
func add_card(card: Card, keep_global_position: bool = true) -> bool
func remove_card(card: Card) -> bool
func get_cards() -> Array[Card]
func get_card_cells(card: Card) -> Array[Vector2i]
func get_card_at(cell: Vector2i) -> Card
func get_placement_cell(card: Card) -> Vector2i
func can_place_card(card: Card, exclude_card: Card = null) -> bool
func get_combat_card_chain() -> Array[CardInstance]
```

保留 `CardZone` 拖拽协议方法。`set_drag_layer()` 仍可作为装配入口存在于 `BoardZone`，但不由 `Board` 代理。

### 8.3 结构化空间结果

新增：

```gdscript
class_name BoardCardPlacement
extends RefCounted

enum Kind {
    CHAIN_EXTENDED,
    GUIDE_SHIFTED,
}

var card: Card
var card_inst: CardInstance
var kind: Kind
var occupied_cells: Array[Vector2i]
var affected_cards: Array[Card]
var chain_tail: Card
```

新增：

```gdscript
class_name BoardCardRetraction
extends RefCounted

var removed_card: Card
var followers_to_return: Array[Card]
var original_chain_size: int
```

`BoardZone` 发布：

```gdscript
signal placement_applied(operation: BoardCardPlacement)
signal chain_segment_detached(operation: BoardCardRetraction)
```

这些信号只说明牌桌侧空间事务已经完成，不代表探索、事件、回手费用或其他业务已经结算。`chain_segment_detached` 发出时，`followers_to_return` 已离开牌桌稳定成员和网格，但尚未保证已进入手牌。

`BoardZone` 不发布：

```gdscript
placement_committed
card_return_requested
chain_retraction_confirmed
```

### 8.4 普通牌放置

合法 ROOT / NORMAL 目标提交完成后：

1. 卡牌进入 `BoardZone` 稳定成员集合；
2. 更新网格占用；
3. 吸附视觉位置；
4. 根据提交时视觉旋转写入 `CardInstance.direction`；
5. 写入 `cur_zone = BOARD` 和 `battlefield_pos`；
6. 构造 `BoardCardPlacement.Kind.CHAIN_EXTENDED`；
7. 清理目标预览；
8. 以 `placement_applied` 作为提交方法的最后一个业务动作同步发布结果。

信号发出后，目标提交不得再次改写、删除或重新父子化操作中的卡牌，因为同步监听器可能已经移动它。

### 8.5 棋盘来源事务与链段回手

开始从棋盘拖拽时，`BoardZone` 保存：

- 原牌链索引；
- 原牌链大小；
- 被拖卡及其后继卡；
- 每张受影响卡的占格、视觉变换、`battlefield_pos` 和 `direction`。

同时暂时从活动牌链与网格占用中撤销被拖卡和后继段，使目标提交后的来源完成不需要再次删除当前卡牌。

若取消，按快照完整恢复牌链顺序、占格、视觉和实例状态。

若目标是 `HandZone`：

1. `HandZone.drag_end_target(card)` 先通过正常目标提交接收被拖卡，并内部复用统一的 `add_card()` 成员接收逻辑；
2. `BoardZone.drag_end_source(card, true)` 只提交原牌桌来源事务，从牌桌稳定成员和网格中永久释放被拖卡及其后继段；
3. 被拖卡已由目标提交处理，不加入 `followers_to_return`，避免 `Board` 重复请求回手；
4. 后继卡按原牌链顺序写入 `BoardCardRetraction.followers_to_return`；
5. `BoardZone` 可清除后继卡已经失效的 `battlefield_pos`，但不得直接写入 `cur_zone = HAND`、重置最终手牌方向或重新父子化到 `HandZone`；
6. 发布 `chain_segment_detached`，再清理原牌桌来源事务。

`chain_segment_detached` 的同步监听链由 `Board` 负责把每张后继卡交给统一回手处理器。同步事务内部允许卡牌短暂处于“已从 Board 分离、尚未由 Hand 接收”的过渡状态；信号处理返回后，每张后继卡必须由 `HandZone.add_card()` 写入 `cur_zone = HAND`、`battlefield_pos = (-1, -1)`、`direction = 0` 并建立稳定手牌成员资格。

若目标是同一个 `BoardZone`，目标提交建立新的牌链成员资格和占格；随后的来源提交只能丢弃旧快照，不得删除新放置，也不得发布 `chain_segment_detached`。

`ReclaimZone` 只接受 `CardInstance.cur_zone == HAND` 的卡，因此棋盘卡不能绕过先回手的规则直接回收。

## 9. GUIDE 语义与同步时序

### 9.1 必须保留的业务语义

GUIDE 合法放置时：

1. GUIDE 覆盖当前链尾连接位置；
2. GUIDE 不成为牌链稳定成员；
3. GUIDE 推动或替换现有牌链布局；
4. 受影响牌链卡更新占格、`battlefield_pos` 和逻辑方向；
5. 最终发布 `BoardPlacementResult.Kind.GUIDE_RESOLVED`；
6. 随后发布 `card_return_requested`；
7. GUIDE 不推进普通探索刷新计数；
8. GUIDE 自动回手不属于玩家主动链回收，不发布 `chain_retraction_confirmed`，也不触发链回手费用。

### 9.2 职责分配

```text
BoardZone
├── 识别 GUIDE 空间模式
├── 移动现有牌链
├── 更新受影响 CardInstance
└── placement_applied(GUIDE_SHIFTED)

Board
├── 查询 GUIDE 覆盖事件
├── 构造 GUIDE_RESOLVED
├── placement_committed
└── card_return_requested

GamePage/运行流程
└── 唯一回手处理器调用 HandZone.add_card(card, true)
```

### 9.3 同步原子顺序

GUIDE 的目标提交顺序为：

```text
BoardZone.drag_end_target
  → 完成牌链空间变化
  → 清理目标预览
  → BoardZone.placement_applied(GUIDE_SHIFTED)
    → Board 构造 BoardPlacementResult
    → Board.placement_committed
    → Board.card_return_requested(GUIDE)
      → GamePage/运行流程调用 HandZone.add_card(GUIDE, true)
      → Board 验证 GUIDE 的 CardInstance.cur_zone == HAND
  → BoardZone.drag_end_target 返回 true
DraggerLayer
  → 原来源 drag_end_source(card, true)
```

GUIDE 与牌链拆除产生的后继卡共享同一个 `card_return_requested` 监听器和同一个 `HandZone.add_card()` 接收入口。两者的最终 `HAND` 状态、无效棋盘坐标清理、逻辑方向重置、父子关系和手牌布局刷新都由 `HandZone` 统一完成。

来源事务规则解决两种情况：

- **Hand → Board GUIDE：** 原 `HandZone` 成员资格已在 `start_drag()` 暂时撤销，因此同步回手可以安全建立新的手牌成员资格；随后来源提交只清理旧快照。
- **Shop → Board GUIDE：** 同步回手先把 GUIDE 放入 `HandZone`；随后 `ShopZone` 来源提交仍完成购买信号、扣费、精确实例注册和该槽补货，但不得删除已经进入手牌的卡牌。

目标信号监听器是同步的。`BoardZone` 发出 `placement_applied` 后不得继续假定 GUIDE 的父节点仍是 `BoardZone`。

若 `card_return_requested` 没有有效监听器，或同步处理返回后 GUIDE 仍未进入 `HAND`，这是场景装配或内部一致性错误；不得让 `BoardZone` 静默把 GUIDE 留为牌链成员。

## 10. BoardEventZone

### 10.1 职责

新增：

```text
scenes/zone/board_event_zone.tscn
scripts/zone/board_event_zone.gd
```

`BoardEventZone` 负责：

- 持有事件节点；
- 事件占格索引；
- 事件外围缓冲格；
- 添加、移动和删除的空间合法性；
- 根据卡牌占格查询未解决事件；
- 更新 `EventInstance.origin` 和事件节点视觉位置。

它不负责：

- 选择事件内容；
- 随机生成位置；
- 探索进度；
- 事件触发时机；
- 事件结算或弹窗。

### 10.2 网格对齐

`BoardEventZone` 与 `BoardZone` 在 `board.tscn` 中覆盖同一棋盘矩形。二者必须使用同一个网格几何来源，包括：

- 网格原点；
- `cell_size`；
- `width`；
- `height`。

实现时由 `BoardEventZone` 引用场景内现有 `BoardZoneBG` 作为只读网格几何来源，避免复制一套可能漂移的宽、高和格子尺寸。事件节点的位置通过该共享几何转换到 `BoardEventZone` 本地坐标。

`Board._ready()` 验证 `board_zone`、`event_zone` 和共享网格引用完整；装配错误应明确报告，而不是使用另一套默认尺寸继续运行。

### 10.3 公开空间接口

```gdscript
func can_attach_event(instance: EventInstance) -> bool
func attach_event(event_node: BoardEvent) -> bool
func move_event(event_node: BoardEvent, target_origin: Vector2i) -> bool
func remove_event(event_node: BoardEvent) -> bool

func get_event_cells(
    origin: Vector2i,
    event_size: Vector2i
) -> Array[Vector2i]

func get_event_buffer_cells(
    origin: Vector2i,
    event_size: Vector2i
) -> Array[Vector2i]

func get_overlapping_unresolved_event(
    card_cells: Array[Vector2i]
) -> EventInstance
```

`attach_event()` 只接受：

- 有有效 `EventInstance` 的 `BoardEvent`；
- 完整位于棋盘边界内的占格；
- 不与已有事件占格或缓冲规则冲突的位置；
- 尚未被本区域持有的事件节点。

失败不能留下半写入的事件索引、父节点关系或 `origin`。

## 11. Board

### 11.1 最小职责

目标类：

```gdscript
class_name Board
extends Node

@export var board_zone: BoardZone
@export var event_zone: BoardEventZone
```

`Board` 负责：

- 验证和连接两个子区域；
- 监听 `BoardZone.placement_applied`；
- 构造 `BoardPlacementResult`；
- 通过 `BoardEventZone` 查询放置覆盖的事件；
- 保留 GUIDE 业务语义并发布统一回手请求；
- 监听 `BoardZone.chain_segment_detached`；
- 按原牌链顺序为后继卡发布统一回手请求；
- 在所有后继卡同步进入手牌后构造 `ChainRetractionTransaction`；
- 对事件节点生命周期发布最终业务信号。

`Board` 不负责：

- 卡牌拖拽预览；
- 注册 `DraggerLayer`；
- 卡牌占格；
- 事件占格实现；
- 事件随机放置；
- 探索或事件结算；
- 商店或回收业务。

### 11.2 保留的业务信号

```gdscript
signal placement_committed(result: BoardPlacementResult)
signal card_return_requested(card: Card)
signal chain_retraction_confirmed(transaction: ChainRetractionTransaction)
signal event_triggered(instance: EventInstance)
signal event_attached(event_node: BoardEvent)
signal event_removed(event_node: BoardEvent)
```

`placement_committed` 是卡牌放置的权威业务结果。`card_placed` 与其重复，迁移后删除。

`event_triggered` 保留名称用于兼容旧连接，但卡牌放置路径不直接发出它。权威事件接触仍记录在 `BoardPlacementResult.overlapped_event`，由 `PlacementPipelineCoordinator` 发布事件交互请求，避免双重触发。待旧连接全部迁移后，可在独立任务中移除该兼容信号。

### 11.3 公开业务入口

```gdscript
func attach_event(event_node: BoardEvent) -> bool
func move_event(event_node: BoardEvent, target_origin: Vector2i) -> bool
func remove_event(event_node: BoardEvent) -> bool
```

这些方法调用 `BoardEventZone`。只有区域操作成功后，`Board` 才分别发出 `event_attached` 或 `event_removed`。`move_event()` 保留现有名称和返回值，不新增重复业务信号。

`Board` 不代理以下空间或拖拽方法：

```gdscript
set_drag_layer()
add_card()
remove_card()
get_cards()
get_card_cells()
can_place_card()
get_combat_card_chain()
world_to_grid()
grid_to_world_center()
preview_card()
clear_preview()
get_event_cells()
get_event_buffer_cells()
can_attach_event()
get_overlapping_unresolved_event()
```

需要卡牌空间的消费者依赖 `BoardZone`；需要事件空间的消费者依赖 `BoardEventZone`。保留业务接口名称不等于继续让 `Board` 代理所有旧空间接口。

### 11.4 Placement 结果转换

保留现有枚举与字段名称，但类型迁移到 `Card`：

```gdscript
class_name BoardPlacementResult
extends RefCounted

enum Kind {
    CHAIN_EXTENDED,
    GUIDE_RESOLVED,
}

var kind: Kind
var source_card: Card
var chain_tail: Card
var affected_cards: Array[Card]
var newly_occupied_cells: Array[Vector2i]
var overlapped_event: EventInstance
```

转换规则：

| `BoardCardPlacement.Kind` | `BoardPlacementResult.Kind` |
|---|---|
| `CHAIN_EXTENDED` | `CHAIN_EXTENDED` |
| `GUIDE_SHIFTED` | `GUIDE_RESOLVED` |

`Board` 使用 `operation.occupied_cells` 查询 `BoardEventZone.get_overlapping_unresolved_event()`，把结果写入 `overlapped_event`。`Board` 不直接解决事件。

`PlacementPipelineCoordinator` 继续只监听：

```gdscript
board.placement_committed
```

它保持现有顺序：卡牌规则、探索处理、事件交互请求。

目标先提交、来源后提交意味着从商店拖出的卡牌会先发布目标侧放置结果，再在同一同步拖拽调用中完成购买注册和扣费。目标侧监听器不得假定 `RunCardService` 已经完成商店来源结算；该结算保证在本次 `DraggerLayer.end_drag()` 返回前完成。

## 12. 链回手事务

`ChainRetractionTransaction` 保留名称和字段，类型迁移到 `Card`：

```gdscript
class_name ChainRetractionTransaction
extends RefCounted

var removed_card: Card
var returned_followers: Array[Card]
var original_chain_size: int
```

流程：

```text
HandZone.drag_end_target(removed_card)
→ 被玩家拖动的卡通过正常目标提交进入 HandZone

BoardZone.drag_end_source(removed_card, true)
→ 完成原牌桌成员与网格清理
→ 构造 BoardCardRetraction(followers_to_return)
→ BoardZone.chain_segment_detached
  → Board 按原牌链顺序逐张发出 card_return_requested(follower)
    → GamePage/运行流程调用 HandZone.add_card(follower, true)
  → Board 验证每张 follower 的 CardInstance.cur_zone == HAND
  → Board 构造 ChainRetractionTransaction(returned_followers)
  → Board.chain_retraction_confirmed
  → 外部 CardRetractionCostService 等业务消费者处理费用
```

被玩家直接拖动的 `removed_card` 不再由 `Board` 发出 `card_return_requested`，避免重复加入手牌或覆盖目标提交确定的手牌位置。它与后继卡最终都必须经过 `HandZone` 的统一成员接收实现：前者由标准拖拽目标提交调用，后者由统一回手处理器调用。

`Board` 对全部 `followers_to_return` 发出同步回手请求后，只有每张卡都已进入 `HAND`，才把同一批卡写入兼容字段 `ChainRetractionTransaction.returned_followers` 并发布 `chain_retraction_confirmed`。`Board` 不计算或扣除费用。GUIDE 自动回手使用相同的 `card_return_requested` 通道，但不构造链回手事务、不发布 `chain_retraction_confirmed`。

原先监听旧 `DragLayer.chain_retraction_confirmed` 的新页面业务接线迁移到 `Board.chain_retraction_confirmed`。旧 `DragLayer` 保持在旧页面迁移边界内，直至旧组件退出。

## 13. 探索与事件边界

探索系统负责决定：

- 生成哪个 `EventInstance`；
- 候选位置；
- 随机选择；
- 何时尝试添加事件。

`BoardEventZone` 只回答空间问题。`EventPlacementService` 的候选扫描改为读取：

```gdscript
board.event_zone
```

并调用 `BoardEventZone` 的宽高、事件格和合法性查询。选定位置并创建 `BoardEvent` 后，仍通过业务入口：

```gdscript
board.attach_event(event_node)
```

这样保留 `Board.attach_event()` 名称，同时避免把 `get_event_cells()`、`can_attach_event()` 等空间方法重新代理到 `Board`。

卡牌放置覆盖事件时：

```text
BoardZone.placement_applied
→ Board 查询 BoardEventZone
→ BoardPlacementResult.overlapped_event
→ Board.placement_committed
→ PlacementPipelineCoordinator
→ event_interaction_requested
```

`Board` 和 `BoardEventZone` 都不直接打开事件界面或结算事件。

## 14. 游戏页面装配

活跃游戏页面不再同时装配旧 `Board`/`DragLayer` 与新区域体系。目标装配顺序：

1. 创建 `DraggerLayer`；
2. 创建 `HandZone`；
3. 创建 `Board`，其场景内包含 `BoardZone` 和 `BoardEventZone`；
4. 创建常驻 `Shop`/`ShopZone`；
5. 创建常驻 `ReclaimZone`；
6. 将同一个 `DraggerLayer` 注入并注册所有可交互 `CardZone`；
7. 将各区域现有卡牌绑定同一个 `DraggerLayer`；
8. 连接 `Board.card_return_requested` 到唯一同步回手处理器，该处理器只调用 `HandZone.add_card(card, true)`；
9. 连接 `Board.placement_committed` 到 `PlacementPipelineCoordinator`；
10. 连接 `Board.chain_retraction_confirmed` 到链回手费用服务；
11. 连接事件添加/删除信号到需要的界面或运行流程；
12. 最后生成初始手牌、商店库存、ROOT 和事件，避免生成时区域尚未完成接线。

`Board.card_return_requested → HandZone.add_card(card, true)` 是 GUIDE 和牌链后继卡自动回手的唯一页面接线。页面不得分别实现 GUIDE 专用回手和链段专用回手，也不得让 `BoardZone` 获取 `HandZone` 引用。

`HUD` 只保留展示职责，不再直接拥有独立 `BoardZone`。`Board` 场景是 `BoardZone` 与 `BoardEventZone` 的唯一牌桌组合入口。

## 15. 错误处理与不变量

### 15.1 必须满足的不变量

1. 稳定状态下，一张 `Card` 最多被一个注册 `CardZone` 拥有。
2. 每张区域卡牌都有有效且精确绑定的 `CardInstance`。
3. `CardInstance.cur_zone` 与成功提交后的区域业务状态一致。
4. 只有 `BoardZone` 写入有效 `battlefield_pos`。
5. 拖拽视觉旋转在提交前不改写逻辑方向。
6. 目标提交后，来源提交不能删除目标建立的新成员资格。
7. GUIDE 永远不成为稳定牌链成员。
8. `BoardZone` 的网格索引与牌链成员集合一致。
9. `BoardEventZone` 的事件索引与事件节点集合一致。
10. `BoardPlacementResult` 只在完整空间提交后发布。
11. `ChainRetractionTransaction` 只在全部待回手后继卡已进入手牌后发布。
12. GUIDE 和链段后继卡的自动回手只经过 `Board.card_return_requested → HandZone.add_card()`。
13. 被玩家直接拖动的棋盘卡只由 `HandZone` 目标提交接收一次，不再由 `Board` 重复请求回手。
14. 购买、回收、放置和回手继续使用同一个 `CardInstance`，不得复制实例。

### 15.2 失败处理

- 预校验失败：目标取消预览，来源按快照恢复。
- 来源所有权重复：拒绝开始拖拽并报告错误。
- 缺少 `CardInstance`：区域拒绝卡牌。
- 缺少 `BoardZone`、`BoardEventZone` 或共享网格：`Board` 报告场景装配错误，不静默创建替代状态。
- 目标提交在通过预校验后仍失败：报告内部一致性错误，并执行现有取消通知；不引入新回滚协议。
- 统一回手信号无人处理：报告场景装配错误；GUIDE 和链段后继卡都不得退回到牌桌稳定成员。
- 同步回手请求结束后 `CardInstance.cur_zone != HAND`：报告内部一致性错误；链回手不得发布 `chain_retraction_confirmed`，但不新增回滚协议。
- 事件添加或移动失败：不得留下部分网格占用、错误父节点或错误 `origin`。

## 16. 迁移范围

预计涉及：

### 新增

```text
scenes/zone/board_event_zone.tscn
scripts/zone/board_event_zone.gd
scripts/game/board_card_placement.gd
scripts/game/board_card_retraction.gd
```

### 重构

```text
scenes/game/board.tscn
scripts/game/board.gd
scenes/zone/board_zone.tscn
scripts/zone/board_zone.gd
scripts/zone/card_zone.gd
scripts/game/drag_layer/dragger_layer.gd
scenes/card/card.gd
scripts/card/card_instance.gd
scripts/zone/handzone.gd
scripts/zone/shop_zone.gd
scripts/zone/reclaim_zone.gd
scripts/game/board_placement_result.gd
scripts/game/chain_retraction_transaction.gd
scripts/game/event/core/event_placement_service.gd
scripts/game/placement/placement_pipeline_coordinator.gd
```

### 页面装配与消费者

迁移活跃游戏页面、运行流程和测试中对以下旧接口的引用：

- `Card.cur_zone`；
- 旧 `CardEntity` 牌桌类型；
- `Board` 的空间代理接口；
- 旧 `DragLayer.chain_retraction_confirmed`；
- HUD 内直接持有的 `BoardZone`；
- 旧 Board 事件网格字段。

迁移应完整删除生产代码和新体系测试中的 `Card.cur_zone` 引用。旧页面若仍需短期保留，应与新页面入口隔离，不能同时驱动同一局运行状态。

## 17. 测试策略

### 17.1 Card / CardInstance

- `Card` 不再暴露 `cur_zone`；
- `CardInstance.ZONE` 包含 `SHOP` 且不包含 `DRAGLAYER`；
- `bind_card_inst()` 后点数、护甲和图片正确刷新；
- 修改显示数据并调用 `refresh_display()` 后标签和图片更新。

### 17.2 DraggerLayer 与所有权

- 从唯一 `owns_card()` 区域解析并缓存来源；
- 多区域重复拥有时拒绝拖拽；
- 目标提交改变父节点或实例区域后，来源仍使用缓存引用；
- 同区拖拽也执行目标提交和来源提交；
- 取消时来源快照完整恢复；
- 旋转卡牌仍使用视觉中心做命中检测。

### 17.3 Hand / Shop / Reclaim

- Hand → Hand 重排不会被来源提交二次删除；
- Hand → Board 普通牌正确移交；
- Hand → Board GUIDE 同步回手后仍在 Hand；
- Shop → Board 普通牌保持精确实例并在来源提交后扣费、注册、补货；
- Shop → Board GUIDE 回手、购买、注册和补货各执行一次；
- Hand → Reclaim 只回收一次并进入 `DISCARD`；
- Board 卡不能直接进入 Reclaim。

### 17.4 BoardZone

- ROOT 只能建立空牌桌；
- NORMAL 只能连接链尾；
- 中间牌不能在棋盘内非法重排；
- 取消拖拽恢复牌链、占格、方向和坐标；
- 成功放置更新唯一 `CardInstance` 状态；
- GUIDE 正确移动牌链且不进入成员集合；
- 链段拆除按原顺序产出全部 `followers_to_return`；
- `BoardZone` 不依赖、查找或调用 `HandZone`；
- `placement_applied` 和 `chain_segment_detached` 各只发出一次。

### 17.5 BoardEventZone

- 事件占格、边界和缓冲格规则与旧 Board 一致；
- 添加、移动、删除失败不污染索引；
- 事件节点使用共享网格正确定位；
- 只返回与卡牌格重叠且未解决的事件。

### 17.6 Board 业务

- 普通空间结果转换为 `CHAIN_EXTENDED`；
- GUIDE 空间结果转换为 `GUIDE_RESOLVED`；
- `overlapped_event` 正确写入结果；
- GUIDE 信号顺序为 `placement_committed` 后 `card_return_requested`；
- GUIDE 与链段后继卡使用同一个同步回手处理器；
- 后继卡按原牌链顺序逐张请求回手，每张只加入 `HandZone` 一次；
- 被玩家直接拖动的卡不会被 `Board` 重复请求回手；
- 全部后继卡进入 `HAND` 后才发布 `chain_retraction_confirmed`；
- `event_attached` / `event_removed` 只在区域成功后发出；
- 卡牌放置不直接重复发出 `event_triggered`。

### 17.7 集成与页面

- 新页面只存在一个活跃 `DraggerLayer`；
- Hand、Board、Shop、Reclaim 全部注册；
- 所有可见卡牌绑定同一拖拽层；
- 初始 ROOT、普通牌、商店购买、GUIDE、链回手和回收形成完整闭环；
- PlacementPipeline、事件交互和费用服务各只收到一次业务通知；
- 场景与 GDScript 全量验证无解析错误；
- 旧接口迁移后相关测试全部更新并通过。

## 18. 验收标准

1. 活跃游戏页面使用新的常驻 Hand、Board、Shop、Reclaim 组件。
2. `Board` 只协调非卡牌拖拽业务，不再包含卡牌或事件网格实现。
3. `BoardZone` 和 `BoardEventZone` 可以独立测试。
4. `Card.cur_zone` 已从新体系删除，状态只保存在 `CardInstance`。
5. GUIDE 从 Hand 和 Shop 出发都能同步回手，且来源提交不误删卡牌。
6. GUIDE 与链段自动返回的后继卡统一经 `Board.card_return_requested → HandZone.add_card()` 回手，`BoardZone` 不直接依赖 `HandZone`。
7. 普通商店购买、回收、牌桌放置和链回手继续使用精确实例。
8. 卡牌实例更新后数值标签和图片正确刷新。
9. 现有业务信号名称保持兼容，重复的 `card_placed` 除外；`chain_segment_detached` 是新的内部空间信号。
10. 不新增拖拽 finalize、deferred 或回滚协议。
11. 所有迁移后的单元与集成测试通过。
