class_name CollisionGrid
extends RefCounted

## Generic Background Collision Grid
## Unpacks 128-byte background collision data ($0680-$06FF) from screen supertiles.
## Supports 2-bit collision codes per 16x16 block:
##   0: Empty (passable)
##   1: Floor (can land, drop through with Down + Jump)
##   2: Water (half-submerged, disables jumping)
##   3: Solid (impassable barrier)

const BG_COLLISION_DATA_SIZE: int = 128
const COLLISION_ROWS_PER_SCREEN: int = 14
const COLLISION_COLS_PER_SCREEN: int = 16
const COLLISION_BYTES_PER_ROW: int = 4

const COLLISION_CODE_EMPTY: int = 0x00
const COLLISION_CODE_FLOOR: int = 0x01
const COLLISION_CODE_WATER: int = 0x02
const COLLISION_CODE_SOLID: int = 0x03

var data: PackedByteArray = PackedByteArray()
var screen_indices: Array[int] = [0, 0]
var screen_loaded: Array[bool] = [false, false]


func _init() -> void:
	init_grid()


## Resets collision grid buffers
func init_grid() -> void:
	data = PackedByteArray()
	data.resize(BG_COLLISION_DATA_SIZE)
	data.fill(0)
	screen_indices = [0, 0]
	screen_loaded = [false, false]


## Maps tile index against stage collision limits to determine collision code
static func determine_tile_code(tile_idx: int, limits: PackedByteArray) -> int:
	if tile_idx == 0:
		return COLLISION_CODE_EMPTY
	if limits.size() < 3:
		return COLLISION_CODE_EMPTY
	if tile_idx < limits[0]:
		return COLLISION_CODE_FLOOR
	if tile_idx < limits[1]:
		return COLLISION_CODE_EMPTY
	if tile_idx < limits[2]:
		return COLLISION_CODE_WATER
	return COLLISION_CODE_SOLID


## Unpacks screen supertiles into a 64-byte half of the collision grid (NT0 or NT1)
func unpack_screen(rom: RefCounted, header: RefCounted, screen_index: int, nametable_index: int) -> bool:
	if rom == null or header == null or nametable_index > 1:
		return false

	var LevelLoaderScript = preload("res://scripts/rom/level_loader.gd")
	var supertiles: PackedByteArray = LevelLoaderScript.decompress_screen_supertiles(rom, header, screen_index)
	if supertiles.is_empty():
		return false

	var base_grid_offset: int = 0x40 if nametable_index == 1 else 0x00
	for i in range(56):
		data[base_grid_offset + i] = 0

	# 7 supertile rows x 8 supertile cols = 56 supertiles per screen
	# Each supertile produces 2x2 collision points (14 collision rows x 16 collision cols)
	for sr in range(7):
		for sc in range(8):
			var supertile_idx: int = sr * 8 + sc
			if supertile_idx >= supertiles.size():
				break
			var supertile_id: int = supertiles[supertile_idx]

			var st_tiles: PackedByteArray = LevelLoaderScript.read_supertile(rom, header.supertile_ptr, supertile_id)
			if st_tiles.size() < 16:
				return false

			# 4 quadrants: (0,0), (0,2), (2,0), (2,2)
			var q0: int = determine_tile_code(st_tiles[0], header.collision_limits)
			var q1: int = determine_tile_code(st_tiles[2], header.collision_limits)
			var q2: int = determine_tile_code(st_tiles[8], header.collision_limits)
			var q3: int = determine_tile_code(st_tiles[10], header.collision_limits)

			# Top half of supertile: row = sr * 2
			var r_top: int = sr * 2
			var c_left: int = sc * 2
			var c_right: int = c_left + 1

			var byte_idx_top: int = base_grid_offset + r_top * COLLISION_BYTES_PER_ROW + int(c_left / 4)
			var shift_q0: int = (3 - (c_left % 4)) * 2
			var shift_q1: int = (3 - (c_right % 4)) * 2
			data[byte_idx_top] |= (q0 << shift_q0) | (q1 << shift_q1)

			# Bottom half of supertile: row = sr * 2 + 1
			var r_bot: int = r_top + 1
			var byte_idx_bot: int = base_grid_offset + r_bot * COLLISION_BYTES_PER_ROW + int(c_left / 4)
			data[byte_idx_bot] |= (q2 << shift_q0) | (q3 << shift_q1)

	screen_indices[nametable_index] = screen_index
	screen_loaded[nametable_index] = true
	return true


## Queries collision point code at absolute world coordinates
func get_code(world_x: int, world_y: int) -> int:
	if world_y < 16 or world_y >= 240:
		return COLLISION_CODE_EMPTY

	var row: int = int((world_y - 16) / 16)
	if row >= COLLISION_ROWS_PER_SCREEN:
		return COLLISION_CODE_EMPTY

	var scroll_x: int = world_x % 512
	var nt_idx: int = int(scroll_x / 256)
	var col_in_screen: int = int((scroll_x % 256) / 16)

	var target_screen: int = int(world_x / 256)
	if not screen_loaded[nt_idx] or screen_indices[nt_idx] != target_screen:
		return COLLISION_CODE_EMPTY

	var base_offset: int = 0x40 if nt_idx == 1 else 0x00
	var byte_idx: int = base_offset + row * COLLISION_BYTES_PER_ROW + int(col_in_screen / 4)
	if byte_idx >= data.size():
		return COLLISION_CODE_EMPTY

	var shift: int = (3 - (col_in_screen % 4)) * 2
	return (data[byte_idx] >> shift) & 0x03


## Tests whether a lower floor exists beneath the player to permit Down + Jump drop-down
func can_drop_down(world_x: int, world_y: int) -> bool:
	if world_y < 16 or world_y >= 240:
		return false

	var cur_row: int = int((world_y - 16) / 16)
	for r in range(cur_row + 1, COLLISION_ROWS_PER_SCREEN):
		var check_y: int = 16 + r * 16 + 8
		var code: int = get_code(world_x, check_y)
		if code == COLLISION_CODE_FLOOR:
			return true
		if code == COLLISION_CODE_SOLID:
			return false
	return false
