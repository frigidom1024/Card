extends SceneTree

const EventInteractionControllerScript := preload("res://scripts/game/event/event_interaction_controller.gd")
const EventDataScript := preload("res://scripts/game/event/core/event_data.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_shop_interaction_has_one_active_lifecycle()
	_test_treasure_claim_finishes_the_active_lifecycle()
	quit(1 if _failure_count > 0 else 0)


func _test_shop_interaction_has_one_active_lifecycle() -> void:
	var controller := EventInteractionControllerScript.new()
	var shop_data := EventDataScript.new()
	shop_data.event_id = "test_shop"
	shop_data.event_type = EventData.EventType.SHOP
	var instance := shop_data.create_instance()
	var events: Array[String] = []
	controller.interaction_started.connect(func(started: EventInstance) -> void:
		_expect(started == instance, "controller starts the supplied shop event")
		events.append("started")
	)
	controller.interaction_finished.connect(func(finished: EventInstance) -> void:
		_expect(finished == instance, "controller finishes the active shop event")
		events.append("finished")
	)

	controller.begin(instance, null, [])
	_expect(controller.get_active_event() == instance, "controller owns the active interaction state")
	controller.close_shop()
	_expect(controller.get_active_event() == null, "closing the shop clears active interaction state")
	_expect(events == ["started", "finished"], "shop uses one explicit interaction lifecycle")


func _test_treasure_claim_finishes_the_active_lifecycle() -> void:
	var controller := EventInteractionControllerScript.new()
	var treasure_data := EventDataScript.new()
	treasure_data.event_id = "test_treasure"
	treasure_data.event_type = EventData.EventType.TREASURE
	var instance := treasure_data.create_instance()
	var events: Array[String] = []
	controller.interaction_started.connect(func(_started: EventInstance) -> void:
		events.append("started")
	)
	controller.interaction_finished.connect(func(_finished: EventInstance) -> void:
		events.append("finished")
	)

	controller.begin(instance, null, [])
	_expect(controller.get_active_event() == instance, "controller starts a treasure interaction")
	controller.claim_treasure(0)
	_expect(controller.get_active_event() == null, "claiming a treasure completes its interaction lifecycle")
	_expect(events == ["started", "finished"], "treasure claim emits exactly one finished lifecycle event")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
