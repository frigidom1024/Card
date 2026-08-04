extends SceneTree

const Rat = preload("res://data/levels/ribwood/mobs/ribwood_marrow_rat_echo.tres")
const Wolf = preload("res://data/levels/ribwood/mobs/ribwood_fallen_rib_wolf_echo.tres")
const Hart = preload("res://data/levels/ribwood/mobs/ribwood_white_horn_hart_boss.tres")
const EventDataScript = preload("res://scripts/game/event/core/event_data.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_rat()
	_test_wolf()
	_test_hart()
	quit(1 if _failure_count > 0 else 0)


func _test_rat() -> void:
	_expect(Rat.base_stats.max_hp == 4, "marrow rat has 4 HP")
	_expect(Rat.actions.size() == 1 and Rat.actions[0].type == 0 and Rat.actions[0].value == 1, "marrow rat attacks for 1")
	_expect(Rat.gold_reward == 8, "marrow rat rewards 8 gold")
	var instance := Rat.create_instance()
	_expect(instance.max_enhancement_stacks == 2, "ordinary rat has two enhancement stacks")


func _test_wolf() -> void:
	_expect(Wolf.base_stats.max_hp == 10, "fallen rib wolf has 10 HP")
	_expect(Wolf.actions.size() == 2, "fallen rib wolf has two actions")
	if Wolf.actions.size() == 2:
		_expect(Wolf.actions[0].type == 0 and Wolf.actions[0].value == 2, "wolf bites for 2")
		_expect(Wolf.actions[1].type == 1 and Wolf.actions[1].value == 2, "wolf guards for 2")
	_expect(Wolf.gold_reward == 12, "fallen rib wolf rewards 12 gold")


func _test_hart() -> void:
	_expect(Hart.base_stats.max_hp == 26, "white horn hart has 26 HP")
	_expect(Hart.actions.size() == 3, "white horn hart has three actions")
	if Hart.actions.size() == 3:
		_expect(Hart.actions[0].type == 0 and Hart.actions[0].value == 3, "hart charges for 3")
		_expect(Hart.actions[1].type == 1 and Hart.actions[1].value == 3, "hart crouches for 3 defense")
		_expect(Hart.actions[2].type == 0 and Hart.actions[2].value == 4, "hart wails for 4")
	var instance := Hart.create_instance()
	_expect(instance.max_enhancement_stacks == 2, "boss data defaults to ordinary enhancement cap before encounter routing")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
