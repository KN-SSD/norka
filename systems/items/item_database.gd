extends Node

var _items: Dictionary = {}

func _ready() -> void:
	_load_items()


func _load_items() -> void:
	var catalog: ItemCatalog = preload(
        "res://systems/items/item_catalog.tres"
	)

	for item in catalog.items:
		if item == null:
			continue

		if _items.has(item.id):
			push_warning("Duplicate item ID: %s" % item.id)
			continue

		_items[item.id] = item


func get_item(item_id: StringName) -> ItemData:
	return _items.get(item_id) as ItemData


func has_item(item_id: StringName) -> bool:
	return _items.has(item_id)


func get_all_items() -> Array:
	return _items.values()
