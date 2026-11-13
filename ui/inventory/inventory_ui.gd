extends Control

const InventoryRowScene := preload("res://ui/inventory/InventoryRow.tscn")
const WorldItemScene := preload("res://features/world_items/world_item.tscn")

const DROP_DISTANCE := 1.5
const DROP_HEIGHT := 0.5
const DROP_PICKUP_GRACE := 0.5

@onready var items_list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ItemList
@onready var weight_bar: ProgressBar = $MarginContainer/VBoxContainer/HBoxContainer/WeightBar
@onready var weight_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/WeightLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/Header/Close

var is_open := false
var _inventory: Inventory
var _player: Node3D


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_inventory = _player.get_node("Inventory") as Inventory

	_inventory.weight_changed.connect(_refresh_weight)
	_inventory.inventory_changed.connect(_refresh_list)
	close_button.pressed.connect(close)
	
	_refresh_list()
	_refresh_weight(_inventory.get_total_weight(), _inventory.max_weight)

	close()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("inventory"):
		if is_open:
			close()
		else:
			open()
		return

	if is_open and Input.is_action_just_pressed("ui_cancel"):
		var dialog := get_node_or_null("DropAmountDialog")
		if dialog != null:
			dialog.queue_free()
		else:
			close()


func open() -> void:
	visible = true
	is_open = true


func close() -> void:
	var dialog := get_node_or_null("DropAmountDialog")
	if dialog != null:
		dialog.queue_free()
	visible = false
	is_open = false



func _refresh_list() -> void:
	for child in items_list.get_children():
		items_list.remove_child(child)
		child.queue_free()

	var stacks := _inventory.get_stacks()

	for stack in stacks:
		var row := InventoryRowScene.instantiate()
		items_list.add_child(row)
		row.setup(stack)
		row.drop_requested.connect(_on_drop_requested)


func _refresh_weight(current_weight: float, max_weight: float) -> void:
	weight_bar.max_value = max_weight
	weight_bar.value = current_weight
	weight_label.text = "%.1f / %.1f" % [current_weight, max_weight]


func _on_drop_requested(item_data: ItemData, amount: int) -> void:
	if item_data == null or amount <= 0:
		return

	if not _inventory.remove_item(item_data.id, amount):
		return

	_spawn_world_item(item_data, amount)


func _spawn_world_item(item_data: ItemData, amount: int) -> void:
	var world_item := WorldItemScene.instantiate()
	world_item.item_data = item_data
	world_item.amount = amount
	world_item.pickup_grace_sec = DROP_PICKUP_GRACE

	var parent := get_tree().current_scene
	parent.add_child(world_item)

	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()

	world_item.global_position = (
		_player.global_position
		+ forward * DROP_DISTANCE
		+ Vector3.UP * DROP_HEIGHT
	)
	
		
