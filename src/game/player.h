#ifndef RECON_PLAYER_H
#define RECON_PLAYER_H

#include "core/types.h"
#include "rom/rom_loader.h"
#include "audio/apu.h"
#include "audio/sound_engine.h"
#include "game/collision.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PLAYER_DEFAULT_LIVES         3u
#define PLAYER_KONAMI_LIVES          30u
#define PLAYER_DEFAULT_SPAWN_X       48u
#define PLAYER_DEFAULT_SPAWN_Y       16u
#define PLAYER_INVINCIBLE_RESPAWN    180u

/* Authentic NES Contra Jump Physics Constants */
#define PLAYER_JUMP_VEL_FAST_OUTDOOR ((int8_t)-5)
#define PLAYER_JUMP_VEL_FRACT_OUTDOOR 0xF0u /* -5.9375 px/frame */
#define PLAYER_GRAVITY_ACCEL_FRACT    0x23u /* +0.1367 px/frame^2 */

/* Controller Input Bitmask */
#define GAME_INPUT_RIGHT  0x01u
#define GAME_INPUT_LEFT   0x02u
#define GAME_INPUT_DOWN   0x04u
#define GAME_INPUT_UP     0x08u
#define GAME_INPUT_START  0x10u
#define GAME_INPUT_SELECT 0x20u
#define GAME_INPUT_B      0x40u
#define GAME_INPUT_A      0x80u

/* Authentic NES Contra Aim Directions ($C2) */
#define AIM_DIR_UP_FACING_RIGHT 0x00u
#define AIM_DIR_UP_RIGHT        0x01u
#define AIM_DIR_RIGHT           0x02u
#define AIM_DIR_DOWN_RIGHT      0x03u
#define AIM_DIR_CROUCH_RIGHT    0x04u
#define AIM_DIR_CROUCH_LEFT     0x05u
#define AIM_DIR_DOWN_LEFT       0x06u
#define AIM_DIR_LEFT            0x07u
#define AIM_DIR_UP_LEFT         0x08u
#define AIM_DIR_UP_FACING_LEFT  0x09u
#define AIM_DIR_DOWN_AIR        0x0Au

typedef enum {
    PLAYER_STATE_SPAWNING = 0,
    PLAYER_STATE_NORMAL   = 1,
    PLAYER_STATE_DYING    = 2,
    PLAYER_STATE_DEAD     = 3,
    PLAYER_STATE_GAMEOVER = 4
} PlayerState;

typedef struct {
    uint8_t player_id;
    PlayerState state;

    uint16_t world_x;
    uint16_t world_y;
    uint8_t screen_x;
    uint8_t screen_y;

    int8_t vel_x;
    int8_t vel_y_fast;
    uint8_t vel_y_fract;
    uint8_t jump_accum;

    bool is_jumping;
    bool is_crouching;
    bool facing_left;
    uint8_t aim_dir;
    uint8_t water_state; /* 0 = Dry land, 1 = Surface swim, 2 = Submerged dive */
    uint8_t edge_fall_code;

    uint16_t invincibility_timer;
    uint8_t lives;
    uint8_t current_weapon; /* 0 = Standard Rifle */
    uint8_t m_fire_timer;   /* Continuous fire accumulator ($9C/$9D) */

    uint8_t anim_timer;
    uint8_t anim_frame;
    uint8_t sprite_sequence;

    const uint8_t *aim_table; /* ROM PRG Bank 7 $D93A pointer */
    const RomData *rom;        /* ROM pointer for dynamic sprite data */
} Player;

ReconResult player_init(Player *player, uint8_t player_id, const RomData *rom);
void player_spawn(Player *player, uint16_t spawn_x, uint16_t spawn_y);
void player_update(Player *player, uint8_t input, uint8_t input_diff,
                   uint16_t camera_scroll_x, const CollisionGrid *grid,
                   Apu2A03 *apu, SoundEngine *sound);
void player_take_hit(Player *player, Apu2A03 *apu, SoundEngine *sound);
void player_render_oam(const Player *player, uint8_t *oam_buffer, size_t oam_entry_start);

#ifdef __cplusplus
}
#endif

#endif /* RECON_PLAYER_H */
