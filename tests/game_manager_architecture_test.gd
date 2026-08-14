extends SceneTree

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game_manager.gd")
	var exploration_source := FileAccess.get_file_as_string(
		"res://scripts/game/exploration/exploration_coordinator.gd"
	)
	var flow_source := FileAccess.get_file_as_string(
		"res://scripts/game/run/run_flow_coordinator.gd"
	)
	var scene_source := FileAccess.get_file_as_string("res://scenes/game/game_manager.tscn")
	_expect(
		not source.is_empty(), "GameManager source is available for structural regression checks"
	)
	_expect(
		not exploration_source.is_empty(),
		"ExplorationCoordinator source is available for boundary checks"
	)
	_expect(
		not flow_source.is_empty(),
		"RunFlowCoordinator source is available for routing boundary checks"
	)
	_expect(
		not scene_source.is_empty(),
		"GameManager scene is available for hover-preview composition checks"
	)
	_expect(
		source.contains("EventHoverPreviewCoordinatorScript := preload("),
		"GameManager preloads the board-event hover preview coordinator"
	)
	_expect(
		source.contains("@onready var event_hover_preview: EventHoverPreview = $EventHoverPreviewLayer/EventHoverPreview"),
		"GameManager receives the hover preview through a scene dependency"
	)
	_expect(
		source.contains("var _event_hover_preview_coordinator: EventHoverPreviewCoordinator"),
		"GameManager retains a typed hover-preview composition dependency"
	)
	_expect(
		source.contains("func _configure_event_hover_preview() -> bool:"),
		"GameManager configures board-event hover previews in a dedicated composition step"
	)
	_expect(
		source.contains("if not _configure_event_hover_preview():"),
		"GameManager initializes hover previews as part of run setup"
	)
	_expect(
		not source.contains("EventHoverPreviewFormatter"),
		"GameManager does not format board-event preview content"
	)
	_expect(
		not source.contains("EncounterEventContent"),
		"GameManager does not inspect encounter content for hover previews"
	)
	_expect(
		not source.contains("ShopEventContent"),
		"GameManager does not inspect shop content for hover previews"
	)
	_expect(
		not source.contains("TreasureEventContent"),
		"GameManager does not inspect treasure content for hover previews"
	)
	_expect(
		scene_source.contains('path="res://scenes/game/event_hover_preview.tscn"'),
		"GameManager scene instantiates the shared hover preview panel"
	)
	_expect(
		scene_source.contains('[node name="EventHoverPreviewLayer" type="CanvasLayer" parent="."'),
		"GameManager scene provides a dedicated hover-preview canvas layer"
	)
	_expect(
		scene_source.contains('[node name="EventHoverPreview" parent="EventHoverPreviewLayer"'),
		"GameManager scene places the shared preview panel in its overlay layer"
	)
	_expect(
		scene_source.contains("layer = 5"),
		"Hover-preview layer renders above board events"
	)
	_expect(
		scene_source.contains("layer = 10"),
		"Event modal layer renders above the hover-preview layer"
	)
	_expect(
		not exploration_source.contains("CardChainRuleService"),
		"ExplorationCoordinator does not own card-chain rule execution"
	)
	_expect(
		source.contains("func _configure_exploration() -> bool:"),
		"GameManager names exploration setup as coordinator composition"
	)
	_expect(
		not source.contains("func init_events"),
		"GameManager does not claim responsibility for direct event initialization"
	)
	_expect(
		source.contains("var _exploration_coordinator: ExplorationCoordinator"),
		"GameManager holds exploration through the coordinator facade type"
	)
	_expect(
		source.contains("ExplorationCoordinatorScript.new()"),
		"GameManager constructs the exploration coordinator facade"
	)
	_expect(
		source.contains("CardChainCoordinatorScript.new()"),
		"GameManager composes card-chain reactions through CardChainCoordinator"
	)
	_expect(
		not source.contains("Fog" + "Service"),
		"GameManager does not directly construct the removed fog service"
	)
	_expect(
		not source.contains("ExplorationEventService.new()"),
		"GameManager does not directly construct ExplorationEventService"
	)
	_expect(
		not source.contains("BossPressureService.new()"),
		"GameManager does not directly construct BossPressureService"
	)
	_expect(
		source.contains("RunSetupCoordinatorScript.new()"),
		"GameManager composes run initialization through RunSetupCoordinator"
	)
	_expect(
		source.contains("var _run_setup: RunSetupCoordinator"),
		"GameManager retains a typed run-setup composition dependency"
	)
	_expect(
		not source.contains("PersistentMarketCoordinator"),
		"GameManager no longer depends on the legacy persistent-market coordinator"
	)
	_expect(
		source.contains("@onready var shop: Shop = $GameplayCanvas/Hud/Shop"),
		"GameManager receives the resident Shop through the active page"
	)
	_expect(
		source.contains("@onready var reclaim_zone: ReclaimZone = $GameplayCanvas/Hud/ReclaimZone"),
		"GameManager receives the resident ReclaimZone through the active page"
	)
	_expect(
		source.contains("var _event_modal_coordinator: EventModalCoordinator"),
		"GameManager retains a typed event-modal composition dependency"
	)
	_expect(
		source.contains("var _encounter_resolution: EncounterResolutionCoordinator"),
		"GameManager retains a typed encounter-resolution composition dependency"
	)
	_expect(
		not source.contains("var _encounter_combat_flow"),
		"GameManager does not retain unused combat-flow implementation state"
	)
	_expect(
		not source.contains("RunCardServiceScript.new()"),
		"GameManager does not construct runtime card ownership directly"
	)
	_expect(
		not source.contains("EventInteractionControllerScript.new()"),
		"GameManager does not construct event interaction lifecycle directly"
	)
	_expect(
		not source.contains("CombatStats.from_data(player_data.base_stats)"),
		"GameManager does not build run combat stats directly"
	)
	_expect(
		source.contains("EncounterResolutionCoordinatorScript.new()"),
		"GameManager composes confirmed encounter settlement through EncounterResolutionCoordinator"
	)
	_expect(
		not source.contains("func _apply_combat_result"),
		"GameManager does not apply combat results directly"
	)
	_expect(
		not source.contains("func _strengthen_encounter_monster"),
		"GameManager does not own retreat monster strengthening"
	)
	_expect(
		not source.contains("PersistentMarketCoordinatorScript.new()"),
		"GameManager does not construct the removed persistent market coordinator"
	)
	_expect(
		source.contains("func _configure_shop() -> bool:"),
		"GameManager configures the resident Shop directly"
	)
	_expect(
		source.contains("func _configure_reclaim_zone() -> bool:"),
		"GameManager configures the resident ReclaimZone directly"
	)
	_expect(
		not scene_source.contains('PersistentMarket'),
		"GameManager scene does not instantiate the legacy PersistentMarket"
	)
	_expect(
		not scene_source.contains('CardManager'),
		"GameManager scene does not instantiate the legacy CardManager"
	)
	_expect(
		not scene_source.contains('HandArea'),
		"GameManager scene does not instantiate the legacy HandArea"
	)
	_expect(
		not source.contains("PersistentMarketStateScript.new()"),
		"GameManager does not construct persistent market state"
	)
	_expect(
		not source.contains("PersistentMarketResolverScript.new()"),
		"GameManager does not construct persistent market resolver"
	)
	_expect(
		not source.contains("func _on_market_purchase_requested"),
		"GameManager does not own market purchase flow"
	)
	_expect(
		not source.contains("func _on_market_reclaim_requested"),
		"GameManager does not own market reclaim flow"
	)
	_expect(
		not source.contains("func _on_market_refresh_requested"),
		"GameManager does not own market refresh flow"
	)
	_expect(
		source.contains("EventModalCoordinatorScript.new()"),
		"GameManager composes event modals through EventModalCoordinator"
	)
	_expect(
		source.contains("var _event_modal_coordinator"),
		"GameManager retains the event modal coordinator"
	)
	_expect(
		source.contains("var _run_context: RunContext"),
		"GameManager owns the run context composition root reference"
	)
	_expect(
		source.contains("var _placement_pipeline: PlacementPipelineCoordinator"),
		"GameManager owns the placement pipeline composition root reference"
	)
	_expect(
		source.contains("var _run_flow: RunFlowCoordinator"),
		"GameManager owns the run-flow composition root reference"
	)
	_expect(
		source.contains("var _presentation: RunPresentationCoordinator"),
		"GameManager owns the run-presentation composition root reference"
	)
	_expect(
		source.contains("func get_run_context() -> RunContext:"),
		"GameManager exposes the run context compatibility getter"
	)
	_expect(
		source.contains("func get_run_flow() -> RunFlowCoordinator:"),
		"GameManager exposes the run-flow compatibility getter"
	)
	_expect(
		not source.contains("func _on_board_placement_committed"),
		"GameManager no longer owns a Board placement callback"
	)
	_expect(
		not source.contains("_on_modal_combat_settlement_confirmed"),
		"GameManager does not consume combat settlement confirmations"
	)
	_expect(
		not source.contains("_on_board_event_triggered"),
		"GameManager does not consume placement event interactions"
	)
	_expect(
		not source.contains("var _market_rng"),
		"GameManager does not create an independent market random stream"
	)
	_expect(
		not source.contains("var _encounter_reward_rng"),
		"GameManager does not create an independent encounter reward random stream"
	)
	_expect(
		not flow_source.contains('get("_exploration")'),
		"RunFlowCoordinator reaches faith echo through an explicit port"
	)
	_expect(
		not source.contains("ShopEventResolver.new("),
		"GameManager does not construct the shop event resolver"
	)
	_expect(
		not source.contains("TreasureEventResolver.new("),
		"GameManager does not construct the treasure event resolver"
	)
	_expect(
		not source.contains("func _on_shop_purchase_requested"),
		"GameManager does not own shop purchase flow"
	)
	_expect(
		not source.contains("func _on_treasure_reward_requested"),
		"GameManager does not own treasure reward flow"
	)
	var threshold_array := RegEx.new()
	threshold_array.compile("(?m)^\\s*(?:var|const)\\s+\\w*(?:threshold|schedule)\\w*.*=\\s*\\[")
	_expect(
		threshold_array.search(source) == null, "GameManager does not own event threshold arrays"
	)
	quit(1 if _failure_count > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
