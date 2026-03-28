extends Control

@onready var _menu: Control = $Root/Menu
@onready var _start_button: Button = $Root/Menu/Center/VBox/StartButton
@onready var _quit_button: Button = $Root/Menu/Center/VBox/QuitButton
@onready var _world_root: Node2D = $WorldRoot

var _table_scene: PackedScene

func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_table_scene = load("res://scenes/Table2D.tscn")
	_world_root.visible = false

func _on_start_pressed() -> void:
	_menu.visible = false
	_world_root.visible = true
	_clear_world_root()
	var inst := _table_scene.instantiate()
	_world_root.add_child(inst)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _clear_world_root() -> void:
	for c in _world_root.get_children():
		c.queue_free()
