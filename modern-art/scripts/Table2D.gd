extends Node2D

const GameState := preload("res://scripts/core/GameState.gd")
const CardDefs := preload("res://scripts/core/CardDefs.gd")
const AssetResolver := preload("res://scripts/assets/AssetResolver.gd")
const CardActorScene: PackedScene = preload("res://scenes/CardActor.tscn")
const ModernArtGenerator: Script = preload("res://scripts/art/ModernArtGenerator.gd")
const FloatingText: Script = preload("res://scripts/ui/FloatingText.gd")
const PlayerPanelScene: PackedScene = preload("res://scenes/ui/PlayerPanel.tscn")

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
@onready var auction_info: RichTextLabel = $Hud/HudRoot/LayoutMargin/LayoutVBox/MainHBox/CenterColumn/AuctionCenterPanel/AuctionVBox/AuctionInfo
@onready var btn1: Button = $Hud/HudRoot/HandActionDock/DockMargin/AuctionButtons/Btn1
@onready var btn2: Button = $Hud/HudRoot/HandActionDock/DockMargin/AuctionButtons/Btn2
@onready var btn3: Button = $Hud/HudRoot/HandActionDock/DockMargin/AuctionButtons/Btn3
@onready var toast: Label = $Hud/HudRoot/Toast

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

func _ready() -> void:
	_apply_chinese_font_if_available()
	_init_dialog()
	_init_background()
	_init_card_textures()
	_art = ModernArtGenerator.new()
	_init_game()

func _apply_chinese_font_if_available() -> void:
	var f := AssetResolver.load_font_or_null()
	var ui_theme := Theme.new()
	if f != null:
		ui_theme.set_default_font(f)
	ui_theme.set_default_font_size(18)

	# 极简深色主题：半透明面板 + 细描边 + 稳定字号层级
	ui_theme.set_color("font_color", "Label", Color(0.92, 0.94, 0.98, 1))
	ui_theme.set_color("font_color", "RichTextLabel", Color(0.92, 0.94, 0.98, 1))
	ui_theme.set_color("default_color", "RichTextLabel", Color(0.92, 0.94, 0.98, 1))
	ui_theme.set_color("font_color", "Button", Color(0.92, 0.94, 0.98, 1))
	ui_theme.set_color("font_color_disabled", "Button", Color(0.55, 0.58, 0.66, 1))

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.07, 0.09, 0.80)
	panel.border_color = Color(0.24, 0.26, 0.33, 0.90)
	panel.border_width_left = 1
	panel.border_width_top = 1
	panel.border_width_right = 1
	panel.border_width_bottom = 1
	panel.corner_radius_top_left = 12
	panel.corner_radius_top_right = 12
	panel.corner_radius_bottom_left = 12
	panel.corner_radius_bottom_right = 12
	panel.content_margin_left = 12
	panel.content_margin_top = 10
	panel.content_margin_right = 12
	panel.content_margin_bottom = 10
	ui_theme.set_stylebox("panel", "PanelContainer", panel)
	ui_theme.set_stylebox("panel", "Panel", panel)

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.10, 0.11, 0.14, 0.95)
	btn_normal.border_color = Color(0.26, 0.28, 0.36, 0.95)
	btn_normal.border_width_left = 1
	btn_normal.border_width_top = 1
	btn_normal.border_width_right = 1
	btn_normal.border_width_bottom = 1
	btn_normal.corner_radius_top_left = 10
	btn_normal.corner_radius_top_right = 10
	btn_normal.corner_radius_bottom_left = 10
	btn_normal.corner_radius_bottom_right = 10
	btn_normal.content_margin_left = 12
	btn_normal.content_margin_top = 8
	btn_normal.content_margin_right = 12
	btn_normal.content_margin_bottom = 8

	var btn_hover := btn_normal.duplicate()
	btn_hover.bg_color = Color(0.12, 0.13, 0.17, 0.98)
	btn_hover.border_color = Color(0.34, 0.36, 0.44, 0.98)

	var btn_pressed := btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.08, 0.09, 0.12, 0.98)
	btn_pressed.border_color = Color(0.34, 0.36, 0.44, 0.98)

	var btn_disabled := btn_normal.duplicate()
	btn_disabled.bg_color = Color(0.08, 0.09, 0.11, 0.75)
	btn_disabled.border_color = Color(0.18, 0.20, 0.26, 0.75)

	ui_theme.set_stylebox("normal", "Button", btn_normal)
	ui_theme.set_stylebox("hover", "Button", btn_hover)
	ui_theme.set_stylebox("pressed", "Button", btn_pressed)
	ui_theme.set_stylebox("disabled", "Button", btn_disabled)
	ui_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	ui_theme.set_constant("outline_size", "Label", 0)
	ui_theme.set_constant("outline_size", "RichTextLabel", 0)

	hud_root.theme = ui_theme

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
	gs.new_game()

func _init_background() -> void:
	bg.texture = _make_table_texture(Vector2i(1280, 720))
	bg.position = Vector2.ZERO

func _init_card_textures() -> void:
	# 先用下载素材的卡牌底图做框（后续会换成真正的卡框+卡面）
	_frame_tex = AssetResolver.load_texture_or_placeholder(
		"res://assets/downloaded/cards/color_empty.png",
		Vector2i(128, 180),
		Color(0.16, 0.16, 0.20, 1)
	)
	_back_tex = AssetResolver.load_texture_or_placeholder(
		"res://assets/downloaded/cards/color_back.png",
		Vector2i(128, 180),
		Color(0.10, 0.10, 0.12, 1)
	)

func _make_table_texture(size: Vector2i) -> Texture2D:
	# 像素风“牌桌”：深色底 + 轻微噪点 + 几何块
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.11, 0.14, 1))

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for y in range(0, size.y, 2):
		for x in range(0, size.x, 2):
			var n := rng.randi_range(-6, 6) / 255.0
			var c := Color(0.10 + n, 0.11 + n, 0.14 + n, 1)
			img.set_pixel(x, y, c)
			if x + 1 < size.x:
				img.set_pixel(x + 1, y, c)
			if y + 1 < size.y:
				img.set_pixel(x, y + 1, c)
				if x + 1 < size.x:
					img.set_pixel(x + 1, y + 1, c)

	# 中间铺一块“拍卖桌面”（位置与 AuctionAnchor 区域对齐，避免压到上方HUD）
	_draw_rect(img, Rect2i(360, 260, 560, 340), Color(0.12, 0.13, 0.18, 1))
	_draw_rect_outline(img, Rect2i(360, 260, 560, 340), Color(0.22, 0.24, 0.32, 1))

	return ImageTexture.create_from_image(img)

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
	turn_label.text = "轮到：%s" % ("你" if ap == 0 else ("电脑%d" % ap))

	var cash: Array = s["cash"]
	money_label.text = "牌库：%d" % int(s.get("deck_remaining", 0))

	auction_info.text = "[b]等待出牌…[/b]\n点击下方手牌出牌。"
	_set_buttons_disabled()

	_update_player_panels(s)
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

	var center_x: float = 600.0
	var base_y: float = 650.0
	var span: float = min(0.85, 0.12 * float(max(n - 1, 1)))

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
		var x: float = center_x + t * 560.0
		var y: float = base_y + abs(t) * 24.0
		var p := Vector2(x, y)

		actor.set_base_transform(p, rot)
		actor.z_index = i

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
		var actor = _hand_by_id[card_id]
		_hand_by_id.erase(card_id) # 防止后续渲染复用已释放实例
		_in_flight[card_id] = actor
		actor.play_to(auction_anchor.position, 0.0, 0.18)

	gs.play_card(0, idx)

func _on_card_played(info: Dictionary) -> void:
	# AI出牌时创建临时卡牌实体从牌库位飞到拍卖位
	var p: int = int(info.get("player", -1))
	if p == 0:
		return
	var cards: Array = info.get("cards", [])
	if cards.is_empty():
		return
	var c0: Dictionary = cards[0]
	var id0: int = int(c0.get("id", -1))

	var actor := CardActorScene.instantiate()
	cards_layer.add_child(actor)
	_in_flight[id0] = actor

	actor.set_card(c0)
	actor.set_textures(_frame_tex, _art.get_face_texture(c0))
	actor.set_font_size(14)
	actor.set_subtitle(CardDefs.auction_display_name(int(c0.get("auction", 0))))
	actor.set_base_transform(deck_anchor.position, 0.0)
	actor.play_to(auction_anchor.position, 0.0, 0.22)

func _on_auction_resolved(info: Dictionary) -> void:
	var winner: int = int(info.get("winner", -1))
	var cards: Array = info.get("cards", [])
	var target: Vector2 = _collection_target_for_player(winner)

	for c in cards:
		var idc: int = int(c.get("id", -1))
		var actor = null
		if _in_flight.has(idc):
			actor = _in_flight[idc]
		elif _hand_by_id.has(idc):
			actor = _hand_by_id[idc]

		if actor == null:
			continue

		var rot: float = 0.10 if winner in [0, 3, 4] else -0.10
		actor.play_to(target, rot, 0.26)

		var tw := create_tween()
		tw.tween_interval(0.28)
		tw.tween_property(actor, "modulate:a", 0.0, 0.20)
		tw.tween_callback(func():
			if _in_flight.has(idc):
				_in_flight.erase(idc)
			if actor != null:
				actor.queue_free()
		)

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

	match action:
		GameState.HumanAction.OPEN_BID_OR_PASS:
			var highest: int = int(info.get("highest_bid", 0))
			var cash: Array = info.get("cash", [])
			var my_cash: int = int(cash[0]) if cash.size() > 0 else 0
			auction_info.text = "[b]%s[/b]\n公开竞价：当前最高 %d\n你的现金：%d" % [title, highest, my_cash]

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
			var cash2: Array = info.get("cash", [])
			var my_cash2: int = int(cash2[0]) if cash2.size() > 0 else 0
			auction_info.text = "[b]%s[/b]\n一轮报价：请输入一次性报价或放弃\n你的现金：%d" % [title, my_cash2]

			btn1.disabled = false
			btn2.disabled = false
			btn3.disabled = true
			btn1.text = "输入报价"
			btn2.text = "放弃"
			btn3.text = "—"
			btn1.pressed.connect(func():
				_prompt_number("输入一次性报价", 0, my_cash2, 10000, func(v):
					gs.human_submit_amount(int(v))
				)
			, CONNECT_ONE_SHOT)
			btn2.pressed.connect(func():
				gs.human_pass()
			, CONNECT_ONE_SHOT)

		GameState.HumanAction.SEALED_BID:
			var cash3: Array = info.get("cash", [])
			var my_cash3: int = int(cash3[0]) if cash3.size() > 0 else 0
			auction_info.text = "[b]%s[/b]\n密封竞价：输入你的密封出价\n你的现金：%d" % [title, my_cash3]

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
			auction_info.text = "[b]%s[/b]\n定价出售：请设定价格（他人依次决定买/不买）\n你的现金：%d" % [title, my_cash4]

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
			auction_info.text = "[b]%s[/b]\n定价：%d\n你是否购买？（你的现金：%d）" % [title, price, my_cash5]

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

func _on_game_ended(r: Dictionary) -> void:
	_show_toast("游戏结束！胜者：" + String(r["winner_name"]))

func _show_toast(msg: String) -> void:
	toast.text = msg
	toast.visible = true
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(func(): toast.visible = false)
