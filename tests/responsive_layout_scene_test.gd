extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const LayoutConfigScript = preload("res://scripts/game/layout_config.gd")
var _failure_count := 0

func _init() -> void:
    var config := ConfigFile.new()
    _expect(config.load("res://project.godot") == OK, "project configuration loads")
    _expect(config.get_value("display", "window/stretch/mode") == "canvas_items", "canvas items stretching stays enabled")
    _expect(config.get_value("display", "window/stretch/aspect") == "expand", "viewport expands instead of letterboxing gameplay root")

    var main := MainScene.instantiate()
    root.add_child(main)
    var background_layer := main.get_node_or_null("BackgroundLayer")
    var background := main.get_node_or_null("BackgroundLayer/BackgroundFill") as ColorRect
    var manager := main.get_node_or_null("GameManager")
    _expect(background_layer is CanvasLayer, "main owns a canvas background layer")
    _expect(background != null, "background layer owns a background fill")
    if background != null:
        _expect(background.anchors_preset == Control.PRESET_FULL_RECT, "background fill covers the window")
        _expect(background.mouse_filter == Control.MOUSE_FILTER_IGNORE, "background never blocks game input")
    _expect(manager != null and manager.get_node_or_null("GameplayCanvas") != null, "game manager exposes gameplay canvas above background")
    _expect(LayoutConfigScript.MIN_WINDOW_SIZE == Vector2i(1280, 720), "minimum desktop window is 1280x720")
    main.free()
    quit(1 if _failure_count > 0 else 0)

func _expect(condition: bool, message: String) -> void:
    if not condition:
        _failure_count += 1
        push_error(message)