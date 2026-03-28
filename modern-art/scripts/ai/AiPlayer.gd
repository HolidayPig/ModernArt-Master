extends RefCounted

const CardDefs := preload("res://scripts/core/CardDefs.gd")

var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func choose_card_index(hand: Array, snapshot: Dictionary) -> int:
	# 基础策略（3-5人通用）：优先打出非“加牌(=)”，其次倾向于桌面数量较少的艺术家
	var table_counts: Array = snapshot.get("table_counts", [0, 0, 0, 0, 0])
	var best_i: int = 0
	var best_score: int = -999999
	for i in range(hand.size()):
		var c: Dictionary = hand[i]
		var t: int = int(c.get("auction", 0))
		var a: int = int(c.get("artist", 0))
		var score: int = 0
		if t == CardDefs.AuctionType.EXTRA:
			score -= 50
		score += (10 - int(table_counts[a])) * 3
		score += _rng.randi_range(0, 2)
		if score > best_score:
			best_score = score
			best_i = i
	return best_i

func decide_open_bid(info: Dictionary, highest_bid: int) -> int:
	var p: int = int(info.get("player", -1))
	var cash_arr: Array = info.get("cash", [])
	var my_cash: int = int(cash_arr[p])
	var cards: Array = info.get("cards", [])
	var v: int = _estimate_bundle_value(info, cards)
	var min_bid: int = highest_bid + 1000
	if my_cash < min_bid:
		return 0
	if v < min_bid:
		return 0
	var target: int = min(my_cash, v - 1000)
	target = int(floor(float(target) / 1000.0) * 1000.0)
	if target < min_bid:
		target = min_bid
	return target

func decide_once_bid(info: Dictionary) -> int:
	var p: int = int(info.get("player", -1))
	var cash_arr: Array = info.get("cash", [])
	var my_cash: int = int(cash_arr[p])
	var cards: Array = info.get("cards", [])
	var v: int = _estimate_bundle_value(info, cards)
	var bid: int = min(my_cash, v - 2000)
	bid = int(floor(float(bid) / 1000.0) * 1000.0)
	return max(bid, 0)

func decide_sealed_bid(info: Dictionary) -> int:
	var p: int = int(info.get("player", -1))
	var cash_arr: Array = info.get("cash", [])
	var my_cash: int = int(cash_arr[p])
	var cards: Array = info.get("cards", [])
	var v: int = _estimate_bundle_value(info, cards)
	var bid: int = min(my_cash, v - int(_rng.randi_range(1000, 6000)))
	bid = int(floor(float(bid) / 1000.0) * 1000.0)
	return max(bid, 0)

func decide_fixed_price(info: Dictionary) -> int:
	var p: int = int(info.get("player", -1))
	var cash_arr: Array = info.get("cash", [])
	var my_cash: int = int(cash_arr[p])
	var cards: Array = info.get("cards", [])
	var v: int = _estimate_bundle_value(info, cards)
	var price: int = min(my_cash, v - 3000)
	price = int(floor(float(price) / 1000.0) * 1000.0)
	return max(price, 0)

func decide_fixed_accept(price: int, info: Dictionary) -> bool:
	var p: int = int(info.get("player", -1))
	var cash_arr: Array = info.get("cash", [])
	var my_cash: int = int(cash_arr[p])
	if price > my_cash:
		return false
	var cards: Array = info.get("cards", [])
	var v: int = _estimate_bundle_value(info, cards)
	return price <= v

func decide_extra_follow(artist: int, candidates: Array[int], snap: Dictionary) -> int:
	# 返回 candidates 内的下标；-1表示不补牌
	var artist_values: Array = snap.get("artist_values", [0, 0, 0, 0, 0])
	var v: int = int(artist_values[artist])
	if candidates.is_empty():
		return -1
	if v >= 20000:
		return 0
	return -1 if _rng.randi_range(0, 99) < 70 else 0

func _estimate_bundle_value(info: Dictionary, cards: Array) -> int:
	var artist_values: Array = info.get("artist_values", [0, 0, 0, 0, 0])
	var table_counts: Array = info.get("table_counts", [0, 0, 0, 0, 0])
	var value: int = 0
	for c in cards:
		var a: int = int(c.get("artist", 0))
		var base: int = int(artist_values[a])
		# 简单热点加成：桌面越多越可能进入前三
		var hot: int = int(table_counts[a]) * 2000
		value += base + 15000 + hot
	return value
