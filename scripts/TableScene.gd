extends Control

const GameState := preload("res://scripts/core/GameState.gd")
const CardDefs := preload("res://scripts/core/CardDefs.gd")
const AiPlayer: Script = preload("res://scripts/ai/AiPlayer.gd")
const AssetResolver := preload("res://scripts/assets/AssetResolver.gd")

@onready var round_label: Label = $Hud/TopBar/TopHBox/RoundLabel
@onready var turn_label: Label = $Hud/TopBar/TopHBox/TurnLabel
@onready var money_label: Label = $Hud/TopBar/TopHBox/MoneyLabel
@onready var gallery_rich: RichTextLabel = $Hud/CenterArea/Right/GalleryPanel/GalleryRich
@onready var auction_info: RichTextLabel = $Hud/CenterArea/Left/AuctionPanel/AuctionVBox/AuctionInfo
@onready var btn1: Button = $Hud/CenterArea/Left/AuctionPanel/AuctionVBox/AuctionButtons/Btn1
@onready var btn2: Button = $Hud/CenterArea/Left/AuctionPanel/AuctionVBox/AuctionButtons/Btn2
@onready var btn3: Button = $Hud/CenterArea/Left/AuctionPanel/AuctionVBox/AuctionButtons/Btn3
@onready var hand_hbox: HBoxContainer = $Hud/HandBar/HandVBox/HandScroll/HandHBox
@onready var toast: Label = $Hud/Overlay/Toast
@onready var anim_layer: Control = $Hud/AnimLayer

var gs: Node
var ai: RefCounted

var _pending_prompt: Dictionary = {}
var _dialog: AcceptDialog
var _spin: SpinBox

func _ready() -> void:
	_apply_chinese_font_if_available()
	_init_dialog()
	_init_game()

func _apply_chinese_font_if_available() -> void:
	var f := AssetResolver.load_font_or_null()
	if f == null:
		return
	var ui_theme := Theme.new()
	ui_theme.set_default_font(f)
	ui_theme.set_default_font_size(18)
	self.theme = ui_theme

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
	gs = GameState.new()
	add_child(gs)
	ai = AiPlayer.new()

	gs.state_changed.connect(_on_state_changed)
	gs.toast.connect(_show_toast)
	gs.auction_prompt.connect(_on_auction_prompt)
	gs.round_scored.connect(_on_round_scored)
	gs.game_ended.connect(_on_game_ended)

	gs.new_game()

func _on_state_changed(s: Dictionary) -> void:
	var r := int(s["round_index"]) + 1
	round_label.text = "第%d轮 / 共4轮" % r

	var ap := int(s["active_player"])
	turn_label.text = "轮到：%s" % ("你" if ap == 0 else "电脑")

	var cash: Array = s["cash"]
	money_label.text = "现金：你 %d｜电脑 %d" % [int(cash[0]), int(cash[1])]

	_render_market(s["sold_counts"])
	_render_hand(s["hands"][0], ap == 0 and int(s["phase"]) == GameState.Phase.WAIT_PLAY_CARD)
	_set_buttons_disabled()
	auction_info.text = "[b]等待出牌…[/b]\n在你的回合，点击一张手牌发起拍卖。"

	if ap == 1 and int(s["phase"]) == GameState.Phase.WAIT_PLAY_CARD:
		_ai_take_turn_play_card(s)

func _render_market(sold_counts: Dictionary) -> void:
	var lines: Array[String] = []
	for a in sold_counts.keys():
		pass
	# 固定顺序显示
	for a in [CardDefs.Artist.CARVALHO, CardDefs.Artist.MARTINS, CardDefs.Artist.MELIM, CardDefs.Artist.SILVEIRA, CardDefs.Artist.THALER]:
		lines.append("%s：%d" % [CardDefs.artist_display_name(a), int(sold_counts.get(a, 0))])
	gallery_rich.text = "[b]本轮售出统计[/b]\n" + "\n".join(lines)

func _render_hand(hand: Array, enable_click: bool) -> void:
	for c in hand_hbox.get_children():
		c.queue_free()
	for i in range(hand.size()):
		var card: Dictionary = hand[i]
		var b := Button.new()
		var t := int(card["auction"])
		b.text = "%s\n[%s]" % [String(card["title"]), CardDefs.auction_display_name(t)]
		b.custom_minimum_size = Vector2(170, 92)
		b.disabled = not enable_click
		b.pressed.connect(func():
			if enable_click:
				_animate_play_card_from_button(b, card)
				gs.play_card(0, i)
		)
		hand_hbox.add_child(b)

func _animate_play_card_from_button(b: Control, card: Dictionary) -> void:
	# 轻量动画：在AnimLayer里生成一张卡牌视图，从按钮位置飞向拍卖区左侧
	var card_view_script := preload("res://scripts/ui/CardView.gd")
	var cv := card_view_script.new()
	anim_layer.add_child(cv)
	cv.set_card_text(String(card["title"]), CardDefs.auction_display_name(int(card["auction"])))
	cv.scale = Vector2.ONE * 0.85

	var from := b.get_global_rect().position + Vector2(0, -40)
	cv.global_position = from
	cv.pop()

	var to := auction_info.get_global_rect().position + Vector2(12, 12)
	cv.animate_to(to, 0.22)
	var tw := create_tween()
	tw.tween_interval(0.30)
	tw.tween_callback(func(): cv.queue_free())

func _set_buttons_disabled() -> void:
	for b in [btn1, btn2, btn3]:
		b.disabled = true
		b.text = "—"

func _on_auction_prompt(prompt: Dictionary) -> void:
	_pending_prompt = prompt
	var seller := int(prompt["seller"])
	var t := int(prompt["type"])
	var cards: Array = prompt["cards"]
	var title := _describe_cards(cards)
	auction_info.text = "[b]%s[/b]\n卖家：%s\n拍卖方式：%s" % [
		title,
		("你" if seller == 0 else "电脑"),
		CardDefs.auction_display_name(t)
	]

	# 2人局：卖家=出牌者；买家=另一方
	# - 你当卖家：除“定价出售”需要你输入定价外，其它拍卖由AI自动给出买方动作
	# - 电脑当卖家：你输入买方动作（出价/接受/放弃）
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
			var price := int(v)
			# AI作为买家决定是否接受
			var acc: Array = ai.respond_fixed_price(price, prompt)
			gs.submit_fixed_price(price, acc)
		)
	, CONNECT_ONE_SHOT)

func _setup_human_buyer_controls(prompt: Dictionary) -> void:
	var t := int(prompt["type"])
	match t:
		CardDefs.AuctionType.OPEN:
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
			var bid := int(v)
			var bids := [{"player": 0, "amount": bid, "is_pass": false}]
			gs.submit_open_bids(bids)
		)
	, CONNECT_ONE_SHOT)
	btn2.pressed.connect(func():
		var bids := [{"player": 0, "amount": 0, "is_pass": true}]
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
	# AI为卖家，需要先由AI设定价格，再让你决定买/不买
	var price := int(_pending_prompt.get("fixed_price_from_ai", -1))
	if price < 0:
		price = ai.choose_fixed_price(prompt)
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

func _prompt_number(title: String, min_v: int, max_v: int, default_v: int, cb: Callable) -> void:
	_dialog.title = title
	_spin.min_value = min_v
	_spin.max_value = max_v
	_spin.value = clamp(default_v, min_v, max_v)
	_dialog.confirmed.connect(func():
		cb.call(int(_spin.value))
	, CONNECT_ONE_SHOT)
	_dialog.popup_centered()

func _ai_take_turn_play_card(s: Dictionary) -> void:
	var hand: Array = s["hands"][1]
	if hand.is_empty():
		return
	var idx: int = int(ai.choose_card_index(hand, s))
	idx = clamp(idx, 0, hand.size() - 1)
	gs.play_card(1, idx)

func _ai_handle_buyer_prompt(prompt: Dictionary) -> void:
	# AI作为买家（seller为你）
	var t := int(prompt["type"])
	match t:
		CardDefs.AuctionType.OPEN:
			var bids: Array = ai.make_open_bids(prompt)
			gs.submit_open_bids(bids)
		CardDefs.AuctionType.ONCE_AROUND:
			gs.submit_once_around(ai.make_once_around(prompt))
		CardDefs.AuctionType.SEALED:
			gs.submit_sealed(ai.make_sealed_bid(prompt))
		_:
			gs.submit_open_bids([{"player": 1, "amount": 0, "is_pass": true}])

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
