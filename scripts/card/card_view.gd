extends Control

const HEAD_INDICATOR_SIZE := Vector2(28.0, 14.0)
const HEAD_INDICATOR_GAP := 2.0

## 阴影相对于卡面左上角的屏幕坐标偏移。
## 以屏幕方向计算，而不是使用 CardView 的局部坐标，保证卡牌旋转后
## 阴影仍然位于卡牌视觉上的右下角。
@export var shadow_screen_offset := Vector2(4.0, 4.0)

@onready var artwork: TextureRect = $Artwork
@onready var label_container: HBoxContainer = $LabelContainer
@onready var head_indicator: Control = $HeadIndicator
@onready var shadow: Panel = $Shadow
@onready var card: Panel = $Card

var card_inst: CardInstance


func _ready() -> void:
	if card_inst == null:
		card_inst = CardInstance.create_debug_card()
	_set_visual_layers_mouse_filter()
	set_notify_transform(true)
	resized.connect(_pin_label_container)
	resized.connect(_pin_head_indicator)
	resized.connect(_sync_shadow)
	_pin_label_container()
	_pin_head_indicator()
	_sync_shadow()
	refresh_display()


## CardView 只是 CardEntity 的视觉层；真正的交互由 Area2D 处理。
## 显式设置而不是依赖场景默认值，避免 Panel/TextureRect 改版后重新拦截输入。
func _set_visual_layers_mouse_filter() -> void:
	for visual_layer in [shadow, card, $FrameHost, head_indicator, label_container, artwork]:
		if visual_layer is Control:
			visual_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready():
		_sync_shadow()


func set_head_indicator_visible(value: bool) -> void:
	if head_indicator == null:
		return
	head_indicator.visible = value


func _pin_head_indicator() -> void:
	if head_indicator == null:
		return
	head_indicator.size = HEAD_INDICATOR_SIZE
	head_indicator.position = Vector2(
		(size.x - HEAD_INDICATOR_SIZE.x) * 0.5,
		-HEAD_INDICATOR_SIZE.y - HEAD_INDICATOR_GAP,
	)


func _pin_label_container() -> void:
	if label_container == null:
		return
	var label_height := label_container.size.y
	if is_zero_approx(label_height):
		label_height = 23.0
	label_container.position = Vector2(0.5, size.y - label_height)
	label_container.size = Vector2(maxf(0.0, size.x - 1.0), label_height)


## 同步阴影的尺寸，并把屏幕方向的偏移换算回 CardView 局部坐标。
##
## Shadow 仍是 CardView 的子节点，所以它会与卡面保持相同的旋转和缩放；
## 只有“右下”偏移通过全局变换的逆矩阵计算，避免旋转 90/180 度后偏移
## 跑到左侧或上方。
func _sync_shadow() -> void:
	if shadow == null or card == null:
		return

	shadow.size = card.size
	var view_transform := get_global_transform_with_canvas()
	var card_global_position := card.get_global_transform_with_canvas() * Vector2.ZERO
	var desired_shadow_global_position := card_global_position + shadow_screen_offset
	shadow.position = view_transform.affine_inverse() * desired_shadow_global_position


func refresh_display() -> void:
	_update_artwork()


func set_value(value: CardInstance) -> void:
	card_inst = value
	if is_node_ready():
		refresh_display()


func _update_artwork() -> void:
	artwork.texture = null
	artwork.visible = false

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
