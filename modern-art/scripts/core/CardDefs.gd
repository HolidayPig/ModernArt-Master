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
	DOUBLE
}

static func artist_display_name(a: int) -> String:
	match a:
		Artist.CARVALHO: return "卡瓦略"
		Artist.MARTINS: return "马丁斯"
		Artist.MELIM: return "梅利姆"
		Artist.SILVEIRA: return "西尔维拉"
		Artist.THALER: return "塔勒"
		_: return "未知"

static func auction_display_name(t: int) -> String:
	match t:
		AuctionType.OPEN: return "公开竞价"
		AuctionType.ONCE_AROUND: return "一轮报价"
		AuctionType.FIXED_PRICE: return "定价出售"
		AuctionType.SEALED: return "密封竞价"
		AuctionType.DOUBLE: return "双重拍卖"
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
	var per_artist_counts := {
		Artist.CARVALHO: 12,
		Artist.MARTINS: 15,
		Artist.MELIM: 15,
		Artist.SILVEIRA: 15,
		Artist.THALER: 13,
	}
	var auctions := [
		AuctionType.OPEN,
		AuctionType.ONCE_AROUND,
		AuctionType.FIXED_PRICE,
		AuctionType.SEALED,
		AuctionType.DOUBLE
	]

	var deck: Array[Dictionary] = []
	var next_id := 1
	for artist in per_artist_counts.keys():
		var n: int = per_artist_counts[artist]
		for i in range(n):
			var auction: int = int(auctions[i % auctions.size()])
			var title := "%s·作品%02d" % [artist_display_name(artist), i + 1]
			deck.append(make_card(next_id, artist, auction, title))
			next_id += 1
	return deck
