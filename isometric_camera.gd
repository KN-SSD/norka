extends Camera3D

@export var target: Node3D
@export var offset: Vector3 = Vector3(10.0, 12.0, 10.0)
@export var smooth_speed: float = 5.0

# Przechowuje ścianę, która jest obecnie przezroczysta
var current_faded_wall: GeometryInstance3D = null

func _ready() -> void:
	if not target:
		target = get_node("../Player")

func _physics_process(delta: float) -> void:
	if not target:
		return
		
	# 1. Płynne podążanie kamery (bez zmian)
	var target_position = target.global_position + offset
	global_position = global_position.lerp(target_position, smooth_speed * delta)
	
	# 2. Sprawdzanie przeszkód między kamerą a graczem
	check_wall_occlusion()

func check_wall_occlusion() -> void:
	var space_state = get_world_3d().direct_space_state
	
	# Celujemy lekko powyżej podłogi (np. na wysokość klatki piersiowej postaci: +1.0m)
	var target_center = target.global_position + Vector3(0, 1.0, 0)
	
	# Tworzymy zapytanie promienia od kamery do gracza
	var query = PhysicsRayQueryParameters3D.create(global_position, target_center)
	# Skanujemy tylko warstwę kolizji nr 2 (na której ustawiliśmy ściany)
	query.collision_mask = 2 
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var hit_object = result.collider
		# Jeśli trafiliśmy w nową ścianę, przywracamy poprzednią i przyciemniamy nową
		if hit_object != current_faded_wall:
			restore_wall_opacity()
			if hit_object is GeometryInstance3D:
				set_wall_opacity(hit_object, 0.3)
				current_faded_wall = hit_object
	else:
		# Jeśli nic nie zasłania gracza, przywracamy pełną widoczność ściany
		restore_wall_opacity()

func set_wall_opacity(wall: GeometryInstance3D, alpha: float) -> void:
	var mat = wall.material_override
	if not mat and "material" in wall:
		mat = wall.material
		
	if mat is BaseMaterial3D:
		# Jeśli ściana nie ma jeszcze własnej, niezależnej kopii materiału, tworzymy ją teraz
		if not wall.has_meta("unique_mat_created"):
			mat = mat.duplicate()
			if "material" in wall:
				wall.material = mat
			else:
				wall.material_override = mat
			wall.set_meta("unique_mat_created", true)
		
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = alpha

func restore_wall_opacity() -> void:
	if current_faded_wall != null:
		var mat = current_faded_wall.material_override
		if not mat and "material" in current_faded_wall:
			mat = current_faded_wall.material
			
		if mat is BaseMaterial3D:
			mat.albedo_color.a = 1.0
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			
		current_faded_wall = null
