## 旧常驻商店协调器兼容占位（已退役）
##
## 负责：
## - 保持旧脚本资源路径可加载，避免历史场景或工具因资源缺失而解析失败
## - 明确暴露已退役状态，供架构边界测试识别
##
## 不负责：
## - 活动游戏页的商店配置、购买、刷新或补货
## - 卡牌回收、金币结算或 CardInstance 生命周期
## - DragLayer/DraggerLayer 注册与跨区域拖拽
##
## 使用方式：
## 新代码不应创建或配置本组件；活动页面应直接组合 Shop、ShopZone 与 ReclaimZone。
## 仅在兼容性检查中加载脚本并调用 is_retired()。
##
## 依赖：
## 无。新商店流程依赖 Shop，回收流程依赖 ReclaimZone。

class_name PersistentMarketCoordinator
extends RefCounted


func is_retired() -> bool:
	return true
