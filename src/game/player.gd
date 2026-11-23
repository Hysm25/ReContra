class_name Player
extends RefCounted

const CollisionGridScript = preload("res://src/game/collision.gd")

## Generic NES Contra Player State Machine & Kinematics
## Emulates 8-direction aiming, running, ducking, parabolic jump (-5.9375 impulse, +0.1367 gravity),
## water swim/dive, damage recoil arc, and Bank 1 $B030 OAM sprite frame unpacking.

# --- Constants: Gameplay Tuning ---
const DEFAULT_LIVES: int = 3
const KONAMI_LIVES: int = 30
const DEFAULT_SPAWN_X: int = 48
const DEFAULT_SPAWN_Y: int = 16
const INVINCIBLE_RESPAWN: int = 180

# --- Constants: Authentic NES Contra Jump Physics ---
const JUMP_VEL_FAST_OUTDOOR: int = -5
const JUMP_VEL_FRACT_OUTDOOR: int = 0xF0 # -5.9375 px/frame initial impulse
const GRAVITY_ACCEL_FRACT: int = 0x23    # +0.1367 px/frame^2 gravity

# --- Constants: Controller Input Bitmask ---
const INPUT_RIGHT: int = 0x01
const INPUT_LEFT: int = 0x02
const INPUT_DOWN: int = 0x04
const INPUT_UP: int = 0x08
const INPUT_START: int = 0x10
const INPUT_SELECT: int = 0x20
const INPUT_B: int = 0x40
const INPUT_A: int = 0x80

# --- Constants: Authentic NES Aim Directions ($C2) ---
const AIM_DIR_UP_FACING_RIGHT: int = 0x00
const AIM_DIR_UP_RIGHT: int = 0x01
const AIM_DIR_RIGHT: int = 0x02
const AIM_DIR_DOWN_RIGHT: int = 0x03
const AIM_DIR_CROUCH_RIGHT: int = 0x04
const AIM_DIR_CROUCH_LEFT: int = 0x05
const AIM_DIR_DOWN_LEFT: int = 0x06
const AIM_DIR_LEFT: int = 0x07
const AIM_DIR_UP_LEFT: int = 0x08
const AIM_DIR_UP_FACING_LEFT: int = 0x09
const AIM_DIR_DOWN_AIR: int = 0x0A

# --- Constants: State Enum ---
enum State {
	SPAWNING = 0,
	NORMAL = 1,
	DYING = 2,
	DEAD = 3,
	GAMEOVER = 4
}

# --- Constants: ROM Memory Addresses ---
const AIM_TABLE_ROM_OFFSET: int = 0x1D93A # Bank 7 CPU $D93A
const SPRITE_PTR_TBL_0_ADDR: int = 0xB030 # Bank 1 CPU $B030
const SPRITE_BANK: int = 1

# --- Player State Properties ---
var player_id: int = 0
var state: int = State.SPAWNING

var world_x: int = DEFAULT_SPAWN_X
var world_y: int = DEFAULT_SPAWN_Y
var screen_x: int = DEFAULT_SPAWN_X
var screen_y: int = DEFAULT_SPAWN_Y

var vel_x: int = 0
var vel_y_fast: int = 0
var vel_y_fract: int = 0
var jump_accum: int = 0

var is_jumping: bool = false
var is_crouching: bool = false
var facing_left: bool = false
var aim_dir: int = AIM_DIR_RIGHT
var water_state: int = 0 # 0 = Dry land, 1 = Surface swim, 2 = Submerged dive
var edge_fall_code: int = 0

var invincibility_timer: int = INVINCIBLE_RESPAWN
var lives: int = DEFAULT_LIVES
var current_weapon: int = 0 # 0 = Standard Rifle
var m_fire_timer: int = 0

var anim_timer: int = 0
var anim_frame: int = 0
var sprite_sequence: int = 0

var rom_loader: RefCounted = null


func _init(id: int = 0, rom: RefCounted = null) -> void:
	init_player(id, rom)


## Initializes player with identity and ROM reference
func init_player(id: int, rom: RefCounted) -> void:
	player_id = id
	lives = DEFAULT_LIVES
	current_weapon = 0
	rom_loader = rom
	spawn(DEFAULT_SPAWN_X + id * 32, DEFAULT_SPAWN_Y)


## Resets player coordinates and state on stage spawn or respawn
func spawn(spawn_x: int, spawn_y: int) -> void:
	world_x = spawn_x
	world_y = spawn_y
	screen_x = spawn_x & 0xFF
	screen_y = spawn_y & 0xFF

	vel_x = 0
	vel_y_fast = 0
	vel_y_fract = 0
	jump_accum = 0

	is_jumping = false
	is_crouching = false
	facing_left = false
	aim_dir = AIM_DIR_RIGHT
	water_state = 0
	edge_fall_code = 0

	invincibility_timer = INVINCIBLE_RESPAWN
	m_fire_timer = 0
	anim_timer = 0
	anim_frame = 0
	sprite_sequence = 0
	state = State.SPAWNING


## Inflicts damage, reducing lives and transitioning to dying recoil arc
func take_hit(apu: RefCounted = null, sound: RefCounted = null) -> void:
	if invincibility_timer > 0:
		return
	if state != State.NORMAL and state != State.SPAWNING:
		return

	if lives > 0:
		lives -= 1

	state = State.GAMEOVER if lives == 0 else State.DYING

	# Backward recoil arc impulse
	vel_y_fast = -4
	vel_y_fract = 0
	vel_x = 1 if facing_left else -1
	is_jumping = true

	if sound != null and apu != null:
		sound.play_sound(apu, 0x52) # Death SFX


## Advances player state machine by one 60 Hz frame
func update_player(input: int, input_diff: int, camera_scroll_x: int, grid: RefCounted,
		apu: RefCounted = null, sound: RefCounted = null) -> void:
	if state == State.GAMEOVER:
		return

	if invincibility_timer > 0:
		invincibility_timer -= 1

	# 1. Spawning / Dropping into Stage
	if state == State.SPAWNING:
		vel_y_fast = 2
		world_y += 2

		var feet_code: int = grid.get_code(world_x + 8, world_y + 32)
		if feet_code == CollisionGridScript.COLLISION_CODE_FLOOR:
			var check_y: int = world_y + 32
			if check_y >= 16 and check_y < 240:
				var row: int = int((check_y - 16) / 16)
				world_y = 16 + row * 16 - 32
			state = State.NORMAL
			vel_y_fast = 0
			is_jumping = false
			if sound != null and apu != null:
				sound.play_sound(apu, 0x03) # Landing SFX

		world_x = clampi(world_x, camera_scroll_x, camera_scroll_x + 240)
		screen_x = (world_x - camera_scroll_x) & 0xFF
		screen_y = world_y & 0xFF
		return

	# 2. Dying Animation Arc
	if state == State.DYING:
		var grav_sum: int = vel_y_fract + GRAVITY_ACCEL_FRACT
		vel_y_fract = grav_sum & 0xFF
		vel_y_fast += grav_sum >> 8

		world_y += vel_y_fast
		world_x += vel_x

		if world_y >= 235:
			if lives > 0:
				spawn(camera_scroll_x + 48, DEFAULT_SPAWN_Y)
			else:
				state = State.GAMEOVER

		world_x = clampi(world_x, camera_scroll_x, camera_scroll_x + 240)
		screen_x = (world_x - camera_scroll_x) & 0xFF
		screen_y = world_y & 0xFF
		return

	# 3. Normal Gameplay State
	if state == State.NORMAL:
		# 3.1 Aim Direction & Facing Resolution from Bank 7 $D93A
		var aim_table_row: int = 0
		if is_jumping:
			aim_table_row = 0x30
		elif facing_left:
			aim_table_row = 0x10

		var dpad: int = input & 0x0F
		var aim_resolved: bool = false
		if rom_loader != null:
			var prg_rom: PackedByteArray = rom_loader.get_prg_rom()
			var aim_offset: int = AIM_TABLE_ROM_OFFSET + aim_table_row + dpad
			if aim_offset < prg_rom.size():
				aim_dir = prg_rom[aim_offset]
				aim_resolved = true

		if not aim_resolved:
			# Fallback 8-direction aim calculation
			if (dpad & INPUT_UP) != 0:
				if (dpad & INPUT_RIGHT) != 0:
					aim_dir = AIM_DIR_UP_RIGHT
				elif (dpad & INPUT_LEFT) != 0:
					aim_dir = AIM_DIR_UP_LEFT
				else:
					aim_dir = AIM_DIR_UP_FACING_LEFT if facing_left else AIM_DIR_UP_FACING_RIGHT
			elif (dpad & INPUT_DOWN) != 0:
				if (dpad & INPUT_RIGHT) != 0:
					aim_dir = AIM_DIR_DOWN_RIGHT
				elif (dpad & INPUT_LEFT) != 0:
					aim_dir = AIM_DIR_DOWN_LEFT
				else:
					aim_dir = AIM_DIR_CROUCH_LEFT if facing_left else AIM_DIR_CROUCH_RIGHT
			elif (dpad & INPUT_LEFT) != 0:
				aim_dir = AIM_DIR_LEFT
			else:
				aim_dir = AIM_DIR_RIGHT

		if (dpad & INPUT_LEFT) != 0:
			facing_left = true
		elif (dpad & INPUT_RIGHT) != 0:
			facing_left = false

		# 3.2 Water State Handling
		if water_state > 0:
			if (input & INPUT_DOWN) != 0:
				water_state = 2 # Submerged dive
				vel_x = 0
			else:
				water_state = 1 # Surface swimming
				if (input & INPUT_RIGHT) != 0:
					vel_x = 1
				elif (input & INPUT_LEFT) != 0:
					vel_x = -1
				else:
					vel_x = 0
			is_jumping = false
			is_crouching = false
		else:
			# 3.3 Land Movement, Jump & Crouch
			if ((input_diff & INPUT_A) != 0) and ((input & INPUT_A) != 0):
				if (input & 0x07) == INPUT_DOWN:
					# Down + Jump: Drop Down through floor
					if grid.can_drop_down(world_x + 8, world_y):
						edge_fall_code = 12
						is_jumping = true
						is_crouching = false
						vel_y_fast = 1
						vel_y_fract = 0
				elif not is_jumping:
					# Authentic Initial Jump Impulse: -5.9375 px/frame
					is_jumping = true
					is_crouching = false
					vel_y_fast = JUMP_VEL_FAST_OUTDOOR
					vel_y_fract = JUMP_VEL_FRACT_OUTDOOR
					jump_accum = 0

					if sound != null and apu != null:
						sound.play_sound(apu, 0x03) # Jump sound

			if not is_jumping:
				if (input & 0x0F) == INPUT_DOWN:
					is_crouching = true
					vel_x = 0
					anim_timer = 0
					anim_frame = 0
				else:
					is_crouching = false
					if (input & INPUT_RIGHT) != 0:
						vel_x = 1
					elif (input & INPUT_LEFT) != 0:
						vel_x = -1
					else:
						vel_x = 0

					if vel_x != 0:
						anim_timer += 1
						if (anim_timer & 0x07) == 0:
							anim_frame = (anim_frame + 1) % 6
					else:
						anim_timer = 0
						anim_frame = 0
			else:
				# Mid-air steering
				anim_timer += 1
				if (input & INPUT_RIGHT) != 0:
					vel_x = 1
				elif (input & INPUT_LEFT) != 0:
					vel_x = -1
				else:
					vel_x = 0

		# 3.4 Horizontal Motion & Wall Collision
		if vel_x != 0:
			var next_x: int = world_x + vel_x
			if next_x < camera_scroll_x:
				world_x = camera_scroll_x
			else:
				var side_x: int = 16 if vel_x > 0 else 0
				var wall_code: int = grid.get_code(next_x + side_x, world_y + 16)
				if wall_code != CollisionGridScript.COLLISION_CODE_SOLID:
					world_x = next_x

		# 3.5 Vertical Motion, Gravity & Floor Collision
		if is_jumping or edge_fall_code > 0:
			var grav_sum: int = vel_y_fract + GRAVITY_ACCEL_FRACT
			vel_y_fract = grav_sum & 0xFF
			vel_y_fast += grav_sum >> 8

			var y_accum: int = jump_accum + vel_y_fract
			jump_accum = y_accum & 0xFF
			var delta_y: int = vel_y_fast + (y_accum >> 8)
			world_y += delta_y

			if edge_fall_code > 0:
				edge_fall_code -= 1

			# Landing check when descending
			if vel_y_fast >= 0 and edge_fall_code == 0:
				var feet_code: int = grid.get_code(world_x + 8, world_y + 32)
				if feet_code == CollisionGridScript.COLLISION_CODE_FLOOR:
					var check_y: int = world_y + 32
					if check_y >= 16 and check_y < 240:
						var floor_row: int = int((check_y - 16) / 16)
						world_y = 16 + floor_row * 16 - 32
					is_jumping = false
					vel_y_fast = 0
					vel_y_fract = 0

					if sound != null and apu != null:
						sound.play_sound(apu, 0x03) # Landing SFX
				elif feet_code == CollisionGridScript.COLLISION_CODE_WATER:
					water_state = 1
					is_jumping = false
					vel_y_fast = 0
					vel_y_fract = 0
		elif water_state == 0:
			# Check walking off ledge
			var feet_code: int = grid.get_code(world_x + 8, world_y + 33)
			if feet_code == CollisionGridScript.COLLISION_CODE_EMPTY:
				is_jumping = true
				vel_y_fast = 0
				vel_y_fract = 0
			elif feet_code == CollisionGridScript.COLLISION_CODE_WATER:
				water_state = 1

		# 3.6 Bottom Pit / Death Check
		if world_y >= 235:
			take_hit(apu, sound)

		world_x = clampi(world_x, camera_scroll_x, camera_scroll_x + 240)
		screen_x = (world_x - camera_scroll_x) & 0xFF
		screen_y = world_y & 0xFF


## Renders player sprites into 256-byte OAM buffer ($0200-$02FF)
func render_oam(oam_buffer: PackedByteArray, oam_entry_start: int) -> void:
	if oam_buffer.size() < 256 or state == State.GAMEOVER:
		return

	# Invincibility flicker: hide every second frame
	if invincibility_timer > 0 and (invincibility_timer & 0x02) != 0:
		return

	var sprite_code: int = 0x0F # Default standing idle
	if state == State.DYING:
		sprite_code = 0x0A # Dying arc
	elif water_state > 0:
		sprite_code = 0x19 if water_state == 2 else 0x1D
	elif is_jumping or edge_fall_code > 0:
		# Somersault curled in air: alternate 0x08 and 0x09 every 6 frames
		sprite_code = 0x09 if ((anim_timer / 6) & 1) != 0 else 0x08
	elif is_crouching:
		sprite_code = 0x17 # Prone crouching
	elif vel_x != 0:
		var run_sprites: Array[int] = [0x02, 0x03, 0x04, 0x05, 0x03, 0x06]
		sprite_code = run_sprites[anim_frame % 6]
	else:
		if aim_dir == AIM_DIR_UP_FACING_RIGHT or aim_dir == AIM_DIR_UP_FACING_LEFT:
			sprite_code = 0x16 # Aim straight up
		else:
			sprite_code = 0x0F # Standing

	# Unpack dynamic sprite definitions from Bank 1 sprite_ptr_tbl_0 ($B030)
	if rom_loader != null:
		var ptr_entry: int = SPRITE_PTR_TBL_0_ADDR + (sprite_code - 1) * 2
		var sprite_addr: int = rom_loader.read_cpu_word(ptr_entry, SPRITE_BANK)

		if sprite_addr >= 0x8000:
			var num_tiles: int = rom_loader.read_cpu(sprite_addr, SPRITE_BANK)
			if num_tiles > 0 and num_tiles < 16:
				var read_addr: int = sprite_addr + 1
				var tiles_written: int = 0
				var oam_idx: int = oam_entry_start

				while tiles_written < num_tiles and oam_idx < 64:
					var b0: int = rom_loader.read_cpu(read_addr, SPRITE_BANK)
					read_addr += 1

					if b0 == 0x80:
						# Shared sprite continuation address
						var sub_addr: int = rom_loader.read_cpu_word(read_addr, SPRITE_BANK)
						read_addr = sub_addr
						continue

					var rel_y: int = b0 if b0 < 128 else b0 - 256
					var tile_idx: int = rom_loader.read_cpu(read_addr, SPRITE_BANK)
					read_addr += 1
					var tile_attr: int = rom_loader.read_cpu(read_addr, SPRITE_BANK)
					read_addr += 1
					var b3: int = rom_loader.read_cpu(read_addr, SPRITE_BANK)
					read_addr += 1
					var rel_x: int = b3 if b3 < 128 else b3 - 256

					var sy: int = screen_y + rel_y
					var sx: int = 0
					var out_attr: int = (tile_attr & 0xFC) | (player_id & 0x03)

					if facing_left:
						out_attr ^= 0x40
						sx = screen_x + (-8 - rel_x)
					else:
						sx = screen_x + rel_x

					if sy >= -16 and sy < 240 and sx >= -16 and sx < 256:
						var oam_byte: int = oam_idx * 4
						oam_buffer[oam_byte + 0] = sy & 0xFF
						oam_buffer[oam_byte + 1] = tile_idx
						oam_buffer[oam_byte + 2] = out_attr
						oam_buffer[oam_byte + 3] = sx & 0xFF
						oam_idx += 1
					tiles_written += 1
				return

	# Fallback rendering if ROM is unlinked
	var oam_offset: int = oam_entry_start * 4
	if oam_offset + 8 > 256:
		return

	var fallback_attr: int = (0x40 if facing_left else 0x00) | (player_id & 0x03)
	var fallback_tile: int = 0x00
	if water_state > 0:
		fallback_tile = 0xDE
		oam_buffer[oam_offset + 0] = screen_y
		oam_buffer[oam_offset + 1] = fallback_tile
		oam_buffer[oam_offset + 2] = fallback_attr
		oam_buffer[oam_offset + 3] = screen_x
	else:
		if is_jumping:
			fallback_tile = 0x44
		elif is_crouching:
			fallback_tile = 0x9C
		oam_buffer[oam_offset + 0] = screen_y
		oam_buffer[oam_offset + 1] = fallback_tile
		oam_buffer[oam_offset + 2] = fallback_attr
		oam_buffer[oam_offset + 3] = screen_x

		oam_buffer[oam_offset + 4] = (screen_y + 16) & 0xFF
		oam_buffer[oam_offset + 5] = (fallback_tile + 2) & 0xFF
		oam_buffer[oam_offset + 6] = fallback_attr
		oam_buffer[oam_offset + 7] = screen_x
