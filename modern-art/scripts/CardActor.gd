extends Area2D

signal clicked(card_id: int)
signal hover_changed(card_id: int, is_hover: bool)

@export var card_size: Vector2 = Vector2(160, 224)

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
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# 字体（可选）
	var font_path := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
	if ResourceLoader.exists(font_path):
		_font = load(font_path)

func set_textures(frame_tex: Texture2D, face_tex: Texture2D) -> void:
	frame.texture = frame_tex
	face.texture = face_tex
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
		z_index = 1000
		_tween.tween_property(self, "position", base_position + Vector2(0, -28), 0.10)
		_tween.parallel().tween_property(self, "scale", Vector2.ONE * 1.10, 0.10)
		_tween.parallel().tween_property(self, "rotation", base_rotation * 0.15, 0.10)
	else:
		z_index = 0
		_tween.tween_property(self, "position", base_position, 0.12)
		_tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.12)
		_tween.parallel().tween_property(self, "rotation", base_rotation, 0.12)

func play_to(target_pos: Vector2, target_rot: float, duration: float = 0.22) -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position", target_pos, duration)
	_tween.parallel().tween_property(self, "rotation", target_rot, duration)
	_tween.parallel().tween_property(self, "scale", Vector2.ONE * 1.05, duration)

func _draw() -> void:
	if _font == null:
		return

	var title: String = String(card_data.get("title", ""))

	# 顶部：作品名（截断）
	var top := title
	if top.length() > 8:
		top = top.substr(0, 8) + "…"

	_font.draw_string(get_canvas_item(), Vector2(-card_size.x * 0.5 + 8, -card_size.y * 0.5 + 18), top, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, Color(1, 1, 1, 0.95))
	# 底部：拍卖类型（中文在后续由外部传入替换）
	_font.draw_string(get_canvas_item(), Vector2(-card_size.x * 0.5 + 8, card_size.y * 0.5 - 10), _subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, Color(1, 1, 1, 0.85))

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			emit_signal("clicked", card_id)

func _input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	# Godot 4 中用回调覆盖更不容易被信号/类型问题影响
	_on_input_event(viewport, event, shape_idx)

func _on_mouse_entered() -> void:
	set_hovered(true)

func _on_mouse_exited() -> void:
	set_hovered(false)

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

