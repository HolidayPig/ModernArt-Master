extends RefCounted

const ROUND_RANK_VALUES := [
	[30, 20, 10], # 第1轮：第1/2/3名每张价值
	[40, 30, 20],
	[50, 40, 30],
	[60, 50, 40], # 第4轮
]

static func compute_round_rankings(sold_counts: Dictionary) -> Array[int]:
	# sold_counts: { artist:int -> count:int } (本轮售出数量)
	var artists_any: Array = sold_counts.keys()
	var artists: Array[int] = []
	artists.resize(artists_any.size())
	for i in range(artists_any.size()):
		artists[i] = int(artists_any[i])

	artists.sort_custom(func(a: int, b: int):
		var ca: int = int(sold_counts.get(a, 0))
		var cb: int = int(sold_counts.get(b, 0))
		if ca == cb:
			return a < b
		return ca > cb
	)
	return artists

static func payout_for_round(round_index: int, sold_counts: Dictionary, player_collections: Array[Array]) -> Array[int]:
	# 返回每位玩家本轮应得收入（非净利润），按其收藏中各艺术家张数 * 该艺术家本轮排名价值
	var rank_values: Array = ROUND_RANK_VALUES[clamp(round_index, 0, ROUND_RANK_VALUES.size() - 1)]
	var ranking := compute_round_rankings(sold_counts)

	var value_by_artist := {}
	for i in range(ranking.size()):
		var artist := ranking[i]
		if i < 3:
			value_by_artist[artist] = rank_values[i]
		else:
			value_by_artist[artist] = 0

	var payouts: Array[int] = []
	for p in range(player_collections.size()):
		var income := 0
		for c in player_collections[p]:
			var a := int(c["artist"])
			income += int(value_by_artist.get(a, 0))
		payouts.append(income)
	return payouts
