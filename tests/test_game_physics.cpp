#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <vector>

#include "core/types.h"
#include "rom/rom_loader.h"
#include "rom/level_loader.h"
#include "render/ppu.h"
#include "audio/apu.h"
#include "audio/sound_engine.h"
#include "game/collision.h"
#include "game/player.h"
#include "game/game_runtime.h"

#define TEST_ASSERT(cond) do { \
    if (!(cond)) { \
        fprintf(stderr, "[ASSERTION FAILED] %s at %s:%d\n", #cond, __FILE__, __LINE__); \
        std::abort(); \
    } \
} while(0)

static void test_collision_grid(const RomData *rom) {
    printf("[TEST] Testing Background Collision Grid...\n");

    LevelHeader lvl;
    ReconResult res = level_load_header(rom, 0, &lvl);
    TEST_ASSERT(res == RECON_OK);

    CollisionGrid grid;
    collision_grid_init(&grid);

    // Unpack Screen 0 and Screen 1
    res = collision_grid_unpack_screen(&grid, rom, &lvl, 0, 0);
    TEST_ASSERT(res == RECON_OK);
    res = collision_grid_unpack_screen(&grid, rom, &lvl, 1, 1);
    TEST_ASSERT(res == RECON_OK);

    // Air above stage must be empty
    uint8_t air_code = collision_grid_get_code(&grid, 48, 32);
    TEST_ASSERT(air_code == COLLISION_CODE_EMPTY);

    // Check collision code limits
    printf("  Stage 1 Collision limits: [%u, %u, %u]\n",
           lvl.collision_limits[0], lvl.collision_limits[1], lvl.collision_limits[2]);

    // Test drop down capability
    // There should be positions with upper floor platforms where can_drop_down returns true
    bool found_drop_down = false;
    for (uint16_t x = 32; x < 240; x += 16) {
        for (uint16_t y = 32; y < 140; y += 16) {
            if (collision_grid_get_code(&grid, x, y) == COLLISION_CODE_FLOOR) {
                if (collision_grid_can_drop_down(&grid, x, y)) {
                    found_drop_down = true;
                    break;
                }
            }
        }
        if (found_drop_down) break;
    }
    printf("  Drop-down platform detected: %s\n", found_drop_down ? "YES" : "NO");

    // Out of bounds queries must return empty
    TEST_ASSERT(collision_grid_get_code(&grid, 48, 0) == COLLISION_CODE_EMPTY);
    TEST_ASSERT(collision_grid_get_code(&grid, 48, 250) == COLLISION_CODE_EMPTY);

    printf("[PASS] Background Collision Grid verified.\n");
}

static void test_player_aiming(const RomData *rom) {
    printf("[TEST] Testing Player State Machine & 8-Direction Aiming...\n");

    Player p;
    ReconResult res = player_init(&p, 0, rom);
    TEST_ASSERT(res == RECON_OK);
    TEST_ASSERT(p.aim_table != nullptr);
    TEST_ASSERT(p.lives == PLAYER_DEFAULT_LIVES);

    LevelHeader lvl;
    ReconResult res_lvl = level_load_header(rom, 0, &lvl);
    TEST_ASSERT(res_lvl == RECON_OK);

    CollisionGrid grid;
    collision_grid_init(&grid);
    ReconResult res_grid = collision_grid_unpack_screen(&grid, rom, &lvl, 0, 0);
    TEST_ASSERT(res_grid == RECON_OK);

    // Transition out of spawning state and place standing on floor
    p.state = PLAYER_STATE_NORMAL;
    p.is_jumping = false;
    p.world_x = 48;
    p.world_y = 80;
    p.invincibility_timer = 0;

    // Test aiming right
    player_update(&p, GAME_INPUT_RIGHT, GAME_INPUT_RIGHT, 0, &grid, nullptr, nullptr);
    TEST_ASSERT(p.aim_dir == AIM_DIR_RIGHT);
    TEST_ASSERT(!p.facing_left);

    // Test aiming up-right
    player_update(&p, GAME_INPUT_RIGHT | GAME_INPUT_UP, GAME_INPUT_UP, 0, &grid, nullptr, nullptr);
    TEST_ASSERT(p.aim_dir == AIM_DIR_UP_RIGHT);

    // Test aiming straight up facing right
    player_update(&p, GAME_INPUT_UP, 0, 0, &grid, nullptr, nullptr);
    TEST_ASSERT(p.aim_dir == AIM_DIR_UP_FACING_RIGHT);

    // Test aiming down-right
    player_update(&p, GAME_INPUT_RIGHT | GAME_INPUT_DOWN, GAME_INPUT_DOWN, 0, &grid, nullptr, nullptr);
    TEST_ASSERT(p.aim_dir == AIM_DIR_DOWN_RIGHT);

    // Test crouching facing right
    player_update(&p, GAME_INPUT_DOWN, 0, 0, &grid, nullptr, nullptr);
    TEST_ASSERT(p.is_crouching);
    TEST_ASSERT(p.aim_dir == AIM_DIR_CROUCH_RIGHT);

    // Test aiming left
    player_update(&p, GAME_INPUT_LEFT, GAME_INPUT_LEFT, 0, &grid, nullptr, nullptr);
    TEST_ASSERT(p.aim_dir == AIM_DIR_LEFT);
    TEST_ASSERT(p.facing_left);

    // Test aiming up-left
    player_update(&p, GAME_INPUT_LEFT | GAME_INPUT_UP, GAME_INPUT_UP, 0, &grid, nullptr, nullptr);
    TEST_ASSERT(p.aim_dir == AIM_DIR_UP_LEFT);

    // Test aiming straight up facing left
    player_update(&p, GAME_INPUT_UP, 0, 0, &grid, nullptr, nullptr);
    TEST_ASSERT(p.aim_dir == AIM_DIR_UP_FACING_LEFT);

    // Test crouching facing left
    player_update(&p, GAME_INPUT_DOWN, 0, 0, &grid, nullptr, nullptr);
    TEST_ASSERT(p.is_crouching);
    TEST_ASSERT(p.aim_dir == AIM_DIR_CROUCH_LEFT);

    printf("[PASS] Player Aiming verified.\n");
}

static void test_player_jumping_physics(const RomData *rom) {
    printf("[TEST] Testing Parabolic Jump Physics & Floor Landing...\n");

    LevelHeader lvl;
    ReconResult res = level_load_header(rom, 0, &lvl);
    TEST_ASSERT(res == RECON_OK);
    CollisionGrid grid;
    collision_grid_init(&grid);
    res = collision_grid_unpack_screen(&grid, rom, &lvl, 0, 0);
    TEST_ASSERT(res == RECON_OK);

    Player p;
    res = player_init(&p, 0, rom);
    TEST_ASSERT(res == RECON_OK);
    p.state = PLAYER_STATE_NORMAL;
    p.world_x = 48;
    p.world_y = 80; // Start on floor

    // Initial A button press triggers Jump and integrates 1 frame of upward motion
    player_update(&p, GAME_INPUT_A, GAME_INPUT_A, 0, &grid, nullptr, nullptr);
    TEST_ASSERT(p.is_jumping);
    TEST_ASSERT(p.vel_y_fast < 0);
    TEST_ASSERT(p.world_y < 80);

    uint16_t min_y = p.world_y;
    int frames = 0;
    bool reached_apex = false;

    // Simulate jump until player lands or reaches apex
    while (frames < 60) {
        player_update(&p, 0, 0, 0, &grid, nullptr, nullptr);
        frames++;

        if (p.world_y < min_y) {
            min_y = p.world_y;
        }

        if (p.vel_y_fast >= 0 && !reached_apex) {
            reached_apex = true;
            printf("  Jump Apex reached at frame %d: start Y=80 -> apex Y=%u (delta = %d px)\n",
                   frames, min_y, 80 - (int)min_y);
            TEST_ASSERT(min_y < 80);
        }

        if (!p.is_jumping) {
            printf("  Landed on floor at frame %d, final Y=%u\n", frames, p.world_y);
            break;
        }
    }

    TEST_ASSERT(reached_apex);
    printf("[PASS] Parabolic Jump Physics verified.\n");
}

static void test_player_drop_down_and_damage(const RomData *rom) {
    printf("[TEST] Testing Floor Drop-Down, Water Mechanics & Damage Recoil...\n");

    LevelHeader lvl;
    ReconResult res = level_load_header(rom, 0, &lvl);
    TEST_ASSERT(res == RECON_OK);
    CollisionGrid grid;
    collision_grid_init(&grid);
    res = collision_grid_unpack_screen(&grid, rom, &lvl, 0, 0);
    TEST_ASSERT(res == RECON_OK);

    Player p;
    res = player_init(&p, 0, rom);
    TEST_ASSERT(res == RECON_OK);
    p.state = PLAYER_STATE_NORMAL;
    p.world_x = 48;
    p.world_y = 80;
    p.invincibility_timer = 0;

    // Test drop down
    if (collision_grid_can_drop_down(&grid, (uint16_t)(p.world_x + 8u), p.world_y)) {
        player_update(&p, GAME_INPUT_DOWN | GAME_INPUT_A, GAME_INPUT_A, 0, &grid, nullptr, nullptr);
        TEST_ASSERT(p.edge_fall_code > 0);
        TEST_ASSERT(p.is_jumping);
    }

    // Test take hit & damage recoil
    player_spawn(&p, 48, 80);
    p.state = PLAYER_STATE_NORMAL;
    p.invincibility_timer = 0;
    uint8_t initial_lives = p.lives;

    player_take_hit(&p, nullptr, nullptr);
    TEST_ASSERT(p.state == PLAYER_STATE_DYING);
    TEST_ASSERT(p.lives == initial_lives - 1);
    TEST_ASSERT(p.vel_y_fast < 0); // Backward recoil arc impulse

    // Test water state
    p.state = PLAYER_STATE_NORMAL;
    p.is_jumping = false;
    p.water_state = 1; // swimming
    player_update(&p, GAME_INPUT_DOWN, 0, 0, &grid, nullptr, nullptr);
    TEST_ASSERT(p.water_state == 2); // submerged dive

    player_update(&p, 0, 0, 0, &grid, nullptr, nullptr);
    TEST_ASSERT(p.water_state == 1); // back to surface swim

    printf("[PASS] Floor Drop-Down, Water Mechanics & Damage Recoil verified.\n");
}

static void test_game_runtime_simulation(const RomData *rom) {
    printf("[TEST] Testing Full GameRuntime Fixed-Timestep Simulation...\n");

    Ppu2C02 ppu;
    ppu_init(&ppu);

    Apu2A03 apu;
    apu_init(&apu, 48000);

    SoundEngine sound;
    sound_engine_init(&sound, rom);

    GameRuntime rt1, rt2;
    ReconResult res = game_runtime_init(&rt1, rom);
    TEST_ASSERT(res == RECON_OK);
    res = game_runtime_load_level(&rt1, 0, &ppu, &sound, &apu);
    TEST_ASSERT(res == RECON_OK);

    res = game_runtime_init(&rt2, rom);
    TEST_ASSERT(res == RECON_OK);
    res = game_runtime_load_level(&rt2, 0, &ppu, &sound, &apu);
    TEST_ASSERT(res == RECON_OK);

    // Simulate 180 frames with P1 running right and jumping
    for (uint32_t f = 0; f < 180; ++f) {
        uint8_t input = GAME_INPUT_RIGHT;
        if (f == 40 || f == 100) {
            input |= GAME_INPUT_A;
        }

        game_runtime_tick(&rt1, input, 0, &ppu, &sound, &apu);
        game_runtime_tick(&rt2, input, 0, &ppu, &sound, &apu);

        uint32_t hash1 = game_runtime_get_state_hash(&rt1);
        uint32_t hash2 = game_runtime_get_state_hash(&rt2);
        TEST_ASSERT(hash1 == hash2);
    }

    printf("  After 180 frames: P1 world_x=%u, camera_scroll_x=%u\n",
           rt1.players[0].world_x, rt1.camera_scroll_x);
    TEST_ASSERT(rt1.players[0].world_x > PLAYER_DEFAULT_SPAWN_X);
    TEST_ASSERT(rt1.camera_scroll_x > 0);

    uint32_t final_hash = game_runtime_get_state_hash(&rt1);
    printf("  Deterministic Simulation State Hash: 0x%08X\n", final_hash);

    printf("[PASS] GameRuntime Simulation verified.\n");
}

static void test_player_oam_mapping(const RomData *rom) {
    printf("[TEST] Testing Player OAM Sprite Tile & Palette Mapping from ROM...\n");

    Player p1, p2;
    ReconResult res = player_init(&p1, 0, rom);
    TEST_ASSERT(res == RECON_OK);
    res = player_init(&p2, 1, rom);
    TEST_ASSERT(res == RECON_OK);

    uint8_t oam[256];

    // 1. Standing Idle State
    p1.state = PLAYER_STATE_NORMAL;
    p1.screen_x = 64;
    p1.screen_y = 100;
    p1.invincibility_timer = 0;
    memset(oam, 0xFF, sizeof(oam));
    player_render_oam(&p1, oam, 0);
    // Player 1 sprite palette must be palette 0 ($3F11-$3F13)
    TEST_ASSERT((oam[2] & 0x03u) == 0x00u);
    // Upper torso tile index should match authentic standing sprite ($94)
    TEST_ASSERT(oam[1] == 0x94u);

    // Player 2 sprite palette must be palette 1 ($3F15-$3F17)
    p2.state = PLAYER_STATE_NORMAL;
    p2.screen_x = 96;
    p2.screen_y = 100;
    p2.invincibility_timer = 0;
    player_render_oam(&p2, oam, 8);
    TEST_ASSERT((oam[8 * 4 + 2] & 0x03u) == 0x01u);
    TEST_ASSERT(oam[8 * 4 + 1] == 0x94u);

    // 2. Jumping (Curled Somersault) State
    p1.is_jumping = true;
    p1.anim_timer = 0;
    memset(oam, 0xFF, sizeof(oam));
    player_render_oam(&p1, oam, 0);
    // Somersault frame 1 tile ($44)
    TEST_ASSERT(oam[1] == 0x44u);

    // 3. Crouching (Prone) State
    p1.is_jumping = false;
    p1.is_crouching = true;
    memset(oam, 0xFF, sizeof(oam));
    player_render_oam(&p1, oam, 0);
    // Prone tile ($9C)
    TEST_ASSERT(oam[1] == 0x9Cu);

    // 4. Water Submerged Dive State
    p1.is_crouching = false;
    p1.water_state = 2; // Submerged
    memset(oam, 0xFF, sizeof(oam));
    player_render_oam(&p1, oam, 0);
    // Water submerged tile ($DE)
    TEST_ASSERT(oam[1] == 0xDEu);

    printf("[PASS] Player OAM Sprite Tile & Palette Mapping verified.\n");
}

int main(int argc, char **argv) {
    const char *rom_path = (argc > 1) ? argv[1] : "Contra (USA).nes";

    RomData rom;
    ReconResult res = rom_load_file(rom_path, &rom);
    if (res != RECON_OK) {
        fprintf(stderr, "[SKIP] Could not load ROM '%s' (Error %d). Skipping test.\n", rom_path, res);
        return 0;
    }

    test_collision_grid(&rom);
    test_player_aiming(&rom);
    test_player_jumping_physics(&rom);
    test_player_drop_down_and_damage(&rom);
    test_player_oam_mapping(&rom);
    test_game_runtime_simulation(&rom);

    rom_free(&rom);
    printf("\nAll Game Physics, Collision Grid & State Machine tests PASSED successfully!\n");
    return 0;
}
