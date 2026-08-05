# 迷雾探索与 Boss 追击 / 拦截设计记录

日期：2026-08-05

## 核心决策

1. 地图初始化时不创建全部事件。玩家成功放置卡牌后揭开迷雾，再由当前关卡的 `EventLib` 生成事件。
2. ROOT 放置后揭开以 ROOT 左上角为起点的 2×2 区域；普通卡牌揭开其占用格及周边相邻区域。
3. 第一关普通事件按探索进度生成；揭开 24 格后生成 Boss。若当前位置无法放置 Boss，保留待生成状态，在下一次揭雾时继续尝试。
4. Boss 追击是关卡级可配规则：`ExplorationConfig.boss_pursuit_enabled` 控制启用与否，而不是全局硬编码。
5. 无论追击是否开启，Boss 与普通事件都只能在**卡牌放置后发生格子重叠**时触发；不提供点击事件圈直接开战的入口。

## “顶部”定义

这里的“顶部”不是屏幕视觉上的上方，而是**最后一张卡牌头部朝向的连接格**：

- 方向 0：卡牌朝上，连接格为卡牌上方一格；
- 方向 1：卡牌朝右，连接格为卡牌右方一格；
- 方向 2：卡牌朝下，连接格为卡牌下方一格；
- 方向 3：卡牌朝左，连接格为卡牌左方一格。

必须统一调用 `Board.get_placement_cell()` 计算此格；Boss 追击逻辑不得复制方向计算。

## Boss 追击配置与阶段

`ExplorationConfig` 定义以下关卡数据：

```gdscript
@export var boss_pursuit_enabled := true
@export_range(1, 99, 1) var cards_to_boss_surround := 2
@export_range(1, 99, 1) var cards_to_boss_intercept := 2
```

- **关闭追击**：Boss 到达 `boss_reveal_threshold` 后照常生成，保持生成位置，行为与普通 Boss 事件一致；玩家将卡牌放到 Boss 占格时进入战斗。
- **开启追击**：Boss 生成后，每成功延长一次普通牌链计数一次。经过 `cards_to_boss_surround` 次后进入 `SURROUNDING` 并移动到牌链周边；再经过 `cards_to_boss_intercept` 次后进入 `INTERCEPTING`，移动到牌头连接格。
- GUIDE 是空间重排而非牌链延长：可揭雾、可接触事件，但不增加追击计数。

## Boss 是普通事件的硬约束

Boss 不是另一套地图交互对象。它只是一张 `EventData.EventType.BOSS` 模板创建出的普通 `EventInstance`，并由通常的 `BoardEvent` 显示。

- **追击服务唯一的权限**：通过 `Board.move_event(boss_event, target_origin)` 修改 Boss 事件的格子位置；
- **触发**：沿用卡牌放置产生的 `BoardPlacementResult.overlapped_event`；
- **交互**：沿用协调器的 `event_interaction_requested(instance)` 与既有 `EventInteractionController.begin()`；
- **胜利 / RETREAT**：沿用现有事件结算、移除和残响强化逻辑；
- **禁止项**：没有 Boss 点击入口、没有 Boss 专用事件控制器、没有 Boss 专用战斗启动信号、没有与普通事件不同的重叠判定。

`INTERCEPTING` 仅描述 Boss 的**位置状态**，不能泄漏为事件系统的行为分支。

## Boss 占格与拦截

`INTERCEPTING` 不是旧设计中的“硬阻塞”。其目标格仍然是最后一张牌的头部连接格，但该格必须继续允许下一张合法卡牌占用：

```text
Boss 移到牌头连接格
→ 玩家放置下一张连接牌
→ 放牌结构提交
→ 揭雾 / 动态事件生成
→ 识别到本次已接触 Boss，跳过 Boss 追击推进
→ 该卡与 Boss 重叠，自动发起 Boss 战
```

因此：

- Boss 可以在视觉和事件数据层占有该格；
- Boss **不得**写入 `Board.can_place_card()` 检查的禁止放牌占格表；
- `Board.add_card()` 只记录 `overlapped_event`，不直接开始战斗；
- `ExplorationCoordinator` 在放牌事务完成后统一请求事件交互；若本次接触的是 Boss，必须先跳过 Boss 推进，防止 Boss 在战斗开始前移动；
- 本次揭雾新生成的 Boss 从零计数开始，不能消耗生成它的这次放牌；
- Boss 胜利时，协调器移除 Boss 事件节点和事件占格并释放其所在格；
- Boss 未被击败 / `CombatResult.Outcome.RETREAT` 时，事件保留并沿用既有残响强化规则。

这既保留了“Boss 压住牌链去路”的紧迫感，也不引入与所有其他事件相矛盾的鼠标点击交互。

## 代码职责

- `FogService`：只管理已揭开格子和本次新增揭雾结果。
- `ExplorationEventService`：只负责根据揭雾进度从当前关卡事件库生成事件。
- `BossPressureService`：只负责 Boss 出现后的放牌计数、周边阶段、拦截阶段与配置开关；它唯一的副作用是调用 `Board.move_event()` 改变 Boss 的位置。其阶段枚举使用 `HIDDEN`、`ACTIVE`、`SURROUNDING`、`INTERCEPTING`。
- `Board`：只负责格子占用、事件空间重叠和卡牌放置合法性；不处理可点击事件，不处理战斗。
- `ExplorationCoordinator`：编排“放牌提交 → 揭雾 → 动态事件 → 仅推进既有且未被接触的 Boss → 接触事件请求”。
- `EventInteractionController`：只处理已请求的商店、宝藏和战斗生命周期。
- `GameManager`：只组装运行时对象、连接场景和更新视图层。

代码名称不使用此前被否定的“诅咒”“潮边”等函数、字段或枚举；未击杀遭遇仍使用现有 `CombatResult.Outcome.RETREAT`。
