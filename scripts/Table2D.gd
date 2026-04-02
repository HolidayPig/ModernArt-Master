extends Node2D

const GameState := preload("res://scripts/core/GameState.gd")
const CardDefs := preload("res://scripts/core/CardDefs.gd")
const AssetResolver := preload("res://scripts/assets/AssetResolver.gd")
const CardActorScene: PackedScene = preload("res://scenes/CardActor.tscn")
const ModernArtGenerator: Script = preload("res://scripts/art/ModernArtGenerator.gd")
const FloatingText: Script = preload("res://scripts/ui/FloatingText.gd")
const PlayerPanelScene: PackedScene = preload("res://scenes/ui/PlayerPanel.tscn")
const HAND_CARD_SIZE: Vector2 = Vector2(116.0, 206.0)

@onready var bg: Sprite2D = $Background
@onready var cards_layer: Node2D = $CardsLayer
@onready var deck_anchor: Marker2D = $BoardAnchors/DeckAnchor
@onready var auction_anchor: Marker2D = $BoardAnchors/AuctionAnchor
@onready var player_collection_anchor: Marker2D = $BoardAnchors/PlayerCollectionAnchor
@onready var ai_collection_anchor: Marker2D = $BoardAnchors/AiCollectionAnchor # fallback
@onready var ai1_collection_anchor: Marker2D = $BoardAnchors/Ai1CollectionAnchor
@onready var ai2_collection_anchor: Marker2D = $BoardAnchors/Ai2CollectionAnchor
@onready var ai3_collection_anchor: Marker2D = $BoardAnchors/Ai3CollectionAnchor
@onready var ai4_collection_anchor: Marker2D = $BoardAnchors/Ai4CollectionAnchor

@onready var hud_root: Control = $Hud/HudRoot
@onready var round_label: Label = $Hud/HudRoot/LayoutMargin/LayoutVBox/TopBar/TopHBox/RoundLabel
@onready var turn_label: Label = $Hud/HudRoot/LayoutMargin/LayoutVBox/TopBar/TopHBox/TurnLabel
@onready var money_label: Label = $Hud/HudRoot/LayoutMargin/LayoutVBox/TopBar/TopHBox/MoneyLabel
@onready var auction_info: RichTextLabel = $Hud/HudRoot/LayoutMargin/LayoutVBox/TopSummaryRow/AuctionPanel/AuctionVBox/AuctionInfo
@onready var btn1: Button = $Hud/HudRoot/HandActionDock/DockMargin/DockVBox/AuctionButtons/Btn1
@onready var btn2: Button = $Hud/HudRoot/HandActionDock/DockMargin/DockVBox/AuctionButtons/Btn2
@onready var btn3: Button = $Hud/HudRoot/HandActionDock/DockMargin/DockVBox/AuctionButtons/Btn3
@onready var toast: Label = $Hud/HudRoot/Toast

@onready var top_bar: Control = $Hud/HudRoot/LayoutMargin/LayoutVBox/TopBar
@onready var brand_eyebrow: Label = $Hud/HudRoot/LayoutMargin/LayoutVBox/TopBar/TopHBox/BrandVBox/BrandEyebrow
@onready var brand_title: Label = $Hud/HudRoot/LayoutMargin/LayoutVBox/TopBar/TopHBox/BrandVBox/BrandTitle
@onready var left_column: Control = $Hud/HudRoot/LayoutMargin/LayoutVBox/MainHBox/LeftColumn
@onready var right_column: Control = $Hud/HudRoot/LayoutMargin/LayoutVBox/MainHBox/RightColumn
@onready var auction_panel: Control = $Hud/HudRoot/LayoutMargin/LayoutVBox/TopSummaryRow/AuctionPanel
@onready var market_panel: Control = $Hud/HudRoot/LayoutMargin/LayoutVBox/TopSummaryRow/MarketPanel
@onready var market_info: RichTextLabel = $Hud/HudRoot/LayoutMargin/LayoutVBox/TopSummaryRow/MarketPanel/MarketVBox/MarketInfo
@onready var auction_info_box: VBoxContainer = $Hud/HudRoot/LayoutMargin/LayoutVBox/TopSummaryRow/AuctionPanel/AuctionVBox
@onready var hand_action_dock: Control = $Hud/HudRoot/HandActionDock
@onready var hand_zone_frame: Control = $Hud/HudRoot/HandZoneFrame
@onready var layout_vbox: VBoxContainer = $Hud/HudRoot/LayoutMargin/LayoutVBox
@onready var top_summary_row: HBoxContainer = $Hud/HudRoot/LayoutMargin/LayoutVBox/TopSummaryRow
@onready var main_hbox: HBoxContainer = $Hud/HudRoot/LayoutMargin/LayoutVBox/MainHBox
@onready var center_column: Control = $Hud/HudRoot/LayoutMargin/LayoutVBox/MainHBox/CenterColumn
@onready var bottom_bar: Control = $Hud/HudRoot/LayoutMargin/LayoutVBox/BottomBar
@onready var table_stage: Control = $Hud/HudRoot/LayoutMargin/LayoutVBox/MainHBox/CenterColumn/TableStage
@onready var auction_stage_frame: Control = $Hud/HudRoot/LayoutMargin/LayoutVBox/MainHBox/CenterColumn/TableStage/AuctionStageFrame
@onready var stage_eyebrow: Label = $Hud/HudRoot/LayoutMargin/LayoutVBox/MainHBox/CenterColumn/TableStage/AuctionStageFrame/AuctionStageMargin/AuctionStageVBox/StageEyebrow
@onready var stage_hint: Label = $Hud/HudRoot/LayoutMargin/LayoutVBox/MainHBox/CenterColumn/TableStage/AuctionStageFrame/AuctionStageMargin/AuctionStageVBox/StageHint

@onready var left_players: VBoxContainer = $Hud/HudRoot/LayoutMargin/LayoutVBox/MainHBox/LeftColumn/LeftPlayers
@onready var right_players: VBoxContainer = $Hud/HudRoot/LayoutMargin/LayoutVBox/MainHBox/RightColumn/RightPlayers
@onready var bottom_player_slot: VBoxContainer = $Hud/HudRoot/LayoutMargin/LayoutVBox/BottomBar/BottomHBox/BottomPlayerSlot

var gs: Node
var _dialog: AcceptDialog
var _spin: SpinBox

var _last_snapshot: Dictionary = {}
var _hand_by_id: Dictionary = {} # card_id(int) -> CardActor(Node)
var _hand_order: Array = [] # Array[Dictionary]
var _in_flight: Dictionary = {} # card_id(int) -> actor

var _frame_tex: Texture2D
var _back_tex: Texture2D
var _art: RefCounted

var _player_panels: Array = [] # index=player_id -> PlayerPanel(Control)
var _hovered_card_id: int = -1
var _owned_by_player: Array = [] # Array[Array[int]]（仅表现层：用于计数排布）
var _toast_tween: Tween

const ARTIST_COLORS: Array[Color] = [
	Color8(202, 92, 67),
	Color8(214, 162, 73),
	Color8(94, 154, 121),
	Color8(79, 132, 188),
	Color8(171, 107, 158),
]

func _ready() -> void:
	_apply_chinese_font_if_available()
	_init_dialog()
	_init_card_textures()
	_art = ModernArtGenerator.new()
	_init_game()
	_style_static_ui()
	get_viewport().size_changed.connect(_refresh_layout_metrics)
	_play_intro()
	_refresh_layout_metrics()

func _apply_chinese_font_if_available() -> void:
	var f := AssetResolver.load_font_or_null()
	var ui_theme := Theme.new()
	if f != null:
		ui_theme.set_default_font(f)
	ui_theme.set_default_font_size(19)

	ui_theme.set_color("font_color", "Label", Color(0.95, 0.95, 0.92, 1))
	ui_theme.set_color("font_color", "RichTextLabel", Color(0.95, 0.95, 0.92, 1))
	ui_theme.set_color("default_color", "RichTextLabel", Color(0.95, 0.95, 0.92, 1))
	ui_theme.set_color("font_color", "Button", Color(0.97, 0.97, 0.95, 1))
	ui_theme.set_color("font_color_disabled", "Button", Color(0.48, 0.50, 0.53, 1))
	ui_theme.set_color("font_outline_color", "Label", Color(0.04, 0.05, 0.07, 0.45))
	ui_theme.set_color("font_outline_color", "Button", Color(0.04, 0.05, 0.07, 0.35))

	ui_theme.set_stylebox("panel", "PanelContainer", _make_panel_style(Color(0.06, 0.08, 0.11, 0.82), Color(0.62, 0.51, 0.27, 0.36), 18, 18, 18, 18, 18))
	ui_theme.set_stylebox("panel", "Panel", _make_panel_style(Color(0.06, 0.08, 0.11, 0.82), Color(0.62, 0.51, 0.27, 0.36), 18, 18, 18, 18, 18))

	var btn_normal := _make_panel_style(Color(0.12, 0.14, 0.18, 0.98), Color(0.73, 0.62, 0.35, 0.55), 16, 16, 16, 16, 16)
	var btn_hover := _make_panel_style(Color(0.18, 0.21, 0.25, 1), Color(0.87, 0.76, 0.45, 0.9), 16, 16, 16, 16, 16)
	var btn_pressed := _make_panel_style(Color(0.09, 0.11, 0.14, 1), Color(0.68, 0.56, 0.28, 0.95), 16, 16, 16, 16, 16)
	var btn_disabled := _make_panel_style(Color(0.10, 0.11, 0.13, 0.72), Color(0.20, 0.21, 0.24, 0.55), 16, 16, 16, 16, 16)
	ui_theme.set_stylebox("normal", "Button", btn_normal)
	ui_theme.set_stylebox("hover", "Button", btn_hover)
	ui_theme.set_stylebox("pressed", "Button", btn_pressed)
	ui_theme.set_stylebox("disabled", "Button", btn_disabled)
	ui_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	ui_theme.set_constant("outline_size", "Label", 1)
	ui_theme.set_constant("outline_size", "Button", 1)
	ui_theme.set_constant("outline_size", "RichTextLabel", 0)
	ui_theme.set_constant("h_separation", "HBoxContainer", 12)
	ui_theme.set_constant("v_separation", "VBoxContainer", 12)

	hud_root.theme = ui_theme

func _make_panel_style(bg: Color, border: Color, radius: int, margin_l: int = 12, margin_t: int = 10, margin_r: int = 12, margin_b: int = 10) -> StyleBoxFlat:
	var panel := StyleBoxFlat.new()
	panel.bg_color = bg
	panel.border_color = border
	panel.border_width_left = 1
	panel.border_width_top = 1
	panel.border_width_right = 1
	panel.border_width_bottom = 1
	panel.corner_radius_top_left = radius
	panel.corner_radius_top_right = radius
	panel.corner_radius_bottom_left = radius
	panel.corner_radius_bottom_right = radius
	panel.shadow_color = Color(0, 0, 0, 0.20)
	panel.shadow_size = 10
	panel.content_margin_left = margin_l
	panel.content_margin_top = margin_t
	panel.content_margin_right = margin_r
	panel.content_margin_bottom = margin_b
	return panel

func _style_static_ui() -> void:
	brand_eyebrow.add_theme_color_override("font_color", Color(0.80, 0.70, 0.45, 0.95))
	brand_eyebrow.add_theme_font_size_override("font_size", 12)
	brand_title.add_theme_font_size_override("font_size", 22)
	brand_title.add_theme_color_override("font_color", Color(0.98, 0.97, 0.92, 1))
	round_label.add_theme_font_size_override("font_size", 15)
	turn_label.add_theme_font_size_override("font_size", 15)
	money_label.add_theme_font_size_override("font_size", 14)
	toast.add_theme_font_size_override("font_size", 16)
	toast.add_theme_color_override("font_color", Color(0.98, 0.97, 0.94, 1))
	auction_info.add_theme_font_size_override("normal_font_size", 15)
	market_info.add_theme_font_size_override("normal_font_size", 13)
	auction_info.scroll_active = true
	auction_info.scroll_following = false
	auction_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	market_info.scroll_active = true
	market_info.scroll_following = false
	market_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	top_bar.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.07, 0.10, 0.88), Color(0.80, 0.68, 0.40, 0.38), 24, 18, 12, 18, 12))
	auction_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.10, 0.14, 0.90), Color(0.86, 0.73, 0.41, 0.42), 28, 18, 16, 18, 16))
	market_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.09, 0.12, 0.88), Color(0.35, 0.58, 0.80, 0.36), 22, 16, 14, 16, 14))
	hand_action_dock.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.06, 0.08, 0.96), Color(0.82, 0.70, 0.40, 0.72), 24, 18, 16, 18, 16))
	hand_zone_frame.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.05, 0.07, 0.30), Color(0.82, 0.70, 0.40, 0.34), 28, 14, 12, 14, 12))
	auction_stage_frame.add_theme_stylebox_override("panel", _make_panel_style(Color(0.09, 0.08, 0.07, 0.30), Color(0.92, 0.77, 0.43, 0.22), 30, 22, 18, 22, 18))
	left_column.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.07, 0.10, 0.22), Color(0.82, 0.70, 0.40, 0.24), 24, 14, 14, 14, 14))
	right_column.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.07, 0.10, 0.22), Color(0.82, 0.70, 0.40, 0.24), 24, 14, 14, 14, 14))
	bottom_bar.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.07, 0.10, 0.18), Color(0.82, 0.70, 0.40, 0.22), 24, 14, 14, 14, 14))
	bottom_player_slot.add_theme_constant_override("separation", 0)
	stage_eyebrow.add_theme_font_size_override("font_size", 11)
	stage_eyebrow.add_theme_color_override("font_color", Color(0.89, 0.75, 0.44, 0.82))
	stage_hint.add_theme_font_size_override("font_size", 14)
	stage_hint.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84, 0.72))

	for label in [round_label, turn_label]:
		label.add_theme_color_override("font_color", Color(0.90, 0.92, 0.95, 0.94))

func _play_intro() -> void:
	for node in [top_bar, left_column, right_column, auction_panel, market_panel, hand_action_dock]:
		if node == null:
			continue
		(node as CanvasItem).modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(top_bar, "modulate:a", 1.0, 0.28)
	tw.tween_property(left_column, "modulate:a", 1.0, 0.36)
	tw.tween_property(right_column, "modulate:a", 1.0, 0.36)
	tw.tween_property(auction_panel, "modulate:a", 1.0, 0.44)
	tw.tween_property(market_panel, "modulate:a", 1.0, 0.52)
	tw.tween_property(hand_action_dock, "modulate:a", 1.0, 0.60)

func _refresh_layout_metrics() -> void:
	if not is_node_ready():
		return
	var vp: Vector2 = get_viewport_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return
	bg.texture = _make_table_texture(Vector2i(int(vp.x), int(vp.y)))
	bg.position = Vector2.ZERO
	bg.scale = Vector2.ONE

	var side_w: float = clamp(vp.x * 0.19, 168.0, 236.0)
	left_column.custom_minimum_size.x = side_w
	right_column.custom_minimum_size.x = side_w
	var center_target: float = clamp(vp.x - side_w * 2.0 - 96.0, 320.0, 720.0)
	center_column.custom_minimum_size.x = center_target

	var bar_h: float = clamp(vp.y * 0.07, 56.0, 64.0)
	top_bar.custom_minimum_size.y = bar_h

	var info_h: float = clamp(vp.y * 0.18, 128.0, 188.0)
	var info_w: float = max(300.0, (vp.x - 64.0) * 0.5)
	market_panel.custom_minimum_size = Vector2(info_w, info_h)
	auction_panel.custom_minimum_size = Vector2(info_w, info_h)
	market_info.custom_minimum_size = Vector2(0.0, max(94.0, info_h - 34.0))
	auction_info_box.custom_minimum_size = Vector2(0.0, max(94.0, info_h - 34.0))
	main_hbox.add_theme_constant_override("separation", 16)
	top_summary_row.add_theme_constant_override("separation", 14)

	var bottom_h: float = clamp(vp.y * 0.18, 128.0, 172.0)
	bottom_bar.custom_minimum_size.y = bottom_h
	var dock_w: float = clamp(vp.x * 0.24, 320.0, 420.0)
	var dock_h: float = clamp(vp.y * 0.28, 300.0, 380.0)
	hand_action_dock.custom_minimum_size = Vector2(dock_w, dock_h)
	hand_action_dock.offset_left = -dock_w - 24.0
	hand_action_dock.offset_right = -24.0
	hand_action_dock.offset_top = -dock_h - 24.0
	hand_action_dock.offset_bottom = -24.0
	bottom_player_slot.custom_minimum_size.x = clamp(vp.x * 0.30, 288.0, 360.0)
	hand_action_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	var hand_zone_w: float = clamp(vp.x * 0.42, 460.0, 760.0)
	var hand_zone_h: float = clamp(vp.y * 0.20, 170.0, 230.0)
	hand_zone_frame.offset_left = -hand_zone_w * 0.5
	hand_zone_frame.offset_right = hand_zone_w * 0.5 - dock_w * 0.34
	hand_zone_frame.offset_top = -hand_zone_h - 20.0
	hand_zone_frame.offset_bottom = -20.0
	var stage_w: float = clamp(center_target - 56.0, 260.0, 420.0)
	var stage_h: float = clamp((vp.y - bar_h - info_h - bottom_h - 170.0) * 0.56, 150.0, 220.0)
	auction_stage_frame.offset_left = -stage_w * 0.5
	auction_stage_frame.offset_right = stage_w * 0.5
	auction_stage_frame.offset_top = -stage_h * 0.5
	auction_stage_frame.offset_bottom = stage_h * 0.5

	var board_w: float = max(760.0, min(1220.0, vp.x * 0.82))
	var board_h: float = max(640.0, min(1100.0, vp.y * 0.88))
	var left_edge: float = (vp.x - board_w) * 0.5
	var right_edge: float = (vp.x + board_w) * 0.5
	var top_edge: float = top_bar.get_global_rect().end.y + info_h + 34.0
	var bottom_edge: float = bottom_bar.get_global_rect().position.y - 28.0
	if bottom_edge <= top_edge:
		bottom_edge = vp.y - bottom_h - 34.0
	deck_anchor.position = Vector2(vp.x * 0.5, min(top_edge + board_h * 0.16, top_edge + 126.0))
	auction_anchor.position = Vector2(vp.x * 0.5, lerp(top_edge + 150.0, bottom_edge - 140.0, 0.42))
	player_collection_anchor.position = Vector2(vp.x * 0.5, max(top_edge + 220.0, bottom_edge - 42.0))
	ai_collection_anchor.position = Vector2(min(vp.x - left_edge, right_edge + 20.0), top_edge + (bottom_edge - top_edge) * 0.46)
	ai1_collection_anchor.position = Vector2(max(40.0, left_edge + 30.0), top_edge + (bottom_edge - top_edge) * 0.35)
	ai2_collection_anchor.position = Vector2(max(40.0, left_edge + 30.0), top_edge + (bottom_edge - top_edge) * 0.53)
	ai3_collection_anchor.position = Vector2(min(vp.x - 30.0, right_edge - 30.0), top_edge + (bottom_edge - top_edge) * 0.46)
	ai4_collection_anchor.position = Vector2(min(vp.x - 30.0, right_edge - 30.0), top_edge + (bottom_edge - top_edge) * 0.64)

func _init_dialog() -> void:
	_dialog = AcceptDialog.new()
	_dialog.title = "输入数值"
	add_child(_dialog)

	var vb := VBoxContainer.new()
	_dialog.add_child(vb)

	_spin = SpinBox.new()
	_spin.min_value = 0
	_spin.max_value = 200000
	_spin.step = 1000
	_spin.value = 0
	vb.add_child(_spin)

func _init_game() -> void:
	if _art == null:
		_art = ModernArtGenerator.new()
	gs = GameState.new()
	add_child(gs)

	gs.state_changed.connect(_on_state_changed)
	gs.toast.connect(_show_toast)
	gs.auction_input_requested.connect(_on_auction_input_requested)
	gs.round_scored.connect(_on_round_scored)
	gs.game_ended.connect(_on_game_ended)
	gs.card_played.connect(_on_card_played)
	gs.auction_resolved.connect(_on_auction_resolved)
	gs.money_changed.connect(_on_money_changed)

	_init_player_panels()
	_reset_owned_visuals()
	gs.new_game()

func _init_background() -> void:
	var vp: Vector2 = get_viewport_rect().size
	vp.x = max(1.0, vp.x)
	vp.y = max(1.0, vp.y)
	bg.texture = _make_table_texture(Vector2i(int(vp.x), int(vp.y)))
	bg.position = Vector2.ZERO

func _init_card_textures() -> void:
	# 先用下载素材的卡牌底图做框（后续会换成真正的卡框+卡面）
	_frame_tex = AssetResolver.load_texture_or_placeholder(
		"res://assets/downloaded/cards/color_empty.png",
		Vector2i(144, 256),
		Color(0.16, 0.16, 0.20, 1)
	)
	_back_tex = AssetResolver.load_texture_or_placeholder(
		"res://assets/downloaded/cards/color_back.png",
		Vector2i(144, 256),
		Color(0.10, 0.10, 0.12, 1)
	)

func _make_table_texture(size: Vector2i) -> Texture2D:
	# 更有展厅感的背景：纵向渐变 + 暖色聚光 + 细颗粒
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in range(size.y):
		var t: float = float(y) / float(max(1, size.y - 1))
		var col := Color(0.05, 0.07, 0.10, 1).lerp(Color(0.12, 0.10, 0.08, 1), t * 0.75)
		for x in range(size.x):
			img.set_pixel(x, y, col)

	_draw_soft_circle(img, Vector2(size.x * 0.52, size.y * 0.32), 280.0, Color(0.88, 0.72, 0.42, 0.12))
	_draw_soft_circle(img, Vector2(size.x * 0.22, size.y * 0.58), 220.0, Color(0.38, 0.58, 0.78, 0.10))
	_draw_soft_circle(img, Vector2(size.x * 0.82, size.y * 0.62), 240.0, Color(0.28, 0.48, 0.62, 0.08))

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for y in range(0, size.y, 2):
		for x in range(0, size.x, 2):
			var base: Color = img.get_pixel(x, y)
			var n := rng.randi_range(-5, 5) / 255.0
			var c := Color(base.r + n, base.g + n, base.b + n, 1)
			img.set_pixel(x, y, c)
			if x + 1 < size.x:
				img.set_pixel(x + 1, y, c)
			if y + 1 < size.y:
				img.set_pixel(x, y + 1, c)
				if x + 1 < size.x:
					img.set_pixel(x + 1, y + 1, c)

	for i in range(5):
		var line_y: int = 110 + i * 108
		_draw_rect(img, Rect2i(72, line_y, size.x - 144, 1), Color(1, 1, 1, 0.035))

	return ImageTexture.create_from_image(img)

func _draw_soft_circle(img: Image, center: Vector2, radius: float, col: Color) -> void:
	var min_x: int = max(0, int(center.x - radius))
	var max_x: int = min(img.get_width() - 1, int(center.x + radius))
	var min_y: int = max(0, int(center.y - radius))
	var max_y: int = min(img.get_height() - 1, int(center.y + radius))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dist: float = center.distance_to(Vector2(x, y))
			if dist > radius:
				continue
			var t: float = 1.0 - (dist / radius)
			var src: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, src.lerp(Color(col.r, col.g, col.b, 1.0), t * col.a))

func _draw_rect(img: Image, r: Rect2i, col: Color) -> void:
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, col)

func _draw_rect_outline(img: Image, r: Rect2i, col: Color) -> void:
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.position.x + r.size.x - 1
	var y1 := r.position.y + r.size.y - 1
	for x in range(x0, x1 + 1):
		_safe_set(img, x, y0, col)
		_safe_set(img, x, y1, col)
	for y in range(y0, y1 + 1):
		_safe_set(img, x0, y, col)
		_safe_set(img, x1, y, col)

func _safe_set(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)

func _on_state_changed(s: Dictionary) -> void:
	_last_snapshot = s
	var r: int = int(s["round_index"]) + 1
	round_label.text = "第%d轮 / 共4轮" % r

	var ap: int = int(s["active_player"])
	turn_label.text = "当前拍卖师：%s" % ("你" if ap == 0 else ("电脑%d" % ap))

	var cash: Array = s["cash"]
	var deck_remaining: int = int(s.get("deck_remaining", 0))
	var my_cash: int = int(cash[0]) if cash.size() > 0 else 0
	money_label.text = "资产 ¥%d   牌库 %d" % [my_cash, deck_remaining]

	auction_info.text = "[b]下一件藏品待上架[/b]\n点击下方手牌，把作品送上拍卖台。"
	_set_buttons_disabled()

	_update_player_panels(s)
	_update_market_board(s)
	_render_hand(s)

func _set_buttons_disabled() -> void:
	for b in [btn1, btn2, btn3]:
		b.disabled = true
		b.text = "—"

func _render_hand(s: Dictionary) -> void:
	var hand: Array = s.get("hand", [])
	_hand_order = hand

	var want_ids: Dictionary = {}
	for c in hand:
		var id: int = int(c.get("id", -1))
		want_ids[id] = true
		var existing: Variant = _hand_by_id.get(id, null)
		if existing == null or not is_instance_valid(existing):
			var actor := CardActorScene.instantiate()
			cards_layer.add_child(actor)
			_hand_by_id[id] = actor
			actor.clicked.connect(_on_card_clicked)

			# 暂时用背面作卡面占位
			actor.set_card(c)
			var face_tex: Texture2D = _art.get_face_texture(c)
			actor.set_textures(_frame_tex, face_tex)
			actor.set_font_size(14)
			actor.set_subtitle(CardDefs.auction_display_name(int(c.get("auction", 0))))

	# 移除不需要的
	var to_remove: Array[int] = []
	for k in _hand_by_id.keys():
		var id_k: int = int(k)
		if not want_ids.has(id_k):
			to_remove.append(id_k)
	for id_r in to_remove:
		# 正在飞行动画中的牌不要立刻销毁
		if _in_flight.has(id_r):
			continue
		var a: Variant = _hand_by_id.get(id_r, null)
		_hand_by_id.erase(id_r)
		if a != null and is_instance_valid(a):
			(a as Node).queue_free()

	_layout_hand_fan()

func _layout_hand_fan() -> void:
	var n: int = _hand_order.size()
	if n <= 0:
		return

	var vp: Vector2 = get_viewport_rect().size
	var hand_rect: Rect2 = hand_zone_frame.get_global_rect()
	var base_y: float = hand_rect.position.y + hand_rect.size.y - (HAND_CARD_SIZE.y * 0.47) - 14.0
	var center_x: float = hand_rect.position.x + hand_rect.size.x * 0.5
	var span: float = min(0.34, 0.044 * float(max(n - 1, 1)))
	var left_limit: float = hand_rect.position.x + 84.0
	var right_limit: float = hand_rect.end.x - 84.0
	var available_w: float = max(280.0, right_limit - left_limit)
	var width: float = min(available_w * 0.76, 74.0 * float(max(n - 1, 1)))
	center_x = clamp(center_x, left_limit + available_w * 0.5, right_limit - available_w * 0.5)

	for i in range(n):
		var c: Dictionary = _hand_order[i]
		var id: int = int(c.get("id", -1))
		if not _hand_by_id.has(id):
			continue
		var actor = _hand_by_id[id]
		var t: float = 0.0
		if n > 1:
			t = (float(i) / float(n - 1)) - 0.5

		var rot: float = t * span
		var x: float = center_x + t * width
		var y: float = base_y + abs(t) * 6.0
		var p := Vector2(x, y)

		actor.set_base_transform(p, rot)
		actor.set_base_z(40 + i)

func _on_card_clicked(card_id: int) -> void:
	# 仅在轮到玩家且等待出牌时响应
	var phase: int = int(_last_snapshot.get("phase", 0))
	var ap: int = int(_last_snapshot.get("active_player", 0))
	if ap != 0 or phase != GameState.Phase.WAIT_PLAY_CARD:
		_show_toast("现在不能出牌（阶段=%d，回合=%d）" % [phase, ap])
		return

	# 找到当前手牌中对应索引
	var idx: int = -1
	for i in range(_hand_order.size()):
		var c: Dictionary = _hand_order[i]
		if int(c.get("id", -1)) == card_id:
			idx = i
			break
	if idx < 0:
		return

	# 播放出牌基础动效：飞到拍卖锚点
	if _hand_by_id.has(card_id):
		_set_hover_card(-1)
		var actor = _hand_by_id[card_id]
		_hand_by_id.erase(card_id) # 防止后续渲染复用已释放实例
		_in_flight[card_id] = actor
		actor.set_hovered(false)
		actor.play_to(_auction_slot_pos(0, 1), 0.0, 0.22, 54.0)

	gs.play_card(0, idx)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mp: Vector2 = get_viewport().get_mouse_position()
		var id: int = _pick_top_hand_card_id(mp)
		if id != _hovered_card_id:
			_set_hover_card(id)

func _pick_top_hand_card_id(mouse_pos: Vector2) -> int:
	# 从最上层往下找（手牌扇形 z_index 与顺序一致）
	for i in range(_hand_order.size() - 1, -1, -1):
		var c: Dictionary = _hand_order[i]
		var id: int = int(c.get("id", -1))
		if not _hand_by_id.has(id):
			continue
		var actor: Variant = _hand_by_id[id]
		if actor == null or not is_instance_valid(actor):
			continue
		var n2d := actor as Node2D
		if n2d != null and _point_hits_actor(mouse_pos, n2d):
			return id
	return -1

func _point_hits_actor(global_point: Vector2, actor: Node2D) -> bool:
	var inv: Transform2D = actor.get_global_transform().affine_inverse()
	var lp: Vector2 = inv * global_point
	var sz: Vector2 = HAND_CARD_SIZE
	var v: Variant = actor.get("card_size")
	if v is Vector2:
		sz = v
	return abs(lp.x) <= sz.x * 0.5 and abs(lp.y) <= sz.y * 0.5

func _set_hover_card(id: int) -> void:
	if _hovered_card_id == id:
		return
	if _hovered_card_id != -1 and _hand_by_id.has(_hovered_card_id):
		var prev: Variant = _hand_by_id[_hovered_card_id]
		if prev != null and is_instance_valid(prev):
			prev.set_hovered(false)
	_hovered_card_id = id
	if _hovered_card_id != -1 and _hand_by_id.has(_hovered_card_id):
		var cur: Variant = _hand_by_id[_hovered_card_id]
		if cur != null and is_instance_valid(cur):
			cur.set_hovered(true)

func _get_or_create_actor_for_card(card_id: int, card: Dictionary) -> Node2D:
	# 已在飞行/桌面上的直接复用
	if _in_flight.has(card_id):
		var ex: Variant = _in_flight[card_id]
		return ex as Node2D

	# 若仍在手牌（例如加牌补牌从手牌抽出时），从手牌拿出来复用
	if _hand_by_id.has(card_id):
		var ex2: Variant = _hand_by_id[card_id]
		_hand_by_id.erase(card_id)
		_in_flight[card_id] = ex2
		return ex2 as Node2D

	var actor := CardActorScene.instantiate()
	cards_layer.add_child(actor)
	_in_flight[card_id] = actor

	actor.set_card(card)
	actor.set_textures(_frame_tex, _art.get_face_texture(card))
	actor.set_font_size(14)
	actor.set_subtitle(CardDefs.auction_display_name(int(card.get("auction", 0))))
	actor.set_base_transform(deck_anchor.position, 0.0)
	return actor as Node2D

func _auction_safe_rect() -> Rect2:
	# 使用UI面板的全局矩形推导“桌面安全区”（避免与信息面板/操作条/侧栏冲突）
	var vp: Vector2 = get_viewport_rect().size
	var lrect: Rect2 = left_column.get_global_rect()
	var rrect: Rect2 = right_column.get_global_rect()
	var mrect: Rect2 = market_panel.get_global_rect()
	var arect: Rect2 = auction_panel.get_global_rect()
	var bottom_rect: Rect2 = bottom_bar.get_global_rect()

	var left: float = lrect.end.x + 28.0
	var right: float = rrect.position.x - 28.0
	var stage_rect: Rect2 = auction_stage_frame.get_global_rect()
	var top: float = max(mrect.end.y, arect.end.y) + 34.0
	var dock_rect: Rect2 = hand_action_dock.get_global_rect()
	var hand_rect: Rect2 = hand_zone_frame.get_global_rect()
	var bottom: float = min(hand_rect.position.y - 34.0, dock_rect.position.y - 34.0)
	bottom = max(bottom, top + 156.0)

	if right - left < 300.0 or bottom - top < 160.0:
		var fallback_w: float = clamp(vp.x * 0.46, 320.0, 520.0)
		var safe_top: float = max(max(mrect.end.y, arect.end.y) + 30.0, vp.y * 0.34)
		var safe_bottom: float = min(hand_rect.position.y - 24.0, dock_rect.position.y - 28.0)
		return Rect2(Vector2(vp.x * 0.5 - fallback_w * 0.5, safe_top), Vector2(fallback_w, max(164.0, safe_bottom - safe_top)))
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))

func _auction_slot_pos(slot_index: int, total: int) -> Vector2:
	var safe: Rect2 = _auction_safe_rect()
	var center: Vector2 = safe.position + safe.size * 0.5
	if total <= 1:
		return center + Vector2(0, -12.0)
	var dx: float = 62.0
	if total == 2:
		return center + Vector2((-dx if slot_index == 0 else dx), float(slot_index) * 8.0 - 4.0)
	# 多于2张则按一排摊开
	var start_x: float = center.x - dx * float(total - 1) * 0.5
	return Vector2(start_x + dx * float(slot_index), center.y + abs(slot_index - (total - 1) * 0.5) * 6.0 - 12.0)

func _on_card_played(info: Dictionary) -> void:
	var cards: Array = info.get("cards", [])
	if cards.is_empty():
		return
	_pulse_panel(auction_panel, 1.03)
	var total: int = cards.size()
	for i in range(total):
		var c: Dictionary = cards[i]
		var id0: int = int(c.get("id", -1))
		var actor: Node2D = _get_or_create_actor_for_card(id0, c)
		actor.set_hovered(false)
		var center_bias: float = float(i) - (float(total - 1) * 0.5)
		actor.play_to(_auction_slot_pos(i, total), center_bias * 0.035, 0.24, 90.0 + float(i), 0.90)

func _on_auction_resolved(info: Dictionary) -> void:
	var winner: int = int(info.get("winner", -1))
	var cards: Array = info.get("cards", [])
	if winner < 0:
		return
	_ensure_owned_arrays()

	for c in cards:
		var idc: int = int(c.get("id", -1))
		var actor = null
		if _in_flight.has(idc):
			actor = _in_flight[idc]
		elif _hand_by_id.has(idc):
			actor = _hand_by_id[idc]

		if actor == null:
			continue

		# HUD：把缩略图放进赢家信息框（显示在上层）
		var idx: int = _owned_by_player[winner].size()
		_owned_by_player[winner].append(idc)
		var panel: Variant = _player_panels[winner]
		if panel != null and is_instance_valid(panel):
			panel.add_mini_card(_art.get_face_texture(c))

		# 世界层：牌飞到赢家附近后淡出（不再长期堆在桌面中间）
		var target: Vector2 = _collection_target_for_player(winner) + Vector2(float(idx % 4) * 16.0, float(idx / 4) * 12.0)
		var rot: float = 0.06 if winner in [0, 3, 4] else -0.06
		if actor is Area2D:
			(actor as Area2D).input_pickable = false
		actor.set_hovered(false)
		actor.play_to(target, rot, 0.22, 18.0, 0.70)
		var tw := create_tween()
		tw.tween_interval(0.24)
		tw.tween_property(actor, "modulate:a", 0.0, 0.18)
		tw.tween_callback(func():
			if actor != null and is_instance_valid(actor):
				(actor as Node).queue_free()
		)

		if _in_flight.has(idc):
			_in_flight.erase(idc)

func _collection_target_for_player(p: int) -> Vector2:
	match p:
		0:
			return player_collection_anchor.position
		1:
			return ai1_collection_anchor.position
		2:
			return ai2_collection_anchor.position
		3:
			return ai3_collection_anchor.position
		4:
			return ai4_collection_anchor.position
		_:
			return ai_collection_anchor.position

func _ensure_owned_arrays() -> void:
	if _owned_by_player.size() == 5:
		return
	_owned_by_player.clear()
	for _i in range(5):
		_owned_by_player.append([])

func _reset_owned_visuals() -> void:
	_ensure_owned_arrays()
	for p in range(_owned_by_player.size()):
		_owned_by_player[p].clear()
		var panel: Variant = _player_panels[p]
		if panel != null and is_instance_valid(panel):
			panel.clear_mini_cards()

func _clear_owned_visuals() -> void:
	if _owned_by_player.size() == 5:
		for p in range(_owned_by_player.size()):
			_owned_by_player[p].clear()
			var panel: Variant = _player_panels[p]
			if panel != null and is_instance_valid(panel):
				panel.clear_mini_cards()

	# 兜底：清理仍在“桌面/飞行”但未被归档的牌
	for k2 in _in_flight.keys():
		var a2: Variant = _in_flight[k2]
		if a2 != null and is_instance_valid(a2):
			(a2 as Node).queue_free()
	_in_flight.clear()

func _on_money_changed(info: Dictionary) -> void:
	var p: int = int(info.get("player", -1))
	var delta: int = int(info.get("delta", 0))
	if delta == 0:
		return
	var pos: Vector2 = _floating_text_pos_for_player(p)
	var col := Color(0.35, 0.95, 0.65, 1) if delta > 0 else Color(0.95, 0.35, 0.45, 1)
	var msg := ("%+d" % delta)
	var ft: Label = FloatingText.new()
	hud_root.add_child(ft)
	ft.start(msg, pos, col)

func _init_player_panels() -> void:
	# 清空容器
	for c in left_players.get_children():
		c.queue_free()
	for c in right_players.get_children():
		c.queue_free()
	for c in bottom_player_slot.get_children():
		c.queue_free()

	_player_panels.clear()
	_player_panels.resize(5)

	# 你
	var p0 = PlayerPanelScene.instantiate()
	bottom_player_slot.add_child(p0)
	p0.set_player(0, "你")
	_player_panels[0] = p0

	# 左侧：电脑1、2
	for pid in [1, 2]:
		var pn = PlayerPanelScene.instantiate()
		left_players.add_child(pn)
		pn.set_player(pid, "电脑%d" % pid)
		_player_panels[pid] = pn

	# 右侧：电脑3、4
	for pid in [3, 4]:
		var pn2 = PlayerPanelScene.instantiate()
		right_players.add_child(pn2)
		pn2.set_player(pid, "电脑%d" % pid)
		_player_panels[pid] = pn2

func _update_player_panels(s: Dictionary) -> void:
	var cash: Array = s.get("cash", [])
	var hand_sizes: Array = s.get("hand_sizes", [])
	var ap: int = int(s.get("active_player", -1))

	for p in range(min(5, cash.size())):
		var panel: Variant = _player_panels[p]
		if panel == null or not is_instance_valid(panel):
			continue
		var hs: int = 0
		if p < hand_sizes.size():
			hs = int(hand_sizes[p])
		panel.update_from_snapshot(int(cash[p]), hs, p == ap)

func _update_market_board(s: Dictionary) -> void:
	var counts: Array = s.get("table_counts", [0, 0, 0, 0, 0])
	var values: Array = s.get("artist_values", [0, 0, 0, 0, 0])
	var lines: Array[String] = []
	for a in range(5):
		var color: String = ARTIST_COLORS[a].to_html(false)
		var count: int = int(counts[a]) if a < counts.size() else 0
		var value: int = int(values[a]) if a < values.size() else 0
		var name: String = CardDefs.artist_display_name(a)
		lines.append("[color=#%s]●[/color] [b]%s[/b]  %d/5  ¥%d" % [color, name, count, value])
	market_info.text = "[b]热度 / 市值[/b]\n" + "\n".join(lines)

func _floating_text_pos_for_player(p: int) -> Vector2:
	if p >= 0 and p < _player_panels.size():
		var panel: Variant = _player_panels[p]
		if panel != null and is_instance_valid(panel):
			var rect: Rect2 = (panel as Control).get_global_rect()
			var global_pos: Vector2 = rect.position + Vector2(rect.size.x - 30.0, 16.0)
			# Control 没有 to_local()；用 canvas transform 手动换算到 hud_root 局部坐标
			var inv: Transform2D = hud_root.get_global_transform_with_canvas().affine_inverse()
			return inv * global_pos
	return Vector2(640, 56)

func _on_auction_input_requested(info: Dictionary) -> void:
	var action: int = int(info.get("action", GameState.HumanAction.NONE))
	var cards: Array = info.get("cards", [])
	var title := _describe_cards(cards)
	_pulse_panel(hand_action_dock, 1.02)

	match action:
		GameState.HumanAction.OPEN_BID_OR_PASS:
			var highest: int = int(info.get("highest_bid", 0))
			var cash: Array = info.get("cash", [])
			var my_cash: int = int(cash[0]) if cash.size() > 0 else 0
			auction_info.text = "[b]%s[/b]\n公开竞价  最高 %d\n现金 %d" % [title, highest, my_cash]

			btn1.disabled = false
			btn2.disabled = false
			btn3.disabled = false
			btn1.text = "输入出价"
			btn2.text = "+5000"
			btn3.text = "放弃"
			btn1.pressed.connect(func():
				var min_bid: int = min(highest + 1000, my_cash)
				_prompt_number("输入出价（最少%d）" % min_bid, min_bid, my_cash, min_bid, func(v):
					gs.human_submit_amount(int(v))
				)
			, CONNECT_ONE_SHOT)
			btn2.pressed.connect(func():
				gs.human_submit_amount(min(highest + 5000, my_cash))
			, CONNECT_ONE_SHOT)
			btn3.pressed.connect(func():
				gs.human_pass()
			, CONNECT_ONE_SHOT)

		GameState.HumanAction.ONCE_BID_OR_PASS:
			var highest2: int = int(info.get("highest_bid", 0))
			var cash2: Array = info.get("cash", [])
			var my_cash2: int = int(cash2[0]) if cash2.size() > 0 else 0
			var min_bid2: int = highest2 + 1000
			auction_info.text = "[b]%s[/b]\n一轮报价  门槛 %d\n现金 %d" % [title, highest2, my_cash2]

			btn1.disabled = min_bid2 > my_cash2
			btn2.disabled = false
			btn3.disabled = true
			btn1.text = "输入报价"
			btn2.text = "放弃"
			btn3.text = "—"
			btn1.pressed.connect(func():
				_prompt_number("输入一次性报价（最少%d）" % min_bid2, min_bid2, my_cash2, min_bid2, func(v):
					gs.human_submit_amount(int(v))
				)
			, CONNECT_ONE_SHOT)
			btn2.pressed.connect(func():
				gs.human_pass()
			, CONNECT_ONE_SHOT)

		GameState.HumanAction.SEALED_BID:
			var cash3: Array = info.get("cash", [])
			var my_cash3: int = int(cash3[0]) if cash3.size() > 0 else 0
			auction_info.text = "[b]%s[/b]\n密封竞价\n现金 %d" % [title, my_cash3]

			btn1.disabled = false
			btn2.disabled = false
			btn3.disabled = true
			btn1.text = "输入密封价"
			btn2.text = "出价0"
			btn3.text = "—"
			btn1.pressed.connect(func():
				_prompt_number("输入密封出价", 0, my_cash3, 0, func(v):
					gs.human_submit_amount(int(v))
				)
			, CONNECT_ONE_SHOT)
			btn2.pressed.connect(func():
				gs.human_submit_amount(0)
			, CONNECT_ONE_SHOT)

		GameState.HumanAction.FIXED_SET_PRICE:
			var cash4: Array = info.get("cash", [])
			var my_cash4: int = int(cash4[0]) if cash4.size() > 0 else 0
			auction_info.text = "[b]%s[/b]\n定价出售\n现金 %d" % [title, my_cash4]

			btn1.disabled = false
			btn2.disabled = true
			btn3.disabled = true
			btn1.text = "输入定价"
			btn2.text = "—"
			btn3.text = "—"
			btn1.pressed.connect(func():
				_prompt_number("输入定价", 0, my_cash4, 10000, func(v):
					gs.human_submit_amount(int(v))
				)
			, CONNECT_ONE_SHOT)

		GameState.HumanAction.FIXED_ACCEPT_OR_DECLINE:
			var price: int = int(info.get("fixed_price", 0))
			var cash5: Array = info.get("cash", [])
			var my_cash5: int = int(cash5[0]) if cash5.size() > 0 else 0
			auction_info.text = "[b]%s[/b]\n定价 %d\n现金 %d" % [title, price, my_cash5]

			btn1.disabled = false
			btn2.disabled = false
			btn3.disabled = true
			btn1.text = "买下"
			btn2.text = "不买"
			btn3.text = "—"
			btn1.pressed.connect(func():
				gs.human_fixed_decision(true)
			, CONNECT_ONE_SHOT)
			btn2.pressed.connect(func():
				gs.human_fixed_decision(false)
			, CONNECT_ONE_SHOT)

		GameState.HumanAction.EXTRA_CHOOSE_CARD:
			var candidates: Array = info.get("candidates", [])
			var lines: Array[String] = []
			for i in range(candidates.size()):
				var idx: int = int(candidates[i])
				if idx >= 0 and idx < _hand_order.size():
					lines.append("%d) %s" % [i, String(_hand_order[idx].get("title", "未知"))])
			auction_info.text = "[b]加牌（=）[/b]\n请选择要补的牌（同艺术家、不同符号），或放弃不补：\n" + "\n".join(lines)

			btn1.disabled = false
			btn2.disabled = false
			btn3.disabled = true
			btn1.text = "选择补牌"
			btn2.text = "不补"
			btn3.text = "—"
			btn1.pressed.connect(func():
				if candidates.is_empty():
					gs.human_pass()
					return
				_prompt_number("输入候选序号(0..%d)" % (candidates.size() - 1), 0, candidates.size() - 1, 0, func(v):
					var pick_i: int = int(v)
					var hand_idx: int = int(candidates[pick_i])
					gs.human_extra_choose_card(hand_idx)
				)
			, CONNECT_ONE_SHOT)
			btn2.pressed.connect(func():
				gs.human_pass()
			, CONNECT_ONE_SHOT)

		_:
			auction_info.text = "[b]等待…[/b]"
			_set_buttons_disabled()

func _describe_cards(cards: Array) -> String:
	if cards.size() == 1:
		return "作品：" + String(cards[0].get("title", ""))
	if cards.size() >= 2:
		return "作品（两张）：" + String(cards[0].get("title", "")) + " + " + String(cards[1].get("title", ""))
	return "作品"

func _prompt_number(title: String, min_v: int, max_v: int, default_v: int, cb: Callable) -> void:
	_dialog.title = title
	_spin.min_value = min_v
	_spin.max_value = max_v
	_spin.value = clamp(default_v, min_v, max_v)
	_dialog.confirmed.connect(func():
		cb.call(int(_spin.value))
	, CONNECT_ONE_SHOT)
	_dialog.popup_centered()

func _on_round_scored(r: Dictionary) -> void:
	var payouts: Array = r["payouts"]
	_show_toast("本轮收入：你 +%d" % int(payouts[0]))
	_clear_owned_visuals()

func _on_game_ended(r: Dictionary) -> void:
	_show_toast("游戏结束！胜者：" + String(r["winner_name"]))

func _show_toast(msg: String) -> void:
	toast.text = msg
	toast.visible = true
	toast.modulate = Color(1, 1, 1, 0)
	toast.position.y = 96.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.set_trans(Tween.TRANS_QUAD)
	_toast_tween.set_ease(Tween.EASE_OUT)
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.18)
	_toast_tween.parallel().tween_property(toast, "position:y", 90.0, 0.18)
	_toast_tween.tween_interval(2.1)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.22)
	_toast_tween.parallel().tween_property(toast, "position:y", 78.0, 0.22)
	_toast_tween.tween_callback(func(): toast.visible = false)

func _pulse_panel(node: CanvasItem, peak: float) -> void:
	if node == null:
		return
	node.scale = Vector2.ONE
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE * peak, 0.12)
	tw.tween_property(node, "scale", Vector2.ONE, 0.18)
