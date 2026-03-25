extends Label

func start(msg: String, pos: Vector2, col: Color) -> void:
	text = msg
	modulate = col
	position = pos
	visible = true

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position", pos + Vector2(0, -40), 0.55)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.55)
	tw.tween_callback(queue_free)

