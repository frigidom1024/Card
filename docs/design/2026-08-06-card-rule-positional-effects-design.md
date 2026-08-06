# CardRule 位置配合与有效次数设计

**日期：** 2026-08-06
**范围：** 现有 `CardRule` 规则框架、牌链位置判断、规则有效次数

## 决策

继续使用 `CardData.effect_rules: Array[CardRule]`。不新增独立的卡牌效果配置体系。

每次普通卡牌成功加入牌链后，探索协调器取得完整牌链，以**新加入卡牌**为目标，遍历牌链中每个 `CardInstance` 持有的全部 `CardRule`。每个规则自行判断来源卡与新卡的位置关系、标签和有效次数，并只在实际改变目标卡牌时返回成功。

`CardRule` 负责静态配置与规则计算；`CardChainRuleContext` 负责来源卡、新加入卡和牌链位置关系；`CardChainRuleService` 负责遍历、次数判断与成功次数消耗；`CardInstance` 保存跨遭遇的点数、护甲和规则使用次数。

## 位置定义

牌链由牌根到头部排列：

```text
牌根 → A → B → C（头部）
```

- 前方相邻卡牌：数组索引 `source_index + 1`，更靠近头部的一张；
- 后方相邻卡牌：数组索引 `source_index - 1`，更靠近牌根的一张；
- 头部：牌链数组最后一张；
- 新加入的普通卡牌会成为当前头部；
- 战斗从头部向牌根结算时，规则仍按牌链物理位置判断，不将“已经结算的卡牌”与“前方/后方”混为一谈。

## 有效次数

`CardRule` 增加静态字段：

```gdscript
@export var effective_count: int = -1
```

- `-1`：无限次；
- `0`：关闭；
- 正数：最多成功触发次数。

剩余次数不能存放在共享的 `CardRule` Resource 内。每个 `CardInstance` 按其 `effect_rules` 中的规则索引记录已成功触发次数，因此同名卡牌、同一张 `CardData` 的不同实例不会共享次数。

只有规则成功找到目标并实际修改目标卡的点数或护甲时才消耗次数。没有目标、不满足位置条件或未产生修改时不消耗。

有效次数绑定卡牌实例，默认在当前探索中持续消耗，不因单场战斗结束自动重置。无限次数规则可以继续作用于后续形成的新头部。

## 首批规则

- `NextCardPointBonusRule`：来源卡前方相邻的新卡获得点数；
- `NextCardArmorBonusRule`：来源卡前方相邻的新卡获得护甲；
- 后续每个位置效果都以独立 `CardRule` 子类实现，不向规则系统添加通用效果枚举。

规则只通过 `CardChainRuleContext` 修改新卡的运行时点数或护甲，不直接修改棋盘、手牌、资源、事件或怪物。

## 调用顺序

```text
Board.add_card 成功提交
  → Board.placement_committed(CHAIN_EXTENDED)
  → ExplorationCoordinator._apply_card_chain_rules
  → CardChainRuleService.resolve_card_added
  → 遍历全链 CardRule
  → 规则成功后累计 CardInstance 触发次数
  → 探索事件生成 / Boss 压力 / 事件接触处理
```

GUIDE 卡产生 `GUIDE_RESOLVED`，不会触发普通卡牌加入规则。
