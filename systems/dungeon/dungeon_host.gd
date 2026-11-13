@tool
extends Node3D

## Podgląd w edytorze bez F5.
## Checkbox regenerate_dungeon = przycisk (getter zawsze false).

@export var seed_value: int = 42:
	set(value):
		seed_value = value
		if Engine.is_editor_hint() and auto_regenerate_in_editor and _can_regenerate():
			regenerate()

@export var regenerate_on_ready: bool = true
@export var auto_regenerate_in_editor: bool = true

@export_group("Actions")
## Kliknij checkbox = regeneruj.
@export var regenerate_dungeon: bool = false:
	get:
		return false
	set(value):
		if not value:
			return
		if _can_regenerate():
			regenerate()
		else:
			push_warning("DungeonHost: węzeł nie jest w drzewie — otwórz scenę dungeon_test.tscn.")

@export_group("Generator")
@export var room_count: int = 8
@export var room_min_size: Vector2i = Vector2i(4, 4)
@export var room_max_size: Vector2i = Vector2i(10, 8)
@export var inside_rad: float = 0.0
@export var outside_rad: float = 28.0
@export_range(1.0, 360.0, 0.1) var angle_size: float = 120.0
@export var angle_offset: float = 0.0
@export var room_padding: int = 2
@export var corridor_width: int = 2
@export var extra_corridors: int = 2
@export var corridor_noise_amplitude: float = 2.5
@export var corridor_noise_frequency: float = 0.12
@export var extra_doors_min: int = 1
@export var extra_doors_max: int = 2
@export var door_spacing: int = 2


@export_group("Builder")
@export var cell_size: float = 2.0
@export var show_door_indicators: bool = true



var last_data: DungeonData


func _ready() -> void:
	if regenerate_on_ready:
		regenerate()


func _can_regenerate() -> bool:
	# Po hot-reload @tool is_node_ready() bywa false — dlatego is_inside_tree().
	return is_inside_tree() and get_node_or_null("DungeonBuilder") != null


func regenerate() -> void:
	var builder := get_node_or_null("DungeonBuilder") as DungeonBuilder
	if builder == null:
		push_warning("DungeonHost: brak dziecka DungeonBuilder.")
		return

	var generator := DungeonGenerator.new()
	generator.room_count = room_count
	generator.room_min_size = room_min_size
	generator.room_max_size = room_max_size
	generator.inside_rad = inside_rad
	generator.outside_rad = outside_rad
	generator.angle_size = angle_size
	generator.angle_offset = angle_offset
	generator.room_padding = room_padding
	generator.corridor_width = corridor_width
	generator.extra_corridors = extra_corridors
	generator.corridor_noise_amplitude = corridor_noise_amplitude
	generator.corridor_noise_frequency = corridor_noise_frequency
	generator.extra_doors_min = extra_doors_min
	generator.extra_doors_max = extra_doors_max
	generator.door_spacing = door_spacing

	last_data = generator.generate(seed_value)
	builder.cell_size = cell_size
	builder.show_door_indicators = show_door_indicators
	builder.build(last_data)

	var linked := 0
	var wfc := 0
	for room in last_data.rooms:
		linked += room.count_doors_with_state(DungeonDoor.State.LINKED)
		wfc += room.count_doors_with_state(DungeonDoor.State.WFC)

	print(
		"Dungeon seed=%s rooms=%s corridors=%s doors_linked=%s doors_wfc=%s"
		% [
			last_data.seed_used,
			last_data.rooms.size(),
			last_data.corridors.size(),
			linked,
			wfc,
		]
	)
