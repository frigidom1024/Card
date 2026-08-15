# 战斗批次处理器与战斗驱动架构

日期：2026-08-15  
状态：已确认，第一阶段框架已实现

## 1. 目标

本设计只建立新的战斗协议和运行框架，暂不替换现有 `CombatService`，也暂不制作具体棋盘动画。

核心目标：

1. 由一个战斗驱动决定下一步战斗流程。
2. 由一个效果批次处理器执行所有效果。
3. 效果批次处理器是战斗状态的唯一写入入口。
4. 玩家攻击和怪物攻击使用不同的批次类型和协议事件。
5. 玩家操作卡不经过战斗流程规划，直接生成批次并插入处理器。
6. 战斗速度只影响战斗驱动的推进节奏，不改变数值和事件顺序。
7. 已提交批次不可回滚，未执行批次在执行前使用最新状态重新验证。

## 2. 总体架构

```mermaid
flowchart TB
    UI[棋盘表现与玩家输入]
    Speed[战斗速度]
    Driver[CombatDriver\n战斗驱动]
    Flow[CombatFlowProvider\n战斗流程提供器]
    Trigger[CombatTriggerPlanner\n触发规划器]
    Operation[OperationBatchFactory\n玩家操作批次工厂]
    Queue[CombatEffectBatchQueue\n统一批次队列]
    Processor[CombatEffectBatchProcessor\n效果批次处理器]
    Registry[CombatEffectHandlerRegistry]
    Rules[CombatStateRule]
    Writer[CombatStateWriter\n唯一草稿写入能力]
    State[CombatRuntimeState]
    Events[CombatStateEvent]
    Result[CombatEffectBatchResult]

    Speed --> Driver
    Flow --> Driver
    Driver -->|自动战斗批次| Queue
    UI --> Operation
    Operation -->|玩家操作批次| Queue
    Queue --> Processor
    Processor --> Registry
    Processor --> Rules
    Registry --> Writer
    Rules --> Writer
    Writer --> State
    Processor --> Events
    Processor --> Result
    Events --> Trigger
    Trigger --> Driver
    Result --> Driver
    Events --> UI
```

## 3. 模块职责

### 3.1 `CombatDriver`

负责：

- 启动和停止战斗运行循环；
- 从 `CombatFlowProvider` 取得下一个自动战斗批次；
- 在批次完成后将事件交给 `CombatTriggerPlanner`；
- 优先调度派生触发批次，再推进主战斗流程；
- 根据 `CombatBattleClock` 和战斗速度控制自动批次间隔；
- 在需要时等待表现层确认；
- 观察玩家操作造成的新状态并重新推进流程。

不负责：

- 修改卡牌点数、护盾、生命或金币；
- 拆牌链或移除卡牌；
- 直接执行卡牌效果；
- 保存已经计算好的未来伤害结果。

### 3.2 `CombatEffectBatchProcessor`

负责：

- 维护统一优先级队列；
- 在批次出队时验证状态版本、牌链版本和前置条件；
- 在批次草稿中依次执行每个效果；
- 每个效果后执行死亡等状态规则；
- 成功时原子提交草稿；
- 失败时丢弃整个草稿；
- 产生状态事件和批次结果。

处理器不理解完整战斗流程，不决定下一个是玩家攻击还是怪物攻击。

### 3.3 `CombatStateWriter`

效果处理器不能取得正式状态，只能取得由批次处理器创建的 `CombatStateWriter`。

`CombatStateWriter` 提供：

- 设置嵌套状态值；
- 增加数值；
- 修改战斗阶段；
- 标记牌链已经变化；
- 产生状态事件。

正式状态只在整个批次成功后由处理器提交。

### 3.4 `CombatTriggerPlanner`

触发规划器消费已经提交的 `CombatStateEvent`，按以下顺序匹配规则：

1. 事件在批次中的顺序；
2. 触发规则优先级；
3. 规则注册顺序。

触发规划器只生成新的 `CombatEffectBatch`，不修改状态。

### 3.5 玩家操作卡

玩家操作卡的流程是：

```text
拖拽并确定目标
    -> 创建 PLAYER_OPERATION 批次
    -> 直接 enqueue 到 CombatEffectBatchProcessor
    -> 当前原子批次结束
    -> 玩家操作批次按高优先级执行
    -> CombatDriver 观察结果并继续规划
```

第一阶段只提供协议和插入入口。撤退目标预览、碰撞判定和具体操作效果将在后续接入。

## 4. 协议对象

### 4.1 `CombatBatchEffect`

描述批次中的单个效果：

```text
effect_id
效果类型
来源实体 ID
目标实体 ID 列表
参数
标签
```

协议不保存 Node 引用。

### 4.2 `CombatEffectBatch`

描述一个原子结算批次：

```text
batch_id
批次类型
批次来源
优先级
期望状态版本
期望牌链版本
前置条件
有序效果列表
开始事件类型
完成事件类型
```

批次类型包括：

- 战斗开始；
- 战斗结束；
- 玩家攻击；
- 怪物攻击；
- 卡牌触发；
- 玩家操作；
- 流程切换；
- 系统规则。

### 4.3 `CombatStateEvent`

表示已经提交的战斗事实，包含：

```text
事件 ID
事件类型
批次 ID
效果 ID
因果事件 ID
来源实体 ID
目标实体 ID
事件顺序
状态版本
牌链版本
负载数据
```

### 4.4 `CombatEffectBatchResult`

批次结果只有三种状态：

- `COMMITTED`：已经原子提交；
- `CANCELED`：执行前条件不再成立；
- `FAILED`：处理器、效果处理器或状态规则执行失败。

## 5. 玩家攻击与怪物攻击

两种攻击可以复用底层伤害效果处理器，但不能复用顶层批次协议。

```mermaid
flowchart LR
    PA[PLAYER_ATTACK 批次]
    PAS[player_attack_started]
    PE[伤害等效果]
    PAF[player_attack_finished]

    MA[MONSTER_ATTACK 批次]
    MAS[monster_attack_started]
    ME[伤害等效果]
    MAF[monster_attack_finished]

    PA --> PAS --> PE --> PAF
    MA --> MAS --> ME --> MAF
```

这样触发规则可以明确监听玩家攻击或怪物攻击，不需要再检查一个混合攻击事件中的攻击方字段。

## 6. 批次执行时序

```mermaid
sequenceDiagram
    participant Source as 驱动或玩家操作
    participant Processor as EffectBatchProcessor
    participant Draft as CombatStateDraft
    participant Handler as EffectHandler
    participant Rule as CombatStateRule
    participant State as CombatRuntimeState
    participant Driver as CombatDriver

    Source->>Processor: enqueue(batch)
    Processor->>Processor: 按优先级出队
    Processor->>Processor: 验证版本和前置条件
    Processor->>Draft: 创建状态草稿
    loop 每个效果
        Processor->>Handler: validate(effect, draft snapshot)
        Handler->>Draft: 通过 StateWriter 写入
        Processor->>Rule: 检查死亡等状态规则
    end
    Processor->>State: 原子提交草稿
    Processor-->>Driver: StateEvents + BatchResult
    Driver->>Driver: 规划触发批次或下一流程批次
```

当前正在执行的批次不可中断。玩家操作只能在下一个批次边界取得执行权。

## 7. 批次优先级

默认优先级：

```text
SYSTEM_RULE       400
PLAYER_OPERATION  300
CARD_TRIGGER      200
BATTLE_FLOW       100
```

同一优先级按进入队列的先后顺序执行。

战斗驱动不会提前把完整未来流程塞入处理器。它一次只获取和提交一个自动批次，因此玩家操作造成状态变化后，后续主流程天然基于最新快照重新生成。

## 8. 战斗速度

`CombatBattleClock` 使用逻辑时间推进：

```text
本帧逻辑时间 = 本帧真实时间 × 战斗速度
```

战斗速度影响：

- 自动战斗批次的提交间隔；
- 卡牌触发批次之间的间隔；
- 后续表现层推荐动画时长；
- 后续操作窗口的实际持续时间。

战斗速度不影响：

- 效果数值；
- 批次优先级；
- 事件顺序；
- 随机结果；
- 状态版本；
- 原子提交边界。

玩家操作批次是直接输入，不需要等待战斗驱动的自动流程计时器。

## 9. 表现接口

处理器产生事件，表现层消费事件。第一阶段不制作具体动画。

表现层后续可按照事件映射：

```text
点数或护盾变化事件 -> 数字变化动画
card_trigger_started -> 卡牌抖动接口
player_attack_started -> 玩家攻击接口
monster_attack_started -> 怪物攻击接口
chain_changed -> 牌链断开接口
```

`CombatDriver` 已提供：

- `presentation_requested` 信号；
- 推荐表现时长；
- `acknowledge_presentation(batch_id)`；
- 等待表现确认时仍允许玩家操作批次进入处理器。

## 10. 当前实现边界

本阶段已经实现：

- 批次、效果、事件和结果协议；
- 玩家攻击与怪物攻击独立协议；
- 统一优先级批次队列；
- 原子效果批次处理器；
- 效果处理器注册表；
- 状态草稿、唯一写入器和只读快照；
- 状态规则扩展点；
- 触发规划器；
- 可插拔战斗流程提供器；
- 受战斗速度影响的战斗驱动；
- 玩家操作直接插入处理器的入口；
- 表现确认信号和接口边界。

本阶段没有实现：

- 替换现有同步 `CombatService`；
- 具体伤害、死亡、撤退和金币强化效果；
- 操作卡拖拽与目标预览；
- 棋盘动画；
- 遭遇战场景接线；
- 战斗存档与回放。

这些功能应在当前协议稳定后逐步接入，而不是绕过批次处理器直接修改状态。
