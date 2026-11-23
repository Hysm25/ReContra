class_name TestGameplaySimulation
extends RefCounted

## Modular Test Suite: Gameplay Physics, Bullet Pool & GameLoop Simulation (31 Tests)

const CollisionGridScript = preload("res://src/game/collision.gd")
const PlayerScript = preload("res://src/game/player.gd")
const BulletPoolScript = preload("res://src/game/weapons.gd")
const GameLoopScript = preload("res://src/game/game_loop.gd")
const LevelLoaderScript = preload("res://src/rom/level_loader.gd")
const PpuRendererScript = preload("res://src/render/ppu_renderer.gd")
const ApuSynthesizerScript = preload("res://src/audio/apu_synthesizer.gd")
const SoundEngineScript = preload("res://src/audio/sound_engine.gd")


static func run(runner: Object, loader: RefCounted) -> bool:
	print("\n--- 6. Gameplay Physics, Bullet Pool & GameLoop Simulation ---")

	# 6.1 Collision Grid Tests (5 tests)
	var grid = CollisionGridScript.new()
	runner.assert_test("CollisionGrid Initial Buffer Size == 128", grid.data.size() == 128)
	runner.assert_test("CollisionGrid Uninitialized Point Empty", grid.get_code(48, 32) == CollisionGridScript.COLLISION_CODE_EMPTY)

	var lvl_hdr = LevelLoaderScript.load_header(loader, 0)
	var ok_s0: bool = grid.unpack_screen(loader, lvl_hdr, 0, 0)
	var ok_s1: bool = grid.unpack_screen(loader, lvl_hdr, 1, 1)
	runner.assert_test("CollisionGrid Unpack Screens 0 & 1", ok_s0 and ok_s1)
	runner.assert_test("CollisionGrid Out-of-Bounds Empty", grid.get_code(48, 10) == CollisionGridScript.COLLISION_CODE_EMPTY and grid.get_code(48, 250) == CollisionGridScript.COLLISION_CODE_EMPTY)
	runner.assert_test("CollisionGrid Stage 1 Drop Down Available", grid.can_drop_down(48, 32))

	# 6.2 Player Kinematics & 8-Direction Aim Tests (13 tests)
	var player = PlayerScript.new(0, loader)
	runner.assert_test("Player Default Spawn Position (48, 16)", player.world_x == 48 and player.world_y == 16)
	runner.assert_test("Player Default Lives == 3", player.lives == 3)

	# Fill grid with floor (0x55) to provide a ground plane for kinematic checks
	grid.data.fill(0x55)
	player.state = PlayerScript.State.NORMAL
	player.is_jumping = false
	player.is_crouching = false
	player.world_y = 16

	# Bank 7 $D93A Aim resolution
	player.update_player(PlayerScript.INPUT_RIGHT, 0, 0, grid)
	runner.assert_test("Player Aim Right (0x02) Facing Right", player.aim_dir == PlayerScript.AIM_DIR_RIGHT and not player.facing_left)

	player.update_player(PlayerScript.INPUT_RIGHT | PlayerScript.INPUT_UP, 0, 0, grid)
	runner.assert_test("Player Aim Up-Right (0x01)", player.aim_dir == PlayerScript.AIM_DIR_UP_RIGHT)

	player.update_player(PlayerScript.INPUT_UP, 0, 0, grid)
	runner.assert_test("Player Aim Up Facing Right (0x00)", player.aim_dir == PlayerScript.AIM_DIR_UP_FACING_RIGHT)

	player.update_player(PlayerScript.INPUT_RIGHT | PlayerScript.INPUT_DOWN, 0, 0, grid)
	runner.assert_test("Player Aim Down-Right (0x03)", player.aim_dir == PlayerScript.AIM_DIR_DOWN_RIGHT)

	player.update_player(PlayerScript.INPUT_LEFT, 0, 0, grid)
	runner.assert_test("Player Aim Left (0x07) Facing Left", player.aim_dir == PlayerScript.AIM_DIR_LEFT and player.facing_left)

	player.update_player(PlayerScript.INPUT_LEFT | PlayerScript.INPUT_UP, 0, 0, grid)
	runner.assert_test("Player Aim Up-Left (0x08)", player.aim_dir == PlayerScript.AIM_DIR_UP_LEFT)

	player.update_player(PlayerScript.INPUT_DOWN, 0, 0, grid)
	runner.assert_test("Player Crouch Facing Left (0x05)", player.is_crouching and player.aim_dir == PlayerScript.AIM_DIR_CROUCH_LEFT)

	# Jump impulse & gravity (-5.9375 px/frame initial impulse with 0x23 gravity step)
	player.state = PlayerScript.State.NORMAL
	player.is_jumping = false
	player.is_crouching = false
	player.update_player(PlayerScript.INPUT_A, PlayerScript.INPUT_A, 0, grid)
	runner.assert_test("Player Jump Impulse (-5.9375 px/frame)", player.is_jumping and player.vel_y_fast == -4 and player.vel_y_fract == 0x13)

	# Drop-down platform bypass (12-frame timer decremented to 11 on frame 1)
	player.state = PlayerScript.State.NORMAL
	player.is_jumping = false
	player.is_crouching = false
	player.world_y = 16
	player.update_player(PlayerScript.INPUT_DOWN | PlayerScript.INPUT_A, PlayerScript.INPUT_A, 0, grid)
	runner.assert_test("Player Drop Down Floor Bypass Timer (12 frames)", player.edge_fall_code == 11)

	# Water dive state
	player.water_state = 1
	player.update_player(PlayerScript.INPUT_DOWN, 0, 0, grid)
	runner.assert_test("Player Water Submerged Dive State", player.water_state == 2)

	# Bank 1 $B030 OAM sprite frame mapping
	var oam_buf = PackedByteArray()
	oam_buf.resize(256)
	oam_buf.fill(0xFF)
	player.invincibility_timer = 0
	player.water_state = 0
	player.state = PlayerScript.State.NORMAL
	player.is_jumping = false
	player.is_crouching = false
	player.render_oam(oam_buf, 0)
	runner.assert_test("Player Bank 1 $B030 OAM Sprite Mapping", oam_buf[0] != 0xFF and oam_buf[1] != 0xFF)

	# 6.3 16-Slot Bullet Pool & Ballistics Engine Tests (8 tests)
	var pool = BulletPoolScript.new(loader)
	runner.assert_test("BulletPool Bank 6 ROM Resolution (0x20000 bytes)", pool.prg_rom.size() == 0x20000)

	# Standard Rifle quota & velocity
	pool.clear_pool()
	var f1: bool = pool.fire(0, BulletPoolScript.WEAPON_TYPE_STANDARD, PlayerScript.AIM_DIR_RIGHT, 60, 100, false, 0, player, PlayerScript.INPUT_B, PlayerScript.INPUT_B)
	runner.assert_test("BulletPool Fire Standard Rifle Slot 0 (3 px/frame)", f1 and pool.slots[0].slot_type == 1 and pool.slots[0].vel_x_fast == 3 and pool.slots[0].vel_y_fast == 0)

	var f2: bool = pool.fire(0, BulletPoolScript.WEAPON_TYPE_STANDARD, PlayerScript.AIM_DIR_RIGHT, 60, 100, false, 0, player, PlayerScript.INPUT_B, PlayerScript.INPUT_B)
	var f3: bool = pool.fire(0, BulletPoolScript.WEAPON_TYPE_STANDARD, PlayerScript.AIM_DIR_RIGHT, 60, 100, false, 0, player, PlayerScript.INPUT_B, PlayerScript.INPUT_B)
	var f4: bool = pool.fire(0, BulletPoolScript.WEAPON_TYPE_STANDARD, PlayerScript.AIM_DIR_RIGHT, 60, 100, false, 0, player, PlayerScript.INPUT_B, PlayerScript.INPUT_B)
	var f5: bool = pool.fire(0, BulletPoolScript.WEAPON_TYPE_STANDARD, PlayerScript.AIM_DIR_RIGHT, 60, 100, false, 0, player, PlayerScript.INPUT_B, PlayerScript.INPUT_B)
	runner.assert_test("BulletPool Standard Rifle Quota Limit (4 max)", f2 and f3 and f4 and not f5)

	# Machine Gun continuous auto-fire
	pool.clear_pool()
	player.current_weapon = BulletPoolScript.WEAPON_TYPE_RAPID
	player.m_fire_timer = 0
	var m_spawned: bool = false
	for _f in range(20):
		if pool.fire(0, player.current_weapon, PlayerScript.AIM_DIR_RIGHT, 60, 100, false, 0, player, PlayerScript.INPUT_B, 0):
			m_spawned = true
	runner.assert_test("BulletPool Machine Gun Continuous Auto-Fire", m_spawned)

	# Spread Gun 5-way fan
	pool.clear_pool()
	player.current_weapon = BulletPoolScript.WEAPON_TYPE_SPREAD
	var s_fired: bool = pool.fire(0, player.current_weapon, PlayerScript.AIM_DIR_RIGHT, 60, 100, false, 0, player, PlayerScript.INPUT_B, PlayerScript.INPUT_B)
	var s_count: int = 0
	for s in range(BulletPoolScript.BULLET_POOL_MAX_SLOTS):
		if pool.slots[s].slot_type == BulletPoolScript.WEAPON_TYPE_SPREAD + 1:
			s_count += 1
	runner.assert_test("BulletPool Spread Gun 5-Way Fan Spawning", s_fired and s_count == 5)

	# Laser Gun 4 sequential segments
	pool.clear_pool()
	player.current_weapon = BulletPoolScript.WEAPON_TYPE_BEAM
	var l_fired: bool = pool.fire(0, player.current_weapon, PlayerScript.AIM_DIR_RIGHT, 60, 100, false, 0, player, PlayerScript.INPUT_B, PlayerScript.INPUT_B)
	var l_count: int = 0
	for s in range(BulletPoolScript.BULLET_POOL_MAX_SLOTS):
		if pool.slots[s].slot_type == BulletPoolScript.WEAPON_TYPE_BEAM + 1:
			l_count += 1
	runner.assert_test("BulletPool Laser Gun 4 Sequential Segments Spawning", l_fired and l_count == 4)

	# Fireball swirling trajectory
	pool.clear_pool()
	player.current_weapon = BulletPoolScript.WEAPON_TYPE_FIREBALL
	var fb_fired: bool = pool.fire(0, player.current_weapon, PlayerScript.AIM_DIR_RIGHT, 60, 100, false, 0, player, PlayerScript.INPUT_B, PlayerScript.INPUT_B)
	runner.assert_test("BulletPool Fireball Swirling Initialization", fb_fired and pool.slots[0].fs_x != 0)

	# Solid wall collision & impact ring tile 0x47
	pool.clear_pool()
	var wall_slot = pool.slots[0]
	wall_slot.slot_type = BulletPoolScript.WEAPON_TYPE_STANDARD + 1
	wall_slot.routine = BulletPoolScript.BULLET_ROUTINE_MOVING
	wall_slot.pos_x = 32
	wall_slot.pos_y = 32
	wall_slot.vel_x_fast = 0
	wall_slot.vel_y_fast = 0
	grid.data.fill(0xFF)
	pool.update_bullets(0, grid)
	runner.assert_test("BulletPool Wall Impact Ring Tile (0x47)", wall_slot.routine == BulletPoolScript.BULLET_ROUTINE_IMPACT and wall_slot.sprite_code == 0x47)

	# 6.4 GameLoop 180-Frame Deterministic Simulation Tests (5 tests)
	var render_ppu = PpuRendererScript.new()
	var render_loop = GameLoopScript.new(loader, render_ppu, null, null)
	render_loop.load_level(0)
	render_loop.tick(PlayerScript.INPUT_RIGHT, 0)
	runner.assert_test("GameLoop PPU Frame Rendering Integration", render_ppu.frame_count >= 1)

	var sim_apu1 = ApuSynthesizerScript.new(48000)
	sim_apu1.set_dmc_memory(loader.get_bank(7))
	var sim_snd1 = SoundEngineScript.new(loader)
	var sim_loop1 = GameLoopScript.new(loader, null, sim_apu1, sim_snd1)
	sim_loop1.load_level(0)

	var sim_apu2 = ApuSynthesizerScript.new(48000)
	sim_apu2.set_dmc_memory(loader.get_bank(7))
	var sim_snd2 = SoundEngineScript.new(loader)
	var sim_loop2 = GameLoopScript.new(loader, null, sim_apu2, sim_snd2)
	sim_loop2.load_level(0)

	for f in range(180):
		var inp: int = 0
		if f >= 40:
			inp |= PlayerScript.INPUT_RIGHT
		if f >= 60 and f < 75:
			inp |= PlayerScript.INPUT_A
		if f >= 100 and f < 115:
			inp |= PlayerScript.INPUT_A
		if (f % 10) == 0:
			inp |= PlayerScript.INPUT_B
		sim_loop1.tick(inp, 0)
		sim_loop2.tick(inp, 0)

	runner.assert_test("GameLoop Simulation Player Advancement (X > 48)", sim_loop1.players[0].world_x > 48)
	runner.assert_test("GameLoop Camera Scrolling Triggered", sim_loop1.camera_scroll_x > 0)

	var hash1: int = sim_loop1.get_state_hash()
	var hash2: int = sim_loop2.get_state_hash()
	print("  GameLoop Determinism Check: Run 1 Hash=0x%08X, Run 2 Hash=0x%08X" % [hash1, hash2])
	runner.assert_test("GameLoop 180-Frame Deterministic State Hash Match", hash1 == hash2)
	runner.assert_test("GameLoop State Hash Non-Zero", hash1 != 0)

	return true
