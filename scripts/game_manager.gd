extends Node

@onready var board: Board = $Board
@onready var card_manager: Node2D = $CardManager
@onready var hand_area: HandArea = $HandManager
@onready var drag_layer: DragLayer = $DragLayer

@export var player_data: PlayerData
var player_stats: CombatStats

# 所有玩家相关卡牌数据引用
var cards_inst: Array[CardInstance]
var card_entities: Array[CardEntity]


func _ready() -> void:
	if player_data and player_data.base_stats:
		player_stats = CombatStats.from_data(player_data.base_stats)
	else:
		push_error("GameManager is missing PlayerData.base_stats")

	# 注入 DragLayer 的区域引用
	drag_layer.board = board
	drag_layer.hand_area = hand_area

	init_player_cards()


# 初始化玩家卡牌：创建初始卡牌并全部发到手牌区
func init_player_cards() -> void:
	var insts = card_manager.get_init_cards(5)
	cards_inst = insts

	card_entities.clear()
	for inst in insts:
		var entity = card_manager.create_card_entity(inst)
		if not entity:
			continue
		entity.drag_layer = drag_layer
		card_entities.append(entity)
		hand_area.add_card(entity)
