class_name Interactor
extends Node

## Trzyma WorldItemy w zasięgu i na [interact] podnosi najbliższy.

var _nearby: Array[WorldItem] = []


func register_world_item(item: WorldItem) -> void:
	if item == null or item in _nearby:
		return

	_nearby.append(item)
	_refresh_prompts()


func unregister_world_item(item: WorldItem) -> void:
	if item == null:
		return

	_nearby.erase(item)
	if is_instance_valid(item):
		item.hide_prompt()
	_refresh_prompts()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return

	var item := get_closest_item()
	if item == null:
		return

	var player := get_parent()
	if item.try_pickup(player):
		get_viewport().set_input_as_handled()


func get_closest_item() -> WorldItem:
	_prune_invalid()

	if _nearby.is_empty():
		return null

	var player := get_parent() as Node3D
	if player == null:
		return null

	var closest: WorldItem = null
	var best_dist := INF

	for item in _nearby:
		var dist := player.global_position.distance_squared_to(item.global_position)
		if dist < best_dist:
			best_dist = dist
			closest = item

	return closest


func _refresh_prompts() -> void:
	_prune_invalid()

	var closest := get_closest_item()
	for item in _nearby:
		if item == closest:
			item.show_prompt()
		else:
			item.hide_prompt()


func _prune_invalid() -> void:
	_nearby = _nearby.filter(
		func(item: WorldItem) -> bool:
			return is_instance_valid(item) and not item.collected
	)


func _process(_delta: float) -> void:
	# Gdy gracz chodzi między kilkoma itemami — aktualizuj, który ma prompt.
	if _nearby.size() > 1:
		_refresh_prompts()
