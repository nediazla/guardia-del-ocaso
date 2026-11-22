extends Node2D

class Tank:
	var cell: Vector2i
	var facing: Vector2i
	var reload := 0
	var next_move := 0
	var armor := 1
	var rank := 1
	var previous_cell: Vector2i
	var move_started := 0.0
	var move_duration := 0.0
	var track_distance := 0.0
	var angle: float
	func _init(position: Vector2i, direction: Vector2i) -> void:
		cell = position
		previous_cell = position
		facing = direction
		angle = Vector2(direction).angle() + PI / 2

class Shot:
	var cell: Vector2i
	var direction: Vector2i
	var friendly: bool
	var power: int
	func _init(tank: Tank, from_player: bool, gun_power := 1) -> void:
		cell = tank.cell
		direction = tank.facing
		friendly = from_player
		power = gun_power

const TILE := 32
const ORIGIN := Vector2(32, 128)
const BOUNDS := Rect2i(0, 0, 22, 12)
const PLAYER_BASE := Vector2i(10, 11)
const ENEMY_BASE := Vector2i(11, 0)
const START := Vector2i(8, 11)
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const ACTIONS: Array[StringName] = [&"ui_up", &"ui_right", &"ui_down", &"ui_left"]
const MAPS = preload("res://campaign.gd").MAPS
const SPAWNS: Array[Vector2i] = [
	Vector2i(13, 0), Vector2i(7, 0), Vector2i(21, 0), Vector2i(0, 0),
]

enum Wall { BRICK, STEEL }

enum Pickup { RUNNER, GRAY_TANK, BLACK_TANK }
enum EnemyType { SCOUT, MEDIUM, HEAVY }

const MOVE_TICKS: Array[int] = [9, 8, 7, 6, 5]
const RELOAD_TICKS: Array[int] = [10, 9, 8, 7, 6]
const ENEMY_TYPES: Array[EnemyType] = [
	EnemyType.SCOUT, EnemyType.SCOUT, EnemyType.MEDIUM, EnemyType.HEAVY, EnemyType.HEAVY,
]
const ENEMY_MOVE_TICKS: Array[int] = [8, 9, 11]
const PICKUP_COLORS: Array[Color] = [Color("#eac47a"), Color("#adbccd"), Color("#353349")]

var player: Tank
var rivals: Array[Tank] = []
var shots: Array[Shot] = []
var walls: Dictionary[Vector2i, Wall] = {}
var damaged_steel: Dictionary[Vector2i, bool] = {}
var level := 1
var upgrades := Vector3i.ONE
var entry_upgrades := Vector3i.ONE
var pickups: Dictionary[Vector2i, Pickup] = {}
var visual_time := 0.0
var player_base_armor := 0
var enemy_base_armor := 0
var base_rank := 1
var won := false
var ticks := 0
var elapsed := 0.0
var result := ""
var fire_requested := false

func _ready() -> void:
	reset()

func reset() -> void:
	upgrades = entry_upgrades
	visual_time = 0.0
	base_rank = 1 if level < 9 else mini(5, 2 + floori((level - 9) / 3.0))
	player_base_armor = base_rank - 1
	enemy_base_armor = base_rank - 1
	player = Tank.new(START, Vector2i.UP)
	rivals.clear()
	var enemy_count := mini(SPAWNS.size(), 1 + floori((level - 1) / 5.0))
	for index in enemy_count:
		var enemy := Tank.new(SPAWNS[index], Vector2i.DOWN)
		enemy.reload = 10 + index * 6
		enemy.rank = clampi(1 + floori((level - 1 + index * 2) / 4.0), 1, 5)
		enemy.armor = enemy.rank
		rivals.append(enemy)
	damaged_steel.clear()
	walls.clear()
	var map: Array = MAPS[level - 1]
	for y in BOUNDS.size.y:
		for x in BOUNDS.size.x:
			var tile: String = map[y][x]
			if tile != ".":
				walls[Vector2i(x, y)] = Wall.STEEL if tile == "M" else Wall.BRICK
	place_pickups()
	shots.clear()
	ticks = 0
	elapsed = 0.0
	result = ""
	won = false
	fire_requested = false
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			reset()
		elif event.physical_keycode == KEY_ENTER and won:
			next_level()
		elif event.physical_keycode == KEY_SPACE and result.is_empty():
			fire_requested = true

func next_level() -> void:
	if level < MAPS.size():
		entry_upgrades = upgrades
		level += 1
	else:
		level = 1
		entry_upgrades = Vector3i.ONE
	reset()

func place_pickups() -> void:
	pickups.clear()
	place_pickup(Pickup.RUNNER, Vector2i(3 + level % 4, 8))
	place_pickup(Pickup.GRAY_TANK, Vector2i(17 - level % 4, 7))
	place_pickup(Pickup.BLACK_TANK, Vector2i(9 + level % 5, 4))

func place_pickup(kind: Pickup, anchor: Vector2i) -> void:
	var best := Vector2i.ZERO
	var best_distance := BOUNDS.get_area()
	for y in BOUNDS.size.y:
		for x in BOUNDS.size.x:
			var cell := Vector2i(x, y)
			if walls.has(cell) or pickups.has(cell) or rival_at(cell) != null:
				continue
			if cell in [START, PLAYER_BASE, ENEMY_BASE]:
				continue
			var distance := absi(x - anchor.x) + absi(y - anchor.y)
			if distance < best_distance:
				best = cell
				best_distance = distance
	pickups[best] = kind

func collect_pickup(cell: Vector2i) -> void:
	if not pickups.has(cell):
		return
	var kind := pickups[cell]
	pickups.erase(cell)
	match kind:
		Pickup.RUNNER:
			upgrades.x = mini(5, upgrades.x + 1)
		Pickup.GRAY_TANK:
			upgrades.y = mini(5, upgrades.y + 1)
		Pickup.BLACK_TANK:
			upgrades.z = mini(5, upgrades.z + 1)

func _process(delta: float) -> void:
	visual_time += delta
	turn_tank(player, delta)
	for enemy in rivals:
		turn_tank(enemy, delta)
	queue_redraw()

func turn_tank(tank: Tank, delta: float) -> void:
	var target := Vector2(tank.facing).angle() + PI / 2
	tank.angle = rotate_toward(tank.angle, target, 14.0 * delta)

func _physics_process(delta: float) -> void:
	if not result.is_empty():
		return
	elapsed += delta
	if elapsed < 0.06:
		return
	elapsed -= 0.06
	ticks += 1
	for shot in shots.duplicate():
		advance_shot(shot)
		if not result.is_empty():
			queue_redraw()
			return
	if ticks >= player.next_move:
		for index in ACTIONS.size():
			if Input.is_action_pressed(ACTIONS[index]):
				if move_tank(player, DIRECTIONS[index], MOVE_TICKS[upgrades.x - 1]):
					collect_pickup(player.cell)
				break
	if (fire_requested or Input.is_physical_key_pressed(KEY_SPACE)) and ticks >= player.reload:
		shots.append(Shot.new(player, true, upgrades.z))
		player.reload = ticks + RELOAD_TICKS[upgrades.y - 1]
		fire_requested = false
	for enemy in rivals:
		if ticks >= enemy.next_move:
			update_enemy(enemy)
	queue_redraw()

func move_tank(tank: Tank, direction: Vector2i, duration: int) -> bool:
	tank.facing = direction
	var next := tank.cell + direction
	if not BOUNDS.has_point(next) or walls.has(next):
		return false
	if next in [PLAYER_BASE, ENEMY_BASE, player.cell] or rival_at(next) != null:
		return false
	tank.previous_cell = tank.cell
	tank.move_started = visual_time
	tank.move_duration = duration * 0.06
	tank.track_distance += TILE
	tank.next_move = ticks + duration
	tank.cell = next
	return true

func rival_at(cell: Vector2i) -> Tank:
	for enemy in rivals:
		if enemy.cell == cell:
			return enemy
	return null

func update_enemy(enemy: Tank) -> void:
	var kind := ENEMY_TYPES[enemy.rank - 1]
	var target := PLAYER_BASE if kind == EnemyType.HEAVY or randf() < 0.55 else player.cell
	var offset := target - enemy.cell
	var horizontal := Vector2i(signi(offset.x), 0)
	var vertical := Vector2i(0, signi(offset.y))
	var direction := horizontal if abs(offset.x) > abs(offset.y) else vertical
	if randf() < 0.2:
		direction = DIRECTIONS.pick_random()
	var duration := ENEMY_MOVE_TICKS[kind]
	enemy.next_move = ticks + duration
	if not move_tank(enemy, direction, duration) and randf() < 0.5:
		move_tank(enemy, DIRECTIONS.pick_random(), duration)
	if ticks >= enemy.reload:
		shots.append(Shot.new(enemy, false, enemy.rank))
		enemy.reload = ticks + randi_range(16, 29) - mini(9, floori((level - 1) / 2.0))

func advance_shot(shot: Shot) -> void:
	shot.cell += shot.direction
	if not BOUNDS.has_point(shot.cell):
		shots.erase(shot)
	elif walls.has(shot.cell):
		hit_wall(shot)
		shots.erase(shot)
	elif shot.cell == PLAYER_BASE or shot.cell == ENEMY_BASE:
		shots.erase(shot)
		if shot.friendly and shot.cell == ENEMY_BASE:
			hit_base(true, shot.power)
		elif not shot.friendly and shot.cell == PLAYER_BASE:
			hit_base(false, shot.power)
	elif shot.friendly:
		var enemy := rival_at(shot.cell)
		if enemy != null:
			enemy.armor -= 1
			shots.erase(shot)
			if enemy.armor > 0:
				return
			rivals.erase(enemy)
			if rivals.is_empty():
				won = true
				result = "Victoria · Rivales eliminados"
	elif not shot.friendly and shot.cell == player.cell:
		result = "Derrota · Tu tanque fue destruido"
		shots.erase(shot)

func hit_wall(shot: Shot) -> void:
	if walls[shot.cell] == Wall.BRICK:
		var row_length := 1
		if shot.friendly and shot.power >= 2:
			row_length = 3 if shot.power == 5 else 2
		for step in row_length:
			var cell := shot.cell + shot.direction * step
			if not walls.has(cell) or walls[cell] != Wall.BRICK:
				break
			walls.erase(cell)
	elif shot.friendly and shot.power >= 3:
		if shot.power >= 4 or damaged_steel.has(shot.cell):
			walls.erase(shot.cell)
			damaged_steel.erase(shot.cell)
		else:
			damaged_steel[shot.cell] = true

func hit_base(enemy_base: bool, power: int) -> void:
	var armor := enemy_base_armor if enemy_base else player_base_armor
	if armor > 0:
		if power >= base_rank:
			if enemy_base:
				enemy_base_armor -= 1
			else:
				player_base_armor -= 1
		return
	won = enemy_base
	result = "Victoria · Base rival destruida" if won else "Derrota · Tu base fue destruida"

func cell_point(cell: Vector2i) -> Vector2:
	return ORIGIN + Vector2(cell * TILE)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 768, 122), Color("#39233f"))
	draw_circle(Vector2(651, 69), 43, Color("#f7a466"), true, -1.0, false)
	for index in 27:
		var height := 11 + (index * 19) % 43
		draw_rect(Rect2(index * 29, 122 - height, 27, height), Color("#251b33"))
	write(Vector2(32, 45), "Guardia del Ocaso", 33, Color("#ffe0ad"))
	write(Vector2(32, 76), "Mapa %d/%d   ·   Rivales %d   ·   Marcha %d   Cadencia %d   Cañón %d" % [
		level, MAPS.size(), rivals.size(), upgrades.x, upgrades.y, upgrades.z,
	], 18)
	if base_rank > 1:
		write(Vector2(32, 103), "Blindaje de base   ·   Aliado %d  Rival %d   ·   Cañón mínimo %d" % [
			player_base_armor, enemy_base_armor, base_rank,
		], 16)

	for y in BOUNDS.size.y:
		for x in BOUNDS.size.x:
			var point := cell_point(Vector2i(x, y))
			draw_rect(Rect2(point, Vector2(TILE, TILE)), Color("#292637") if (x + y) % 2 == 0 else Color("#2e293b"))
	for cell in walls:
		var point := cell_point(cell)
		if walls[cell] == Wall.STEEL:
			draw_steel(point, damaged_steel.has(cell))
			continue
		draw_rect(Rect2(point + Vector2.ONE, Vector2(30, 30)), Color("#633244"))
		for row in 3:
			for column in 2:
				draw_rect(Rect2(point + Vector2(2 + column * 15, 3 + row * 9), Vector2(13, 7)), Color("#a45752"))
	draw_base(PLAYER_BASE, Color("#85bda5"), player_base_armor)
	draw_base(ENEMY_BASE, Color("#df7864"), enemy_base_armor)
	for cell in pickups:
		draw_pickup(cell, pickups[cell])
	draw_tank(player, Color("#85bda5"), upgrades.z)
	for enemy in rivals:
		draw_tank(enemy, Color("#df7864"), enemy.rank)
	for shot in shots:
		var center := cell_point(shot.cell) + Vector2(16, 16)
		draw_rect(Rect2(center - Vector2(3, 3), Vector2(6, 6)), Color("#fff2b2") if shot.friendly else Color("#ff9567"))
	write(Vector2(32, 538), "Corredor  Marcha      Tanque gris  Cadencia      Tanque negro  Potencia", 15)
	write(Vector2(32, 561), "Flechas  mover      Espacio  disparar      R  reiniciar", 15)
	if not result.is_empty():
		draw_rect(Rect2(104, 246, 560, 111), Color("#1d152a"))
		var font := ThemeDB.fallback_font
		var width := font.get_string_size(result, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		write(Vector2((768 - width) / 2, 293), result, 30, Color("#ffe0ad"))
		var prompt := "R  Reintentar nivel"
		if won:
			prompt = "Intro  Siguiente nivel   ·   R  Repetir" if level < MAPS.size() else "Campaña completada   ·   Intro  Volver al nivel 1"
		var prompt_width := font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		write(Vector2((768 - prompt_width) / 2, 326), prompt, 18)

func draw_steel(point: Vector2, damaged: bool) -> void:
	draw_rect(Rect2(point + Vector2.ONE, Vector2(30, 30)), Color("#414f65"))
	draw_rect(Rect2(point + Vector2(4, 4), Vector2(24, 24)), Color("#8296a9"))
	draw_rect(Rect2(point + Vector2(7, 7), Vector2(18, 18)), Color("#9c604d") if damaged else Color("#617487"))
	for offset in [Vector2(5, 5), Vector2(24, 5), Vector2(5, 24), Vector2(24, 24)]:
		draw_rect(Rect2(point + offset, Vector2(3, 3)), Color("#bacad6"))

func draw_base(cell: Vector2i, color: Color, armor: int) -> void:
	var point := cell_point(cell)
	draw_rect(Rect2(point + Vector2(2, 2), Vector2(28, 28)), Color("#a9bac9") if armor > 0 else Color("#4e5268"))
	draw_rect(Rect2(point + Vector2(7, 7), Vector2(18, 18)), color)
	draw_rect(Rect2(point + Vector2(13, 10), Vector2(6, 12)), Color("#39233f"))

func draw_pickup(cell: Vector2i, kind: Pickup) -> void:
	var center := cell_point(cell) + Vector2(16, 16)
	draw_circle(center, 12, Color("#e9cf9a"))
	draw_circle(center, 10, Color("#24243a") if kind != Pickup.BLACK_TANK else Color("#f0e1c3"))
	var ink := PICKUP_COLORS[kind]
	if kind == Pickup.RUNNER:
		draw_circle(center + Vector2(4, -6), 2, ink)
		draw_polyline(PackedVector2Array([center + Vector2(-5, 6), center, center + Vector2(3, -3), center + Vector2(7, 0)]), ink, 2)
		draw_polyline(PackedVector2Array([center + Vector2(-5, -1), center + Vector2(-2, -3), center + Vector2(3, -3)]), ink, 2)
		draw_polyline(PackedVector2Array([center, center + Vector2(4, 2), center + Vector2(6, 6)]), ink, 2)
	else:
		draw_rect(Rect2(center + Vector2(-6, -3), Vector2(12, 8)), ink)
		draw_rect(Rect2(center + Vector2(-4, -5), Vector2(8, 2)), ink)
		draw_rect(Rect2(center + Vector2(-1, -8), Vector2(2, 4)), ink)

func draw_tank(tank: Tank, color: Color, rank: int) -> void:
	var progress := 1.0
	if tank.move_duration > 0.0:
		progress = clampf((visual_time - tank.move_started) / tank.move_duration, 0.0, 1.0)
	var center := cell_point(tank.previous_cell).lerp(cell_point(tank.cell), progress) + Vector2(16, 16)
	draw_set_transform(center, tank.angle)
	var half_width := 10 + mini(rank, 4)
	var track_length := 18 + rank * 2
	var track_offset := fposmod(tank.track_distance - TILE * (1.0 - progress), 5.0)
	for side in [-1, 1]:
		var edge: float = float(side) * (half_width - 3) - 3
		draw_rect(Rect2(edge, -track_length * 0.5, 6, track_length), Color("#171923"))
		for step in range(-15, 16, 5):
			var belt_y := float(step) + track_offset
			if absf(belt_y) < track_length * 0.5 - 1.5:
				draw_line(Vector2(edge + 1, belt_y), Vector2(edge + 5, belt_y), Color("#777f85"), 1.5)
	var hull_length := 16 + rank * 2
	draw_rect(Rect2(-half_width + 5, -hull_length * 0.5, (half_width - 5) * 2, hull_length), color.darkened(0.32))
	match rank:
		1:
			draw_circle(Vector2(0, -1), 5, color)
		2:
			draw_rect(Rect2(-6, -6, 12, 11), color)
		3:
			draw_colored_polygon(PackedVector2Array([Vector2(-7, 4), Vector2(-6, -6), Vector2(6, -6), Vector2(7, 4), Vector2(0, 8)]), color)
		4:
			draw_rect(Rect2(-8, -7, 16, 14), color)
			draw_rect(Rect2(-5, -7, 10, 12), color.lightened(0.24))
		5:
			draw_colored_polygon(PackedVector2Array([Vector2(-9, 5), Vector2(-9, -4), Vector2(-5, -8), Vector2(5, -8), Vector2(9, -4), Vector2(9, 5), Vector2(0, 9)]), color)
			draw_rect(Rect2(-5, 3, 10, 3), color.lightened(0.3))
	var barrel := 2 + rank
	draw_rect(Rect2(-barrel * 0.5, -15, barrel, 13), color.lightened(0.27))
	draw_set_transform(Vector2.ZERO)

func write(point: Vector2, label: String, size: int, color := Color("#e4cccb")) -> void:
	draw_string(ThemeDB.fallback_font, point, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
