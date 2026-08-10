extends SceneTree

const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const CombatResultScript = preload("res://scripts/combatv2/combat_result.gd")
const CombatServiceScript = preload("res://scripts/combatv2/combat_service.gd")
const CombatStatsScript = preload("res://scripts/combatv2/combat_stats.gd")
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
	_test_short_chain_retreats_and_preserves_echo_damage()
	quit(1 if _failure_count > 0 else 0)


func _test_recommended_three_card_chain_kills_marrow_rat() -> void:
	var player := _stats(20, 20)
	var root := CardInstanceScript.new(Root)
	var blade := CardInstanceScript.new(Blade)
	var tinder := CardInstanceScript.new(Tinder)
	var chain: Array[CardInstance] = [root, blade, tinder]
	var result := CombatServiceScript.new().resolve_encounter(player, chain, Rat.create_instance())

	_expect(tinder.current_points == 0, "Rib Blade does not change Old Tinder during placement")

	_expect(result.outcome == CombatResultScript.Outcome.VICTORY, "root + blade + tinder kills a 4 HP marrow rat")
	_expect(result.monster_stats_after.hp == 0, "recommended chain leaves marrow rat at 0 HP")
	_expect(tinder.current_points == 0, "the tinder is exhausted by the first comparison")
	_expect(blade.current_points == 0, "the blade spends its points after its temporary combat-start bonus is cleared")
	_expect(root.current_points == 2, "the unneeded root stays on the board at full points")
	_expect(result.depleted_cards.has(tinder), "the depleted tinder is reported for encounter settlement")
	_expect(result.depleted_cards.has(blade), "the depleted blade is reported for encounter settlement")
	_expect(not result.depleted_cards.has(root), "the unused root is not reported as depleted")


func _test_short_chain_retreats_and_preserves_echo_damage() -> void:
	var player := _stats(20, 20)
	var root := CardInstanceScript.new(Root)
	var flask := CardInstanceScript.new(Flask)
	var chain: Array[CardInstance] = [root, flask]

	var result := CombatServiceScript.new().resolve_encounter(player, chain, Rat.create_instance())

	_expect(result.outcome == CombatResultScript.Outcome.RETREAT, "a short chain returns RETREAT")
	_expect(result.monster_stats_after.hp == 1, "RETREAT preserves the three points already dealt")
	_expect(result.monster_stats_after.max_hp == 4, "combat result preserves the rat state before encounter settlement strengthens it")
	_expect(player.hp == 20, "normal point comparison does not damage the player")
	_expect(result.depleted_cards.has(flask) and result.depleted_cards.has(root), "spent cards are reported")


func _stats(max_hp: int, hp: int) -> CombatStats:
	var stats := CombatStatsScript.new()
	stats.max_hp = max_hp
	stats.hp = hp
	return stats


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
