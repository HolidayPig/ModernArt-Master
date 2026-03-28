extends Node

const GameState := preload("res://scripts/core/GameState.gd")

@export var player_counts: Array[int] = [3, 4, 5]
@export var seeds: Array[int] = [1, 2, 3]
@export var max_steps: int = 20000

var _gs: Node = null
var _pc_i: int = 0
var _seed_i: int = 0
var _steps: int = 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_run_next()

func _run_next() -> void:
	if _gs != null and is_instance_valid(_gs):
		_gs.queue_free()
		_gs = null

	if _pc_i >= player_counts.size():
		print("[PlaythroughRunner] all done")
		get_tree().quit()
		return

	var pc: int = int(player_counts[_pc_i])
	var seed: int = int(seeds[_seed_i])
	_steps = 0

	_gs = GameState.new()
	add_child(_gs)

	_gs.auction_input_requested.connect(_on_input_requested)
	_gs.game_ended.connect(_on_game_ended)

	_gs.new_game(pc, seed)
	print("[PlaythroughRunner] start pc=%d seed=%d" % [pc, seed])

func _process(_delta: float) -> void:
	if _gs == null or not is_instance_valid(_gs):
		return
	_steps += 1
	if _steps > max_steps:
		push_error("[PlaythroughRunner] exceeded max_steps (pc=%d seed=%d)" % [int(player_counts[_pc_i]), int(seeds[_seed_i])])
		get_tree().quit()
		return

	var s: Dictionary = _gs.snapshot()
	var phase: int = int(s.get("phase", 0))
	var ap: int = int(s.get("active_player", 0))
	if phase == GameState.Phase.WAIT_PLAY_CARD and ap == 0:
		var hand: Array = s.get("hand", [])
		if hand.is_empty():
			return
		var idx: int = _rng.randi_range(0, hand.size() - 1)
		_gs.play_card(0, idx)

func _on_input_requested(info: Dictionary) -> void:
	# 用极简策略自动回应（用于回归跑通，不代表强AI）
	var action: int = int(info.get("action", -1))
	match action:
		GameState.HumanAction.OPEN_BID_OR_PASS:
			var highest: int = int(info.get("highest_bid", 0))
			var cash: Array = info.get("cash", [])
			var my_cash: int = int(cash[0]) if cash.size() > 0 else 0
			var bid: int = highest + 1000
			if bid > my_cash:
				_gs.human_pass()
			else:
				_gs.human_submit_amount(bid)
		GameState.HumanAction.ONCE_BID_OR_PASS:
			var cash2: Array = info.get("cash", [])
			var my_cash2: int = int(cash2[0]) if cash2.size() > 0 else 0
			var bid2: int = min(10000, my_cash2)
			if bid2 <= 0:
				_gs.human_pass()
			else:
				_gs.human_submit_amount(bid2)
		GameState.HumanAction.SEALED_BID:
			_gs.human_submit_amount(0)
		GameState.HumanAction.FIXED_SET_PRICE:
			var cash3: Array = info.get("cash", [])
			var my_cash3: int = int(cash3[0]) if cash3.size() > 0 else 0
			_gs.human_submit_amount(min(10000, my_cash3))
		GameState.HumanAction.FIXED_ACCEPT_OR_DECLINE:
			_gs.human_fixed_decision(false)
		GameState.HumanAction.EXTRA_CHOOSE_CARD:
			var candidates: Array = info.get("candidates", [])
			if candidates.is_empty():
				_gs.human_pass()
			else:
				# 50%补牌，50%不补
				if _rng.randi_range(0, 99) < 50:
					_gs.human_extra_choose_card(int(candidates[0]))
				else:
					_gs.human_pass()
		_:
			_gs.human_pass()

func _on_game_ended(r: Dictionary) -> void:
	print("[PlaythroughRunner] end pc=%d seed=%d winner=%s cash=%s steps=%d" % [
		int(player_counts[_pc_i]),
		int(seeds[_seed_i]),
		String(r.get("winner_name", "?")),
		str(r.get("cash", [])),
		_steps
	])
	_seed_i += 1
	if _seed_i >= seeds.size():
		_seed_i = 0
		_pc_i += 1
	call_deferred("_run_next")

