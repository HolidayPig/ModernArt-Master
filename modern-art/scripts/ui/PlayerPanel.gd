extends PanelContainer

@onready var name_label: Label = $Margin/VBox/NameRow/NameLabel
@onready var status_label: Label = $Margin/VBox/NameRow/StatusLabel
@onready var cash_label: Label = $Margin/VBox/CashLabel
@onready var hand_label: Label = $Margin/VBox/HandLabel

var player_id: int = -1
var player_name: String = ""

func set_player(p: int, name: String) -> void:
	player_id = p
	player_name = name
	name_label.text = name

func update_from_snapshot(cash: int, hand_size: int, is_active: bool) -> void:
	cash_label.text = "现金：%d" % cash
	hand_label.text = "手牌：%d" % hand_size
	status_label.text = "行动中" if is_active else ""
	status_label.visible = is_active

