extends SceneTree

const CombatStatsDataScript = preload("res://scripts/combat/combat_stats_data.gd")
const CombatStatsScript = preload("res://scripts/combat/combat_stats.gd")
const MobDataScript = preload("res://scripts/game/event/mob_data.gd")
const PlayerDataScript = preload("res://scripts/player/player_data.gd")
const MobActionScript = preload("res://scripts/game/event/mob_action.gd")
const CardDataScript = preload("res://scripts/card/card_data.gd")

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

	_expect_mob("res://data/event/mobs/rotwood_gnawer_mob.tres", "Rotwood Gnawer", 8, 2, 0, 1, 0)
	_expect_mob("res://data/event/mobs/wolf_mob.tres", "Forest Wolf", 12, 3, 1, 2, 0)
	_expect_mob("res://data/event/mobs/miasma_shadow_lizard_mob.tres", "Miasma Shadow Lizard", 16, 4, 1, 4, 0)
	_expect_mob("res://data/event/mobs/miasma_grove_guardian_boss.tres", "Miasma Grove Guardian", 30, 5, 2, 16, 1)
	var guardian = load("res://data/event/mobs/miasma_grove_guardian_boss.tres") as MobData
	if guardian and guardian.card_rewards.size() == 1:
		var boss_card = guardian.card_rewards[0] as CardDataScript
		_expect(boss_card != null and boss_card.card_name == "World Tree Branch Cleaver", "boss reward is WorldTreeBranchCleaver")

	var event_lib = load("res://data/event/event_lib.tres") as EventLib
	_expect(event_lib != null, "enemy event library loads")
	if event_lib:
		var generated_events = event_lib.generate_event_datas()
		var expected_event_ids := [
			"rotwood_gnawer",
			"forest_wolf",
			"miasma_shadow_lizard",
			"miasma_grove_guardian",
		]
		var expected_event_types := [
			EventData.EventType.MONSTER,
			EventData.EventType.MONSTER,
			EventData.EventType.MONSTER,
			EventData.EventType.BOSS,
		]
		_expect(generated_events.size() == expected_event_ids.size(), "enemy event library generates four fixed events")
		if generated_events.size() == expected_event_ids.size():
			for index in range(expected_event_ids.size()):
				var event = generated_events[index]
				var expected_event_id: String = expected_event_ids[index]
				_expect(event.event_id == expected_event_id, "generated event %d has expected roster ID" % (index + 1))
				_expect(event.event_type == expected_event_types[index], "%s has correct event type" % expected_event_id)
				var monster_content = event.content as EventMonsterContent
				_expect(monster_content != null, "%s has monster content" % expected_event_id)
				if monster_content:
					_expect(monster_content.count == 1, "%s spawns one mob" % expected_event_id)
					_expect(monster_content.mob != null, "%s resolves its mob" % expected_event_id)

	var card = load("res://data/cards/AllThingsRevival.tres")
	if card == null:
		push_error("migrated card resource loads")
		quit(1)
		return
	_expect(int(card.get("card_id")) == 28, "migrated card data preserves its ID")
	quit(0)

func _expect_mob(
	resource_path: String,
	expected_name: String,
	expected_hp: int,
	expected_attack: int,
	expected_defense: int,
	expected_gold: int,
	expected_reward_count: int
) -> void:
	var mob = load(resource_path) as MobData
	_expect(mob != null, "%s loads" % resource_path)
	if mob == null:
		return
	_expect(mob.mob_name == expected_name, "%s keeps its display name" % resource_path)
	_expect(mob.base_stats != null, "%s has inline base stats" % resource_path)
	if mob.base_stats:
		_expect(mob.base_stats.max_hp == expected_hp, "%s has expected HP" % resource_path)
		_expect(mob.base_stats.attack == expected_attack, "%s has expected attack" % resource_path)
		_expect(mob.base_stats.defense == expected_defense, "%s has expected defense" % resource_path)
	_expect(mob.gold_reward == expected_gold, "%s has expected gold reward" % resource_path)
	_expect(mob.actions.size() == 1, "%s has one action" % resource_path)
	if mob.actions.size() == 1:
		_expect(mob.actions[0].type == MobActionScript.Type.ATTACK, "%s action is attack" % resource_path)
		_expect(mob.actions[0].value == expected_attack, "%s action value matches attack" % resource_path)
	_expect(mob.card_rewards.size() == expected_reward_count, "%s has expected fixed reward count" % resource_path)
	_expect(mob.create_instance().is_alive(), "%s creates a live encounter" % resource_path)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
