#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <vector>

#include "core/types.h"
#include "rom/rom_loader.h"
#include "audio/apu.h"
#include "audio/sound_engine.h"
#include "game/collision.h"
#include "game/player.h"
#include "game/bullet_pool.h"

#define TEST_ASSERT(cond) do { \
    if (!(cond)) { \
        fprintf(stderr, "[ASSERTION FAILED] %s at %s:%d\n", #cond, __FILE__, __LINE__); \
        std::abort(); \
    } \
} while(0)

static void test_bullet_pool_init(const RomData *rom) {
    printf("[TEST] Testing Bullet Pool Initialization & ROM Table Resolution...\n");

    BulletPool pool;
    ReconResult res = bullet_pool_init(&pool, rom);
    TEST_ASSERT(res == RECON_OK);

    // Verify all 19 dynamic table pointers from Bank 6 are resolved
    TEST_ASSERT(pool.tables.pos_offset_ground != nullptr);
    TEST_ASSERT(pool.tables.pos_offset_air != nullptr);
    TEST_ASSERT(pool.tables.vel_std_normal != nullptr);
    TEST_ASSERT(pool.tables.vel_std_rapid != nullptr);
    TEST_ASSERT(pool.tables.vel_f_normal != nullptr);
    TEST_ASSERT(pool.tables.vel_f_rapid != nullptr);
    TEST_ASSERT(pool.tables.f_init_table != nullptr);
    TEST_ASSERT(pool.tables.f_swirl_y != nullptr);
    TEST_ASSERT(pool.tables.f_swirl_x != nullptr);
    TEST_ASSERT(pool.tables.aim_dir_to_s_index != nullptr);
    TEST_ASSERT(pool.tables.s_index_modifiers != nullptr);
    TEST_ASSERT(pool.tables.s_vel_normal_y != nullptr);
    TEST_ASSERT(pool.tables.s_vel_normal_x != nullptr);
    TEST_ASSERT(pool.tables.s_vel_rapid_y != nullptr);
    TEST_ASSERT(pool.tables.s_vel_rapid_x != nullptr);
    TEST_ASSERT(pool.tables.beam_delays != nullptr);
    TEST_ASSERT(pool.tables.beam_sprites != nullptr);
    TEST_ASSERT(pool.tables.weapon_sounds != nullptr);
    TEST_ASSERT(pool.tables.weapon_sprites != nullptr);

    // Check specific verified bytes in ROM Bank 6
    // Standard weapon normal velocity for horizontal right (aim_dir 2): entry 2 * 4 = offset 8
    // Format: x_fast, x_fract, y_fast, y_fract -> 0x03, 0x00, 0x00, 0x00 (+3 px/frame)
    TEST_ASSERT((int8_t)pool.tables.vel_std_normal[8] == 3);
    TEST_ASSERT(pool.tables.vel_std_normal[9] == 0);
    TEST_ASSERT((int8_t)pool.tables.vel_std_normal[10] == 0);
    TEST_ASSERT(pool.tables.vel_std_normal[11] == 0);

    // S weapon modifier table: 0, 1, -1 (0xFF), 2, -2 (0xFE)
    TEST_ASSERT(pool.tables.s_index_modifiers[0] == 0x00);
    TEST_ASSERT(pool.tables.s_index_modifiers[1] == 0x01);
    TEST_ASSERT(pool.tables.s_index_modifiers[2] == 0xFF);
    TEST_ASSERT(pool.tables.s_index_modifiers[3] == 0x02);
    TEST_ASSERT(pool.tables.s_index_modifiers[4] == 0xFE);

    // Beam delay table: 10, 7, 4, 1
    TEST_ASSERT(pool.tables.beam_delays[0] == 10);
    TEST_ASSERT(pool.tables.beam_delays[1] == 7);
    TEST_ASSERT(pool.tables.beam_delays[2] == 4);
    TEST_ASSERT(pool.tables.beam_delays[3] == 1);

    printf("[PASS] Bullet Pool initialization verified.\n");
}

static void test_standard_rifle(const RomData *rom) {
    printf("[TEST] Testing Standard Rifle Weapon & Slot Quota...\n");

    BulletPool pool;
    TEST_ASSERT(bullet_pool_init(&pool, rom) == RECON_OK);

    uint8_t m_timer = 0;
    // Fire 1st shot facing right on ground (aim_dir 2)
    bool fired = bullet_pool_fire(&pool, 0, WEAPON_TYPE_STANDARD, AIM_DIR_RIGHT,
                                  48, 128, false, 0, &m_timer, 0x40, 0x40, nullptr, nullptr);
    TEST_ASSERT(fired);
    TEST_ASSERT(pool.slots[0].slot_type == 1); // Standard bullet active
    TEST_ASSERT(pool.slots[0].sprite_code == 0x1E);
    TEST_ASSERT(pool.slots[0].vel_x_fast == 3);
    TEST_ASSERT(pool.slots[0].vel_y_fast == 0);

    // Fire 2nd, 3rd, 4th shot
    TEST_ASSERT(bullet_pool_fire(&pool, 0, WEAPON_TYPE_STANDARD, AIM_DIR_RIGHT,
                                 48, 128, false, 0, &m_timer, 0x40, 0x40, nullptr, nullptr));
    TEST_ASSERT(bullet_pool_fire(&pool, 0, WEAPON_TYPE_STANDARD, AIM_DIR_RIGHT,
                                 48, 128, false, 0, &m_timer, 0x40, 0x40, nullptr, nullptr));
    TEST_ASSERT(bullet_pool_fire(&pool, 0, WEAPON_TYPE_STANDARD, AIM_DIR_RIGHT,
                                 48, 128, false, 0, &m_timer, 0x40, 0x40, nullptr, nullptr));

    // 5th shot must be rejected (Standard weapon limit: 4 simultaneous bullets)
    bool shot5 = bullet_pool_fire(&pool, 0, WEAPON_TYPE_STANDARD, AIM_DIR_RIGHT,
                                  48, 128, false, 0, &m_timer, 0x40, 0x40, nullptr, nullptr);
    TEST_ASSERT(!shot5);

    // Update 10 frames: slot 0 should travel 30 pixels right
    uint8_t init_x = pool.slots[0].pos_x;
    for (int f = 0; f < 10; ++f) {
        bullet_pool_update(&pool, 0, nullptr);
    }
    TEST_ASSERT(pool.slots[0].pos_x == (uint8_t)(init_x + 30));

    // Update until bullet flies off screen (> 251): slot must be recycled
    for (int f = 0; f < 100; ++f) {
        bullet_pool_update(&pool, 0, nullptr);
    }
    TEST_ASSERT(pool.slots[0].slot_type == 0); // Slot cleaned up

    printf("[PASS] Standard Rifle weapon verified.\n");
}

static void test_machine_gun(const RomData *rom) {
    printf("[TEST] Testing Machine Gun (Continuous Rapid Fire)...\n");

    BulletPool pool;
    TEST_ASSERT(bullet_pool_init(&pool, rom) == RECON_OK);

    uint8_t m_timer = 0;
    size_t bullets_spawned = 0;

    // Hold Button B (input = 0x40) continuously for 80 frames
    for (int f = 0; f < 80; ++f) {
        bool fired = bullet_pool_fire(&pool, 0, WEAPON_TYPE_RAPID, AIM_DIR_RIGHT,
                                      48, 128, false, 0, &m_timer, 0x40, (f == 0 ? 0x40 : 0x00), nullptr, nullptr);
        if (fired) {
            bullets_spawned++;
        }
        bullet_pool_update(&pool, 0, nullptr);
    }

    // Must have spawned multiple bullets automatically via m_fire_timer pacing
    printf("  Machine gun bullets spawned over 80 frames: %zu\n", bullets_spawned);
    TEST_ASSERT(bullets_spawned >= 4 && bullets_spawned <= 8);

    printf("[PASS] Machine Gun verified.\n");
}

static void test_fireball_swirl(const RomData *rom) {
    printf("[TEST] Testing Fireball Weapon & Swirling Trajectory...\n");

    BulletPool pool;
    TEST_ASSERT(bullet_pool_init(&pool, rom) == RECON_OK);

    uint8_t m_timer = 0;
    bool fired = bullet_pool_fire(&pool, 0, WEAPON_TYPE_FIREBALL, AIM_DIR_RIGHT,
                                  48, 128, false, 0, &m_timer, 0x40, 0x40, nullptr, nullptr);
    TEST_ASSERT(fired);
    TEST_ASSERT(pool.slots[0].slot_type == 3); // F weapon

    // Center coordinates must be initialized
    uint8_t initial_fs_x = pool.slots[0].fs_x;
    uint8_t initial_f_y  = pool.slots[0].f_y;
    TEST_ASSERT(initial_fs_x != 0 && initial_f_y != 0);

    // Track trajectory over 16 frames (one full swirl loop)
    std::vector<int8_t> x_offsets;
    for (int f = 0; f < 16; ++f) {
        int8_t dx = (int8_t)(pool.slots[0].pos_x - pool.slots[0].fs_x);
        x_offsets.push_back(dx);
        bullet_pool_update(&pool, 0, nullptr);
    }

    // Verify non-linear swirl (oscillating offsets around center)
    bool has_positive = false;
    bool has_negative = false;
    for (int8_t dx : x_offsets) {
        if (dx > 0) has_positive = true;
        if (dx < 0) has_negative = true;
    }
    TEST_ASSERT(has_positive && has_negative);

    printf("[PASS] Fireball swirling trajectory verified.\n");
}

static void test_spread_gun(const RomData *rom) {
    printf("[TEST] Testing Spread Gun 5-Way Fan Trajectory & Sprite Sizing...\n");

    BulletPool pool;
    TEST_ASSERT(bullet_pool_init(&pool, rom) == RECON_OK);

    uint8_t m_timer = 0;
    // Single shot with Spread Gun
    bool fired = bullet_pool_fire(&pool, 0, WEAPON_TYPE_SPREAD, AIM_DIR_RIGHT,
                                  48, 128, false, 0, &m_timer, 0x40, 0x40, nullptr, nullptr);
    TEST_ASSERT(fired);

    // Count spawned bullets: exactly 5 bullets fanning out
    size_t active_count = 0;
    for (size_t i = 0; i < BULLET_POOL_MAX_SLOTS; ++i) {
        if (pool.slots[i].slot_type == 4) {
            active_count++;
        }
    }
    TEST_ASSERT(active_count == 5);

    // Verify unique velocity angles
    bool found_upward = false;
    bool found_downward = false;
    bool found_straight = false;

    for (size_t i = 0; i < 5; ++i) {
        if (pool.slots[i].vel_y_fast < 0) found_upward = true;
        if (pool.slots[i].vel_y_fast > 0) found_downward = true;
        if (pool.slots[i].vel_y_fast == 0) found_straight = true;
    }
    TEST_ASSERT(found_upward && found_downward && found_straight);

    // Check distance-based sprite progression: small (0x1F) -> medium (0x20) -> large (0x21)
    TEST_ASSERT(pool.slots[0].sprite_code == 0x1F); // Initially small
    for (int f = 0; f < 18; ++f) {
        bullet_pool_update(&pool, 0, nullptr);
    }
    TEST_ASSERT(pool.slots[0].sprite_code == 0x20); // Medium after 16 frames
    for (int f = 0; f < 16; ++f) {
        bullet_pool_update(&pool, 0, nullptr);
    }
    TEST_ASSERT(pool.slots[0].sprite_code == 0x21); // Large after 32 frames

    printf("[PASS] Spread Gun 5-way fan verified.\n");
}

static void test_laser_beam(const RomData *rom) {
    printf("[TEST] Testing Laser Beam 4-Segment Trajectory...\n");

    BulletPool pool;
    TEST_ASSERT(bullet_pool_init(&pool, rom) == RECON_OK);

    uint8_t m_timer = 0;
    bool fired = bullet_pool_fire(&pool, 0, WEAPON_TYPE_BEAM, AIM_DIR_RIGHT,
                                  48, 128, false, 0, &m_timer, 0x40, 0x40, nullptr, nullptr);
    TEST_ASSERT(fired);

    // 4 connected segments created in delay phase
    size_t segment_count = 0;
    for (size_t i = 0; i < BULLET_POOL_MAX_SLOTS; ++i) {
        if (pool.slots[i].slot_type == 5) {
            segment_count++;
        }
    }
    TEST_ASSERT(segment_count == 4);

    // Step 2 frames: segment with timer 1 should transition to moving
    bullet_pool_update(&pool, 0, nullptr);
    bullet_pool_update(&pool, 0, nullptr);

    bool has_moving = false;
    for (size_t i = 0; i < 4; ++i) {
        if (pool.slots[i].routine == BULLET_ROUTINE_MOVING) {
            has_moving = true;
            break;
        }
    }
    TEST_ASSERT(has_moving);

    printf("[PASS] Laser Beam verified.\n");
}

static void test_rapid_fire_modifier(const RomData *rom) {
    printf("[TEST] Testing Rapid Fire Modifier Upgrade...\n");

    BulletPool pool;
    TEST_ASSERT(bullet_pool_init(&pool, rom) == RECON_OK);

    uint8_t m_timer = 0;
    // Standard rifle without rapid fire: vel_x_fast is 3
    bullet_pool_fire(&pool, 0, WEAPON_TYPE_STANDARD, AIM_DIR_RIGHT,
                     48, 128, false, 0, &m_timer, 0x40, 0x40, nullptr, nullptr);
    TEST_ASSERT(pool.slots[0].vel_x_fast == 3);

    // Standard rifle WITH rapid fire (bit 4 set: 0x10): vel_x_fast is 4
    bullet_pool_clear(&pool);
    bullet_pool_fire(&pool, 0, (uint8_t)(WEAPON_TYPE_STANDARD | WEAPON_MODIFIER_RAPID_FIRE), AIM_DIR_RIGHT,
                     48, 128, false, 0, &m_timer, 0x40, 0x40, nullptr, nullptr);
    TEST_ASSERT(pool.slots[0].vel_x_fast == 4);

    printf("[PASS] Rapid Fire modifier verified.\n");
}

static void test_wall_impact_collision(const RomData *rom) {
    printf("[TEST] Testing Bullet Wall Collision & Impact Ring...\n");

    BulletPool pool;
    TEST_ASSERT(bullet_pool_init(&pool, rom) == RECON_OK);

    CollisionGrid grid;
    collision_grid_init(&grid);
    grid.screen_loaded[0] = true;
    grid.screen_indices[0] = 0;

    // Place solid barrier at X=96..111 (col 6), rows 6 and 7 (Y=112..143)
    // row 6: 6 * 4 + 1 = 25; row 7: 7 * 4 + 1 = 29
    grid.data[25] = (uint8_t)(grid.data[25] | (3u << 2u));
    grid.data[29] = (uint8_t)(grid.data[29] | (3u << 2u));

    uint8_t m_timer = 0;
    bullet_pool_fire(&pool, 0, WEAPON_TYPE_STANDARD, AIM_DIR_RIGHT,
                     48, 128, false, 0, &m_timer, 0x40, 0x40, nullptr, nullptr);

    // Fly bullet until impact
    bool impacted = false;
    for (int f = 0; f < 50; ++f) {
        bullet_pool_update(&pool, 0, &grid);
        if (pool.slots[0].routine == BULLET_ROUTINE_IMPACT) {
            impacted = true;
            TEST_ASSERT(pool.slots[0].sprite_code == 0x47); // Impact ring tile
            break;
        }
    }
    printf("  Wall impact detected: %s\n", impacted ? "YES" : "NO");

    // After timer runs down, slot must be destroyed
    for (int f = 0; f < 10; ++f) {
        bullet_pool_update(&pool, 0, &grid);
    }
    TEST_ASSERT(pool.slots[0].slot_type == 0);

    printf("[PASS] Wall impact verified.\n");
}

static void test_oam_rendering(const RomData *rom) {
    printf("[TEST] Testing Bullet OAM Rendering...\n");

    BulletPool pool;
    TEST_ASSERT(bullet_pool_init(&pool, rom) == RECON_OK);

    uint8_t m_timer = 0;
    bullet_pool_fire(&pool, 0, WEAPON_TYPE_STANDARD, AIM_DIR_RIGHT,
                     48, 128, false, 0, &m_timer, 0x40, 0x40, nullptr, nullptr);

    uint8_t oam[256];
    memset(oam, 0xFF, sizeof(oam));

    size_t count = bullet_pool_render_oam(&pool, oam, 2, 0);
    TEST_ASSERT(count == 1);

    // OAM Entry 2 starts at offset 8 (2 * 4)
    // Small bullet format: Y - 8, tile, attr, X - 4
    TEST_ASSERT(oam[8] == (uint8_t)(pool.slots[0].pos_y - 8));
    TEST_ASSERT(oam[9] == 0x1E);
    TEST_ASSERT(oam[10] == 0x02);
    TEST_ASSERT(oam[11] == (uint8_t)(pool.slots[0].pos_x - 4));

    printf("[PASS] Bullet OAM rendering verified.\n");
}

int main(int argc, char **argv) {
    const char *rom_path = "Contra (USA).nes";
    if (argc > 1) {
        rom_path = argv[1];
    }

    printf("========================================================\n");
    printf("[TEST SUITE] Phase 5: Weapon System & 16-Slot Bullet Pool\n");
    printf("========================================================\n");

    RomData rom;
    ReconResult res = rom_load_file(rom_path, &rom);
    if (res != RECON_OK) {
        res = rom_load_file("Contra.nes", &rom);
    }
    TEST_ASSERT(res == RECON_OK);

    test_bullet_pool_init(&rom);
    test_standard_rifle(&rom);
    test_machine_gun(&rom);
    test_fireball_swirl(&rom);
    test_spread_gun(&rom);
    test_laser_beam(&rom);
    test_rapid_fire_modifier(&rom);
    test_wall_impact_collision(&rom);
    test_oam_rendering(&rom);

    rom_free(&rom);
    printf("========================================================\n");
    printf("[ALL PASS] Phase 5 Weapon System 100%% Verified!\n");
    printf("========================================================\n");
    return 0;
}
