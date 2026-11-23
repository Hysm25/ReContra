class_name GameLoop
extends RefCounted

const CollisionGridScript = preload("res://scripts/game/collision.gd")
const BulletPoolScript = preload("res://scripts/game/weapons.gd")
const PlayerScript = preload("res://scripts/game/player.gd")

## Generic 60.0988 Hz Fixed-Timestep Game Runtime & Coordinator
## Coordinates Player state machines, 16-slot BulletPool, CollisionGrid,
## dual-nametable outdoor/indoor camera scrolling, PPU rendering, and APU sound.

const GAME_ROUTINE_INTRO: int = 0x00
const GAME_ROUTINE_TITLE: int = 0x01
const GAME_ROUTINE_DEMO_WAIT: int = 0x02
const GAME_ROUTINE_START_FLASH: int = 0x03
const GAME_ROUTINE_CLEAR_RAM: int = 0x04
const GAME_ROUTINE_PLAY_LEVEL: int = 0x05
const GAME_ROUTINE_ENDING: int = 0x06

const MAX_PLAYERS: int = 2

var rom: RefCounted = null
var ppu: RefCounted = null
var apu: RefCounted = null
var sound: RefCounted = null

var game_routine: int = GAME_ROUTINE_PLAY_LEVEL
var current_level: int = 0
var player_mode: int = 0
var frame_counter: int = 0
var random_num: int = 0
var is_paused: bool = false
var konami_code_active: bool = false
var total_frames: int = 0

var camera_scroll_x: int = 0
var camera_scroll_y: int = 0
var active_screen_index: int = 0
var loaded_screens: Array[int] = [-1, -1]

var level_header: RefCounted = null
var collision_grid: RefCounted = null
var bullet_pool: RefCounted = null
var players: Array[RefCounted] = []
var prev_inputs: Array[int] = [0, 0]


func _init(rom_ref: RefCounted = null, ppu_ref: RefCounted = null,
		apu_ref: RefCounted = null, sound_ref: RefCounted = null) -> void:
	collision_grid = CollisionGridScript.new()
	bullet_pool = BulletPoolScript.new()
	players.resize(MAX_PLAYERS)
	for p in range(MAX_PLAYERS):
		players[p] = PlayerScript.new(p, rom_ref)

	if rom_ref != null:
		init_game(rom_ref, ppu_ref, apu_ref, sound_ref)


## Initializes game runtime state with ROM and hardware references
func init_game(rom_ref: RefCounted, ppu_ref: RefCounted = null,
		apu_ref: RefCounted = null, sound_ref: RefCounted = null) -> bool:
	if rom_ref == null:
		return false

	rom = rom_ref
	ppu = ppu_ref
	apu = apu_ref
	sound = sound_ref

	game_routine = GAME_ROUTINE_PLAY_LEVEL
	current_level = 0
	player_mode = 0
	frame_counter = 0
	random_num = 0
	is_paused = false
	konami_code_active = false
	total_frames = 0
	camera_scroll_x = 0
	camera_scroll_y = 0
	active_screen_index = 0
	loaded_screens = [-1, -1]
	prev_inputs = [0, 0]

	for p in range(MAX_PLAYERS):
		players[p].init_player(p, rom)

	bullet_pool.init_pool(rom)
	collision_grid.init_grid()
	return true


## Activates or clears Konami Code 30 lives
func set_konami_code(active: bool) -> void:
	konami_code_active = active
	if active:
		players[0].lives = PlayerScript.KONAMI_LIVES
		players[1].lives = PlayerScript.KONAMI_LIVES


## Loads a stage by index, configuring palettes, CHR VRAM, nametables, and collision
func load_level(level_idx: int) -> bool:
	if rom == null:
		return false

	current_level = level_idx
	var LevelLoaderScript = preload("res://scripts/rom/level_loader.gd")
	var ChrExtractorScript = preload("res://scripts/rom/chr_extractor.gd")

	level_header = LevelLoaderScript.load_level_header(rom, level_idx)
	if level_header == null:
		return false

	var pal_buffer: PackedByteArray = LevelLoaderScript.load_palettes(rom, level_idx)
	if ppu != null:
		ppu.load_palettes(pal_buffer)
		ChrExtractorScript.load_level_graphics(rom, level_idx, ppu.vram)

	camera_scroll_x = 0
	camera_scroll_y = 0
	active_screen_index = 0

	collision_grid.init_grid()
	bullet_pool.clear_pool()

	if ppu != null:
		ppu.unpack_screen_horizontal(0, rom, level_header, 0)
		ppu.unpack_screen_horizontal(1, rom, level_header, 1)

	collision_grid.unpack_screen(rom, level_header, 0, 0)
	collision_grid.unpack_screen(rom, level_header, 1, 1)
	loaded_screens[0] = 0
	loaded_screens[1] = 1

	for p in range(MAX_PLAYERS):
		players[p].spawn(PlayerScript.DEFAULT_SPAWN_X + p * 32, PlayerScript.DEFAULT_SPAWN_Y)

	if sound != null and apu != null:
		sound.play_sound(apu, 0x2A) # Stage 1 Jungle BGM

	return true


## Advances the full game simulation by one 60.0988 Hz fixed timestep frame
func tick(p1_input: int, p2_input: int = 0) -> void:
	frame_counter = (frame_counter + 1) & 0xFF
	random_num = (random_num + frame_counter) & 0xFF
	total_frames += 1

	# Update Player 1
	var p1_diff: int = (p1_input ^ prev_inputs[0]) & p1_input
	players[0].update_player(p1_input, p1_diff, camera_scroll_x, collision_grid, apu, sound)
	bullet_pool.fire(0, players[0].current_weapon, players[0].aim_dir,
			players[0].screen_x, players[0].screen_y,
			players[0].is_jumping, players[0].water_state,
			players[0], p1_input, p1_diff, apu, sound)
	prev_inputs[0] = p1_input

	# Update Player 2
	if player_mode == 1:
		var p2_diff: int = (p2_input ^ prev_inputs[1]) & p2_input
		players[1].update_player(p2_input, p2_diff, camera_scroll_x, collision_grid, apu, sound)
		bullet_pool.fire(1, players[1].current_weapon, players[1].aim_dir,
				players[1].screen_x, players[1].screen_y,
				players[1].is_jumping, players[1].water_state,
				players[1], p2_input, p2_diff, apu, sound)
		prev_inputs[1] = p2_input

	# Camera scrolling logic (Outdoor horizontal mode)
	var scroll_delta: int = 0
	if level_header != null and level_header.scrolling_type == 0 and level_header.location_type == 0:
		var lead_x: int = players[0].world_x
		if player_mode == 1 and players[1].state == PlayerScript.State.NORMAL and players[1].world_x > lead_x:
			lead_x = players[1].world_x

		var old_scroll_x: int = camera_scroll_x
		if lead_x >= camera_scroll_x + 128:
			var desired_scroll: int = lead_x - 128
			var max_scroll: int = level_header.stop_scrolling_pos * 256
			if desired_scroll > max_scroll:
				desired_scroll = max_scroll
			if desired_scroll > camera_scroll_x:
				camera_scroll_x = desired_scroll

		scroll_delta = camera_scroll_x - old_scroll_x
		var cur_screen: int = int(camera_scroll_x / 256)
		active_screen_index = cur_screen
		var next_screen: int = cur_screen + 1

		if next_screen <= level_header.stop_scrolling_pos and rom != null:
			var nt_idx: int = next_screen % 2
			if loaded_screens[nt_idx] != next_screen:
				if ppu != null:
					ppu.unpack_screen_horizontal(nt_idx, rom, level_header, next_screen)
				collision_grid.unpack_screen(rom, level_header, next_screen, nt_idx)
				loaded_screens[nt_idx] = next_screen

	# Update projectiles
	bullet_pool.update_bullets(scroll_delta, collision_grid)

	# Render PPU Frame
	render()

	# Audio frame sequencer update
	if sound != null and apu != null:
		sound.update_frame(apu)


## Submits OAM sprites and renders the PPU software framebuffer
func render() -> void:
	if ppu == null:
		return

	ppu.scroll_x = camera_scroll_x % 512
	ppu.scroll_y = camera_scroll_y % 480

	ppu.oam.fill(0xFF)
	players[0].render_oam(ppu.oam, 0)
	if player_mode == 1:
		players[1].render_oam(ppu.oam, 8)
	bullet_pool.render_oam(ppu.oam, (16 if player_mode == 1 else 8), frame_counter)

	ppu.render_frame()


## Computes a 32-bit FNV-1a hash of the complete simulation state for replay verification
func get_state_hash() -> int:
	var hash: int = 0x811C9DC5

	# Helper closure
	var hash_byte = func(b: int) -> void:
		hash ^= (b & 0xFF)
		hash = (hash * 0x01000193) & 0xFFFFFFFF

	var hash_word = func(w: int) -> void:
		hash_byte.call(w & 0xFF)
		hash_byte.call((w >> 8) & 0xFF)

	hash_byte.call(frame_counter)
	hash_byte.call(random_num)
	hash_word.call(camera_scroll_x)
	hash_word.call(camera_scroll_y)
	hash_byte.call(active_screen_index)

	for p in range(MAX_PLAYERS):
		var pl = players[p]
		hash_byte.call(pl.state)
		hash_word.call(pl.world_x)
		hash_word.call(pl.world_y)
		hash_byte.call(pl.screen_x)
		hash_byte.call(pl.screen_y)
		hash_byte.call(pl.vel_x)
		hash_byte.call(pl.vel_y_fast)
		hash_byte.call(pl.vel_y_fract)
		hash_byte.call(pl.jump_accum)
		hash_byte.call(1 if pl.is_jumping else 0)
		hash_byte.call(1 if pl.facing_left else 0)
		hash_byte.call(pl.aim_dir)
		hash_byte.call(pl.water_state)
		hash_byte.call(pl.lives)
		hash_word.call(pl.invincibility_timer)

	for b in range(BulletPoolScript.BULLET_POOL_MAX_SLOTS):
		var slot = bullet_pool.slots[b]
		if slot.slot_type != 0:
			hash_byte.call(slot.slot_type)
			hash_byte.call(slot.pos_x)
			hash_byte.call(slot.pos_y)
			hash_byte.call(slot.routine)
			hash_byte.call(slot.timer)

	return hash
