class_name GameplayCanvas
extends Node2D


func get_applied_scale(viewport_size: Vector2) -> float:
    if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
        return LayoutConfig.MIN_GAMEPLAY_SCALE
    var width_scale := viewport_size.x / LayoutConfig.DESIGN_VIEWPORT_SIZE.x
    var height_scale := viewport_size.y / LayoutConfig.DESIGN_VIEWPORT_SIZE.y
    return clampf(minf(width_scale, height_scale), LayoutConfig.MIN_GAMEPLAY_SCALE, LayoutConfig.MAX_GAMEPLAY_SCALE)


func fit_to_viewport(viewport_size: Vector2) -> void:
    var applied_scale := get_applied_scale(viewport_size)
    scale = Vector2.ONE * applied_scale
    position = (viewport_size - LayoutConfig.DESIGN_VIEWPORT_SIZE * applied_scale) * 0.5