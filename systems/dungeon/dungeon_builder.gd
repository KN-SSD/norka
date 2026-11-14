@tool
class_name DungeonBuilder
extends Node3D

## Bierze DungeonData i stawia podłogi 3D + indykatory drzwi.

@export var cell_size: float = 2.0
@export var floor_thickness: float = 0.3
@export var room_color: Color = Color(0.35, 0.45, 0.55)
@export var room_nearest_color: Color = Color(0.2, 0.85, 0.35)
@export var room_farthest_color: Color = Color(0.9, 0.2, 0.2)
@export var corridor_color: Color = Color(0.25, 0.3, 0.28)
@export var door_linked_color: Color = Color(0.2, 0.85, 0.35)
@export var door_wfc_color: Color = Color(0.95, 0.55, 0.15)
@export var show_door_indicators: bool = true

var _root: Node3D


func clear_built() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null

	for child in get_children():
		if child.name == "GeneratedDungeon":
			child.free()


func build(data: DungeonData) -> void:
	clear_built()

	_root = Node3D.new()
	_root.name = "GeneratedDungeon"
	add_child(_root)

	var extremes := _find_nearest_farthest_rooms(data)
	var nearest_i: int = extremes.x
	var farthest_i: int = extremes.y

	for room_index in data.rooms.size():
		var room := data.rooms[room_index]
		var color := room_color
		if room_index == nearest_i:
			color = room_nearest_color
		elif room_index == farthest_i:
			color = room_farthest_color

		_root.add_child(_make_polygon_room(room, color))

		if show_door_indicators:
			_root.add_child(
				_make_room_door_label(
					room,
					room_index == nearest_i,
					room_index == farthest_i
				)
			)
			for door in room.doors:
				_root.add_child(_make_door_marker(door))

	for corridor in data.corridors:
		_root.add_child(_make_box(corridor, corridor_color, "Corridor"))

	_center_on_origin(data)


func _find_nearest_farthest_rooms(data: DungeonData) -> Vector2i:
	## x = nearest index, y = farthest index (dystans od środka okręgu 0,0).
	if data.rooms.is_empty():
		return Vector2i(-1, -1)

	var best_near := INF
	var best_far := -1.0
	var near_idx := 0
	var far_idx := 0

	for i in data.rooms.size():
		var d := Vector2(data.rooms[i].get_center()).length_squared()
		if d < best_near:
			best_near = d
			near_idx = i
		if d > best_far:
			best_far = d
			far_idx = i

	return Vector2i(near_idx, far_idx)


func _make_room_door_label(room: DungeonRoom, is_nearest: bool, is_farthest: bool) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 8
	label.modulate = Color(1, 1, 1)
	label.position = _cell_to_world_center(room.get_center()) + Vector3(0, 1.2, 0)

	var linked := room.count_doors_with_state(DungeonDoor.State.LINKED)
	var wfc := room.count_doors_with_state(DungeonDoor.State.WFC)
	var tag := ""
	if is_nearest:
		tag = "\n[NEAREST]"
		label.modulate = room_nearest_color
	elif is_farthest:
		tag = "\n[FARTHEST]"
		label.modulate = room_farthest_color

	label.text = "Drzwi: %d\nL:%d  WFC:%d%s" % [room.door_count(), linked, wfc, tag]
	return label


func _make_door_marker(door: DungeonDoor) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(cell_size * 0.55, 0.8, cell_size * 0.55)
	marker.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = (
		door_linked_color if door.state == DungeonDoor.State.LINKED else door_wfc_color
	)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 2.0
	marker.material_override = mat

	marker.position = _cell_to_world_center(door.cell) + Vector3(0, 0.5, 0)
	return marker


func _cell_to_world_center(cell: Vector2i) -> Vector3:
	return Vector3(
		(cell.x + 0.5) * cell_size,
		0.0,
		(cell.y + 0.5) * cell_size
	)


func _make_polygon_room(
	room: DungeonRoom,
	color: Color
) -> StaticBody3D:

	var body := StaticBody3D.new()
	body.name = "Room_%d_%d" % [
		room.rect.position.x,
		room.rect.position.y
	]

	var polygon := room.polygon

	if polygon.size() < 3:
		return _make_box(room.rect, color, "Room")

	var vertices := PackedVector3Array()

	# Konwersja 2D na 3D.
	# W Godot oś Y jest wysokością.
	# Oś Z odpowiada drugiej współrzędnej 2D.
	for point in polygon:
		vertices.append(Vector3(
			point.x * cell_size,
			0.0,
			point.y * cell_size
		))

	# Triangulacja podłogi.
	var indices := Geometry2D.triangulate_polygon(polygon)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var mesh_vertices := PackedVector3Array()

	for i in indices:
		var point := polygon[i]
		mesh_vertices.append(Vector3(
			point.x * cell_size,
			0.0,
			point.y * cell_size
		))

	arrays[Mesh.ARRAY_VERTEX] = mesh_vertices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays
	)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = mat

	body.add_child(mesh_instance)

	# Kolizja wypukła.
	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()

	var collision_points := PackedVector3Array()

	for point in polygon:
		collision_points.append(Vector3(
			point.x * cell_size,
			-floor_thickness * 0.5,
			point.y * cell_size
		))
		collision_points.append(Vector3(
			point.x * cell_size,
			floor_thickness * 0.5,
			point.y * cell_size
		))

	shape.points = collision_points
	collision.shape = shape
	body.add_child(collision)

	# Pozycja pokoju w świecie.
	body.position = Vector3(
		room.rect.position.x * cell_size,
		0.0,
		room.rect.position.y * cell_size
	)

	return body


func _make_box(rect: Rect2i, color: Color, prefix: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "%s_%d_%d" % [prefix, rect.position.x, rect.position.y]

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(
		rect.size.x * cell_size,
		floor_thickness,
		rect.size.y * cell_size
	)
	mesh_instance.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	body.add_child(collision)

	body.position = Vector3(
		(rect.position.x + rect.size.x * 0.5) * cell_size,
		0.0,
		(rect.position.y + rect.size.y * 0.5) * cell_size
	)
	return body


func _center_on_origin(data: DungeonData) -> void:
	var bounds := data.get_bounds()
	if bounds.size == Vector2i.ZERO:
		return

	_root.position = Vector3(
		-(bounds.position.x + bounds.size.x * 0.5) * cell_size,
		0.0,
		-(bounds.position.y + bounds.size.y * 0.5) * cell_size
	)
