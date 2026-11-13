class_name WorldItem
extends Area3D

@export var item_data: ItemData
@export_range(1, 9999) var amount: int = 1
@export var pickup_grace_sec: float = 0.0

@onready var prompt: Label3D = $Prompt

var collected := false
var _player_body: Node3D = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	hide_prompt()
	_refresh_prompt_text()

	if pickup_grace_sec > 0.0:
		monitoring = false
		await get_tree().create_timer(pickup_grace_sec).timeout
		if not is_instance_valid(self):
			return
		monitoring = true
		for body in get_overlapping_bodies():
			_on_body_entered(body)


func show_prompt() -> void:
	_refresh_prompt_text()
	prompt.visible = true


func hide_prompt() -> void:
	prompt.visible = false


func try_pickup(player: Node) -> bool:
	if collected:
		return false

	if item_data == null:
		push_warning("WorldItem has no ItemData assigned!")
		return false

	if player == null or not player.is_in_group("player"):
		return false

	var inventory = player.get_node_or_null("Inventory")
	if inventory == null:
		push_warning("Player does not have an Inventory node!")
		return false

	collected = true
	_unregister_from_player()

	inventory.add_item(item_data, amount)
	queue_free()
	return true


func _refresh_prompt_text() -> void:
	if prompt == null:
		return

	if item_data == null:
		prompt.text = "???"
		return

	prompt.text = "%s x%d\n[E]" % [item_data.item_name, amount]


func _on_body_entered(body: Node3D) -> void:
	if collected:
		return

	if not body.is_in_group("player"):
		return

	_player_body = body
	var interactor := body.get_node_or_null("Interactor") as Interactor
	if interactor == null:
		push_warning("Player has no Interactor node!")
		return

	interactor.register_world_item(self)


func _on_body_exited(body: Node3D) -> void:
	if body != _player_body:
		return

	_unregister_from_player()
	_player_body = null


func _unregister_from_player() -> void:
	if _player_body == null:
		return

	var interactor := _player_body.get_node_or_null("Interactor") as Interactor
	if interactor != null:
		interactor.unregister_world_item(self)
