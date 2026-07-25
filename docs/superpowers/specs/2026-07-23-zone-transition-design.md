# 卡牌区域迁越设计 — DragLayer 方案

## 概述

通过 DragLayer 管理层实现卡牌在 Board（棋盘）和 HandArea（手牌区）之间的双向迁越。

## 架构

```
Main (Node2D)
 ├─ Board (Node2D)
 │    ├─ DropDetector (Area2D)  ← 棋盘放置检测区
 │    └─ ...grid logic
 ├─ HandArea (Node2D)            ← 手牌区
 ├─ DragLayer (Node2D)           ← 拖拽时卡牌临时父节点
 └─ CardManager (Node2D)
```

## 迁越流程

### 手牌 → 棋盘
1. 手牌中左键拖拽 → CardEntity 触发 drag
2. `reparent(DragLayer)` — 卡牌移到拖拽层，z_index = 100
3. 跟随鼠标移动，持续检测是否在棋盘上方 → Board 实时显示放置预览
4. 松手后 DragLayer 检测落点：
   - 在 DropDetector 内 → `Board.add_card(card)`
   - 否则 → `HandArea.add_card(card)` 归位

### 棋盘 → 手牌
1. 棋盘上左键拖拽 → CardEntity 触发 drag
2. `reparent(DragLayer)` — 同上
3. 松手后 DragLayer 检测落点：
   - 在 HandArea 范围内 → `HandArea.add_card(card)`
   - 否则 → `Board.add_card(card)` 原地归位

## 接口

### Board
- `add_card(card: CardEntity)` — 吸附到最近格子，记录到 cards 数组
- `remove_card(card: CardEntity)` — 从 cards 移除，释放格子

### HandArea（已有）
- `add_card(card, animate)` — reparent + 加入手牌布局
- `remove_card(card, animate)` — 从手牌移除

### DragLayer
- `_on_card_drag_start(card)` — reparent 到 DragLayer
- `_on_card_drag_end(card)` — 检测落点，路由到目标区
