#ifndef RECON_SOUND_ENGINE_H
#define RECON_SOUND_ENGINE_H

#include "core/types.h"
#include "rom/rom_loader.h"
#include "audio/apu.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SOUND_SLOT_COUNT 6u

/*
 * Slot assignments:
 * 0: BGM Pulse 1
 * 1: BGM Pulse 2
 * 2: BGM Triangle
 * 3: BGM Noise & DMC (Percussion)
 * 4: SFX Pulse 1 (Priority over Slot 0)
 * 5: SFX Noise (Priority over Slot 3)
 */
#define SOUND_SLOT_BGM_PULSE1 0u
#define SOUND_SLOT_BGM_PULSE2 1u
#define SOUND_SLOT_BGM_TRI    2u
#define SOUND_SLOT_BGM_PERC   3u
#define SOUND_SLOT_SFX_PULSE1 4u
#define SOUND_SLOT_SFX_NOISE  5u

/* Known ROM Offsets in Bank 1 (PRG 0x4000) */
#define ROM_SOUND_TABLE_OFFSET      0x48E8u /* CPU $88E8 */
#define ROM_DPCM_TABLE_OFFSET       0x48DBu /* CPU $88DB */
#define ROM_PERCUSSION_TABLE_OFFSET 0x42CDu /* CPU $82CD */
#define ROM_PULSE_VOL_TABLE_OFFSET  0x4001u /* CPU $8001 */
#define ROM_NOTE_PERIOD_OFFSET      0x46D5u /* CPU $86D5 */

typedef struct {
    uint8_t sound_code;
    uint8_t cmd_length;
    uint8_t length_multiplier;
    uint8_t flags;             /* Bit 0: low code (< $30), Bit 2: auto decrescendo, Bit 3: shared child call, Bit 4: flatten, Bit 5: pause decrescendo, Bit 6: mute */
    uint16_t cmd_addr;         /* Current CPU pointer to bytecode in Bank 1 ($8000-$BFFF) */
    uint16_t return_addr;      /* Return CPU pointer for $FD child calls */
    uint8_t repeat_count;      /* Repeat loop counter for $FE commands */
    uint8_t pulse_length;
    uint8_t pulse_period;
    uint8_t pulse_volume;
    uint8_t vol_duration;
    uint8_t vol_env_index;     /* Index into pulse_volume_ptr_tbl */
    uint8_t vol_step_index;    /* Step index within active envelope */
    uint8_t decrescendo_pause;
    uint8_t pitch_adjust;
    uint8_t period_rotate;
    uint8_t cfg_high;
    uint8_t cfg_low;
    uint8_t triangle_cfg;
    uint8_t vibrato_ctrl;
    uint8_t vibrato_delay;
    uint8_t vibrato_amount;
    uint8_t vol_timer;
} SoundSlot;

typedef struct {
    const uint8_t *prg_data;
    size_t prg_size;
    bool is_loaded;
    bool is_paused;

    SoundSlot slots[SOUND_SLOT_COUNT];
} SoundEngine;

ReconResult sound_engine_init(SoundEngine *engine, const RomData *rom);
void sound_engine_reset(SoundEngine *engine);
void sound_engine_set_paused(SoundEngine *engine, bool paused);
ReconResult sound_engine_play_sound(SoundEngine *engine, Apu2A03 *apu, uint8_t sound_code);
void sound_engine_update_frame(SoundEngine *engine, Apu2A03 *apu);

#ifdef __cplusplus
}
#endif

#endif /* RECON_SOUND_ENGINE_H */
