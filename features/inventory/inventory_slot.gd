class_name InventoryStack
extends RefCounted

var item_data: ItemData
var amount: int = 1


func _init(
	data: ItemData = null,
	quantity: int = 1
) -> void:
	item_data = data
	amount = quantity


func get_total_weight() -> float:
	if item_data == null:
		return 0.0

	return item_data.weight * amount
