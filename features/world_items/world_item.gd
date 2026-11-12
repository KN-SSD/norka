extends Area3D

@export var item_data: ItemData
@export_range(1, 9999) var amount: int = 1

var collected := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if collected:
		return

	if not body.is_in_group("player"):
		return
	print("a")
	var inventory = body.get_node_or_null("Inventory")

	if inventory == null:
		push_warning("Player does not have an Inventory node!")
		return

	if item_data == null:
		push_warning("WorldItem has no ItemData assigned!")
		return

	collected = true

	inventory.add_item(item_data, amount)

	queue_free()
