extends PanelContainer

@onready var name_label: Label = $Margin/VBox/NameRow/NameLabel
@onready var status_label: Label = $Margin/VBox/NameRow/StatusLabel
@onready var info_label: Label = $Margin/VBox/InfoRow/InfoLabel
@onready var mini_cards: Control = $MiniCards

var player_id: int = -1
var player_name: String = ""
var _mini_tex_cache: Dictionary = {} # tex_instance_id -> Texture2D

const MINI_W: int = 58
const MINI_H: int = 72

func set_player(p: int, name: String) -> void:
	player_id = p
	player_name = name
	name_label.text = name
	clear_mini_cards()

func update_from_snapshot(cash: int, hand_size: int, is_active: bool) -> void:
	info_label.text = "现¥%d  牌%d" % [cash, hand_size]
	status_label.text = "行动中" if is_active else ""
	status_label.visible = is_active

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
	var step_x: float = 18.0 # 水平轻微叠放

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

