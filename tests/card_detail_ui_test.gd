extends SceneTree

const CardDetailStatSealScene = preload("res://scenes/card_view/card_detail_stat_seal.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_formatter_uses_english_display_copy()
	_test_formatter_omits_zero_stat_entries()
	_test_stat_seal_uses_muted_attribute_style()
	_test_attribute_seals_use_distinct_copy_and_colors()
	_test_detail_layers_keep_central_priorities()
	quit(1 if _failure_count > 0 else 0)


func _test_formatter_uses_english_display_copy() -> void:
	_expect(
		CardDetailFormat.rarity_name(CardData.Rarity.RARE) == "RARE",
		"rarity uses English display copy"
	)
	_expect(
		CardDetailFormat.card_type_name(CardData.CardType.ROOT) == "ROOT",
		"root type uses English display copy"
	)
	_expect(
		CardDetailFormat.tag_name(CardData.CardTag.WEAPON) == "WEAPON",
		"tag uses English display copy"
	)
	_expect(
		CardDetailFormat.compact_description("abc", 2) == "a…",
		"long hover descriptions truncate with an ellipsis"
	)


func _test_formatter_omits_zero_stat_entries() -> void:
	var data := CardData.new()
	data.damage = 8
	data.defense = 2
	data.heal = 0

	var entries := CardDetailFormat.stat_entries(data)
	_expect(entries.size() == 2, "zero-value detail stats are omitted")
	_expect(
		entries[0].attribute == CardDetailStatSeal.Attribute.DAMAGE and entries[0].value == 8,
		"damage is first"
	)
	_expect(
		entries[1].attribute == CardDetailStatSeal.Attribute.DEFENSE and entries[1].value == 2,
		"defense follows damage"
	)


func _test_stat_seal_uses_muted_attribute_style() -> void:
	var seal := CardDetailStatSealScene.instantiate() as CardDetailStatSeal
	root.add_child(seal)
	seal.configure(CardDetailStatSeal.Attribute.DAMAGE, 8)

	var value_label := seal.get_node_or_null("ValueLabel") as Label
	_expect(value_label != null and value_label.text == "8 STRIKE", "damage seal uses approved copy")

	var style := seal.get_theme_stylebox("panel") as StyleBoxFlat
	_expect(style != null and style.bg_color.r > style.bg_color.g and style.bg_color.r > style.bg_color.b, "damage seal uses muted red")

	seal.free()


func _test_attribute_seals_use_distinct_copy_and_colors() -> void:
	var colors: Array[Color] = []
	for config in [
		{"attribute": CardDetailStatSeal.Attribute.DAMAGE, "copy": "STRIKE"},
		{"attribute": CardDetailStatSeal.Attribute.DEFENSE, "copy": "GUARD"},
		{"attribute": CardDetailStatSeal.Attribute.HEAL, "copy": "MEND"},
	]:
		var seal := CardDetailStatSealScene.instantiate() as CardDetailStatSeal
		root.add_child(seal)
		seal.configure(config["attribute"], 3)
		var label := seal.get_node_or_null("ValueLabel") as Label
		var style := seal.get_theme_stylebox("panel") as StyleBoxFlat
		_expect(label != null and label.text == "3 %s" % config["copy"], "stat seal uses approved English copy")
		_expect(style != null, "stat seal provides a panel style")
		if style != null:
			colors.append(style.bg_color)
		seal.free()

	_expect(colors.size() == 3 and colors[0] != colors[1] and colors[1] != colors[2] and colors[0] != colors[2], "attribute seals use distinct muted colors")


func _test_detail_layers_keep_central_priorities() -> void:
	_expect(RenderPriority.CARD_INFO_OVERLAY == 5, "hover layer remains centrally configured")
	_expect(RenderPriority.CARD_ZOOM_OVERLAY == 128, "zoom layer remains centrally configured")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)