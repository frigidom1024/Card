extends SceneTree

const ShieldBreakScript = preload("res://scripts/combatv2/mob_effects/mob_effect_shield_break.gd")
const RearShockScript = preload("res://scripts/combatv2/mob_effects/mob_effect_rear_shock.gd")

var _failure_count := 0

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_ribwood_echo_effect_configuration()
	quit(1 if _failure_count > 0 else 0)

func _test_ribwood_echo_effect_configuration() -> void:
	var rat = load("res://data/levels/ribwood/mobs/ribwood_marrow_rat_echo.tres") as MobData
	var wolf = load("res://data/levels/ribwood/mobs/ribwood_fallen_rib_wolf_echo.tres") as MobData
	var hart = load("res://data/levels/ribwood/mobs/ribwood_white_horn_hart_boss.tres") as MobData
	_expect(rat != null and rat.effects.is_empty(), "marrow rats stay as the no-special-effect teaching echo")
	_expect(wolf != null and wolf.effects.size() == 1, "fallen rib wolf configures one readable special effect")
	if wolf != null and wolf.effects.size() == 1:
		var shield_break = wolf.effects[0]
		_expect(shield_break is ShieldBreakScript, "fallen rib wolf uses shield break")
		_expect(is_equal_approx(float(shield_break.armor_multiplier), 2.0), "wolf shield break doubles armor damage")
	_expect(hart != null and hart.effects.size() == 1, "white horn hart configures one boss special effect")
	if hart != null and hart.effects.size() == 1:
		var rear_shock = hart.effects[0]
		_expect(rear_shock is RearShockScript, "white horn hart uses rear shock")
		_expect(rear_shock.damage == 1 and rear_shock.card_count == 1, "boss rear shock is deliberately low pressure")
		_expect(rear_shock.effective_count == 1, "boss rear shock fires once per encounter")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
