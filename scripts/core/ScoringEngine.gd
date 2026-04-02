extends RefCounted

const MARKERS: Array[int] = [30000, 20000, 10000]

static func rank_artists_by_counts(counts: Array[int]) -> Array[int]:
	# counts: length=5, ties broken by artist precedence (lower index wins)
	var artists: Array[int] = [0, 1, 2, 3, 4]
	artists.sort_custom(func(a: int, b: int) -> bool:
		var ca: int = counts[a]
		var cb: int = counts[b]
		if ca == cb:
			return a < b
		return ca > cb
	)
	return artists

static func apply_round_markers(artist_values: Array[int], counts: Array[int]) -> void:
	var ranking: Array[int] = rank_artists_by_counts(counts)
	for i in range(3):
		var a: int = ranking[i]
		artist_values[a] += MARKERS[i]

static func current_round_values(artist_values: Array[int], counts: Array[int]) -> Array[int]:
	var round_values: Array[int] = [0, 0, 0, 0, 0]
	var ranking: Array[int] = rank_artists_by_counts(counts)
	for i in range(3):
		var a: int = ranking[i]
		round_values[a] = artist_values[a]
	return round_values

static func payout_for_sold_cards(round_values: Array[int], sold_cards_by_player: Array[Array]) -> Array[int]:
	var payouts: Array[int] = []
	payouts.resize(sold_cards_by_player.size())
	for p in range(sold_cards_by_player.size()):
		var income: int = 0
		for c in sold_cards_by_player[p]:
			var a: int = int(c["artist"])
			income += round_values[a]
		payouts[p] = income
	return payouts
