extends SceneTree

const CardScene := preload("res://scenes/card/card.tscn")

var _failure_count := 0

func _init() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var card := CardScene.instantiate() as Button
	root.add_child(card)
	await process_frame

	var card_texture := card.get_node_or_null("CardTexture") as TextureRect
	_expect(card_texture != null, "card exposes one TextureRect as the shader output surface")
	if card_texture != null:
		_expect(card_texture.texture is ViewportTexture, "shader output samples the composed viewport texture")
		_expect(card_texture.material is ShaderMaterial, "shader material is assigned to the composed texture output")

	var composite_viewport := card.get_node_or_null("CardTexture/CompositeViewport") as SubViewport
	_expect(composite_viewport != null, "card owns an offscreen viewport for compositing visual layers")
	_expect(card.get_node_or_null("CardTexture/CompositeViewport/Composite/Card") is Panel, "card frame is rendered inside the composite viewport")
	_expect(card.get_node_or_null("CardTexture/CompositeViewport/Composite/Artwork") is TextureRect, "artwork is rendered inside the composite viewport")
	_expect(card.get_node_or_null("CardTexture/Card") == null, "card frame is not a separate sibling draw pass")
	_expect(card.get_node_or_null("CardTexture/Artwork") == null, "artwork is not a separate sibling draw pass")

	card.free()
	quit(1 if _failure_count > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
