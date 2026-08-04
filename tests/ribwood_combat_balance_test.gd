extends SceneTree

const CombatServiceScript = preload("res://scripts/combatv2/combat_service.gd")
const CombatResultScript = preload("res://scripts/combatv2/combat_result.gd")
const CombatStatsScript = preload("res://scripts/combatv2/combat_stats.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const Root = preload("res://data/levels/ribwood/cards/ribwood_guardian_root.tres")
const Blade = preload("res://data/levels/ribwood/cards/ribwood_rib_blade.tres")
const Tinder = preload("res://data/levels/ribwood/cards/ribwood_old_tinder.tres")
const Flask = preload("res://data/levels/ribwood/cards/ribwood_warm_marrow_flask.tres")
const Rat = preload("res://data/levels/ribwood/mobs/ribwood_marrow_rat_echo.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_recommended_three_card_chain_kills_marrow_rat()
	_test_nonlethal_chain_retreated_instead_of_victory()
	quit(1 if _failure_count > 0 else 0)


func _test_recommended_three_card_chain_kills_marrow_rat() -> void:
	var player := _stats(20, 20, 0, 0)
	var chain: Array[CardInstance] = [
		CardInstanceScript.new(Root),
		CardInstanceScript.new(Blade),
		CardInstanceScript.new(Tinder),
	]
	var result := CombatServiceScript.new().resolve_encounter(player, chain, Rat.create_instance())
	_expect(result.outcome == CombatResultScript.Outcome.VICTORY, "root + blade + tinder kills a 4 HP marrow rat")
	_expect(result.monster_stats_after.hp == 0, "recommended chain leaves marrow rat at 0 HP")


func _test_nonlethal_chain_retreated_instead_of_victory() -> void:
	var player := _stats(20, 20, 0, 0)
	var chain: Array[CardInstance] = [
		CardInstanceScript.new(Root),
		CardInstanceScript.new(Blade),
		CardInstanceScript.new(Flask),
	]
	var result := CombatServiceScript.new().resolve_encounter(player, chain, Rat.create_instance())
	_expect(result.outcome == CombatResultScript.Outcome.RETREAT, "nonlethal chain returns RETREAT")
	_expect(result.monster_stats_after.hp == 2, "nonlethal chain preserves the damage dealt")


func _stats(max_hp: int, hp: int, attack: int, defense: int) -> CombatStats:
	var stats := CombatStatsScript.new()
	stats.max_hp = max_hp
	stats.hp = hp
	stats.attack = attack
	stats.defense = defense
	return stats


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
