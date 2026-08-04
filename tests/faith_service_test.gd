extends SceneTree

const FaithServicePath := "res://scripts/player/faith_service.gd"

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_manual_chain_retraction_can_create_faith_debt()
	quit(0 if _failure_count == 0 else 1)


func _test_manual_chain_retraction_can_create_faith_debt() -> void:
	_expect(ResourceLoader.exists(FaithServicePath), "FaithService exists as the faith-rule entry point")
	if not ResourceLoader.exists(FaithServicePath):
		return
	var script := load(FaithServicePath) as GDScript
	var service: Object = script.new() if script != null else null
	_expect(service.has_method("configure"), "FaithService accepts the runtime PlayerData")
	_expect(service.has_method("resolve_manual_chain_retraction"), "FaithService resolves manual chain retractions")
	if not service.has_method("configure") or not service.has_method("resolve_manual_chain_retraction"):
		return

	var player := PlayerData.new()
	player.faith = 1
	var changed_values: Array[int] = []
	var spawn_requests: Array[bool] = []
	service.faith_changed.connect(func(current_faith: int): changed_values.append(current_faith))
	service.echo_spawn_requested.connect(func(): spawn_requests.append(true))
	service.configure(player)

	service.resolve_manual_chain_retraction()
	_expect(player.faith == 0, "the service spends faith from its configured PlayerData")
	_expect(changed_values == [0], "the service publishes the updated faith value")
	_expect(spawn_requests.size() == 1, "reaching zero faith requests one residual encounter")

	service.resolve_manual_chain_retraction()
	_expect(player.faith == -1, "faith can become negative after another manual retraction")
	_expect(changed_values == [0, -1], "each manual retraction publishes exactly one faith update")
	_expect(spawn_requests.size() == 2, "negative faith requests one residual encounter per manual retraction")
	_expect(service.get_player_data() == player, "FaithService retains access to the configured PlayerData")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
