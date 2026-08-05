extends SceneTree

const FaithServicePath := "res://scripts/player/faith_service.gd"
const ChainRetractionTransactionPath := "res://scripts/game/chain_retraction_transaction.gd"

var _failure_count := 0

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_confirmed_chain_retraction_can_create_faith_debt()
	quit(0 if _failure_count == 0 else 1)

func _test_confirmed_chain_retraction_can_create_faith_debt() -> void:
	_expect(ResourceLoader.exists(FaithServicePath), "FaithService exists as the faith-rule entry point")
	_expect(ResourceLoader.exists(ChainRetractionTransactionPath), "confirmed retractions have a dedicated transaction type")
	if not ResourceLoader.exists(FaithServicePath) or not ResourceLoader.exists(ChainRetractionTransactionPath):
		return
	var script := load(FaithServicePath) as GDScript
	var transaction_script := load(ChainRetractionTransactionPath) as GDScript
	var service: Object = script.new() if script != null else null
	var transaction: Object = transaction_script.new() if transaction_script != null else null
	_expect(service != null and service.has_method("configure"), "FaithService accepts the runtime PlayerData")
	_expect(service != null and service.has_method("resolve_confirmed_chain_retraction"), "FaithService resolves confirmed chain-retraction transactions")
	if service == null or transaction == null or not service.has_method("configure") or not service.has_method("resolve_confirmed_chain_retraction"):
		return
	var player := PlayerData.new()
	player.faith = 1
	var changed_values: Array[int] = []
	var spawn_requests: Array[bool] = []
	service.faith_changed.connect(func(current_faith: int): changed_values.append(current_faith))
	service.echo_spawn_requested.connect(func(): spawn_requests.append(true))
	service.configure(player)
	service.call("resolve_confirmed_chain_retraction", transaction)
	_expect(player.faith == 0, "the service spends faith from its configured PlayerData after confirmation")
	_expect(changed_values == [0], "the service publishes the updated faith value")
	_expect(spawn_requests.size() == 1, "reaching zero faith requests one residual encounter")
	service.call("resolve_confirmed_chain_retraction", transaction)
	_expect(player.faith == -1, "faith can become negative after another confirmed retraction")
	_expect(changed_values == [0, -1], "each confirmed retraction publishes exactly one faith update")
	_expect(spawn_requests.size() == 2, "negative faith requests one residual encounter per confirmed retraction")
	_expect(service.get_player_data() == player, "FaithService retains access to the configured PlayerData")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)