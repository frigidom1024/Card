extends SceneTree

const SESSION_ENTRYPOINT := "res://scripts/combat_framework/runtime/combat_battle_session.gd"

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var session_script := load(SESSION_ENTRYPOINT)
	_expect(session_script != null, "新版战斗框架必须能从独立的 combat_framework 入口加载")
	if session_script != null:
		var session = session_script.new(
			CombatStateSchema.create_initial_state(
				{"entity_id": "player", "hp": 10},
				{"entity_id": "monster", "hp": 3},
				{"head": {"points": 5}},
				["head"]
			)
		)
		session.start()
		session.advance(0.0)
		_expect(session.get_outcome() == CombatBattleOutcome.VICTORY, "独立入口创建的会话必须能够执行战斗")
	quit(1 if _failure_count > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
