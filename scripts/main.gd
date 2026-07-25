extends Node2D

@onready var board: Board = $Board
@onready var card_manager: Node2D = $CardManager
@onready var hand_area: HandArea = $HandManager
@onready var drag_layer: DragLayer = $DragLayer


func _ready() -> void:
	# 注入 DragLayer 的区域引用
	drag_layer.board = board
	drag_layer.hand_area = hand_area

	# 创建测试手牌
	for i in range(5):
		var data := CardData.new(i, "卡牌 %d" % i)
		var inst := CardInstance.new(data)
		inst.cur_zone = CardInstance.ZONE.HAND

		var card := preload("res://scenes/card_entity.tscn").instantiate() as CardEntity
		card.bind_instance(inst)
		hand_area.add_card(card)
