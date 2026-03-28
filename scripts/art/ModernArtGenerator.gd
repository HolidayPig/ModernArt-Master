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
	var w: int = 144
	var h: int = 256
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
	# 不同源图可能是 RGB/RGBA；blit_rect 需要格式一致，否则会出现“只有部分图能显示”
	if src_img.get_format() != Image.FORMAT_RGBA8:
		src_img.convert(Image.FORMAT_RGBA8)

	# 1) 按 9:16 画布“完整显示原图”（不裁切）：contain 缩放 + 居中
	var sw: int = src_img.get_width()
	var sh: int = src_img.get_height()
	var scale: float = min(float(w) / float(max(1, sw)), float(h) / float(max(1, sh)))
	var nw: int = max(1, int(round(float(sw) * scale)))
	var nh: int = max(1, int(round(float(sh) * scale)))

	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.06, 0.07, 0.09, 1))

	var scaled: Image = src_img.duplicate()
	if scaled.get_format() != Image.FORMAT_RGBA8:
		scaled.convert(Image.FORMAT_RGBA8)
	scaled.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	var dx: int = int((w - nw) * 0.5)
	var dy: int = int((h - nh) * 0.5)
	out.blit_rect(scaled, Rect2i(0, 0, nw, nh), Vector2i(dx, dy))

	# 2) 顶底加轻微遮罩，便于读标题
	_draw_rect(out, Rect2i(0, h - 30, w, 30), Color(0, 0, 0, 0.26), false)
	_draw_rect(out, Rect2i(0, 0, w, 22), Color(0, 0, 0, 0.18), false)

	return ImageTexture.create_from_image(out)

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

