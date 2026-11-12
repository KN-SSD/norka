
class_name Inventory
extends Node

signal inventory_changed
signal weight_changed(current_weight: float, max_weight: float)

signal encumbrance_changed(multiplier: float, is_overweight: bool)

@export_group("Configuration")

@export_range(0.1, 100000.0, 0.1)
var max_weight: float = 50.0

@export_range(0.1, 1.0, 0.05)
var minimum_speed_multiplier: float = 0.5

@export var item_database: ItemDatabase

var _stacks: Array[InventoryStack] = []


# --------------------------------------------------
# GETTERS
# --------------------------------------------------

func get_stacks() -> Array[InventoryStack]:
	return _stacks.duplicate()


func get_total_weight() -> float:
	var total := 0.0

	for stack in _stacks:
		total += stack.get_total_weight()

	return total


func get_remaining_weight() -> float:
	return maxf(0.0, max_weight - get_total_weight())


func is_overweight() -> bool:
	return get_total_weight() > max_weight


func get_speed_multiplier() -> float:
	var current := get_total_weight()

	if current <= max_weight:
		return 1.0

	var overload_ratio := current / max_weight

	var penalty := (overload_ratio - 1.0) * 0.5

	return maxf(
		minimum_speed_multiplier,
		1.0 - penalty
	)


func get_item_amount(item_id: StringName) -> int:
	for stack in _stacks:
		if stack.item_data.id == item_id:
			return stack.amount

	return 0


func has_item(
	item_id: StringName,
	amount: int = 1
) -> bool:

	if amount <= 0:
		return false

	return get_item_amount(item_id) >= amount


# --------------------------------------------------
# ADD ITEM
# --------------------------------------------------

func add_item(
	item_data: ItemData,
	amount: int = 1
) -> bool:

	if item_data == null:
		return false

	if amount <= 0:
		return false

	if item_data.id == &"":
		return false

	if item_data.weight <= 0.0:
		return false

	# Search for existing stack.
	for stack in _stacks:

		if stack.item_data.id == item_data.id:

			stack.amount += amount

			_notify_changed()

			return true

	# Create new stack.
	var new_stack := InventoryStack.new(
		item_data,
		amount
	)

	_stacks.append(new_stack)

	_notify_changed()

	return true


# --------------------------------------------------
# REMOVE ITEM
# --------------------------------------------------

func remove_item(
	item_id: StringName,
	amount: int = 1
) -> bool:

	if amount <= 0:
		return false

	for stack in _stacks:

		if stack.item_data.id == item_id:

			if stack.amount < amount:
				return false

			stack.amount -= amount

			if stack.amount == 0:
				_stacks.erase(stack)

			_notify_changed()

			return true

	return false


# --------------------------------------------------
# CLEAR INVENTORY
# --------------------------------------------------

func clear_inventory() -> void:
	_stacks.clear()
	_notify_changed()


# --------------------------------------------------
# INTERNAL
# --------------------------------------------------

func _notify_changed() -> void:
	var current_weight := get_total_weight()

	inventory_changed.emit()

	weight_changed.emit(
		current_weight,
		max_weight
	)

	encumbrance_changed.emit(
		get_speed_multiplier(),
		is_overweight()
	)


# --------------------------------------------------
# SAVE DATA
# --------------------------------------------------

func to_save_data() -> Dictionary:

	var saved_items: Array[Dictionary] = []

	for stack in _stacks:

		saved_items.append({
			"id": String(stack.item_data.id),
			"amount": stack.amount
		})

	return {
		"max_weight": max_weight,
		"items": saved_items
	}


# --------------------------------------------------
# LOAD DATA
# --------------------------------------------------

func load_save_data(data: Dictionary) -> bool:

	if item_database == null:
		push_error("Inventory: ItemDatabase is missing.")
		return false

	var saved_items: Variant = data.get("items", [])

	if typeof(saved_items) != TYPE_ARRAY:
		push_error("Inventory: Invalid saved items.")
		return false

	var loaded_stacks: Array[InventoryStack] = []

	for saved_item in saved_items:

		if typeof(saved_item) != TYPE_DICTIONARY:
			continue

		var item_id := StringName(
			saved_item.get("id", "")
		)

		var amount := int(
			saved_item.get("amount", 0)
		)

		if amount <= 0:
			continue

		var item_data := item_database.get_item(item_id)

		if item_data == null:
			push_warning(
				"Unknown item in save: " + String(item_id)
			)
			continue

		# Merge duplicate entries from save.
		var existing_stack: InventoryStack = null

		for stack in loaded_stacks:
			if stack.item_data.id == item_id:
				existing_stack = stack
				break

		if existing_stack != null:
			existing_stack.amount += amount
		else:
			loaded_stacks.append(
				InventoryStack.new(item_data, amount)
			)

	_stacks = loaded_stacks

	_notify_changed()

	return true
