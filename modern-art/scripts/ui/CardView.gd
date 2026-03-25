extends Control

@export var card_size: Vector2 = Vector2(160, 224)

@onready var bg: ColorRect = ColorRect.new()
@onready var title_label: Label = Label.new()
@onready var subtitle_label: Label = Label.new()

var _tween: Tween

func _ready() -> void:
	custom_minimum_size = card_size
	size = card_size

	bg.color = Color(0.18, 0.18, 0.22, 1)
	bg.anchors_preset = Control.PRESET_FULL_RECT
	add_child(bg)

	title_label.text = "作品"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.anchors_preset = Control.PRESET_FULL_RECT
	title_label.offset_left = 8
	title_label.offset_right = -8
	title_label.offset_top = 12
	title_label.offset_bottom = -44
	add_child(title_label)

	subtitle_label.text = "拍卖"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.anchors_preset = Control.PRESET_FULL_RECT
	subtitle_label.offset_left = 8
	subtitle_label.offset_right = -8
	subtitle_label.offset_top = card_size.y - 44
	subtitle_label.offset_bottom = -8
	add_child(subtitle_label)

func set_card_text(title: String, subtitle: String) -> void:
	title_label.text = title
	subtitle_label.text = subtitle

func set_card_color(c: Color) -> void:
	bg.color = c

func animate_to(global_pos: Vector2, duration: float = 0.25) -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "global_position", global_pos, duration)

func animate_scale_to(target_scale: Vector2, duration: float = 0.18) -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", target_scale, duration)

func pop() -> void:
	_kill_tween()
	scale = Vector2.ONE
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_BACK)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * 1.05, 0.10)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.12)

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

