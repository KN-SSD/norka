extends Control

signal drop_requested(item_data: ItemData, amount: int)

@onready var title_label: Label = %Title
@onready var amount_label: Label = %AmountLabel
@onready var slider: HSlider = %Slider
@onready var half_button: Button = %Half
@onready var full_button: Button = %Full
@onready var drop_button: Button = %Drop
@onready var cancel_button: Button = %Cancel

var _item_data: ItemData
var _max_amount: int = 1


func _ready() -> void:
	half_button.pressed.connect(_on_half_pressed)
	full_button.pressed.connect(_on_full_pressed)
	drop_button.pressed.connect(_on_drop_pressed)
	cancel_button.pressed.connect(close)
	slider.value_changed.connect(_on_slider_value_changed)


func setup(item_data: ItemData, max_amount: int) -> void:
	_item_data = item_data
	_max_amount = maxi(1, max_amount)

	title_label.text = "Wyrzuć: %s" % item_data.item_name

	slider.min_value = 1
	slider.max_value = _max_amount
	slider.step = 1
	slider.value = _max_amount

	_update_amount_label()


func close() -> void:
	queue_free()


func _on_half_pressed() -> void:
	slider.value = maxi(1, _max_amount / 2)


func _on_full_pressed() -> void:
	slider.value = _max_amount


func _on_slider_value_changed(_value: float) -> void:
	_update_amount_label()


func _update_amount_label() -> void:
	amount_label.text = "%d / %d" % [int(slider.value), _max_amount]


func _on_drop_pressed() -> void:
	if _item_data == null:
		return

	var amount := clampi(int(slider.value), 1, _max_amount)
	drop_requested.emit(_item_data, amount)
	close()
