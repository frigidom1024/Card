extends SceneTree

const CARD_SCENE := preload("res://scenes/card/card.tscn")
const DRAGGER_LAYER_SCENE := preload("res://scenes/drag_layer/dragger_layer.tscn")

var _failures := 0


class RecordingZone:
	extends CardZone

	var zone_label := "zone"
	var owned: Array[Card] = []
	var calls: Array[String] = []
	var shared_calls: Array[String] = []
	var accept_target := true
	var owns_query_count := 0

	func owns_card(card: Card) -> bool:
		owns_query_count += 1
		return owned.has(card)

	func start_drag(_card: Card) -> void:
		_record("start")

	func update_drag(_card: Card) -> void:
		pass

	func can_trans_from_source(_card: Card) -> bool:
		return true

	func can_trans_to_target(_card: Card) -> bool:
		return accept_target

	func drag_end_target(_card: Card, ok: bool) -> bool:
		_record("target:%s" % ok)
		return ok and accept_target

	func drag_end_source(_card: Card, ok: bool) -> bool:
		_record("source:%s" % ok)
		return true

	func _record(call_name: String) -> void:
		calls.append(call_name)
		shared_calls.append("%s:%s" % [zone_label, call_name])


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_registered_zone_detection_and_unregistration()
	await _test_locked_layer_rejects_drag_start()
	await _test_unique_owner_is_cached_after_membership_changes()
	await _test_duplicate_owners_reject_drag()
	await _test_zero_source_can_be_accepted_by_target()
	await _test_same_zone_commits_target_before_source()
	quit(1 if _failures > 0 else 0)


func _test_registered_zone_detection_and_unregistration() -> void:
	var dragger := _make_dragger()
	var first_zone := _make_zone("first", Vector2(0.0, 0.0), Vector2(300.0, 200.0))
	var second_zone := _make_zone("second", Vector2(350.0, 0.0), Vector2(300.0, 200.0))
	await process_frame

	dragger.register_zone(first_zone)
	dragger.register_zone(second_zone)
	_expect(
		dragger.get_zone_at(Vector2(50.0, 50.0)) == first_zone,
		"DraggerLayer detects the first registered CardZone"
	)
	_expect(
		dragger.get_zone_at(Vector2(400.0, 50.0)) == second_zone,
		"DraggerLayer detects another registered CardZone"
	)
	_expect(
		dragger.get_zone_at(Vector2(700.0, 50.0)) == null,
		"DraggerLayer reports no zone outside registered bounds"
	)

	dragger.unregister_zone(first_zone)
	_expect(
		dragger.get_zone_at(Vector2(50.0, 50.0)) == null,
		"unregistered CardZone no longer participates in detection"
	)
	_free_nodes([first_zone, second_zone, dragger])


func _test_locked_layer_rejects_drag_start() -> void:
	var fixture := await _make_drag_fixture()
	var dragger: DraggerLayer = fixture.dragger
	var source: RecordingZone = fixture.source
	var card: Card = fixture.card
	source.owned.append(card)
	dragger.register_zone(source)

	dragger.set_interaction_locked(true)
	_expect(not dragger.start_drag(card), "locked DraggerLayer rejects drag start")
	_expect(dragger.dragging_card == null, "rejected locked drag does not retain a Card")
	_expect(source.owns_query_count == 0, "locked drag rejects before resolving source ownership")
	dragger.set_interaction_locked(false)
	_expect(not dragger.is_interaction_locked(), "DraggerLayer exposes the released lock state")
	_free_drag_fixture(fixture)


func _test_unique_owner_is_cached_after_membership_changes() -> void:
	var fixture := await _make_drag_fixture()
	var dragger: DraggerLayer = fixture.dragger
	var source: RecordingZone = fixture.source
	var target: RecordingZone = fixture.target
	var card: Card = fixture.card
	var shared_calls: Array[String] = fixture.shared_calls
	source.owned.append(card)
	dragger.register_zone(source)
	dragger.register_zone(target)

	_expect(dragger.start_drag(card), "a unique registered owner can start the drag")
	_expect(source.owns_query_count == 1, "the source owner is resolved once at drag start")
	source.owned.erase(card)
	target.owned.append(card)
	_expect(dragger.end_drag(card), "the target accepts a drag after membership changes")
	_expect(
		shared_calls == ["source:start", "target:target:true", "source:source:true"],
		"target commits before the cached source even when target membership changes"
	)
	_expect(source.owns_query_count == 1, "DraggerLayer does not resolve source ownership again")
	_free_drag_fixture(fixture)


func _test_duplicate_owners_reject_drag() -> void:
	var fixture := await _make_drag_fixture()
	var dragger: DraggerLayer = fixture.dragger
	var source: RecordingZone = fixture.source
	var target: RecordingZone = fixture.target
	var card: Card = fixture.card
	source.owned.append(card)
	target.owned.append(card)
	dragger.register_zone(source)
	dragger.register_zone(target)

	_expect(not dragger.start_drag(card), "multiple registered owners reject an ambiguous drag")
	_expect(dragger.dragging_card == null, "duplicate-owner rejection keeps no active drag")
	_expect(source.calls.is_empty() and target.calls.is_empty(), "duplicate owners receive no drag lifecycle calls")
	_free_drag_fixture(fixture)


func _test_zero_source_can_be_accepted_by_target() -> void:
	var fixture := await _make_drag_fixture()
	var dragger: DraggerLayer = fixture.dragger
	var target: RecordingZone = fixture.target
	var card: Card = fixture.card
	dragger.register_zone(target)

	_expect(dragger.start_drag(card), "a Card with no registered owner can start dragging")
	_expect(dragger.end_drag(card), "a target can accept a zero-source Card")
	_expect(
		target.calls == ["target:true"],
		"zero-source drag commits only the accepting target"
	)
	_free_drag_fixture(fixture)


func _test_same_zone_commits_target_before_source() -> void:
	var fixture := await _make_drag_fixture()
	var dragger: DraggerLayer = fixture.dragger
	var source: RecordingZone = fixture.source
	var target: RecordingZone = fixture.target
	var card: Card = fixture.card
	var shared_calls: Array[String] = fixture.shared_calls
	source.position = target.position
	source.size = target.size
	source.owned.append(card)
	dragger.register_zone(source)

	_expect(dragger.start_drag(card), "same-zone Card starts from its stable owner")
	_expect(dragger.end_drag(card), "same-zone target accepts the drop")
	_expect(
		shared_calls == ["source:start", "source:target:true", "source:source:true"],
		"same-zone drag commits target before source without a finalize phase"
	)
	_free_drag_fixture(fixture)


func _make_drag_fixture() -> Dictionary:
	var shared_calls: Array[String] = []
	var dragger := _make_dragger()
	var source := _make_zone("source", Vector2(500.0, 0.0), Vector2(200.0, 200.0))
	var target := _make_zone("target", Vector2(80.0, 80.0), Vector2(260.0, 260.0))
	source.shared_calls = shared_calls
	target.shared_calls = shared_calls
	var card := CARD_SCENE.instantiate() as Card
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.position = Vector2(100.0, 100.0)
	root.add_child(card)
	await process_frame
	return {
		"dragger": dragger,
		"source": source,
		"target": target,
		"card": card,
		"shared_calls": shared_calls,
	}


func _make_dragger() -> DraggerLayer:
	var dragger := DRAGGER_LAYER_SCENE.instantiate() as DraggerLayer
	root.add_child(dragger)
	return dragger


func _make_zone(zone_label: String, zone_position: Vector2, zone_size: Vector2) -> RecordingZone:
	var zone := RecordingZone.new()
	zone.zone_label = zone_label
	zone.set_anchors_preset(Control.PRESET_TOP_LEFT)
	zone.position = zone_position
	zone.size = zone_size
	root.add_child(zone)
	return zone


func _free_drag_fixture(fixture: Dictionary) -> void:
	_free_nodes([fixture.card, fixture.source, fixture.target, fixture.dragger])


func _free_nodes(nodes: Array) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			node.free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
