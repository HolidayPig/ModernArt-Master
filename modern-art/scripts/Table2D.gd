extends Node2D

const GameState := preload("res://scripts/core/GameState.gd")
const CardDefs := preload("res://scripts/core/CardDefs.gd")
const AiPlayer: Script = preload("res://scripts/ai/AiPlayer.gd")
const AssetResolver := preload("res://scripts/assets/AssetResolver.gd")
const CardActorScene: PackedScene = preload("res://scenes/CardActor.tscn")
const ModernArtGenerator: Script = preload("res://scripts/art/ModernArtGenerator.gd")
const FloatingText: Script = preload("res://scripts/ui/FloatingText.gd")

@onready var bg: Sprite2D = $Background
@onready var cards_layer: Node2D = $CardsLayer
@onready var deck_anchor: Marker2D = $BoardAnchors/DeckAnchor
@onready var auction_anchor: Marker2D = $BoardAnchors/AuctionAnchor
@onready var player_collection_anchor: Marker2D = $BoardAnchors/PlayerCollectionAnchor
@onready var ai_collection_anchor: Marker2D = $BoardAnchors/AiCollectionAnchor

@onready var round_label: Label = $Hud/HudRoot/TopBar/TopHBox/RoundLabel
@onready var turn_label: Label = $Hud/HudRoot/TopBar/TopHBox/TurnLabel
@onready var money_label: Label = $Hud/HudRoot/TopBar/TopHBox/MoneyLabel
@onready var auction_info: RichTextLabel = $Hud/HudRoot/AuctionPanel/AuctionVBox/AuctionInfo
@onready var btn1: Button = $Hud/HudRoot/AuctionPanel/AuctionVBox/AuctionButtons/Btn1
@onready var btn2: Button = $Hud/HudRoot/AuctionPanel/AuctionVBox/AuctionButtons/Btn2
@onready var btn3: Button = $Hud/HudRoot/AuctionPanel/AuctionVBox/AuctionButtons/Btn3
@onready var toast: Label = $Hud/HudRoot/Toast

var gs: Node
var ai: RefCounted

var _pending_prompt: Dictionary = {}
var _dialog: AcceptDialog
var _spin: SpinBox

var _last_snapshot: Dictionary = {}
var _hand_by_id: Dictionary = {} # card_id(int) -> CardActor(Node)
var _hand_order: Array = [] # Array[Dictionary]
var _in_flight: Dictionary = {} # card_id(int) -> actor

var _frame_tex: Texture2D
var _back_tex: Texture2D
var _art: RefCounted

func _ready() -> void:
	_apply_chinese_font_if_available()
	_init_dialog()
	_init_background()
	_init_card_textures()
	_art = ModernArtGenerator.new()
	_init_game()

func _apply_chinese_font_if_available() -> void:
	var f := AssetResolver.load_font_or_null()
	if f == null:
		return
	var ui_theme := Theme.new()
	ui_theme.set_default_font(f)
	ui_theme.set_default_font_size(18)
	$Hud/HudRoot.theme = ui_theme

func _init_dialog() -> void:
	_dialog = AcceptDialog.new()
	_dialog.title = "输入数值"
	add_child(_dialog)

	var vb := VBoxContainer.new()
	_dialog.add_child(vb)

	_spin = SpinBox.new()
	_spin.min_value = 0
	_spin.max_value = 200
	_spin.step = 1
	_spin.value = 0
	vb.add_child(_spin)

func _init_game() -> void:
	if _art == null:
		_art = ModernArtGenerator.new()
	gs = GameState.new()
	add_child(gs)
	ai = AiPlayer.new()

	gs.state_changed.connect(_on_state_changed)
	gs.toast.connect(_show_toast)
	gs.auction_prompt.connect(_on_auction_prompt)
	gs.round_scored.connect(_on_round_scored)
	gs.game_ended.connect(_on_game_ended)
	gs.card_played.connect(_on_card_played)
	gs.auction_resolved.connect(_on_auction_resolved)
	gs.money_changed.connect(_on_money_changed)

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

	# 中间铺一块“拍卖桌面”
	_draw_rect(img, Rect2i(420, 120, 440, 300), Color(0.12, 0.13, 0.18, 1))
	_draw_rect_outline(img, Rect2i(420, 120, 440, 300), Color(0.22, 0.24, 0.32, 1))

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
	turn_label.text = "轮到：%s" % ("你" if ap == 0 else "电脑")

	var cash: Array = s["cash"]
	money_label.text = "现金：你 %d｜电脑 %d" % [int(cash[0]), int(cash[1])]

	auction_info.text = "[b]等待出牌…[/b]\n点击下方手牌出牌。"
	_set_buttons_disabled()

	_render_hand(s)

	# 电脑回合自动出牌
	var phase: int = int(s["phase"])
	var active_p: int = int(s["active_player"])
	if active_p == 1 and phase == GameState.Phase.WAIT_PLAY_CARD:
		_ai_take_turn_play_card(s)

func _set_buttons_disabled() -> void:
	for b in [btn1, btn2, btn3]:
		b.disabled = true
		b.text = "—"

func _render_hand(s: Dictionary) -> void:
	var hands: Array = s["hands"]
	var hand: Array = hands[0]
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

	var center_x: float = 640.0
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

func _ai_take_turn_play_card(s: Dictionary) -> void:
	var hands: Array = s["hands"]
	var hand_ai: Array = hands[1]
	if hand_ai.is_empty():
		return
	var idx: int = int(ai.choose_card_index(hand_ai, s))
	idx = clamp(idx, 0, hand_ai.size() - 1)
	gs.play_card(1, idx)

func _on_card_played(info: Dictionary) -> void:
	# AI出牌时创建临时卡牌实体从牌库位飞到拍卖位
	var seller: int = int(info.get("seller", -1))
	if seller != 1:
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
	var target: Vector2 = player_collection_anchor.position if winner == 0 else ai_collection_anchor.position

	for c in cards:
		var idc: int = int(c.get("id", -1))
		var actor = null
		if _in_flight.has(idc):
			actor = _in_flight[idc]
		elif _hand_by_id.has(idc):
			actor = _hand_by_id[idc]

		if actor == null:
			continue

		var rot: float = 0.10 if winner == 0 else -0.10
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

func _on_money_changed(info: Dictionary) -> void:
	var p: int = int(info.get("player", -1))
	var delta: int = int(info.get("delta", 0))
	if delta == 0:
		return
	var pos := Vector2(860, 40) if p == 0 else Vector2(1040, 40)
	var col := Color(0.35, 0.95, 0.65, 1) if delta > 0 else Color(0.95, 0.35, 0.45, 1)
	var msg := ("%+d" % delta)
	var ft: Label = FloatingText.new()
	$Hud/HudRoot.add_child(ft)
	ft.start(msg, pos, col)

func _on_auction_prompt(prompt: Dictionary) -> void:
	_pending_prompt = prompt
	var seller: int = int(prompt["seller"])
	var t: int = int(prompt["type"])
	var cards: Array = prompt["cards"]
	var title := _describe_cards(cards)
	auction_info.text = "[b]%s[/b]\n卖家：%s\n拍卖方式：%s" % [
		title,
		("你" if seller == 0 else "电脑"),
		CardDefs.auction_display_name(t)
	]

	# 首版先沿用原有交互逻辑：电脑当卖家你输入；你当卖家多数由AI自动
	if seller == 0:
		if t == CardDefs.AuctionType.FIXED_PRICE:
			_setup_human_seller_fixed_price(prompt)
		else:
			_set_buttons_disabled()
			_ai_handle_buyer_prompt(prompt)
	else:
		_setup_human_buyer_controls(prompt)

func _describe_cards(cards: Array) -> String:
	if cards.size() == 1:
		return "拍卖作品：" + String(cards[0]["title"])
	return "拍卖作品（两张）：" + String(cards[0]["title"]) + " + " + String(cards[1]["title"])

func _setup_human_seller_fixed_price(prompt: Dictionary) -> void:
	btn1.disabled = false
	btn2.disabled = true
	btn3.disabled = true
	btn1.text = "输入定价"
	btn2.text = "—"
	btn3.text = "—"
	btn1.pressed.connect(func():
		_prompt_number("输入你要定的价格", 0, 200, 20, func(v):
			var price: int = int(v)
			var acc: Array = ai.respond_fixed_price(price, prompt)
			gs.submit_fixed_price(price, acc)
		)
	, CONNECT_ONE_SHOT)

func _setup_human_buyer_controls(prompt: Dictionary) -> void:
	var t: int = int(prompt["type"])
	match t:
		CardDefs.AuctionType.OPEN, CardDefs.AuctionType.DOUBLE:
			_setup_human_buyer_open_like(prompt)
		CardDefs.AuctionType.ONCE_AROUND:
			_setup_human_buyer_once_around(prompt)
		CardDefs.AuctionType.FIXED_PRICE:
			_setup_human_buyer_fixed_price(prompt)
		CardDefs.AuctionType.SEALED:
			_setup_human_buyer_sealed(prompt)
		_:
			_set_buttons_disabled()

func _setup_human_buyer_open_like(prompt: Dictionary) -> void:
	btn1.disabled = false
	btn2.disabled = false
	btn3.disabled = true
	btn1.text = "输入出价"
	btn2.text = "放弃"
	btn3.text = "—"

	btn1.pressed.connect(func():
		var cash: Array = prompt.get("cash", [100, 100])
		_prompt_number("输入你的出价", 0, int(cash[0]), 15, func(v):
			var bid: int = int(v)
			var bids: Array = [{"player": 0, "amount": bid, "is_pass": false}]
			if int(prompt["type"]) == CardDefs.AuctionType.DOUBLE:
				gs.submit_double_open_bids(bids)
			else:
				gs.submit_open_bids(bids)
		)
	, CONNECT_ONE_SHOT)
	btn2.pressed.connect(func():
		var bids: Array = [{"player": 0, "amount": 0, "is_pass": true}]
		if int(prompt["type"]) == CardDefs.AuctionType.DOUBLE:
			gs.submit_double_open_bids(bids)
		else:
			gs.submit_open_bids(bids)
	, CONNECT_ONE_SHOT)

func _setup_human_buyer_once_around(prompt: Dictionary) -> void:
	btn1.disabled = false
	btn2.disabled = false
	btn3.disabled = true
	btn1.text = "输入一次报价"
	btn2.text = "放弃"
	btn3.text = "—"
	btn1.pressed.connect(func():
		var cash: Array = prompt.get("cash", [100, 100])
		_prompt_number("输入你的一次性报价", 0, int(cash[0]), 12, func(v):
			gs.submit_once_around([{"player": 0, "amount": int(v), "is_pass": false}])
		)
	, CONNECT_ONE_SHOT)
	btn2.pressed.connect(func():
		gs.submit_once_around([{"player": 0, "amount": 0, "is_pass": true}])
	, CONNECT_ONE_SHOT)

func _setup_human_buyer_fixed_price(prompt: Dictionary) -> void:
	var price: int = int(_pending_prompt.get("fixed_price_from_ai", -1))
	if price < 0:
		price = int(ai.choose_fixed_price(prompt))
		_pending_prompt["fixed_price_from_ai"] = price
		auction_info.text += "\n定价：%d" % price

	btn1.disabled = false
	btn2.disabled = false
	btn3.disabled = true
	btn1.text = "买下"
	btn2.text = "不买"
	btn3.text = "—"
	btn1.pressed.connect(func():
		gs.submit_fixed_price(price, [{"player": 0, "accept": true}])
	, CONNECT_ONE_SHOT)
	btn2.pressed.connect(func():
		gs.submit_fixed_price(price, [{"player": 0, "accept": false}])
	, CONNECT_ONE_SHOT)

func _setup_human_buyer_sealed(prompt: Dictionary) -> void:
	btn1.disabled = false
	btn2.disabled = false
	btn3.disabled = true
	btn1.text = "输入密封价"
	btn2.text = "出价0"
	btn3.text = "—"
	btn1.pressed.connect(func():
		var cash: Array = prompt.get("cash", [100, 100])
		_prompt_number("输入你的密封出价", 0, int(cash[0]), 10, func(v):
			gs.submit_sealed([{"player": 0, "amount": int(v)}])
		)
	, CONNECT_ONE_SHOT)
	btn2.pressed.connect(func():
		gs.submit_sealed([{"player": 0, "amount": 0}])
	, CONNECT_ONE_SHOT)

func _ai_handle_buyer_prompt(prompt: Dictionary) -> void:
	var t: int = int(prompt["type"])
	match t:
		CardDefs.AuctionType.OPEN, CardDefs.AuctionType.DOUBLE:
			var bids: Array = ai.make_open_bids(prompt)
			if t == CardDefs.AuctionType.DOUBLE:
				gs.submit_double_open_bids(bids)
			else:
				gs.submit_open_bids(bids)
		CardDefs.AuctionType.ONCE_AROUND:
			gs.submit_once_around(ai.make_once_around(prompt))
		CardDefs.AuctionType.SEALED:
			gs.submit_sealed(ai.make_sealed_bid(prompt))
		_:
			gs.submit_open_bids([{"player": 1, "amount": 0, "is_pass": true}])

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
	_show_toast("本轮收入：你 +%d｜电脑 +%d" % [int(payouts[0]), int(payouts[1])])

func _on_game_ended(r: Dictionary) -> void:
	_show_toast("游戏结束！胜者：" + String(r["winner_name"]))

func _show_toast(msg: String) -> void:
	toast.text = msg
	toast.visible = true
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(func(): toast.visible = false)
