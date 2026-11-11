extends CharacterBody3D

# Parametry podstawowego ruchu
const WALK_SPEED = 5.0

# Parametry Dasha (Zrywu)
const DASH_SPEED = 18.0
const DASH_DURATION = 0.15
const MAX_DASH_CHARGES = 2
const DASH_COOLDOWN = 3.0

# Pobieranie domyślnej grawitacji z ustawień projektu Godot
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Zmienne śledzące stan
var current_charges: int = MAX_DASH_CHARGES
var is_dashing: bool = false
var dash_timer: float = 0.0
var recharge_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO

func _ready() -> void:
	# 1. Zwiększamy tolerancję kąta (np. do 60 stopni)
	floor_max_angle = deg_to_rad(60.0)
	
	# 2. Blokuje samoczynne zsuwanie się, gdy stoisz w miejscu
	floor_stop_on_slope = true
	
	# 3. Stała prędkość na podejściach
	floor_constant_speed = true
	
	# 4. Trzymanie podłoża przy schodzeniu w dół
	floor_snap_length = 0.3


func _physics_process(delta: float) -> void:
	handle_dash_recharge(delta)
	
	# Prawidłowa obsługa grawitacji:
	# NIE zeruj velocity.y ręcznie w bloku else. move_and_slide() robi to sam.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Pobieranie kierunku ruchu...
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := Vector3(input_dir.x, 0.0, input_dir.y).normalized()
	direction = direction.rotated(Vector3.UP, deg_to_rad(45))

	if Input.is_action_just_pressed("dash") and current_charges > 0 and not is_dashing:
		start_dash_towards_mouse()

	if is_dashing:
		dash_timer -= delta
		velocity.x = dash_direction.x * DASH_SPEED
		velocity.z = dash_direction.z * DASH_SPEED
		if dash_timer <= 0.0:
			is_dashing = false
	else:
		if direction != Vector3.ZERO:
			velocity.x = direction.x * WALK_SPEED
			velocity.z = direction.z * WALK_SPEED
			
			var look_target = global_position + direction
			look_target.y = global_position.y
			look_at(look_target, Vector3.UP)
		else:
			velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
			velocity.z = move_toward(velocity.z, 0, WALK_SPEED)

	# move_and_slide sam rozłoży velocity.x i velocity.z na wspinanie po rampie
	move_and_slide()
	
func start_dash_towards_mouse() -> void:
	var mouse_world_pos = get_mouse_world_position()
	
	if mouse_world_pos != null:
		var dir_to_mouse = (mouse_world_pos - global_position)
		dir_to_mouse.y = 0.0
		
		if dir_to_mouse.length() > 0.01:
			dash_direction = dir_to_mouse.normalized()
		else:
			dash_direction = -transform.basis.z.normalized()
	else:
		dash_direction = -transform.basis.z.normalized()
		
	is_dashing = true
	dash_timer = DASH_DURATION
	current_charges -= 1
	
	var dash_look_target = global_position + dash_direction
	dash_look_target.y = global_position.y
	look_at(dash_look_target, Vector3.UP)

func get_mouse_world_position():
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return null
		
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	# Płaszczyzna celowania zawsze na aktualnej wysokości gracza (uwzględnia nową wysokość na schodach)
	var ground_plane = Plane(Vector3.UP, global_position.y)
	
	return ground_plane.intersects_ray(ray_origin, ray_dir)

func handle_dash_recharge(delta: float) -> void:
	if current_charges < MAX_DASH_CHARGES:
		recharge_timer += delta
		if recharge_timer >= DASH_COOLDOWN:
			current_charges += 1
			recharge_timer = 0.0
