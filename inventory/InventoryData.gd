class_name InventoryData
extends Resource

signal inventory_updated(inventory_data: InventoryData)
signal slot_clicked(index: int, button: int)

@export var slot_datas: Array[SlotData]

func add_item(item_data: ItemData, quantity: int = 1) -> int:
	var remaining = quantity

	# 1. Próba dołożenia do istniejącego stosu
	for slot in slot_datas:
		if slot and slot.item_data == item_data:
			var space_left = item_data.max_stack_size - slot.quantity
			if space_left > 0:
				var to_add = mini(space_left, remaining)
				slot.quantity += to_add
				remaining -= to_add
				if remaining == 0:
					inventory_updated.emit(self)
					return 0

	# 2. Szukanie pustego slotu dla reszty
	while remaining > 0:
		var empty_index = slot_datas.find(null)
		if empty_index == -1:
			break # Brak wolnego miejsca
		
		var to_add = mini(item_data.max_stack_size, remaining)
		var new_slot = SlotData.new()
		new_slot.item_data = item_data
		new_slot.quantity = to_add
		slot_datas[empty_index] = new_slot
		remaining -= to_add

	inventory_updated.emit(self)
	return remaining # Zwraca ile sztuk się nie zmieściło
