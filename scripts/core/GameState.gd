extends Node

const CardDefs := preload("res://scripts/core/CardDefs.gd")
const ScoringEngine := preload("res://scripts/core/ScoringEngine.gd")
const AiPlayer: Script = preload("res://scripts/ai/AiPlayer.gd")

signal state_changed(snapshot: Dictionary)
signal toast(msg: String)

# 需要人类输入时抛给UI（你=player0）
signal auction_input_requested(info: Dictionary)

signal round_scored(result: Dictionary)
signal game_ended(result: Dictionary)

# 用于表现层动效（不改变规则）
signal card_played(info: Dictionary) # {player:int, cards:Array, auctioneer:int, auction_type:int, ends_round:bool}
signal auction_resolved(info: Dictionary) # {auctioneer:int, winner:int, price:int, cards:Array, notes:String}
signal money_changed(info: Dictionary) # {player:int, delta:int, reason:String}

enum Phase { WAIT_PLAY_CARD, AUCTION_RUNNING, ROUND_SCORING, GAME_ENDED }

enum HumanAction {
	NONE,
	OPEN_BID_OR_PASS,
	ONCE_BID_OR_PASS,
	SEALED_BID,
	FIXED_SET_PRICE,
	FIXED_ACCEPT_OR_DECLINE,
	EXTRA_ADD_OR_DECLINE,
	EXTRA_CHOOSE_CARD,
}

enum AuctionKind { OPEN, ONCE_AROUND, SEALED, FIXED_PRICE }

class AuctionState:
	var kind: int = AuctionKind.OPEN
	var auctioneer: int = 0
	var cards: Array[Dictionary] = []
	var min_increment: int = 1000

	# OPEN
	var open_active: Array = [] # bool[]
	var open_current: int = 0
	var open_highest_bid: int = 0
	var open_highest_player: int = -1

	# ONCE_AROUND
	var once_order: Array[int] = []
	var once_index: int = 0
	var once_bids: Array[int] = [] # -1=pass
	var once_current_bid: int = 0

	# SEALED
	var sealed_order: Array[int] = []
	var sealed_index: int = 0
	var sealed_bids: Array[int] = [] # -1=unfilled

	# FIXED_PRICE
	var fixed_price: int = -1
	var fixed_order: Array[int] = []
	var fixed_index: int = 0

class ExtraState:
	var base_player: int = 0
	var base_card: Dictionary = {}
	var artist: int = 0
	var seeker: int = 0
	var skipped: Array = [] # bool[]

var player_count: int = 5
var player_names: Array[String] = []
var player_cash: Array[int] = []
var player_hands: Array[Array] = [] # Array[Array[Dictionary]]

var deck: Array[Dictionary] = []

var round_index: int = 0 # 0..3
var start_player: int = 0
var active_player: int = 0
var phase: int = Phase.WAIT_PLAY_CARD
var last_player_to_play: int = -1

# 价值（跨轮累加）
var artist_values: Array[int] = [0, 0, 0, 0, 0]

# 本轮：桌面与售出
var table_counts: Array[int] = [0, 0, 0, 0, 0] # 含第5张与未拍卖牌
var table_cards: Array[Dictionary] = [] # {card:Dictionary, played_by:int}
var sold_cards_by_player: Array[Array] = [] # Array[Array[Dictionary]]

var _ais: Array = [] # AiPlayer instances (player 1..n-1)

var _auction: AuctionState = null
var _extra: ExtraState = null

var _waiting_action: int = HumanAction.NONE
var _waiting_player: int = -1

func new_game(new_player_count: int = 5, rng_seed: int = 0) -> void:
	player_count = clamp(new_player_count, 3, 5)

	player_names.clear()
	player_cash.clear()
	player_hands.clear()
	_ais.clear()

	for p in range(player_count):
		player_names.append("你" if p == 0 else ("电脑%d" % p))
		player_cash.append(100000)
		player_hands.append([])
		_ais.append(null)
	for p in range(1, player_count):
		_ais[p] = AiPlayer.new()

	deck = CardDefs.build_standard_deck()
	_shuffle(deck, rng_seed)

	artist_values = [0, 0, 0, 0, 0]
	round_index = 0
	last_player_to_play = -1

	_deal_initial()
	_start_round(0)

func can_play_card(p: int, card_index: int) -> bool:
	return phase == Phase.WAIT_PLAY_CARD and p == active_player and card_index >= 0 and card_index < player_hands[p].size()

func play_card(p: int, card_index: int) -> void:
	if not can_play_card(p, card_index):
		emit_signal("toast", "现在不能出牌")
		return

	var card: Dictionary = player_hands[p][card_index]
	player_hands[p].remove_at(card_index)
	last_player_to_play = p

	var auction_type: int = int(card.get("auction", 0))
	if auction_type == CardDefs.AuctionType.EXTRA:
		_begin_extra(p, card)
		return

	_play_and_maybe_auction(p, [card], auction_type)

func human_pass() -> void:
	if _waiting_player != 0:
		return
	match _waiting_action:
		HumanAction.OPEN_BID_OR_PASS:
			_apply_open_pass(0)
		HumanAction.ONCE_BID_OR_PASS:
			_apply_once_bid(0, -1)
		HumanAction.EXTRA_CHOOSE_CARD:
			_apply_extra_decline(0)
		_:
			return
	_auto_advance()

func human_submit_amount(amount: int) -> void:
	if _waiting_player != 0:
		return
	match _waiting_action:
		HumanAction.OPEN_BID_OR_PASS:
			_apply_open_bid(0, amount)
		HumanAction.ONCE_BID_OR_PASS:
			_apply_once_bid(0, amount if amount > _auction.once_current_bid else -1)
		HumanAction.SEALED_BID:
			_apply_sealed_bid(0, amount)
		HumanAction.FIXED_SET_PRICE:
			_apply_fixed_set_price(amount)
		_:
			return
	_auto_advance()

func human_fixed_decision(accept: bool) -> void:
	if _waiting_player != 0 or _waiting_action != HumanAction.FIXED_ACCEPT_OR_DECLINE:
		return
	_apply_fixed_decision(0, accept)
	_auto_advance()

func human_extra_choose_card(card_index: int) -> void:
	if _waiting_player != 0 or _waiting_action != HumanAction.EXTRA_CHOOSE_CARD:
		return
	_apply_extra_choose_card(0, card_index)
	_auto_advance()

func _deal_initial() -> void:
	var n: int = 8
	if player_count == 3:
		n = 10
	elif player_count == 4:
		n = 9
	elif player_count == 5:
		n = 8
	for p in range(player_count):
		_draw_cards(p, n)

func _draw_extra_for_round() -> void:
	if round_index != 1 and round_index != 2:
		return
	var n: int = 0
	if player_count == 3:
		n = 6
	elif player_count == 4:
		n = 4
	elif player_count == 5:
		n = 3
	for p in range(player_count):
		_draw_cards(p, n)

func _draw_cards(p: int, n: int) -> void:
	for i in range(n):
		if deck.is_empty():
			return
		player_hands[p].append(deck.pop_back())

func _start_round(new_start_player: int) -> void:
	start_player = new_start_player
	active_player = new_start_player
	phase = Phase.WAIT_PLAY_CARD

	table_counts = [0, 0, 0, 0, 0]
	table_cards.clear()
	sold_cards_by_player.clear()
	for p in range(player_count):
		sold_cards_by_player.append([])

	_auction = null
	_extra = null
	_waiting_action = HumanAction.NONE
	_waiting_player = -1

	_draw_extra_for_round()
	emit_signal("toast", "第%d轮开始" % (round_index + 1))
	_emit_snapshot()
	_auto_advance()

func _auto_advance() -> void:
	_waiting_action = HumanAction.NONE
	_waiting_player = -1

	if phase == Phase.GAME_ENDED:
		_emit_snapshot()
		return

	# 若正在处理“加牌(=)”流程，继续推进
	if _extra != null and phase == Phase.AUCTION_RUNNING:
		_advance_extra()
		return

	# 若在拍卖，推进拍卖直到需要人类输入或结束
	if _auction != null and phase == Phase.AUCTION_RUNNING:
		_advance_auction()
		return

	# 若等待出牌，自动跳过没手牌的玩家；AI玩家自动出牌
	if phase != Phase.WAIT_PLAY_CARD:
		return

	if _all_hands_empty():
		_end_round(last_player_to_play, "所有牌已打完")
		return

	active_player = _next_player_with_cards(active_player)
	_emit_snapshot()

	if active_player != 0:
		_ai_play_turn(active_player)

func _ai_play_turn(p: int) -> void:
	var ai = _ais[p]
	if ai == null:
		return
	var snap: Dictionary = snapshot()
	var hand: Array = player_hands[p]
	if hand.is_empty():
		active_player = (p + 1) % player_count
		_auto_advance()
		return
	var idx: int = int(ai.choose_card_index(hand, snap))
	idx = clamp(idx, 0, hand.size() - 1)
	play_card(p, idx)

func _play_and_maybe_auction(auctioneer: int, cards: Array[Dictionary], auction_type: int) -> void:
	for c in cards:
		_add_table_card(auctioneer, c)

	var ends_round: bool = _is_round_end_triggered()
	emit_signal("card_played", {"player": auctioneer, "cards": cards, "auctioneer": auctioneer, "auction_type": auction_type, "ends_round": ends_round})

	if ends_round:
		_end_round(auctioneer, "触发第5张，本轮结束（最后牌不拍卖）")
		return

	_begin_auction(auctioneer, cards, auction_type)

func _add_table_card(played_by: int, card: Dictionary) -> void:
	var a: int = int(card.get("artist", 0))
	table_counts[a] += 1
	table_cards.append({"card": card, "played_by": played_by})

func _is_round_end_triggered() -> bool:
	for a in range(5):
		if table_counts[a] >= 5:
			return true
	return false

func _all_hands_empty() -> bool:
	for p in range(player_count):
		if player_hands[p].size() > 0:
			return false
	return true

func _next_player_with_cards(start_from: int) -> int:
	for i in range(player_count):
		var p: int = (start_from + i) % player_count
		if player_hands[p].size() > 0:
			return p
	return start_from

func _begin_auction(auctioneer: int, cards: Array[Dictionary], auction_type: int) -> void:
	phase = Phase.AUCTION_RUNNING

	_auction = AuctionState.new()
	_auction.auctioneer = auctioneer
	_auction.cards = cards

	match auction_type:
		CardDefs.AuctionType.OPEN:
			_auction.kind = AuctionKind.OPEN
			_auction.open_active = []
			for p in range(player_count):
				_auction.open_active.append(true)
			_auction.open_current = (auctioneer + 1) % player_count
			_auction.open_highest_bid = 0
			_auction.open_highest_player = -1
		CardDefs.AuctionType.ONCE_AROUND:
			_auction.kind = AuctionKind.ONCE_AROUND
			_auction.once_order = _order_from_left_including_auctioneer(auctioneer)
			_auction.once_index = 0
			_auction.once_bids = []
			_auction.once_current_bid = 0
			for p in range(player_count):
				_auction.once_bids.append(-1)
		CardDefs.AuctionType.SEALED:
			_auction.kind = AuctionKind.SEALED
			_auction.sealed_order = _order_from_auctioneer_clockwise(auctioneer)
			_auction.sealed_index = 0
			_auction.sealed_bids = []
			for p in range(player_count):
				_auction.sealed_bids.append(-1)
		CardDefs.AuctionType.FIXED_PRICE:
			_auction.kind = AuctionKind.FIXED_PRICE
			_auction.fixed_price = -1
			_auction.fixed_order = _order_from_left_excluding_auctioneer(auctioneer)
			_auction.fixed_index = 0
		_:
			# 未知类型，按公开竞价兜底
			_auction.kind = AuctionKind.OPEN
			_auction.open_active = []
			for p in range(player_count):
				_auction.open_active.append(true)
			_auction.open_current = (auctioneer + 1) % player_count
			_auction.open_highest_bid = 0
			_auction.open_highest_player = -1

	_emit_snapshot()
	_advance_auction()

func _advance_auction() -> void:
	while _auction != null and phase == Phase.AUCTION_RUNNING and _waiting_action == HumanAction.NONE:
		match _auction.kind:
			AuctionKind.OPEN:
				_advance_open()
			AuctionKind.ONCE_AROUND:
				_advance_once_around()
			AuctionKind.SEALED:
				_advance_sealed()
			AuctionKind.FIXED_PRICE:
				_advance_fixed_price()
			_:
				_advance_open()

func _advance_open() -> void:
	var remaining: int = 0
	var last_active: int = -1
	for p in range(player_count):
		if bool(_auction.open_active[p]):
			remaining += 1
			last_active = p
	if remaining <= 1:
		var winner: int = last_active
		var price: int = _auction.open_highest_bid
		if _auction.open_highest_player == -1:
			winner = _auction.auctioneer
			price = 0
		_finish_auction(winner, price, "公开竞价结束")
		return

	var p_now: int = _auction.open_current
	if p_now == 0:
		_request_human(HumanAction.OPEN_BID_OR_PASS, 0, _auction_info_for_ui())
		return

	var ai = _ais[p_now]
	var bid: int = int(ai.decide_open_bid(_auction_info_for_ai(p_now), _auction.open_highest_bid))
	if bid <= _auction.open_highest_bid:
		_apply_open_pass(p_now)
	else:
		_apply_open_bid(p_now, bid)

func _apply_open_pass(p: int) -> void:
	# 公开竞价：当前最高者“放弃加价”不应退出拍卖；无人出价时拍卖者也不会被淘汰（等价于拿回牌）
	if p == _auction.open_highest_player:
		_auction.open_current = _next_active_player(_auction.open_current)
		return
	if _auction.open_highest_player == -1 and p == _auction.auctioneer:
		_auction.open_current = _next_active_player(_auction.open_current)
		return
	_auction.open_active[p] = false
	_auction.open_current = _next_active_player(_auction.open_current)

func _apply_open_bid(p: int, bid: int) -> void:
	var capped: int = min(bid, player_cash[p])
	var min_bid: int = _auction.open_highest_bid + _auction.min_increment
	if capped < min_bid:
		_apply_open_pass(p)
		return
	_auction.open_highest_bid = capped
	_auction.open_highest_player = p
	_auction.open_current = _next_active_player(_auction.open_current)

func _next_active_player(from_p: int) -> int:
	for i in range(1, player_count + 1):
		var p: int = (from_p + i) % player_count
		if bool(_auction.open_active[p]):
			return p
	return from_p

func _advance_once_around() -> void:
	if _auction.once_index >= _auction.once_order.size():
		var winner: int = _resolve_highest_bidder(_auction.once_bids, _auction.auctioneer)
		var price: int = 0 if winner == -1 else _auction.once_bids[winner]
		if winner == -1:
			winner = _auction.auctioneer
			price = 0
		_finish_auction(winner, price, "一轮报价结束")
		return

	var p_now: int = _auction.once_order[_auction.once_index]
	if p_now == 0:
		_request_human(HumanAction.ONCE_BID_OR_PASS, 0, _auction_info_for_ui())
		return

	var ai = _ais[p_now]
	var bid: int = int(ai.decide_once_bid(_auction_info_for_ai(p_now)))
	if bid <= _auction.once_current_bid:
		_apply_once_bid(p_now, -1)
	else:
		_apply_once_bid(p_now, min(bid, player_cash[p_now]))

func _apply_once_bid(p: int, bid: int) -> void:
	if bid > _auction.once_current_bid:
		_auction.once_current_bid = bid
	_auction.once_bids[p] = bid
	_auction.once_index += 1

func _advance_sealed() -> void:
	if _auction.sealed_index >= _auction.sealed_order.size():
		var winner: int = _resolve_highest_bidder(_auction.sealed_bids, _auction.auctioneer)
		var price: int = 0 if winner == -1 else _auction.sealed_bids[winner]
		if winner == -1:
			winner = _auction.auctioneer
			price = 0
		_finish_auction(winner, price, "密封竞价结束")
		return

	var p_now: int = _auction.sealed_order[_auction.sealed_index]
	if p_now == 0:
		_request_human(HumanAction.SEALED_BID, 0, _auction_info_for_ui())
		return

	var ai = _ais[p_now]
	var bid: int = int(ai.decide_sealed_bid(_auction_info_for_ai(p_now)))
	_apply_sealed_bid(p_now, min(max(bid, 0), player_cash[p_now]))

func _apply_sealed_bid(p: int, bid: int) -> void:
	_auction.sealed_bids[p] = bid
	_auction.sealed_index += 1

func _advance_fixed_price() -> void:
	# 先由拍卖者定价
	if _auction.fixed_price < 0:
		if _auction.auctioneer == 0:
			_request_human(HumanAction.FIXED_SET_PRICE, 0, _auction_info_for_ui())
			return
		var ai = _ais[_auction.auctioneer]
		var price: int = int(ai.decide_fixed_price(_auction_info_for_ai(_auction.auctioneer)))
		_apply_fixed_set_price(price)
		return

	# 依次询问购买（不含拍卖者）
	if _auction.fixed_index >= _auction.fixed_order.size():
		# 无人购买，拍卖者自购（付给银行）
		var winner: int = _auction.auctioneer
		var price2: int = _auction.fixed_price
		_finish_auction(winner, price2, "无人接受定价，拍卖者自购")
		return

	var p_now: int = _auction.fixed_order[_auction.fixed_index]
	if p_now == 0:
		_request_human(HumanAction.FIXED_ACCEPT_OR_DECLINE, 0, _auction_info_for_ui())
		return

	var ai_b: Variant = _ais[p_now]
	var accept: bool = bool(ai_b.decide_fixed_accept(_auction.fixed_price, _auction_info_for_ai(p_now)))
	_apply_fixed_decision(p_now, accept)

func _apply_fixed_set_price(price: int) -> void:
	var capped: int = min(max(price, 0), player_cash[_auction.auctioneer])
	_auction.fixed_price = capped

func _apply_fixed_decision(p: int, accept: bool) -> void:
	if accept:
		_finish_auction(p, _auction.fixed_price, "接受定价")
	else:
		_auction.fixed_index += 1

func _finish_auction(winner: int, price: int, notes: String) -> void:
	var auctioneer: int = _auction.auctioneer
	var cards: Array[Dictionary] = _auction.cards
	_auction = null

	price = max(price, 0)
	price = min(price, player_cash[winner])

	var cash_before: Array[int] = []
	for p in range(player_count):
		cash_before.append(player_cash[p])

	# 支付：赢家->拍卖者；若拍卖者买回自己牌，则支付给银行（即仅扣款不加给自己）
	player_cash[winner] -= price
	if winner != auctioneer:
		player_cash[auctioneer] += price

	for p in range(player_count):
		var delta: int = player_cash[p] - cash_before[p]
		if delta != 0:
			emit_signal("money_changed", {"player": p, "delta": delta, "reason": "auction"})

	# 牌归属：计入本轮售出牌（仅拍卖成交的牌）
	for c in cards:
		sold_cards_by_player[winner].append(c)

	emit_signal("auction_resolved", {"auctioneer": auctioneer, "winner": winner, "price": price, "cards": cards, "notes": notes})
	emit_signal("toast", "拍卖结束：%s 以 %d 购得" % [player_names[winner], price])

	if _all_hands_empty():
		_end_round(auctioneer, "所有手牌已拍卖完，进入最终结算", true)
		return

	phase = Phase.WAIT_PLAY_CARD
	active_player = (auctioneer + 1) % player_count
	_emit_snapshot()
	_auto_advance()

func _resolve_highest_bidder(bids: Array[int], auctioneer: int) -> int:
	var best: int = -1
	for p in range(player_count):
		if bids[p] > best:
			best = bids[p]
	if best < 0:
		return -1
	var candidates: Array[int] = []
	for p in range(player_count):
		if bids[p] == best:
			candidates.append(p)
	if candidates.size() == 1:
		return candidates[0]
	return _tie_break(candidates, auctioneer)

func _tie_break(candidates: Array[int], start: int) -> int:
	var cand_set: Dictionary = {}
	for p in candidates:
		cand_set[int(p)] = true
	for i in range(player_count):
		var p2: int = (start + i) % player_count
		if cand_set.has(p2):
			return p2
	return candidates[0]

func _order_from_left_including_auctioneer(auctioneer: int) -> Array[int]:
	var order: Array[int] = []
	for i in range(1, player_count + 1):
		order.append((auctioneer + i) % player_count)
	return order

func _order_from_left_excluding_auctioneer(auctioneer: int) -> Array[int]:
	var order: Array[int] = []
	for i in range(1, player_count):
		order.append((auctioneer + i) % player_count)
	return order

func _order_from_auctioneer_clockwise(auctioneer: int) -> Array[int]:
	var order: Array[int] = []
	for i in range(player_count):
		order.append((auctioneer + i) % player_count)
	return order

func _auction_info_for_ui() -> Dictionary:
	return {
		"round_index": round_index,
		"phase": phase,
		"active_player": active_player,
		"auctioneer": _auction.auctioneer,
		"kind": _auction.kind,
		"cards": _auction.cards,
		"highest_bid": _auction.open_highest_bid if _auction.kind == AuctionKind.OPEN else (_auction.once_current_bid if _auction.kind == AuctionKind.ONCE_AROUND else 0),
		"fixed_price": _auction.fixed_price if _auction.kind == AuctionKind.FIXED_PRICE else -1,
		"cash": player_cash.duplicate(),
	}

func _auction_info_for_ai(p: int) -> Dictionary:
	return {
		"player": p,
		"round_index": round_index,
		"auctioneer": _auction.auctioneer,
		"kind": _auction.kind,
		"cards": _auction.cards,
		"cash": player_cash.duplicate(),
		"table_counts": table_counts.duplicate(),
		"artist_values": artist_values.duplicate(),
	}

func _request_human(action: int, player: int, info: Dictionary) -> void:
	_waiting_action = action
	_waiting_player = player
	info["action"] = action
	info["player"] = player
	emit_signal("auction_input_requested", info)

func _begin_extra(p: int, base_card: Dictionary) -> void:
	# base_card 已从手牌移除；先放到桌面（计数）
	_add_table_card(p, base_card)

	_extra = ExtraState.new()
	_extra.base_player = p
	_extra.base_card = base_card
	_extra.artist = int(base_card.get("artist", 0))
	_extra.seeker = p
	_extra.skipped = []
	for i in range(player_count):
		_extra.skipped.append(false)

	phase = Phase.AUCTION_RUNNING
	_emit_snapshot()
	_advance_extra()

func _advance_extra() -> void:
	if _extra == null or _waiting_action != HumanAction.NONE:
		return

	# 依次询问是否补同艺术家、且符号不同（不能是EXTRA）
	var seeker: int = _extra.seeker
	var candidates: Array[int] = _extra_candidate_indices(seeker, _extra.artist)

	if seeker == 0:
		# 人类：先询问是否愿意补牌
		if candidates.is_empty():
			_apply_extra_decline(0)
			return
		_request_human(HumanAction.EXTRA_CHOOSE_CARD, 0, {"artist": _extra.artist, "candidates": candidates, "player": 0})
		return

	if not candidates.is_empty():
		var ai = _ais[seeker]
		var choose: int = int(ai.decide_extra_follow(_extra.artist, candidates, snapshot()))
		if choose >= 0 and choose < candidates.size():
			_apply_extra_choose_card(seeker, candidates[choose])
			return

	_apply_extra_decline(seeker)

func _apply_extra_decline(p: int) -> void:
	_extra.skipped[p] = true
	_extra.seeker = (p + 1) % player_count

	# 若回到base_player，表示无人补牌
	if _extra.seeker == _extra.base_player:
		emit_signal("toast", "无人补牌：加牌(=)放到桌面，不拍卖")
		_extra = null
		phase = Phase.WAIT_PLAY_CARD
		active_player = (_extra_next_player_no_adder()) # 正常轮转：base_player左手
		_emit_snapshot()
		_auto_advance()
		return

	_advance_extra()

func _extra_next_player_no_adder() -> int:
	return (last_player_to_play + 1) % player_count if last_player_to_play >= 0 else 0

func _apply_extra_choose_card(p: int, card_index: int) -> void:
	# p 补出一张同艺术家的非EXTRA牌，并成为拍卖者
	if card_index < 0 or card_index >= player_hands[p].size():
		_apply_extra_decline(p)
		return

	var add_card: Dictionary = player_hands[p][card_index]
	if int(add_card.get("artist", -1)) != _extra.artist or int(add_card.get("auction", 0)) == CardDefs.AuctionType.EXTRA:
		_apply_extra_decline(p)
		return

	player_hands[p].remove_at(card_index)
	last_player_to_play = p
	_add_table_card(p, add_card)

	var cards_for_auction: Array[Dictionary] = [_extra.base_card, add_card]
	var auction_type: int = int(add_card.get("auction", 0))

	var ends_round: bool = _is_round_end_triggered()
	emit_signal("card_played", {"player": p, "cards": cards_for_auction, "auctioneer": p, "auction_type": auction_type, "ends_round": ends_round})

	_extra = null
	if ends_round:
		_end_round(p, "加牌补牌后触发本轮结束（两张不拍卖）")
		return

	_begin_auction(p, cards_for_auction, auction_type)

func _extra_candidate_indices(p: int, artist: int) -> Array[int]:
	var res: Array[int] = []
	for i in range(player_hands[p].size()):
		var c: Dictionary = player_hands[p][i]
		if int(c.get("artist", -1)) == artist and int(c.get("auction", 0)) != CardDefs.AuctionType.EXTRA:
			res.append(i)
	return res

func _end_round(last_player: int, reason: String, force_game_end: bool = false) -> void:
	phase = Phase.ROUND_SCORING
	emit_signal("toast", "本轮结算：" + reason)

	var cash_before: Array[int] = []
	for p in range(player_count):
		cash_before.append(player_cash[p])

	# 30/20/10 标记累加
	ScoringEngine.apply_round_markers(artist_values, table_counts)

	# 只有本轮进入前三的艺术家才按其累计价值结算；其余艺术家本轮价值为0。
	var round_values: Array[int] = ScoringEngine.current_round_values(artist_values, table_counts)
	var payouts: Array[int] = ScoringEngine.payout_for_sold_cards(round_values, sold_cards_by_player)
	for p in range(player_count):
		player_cash[p] += payouts[p]

	for p in range(player_count):
		var delta: int = player_cash[p] - cash_before[p]
		if delta != 0:
			emit_signal("money_changed", {"player": p, "delta": delta, "reason": "round_score"})

	emit_signal("round_scored", {
		"round_index": round_index,
		"table_counts": table_counts.duplicate(),
		"artist_values": artist_values.duplicate(),
		"payouts": payouts,
		"cash": player_cash.duplicate(),
	})

	# 清空本轮牌（移出游戏）
	table_cards.clear()
	for p in range(player_count):
		sold_cards_by_player[p].clear()
	table_counts = [0, 0, 0, 0, 0]

	round_index += 1
	if force_game_end or round_index >= 4:
		_end_game()
		return

	var next_start: int = (last_player + 1) % player_count if last_player >= 0 else 0
	_start_round(next_start)

func _end_game() -> void:
	phase = Phase.GAME_ENDED
	var best_p: int = 0
	var best_cash: int = player_cash[0]
	for p in range(1, player_count):
		if player_cash[p] > best_cash:
			best_cash = player_cash[p]
			best_p = p
	var result := {"cash": player_cash.duplicate(), "winner": best_p, "winner_name": player_names[best_p]}
	emit_signal("game_ended", result)
	_emit_snapshot()

func snapshot() -> Dictionary:
	var hand_sizes: Array[int] = []
	for p in range(player_count):
		hand_sizes.append(player_hands[p].size())
	return {
		"player_count": player_count,
		"round_index": round_index,
		"start_player": start_player,
		"active_player": active_player,
		"phase": phase,
		"cash": player_cash.duplicate(),
		"hand_sizes": hand_sizes,
		"hand": player_hands[0].duplicate(true),
		"table_counts": table_counts.duplicate(),
		"artist_values": artist_values.duplicate(),
		"deck_remaining": deck.size(),
	}

func _emit_snapshot() -> void:
	emit_signal("state_changed", snapshot())

func _shuffle(arr: Array, rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
