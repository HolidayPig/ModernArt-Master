extends Node

const CardDefs := preload("res://scripts/core/CardDefs.gd")
const AuctionEngine: Script = preload("res://scripts/core/AuctionEngine.gd")
const ScoringEngine := preload("res://scripts/core/ScoringEngine.gd")

signal state_changed(snapshot: Dictionary)
signal toast(msg: String)
signal auction_prompt(prompt: Dictionary) # UI根据prompt渲染并回传输入
signal round_scored(result: Dictionary)
signal game_ended(result: Dictionary)

# 用于表现层动效（不改变规则）
signal card_played(info: Dictionary) # {seller:int, cards:Array, auction_type:int}
signal auction_started(info: Dictionary) # 同auction_prompt结构
signal auction_resolved(info: Dictionary) # {seller,winner,price,cards,notes,cash_before,cash_after}
signal money_changed(info: Dictionary) # {player:int, delta:int, reason:String}

enum Phase {
	WAIT_PLAY_CARD,
	AUCTION_RUNNING,
	ROUND_SCORING,
	GAME_ENDED
}

var player_names := ["你", "电脑"]
var player_cash: Array[int] = [100, 100]
var player_hands: Array[Array] = [[], []] # Array[Dictionary]
var player_collections: Array[Array] = [[], []]

var deck: Array[Dictionary] = []
var discard: Array[Dictionary] = []

var round_index: int = 0 # 0..3
var active_player: int = 0
var phase: int = Phase.WAIT_PLAY_CARD

var sold_counts: Dictionary = {} # artist -> count (本轮)

var current_auction: Dictionary = {} # 进行中的拍卖状态

func new_game(rng_seed: int = 0) -> void:
	player_cash = [100, 100]
	player_hands = [[], []]
	player_collections = [[], []]
	deck = CardDefs.build_standard_deck()
	_shuffle(deck, rng_seed)
	discard = []
	round_index = 0
	active_player = 0
	phase = Phase.WAIT_PLAY_CARD
	_start_round()

func _start_round() -> void:
	sold_counts.clear()
	_deal_for_round()
	phase = Phase.WAIT_PLAY_CARD
	emit_signal("toast", "第%d轮开始" % (round_index + 1))
	_emit_snapshot()

func _deal_for_round() -> void:
	# 原作无2人官方发牌，这里用“每轮每人10张”作为稳定可玩首版配置（总20张/轮）。
	# 其余牌留在牌库，下一轮继续抽。
	for p in range(2):
		player_hands[p].clear()
	for i in range(10):
		for p in range(2):
			if deck.is_empty():
				break
			player_hands[p].append(deck.pop_back())

func can_play_card(p: int, card_index: int) -> bool:
	return phase == Phase.WAIT_PLAY_CARD and p == active_player and card_index >= 0 and card_index < player_hands[p].size()

func play_card(p: int, card_index: int, extra_card_index: int = -1) -> void:
	if not can_play_card(p, card_index):
		emit_signal("toast", "现在不能出牌")
		return
	var card: Dictionary = player_hands[p][card_index]
	player_hands[p].remove_at(card_index)

	var cards_for_auction: Array[Dictionary] = [card]
	if int(card["auction"]) == CardDefs.AuctionType.DOUBLE:
		if extra_card_index < 0 or extra_card_index >= player_hands[p].size():
			# 兜底：若未提供附加牌，改为从手牌最前面取一张（若存在）
			if player_hands[p].size() > 0:
				extra_card_index = 0
		if extra_card_index >= 0 and extra_card_index < player_hands[p].size():
			var extra: Dictionary = player_hands[p][extra_card_index]
			player_hands[p].remove_at(extra_card_index)
			cards_for_auction.append(extra)

	emit_signal("card_played", {
		"seller": p,
		"cards": cards_for_auction,
		"auction_type": int(cards_for_auction[0]["auction"])
	})
	_begin_auction(p, cards_for_auction)

func _begin_auction(seller: int, cards_for_auction: Array[Dictionary]) -> void:
	phase = Phase.AUCTION_RUNNING
	current_auction = {
		"seller": seller,
		"cards": cards_for_auction,
		"auction_type": int(cards_for_auction[0]["auction"]),
	}
	_emit_snapshot()

	# 发给UI一个“该怎么输入”的prompt，UI/AI再调用 submit_* 回来
	var prompt := {
		"type": current_auction["auction_type"],
		"seller": seller,
		"cards": cards_for_auction,
		"cash": player_cash.duplicate(),
		"round_index": round_index,
		"sold_counts": sold_counts.duplicate(),
	}
	emit_signal("auction_started", prompt)
	emit_signal("auction_prompt", prompt)

func submit_open_bids(bids: Array) -> void:
	# bids: [{player, amount, is_pass}]，由UI/AI组织
	if phase != Phase.AUCTION_RUNNING:
		return
	var seller := int(current_auction["seller"])
	var res: Variant = AuctionEngine.resolve_open(bids, seller)
	_finalize_auction(res.winner_player, res.price, String(res.notes))

func submit_once_around(offered: Array) -> void:
	if phase != Phase.AUCTION_RUNNING:
		return
	var seller := int(current_auction["seller"])
	var res: Variant = AuctionEngine.resolve_once_around(offered, seller)
	_finalize_auction(res.winner_player, res.price, String(res.notes))

func submit_fixed_price(price: int, accepts_in_order: Array) -> void:
	if phase != Phase.AUCTION_RUNNING:
		return
	var seller := int(current_auction["seller"])
	var res: Variant = AuctionEngine.resolve_fixed_price(price, accepts_in_order, seller)
	_finalize_auction(res.winner_player, res.price, String(res.notes), true)

func submit_sealed(sealed_bids: Array) -> void:
	if phase != Phase.AUCTION_RUNNING:
		return
	var seller := int(current_auction["seller"])
	var res: Variant = AuctionEngine.resolve_sealed(sealed_bids, seller)
	_finalize_auction(res.winner_player, res.price, String(res.notes))

func submit_double_open_bids(bids: Array) -> void:
	# 首版：双重拍卖按公开竞价处理，得标者获得两张牌，支付一次价格
	if phase != Phase.AUCTION_RUNNING:
		return
	var seller := int(current_auction["seller"])
	var res: Variant = AuctionEngine.resolve_double(bids, seller)
	_finalize_auction(res.winner_player, res.price, String(res.notes))

func _finalize_auction(winner: int, price: int, notes: String, fixed_price_mode: bool = false) -> void:
	var seller := int(current_auction["seller"])
	var cards: Array[Dictionary] = current_auction["cards"]

	var cash_before: Array[int] = [player_cash[0], player_cash[1]]

	if winner == -1:
		# 流拍：归卖家
		winner = seller
		price = 0

	price = max(price, 0)
	price = min(price, player_cash[winner]) # 兜底：不能付出超过现金（首版简化为封顶）

	if fixed_price_mode and winner == seller:
		# 卖家自购：现金减少（支付给银行）
		player_cash[seller] -= price
	else:
		# 常规：赢家付钱给卖家
		player_cash[winner] -= price
		if winner != seller:
			player_cash[seller] += price

	for c in cards:
		player_collections[winner].append(c)
		var a := int(c["artist"])
		sold_counts[a] = int(sold_counts.get(a, 0)) + 1
		discard.append(c)

	for p in range(2):
		var delta: int = player_cash[p] - cash_before[p]
		if delta != 0:
			emit_signal("money_changed", {"player": p, "delta": delta, "reason": "auction"})

	emit_signal("auction_resolved", {
		"seller": seller,
		"winner": winner,
		"price": price,
		"cards": cards,
		"notes": notes,
		"cash_before": cash_before,
		"cash_after": [player_cash[0], player_cash[1]]
	})

	emit_signal("toast", "拍卖结束：%s 以 %d 购得（%s）" % [player_names[winner], price, notes])

	current_auction = {}
	phase = Phase.WAIT_PLAY_CARD
	active_player = 1 - active_player

	if _is_round_end():
		_do_round_scoring()
	else:
		_emit_snapshot()

func _is_round_end() -> bool:
	for a in sold_counts.keys():
		if int(sold_counts[a]) >= 5:
			return true
	return false

func _do_round_scoring() -> void:
	phase = Phase.ROUND_SCORING
	var payouts: Array[int] = ScoringEngine.payout_for_round(round_index, sold_counts, player_collections)
	var cash_before: Array[int] = [player_cash[0], player_cash[1]]
	for p in range(2):
		player_cash[p] += payouts[p]

	for p in range(2):
		var delta: int = player_cash[p] - cash_before[p]
		if delta != 0:
			emit_signal("money_changed", {"player": p, "delta": delta, "reason": "round_score"})

	var result := {
		"round_index": round_index,
		"sold_counts": sold_counts.duplicate(),
		"payouts": payouts,
		"cash": player_cash.duplicate()
	}
	emit_signal("round_scored", result)
	emit_signal("toast", "第%d轮结算完成" % (round_index + 1))

	round_index += 1
	if round_index >= 4:
		_end_game()
	else:
		active_player = 0
		_start_round()

func _end_game() -> void:
	phase = Phase.GAME_ENDED
	var winner := 0
	if player_cash[1] > player_cash[0]:
		winner = 1
	var result := {
		"cash": player_cash.duplicate(),
		"winner": winner,
		"winner_name": player_names[winner],
	}
	emit_signal("game_ended", result)
	emit_signal("state_changed", snapshot())

func snapshot() -> Dictionary:
	return {
		"round_index": round_index,
		"active_player": active_player,
		"phase": phase,
		"cash": player_cash.duplicate(),
		"hand_sizes": [player_hands[0].size(), player_hands[1].size()],
		"hands": [player_hands[0].duplicate(true), player_hands[1].duplicate(true)],
		"collections": [player_collections[0].duplicate(true), player_collections[1].duplicate(true)],
		"sold_counts": sold_counts.duplicate(),
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
