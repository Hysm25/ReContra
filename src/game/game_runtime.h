#ifndef RECON_GAME_RUNTIME_H
#define RECON_GAME_RUNTIME_H

#include "core/types.h"
#include "rom/rom_loader.h"
#include "rom/level_loader.h"
#include "render/ppu.h"
#include "audio/apu.h"
#include "audio/sound_engine.h"
#include "game/collision.h"
#include "game/player.h"
#include "game/bullet_pool.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * GAME_ROUTINE_INDEX ($18) Major State Constants
 */
#define GAME_ROUTINE_INTRO       0x00u
#define GAME_ROUTINE_TITLE       0x01u
#define GAME_ROUTINE_DEMO_WAIT   0x02u
#define GAME_ROUTINE_START_FLASH 0x03u
#define GAME_ROUTINE_CLEAR_RAM   0x04u
#define GAME_ROUTINE_PLAY_LEVEL  0x05u
#define GAME_ROUTINE_ENDING      0x06u

#define MAX_PLAYERS 2u

typedef struct {
    const RomData *rom;
    uint8_t game_routine;      /* $18 GAME_ROUTINE_INDEX */
    uint8_t current_level;     /* $30 CURRENT_LEVEL (0..7) */
    uint8_t player_mode;       /* $22 PLAYER_MODE (0: 1P, 1: 2P) */
    uint8_t frame_counter;     /* $1A FRAME_COUNTER */
    uint8_t random_num;        /* $34 RANDOM_NUM (PRNG accumulator) */
    bool is_paused;            /* $25 PAUSE_STATE */
    bool konami_code_active;   /* $24 KONAMI_CODE_STATUS */
    uint32_t total_frames;

    /* Camera & Level Progress */
    uint16_t camera_scroll_x;
    uint16_t camera_scroll_y;
    uint8_t active_screen_index;
    uint8_t loaded_screens[2]; /* Screen index loaded in NT0 and NT1 */

    LevelHeader level_header;
    CollisionGrid collision_grid;
    BulletPool bullet_pool;

    /* Players */
    Player players[MAX_PLAYERS];
    uint8_t prev_inputs[MAX_PLAYERS];
} GameRuntime;

ReconResult game_runtime_init(GameRuntime *rt, const RomData *rom);

ReconResult game_runtime_load_level(GameRuntime *rt, uint8_t level_idx, Ppu2C02 *ppu,
                                    SoundEngine *sound, Apu2A03 *apu);

void game_runtime_tick(GameRuntime *rt, uint8_t p1_input, uint8_t p2_input,
                       Ppu2C02 *ppu, SoundEngine *sound, Apu2A03 *apu);

void game_runtime_render(GameRuntime *rt, Ppu2C02 *ppu);

uint32_t game_runtime_get_state_hash(const GameRuntime *rt);

void game_runtime_set_konami_code(GameRuntime *rt, bool active);

#ifdef __cplusplus
}
#endif

#endif /* RECON_GAME_RUNTIME_H */
