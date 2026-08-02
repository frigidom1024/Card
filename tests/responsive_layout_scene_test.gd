extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const LayoutConfigScript = preload("res://scripts/game/layout_config.gd")
var _failure_count := 0

func _init() -> void:
    call_deferred("_run_test")

func _run_test() -> void:
    var config := ConfigFile.new()
    _expect(config.load("res://project.godot") == OK, "project configuration loads")
    _expect(config.get_value("display", "window/size/viewport_width") == 1920, "viewport width is 1920")
    _expect(config.get_value("display", "window/size/viewport_height") == 1080, "viewport height is 1080")
    _expect(LayoutConfigScript.DESIGN_VIEWPORT_SIZE == Vector2(1920, 1080), "gameplay design size matches the default resolution")
    _expect(config.get_value("display", "window/stretch/mode") == "canvas_items", "canvas items stretching stays enabled")
    _expect(config.get_value("display", "window/stretch/aspect") == "expand", "viewport expands instead of letterboxing gameplay root")

    var main := MainScene.instantiate()
    root.add_child(main)
    await process_frame
    var actual_min_window_size := DisplayServer.window_get_min_size()
    if DisplayServer.get_name() == "headless":
        _expect(actual_min_window_size == Vector2i.ZERO, "headless display server exposes no window minimum")
        _expect(main.is_node_ready(), "main reaches _ready under the headless display server")
    else:
        _expect(actual_min_window_size == LayoutConfigScript.MIN_WINDOW_SIZE, "main configures the desktop minimum window size")

    var background_layer := main.get_node_or_null("BackgroundLayer") as CanvasLayer
    var background := main.get_node_or_null("BackgroundLayer/BackgroundFill") as ColorRect
    var manager := main.get_node_or_null("GameManager")
    _expect(background_layer != null, "main owns a canvas background layer")
    if background_layer != null:
        _expect(background_layer.layer == -10, "background layer renders behind gameplay")
    _expect(
        background_layer != null
        and manager != null
        and main.get_children().find(background_layer) < main.get_children().find(manager),
        "background layer appears before game manager"
    )
    _expect(background != null, "background layer owns a background fill")
    if background != null:
        _expect(background.anchors_preset == Control.PRESET_FULL_RECT, "background fill covers the window")
        _expect(background.mouse_filter == Control.MOUSE_FILTER_IGNORE, "background never blocks game input")
        _expect(background.color == Color(0.035, 0.075, 0.055, 1), "background fill uses the safe forest green")
    if background != null:
        background.size = Vector2(1.0, 1.0)
        root.get_viewport().size_changed.emit()
        await process_frame
        _expect(
            background.position == Vector2.ZERO
            and background.size.is_equal_approx(root.get_viewport().get_visible_rect().size),
            "background fill resizes to the complete visible viewport after a window resize"
        )
    _expect(manager != null and manager.get_node_or_null("GameplayCanvas") != null, "game manager exposes gameplay canvas above background")
    _expect(LayoutConfigScript.MIN_WINDOW_SIZE == Vector2i(1280, 720), "minimum desktop window is 1280x720")
    main.free()
    quit(1 if _failure_count > 0 else 0)

func _expect(condition: bool, message: String) -> void:
    if not condition:
        _failure_count += 1
        push_error(message)
