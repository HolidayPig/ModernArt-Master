extends RefCounted

const CardDefs := preload("res://scripts/core/CardDefs.gd")

var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func choose_card_index(hand: Array, snapshot: Dictionary) -> int:
	# 基础策略：优先打出“双重拍卖”，其次打出当前本轮售出较少的艺术家（制造稀缺），否则随便
	var sold: Dictionary = snapshot.get("sold_counts", {})
	var best_i: int = 0
	var best_score: int = -999999
	for i in range(hand.size()):
		var c: Dictionary = hand[i]
		var t := int(c["auction"])
		var a := int(c["artist"])
		var score: int = 0
		if t == CardDefs.AuctionType.DOUBLE:
			score += 100
		score += (10 - int(sold.get(a, 0))) * 3
		score += _rng.randi_range(0, 2)
		if score > best_score:
			best_score = score
			best_i = i
	return best_i

func _estimate_card_value(prompt: Dictionary, artist: int) -> int:
	# 非精确估值：依据本轮售出数量排序倾向 + 轮次加成
	var round_index: int = int(prompt.get("round_index", 0))
	var sold: Dictionary = prompt.get("sold_counts", {})
	var count: int = int(sold.get(artist, 0))
	var base: int = 18 + round_index * 8
	# 越“热门”（售出多）越可能进前三，AI愿意更高出价
	return base + count * 6

func make_open_bids(prompt: Dictionary) -> Array:
	# 在2人局，卖家与买家一对一：AI决定“加价”或“放弃”
	var seller: int = int(prompt["seller"])
	var cash: Array = prompt.get("cash", [100, 100])
	var my_cash: int = int(cash[1])
	if seller != 0:
		# AI为卖家时不会参与出价（引擎会忽略）
		return [{"player": 0, "amount": 0, "is_pass": true}]

	var cards: Array = prompt["cards"]
	var v: int = 0
	for c in cards:
		v += _estimate_card_value(prompt, int(c["artist"]))

	var bid: int = int(min(my_cash, v))
	if bid <= 0:
		return [{"player": 1, "amount": 0, "is_pass": true}]

	# 少量随机让AI不那么“机械”
	var jitter: int = _rng.randi_range(-5, 5)
	bid = clamp(bid + jitter, 0, my_cash)
	if bid < 6:
		return [{"player": 1, "amount": 0, "is_pass": true}]
	return [{"player": 1, "amount": bid, "is_pass": false}]

func make_once_around(prompt: Dictionary) -> Array:
	# 只给一次报价或放弃
	var seller: int = int(prompt["seller"])
	var cash: Array = prompt.get("cash", [100, 100])
	var my_cash: int = int(cash[1])
	if seller != 0:
		return [{"player": 0, "amount": 0, "is_pass": true}]

	var cards: Array = prompt["cards"]
	var v: int = 0
	for c in cards:
		v += _estimate_card_value(prompt, int(c["artist"]))

	var offer: int = int(clamp(v - 5, 0, my_cash))
	if offer < 5:
		return [{"player": 1, "amount": 0, "is_pass": true}]
	return [{"player": 1, "amount": offer, "is_pass": false}]

func choose_fixed_price(prompt: Dictionary) -> int:
	# AI作为卖家设定价格：略低于估值以提高成交概率
	var cards: Array = prompt["cards"]
	var v: int = 0
	for c in cards:
		v += _estimate_card_value(prompt, int(c["artist"]))
	return max(0, v - 8)

func respond_fixed_price(price: int, prompt: Dictionary) -> Array:
	# 返回按顺序的accept列表（2人局只有买家自己）
	var seller: int = int(prompt["seller"])
	var cash: Array = prompt.get("cash", [100, 100])
	var my_cash: int = int(cash[1])
	if seller != 0:
		# AI不是买家时，这个函数可能不被调用；给个兜底
		return [{"player": 0, "accept": false}]

	var cards: Array = prompt["cards"]
	var v: int = 0
	for c in cards:
		v += _estimate_card_value(prompt, int(c["artist"]))
	var accept: bool = price <= int(min(my_cash, v))
	return [{"player": 1, "accept": accept}]

func make_sealed_bid(prompt: Dictionary) -> Array:
	var seller: int = int(prompt["seller"])
	var cash: Array = prompt.get("cash", [100, 100])
	var my_cash: int = int(cash[1])
	if seller != 0:
		return [{"player": 0, "amount": 0}]

	var cards: Array = prompt["cards"]
	var v: int = 0
	for c in cards:
		v += _estimate_card_value(prompt, int(c["artist"]))
	var bid: int = int(clamp(v - 3, 0, my_cash))
	return [{"player": 1, "amount": bid}]
