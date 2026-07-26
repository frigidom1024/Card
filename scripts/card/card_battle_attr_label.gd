extends Label


@export var type:String
@export var number:int


# 刷新文字内容+对应颜色
func refresh_display():
	text = str(number)
	match type:
		"damage":
			modulate = Color("red") # 红色-攻击
		"defense":
			modulate = Color("yellow") # 黄色-防御
		"heal":
			modulate = Color("green") # 绿色-治疗
	

func _ready() -> void:
	refresh_display()


# 外部修改数值/类型后，调用这个刷新
func set_value(new_num: int, new_type: String):
	number = new_num
	type = new_type.to_lower()
	refresh_display()

func set_and_refresh(new_num: int, new_type: String):
	set_value(new_num,new_type)
	refresh_display()
