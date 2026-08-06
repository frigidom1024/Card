# CardRule 位置配合与有效次数设计

**日期：** 2026-08-06
**范围：** 现有 `CardRule` 规则框架、牌链位置判断、规则有效次数

## 决策

继续使用 `CardData.effect_rules: Array[CardRule]`。不新增独立的卡牌效果配置体系。

`CardRule` 负责静态配置与规则计算；`CardResolutionContext` 负责当前牌链位置和规则运行时触发次数；`CardResolutionDraft` 负责当前卡牌本次结算的临时战斗数值。

## 位置定义

牌链由牌根到头部排列：

```text
牌根 → A → B → C（头部）
```

- 前方相邻卡牌：数组索引 `current_index + 1`，更靠近头部的一张；
- 后方相邻卡牌：数组索引 `current_index - 1`，更靠近牌根的一张；
- 头部：牌链数组最后一张；
- 战斗从头部向牌根结算时，规则仍按牌链物理位置判断，不将“已经结算的卡牌”与“前方/后方”混为一谈。

## 有效次数

`CardRule` 增加静态字段：

```gdscript
@export var effective_count: int = -1
```

- `-1`：无限次；
- `0`：关闭；
- 正数：最多成功触发次数。

剩余次数不能存放在共享的 `CardRule` Resource 内，必须由战斗/探索运行时按“卡牌实例 + 规则实例”记录。

只有规则成功找到目标并实际修改 `CardResolutionDraft` 时才消耗次数。没有目标、不满足条件或未产生修改时不消耗。

有效次数绑定卡牌实例，默认在当前探索中持续消耗，不因单场战斗结束自动重置。无限次数规则可以继续作用于后续形成的新头部。

## 首批规则

- `NextCardPointBonusRule`：前方相邻卡牌本次比较点数增加；
- `NextCardArmorBonusRule`：前方相邻卡牌本场战斗获得护甲；
- `NextCardTagPointBonusRule`：前方相邻卡牌满足标签时获得点数；
- `PreviousCardPointBonusRule`：后方相邻卡牌满足条件时当前卡获得点数；
- `AdjacentCardArmorRule`：当前卡前后均有卡牌时获得护甲；
- 保留现有规则类，并通过兼容方法继续支持旧数据。

规则只返回修改后的 `CardResolutionDraft`，不直接修改棋盘、手牌、资源或怪物。
