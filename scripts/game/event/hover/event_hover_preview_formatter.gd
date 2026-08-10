class_name EventHoverPreviewFormatter
extends RefCounted

const MarketPricingServiceScript = preload("res://scripts/game/market/market_pricing_service.gd")

var _pricing: Object


func _init(pricing: Object = null) -> void:
	_pricing = pricing if pricing != null else MarketPricingServiceScript.new()


## 将事件模板和运行时状态转换为悬停预览模型。
## 此方法只读取数据，不调用事件 resolver，也不改变事件状态。
func build(instance: EventInstance) -> EventHoverPreviewModel:
	var model := EventHoverPreviewModel.new()
	if instance == null or instance.is_resolved or instance.template == null:
		return model

	var content := instance.get_content()
	if content == null:
		return model

	model.visible = true
	model.type_label = _type_label(instance.get_event_type())
	model.title = _event_title(instance)

	match instance.get_event_type():
		EventData.EventType.MONSTER, EventData.EventType.BOSS:
			_format_encounter(instance, model)
		EventData.EventType.SHOP:
			_format_shop(instance, model)
		EventData.EventType.TREASURE:
			_format_treasure(instance, model)
		_:
			model.visible = false

	return model


func _format_encounter(instance: EventInstance, model: EventHoverPreviewModel) -> void:
	var content := instance.get_content() as EncounterEventContent
	if content == null or content.mob == null:
		model.visible = false
		return

	var mob := content.mob
	model.title = mob.mob_name if not mob.mob_name.is_empty() else model.title
	var stats := _encounter_stats(instance, content)
	if stats == null:
		model.stat_lines.append("生命：未知")
	else:
		model.stat_lines.append("生命：%d / %d" % [stats.hp, stats.max_hp])
		model.stat_lines.append("攻击：%d" % stats.attack)
		model.stat_lines.append("护甲：%d" % stats.defense)

	_format_encounter_rewards(content, mob, model)
	_format_mob_abilities(mob, model)


func _format_shop(instance: EventInstance, model: EventHoverPreviewModel) -> void:
	var content := instance.get_content() as ShopEventContent
	if content == null:
		model.visible = false
		return

	var state := instance.runtime_state as ShopRuntimeState
	for index in content.items.size():
		if _is_item_sold(state, index):
			continue
		var item := content.items[index]
		if item == null or item.card_data == null:
			continue
		var card := item.card_data
		var price := int(_pricing.call("get_purchase_price", card, null))
		model.reward_lines.append(
			"%s · 点数 %d · 护甲 %d · %d 金币" % [card.card_name, card.max_points, card.armor, price]
		)
	if model.reward_lines.is_empty():
		model.reward_lines.append("商品已售罄。")


func _format_treasure(instance: EventInstance, model: EventHoverPreviewModel) -> void:
	var content := instance.get_content() as TreasureEventContent
	if content == null:
		model.visible = false
		return

	var state := instance.runtime_state as TreasureRuntimeState
	if state == null or state.options.is_empty():
		model.reward_lines.append("卡牌奖励：随机")
		model.reward_lines.append("金币奖励：%d~%d 金币" % [content.gold_range.x, content.gold_range.y])
		model.reward_lines.append("奖励选择：选择 1 项")
		return

	model.reward_lines.append("奖励选择：选择 1 项")
	for option in state.options:
		if option == null:
			continue
		match option.kind:
			TreasureRewardOption.Kind.CARD:
				if option.card_data != null:
					model.reward_lines.append("卡牌：%s" % option.card_data.card_name)
			TreasureRewardOption.Kind.GOLD:
				model.reward_lines.append("金币：%d" % option.gold_amount)


func _format_encounter_rewards(
	content: EncounterEventContent, mob: MobData, model: EventHoverPreviewModel
) -> void:
	if not content.drop_entries.is_empty():
		for entry in content.drop_entries:
			if entry == null:
				continue
			var prefix := _chance_label(entry.chance)
			match entry.kind:
				EncounterDropEntry.Kind.GOLD:
					if entry.gold_amount > 0:
						model.reward_lines.append("%s：%d 金币" % [prefix, entry.gold_amount])
				EncounterDropEntry.Kind.CARD:
					if entry.card_data != null:
						model.reward_lines.append("%s：%s" % [prefix, entry.card_data.card_name])
	else:
		if mob.gold_reward > 0:
			model.reward_lines.append("必得：%d 金币" % mob.gold_reward)
		for card in mob.card_rewards:
			if card != null:
				model.reward_lines.append("必得：%s" % card.card_name)
	if model.reward_lines.is_empty():
		model.reward_lines.append("无已配置奖励。")


func _format_mob_abilities(mob: MobData, model: EventHoverPreviewModel) -> void:
	for action in mob.actions:
		if action != null and not action.description.strip_edges().is_empty():
			model.ability_lines.append(action.description)
	if model.ability_lines.is_empty():
		model.ability_lines.append("无额外效果。")


func _encounter_stats(instance: EventInstance, content: EncounterEventContent) -> CombatStats:
	var runtime := instance.runtime_state as EncounterRuntimeState
	if runtime != null and runtime.mob_instance != null and runtime.mob_instance.stats != null:
		return runtime.mob_instance.stats
	if content.mob.base_stats == null:
		return null
	return CombatStats.from_data(content.mob.base_stats)


func _is_item_sold(state: ShopRuntimeState, index: int) -> bool:
	return state != null and index < state.sold_flags.size() and state.sold_flags[index]


func _chance_label(chance: float) -> String:
	if chance >= 0.999:
		return "必得"
	return "%d%%" % roundi(chance * 100.0)


func _type_label(event_type: int) -> String:
	match event_type:
		EventData.EventType.MONSTER:
			return "残响"
		EventData.EventType.BOSS:
			return "BOSS"
		EventData.EventType.SHOP:
			return "商店"
		EventData.EventType.TREASURE:
			return "宝藏"
	return "事件"


func _event_title(instance: EventInstance) -> String:
	if instance.template != null and not instance.template.event_id.is_empty():
		return instance.template.event_id
	return _type_label(instance.get_event_type())
