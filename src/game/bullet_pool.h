#ifndef RECON_BULLET_POOL_H
#define RECON_BULLET_POOL_H

#include "core/types.h"
#include "rom/rom_loader.h"
#include "game/collision.h"
#include "audio/apu.h"
#include "audio/sound_engine.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BULLET_POOL_MAX_SLOTS 16u

/* Weapon Type Codes (Low 4 bits of weapon byte) */
typedef enum {
    WEAPON_TYPE_STANDARD = 0,
    WEAPON_TYPE_RAPID    = 1,
    WEAPON_TYPE_FIREBALL = 2,
    WEAPON_TYPE_SPREAD   = 3,
    WEAPON_TYPE_BEAM     = 4
} WeaponType;

/* Weapon Upgrade Modifiers */
#define WEAPON_MODIFIER_RAPID_FIRE 0x10u
#define WEAPON_MODIFIER_BARRIER    0x20u

/* Bullet Routine Indices */
#define BULLET_ROUTINE_INACTIVE 0u
#define BULLET_ROUTINE_INIT     1u
#define BULLET_ROUTINE_MOVING   2u
#define BULLET_ROUTINE_IMPACT   3u

/*
 * Bullet Slot Representation ($0368-$04B7)
 */
typedef struct {
    uint8_t slot_type;      /* $0388: 0 = empty, 1 = Std, 2 = M, 3 = F, 4 = S, 5 = L */
    uint8_t sprite_code;    /* $0368: PPU pattern / sprite index */
    uint8_t sprite_attr;    /* $0378: OAM attributes (flip, palette) */
    uint8_t vel_y_accum;    /* $0398: Sub-pixel Y velocity accumulator */
    uint8_t vel_x_accum;    /* $03A8: Sub-pixel X velocity accumulator */
    uint8_t pos_y;          /* $03B8: Screen Y position */
    uint8_t pos_x;          /* $03C8: Screen X position */
    uint8_t vel_y_fract;    /* $03D8: Fractional Y velocity */
    uint8_t vel_x_fract;    /* $03E8: Fractional X velocity */
    int8_t  vel_y_fast;     /* $03F8: Integer Y velocity */
    int8_t  vel_x_fast;     /* $0408: Integer X velocity */
    uint8_t timer;          /* $0418: Delay timer / swirl phase / impact decay */
    uint8_t aim_dir;        /* $0428: Aim direction at time of firing */
    uint8_t routine;        /* $0438: 0: Inactive, 1: Init/Delay, 2: Moving, 3: Impact */
    uint8_t owner;          /* $0448: 0 = Player 1, 1 = Player 2 */
    uint8_t rapid_flag;     /* $0458: Rapid fire modifier active */
    uint8_t dist;           /* $0468: Travel distance (for S sprite scaling) */
    uint8_t fs_x;           /* $0478: Center X position for swirl trajectory */
    uint8_t f_y;            /* $0488: Center Y position for swirl trajectory */
    uint8_t vel_fs_x_accum; /* $0498: Center X accumulator */
    uint8_t vel_f_y_accum;  /* $04A8: Center Y accumulator */
} BulletSlot;

/*
 * Dynamic Table Pointers resolved from ROM PRG Bank 6 at runtime
 */
typedef struct {
    const uint8_t *pos_offset_ground;      /* Bank 6 $B5FA: 20 bytes (10 pairs) */
    const uint8_t *pos_offset_air;         /* Bank 6 $B60E: 24 bytes (12 pairs) */
    const uint8_t *vel_std_normal;         /* Bank 6 $B6E9: 48 bytes (12 * 4) */
    const uint8_t *vel_std_rapid;          /* Bank 6 $B719: 48 bytes (12 * 4) */
    const uint8_t *vel_f_normal;           /* Bank 6 $B779: 48 bytes (12 * 4) */
    const uint8_t *vel_f_rapid;            /* Bank 6 $B749: 48 bytes (12 * 4) */
    const uint8_t *f_init_table;           /* Bank 6 $B817: 36 bytes (12 * 3) */
    const uint8_t *f_swirl_y;              /* Bank 6 $BADE: 16 bytes */
    const uint8_t *f_swirl_x;              /* Bank 6 $BAE2: 16 bytes */
    const uint8_t *aim_dir_to_s_index;     /* Bank 6 $B891: 12 bytes */
    const uint8_t *s_index_modifiers;      /* Bank 6 $B89D: 5 bytes */
    const uint8_t *s_vel_normal_y;         /* Bank 6 $B8AA: 16 bytes */
    const uint8_t *s_vel_normal_x;         /* Bank 6 $B8BA: 64 bytes */
    const uint8_t *s_vel_rapid_y;          /* Bank 6 $B8FA: 16 bytes */
    const uint8_t *s_vel_rapid_x;          /* Bank 6 $B90A: 64 bytes */
    const uint8_t *beam_delays;            /* Bank 6 $B55D: 8 bytes */
    const uint8_t *beam_sprites;           /* Bank 6 $BA17: 24 bytes (12 * 2) */
    const uint8_t *weapon_sounds;          /* Bank 6 $B5A7: 5 bytes */
    const uint8_t *weapon_sprites;         /* Bank 6 $B5AB: 6 bytes */
} BulletTables;

typedef struct {
    BulletSlot slots[BULLET_POOL_MAX_SLOTS];
    BulletTables tables;
    bool authentic_flicker;
} BulletPool;

ReconResult bullet_pool_init(BulletPool *pool, const RomData *rom);
void bullet_pool_clear(BulletPool *pool);

/* Fire weapon for given player */
bool bullet_pool_fire(BulletPool *pool, uint8_t player_id, uint8_t weapon_code,
                      uint8_t aim_dir, uint8_t player_screen_x, uint8_t player_screen_y,
                      bool is_jumping, uint8_t water_state, uint8_t *m_fire_timer,
                      uint8_t input, uint8_t input_diff,
                      Apu2A03 *apu, SoundEngine *sound);

/* Update all active bullets for the frame */
void bullet_pool_update(BulletPool *pool, int16_t scroll_delta, const CollisionGrid *grid);

/* Render active bullets to OAM buffer */
size_t bullet_pool_render_oam(const BulletPool *pool, uint8_t *oam_buffer,
                              size_t oam_entry_start, uint8_t frame_counter);

#ifdef __cplusplus
}
#endif

#endif /* RECON_BULLET_POOL_H */
