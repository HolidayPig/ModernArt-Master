extends RefCounted

const CardDefs := preload("res://scripts/core/CardDefs.gd")

var _cache: Dictionary = {} # card_id(int) -> Texture2D

func get_face_texture(card: Dictionary) -> Texture2D:
	var card_id: int = int(card.get("id", -1))
	if _cache.has(card_id):
		return _cache[card_id]
	var artist: int = int(card.get("artist", 0))
	var tex := _generate(card_id, artist)
	_cache[card_id] = tex
	return tex

func _generate(card_id: int, artist: int) -> Texture2D:
	var w: int = 96
	var h: int = 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(card_id, artist)

	var base := _artist_base_color(artist)
	img.fill(base)

	# 轻微噪点底纹
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var n: float = float(rng.randi_range(-12, 12)) / 255.0
			var c := Color(
				clamp(base.r + n, 0.0, 1.0),
				clamp(base.g + n, 0.0, 1.0),
				clamp(base.b + n, 0.0, 1.0),
				1.0
			)
			_plot2x2(img, x, y, c)

	# 抽象块
	var blocks: int = rng.randi_range(6, 11)
	for i in range(blocks):
		var rw: int = rng.randi_range(10, 36)
		var rh: int = rng.randi_range(10, 36)
		var rx: int = rng.randi_range(4, w - rw - 4)
		var ry: int = rng.randi_range(4, h - rh - 4)
		var col := _random_accent(rng, artist)
		_draw_rect(img, Rect2i(rx, ry, rw, rh), col, rng.randi_range(0, 1) == 1)

	# 笔触线条
	var strokes: int = rng.randi_range(8, 14)
	for i in range(strokes):
		var x0: int = rng.randi_range(0, w - 1)
		var y0: int = rng.randi_range(0, h - 1)
		var x1: int = rng.randi_range(0, w - 1)
		var y1: int = rng.randi_range(0, h - 1)
		var thick: int = rng.randi_range(1, 3)
		var col2 := _random_accent(rng, artist)
		_draw_line_thick(img, x0, y0, x1, y1, thick, col2)

	# 亮色圆点
	var dots: int = rng.randi_range(10, 22)
	for i in range(dots):
		var dx: int = rng.randi_range(6, w - 7)
		var dy: int = rng.randi_range(10, h - 10)
		var rad: int = rng.randi_range(1, 3)
		_draw_circle(img, dx, dy, rad, _random_accent(rng, artist))

	# 留出底部文字区（深色遮罩，便于读）
	_draw_rect(img, Rect2i(0, h - 26, w, 26), Color(0, 0, 0, 0.35), false)
	_draw_rect(img, Rect2i(0, 0, w, 18), Color(0, 0, 0, 0.25), false)

	return ImageTexture.create_from_image(img)

func _seed_for(card_id: int, artist: int) -> int:
	# 简单可重复的混合种子
	var a: int = (card_id * 1103515245) & 0x7fffffff
	var b: int = (artist * 2654435761) & 0x7fffffff
	return int((a ^ b) & 0x7fffffff)

func _artist_base_color(artist: int) -> Color:
	match artist:
		CardDefs.Artist.CARVALHO: return Color(0.16, 0.16, 0.22, 1)
		CardDefs.Artist.MARTINS: return Color(0.15, 0.20, 0.16, 1)
		CardDefs.Artist.MELIM: return Color(0.20, 0.16, 0.16, 1)
		CardDefs.Artist.SILVEIRA: return Color(0.17, 0.18, 0.14, 1)
		CardDefs.Artist.THALER: return Color(0.14, 0.18, 0.22, 1)
		_: return Color(0.16, 0.16, 0.20, 1)

func _random_accent(rng: RandomNumberGenerator, artist: int) -> Color:
	# 每位艺术家一组偏好色系
	var palette: Array = []
	match artist:
		CardDefs.Artist.CARVALHO:
			palette = [Color(0.95, 0.55, 0.25), Color(0.85, 0.85, 0.95), Color(0.35, 0.75, 0.90)]
		CardDefs.Artist.MARTINS:
			palette = [Color(0.35, 0.95, 0.65), Color(0.85, 0.95, 0.35), Color(0.20, 0.65, 0.40)]
		CardDefs.Artist.MELIM:
			palette = [Color(0.95, 0.35, 0.45), Color(0.95, 0.80, 0.30), Color(0.60, 0.25, 0.35)]
		CardDefs.Artist.SILVEIRA:
			palette = [Color(0.95, 0.95, 0.35), Color(0.45, 0.85, 0.95), Color(0.75, 0.55, 0.25)]
		CardDefs.Artist.THALER:
			palette = [Color(0.55, 0.55, 0.98), Color(0.90, 0.40, 0.90), Color(0.35, 0.85, 0.95)]
		_:
			palette = [Color(0.9, 0.9, 0.9), Color(0.3, 0.8, 0.9)]
	return palette[rng.randi_range(0, palette.size() - 1)]

func _plot2x2(img: Image, x: int, y: int, col: Color) -> void:
	_safe_set(img, x, y, col)
	_safe_set(img, x + 1, y, col)
	_safe_set(img, x, y + 1, col)
	_safe_set(img, x + 1, y + 1, col)

func _safe_set(img: Image, x: int, y: int, col: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, col)

func _draw_rect(img: Image, r: Rect2i, col: Color, outline: bool) -> void:
	if outline:
		for x in range(r.position.x, r.position.x + r.size.x):
			_safe_set(img, x, r.position.y, col)
			_safe_set(img, x, r.position.y + r.size.y - 1, col)
		for y in range(r.position.y, r.position.y + r.size.y):
			_safe_set(img, r.position.x, y, col)
			_safe_set(img, r.position.x + r.size.x - 1, y, col)
	else:
		for y in range(r.position.y, r.position.y + r.size.y):
			for x in range(r.position.x, r.position.x + r.size.x):
				_safe_set(img, x, y, col)

func _draw_line_thick(img: Image, x0: int, y0: int, x1: int, y1: int, thick: int, col: Color) -> void:
	var dx: int = abs(x1 - x0)
	var sx: int = 1 if x0 < x1 else -1
	var dy: int = -abs(y1 - y0)
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	var x: int = x0
	var y: int = y0
	while true:
		for oy in range(-thick, thick + 1):
			for ox in range(-thick, thick + 1):
				_safe_set(img, x + ox, y + oy, col)
		if x == x1 and y == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy

func _draw_circle(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				_safe_set(img, cx + x, cy + y, col)

