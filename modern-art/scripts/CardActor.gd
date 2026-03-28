extends Area2D

signal clicked(card_id: int)
signal hover_changed(card_id: int, is_hover: bool)

@export var card_size: Vector2 = Vector2(144, 256)

@onready var frame: Sprite2D = $Frame
@onready var face: Sprite2D = $Face
@onready var shape: CollisionShape2D = $CollisionShape2D

var card_id: int = -1
var card_data: Dictionary = {}

var _is_hover: bool = false
var _tween: Tween
var _font: Font
var _font_size: int = 14
var _subtitle: String = ""

var base_position: Vector2 = Vector2.ZERO
var base_rotation: float = 0.0
var base_z_index: int = 0

func _ready() -> void:
	input_pickable = true
	# 碰撞区域
	var rs := RectangleShape2D.new()
	rs.size = card_size
	shape.shape = rs

	# Sprite 以中心为基准
	frame.centered = true
	face.centered = true

	# 默认层级
	z_index = 0

	# 仍保留signal连接（兼容性），同时实现_input_event更稳
	input_event.connect(_on_input_event)
	# hover 交由上层（Table2D）统一管理，避免重叠卡牌同时触发多个 hover
	mouse_entered.connect(func(): emit_signal("hover_changed", card_id, true))
	mouse_exited.connect(func(): emit_signal("hover_changed", card_id, false))

	# 字体（可选）
	var font_path := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
	if ResourceLoader.exists(font_path):
		_font = load(font_path)

func set_textures(frame_tex: Texture2D, face_tex: Texture2D) -> void:
	frame.texture = frame_tex
	face.texture = face_tex
	# 让卡面严格铺满 card_size（避免露出边框导致“显示不全”）
	if face_tex != null:
		var sz: Vector2 = face_tex.get_size()
		if sz.x > 0 and sz.y > 0:
			face.scale = Vector2(card_size.x / sz.x, card_size.y / sz.y)
	# 框只作为阴影/底板（可见性降低，避免遮挡原图）
	frame.modulate.a = 0.20
	if frame_tex != null:
		var fsz: Vector2 = frame_tex.get_size()
		if fsz.x > 0 and fsz.y > 0:
			frame.scale = Vector2(card_size.x / fsz.x, card_size.y / fsz.y)
	queue_redraw()

func set_card(card: Dictionary) -> void:
	card_data = card
	card_id = int(card.get("id", -1))
	queue_redraw()

func set_subtitle(s: String) -> void:
	_subtitle = s
	queue_redraw()

func set_font_size(px: int) -> void:
	_font_size = px
	queue_redraw()

func set_base_transform(p: Vector2, rot: float) -> void:
	base_position = p
	base_rotation = rot
	position = p
	rotation = rot

func set_base_z(z: int) -> void:
	base_z_index = z
	if not _is_hover:
		z_index = z

func set_hovered(v: bool) -> void:
	if _is_hover == v:
		return
	_is_hover = v
	emit_signal("hover_changed", card_id, _is_hover)
	_play_hover_anim(_is_hover)

func _play_hover_anim(v: bool) -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_OUT)

	if v:
		z_index = base_z_index + 1000
		_tween.tween_property(self, "position", base_position + Vector2(0, -28), 0.10)
		_tween.parallel().tween_property(self, "scale", Vector2.ONE * 1.10, 0.10)
		_tween.parallel().tween_property(self, "rotation", base_rotation * 0.15, 0.10)
	else:
		z_index = base_z_index
		_tween.tween_property(self, "position", base_position, 0.12)
		_tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.12)
		_tween.parallel().tween_property(self, "rotation", base_rotation, 0.12)

func play_to(
	target_pos: Vector2,
	target_rot: float,
	duration: float = 0.22,
	arc_height: float = 0.0,
	target_scale: float = 1.05
) -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_OUT)
	if arc_height <= 0.0:
		_tween.tween_property(self, "position", target_pos, duration)
		_tween.parallel().tween_property(self, "rotation", target_rot, duration)
		_tween.parallel().tween_property(self, "scale", Vector2.ONE * target_scale, duration)
		return

	var mid: Vector2 = (position + target_pos) * 0.5 + Vector2(0, -arc_height)
	var d1: float = duration * 0.55
	var d2: float = max(0.01, duration - d1)
	var mid_scale: float = max(target_scale, 1.0) + 0.05
	_tween.tween_property(self, "position", mid, d1)
	_tween.parallel().tween_property(self, "scale", Vector2.ONE * mid_scale, d1)
	_tween.parallel().tween_property(self, "rotation", lerp(rotation, target_rot, 0.35), d1)
	_tween.tween_property(self, "position", target_pos, d2)
	_tween.parallel().tween_property(self, "scale", Vector2.ONE * target_scale, d2)
	_tween.parallel().tween_property(self, "rotation", target_rot, d2)

func _draw() -> void:
	if _font == null:
		return

	var title: String = String(card_data.get("title", ""))

	# 上方：拍卖方式标签（带半透明底）
	var pad_x: float = 8.0
	var tag_h: float = 22.0
	var tag_rect := Rect2(Vector2(-card_size.x * 0.5 + 6.0, -card_size.y * 0.5 + 6.0), Vector2(card_size.x - 12.0, tag_h))
	draw_rect(tag_rect, Color(0, 0, 0, 0.35), true)
	draw_rect(tag_rect, Color(1, 1, 1, 0.10), false, 1.0)
	_font.draw_string(
		get_canvas_item(),
		Vector2(-card_size.x * 0.5 + pad_x, -card_size.y * 0.5 + 22),
		_subtitle,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		_font_size,
		Color(1, 1, 1, 0.92)
	)

	# 下方：画作名（温和截断）
	var bottom := title
	if bottom.length() > 10:
		bottom = bottom.substr(0, 10) + "…"
	_font.draw_string(
		get_canvas_item(),
		Vector2(-card_size.x * 0.5 + pad_x, card_size.y * 0.5 - 10),
		bottom,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		_font_size,
		Color(1, 1, 1, 0.92)
	)

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			emit_signal("clicked", card_id)

func _input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	# Godot 4 中用回调覆盖更不容易被信号/类型问题影响
	_on_input_event(viewport, event, shape_idx)

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

