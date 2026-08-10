extends SceneTree

const Rat = preload("res://data/levels/ribwood/mobs/ribwood_marrow_rat_echo.tres")
const Wolf = preload("res://data/levels/ribwood/mobs/ribwood_fallen_rib_wolf_echo.tres")
const Hart = preload("res://data/levels/ribwood/mobs/ribwood_white_horn_hart_boss.tres")
const RatContent = preload(
	"res://data/levels/ribwood/event_content/ribwood_marrow_rat_content.tres"
)
const WolfContent = preload(
	"res://data/levels/ribwood/event_content/ribwood_fallen_rib_wolf_content.tres"
)
const HartContent = preload(
	"res://data/levels/ribwood/event_content/ribwood_white_horn_hart_boss_content.tres"
)
const EncounterDropEntryScript = preload(
	"res://scripts/game/event/encounter/encounter_drop_entry.gd"
)

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
	_expect(Rat.enhancement_hp_bonus == 1, "marrow rat gains one HP after RETREAT")
	_expect(RatContent.drop_entries.size() == 2, "marrow rat has gold and card drop entries")
	if RatContent.drop_entries.size() == 2:
		var gold_drop = RatContent.drop_entries[0]
		var card_drop = RatContent.drop_entries[1]
		_expect(
			gold_drop.kind == EncounterDropEntryScript.Kind.GOLD, "marrow rat first drop is gold"
		)
		_expect(
			gold_drop.chance == 1.0 and gold_drop.gold_amount == 8, "marrow rat always drops 8 gold"
		)
		_expect(
			card_drop.kind == EncounterDropEntryScript.Kind.CARD, "marrow rat second drop is a card"
		)
		_expect(card_drop.chance == 0.2, "marrow rat card drop chance is 20%")
		_expect(
			card_drop.card_data != null and card_drop.card_data.card_name == "旧火绒",
			"marrow rat card drop is Old Tinder"
		)
	var instance := Rat.create_instance()
	_expect(instance.max_enhancement_stacks == 2, "ordinary rat has two enhancement stacks")


func _test_wolf() -> void:
	_expect(Wolf.base_stats.max_hp == 10, "fallen rib wolf has 10 HP")
	_expect(Wolf.enhancement_hp_bonus == 1, "fallen rib wolf gains one HP after RETREAT")
	_expect(WolfContent.drop_entries.size() == 2, "fallen rib wolf has gold and card drop entries")
	if WolfContent.drop_entries.size() == 2:
		var gold_drop = WolfContent.drop_entries[0]
		var card_drop = WolfContent.drop_entries[1]
		_expect(
			gold_drop.kind == EncounterDropEntryScript.Kind.GOLD,
			"fallen rib wolf first drop is gold"
		)
		_expect(
			gold_drop.chance == 1.0 and gold_drop.gold_amount == 12,
			"fallen rib wolf always drops 12 gold"
		)
		_expect(
			card_drop.kind == EncounterDropEntryScript.Kind.CARD,
			"fallen rib wolf second drop is a card"
		)
		_expect(card_drop.chance == 0.35, "fallen rib wolf card drop chance is 35%")
		_expect(
			card_drop.card_data != null and card_drop.card_data.card_name == "折叠肋盾",
			"fallen rib wolf card drop is Folded Rib Shield"
		)


func _test_hart() -> void:
	_expect(Hart.base_stats.max_hp == 20, "white horn hart has 20 HP")
	_expect(Hart.enhancement_hp_bonus == 2, "white horn hart gains two HP after RETREAT")
	_expect(HartContent.drop_entries.is_empty(), "white horn hart has no extra encounter drops")
	var instance := Hart.create_instance()
	_expect(
		instance.max_enhancement_stacks == 2,
		"boss data defaults to ordinary enhancement cap before encounter routing"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
