extends PanelContainer

var card_instance:CardInstance = null

@onready var header := $VBoxContainer/Header as HBoxContainer
@onready var attr_box := $VBoxContainer/AttrBox as VBoxContainer
@onready var description_label := $VBoxContainer/DescriptionLabel as Label
@onready var tag_container := $VBoxContainer/TagContainer as FlowContainer


func _ready() -> void:
	if card_instance:
		refresh_display()


func set_card(inst: CardInstance) -> void:
	card_instance = inst
	refresh_display()


func refresh_display() -> void:
	if not card_instance or not card_instance.card_data:
		return

	var data := card_instance.card_data

	# 渲染卡牌名称
	_update_header(data.card_name, data.rarity)

	# 渲染战斗属性
	_update_attrs(data.damage, data.defense, data.heal)

	# 渲染描述
	_update_description(data.description)

	# 渲染标签
	_update_tags(data.tags)


func _update_header(name_text: String, rarity: int) -> void:
	# 清空 header 重新填充
	for child in header.get_children():
		child.queue_free()

	var name_label := Label.new()
	name_label.text = name_text

	# 稀有度染色
	match rarity:
		CardData.Rarity.COMMON:
			name_label.modulate = Color.WHITE
		CardData.Rarity.RARE:
			name_label.modulate = Color(0.2, 0.6, 1.0)  # 蓝色
		CardData.Rarity.EPIC:
			name_label.modulate = Color(0.7, 0.2, 1.0)  # 紫色
		CardData.Rarity.LEGENDARY:
			name_label.modulate = Color(1.0, 0.6, 0.0)  # 金色

	header.add_child(name_label)


func _update_attrs(damage: int, defense: int, heal: int) -> void:
	for child in attr_box.get_children():
		child.queue_free()

	var hbox := HBoxContainer.new()
	for entry in [
		{"value": damage,  "icon": "⚔", "color": Color("red")},
		{"value": defense, "icon": "🛡", "color": Color("yellow")},
		{"value": heal,    "icon": "❤", "color": Color("green")},
	]:
		if entry.value>0:
			var label := Label.new()
			label.text = entry.icon + str(entry.value)
			label.modulate = entry.color
			hbox.add_child(label)

	attr_box.add_child(hbox)


func _update_description(text: String) -> void:
	description_label.text = text
	description_label.visible = not text.is_empty()


func _update_tags(tags: Array) -> void:
	for child in tag_container.get_children():
		child.queue_free()

	for tag in tags:
		var tag_label := Label.new()
		tag_label.text = _tag_name(tag)
		tag_container.add_child(tag_label)


## 以悬浮面板形式展示（显示 + 定位，local_pos 为父节点局部坐标的左上角位置）
func show_as_floating(inst: CardInstance, local_pos: Vector2) -> void:
	set_card(inst)
	visible = true
	# 等待一帧让容器完成尺寸计算，再定位
	await get_tree().process_frame
	position = local_pos


func hide_floating() -> void:
	visible = false


static func _tag_name(tag: int) -> String:
	match tag:
		CardData.CardTag.WEAPON:
			return "武器"
		CardData.CardTag.DEFENSE:
			return "防御"
		CardData.CardTag.HEAL:
			return "治疗"
		CardData.CardTag.RESOURCE:
			return "资源"
		CardData.CardTag.LOCATION:
			return "地点"
		CardData.CardTag.CREATURE:
			return "生物"
		CardData.CardTag.ITEM:
			return "物品"
		CardData.CardTag.EVENT:
			return "事件"
		CardData.CardTag.HOLY:
			return "圣光"
		CardData.CardTag.DARK:
			return "暗影"
		CardData.CardTag.NATURE:
			return "自然"
	return "未知"
