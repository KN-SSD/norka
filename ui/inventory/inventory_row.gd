extends HBoxContainer

signal drop_requested(item_data: ItemData, amount: int)

const DropAmountDialogScene := preload("res://ui/inventory/DropAmountDialog.tscn")

@onready var icon: TextureRect = $Icon
@onready var name_label: Label = $Name
@onready var amount_label: Label = $Amount
@onready var weight_label: Label = $Weight
@onready var drop_button: Button = $Drop

var _stack: InventoryStack


func _ready() -> void:
	drop_button.pressed.connect(_on_drop_pressed)


func setup(stack: InventoryStack) -> void:
	if stack == null or stack.item_data == null:
		return

	_stack = stack
	var data: ItemData = stack.item_data

	icon.texture = data.icon
	name_label.text = data.item_name
	amount_label.text = "x%d" % stack.amount
	weight_label.text = "%.1f" % stack.get_total_weight()


func _on_drop_pressed() -> void:
	if _stack == null or _stack.item_data == null:
		return

	if _stack.amount <= 1:
		drop_requested.emit(_stack.item_data, 1)
		return

	_open_drop_dialog()


func _open_drop_dialog() -> void:
	var panel := _find_inventory_panel()
	if panel == null:
		push_warning("InventoryRow: nie znaleziono InventoryPanel.")
		return

	var existing := panel.get_node_or_null("DropAmountDialog")
	if existing != null:
		existing.queue_free()

	var dialog := DropAmountDialogScene.instantiate()
	dialog.name = "DropAmountDialog"
	panel.add_child(dialog)
	dialog.setup(_stack.item_data, _stack.amount)
	dialog.drop_requested.connect(
		func(item_data: ItemData, amount: int) -> void:
			drop_requested.emit(item_data, amount)
	)


func _find_inventory_panel() -> Node:
	var node: Node = self
	while node != null:
		if node.name == "InventoryPanel":
			return node
		node = node.get_parent()
	return null
