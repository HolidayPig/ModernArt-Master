extends RefCounted

static func load_font_or_null() -> Font:
	var p := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
	if ResourceLoader.exists(p):
		return load(p)
	return null

static func load_texture_or_placeholder(path: String, size: Vector2i, color: Color) -> Texture2D:
	if ResourceLoader.exists(path):
		var t := load(path)
		if t is Texture2D:
			return t
	return _make_placeholder(size, color)

static func _make_placeholder(size: Vector2i, color: Color) -> Texture2D:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(color)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

