class_name DungeonGenerator
extends RefCounted

## 1) Prim łączy pokoje
## 2) Drzwi = przecięcie linii z obwodem
## 3) Extra drzwi → część w ekstra korytarze, reszta WFC
## Hub: korytarz ze środka okręgu do nearest. Farthest = liść MST (1 drzwi).

@export var room_count: int = 8
@export var room_min_size: Vector2i = Vector2i(4, 4)
@export var room_max_size: Vector2i = Vector2i(10, 8)
@export var inside_rad: float = 0.0
@export var outside_rad: float = 28.0
@export_range(1.0, 360.0, 0.1) var angle_size: float = 120.0
@export var angle_offset: float = 0.0
@export var room_padding: int = 2
@export var corridor_width: int = 2
@export var max_placement_attempts: int = 40
@export var extra_corridors: int = 2
@export var corridor_noise_amplitude: float = 2.5
@export var corridor_noise_frequency: float = 0.12
## Ile dodatkowych drzwi (poza MST/hub) próbować dołożyć na pokój.
@export var extra_doors_min: int = 1
@export var extra_doors_max: int = 2
@export var door_spacing: int = 2

var _corridor_noise: FastNoiseLite


func generate(seed_value: int = 0) -> DungeonData:
	var rng := RandomNumberGenerator.new()
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value

	var data := DungeonData.new()
	data.seed_used = rng.seed

	_corridor_noise = FastNoiseLite.new()
	_corridor_noise.seed = int(data.seed_used)
	_corridor_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_corridor_noise.frequency = corridor_noise_frequency

	_place_rooms(rng, data)

	var extremes := _find_nearest_farthest_indices(data)
	var nearest_i: int = extremes.x
	var farthest_i: int = extremes.y

	_connect_hub_to_nearest(data, nearest_i)
	_connect_rooms_prim(data, nearest_i)
	_add_extra_doors(rng, data, nearest_i, farthest_i)
	_add_extra_corridors(rng, data)
	_mark_unused_doors_as_wfc(data)

	return data


# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

func _place_rooms(rng: RandomNumberGenerator, data: DungeonData) -> void:
	var count: int = maxi(1, room_count)
	var r_in := minf(inside_rad, outside_rad)
	var r_out := maxf(inside_rad, outside_rad)

	for i in count:
		var placed := false
		var base_angle := _arc_angle_deg(i, count)

		for attempt in max_placement_attempts:
			var size := Vector2i(
				rng.randi_range(room_min_size.x, room_max_size.x),
				rng.randi_range(room_min_size.y, room_max_size.y)
			)

			var angle_span := angle_size / float(maxi(1, count))
			var angle_deg := base_angle + rng.randf_range(-angle_span * 0.35, angle_span * 0.35)
			var r := rng.randf_range(r_in, r_out)
			r = minf(r_out + float(attempt) * 0.5, r + float(attempt) * 0.35)

			var center := _point_on_arc(angle_deg, r)
			var pos := Vector2i(
				int(round(center.x - size.x * 0.5)),
				int(round(center.y - size.y * 0.5))
			)
			var candidate := Rect2i(pos, size)

			if _overlaps_any(candidate, data.rooms, room_padding):
				continue

			var room := DungeonRoom.new()
			room.rect = candidate
			# Drzwi dopiero z Prima / huba / ekstra.
			data.rooms.append(room)
			placed = true
			break

		if not placed:
			push_warning("DungeonGenerator: nie udało się postawić pokoju %s." % i)


func _arc_angle_deg(index: int, count: int) -> float:
	if count <= 1:
		return angle_offset
	var t := float(index) / float(count - 1)
	return angle_offset - angle_size * 0.5 + t * angle_size


func _point_on_arc(angle_deg: float, r: float) -> Vector2:
	var a := deg_to_rad(angle_deg)
	return Vector2(cos(a), sin(a)) * r


func _overlaps_any(candidate: Rect2i, rooms: Array[DungeonRoom], padding: int) -> bool:
	var grown := candidate.grow(padding)
	for room in rooms:
		if grown.intersects(room.rect):
			return true
	return false


func _find_nearest_farthest_indices(data: DungeonData) -> Vector2i:
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


# ---------------------------------------------------------------------------
# Hub + Prim (drzwi z przecięć)
# ---------------------------------------------------------------------------

func _connect_hub_to_nearest(data: DungeonData, nearest_i: int) -> void:
	if nearest_i < 0 or nearest_i >= data.rooms.size():
		return

	var room := data.rooms[nearest_i]
	var hub := Vector2.ZERO
	var center := Vector2(room.get_center())

	if not _segment_hits_only_allowed_rooms(data, hub, center, [nearest_i]):
		push_warning("DungeonGenerator: hub→nearest przecina obcy pokój.")
		return


	var door_cell: Vector2i = _ray_hit_perimeter(room.rect, hub, center)
	var outward_f := Vector2(door_cell) - center
	var outward := Vector2i(signi(int(outward_f.x)), signi(int(outward_f.y)))
	var door := _ensure_door_at(room, nearest_i, door_cell, outward)
	door.state = DungeonDoor.State.LINKED
	door.link_room_index = -1
	door.link_door_index = -1
	_add_corridor_between_points(data, Vector2i.ZERO, door.cell)



func _connect_rooms_prim(data: DungeonData, start_room: int) -> void:
	var n := data.rooms.size()
	if n < 2:
		return

	start_room = clampi(start_room, 0, n - 1)
	var in_tree: Array[bool] = []
	in_tree.resize(n)
	in_tree.fill(false)
	in_tree[start_room] = true
	var in_count := 1

	while in_count < n:
		var best_a := -1
		var best_b := -1
		var best_dist := INF

		for a in n:
			if not in_tree[a]:
				continue
			for b in n:
				if in_tree[b]:
					continue
				if not _room_edge_valid(data, a, b):
					continue
				var dist := _room_distance(data.rooms[a], data.rooms[b])
				if dist < best_dist:
					best_dist = dist
					best_a = a
					best_b = b

		if best_a < 0:
			push_warning("DungeonGenerator: Prim nie połączył wszystkich pokoi.")
			break

		_link_rooms_by_intersection(data, best_a, best_b)
		in_tree[best_b] = true
		in_count += 1


func _room_distance(a: DungeonRoom, b: DungeonRoom) -> float:
	return Vector2(a.get_center()).distance_squared_to(Vector2(b.get_center()))


func _room_edge_valid(data: DungeonData, a: int, b: int) -> bool:
	var ca := Vector2(data.rooms[a].get_center())
	var cb := Vector2(data.rooms[b].get_center())
	return _segment_hits_only_allowed_rooms(data, ca, cb, [a, b])


func _link_rooms_by_intersection(data: DungeonData, a: int, b: int) -> void:
	var room_a := data.rooms[a]
	var room_b := data.rooms[b]
	var ca := Vector2(room_a.get_center())
	var cb := Vector2(room_b.get_center())

	var cell_a: Vector2i = _ray_hit_perimeter(room_a.rect, ca, cb)
	var cell_b: Vector2i = _ray_hit_perimeter(room_b.rect, cb, ca)

	var door_a := _ensure_door_at(
		room_a,
		a,
		cell_a,
		Vector2i(signi(int(cb.x - ca.x)), signi(int(cb.y - ca.y)))
	)
	var door_b := _ensure_door_at(
		room_b,
		b,
		cell_b,
		Vector2i(signi(int(ca.x - cb.x)), signi(int(ca.y - cb.y)))
	)


	var da := room_a.doors.find(door_a)
	var db := room_b.doors.find(door_b)

	door_a.state = DungeonDoor.State.LINKED
	door_b.state = DungeonDoor.State.LINKED
	door_a.link_room_index = b
	door_a.link_door_index = db
	door_b.link_room_index = a
	door_b.link_door_index = da

	_add_corridor_between_points(data, door_a.cell, door_b.cell)


# ---------------------------------------------------------------------------
# Extra doors + corridors + WFC
# ---------------------------------------------------------------------------

func _add_extra_doors(
	rng: RandomNumberGenerator,
	data: DungeonData,
	nearest_i: int,
	farthest_i: int
) -> void:
	for i in data.rooms.size():
		# Liść (farthest) zostaje z drzwiami z MST — bez ekstra.
		if i == farthest_i and farthest_i != nearest_i:
			continue

		var room := data.rooms[i]
		var wanted_extra: int = rng.randi_range(
			mini(extra_doors_min, extra_doors_max),
			maxi(extra_doors_min, extra_doors_max)
		)
		if wanted_extra <= 0:
			continue

		var slots := _perimeter_door_slots(room.rect)
		_shuffle(rng, slots)

		var added := 0
		for slot in slots:
			if added >= wanted_extra:
				break
			var cell: Vector2i = slot["cell"]
			if _door_too_close(room, cell):
				continue
			if _find_door_at(room, cell) != null:
				continue

			var door := DungeonDoor.new()
			door.cell = cell
			door.outward = slot["outward"]
			door.room_index = i
			door.state = DungeonDoor.State.FREE
			room.doors.append(door)
			added += 1


func _add_extra_corridors(rng: RandomNumberGenerator, data: DungeonData) -> void:
	var n := data.rooms.size()
	if n < 2 or extra_corridors <= 0:
		return

	var candidates: Array[Dictionary] = []
	for a in n:
		for b in range(a + 1, n):
			var pair := _best_extra_corridor_candidate(data, a, b)
			if pair.is_empty():
				continue
			candidates.append(pair)

	_shuffle(rng, candidates)
	var added := 0
	for link in candidates:
		if added >= extra_corridors:
			break
		if _try_apply_extra_corridor(data, link):
			added += 1


func _best_extra_corridor_candidate(data: DungeonData, a: int, b: int) -> Dictionary:
	var room_a := data.rooms[a]
	var room_b := data.rooms[b]
	var best: Dictionary = {}
	var best_dist := INF

	# 1) Wolne drzwi — pełna walidacja ścieżki ze szumem.
	for di in room_a.doors.size():
		if room_a.doors[di].state != DungeonDoor.State.FREE:
			continue
		for dj in room_b.doors.size():
			if room_b.doors[dj].state != DungeonDoor.State.FREE:
				continue
			var from_cell := room_a.doors[di].cell
			var to_cell := room_b.doors[dj].cell
			if not _is_corridor_clear(data, from_cell, to_cell, a, b):
				continue
			var dist := Vector2(from_cell).distance_squared_to(Vector2(to_cell))
			if dist < best_dist:
				best_dist = dist
				best = {
					"room_a": a,
					"door_a": di,
					"room_b": b,
					"door_b": dj,
					"use_intersection": false,
				}

	if not best.is_empty():
		return best

	# 2) Nowe przecięcie środków — tylko jeśli prosta i ścieżka drzwi→drzwi są czyste.
	if not _room_edge_valid(data, a, b):
		return {}

	var ca := Vector2(room_a.get_center())
	var cb := Vector2(room_b.get_center())
	var cell_a: Vector2i = _ray_hit_perimeter(room_a.rect, ca, cb)
	var cell_b: Vector2i = _ray_hit_perimeter(room_b.rect, cb, ca)
	if not _is_corridor_clear(data, cell_a, cell_b, a, b):
		return {}

	return {
		"room_a": a,
		"room_b": b,
		"cell_a": cell_a,
		"cell_b": cell_b,
		"use_intersection": true,
		"dist": _room_distance(room_a, room_b),
	}


func _try_apply_extra_corridor(data: DungeonData, link: Dictionary) -> bool:
	var ra: int = int(link["room_a"])
	var rb: int = int(link["room_b"])

	if link.get("use_intersection", false):
		var cell_a: Vector2i = link["cell_a"]
		var cell_b: Vector2i = link["cell_b"]
		if not _is_corridor_clear(data, cell_a, cell_b, ra, rb):
			return false

		var room_a := data.rooms[ra]
		var room_b := data.rooms[rb]
		var ca := Vector2(room_a.get_center())
		var cb := Vector2(room_b.get_center())
		var door_a := _ensure_door_at(
			room_a,
			ra,
			cell_a,
			Vector2i(signi(int(cb.x - ca.x)), signi(int(cb.y - ca.y)))
		)
		var door_b := _ensure_door_at(
			room_b,
			rb,
			cell_b,
			Vector2i(signi(int(ca.x - cb.x)), signi(int(ca.y - cb.y)))
		)
		if door_a.state != DungeonDoor.State.FREE or door_b.state != DungeonDoor.State.FREE:
			return false

		var da := room_a.doors.find(door_a)
		var db := room_b.doors.find(door_b)
		door_a.state = DungeonDoor.State.LINKED
		door_b.state = DungeonDoor.State.LINKED
		door_a.link_room_index = rb
		door_a.link_door_index = db
		door_b.link_room_index = ra
		door_b.link_door_index = da
		_add_corridor_between_points(data, door_a.cell, door_b.cell)
		return true

	var da2: int = int(link["door_a"])
	var db2: int = int(link["door_b"])
	var door_a2 := data.rooms[ra].doors[da2]
	var door_b2 := data.rooms[rb].doors[db2]
	if door_a2.state != DungeonDoor.State.FREE or door_b2.state != DungeonDoor.State.FREE:
		return false
	if not _is_corridor_clear(data, door_a2.cell, door_b2.cell, ra, rb):
		return false

	door_a2.state = DungeonDoor.State.LINKED
	door_b2.state = DungeonDoor.State.LINKED
	door_a2.link_room_index = rb
	door_a2.link_door_index = db2
	door_b2.link_room_index = ra
	door_b2.link_door_index = da2
	_add_corridor_between_points(data, door_a2.cell, door_b2.cell)
	return true


func _is_corridor_clear(
	data: DungeonData,
	from_cell: Vector2i,
	to_cell: Vector2i,
	room_a: int,
	room_b: int
) -> bool:
	## Ścieżka ze szumem + grubością: obcy pokój = fail;
	## w pokojach A/B wolno tylko okolica drzwi.
	var covered := _sample_corridor_cells(from_cell, to_cell)
	var slack: int = maxi(1, corridor_width)

	for cell in covered:
		for ri in data.rooms.size():
			if not data.rooms[ri].rect.has_point(cell):
				continue

			if ri == room_a:
				if _manhattan(cell, from_cell) <= slack:
					continue
				return false
			if ri == room_b:
				if _manhattan(cell, to_cell) <= slack:
					continue
				return false

			# Obcy pokój.
			return false

	return true


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _mark_unused_doors_as_wfc(data: DungeonData) -> void:
	for room in data.rooms:
		for door in room.doors:
			if door.state == DungeonDoor.State.FREE:
				door.state = DungeonDoor.State.WFC


# ---------------------------------------------------------------------------
# Geometry / doors helpers
# ---------------------------------------------------------------------------

func _ray_hit_perimeter(rect: Rect2i, from: Vector2, toward: Vector2) -> Vector2i:
	## Pierwsze trafienie w obwód idąc z `from` w stronę `toward`.
	var dir := toward - from
	if dir.length_squared() < 0.0001:
		return _clamp_to_perimeter(
			rect,
			Vector2i(int(round(from.x)), int(round(from.y)))
		)

	var steps: int = maxi(1, int(ceil(dir.length() * 2.0)))
	var prev_inside := rect.has_point(Vector2i(int(round(from.x)), int(round(from.y))))
	# Jeśli start poza rect (hub), szukamy wejścia; jeśli w środku — wyjścia.
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var p := from.lerp(toward, t)
		var cell := Vector2i(int(round(p.x)), int(round(p.y)))
		var inside := rect.has_point(cell)

		if prev_inside and not inside:
			# Właśnie wyszliśmy — drzwi = poprzednia komórka na/obok obwodu.
			var prev := from.lerp(toward, float(i - 1) / float(steps))
			return _clamp_to_perimeter(
				rect,
				Vector2i(int(round(prev.x)), int(round(prev.y)))
			)
		if not prev_inside and inside:
			return _clamp_to_perimeter(rect, cell)

		prev_inside = inside

	return _clamp_to_perimeter(
		rect,
		Vector2i(int(round(toward.x)), int(round(toward.y)))
	)


func _clamp_to_perimeter(rect: Rect2i, cell: Vector2i) -> Vector2i:
	var c := cell
	c.x = clampi(c.x, rect.position.x, rect.end.x - 1)
	c.y = clampi(c.y, rect.position.y, rect.end.y - 1)

	# Jeśli w środku — wypchnij na najbliższą krawędź.
	if c.x > rect.position.x and c.x < rect.end.x - 1 and c.y > rect.position.y and c.y < rect.end.y - 1:
		var dl: int = c.x - rect.position.x
		var dr: int = rect.end.x - 1 - c.x
		var dt: int = c.y - rect.position.y
		var db: int = rect.end.y - 1 - c.y
		var m: int = mini(mini(dl, dr), mini(dt, db))
		if m == dl:
			c.x = rect.position.x
		elif m == dr:
			c.x = rect.end.x - 1
		elif m == dt:
			c.y = rect.position.y
		else:
			c.y = rect.end.y - 1
	return c


func _ensure_door_at(
	room: DungeonRoom,
	room_index: int,
	cell: Vector2i,
	outward_hint: Vector2i
) -> DungeonDoor:
	var existing := _find_door_at(room, cell)
	if existing != null:
		return existing

	var door := DungeonDoor.new()
	door.cell = _clamp_to_perimeter(room.rect, cell)
	door.room_index = room_index
	door.outward = outward_hint
	if door.outward == Vector2i.ZERO:
		door.outward = Vector2i.RIGHT
	door.state = DungeonDoor.State.FREE
	room.doors.append(door)
	return door


func _find_door_at(room: DungeonRoom, cell: Vector2i) -> DungeonDoor:
	for door in room.doors:
		if door.cell == cell:
			return door
	return null


func _door_too_close(room: DungeonRoom, cell: Vector2i) -> bool:
	for door in room.doors:
		if absi(door.cell.x - cell.x) + absi(door.cell.y - cell.y) < door_spacing:
			return true
	return false


func _perimeter_door_slots(rect: Rect2i) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	if rect.size.x < 3 or rect.size.y < 3:
		var c := rect.get_center()
		slots.append({"cell": Vector2i(c.x, rect.position.y), "outward": Vector2i(0, -1)})
		slots.append({"cell": Vector2i(c.x, rect.end.y - 1), "outward": Vector2i(0, 1)})
		slots.append({"cell": Vector2i(rect.position.x, c.y), "outward": Vector2i(-1, 0)})
		slots.append({"cell": Vector2i(rect.end.x - 1, c.y), "outward": Vector2i(1, 0)})
		return slots

	for x in range(rect.position.x + 1, rect.end.x - 1):
		slots.append({"cell": Vector2i(x, rect.position.y), "outward": Vector2i(0, -1)})
		slots.append({"cell": Vector2i(x, rect.end.y - 1), "outward": Vector2i(0, 1)})
	for y in range(rect.position.y + 1, rect.end.y - 1):
		slots.append({"cell": Vector2i(rect.position.x, y), "outward": Vector2i(-1, 0)})
		slots.append({"cell": Vector2i(rect.end.x - 1, y), "outward": Vector2i(1, 0)})
	return slots


func _segment_hits_only_allowed_rooms(
	data: DungeonData,
	from: Vector2,
	to: Vector2,
	allowed_room_indices: Array
) -> bool:
	## False, gdy prosta trafia w pokój spoza allowed (allowed może zawierać indeksy pokoi).
	var delta := to - from
	var length := delta.length()
	if length < 0.001:
		return true

	var steps: int = maxi(1, int(ceil(length)))
	for i in steps + 1:
		var p := from.lerp(to, float(i) / float(steps))
		var cell := Vector2i(int(round(p.x)), int(round(p.y)))
		for ri in data.rooms.size():
			if not data.rooms[ri].rect.has_point(cell):
				continue
			if ri in allowed_room_indices:
				continue
			return false
	return true


# ---------------------------------------------------------------------------
# Corridor raster
# ---------------------------------------------------------------------------

func _sample_corridor_cells(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen: Dictionary = {}

	var from_p := Vector2(from_cell)
	var to_p := Vector2(to_cell)
	var delta := to_p - from_p
	var length := delta.length()
	if length < 0.001:
		_append_stamp_cells(result, seen, from_cell)
		return result

	var dir := delta / length
	var perp := Vector2(-dir.y, dir.x)
	var steps: int = maxi(1, int(ceil(length)))

	for i in steps + 1:
		var t := float(i) / float(steps)
		var point := from_p.lerp(to_p, t)
		var fade := sin(t * PI) # szum tylko w środku segmentu
		var n := 0.0
		if _corridor_noise != null:
			n = _corridor_noise.get_noise_1d(float(i) * 10.0)
		point += perp * n * corridor_noise_amplitude * fade
		_append_stamp_cells(
			result,
			seen,
			Vector2i(int(round(point.x)), int(round(point.y)))
		)

	return result


func _append_stamp_cells(result: Array[Vector2i], seen: Dictionary, center: Vector2i) -> void:
	var half_w: int = maxi(0, corridor_width / 2)
	var w: int = maxi(1, corridor_width)
	for y in w:
		for x in w:
			var cell := Vector2i(center.x - half_w + x, center.y - half_w + y)
			if seen.has(cell):
				continue
			seen[cell] = true
			result.append(cell)


func _add_corridor_between_points(data: DungeonData, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var half_w: int = maxi(0, corridor_width / 2)
	var stamp := Vector2i(maxi(1, corridor_width), maxi(1, corridor_width))
	var stamped_centers: Dictionary = {}

	var from_p := Vector2(from_cell)
	var to_p := Vector2(to_cell)
	var delta := to_p - from_p
	var length := delta.length()
	if length < 0.001:
		return

	var dir := delta / length
	var perp := Vector2(-dir.y, dir.x)
	var steps: int = maxi(1, int(ceil(length)))

	for i in steps + 1:
		var t := float(i) / float(steps)
		var point := from_p.lerp(to_p, t)
		var fade := sin(t * PI)
		var n := 0.0
		if _corridor_noise != null:
			n = _corridor_noise.get_noise_1d(float(i) * 10.0)
		point += perp * n * corridor_noise_amplitude * fade

		var cell := Vector2i(int(round(point.x)), int(round(point.y)))
		if stamped_centers.has(cell):
			continue
		stamped_centers[cell] = true
		data.corridors.append(Rect2i(Vector2i(cell.x - half_w, cell.y - half_w), stamp))


func _shuffle(rng: RandomNumberGenerator, items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp
