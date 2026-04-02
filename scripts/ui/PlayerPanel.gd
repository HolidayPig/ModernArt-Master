extends PanelContainer

@onready var accent: ColorRect = $Accent
@onready var glow: ColorRect = $Glow
@onready var name_label: Label = $Margin/VBox/NameRow/NameLabel
@onready var status_label: Label = $Margin/VBox/NameRow/StatusLabel
@onready var info_label: Label = $Margin/VBox/InfoRow/InfoLabel
@onready var mini_cards: Control = $MiniCards

var player_id: int = -1
var player_name: String = ""
var _mini_tex_cache: Dictionary = {} # tex_instance_id -> Texture2D
var _active_tween: Tween

const MINI_W: int = 44
const MINI_H: int = 56
const ACCENT_IDLE := Color(0.60, 0.48, 0.24, 0.72)
const ACCENT_ACTIVE := Color(0.94, 0.78, 0.36, 1.0)
const GLOW_IDLE := Color(1, 1, 1, 0.03)
const GLOW_ACTIVE := Color(1.0, 0.96, 0.82, 0.10)
const PANEL_IDLE := Color(0.90, 0.92, 0.96, 0.94)
const PANEL_ACTIVE := Color(1, 1, 1, 1)

func set_player(p: int, name: String) -> void:
	player_id = p
	player_name = name
	name_label.text = name
	if accent != null:
		accent.color = ACCENT_IDLE
	if glow != null:
		glow.color = GLOW_IDLE
		if p == 0:
			glow.color = Color(1.0, 0.95, 0.80, 0.08)
	if p == 0:
		custom_minimum_size = Vector2(288, 98)
		name_label.add_theme_color_override("font_color", Color(0.98, 0.96, 0.90, 1))
		info_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.84, 0.95))
	else:
		custom_minimum_size = Vector2(224, 92)
		name_label.add_theme_color_override("font_color", Color(0.96, 0.97, 0.99, 1))
		info_label.add_theme_color_override("font_color", Color(0.83, 0.87, 0.93, 0.92))
	clear_mini_cards()

func update_from_snapshot(cash: int, hand_size: int, is_active: bool) -> void:
	info_label.text = "¥%d   藏%d" % [cash, hand_size]
	status_label.text = "行动中" if is_active else ""
	status_label.visible = is_active
	_animate_active_state(is_active)

func clear_mini_cards() -> void:
	if mini_cards == null:
		return
	for c in mini_cards.get_children():
		c.queue_free()

func add_mini_card(tex: Texture2D) -> void:
	if mini_cards == null or tex == null:
		return
	var mini_tex: Texture2D = _to_mini_tex(tex)
	var tr := TextureRect.new()
	tr.texture = mini_tex
	tr.custom_minimum_size = Vector2(MINI_W, MINI_H)
	# MiniCards 不是 Container，子节点不会自动应用 custom_minimum_size
	tr.size = tr.custom_minimum_size
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_cards.add_child(tr)
	_layout_mini_cards()

func _to_mini_tex(tex: Texture2D) -> Texture2D:
	var key: int = tex.get_instance_id()
	if _mini_tex_cache.has(key):
		return _mini_tex_cache[key]
	var img: Image = tex.get_image()
	if img == null:
		return tex
	img.resize(MINI_W, MINI_H, Image.INTERPOLATE_NEAREST)
	var out: Texture2D = ImageTexture.create_from_image(img)
	_mini_tex_cache[key] = out
	return out

func _layout_mini_cards() -> void:
	if mini_cards == null:
		return
	var n: int = mini_cards.get_child_count()
	if n <= 0:
		return

	var w: float = max(1.0, mini_cards.size.x)
	var h: float = max(1.0, mini_cards.size.y)
	var step_x: float = 12.0 # 水平轻微叠放

	# 以第一张的尺寸作为基准
	var first := mini_cards.get_child(0) as Control
	var cw: float = float(MINI_W)
	var ch: float = float(MINI_H)
	if first != null:
		cw = max(1.0, first.custom_minimum_size.x)
		ch = max(1.0, first.custom_minimum_size.y)

	var total_w: float = cw + float(max(0, n - 1)) * step_x
	var start_x: float = w - total_w # 允许为负，超出部分会被 clip 裁剪（保留右侧最新牌）
	var y: float = floor((h - ch) * 0.5)

	for i in range(n):
		var c := mini_cards.get_child(i) as Control
		if c == null:
			continue
		# 同上：确保有实际 size，避免只显示一小块
		if c.size == Vector2.ZERO and c.custom_minimum_size != Vector2.ZERO:
			c.size = c.custom_minimum_size
		c.position = Vector2(start_x + float(i) * step_x, y)

func _ready() -> void:
	if mini_cards != null:
		mini_cards.resized.connect(_layout_mini_cards)
		_layout_mini_cards()
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	modulate = PANEL_IDLE

func _animate_active_state(is_active: bool) -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_QUAD)
	_active_tween.set_ease(Tween.EASE_OUT)
	var target_modulate: Color = PANEL_ACTIVE if is_active else PANEL_IDLE
	var target_accent: Color = ACCENT_ACTIVE if is_active else ACCENT_IDLE
	_active_tween.tween_property(self, "modulate", target_modulate, 0.18)
	if accent != null:
		_active_tween.parallel().tween_property(accent, "color", target_accent, 0.18)
	if glow != null:
		var target_glow: Color = GLOW_ACTIVE if is_active else (Color(1.0, 0.95, 0.80, 0.08) if player_id == 0 else GLOW_IDLE)
		_active_tween.parallel().tween_property(glow, "color", target_glow, 0.18)
