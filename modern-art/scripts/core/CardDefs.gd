extends RefCounted

enum Artist {
	CARVALHO,
	MARTINS,
	MELIM,
	SILVEIRA,
	THALER
}

enum AuctionType {
	OPEN,
	ONCE_AROUND,
	FIXED_PRICE,
	SEALED,
	EXTRA # "=" 还需加一张同艺术家牌
}

static func artist_display_name(a: int) -> String:
	match a:
		# 使用你放入 assets/cards 的五张画作名（不再使用原桌游的五位艺术家名）
		Artist.CARVALHO: return "八嘎呀路"
		Artist.MARTINS: return "哈基米"
		Artist.MELIM: return "巴巴博一"
		Artist.SILVEIRA: return "比比拉布"
		Artist.THALER: return "我的刀盾"
		_: return "未知"

static func auction_display_name(t: int) -> String:
	match t:
		AuctionType.OPEN: return "公开竞价"
		AuctionType.ONCE_AROUND: return "一轮报价"
		AuctionType.FIXED_PRICE: return "定价出售"
		AuctionType.SEALED: return "密封竞价"
		AuctionType.EXTRA: return "加牌（=）"
		_: return "未知"

# Card represented as Dictionary:
# {
#   "id": int,
#   "artist": Artist,
#   "auction": AuctionType,
#   "title": String
# }
static func make_card(id: int, artist: int, auction: int, title: String) -> Dictionary:
	return {
		"id": id,
		"artist": artist,
		"auction": auction,
		"title": title
	}

# 近似原作的数量（70张，5位艺术家）。拍卖类型分布做均衡近似：每位艺术家按比例混入5种拍卖。
# 目的：首版“可玩+规则完整”，而非复刻每张牌的具体符号分布。
static func build_standard_deck() -> Array[Dictionary]:
	# 原版：5位艺术家牌数为 12/13/14/15/16（用于平衡同分优先级）。
	var per_artist_counts := {
		Artist.CARVALHO: 12,
		Artist.MARTINS: 13,
		Artist.MELIM: 14,
		Artist.SILVEIRA: 15,
		Artist.THALER: 16,
	}

	var deck: Array[Dictionary] = []
	var next_id := 1
	for artist in per_artist_counts.keys():
		var n: int = per_artist_counts[artist]
		for i in range(n):
			# 近似分配符号：每位艺术家插入少量“加牌(=)”，其余在4种拍卖里轮转。
			var auction: int
			if i == 0 or i == 7:
				auction = AuctionType.EXTRA
			else:
				var cycle := [AuctionType.OPEN, AuctionType.ONCE_AROUND, AuctionType.SEALED, AuctionType.FIXED_PRICE]
				auction = int(cycle[i % cycle.size()])
			var title := "%s·作品%02d" % [artist_display_name(artist), i + 1]
			deck.append(make_card(next_id, artist, auction, title))
			next_id += 1
	return deck
