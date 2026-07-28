extends PanelContainer

# ============================
# 稀有度颜色
# ============================
const RARITY_COLORS := {
	CardData.Rarity.COMMON:    Color(0.7, 0.7, 0.75),
	CardData.Rarity.RARE:      Color(0.3, 0.5, 0.95),
	CardData.Rarity.EPIC:      Color(0.6, 0.3, 0.9),
	CardData.Rarity.LEGENDARY: Color(0.95, 0.75, 0.2),
}

const RARITY_NAMES := {
	CardData.Rarity.COMMON:    "COMMON",
	CardData.Rarity.RARE:      "RARE",
	CardData.Rarity.EPIC:      "EPIC",
	CardData.Rarity.LEGENDARY: "LEGENDARY",
}

const TAG_NAMES := {
	CardData.CardTag.WEAPON:    "WEAPON",
	CardData.CardTag.DEFENSE:   "DEFENSE",
	CardData.CardTag.HEAL:      "HEAL",
	CardData.CardTag.RESOURCE:  "RESOURCE",
	CardData.CardTag.LOCATION:  "LOCATION",
	CardData.CardTag.CREATURE:  "CREATURE",
	CardData.CardTag.ITEM:      "ITEM",
	CardData.CardTag.EVENT:     "EVENT",
	CardData.CardTag.HOLY:      "HOLY",
	CardData.CardTag.DARK:      "DARK",
	CardData.CardTag.NATURE:    "NATURE",
}


var card_inst:CardInstance

@onready var  rarity_label = $MarginContainer/VBoxContainer/RarityLabel
@onready var title = $MarginContainer/VBoxContainer/Title
@onready var id_label = $MarginContainer/VBoxContainer/ID

@onready var damage_label = $MarginContainer/VBoxContainer/AttrContainer/DamageLabel
@onready var defense_label = $MarginContainer/VBoxContainer/AttrContainer/DefenseLabel
@onready var heal_label = $MarginContainer/VBoxContainer/AttrContainer/HealLabel

@onready var description_label = $MarginContainer/VBoxContainer/Description
@onready var tags_container = $MarginContainer/VBoxContainer/Tags
@export var tag_label_template :PackedScene

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if not card_inst:
		card_inst = CardInstance.create_debug_card()
	refresh_display()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func set_data(card_inst:CardInstance):
	self.card_inst = card_inst

func refresh_display():
	_update_rarity_label()
	_update_title()
	_update_id_label()
	_update_attr_labels()
	_updata_description_label()
	_updata_tags()
	
func _update_rarity_label():
	var data = card_inst.card_data
	var rarity_color = RARITY_COLORS.get(data.rarity if data else CardData.Rarity.COMMON, RARITY_COLORS[CardData.Rarity.COMMON])
	var rarity_name = RARITY_NAMES.get(data.rarity if data else CardData.Rarity.COMMON, "COMMON")
	
	
	rarity_label.add_theme_color_override("font_color", rarity_color)
	rarity_label.text = "★ " + rarity_name
	
func _update_title():
	title.text = card_inst.card_data.card_name if  card_inst.card_data.card_name else "Card"

func _update_id_label():
	var data = card_inst.card_data
	if data:
		id_label.text = "ID: %d" % data.card_id
	else:
		id_label.text = "ID: -"
		
func _update_attr_labels():
	var data = card_inst.card_data
	if data and data.damage>0:
		damage_label.visible = true
		damage_label.text = "%d" % data.damage
	else:
		damage_label.visible = false
		
	if data and data.defense>0:
		defense_label.visible = true
		defense_label.text = "%d" % data.defense
	else:
		defense_label.visible = false
		
	if data and data.heal>0:
		heal_label.visible = true
		heal_label.text = "%d" % data.heal
	else:
		heal_label.visible = false

func _updata_description_label():
	var data = card_inst.card_data
	if description_label and data:
		description_label.text=data.description

func _updata_tags():
	for child in tags_container.get_children():
		child.queue_free()
	var data = card_inst.card_data
	for tag in data.tags:
		var new_tag_label = tag_label_template.instantiate()
		new_tag_label.text = TAG_NAMES.get(tag,"unknow")
		tags_container.add_child(new_tag_label)
	
	
