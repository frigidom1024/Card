extends SceneTree
const Shield=preload("res://data/levels/ribwood/cards/ribwood_folded_rib_shield.tres")
func _init():
 print("points=",Shield.max_points," armor=",Shield.armor," rule=",Shield.effect_rules[0].get_script().resource_path," class=",Shield.effect_rules[0].get_class())
 quit()