## 拖拽组件集成测试页面
##
## 负责组装两个 HandZone、一个 BoardZone 与共享 DraggerLayer，提供可直接运行的
## ROOT/NORMAL 卡牌拖拽验证环境。
##
## 不负责：
## - 正式游戏页面的商店、回收或战斗业务
## - 卡牌数据持久化
## - 区域内部规则实现

extends Node2D

@onready var draglayer: DraggerLayer = $DraggerLayer
@onready var hand_zones: Array[HandZone] = [$Handzone, $Handzone2]
@onready var board_zone: BoardZone = $BoardZone


func _ready() -> void:
	var root_card := $Handzone/Card2 as Card
	var normal_card := $Handzone2/Card2 as Card
	root_card.bind_card_inst(_create_test_instance(CardData.CardType.ROOT, "Test Root"))
	normal_card.bind_card_inst(_create_test_instance(CardData.CardType.NORMAL, "Test Normal"))

	for hand_zone in hand_zones:
		draglayer.register_zone(hand_zone)
	board_zone.set_drag_layer(draglayer)

	for card in find_children("*", "Card", true, false):
		_connect_card(card as Card)


func _create_test_instance(card_type: CardData.CardType, card_name: String) -> CardInstance:
	var data := CardData.new()
	data.card_type = card_type
	data.card_name = card_name
	var card_inst := CardInstance.new(data)
	card_inst.cur_zone = CardInstance.ZONE.HAND
	return card_inst


func _connect_card(card: Card) -> void:
	if card == null:
		return
	card.bind_drag_layer(draglayer)
