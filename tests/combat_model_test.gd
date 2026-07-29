extends SceneTree

const CombatStatsDataScript = preload("res://scripts/combat/combat_stats_data.gd")
const CombatStatsScript = preload("res://scripts/combat/combat_stats.gd")
const MobDataScript = preload("res://scripts/game/event/mob_data.gd")
const PlayerDataScript = preload("res://scripts/player/player_data.gd")

func _init() -> void:
	var data = CombatStatsDataScript.new()
	data.max_hp = 10
	data.attack = 3
	data.defense = 2

	var stats = CombatStatsScript.new()
	stats.reset_from_data(data)
	_expect(stats.hp == 10, "new runtime stats start at maximum HP")
	_expect(stats.attack == 3, "runtime attack copies base attack")
	_expect(stats.take_damage(5) == 3, "defense absorbs two damage")
	_expect(stats.hp == 7, "only unabsorbed damage reduces HP")
	stats.heal(99)
	_expect(stats.hp == 10, "healing cannot exceed maximum HP")
	stats.add_defense(4)
	stats.modify_attack(-1)
	_expect(stats.defense == 4, "damage consumes existing defense before new defense is added")
	_expect(stats.attack == 2, "attack modifiers use the shared runtime API")

	var mob_data = MobDataScript.new()
	mob_data.base_stats = data
	var first = mob_data.create_instance()
	var second = mob_data.create_instance()
	first.take_damage(12)
	_expect(not first.is_alive(), "first encounter can be defeated")
	_expect(second.is_alive(), "second encounter has independent runtime HP")
	_expect(second.stats.hp == 10, "definition resources are not mutated by encounters")

	var player_data = PlayerDataScript.new()
	player_data.base_stats = data
	var player_stats = CombatStatsScript.new()
	player_stats.reset_from_data(player_data.base_stats)
	_expect(player_stats.take_damage(2) == 0, "player stats use the same defense rule as monsters")
	_expect(player_stats.is_alive(), "player stats use the same alive-state API as monsters")

	var wolf = load("res://data/event/mobs/wolf_mob.tres")
	if wolf == null:
		push_error("wolf resource loads")
		quit(1)
		return
	_expect(wolf.base_stats != null, "wolf resource includes inline base stats")
	_expect(wolf.create_instance().is_alive(), "loaded wolf creates a valid encounter")

	var card = load("res://data/cards/AllThingsRevival.tres")
	if card == null:
		push_error("migrated card resource loads")
		quit(1)
		return
	_expect(int(card.get("card_id")) == 28, "migrated card data preserves its ID")
	quit(0)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
