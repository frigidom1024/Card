extends Node2D

@onready var draglayer: DraggerLayer = $DraggerLayer
@onready var hand_zones: Array[HandZone] = [$Handzone, $Handzone2]


func _ready() -> void:
	for hand_zone in hand_zones:
		draglayer.register_zone(hand_zone)


	for card in find_children("*", "Card", true, false):
		_connect_card(card as Card)


func _connect_card(card: Card) -> void:
	if card == null:
		return
	card.bind_drag_layer(draglayer)
