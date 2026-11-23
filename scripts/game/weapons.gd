class_name BulletPool
extends RefCounted

const CollisionGridScript = preload("res://scripts/game/collision.gd")

## Generic 16-Slot Bullet Pool & Ballistics Engine
## Emulates 16 slots ($0368-$04B7) matching NES Contra memory buffers.
## Dynamically resolves Bank 6 trajectory, velocity, aim, sound, and sprite tables:
##   - Standard Rifle (limit: 4 simultaneous, 3 px/frame)
##   - Machine Gun (M, continuous stream governed by m_fire_timer, limit: 6)
##   - Fireball (F, swirling circular trajectory with 16-step phase tables)
##   - Spread Gun (S, 5-way angled bullet fan with distance-based scaling)
##   - Laser Gun (L, 4 sequential segments with staggered delay timers)
##   - Rapid Fire (R, velocity upgrade modifier)
##   - Barrier (B, invincibility state)

const BULLET_POOL_MAX_SLOTS: int = 16

const WEAPON_TYPE_STANDARD: int = 0
const WEAPON_TYPE_RAPID: int = 1
const WEAPON_TYPE_FIREBALL: int = 2
const WEAPON_TYPE_SPREAD: int = 3
const WEAPON_TYPE_BEAM: int = 4

const WEAPON_MODIFIER_RAPID_FIRE: int = 0x10
const WEAPON_MODIFIER_BARRIER: int = 0x20

const BULLET_ROUTINE_INACTIVE: int = 0
const BULLET_ROUTINE_INIT: int = 1
const BULLET_ROUTINE_MOVING: int = 2
const BULLET_ROUTINE_IMPACT: int = 3

# Bank 6 Table CPU Addresses
const ROM_POS_OFFSET_GROUND: int = 0x1B5FA     # CPU $B5FA: 20 bytes
const ROM_POS_OFFSET_AIR: int = 0x1B60E        # CPU $B60E: 24 bytes
const ROM_VEL_STD_NORMAL: int = 0x1B6E9        # CPU $B6E9: 48 bytes
const ROM_VEL_STD_RAPID: int = 0x1B719         # CPU $B719: 48 bytes
const ROM_VEL_F_NORMAL: int = 0x1B779          # CPU $B779: 48 bytes
const ROM_VEL_F_RAPID: int = 0x1B749           # CPU $B749: 48 bytes
const ROM_F_INIT_TABLE: int = 0x1B817          # CPU $B817: 36 bytes
const ROM_F_SWIRL_Y: int = 0x1BADE             # CPU $BADE: 16 bytes
const ROM_F_SWIRL_X: int = 0x1BAE2             # CPU $BAE2: 16 bytes
const ROM_AIM_DIR_TO_S_INDEX: int = 0x1B891    # CPU $B891: 12 bytes
const ROM_S_INDEX_MODIFIERS: int = 0x1B89D     # CPU $B89D: 5 bytes
const ROM_S_VEL_NORMAL_Y: int = 0x1B8AA        # CPU $B8AA: 16 bytes
const ROM_S_VEL_NORMAL_X: int = 0x1B8BA        # CPU $B8BA: 64 bytes
const ROM_S_VEL_RAPID_Y: int = 0x1B8FA         # CPU $B8FA: 16 bytes
const ROM_S_VEL_RAPID_X: int = 0x1B90A         # CPU $B90A: 64 bytes
const ROM_BEAM_DELAYS: int = 0x1B55D           # CPU $B55D: 8 bytes
const ROM_BEAM_SPRITES: int = 0x1BA17          # CPU $BA17: 24 bytes
const ROM_WEAPON_SOUNDS: int = 0x1B5A7         # CPU $B5A7: 5 bytes
const ROM_WEAPON_SPRITES: int = 0x1B5AB        # CPU $B5AB: 6 bytes

class BulletSlot extends RefCounted:
	var slot_type: int = 0       # $0388: 0 = empty, 1 = Std, 2 = M, 3 = F, 4 = S, 5 = L
	var sprite_code: int = 0     # $0368: PPU pattern / sprite index
	var sprite_attr: int = 0     # $0378: OAM attributes (flip, palette)
	var vel_y_accum: int = 0     # $0398: Sub-pixel Y velocity accumulator
	var vel_x_accum: int = 0     # $03A8: Sub-pixel X velocity accumulator
	var pos_y: int = 0           # $03B8: Screen Y position
	var pos_x: int = 0           # $03C8: Screen X position
	var vel_y_fract: int = 0     # $03D8: Fractional Y velocity
	var vel_x_fract: int = 0     # $03E8: Fractional X velocity
	var vel_y_fast: int = 0      # $03F8: Integer Y velocity
	var vel_x_fast: int = 0      # $0408: Integer X velocity
	var timer: int = 0           # $0418: Delay timer / swirl phase / impact decay
	var aim_dir: int = 0         # $0428: Aim direction
	var routine: int = 0         # $0438: 0: Inactive, 1: Init, 2: Moving, 3: Impact
	var owner: int = 0           # $0448: 0 = Player 1, 1 = Player 2
	var rapid_flag: int = 0      # $0458: Rapid fire modifier active
	var dist: int = 0            # $0468: Travel distance (for S sprite scaling)
	var fs_x: int = 0            # $0478: Center X position for swirl trajectory
	var f_y: int = 0             # $0488: Center Y position for swirl trajectory
	var vel_fs_x_accum: int = 0  # $0498: Center X accumulator
	var vel_f_y_accum: int = 0   # $04A8: Center Y accumulator

	func reset() -> void:
		slot_type = 0
		sprite_code = 0
		sprite_attr = 0
		vel_y_accum = 0
		vel_x_accum = 0
		pos_y = 0
		pos_x = 0
		vel_y_fract = 0
		vel_x_fract = 0
		vel_y_fast = 0
		vel_x_fast = 0
		timer = 0
		aim_dir = 0
		routine = 0
		owner = 0
		rapid_flag = 0
		dist = 0
		fs_x = 0
		f_y = 0
		vel_fs_x_accum = 0
		vel_f_y_accum = 0


var slots: Array[BulletSlot] = []
var prg_rom: PackedByteArray = PackedByteArray()
var authentic_flicker: bool = false


func _init(rom: RefCounted = null) -> void:
	slots.resize(BULLET_POOL_MAX_SLOTS)
	for i in range(BULLET_POOL_MAX_SLOTS):
		slots[i] = BulletSlot.new()
	if rom != null:
		init_pool(rom)


## Initializes bullet pool with ROM reference and verifies Bank 6 tables
func init_pool(rom: RefCounted) -> bool:
	if rom == null:
		return false
	prg_rom = rom.get_prg_rom()
	if prg_rom.size() < 131072:
		return false
	clear_pool()
	return true


## Clears all bullet slots
func clear_pool() -> void:
	for slot in slots:
		slot.reset()


## Helper: converts unsigned 8-bit byte to signed int (-128..127)
static func to_signed_8(b: int) -> int:
	return b if b < 128 else b - 256


## Calculates spawn position according to player stance and aim direction
func _calculate_spawn_pos(aim_dir: int, player_screen_x: int, player_screen_y: int,
		is_jumping: bool) -> Vector2i:
	var off_x: int = 0
	var off_y: int = 0

	if is_jumping:
		var idx: int = (aim_dir if aim_dir < 12 else 0) * 2
		if ROM_POS_OFFSET_AIR + idx + 1 < prg_rom.size():
			off_x = to_signed_8(prg_rom[ROM_POS_OFFSET_AIR + idx])
			off_y = to_signed_8(prg_rom[ROM_POS_OFFSET_AIR + idx + 1])
	else:
		var idx: int = (aim_dir if aim_dir < 10 else 0) * 2
		if ROM_POS_OFFSET_GROUND + idx + 1 < prg_rom.size():
			off_x = to_signed_8(prg_rom[ROM_POS_OFFSET_GROUND + idx])
			off_y = to_signed_8(prg_rom[ROM_POS_OFFSET_GROUND + idx + 1])

	return Vector2i((player_screen_x + off_x) & 0xFF, (player_screen_y + off_y) & 0xFF)


## Initializes velocities from Bank 6 tables for standard/fireball weapons
func _init_bullet_velocities(slot: BulletSlot, wtype: int, rapid_fire: bool, aim_dir: int) -> void:
	var vel_table_off: int = 0
	if wtype == WEAPON_TYPE_FIREBALL:
		vel_table_off = ROM_VEL_F_RAPID if rapid_fire else ROM_VEL_F_NORMAL
	else:
		vel_table_off = ROM_VEL_STD_RAPID if rapid_fire else ROM_VEL_STD_NORMAL

	var idx: int = (aim_dir if aim_dir < 12 else 0) * 4
	if vel_table_off + idx + 3 < prg_rom.size():
		slot.vel_x_fast = to_signed_8(prg_rom[vel_table_off + idx + 0])
		slot.vel_x_fract = prg_rom[vel_table_off + idx + 1]
		slot.vel_y_fast = to_signed_8(prg_rom[vel_table_off + idx + 2])
		slot.vel_y_fract = prg_rom[vel_table_off + idx + 3]


## Fires a weapon projectile for the specified player
func fire(player_id: int, weapon_code: int, aim_dir: int, player_screen_x: int, player_screen_y: int,
		is_jumping: bool, water_state: int, m_timer_ref: Variant, input: int, input_diff: int,
		apu: RefCounted = null, sound: RefCounted = null) -> bool:
	if prg_rom.is_empty():
		return false

	# In water: cannot fire downward
	if water_state > 0 and (aim_dir >= 3 and aim_dir <= 6):
		return false

	var wtype: int = weapon_code & 0x0F
	var rapid_fire: bool = (weapon_code & WEAPON_MODIFIER_RAPID_FIRE) != 0

	# Machine Gun continuous fire timer check
	if wtype == WEAPON_TYPE_RAPID:
		if (input & 0x40) == 0:
			# Button B not held
			if m_timer_ref is Array and not m_timer_ref.is_empty():
				if (m_timer_ref[0] & 0x0F) < 7:
					m_timer_ref[0] += 1
				else:
					m_timer_ref[0] = (m_timer_ref[0] & 0xF0) | 7
			elif m_timer_ref != null and "m_fire_timer" in m_timer_ref:
				if (m_timer_ref.m_fire_timer & 0x0F) < 7:
					m_timer_ref.m_fire_timer += 1
				else:
					m_timer_ref.m_fire_timer = (m_timer_ref.m_fire_timer & 0xF0) | 7
			return false

		# Button B is held
		if m_timer_ref is Array and not m_timer_ref.is_empty():
			m_timer_ref[0] += 1
			var t: int = m_timer_ref[0]
			if t < 0x60:
				if (t & 0x0F) != 8:
					return false
			else:
				if (t & 0x0F) < 0x0F:
					return false
				t += 0x0F
				m_timer_ref[0] = 0 if t >= 0x70 else (t & 0xF0)
		elif m_timer_ref != null and "m_fire_timer" in m_timer_ref:
			m_timer_ref.m_fire_timer += 1
			var t: int = m_timer_ref.m_fire_timer
			if t < 0x60:
				if (t & 0x0F) != 8:
					return false
			else:
				if (t & 0x0F) < 0x0F:
					return false
				t += 0x0F
				m_timer_ref.m_fire_timer = 0 if t >= 0x70 else (t & 0xF0)
	elif wtype == WEAPON_TYPE_BEAM:
		if (input & 0x40) == 0 and (input_diff & 0x40) == 0:
			return false
	else:
		# Standard, F, S require newly pressed Button B
		if (input_diff & 0x40) == 0:
			return false

	# Quota and active search boundaries
	var start_slot: int = 0 if player_id == 0 else 8
	var max_search: int = 8 if player_id == 0 else 16
	var allowed_active: int = 4

	if wtype == WEAPON_TYPE_RAPID:
		allowed_active = 6
	elif wtype == WEAPON_TYPE_SPREAD:
		allowed_active = 10
		start_slot = 0 if player_id == 0 else 6
		max_search = 16

	var current_count: int = 0
	for i in range(BULLET_POOL_MAX_SLOTS):
		if slots[i].slot_type != 0 and slots[i].owner == player_id:
			current_count += 1

	if current_count >= allowed_active:
		return false

	# Spread Gun: 5 fan pellets
	if wtype == WEAPON_TYPE_SPREAD:
		var spawned: int = 0
		for k in range(5):
			if current_count + spawned >= allowed_active:
				break
			var slot_idx: int = -1
			for s in range(start_slot, max_search):
				if slots[s].slot_type == 0:
					slot_idx = s
					break
			if slot_idx == -1:
				break

			var slot: BulletSlot = slots[slot_idx]
			slot.reset()
			slot.slot_type = wtype + 1
			slot.owner = player_id
			slot.aim_dir = aim_dir
			slot.rapid_flag = 1 if rapid_fire else 0
			slot.routine = BULLET_ROUTINE_MOVING
			slot.sprite_code = 0x1F # Small bullet
			slot.sprite_attr = 0x02

			var spawn_pos: Vector2i = _calculate_spawn_pos(aim_dir, player_screen_x, player_screen_y, is_jumping)
			slot.pos_x = spawn_pos.x
			slot.pos_y = spawn_pos.y

			var base_angle: int = prg_rom[ROM_AIM_DIR_TO_S_INDEX + (aim_dir if aim_dir < 12 else 0)]
			var mod: int = to_signed_8(prg_rom[ROM_S_INDEX_MODIFIERS + k])
			var angle_idx: int = (base_angle + mod) & 0x1F
			var byte_off: int = angle_idx * 2

			var s_vel_y_off: int = ROM_S_VEL_RAPID_Y if rapid_fire else ROM_S_VEL_NORMAL_Y
			var s_vel_x_off: int = ROM_S_VEL_RAPID_X if rapid_fire else ROM_S_VEL_NORMAL_X

			slot.vel_y_fract = prg_rom[s_vel_y_off + byte_off + 0]
			slot.vel_y_fast = to_signed_8(prg_rom[s_vel_y_off + byte_off + 1])
			slot.vel_x_fract = prg_rom[s_vel_x_off + byte_off + 0]
			slot.vel_x_fast = to_signed_8(prg_rom[s_vel_x_off + byte_off + 1])

			spawned += 1

		if spawned > 0 and sound != null and apu != null:
			sound.play_sound(apu, prg_rom[ROM_WEAPON_SOUNDS + 3])
		return spawned > 0

	# Laser Beam: 4 sequential segments
	if wtype == WEAPON_TYPE_BEAM:
		var spawned: int = 0
		for k in [3, 2, 1, 0]:
			var slot_idx: int = -1
			for s in range(start_slot, max_search):
				if slots[s].slot_type == 0:
					slot_idx = s
					break
			if slot_idx == -1:
				break

			var slot: BulletSlot = slots[slot_idx]
			slot.reset()
			slot.slot_type = wtype + 1
			slot.owner = player_id
			slot.aim_dir = aim_dir
			slot.rapid_flag = 1
			slot.routine = BULLET_ROUTINE_INIT
			slot.timer = prg_rom[ROM_BEAM_DELAYS + k]

			var spawn_pos: Vector2i = _calculate_spawn_pos(aim_dir, player_screen_x, player_screen_y, is_jumping)
			slot.pos_x = spawn_pos.x
			slot.pos_y = spawn_pos.y

			_init_bullet_velocities(slot, wtype, true, aim_dir)
			spawned += 1

		if spawned > 0 and sound != null and apu != null:
			sound.play_sound(apu, prg_rom[ROM_WEAPON_SOUNDS + 4])
		return spawned > 0

	# Standard, Machine Gun, and Fireball
	var slot_idx: int = -1
	for s in range(start_slot, max_search):
		if slots[s].slot_type == 0:
			slot_idx = s
			break
	if slot_idx == -1:
		return false

	var slot: BulletSlot = slots[slot_idx]
	slot.reset()
	slot.slot_type = wtype + 1
	slot.owner = player_id
	slot.aim_dir = aim_dir
	slot.rapid_flag = 1 if rapid_fire else 0
	slot.routine = BULLET_ROUTINE_MOVING

	slot.sprite_code = prg_rom[ROM_WEAPON_SPRITES + wtype + 1]
	slot.sprite_attr = 0x02

	var spawn_pos: Vector2i = _calculate_spawn_pos(aim_dir, player_screen_x, player_screen_y, is_jumping)
	slot.pos_x = spawn_pos.x
	slot.pos_y = spawn_pos.y

	_init_bullet_velocities(slot, wtype, rapid_fire, aim_dir)

	# F weapon swirl center initialization
	if wtype == WEAPON_TYPE_FIREBALL:
		var f_idx: int = (aim_dir if aim_dir < 12 else 0) * 3
		slot.timer = prg_rom[ROM_F_INIT_TABLE + f_idx + 0]
		slot.fs_x = (slot.pos_x + to_signed_8(prg_rom[ROM_F_INIT_TABLE + f_idx + 1])) & 0xFF
		slot.f_y = (slot.pos_y + to_signed_8(prg_rom[ROM_F_INIT_TABLE + f_idx + 2])) & 0xFF

	if sound != null and apu != null:
		sound.play_sound(apu, prg_rom[ROM_WEAPON_SOUNDS + wtype])

	return true


## Updates all active projectiles by one frame
func update_bullets(scroll_delta: int, grid: RefCounted = null) -> void:
	for i in range(BULLET_POOL_MAX_SLOTS):
		var slot: BulletSlot = slots[i]
		if slot.slot_type == 0:
			continue

		# Delay routine (Beam segments waiting to activate)
		if slot.routine == BULLET_ROUTINE_INIT:
			if scroll_delta != 0:
				slot.pos_x = (slot.pos_x - scroll_delta) & 0xFF
				slot.fs_x = (slot.fs_x - scroll_delta) & 0xFF
			if slot.timer > 0:
				slot.timer -= 1
			if slot.timer == 0:
				slot.routine = BULLET_ROUTINE_MOVING
				var s_idx: int = (slot.aim_dir if slot.aim_dir < 12 else 0) * 2
				slot.sprite_code = prg_rom[ROM_BEAM_SPRITES + s_idx + 0]
				slot.sprite_attr = prg_rom[ROM_BEAM_SPRITES + s_idx + 1]
			continue

		# Active moving bullet
		if slot.routine == BULLET_ROUTINE_MOVING:
			if scroll_delta != 0:
				slot.pos_x = (slot.pos_x - scroll_delta) & 0xFF
				slot.fs_x = (slot.fs_x - scroll_delta) & 0xFF

			if slot.slot_type == WEAPON_TYPE_FIREBALL + 1:
				# Swirling trajectory
				var y_acc: int = slot.vel_f_y_accum + slot.vel_y_fract
				slot.vel_f_y_accum = y_acc & 0xFF
				slot.f_y = (slot.f_y + slot.vel_y_fast + (y_acc >> 8)) & 0xFF

				var x_acc: int = slot.vel_fs_x_accum + slot.vel_x_fract
				slot.vel_fs_x_accum = x_acc & 0xFF
				slot.fs_x = (slot.fs_x + slot.vel_x_fast + (x_acc >> 8)) & 0xFF

				slot.timer = (slot.timer + 1) & 0x0F
				var swirl_x: int = to_signed_8(prg_rom[ROM_F_SWIRL_X + slot.timer])
				var swirl_y: int = to_signed_8(prg_rom[ROM_F_SWIRL_Y + slot.timer])

				slot.pos_x = (slot.fs_x + swirl_x) & 0xFF
				slot.pos_y = (slot.f_y + swirl_y) & 0xFF
			else:
				# Straight / angled trajectory
				var x_acc: int = slot.vel_x_accum + slot.vel_x_fract
				slot.vel_x_accum = x_acc & 0xFF
				slot.pos_x = (slot.pos_x + slot.vel_x_fast + (x_acc >> 8)) & 0xFF

				var y_acc: int = slot.vel_y_accum + slot.vel_y_fract
				slot.vel_y_accum = y_acc & 0xFF
				slot.pos_y = (slot.pos_y + slot.vel_y_fast + (y_acc >> 8)) & 0xFF

				# Spread Gun distance-based sizing
				if slot.slot_type == WEAPON_TYPE_SPREAD + 1:
					if slot.dist < 255:
						slot.dist += 1
					if slot.dist >= 32:
						slot.sprite_code = 0x21 # Large pellet
					elif slot.dist >= 16:
						slot.sprite_code = 0x20 # Medium pellet
					else:
						slot.sprite_code = 0x1F # Small pellet

			# Solid wall collision
			if grid != null:
				var tile_code: int = grid.get_code(slot.pos_x, slot.pos_y)
				if tile_code == CollisionGridScript.COLLISION_CODE_SOLID:
					slot.routine = BULLET_ROUTINE_IMPACT
					slot.timer = 6
					slot.sprite_code = 0x47 # Impact ring tile
					continue

			# Off-screen boundary check
			if slot.pos_x < 5 or slot.pos_x > 251 or slot.pos_y < 5 or slot.pos_y > 232:
				slot.reset()
			continue

		# Impact decay routine
		if slot.routine == BULLET_ROUTINE_IMPACT:
			if scroll_delta != 0:
				slot.pos_x = (slot.pos_x - scroll_delta) & 0xFF
			if slot.timer > 0:
				slot.timer -= 1
			if slot.timer == 0:
				slot.reset()


## Renders active bullet sprites into the 256-byte OAM buffer
func render_oam(oam_buffer: PackedByteArray, oam_entry_start: int, frame_counter: int) -> int:
	if oam_buffer.size() < 256:
		return 0

	var oam_idx: int = oam_entry_start
	var rendered_count: int = 0

	if authentic_flicker:
		var phase: int = frame_counter & 0x01
		for y in range(8):
			var slot_num: int = (y * 2) | phase
			var slot: BulletSlot = slots[slot_num]
			if slot.slot_type == 0 or slot.routine == BULLET_ROUTINE_INACTIVE or slot.routine == BULLET_ROUTINE_INIT:
				continue
			if slot.pos_y >= 240:
				continue

			var oam_off: int = oam_idx * 4
			if oam_off + 4 > 256:
				break

			oam_buffer[oam_off + 0] = (slot.pos_y - 8) & 0xFF
			oam_buffer[oam_off + 1] = slot.sprite_code
			oam_buffer[oam_off + 2] = slot.sprite_attr
			oam_buffer[oam_off + 3] = (slot.pos_x - 4) & 0xFF

			oam_idx += 1
			rendered_count += 1
	else:
		for s in range(BULLET_POOL_MAX_SLOTS):
			var slot: BulletSlot = slots[s]
			if slot.slot_type == 0 or slot.routine == BULLET_ROUTINE_INACTIVE or slot.routine == BULLET_ROUTINE_INIT:
				continue
			if slot.pos_y >= 240:
				continue

			var oam_off: int = oam_idx * 4
			if oam_off + 4 > 256:
				break

			# 2-tile horizontal laser beam
			if slot.sprite_code == 0x24:
				if oam_off + 8 > 256:
					break
				oam_buffer[oam_off + 0] = (slot.pos_y - 8) & 0xFF
				oam_buffer[oam_off + 1] = 0x24
				oam_buffer[oam_off + 2] = slot.sprite_attr
				oam_buffer[oam_off + 3] = (slot.pos_x - 12) & 0xFF

				oam_buffer[oam_off + 4] = (slot.pos_y - 8) & 0xFF
				oam_buffer[oam_off + 5] = 0x24
				oam_buffer[oam_off + 6] = slot.sprite_attr
				oam_buffer[oam_off + 7] = (slot.pos_x - 4) & 0xFF

				oam_idx += 2
				rendered_count += 2
				continue

			oam_buffer[oam_off + 0] = (slot.pos_y - 8) & 0xFF
			oam_buffer[oam_off + 1] = slot.sprite_code
			oam_buffer[oam_off + 2] = slot.sprite_attr
			oam_buffer[oam_off + 3] = (slot.pos_x - 4) & 0xFF

			oam_idx += 1
			rendered_count += 1

	return rendered_count
