extends RefCounted

const CardDefs := preload("res://scripts/core/CardDefs.gd")

class AuctionResult:
	var winner_player: int = -1
	var price: int = 0
	var cards_awarded: Array[Dictionary] = []
	var notes: String = ""

static func resolve_open(bids: Array, seller: int) -> AuctionResult:
	# bids: [{ "player":int, "amount":int, "is_pass":bool }]
	# 规则：卖家不得出价；最高价得标；若全员放弃（无人出价），流拍 -> 归卖家，价格0
	var res := AuctionResult.new()
	var best_p := -1
	var best_amt := -1
	for b in bids:
		var p := int(b["player"])
		if p == seller:
			continue
		if bool(b.get("is_pass", false)):
			continue
		var amt := int(b.get("amount", 0))
		if amt > best_amt:
			best_amt = amt
			best_p = p
	res.winner_player = best_p
	res.price = max(best_amt, 0)
	if best_p == -1:
		res.price = 0
		res.notes = "流拍"
	return res

static func resolve_once_around(offered: Array, seller: int) -> AuctionResult:
	# offered: 按顺序（卖家之后）的一次性报价/放弃
	var res := AuctionResult.new()
	var best_p := -1
	var best_amt := -1
	for b in offered:
		var p := int(b["player"])
		if p == seller:
			continue
		if bool(b.get("is_pass", false)):
			continue
		var amt := int(b.get("amount", 0))
		if amt > best_amt:
			best_amt = amt
			best_p = p
	res.winner_player = best_p
	res.price = max(best_amt, 0)
	if best_p == -1:
		res.price = 0
		res.notes = "无人报价，流拍"
	return res

static func resolve_fixed_price(price: int, buyer_accepts_in_order: Array, seller: int) -> AuctionResult:
	# buyer_accepts_in_order: [{ "player":int, "accept":bool }]
	# 规则：按顺序，第一个接受者买下并支付price；若无人接受，则卖家自己以price买下（支付给银行/消耗现金）
	var res := AuctionResult.new()
	res.price = max(price, 0)
	for a in buyer_accepts_in_order:
		var p := int(a["player"])
		if p == seller:
			continue
		if bool(a.get("accept", false)):
			res.winner_player = p
			res.notes = "有人接受定价"
			return res
	res.winner_player = seller
	res.notes = "无人接受，卖家自购"
	return res

static func resolve_sealed(sealed_bids: Array, seller: int) -> AuctionResult:
	# sealed_bids: [{ "player":int, "amount":int }] (卖家不参与)
	# 规则：最高密封价得标并支付；若全为0，仍可视为0成交（首版简化），等价“流拍但给最高者”。
	var res := AuctionResult.new()
	var best_p := -1
	var best_amt := -1
	for b in sealed_bids:
		var p := int(b["player"])
		if p == seller:
			continue
		var amt := int(b.get("amount", 0))
		if amt > best_amt:
			best_amt = amt
			best_p = p
	res.winner_player = best_p
	res.price = max(best_amt, 0)
	if best_p == -1:
		res.winner_player = -1
		res.price = 0
		res.notes = "无人参与"
	return res

static func resolve_double(bids: Array, seller: int) -> AuctionResult:
	# 双重拍卖：一口价竞拍两张牌打包（首版实现：一张出牌+一张附加牌）
	return resolve_open(bids, seller)

