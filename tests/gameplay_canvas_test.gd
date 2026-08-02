extends SceneTree

const GameplayCanvasScript = preload("res://scripts/game/gameplay_canvas.gd")
const LayoutConfigScript = preload("res://scripts/game/layout_config.gd")
var _failure_count := 0

func _init() -> void:
    _expect(LayoutConfigScript.DESIGN_VIEWPORT_SIZE == Vector2(1600, 900), "design size is 1600x900")
    _expect(LayoutConfigScript.MIN_GAMEPLAY_SCALE == 0.8, "minimum gameplay scale is 0.8")
    _expect(LayoutConfigScript.MAX_GAMEPLAY_SCALE == 1.35, "maximum gameplay scale is 1.35")

    var canvas := GameplayCanvasScript.new()
    _expect(is_equal_approx(canvas.get_applied_scale(Vector2(1600, 900)), 1.0), "design viewport uses scale 1.0")
    _expect(is_equal_approx(canvas.get_applied_scale(Vector2(1920, 1200)), 1.2), "16:10 viewport uses the limiting axis")
    _expect(is_equal_approx(canvas.get_applied_scale(Vector2(2560, 1080)), 1.2), "ultrawide viewport does not stretch horizontally")
    _expect(is_equal_approx(canvas.get_applied_scale(Vector2(2560, 1440)), 1.35), "large viewport clamps to maximum scale")
    _expect(is_equal_approx(canvas.get_applied_scale(Vector2(1280, 720)), 0.8), "minimum window uses minimum scale")

    canvas.fit_to_viewport(Vector2(2560, 1080))
    _expect(canvas.scale == Vector2(1.2, 1.2), "canvas uses a uniform scale")
    _expect(canvas.position.is_equal_approx(Vector2(320, 0)), "ultrawide canvas is centered horizontally")

    canvas.fit_to_viewport(Vector2(2560, 1440))
    _expect(canvas.scale == Vector2(1.35, 1.35), "maximum scale applies to both axes")
    _expect(canvas.position.is_equal_approx(Vector2(200, 112.5)), "clamped canvas remains centered")
    canvas.free()
    quit(1 if _failure_count > 0 else 0)

func _expect(condition: bool, message: String) -> void:
    if not condition:
        _failure_count += 1
        push_error(message)