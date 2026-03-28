extends RefCounted

const CardDefs := preload("res://scripts/core/CardDefs.gd")

var _cache: Dictionary = {} # card_id(int) -> Texture2D
var _artist_base: Dictionary = {} # artist(int) -> Texture2D (来自 assets/cards 的五张画作)

const _ART_FILES_BY_ARTIST := {
	CardDefs.Artist.CARVALHO: "res://assets/cards/八嘎呀路.png",
	CardDefs.Artist.MARTINS: "res://assets/cards/哈基米.png",
	CardDefs.Artist.MELIM: "res://assets/cards/巴巴博一.png",
	CardDefs.Artist.SILVEIRA: "res://assets/cards/比比拉布.png",
	CardDefs.Artist.THALER: "res://assets/cards/我的刀盾.png",
}

func _init() -> void:
	_load_artist_base_textures()

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
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(card_id, artist)

	var src_tex: Texture2D = null
	if _artist_base.has(artist):
		src_tex = _artist_base[artist]

	if src_tex == null:
		# 回退：纯色占位（理论上不会触发，只在缺图时用）
		var fallback := Image.create(w, h, false, Image.FORMAT_RGBA8)
		fallback.fill(Color(0.15, 0.15, 0.18, 1))
		return ImageTexture.create_from_image(fallback)

	var src_img: Image = src_tex.get_image()
	if src_img == null:
		var fb2 := Image.create(w, h, false, Image.FORMAT_RGBA8)
		fb2.fill(Color(0.15, 0.15, 0.18, 1))
		return ImageTexture.create_from_image(fb2)

	# 1) Cover裁剪到目标比例（3:4），并做一点点随机偏移，让同一画作不同卡有变化
	var target_ratio: float = float(w) / float(h) # 0.75
	var sw: int = src_img.get_width()
	var sh: int = src_img.get_height()

	var crop_w: int = sw
	var crop_h: int = sh
	if float(sw) / float(sh) > target_ratio:
		crop_h = sh
		crop_w = int(round(float(sh) * target_ratio))
	else:
		crop_w = sw
		crop_h = int(round(float(sw) / target_ratio))

	crop_w = clamp(crop_w, 1, sw)
	crop_h = clamp(crop_h, 1, sh)

	var max_dx: int = max(0, sw - crop_w)
	var max_dy: int = max(0, sh - crop_h)
	var ox: int = int(round(float(max_dx) * (0.35 + float(rng.randi_range(-10, 10)) / 100.0)))
	var oy: int = int(round(float(max_dy) * (0.35 + float(rng.randi_range(-10, 10)) / 100.0)))
	ox = clamp(ox, 0, max_dx)
	oy = clamp(oy, 0, max_dy)

	var cropped := src_img.get_region(Rect2i(ox, oy, crop_w, crop_h))

	# 2) 像素化：先缩到低分辨率，再用Nearest放大回目标尺寸
	var low_w: int = 48
	var low_h: int = 64
	cropped.resize(low_w, low_h, Image.INTERPOLATE_NEAREST)
	cropped.resize(w, h, Image.INTERPOLATE_NEAREST)

	# 3) 顶底加轻微遮罩，便于读标题
	_draw_rect(cropped, Rect2i(0, h - 26, w, 26), Color(0, 0, 0, 0.32), false)
	_draw_rect(cropped, Rect2i(0, 0, w, 18), Color(0, 0, 0, 0.18), false)

	return ImageTexture.create_from_image(cropped)

func _load_artist_base_textures() -> void:
	_artist_base.clear()
	for a in _ART_FILES_BY_ARTIST.keys():
		var p: String = String(_ART_FILES_BY_ARTIST[a])
		if ResourceLoader.exists(p):
			var t := load(p)
			if t is Texture2D:
				_artist_base[int(a)] = t

func _seed_for(card_id: int, artist: int) -> int:
	# 简单可重复的混合种子
	var a: int = (card_id * 1103515245) & 0x7fffffff
	var b: int = (artist * 2654435761) & 0x7fffffff
	return int((a ^ b) & 0x7fffffff)

func _artist_base_color(_artist: int) -> Color:
	return Color(0.15, 0.15, 0.18, 1)

func _random_accent(_rng: RandomNumberGenerator, _artist: int) -> Color:
	return Color(0.85, 0.85, 0.85, 1)

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

