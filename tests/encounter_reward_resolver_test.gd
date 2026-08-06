extends SceneTree

const DropEntryPath := "res://scripts/game/event/encounter/encounter_drop_entry.gd"
const RewardResultPath := "res://scripts/game/event/encounter/encounter_reward_result.gd"
const RewardResolverPath := "res://scripts/game/event/encounter/encounter_reward_resolver.gd"

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var drop_entry_script = ResourceLoader.load(DropEntryPath)
	var result_script = ResourceLoader.load(RewardResultPath)
	var resolver_script = ResourceLoader.load(RewardResolverPath)
	_expect(drop_entry_script != null, "encounter drop entry resource script exists")
	_expect(result_script != null, "encounter reward result script exists")
	_expect(resolver_script != null, "encounter reward resolver script exists")
	if drop_entry_script != null and result_script != null and resolver_script != null:
		_test_guaranteed_entries_award_gold_and_card_in_order(drop_entry_script, resolver_script)
		_test_zero_chance_entries_award_nothing(drop_entry_script, resolver_script)
		_test_independent_gold_entries_sum(drop_entry_script, resolver_script)
		_test_invalid_entries_are_skipped_without_suppressing_valid_entries(
			drop_entry_script, resolver_script
		)
		_test_entry_validation_rejects_invalid_configuration(drop_entry_script)
	quit(1 if _failure_count > 0 else 0)


func _test_guaranteed_entries_award_gold_and_card_in_order(
	drop_entry_script: Script, resolver_script: Script
) -> void:
	var card := CardData.new()
	card.card_name = "Resolver Card"
	var content := _content_with_entries(
		[_gold_drop(drop_entry_script, 1.0, 8), _card_drop(drop_entry_script, 1.0, card)]
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11

	var result = resolver_script.new().resolve(content, rng)

	_expect(result.gold == 8, "a successful gold entry adds its configured amount")
	_expect(result.cards == [card], "a successful card entry preserves configured card order")


func _test_zero_chance_entries_award_nothing(
	drop_entry_script: Script, resolver_script: Script
) -> void:
	var card := CardData.new()
	var content := _content_with_entries(
		[_gold_drop(drop_entry_script, 0.0, 8), _card_drop(drop_entry_script, 0.0, card)]
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11

	var result = resolver_script.new().resolve(content, rng)

	_expect(result.gold == 0, "a zero-chance gold entry awards no gold")
	_expect(result.cards.is_empty(), "a zero-chance card entry awards no card")


func _test_independent_gold_entries_sum(drop_entry_script: Script, resolver_script: Script) -> void:
	var content := _content_with_entries(
		[_gold_drop(drop_entry_script, 1.0, 8), _gold_drop(drop_entry_script, 1.0, 5)]
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19

	var result = resolver_script.new().resolve(content, rng)

	_expect(result.gold == 13, "multiple successful gold entries award their combined amount")


func _test_invalid_entries_are_skipped_without_suppressing_valid_entries(
	drop_entry_script: Script, resolver_script: Script
) -> void:
	var invalid_gold = _gold_drop(drop_entry_script, 1.0, -1)
	var valid_gold = _gold_drop(drop_entry_script, 1.0, 5)
	var missing_card = _card_drop(drop_entry_script, 1.0, null)
	var content := _content_with_entries([invalid_gold, missing_card, valid_gold])
	var rng := RandomNumberGenerator.new()
	rng.seed = 29

	var result = resolver_script.new().resolve(content, rng)

	_expect(result.gold == 5, "invalid entries do not prevent later valid entries from awarding")
	_expect(result.cards.is_empty(), "missing-card entries are skipped")


func _test_entry_validation_rejects_invalid_configuration(drop_entry_script: Script) -> void:
	var invalid_chance_low = _gold_drop(drop_entry_script, -0.1, 1)
	var invalid_chance_high = _gold_drop(drop_entry_script, 1.1, 1)
	var invalid_gold = _gold_drop(drop_entry_script, 1.0, 0)
	var invalid_card = _card_drop(drop_entry_script, 1.0, null)

	_expect(not invalid_chance_low.validate().is_empty(), "validation rejects a chance below zero")
	_expect(not invalid_chance_high.validate().is_empty(), "validation rejects a chance above one")
	_expect(not invalid_gold.validate().is_empty(), "validation rejects a non-positive gold amount")
	_expect(not invalid_card.validate().is_empty(), "validation rejects a missing card resource")


func _content_with_entries(entries: Array) -> MonsterEventContent:
	var content := MonsterEventContent.new()
	for entry in entries:
		content.drop_entries.append(entry)
	return content


func _gold_drop(drop_entry_script: Script, chance: float, amount: int):
	var entry = drop_entry_script.new()
	entry.set("kind", 0)
	entry.set("chance", chance)
	entry.set("gold_amount", amount)
	return entry


func _card_drop(drop_entry_script: Script, chance: float, card: CardData):
	var entry = drop_entry_script.new()
	entry.set("kind", 1)
	entry.set("chance", chance)
	entry.set("card_data", card)
	return entry


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
