extends ColorRect

const FRAME_SCENES := {
	CardData.Rarity.COMMON: preload("res://scenes/card_view/frames/card_frame_common.tscn"),
	CardData.Rarity.RARE: preload("res://scenes/card_view/frames/card_frame_rare.tscn"),
	CardData.Rarity.EPIC: preload("res://scenes/card_view/frames/card_frame_epic.tscn"),
	CardData.Rarity.LEGENDARY: preload("res://scenes/card_view/frames/card_frame_legendary.tscn"),
}

@onready var artwork: TextureRect = $Artwork
@onready var artwork_placeholder: Control = $ArtworkPlaceholder
@onready var frame_host: Control = $FrameHost
@onready var labelcontainer: HBoxContainer = $LabelContainer

var card_inst: CardInstance


func _ready() -> void:
	if not card_inst:
		card_inst = CardInstance.create_debug_card()
	resized.connect(_pin_label_container)
	_pin_label_container()
	refresh_display()


func _pin_label_container() -> void:
	var h := size.y
	labelcontainer.offset_left = 0.5
	labelcontainer.offset_top = h - 23.0
	labelcontainer.offset_right = size.x - 0.5
	labelcontainer.offset_bottom = h


func refresh_display() -> void:
	if card_inst == null or card_inst.card_data == null:
		_update_artwork()
		return
	_update_frame()
	_update_artwork()


func set_value(value: CardInstance) -> void:
	card_inst = value
	refresh_display()




func _update_artwork() -> void:
	artwork.texture = null
	artwork.visible = false
	artwork_placeholder.visible = true

	if card_inst == null or card_inst.card_data == null:
		return

	var artwork_path := card_inst.card_data.artwork_path
	if artwork_path.is_empty():
		return
	if not ResourceLoader.exists(artwork_path, "Texture2D"):
		return

	var loaded_texture := ResourceLoader.load(artwork_path, "Texture2D") as Texture2D
	if loaded_texture == null:
		return

	artwork.texture = loaded_texture
	artwork.visible = true
	artwork_placeholder.visible = false


func _update_frame() -> void:
	for child in frame_host.get_children():
		child.queue_free()

	var frame_scene: PackedScene = FRAME_SCENES.get(
		card_inst.card_data.rarity,
		FRAME_SCENES[CardData.Rarity.COMMON]
	)
	frame_host.add_child(frame_scene.instantiate())