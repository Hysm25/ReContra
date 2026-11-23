#ifndef RECON_TYPES_H
#define RECON_TYPES_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define DISPLAY_WIDTH          256
#define DISPLAY_HEIGHT         240
#define NTSC_FRAME_HZ          60.0988
#define NTSC_FRAME_TIME_MS     16.6392

#define INES_HEADER_SIZE       16
#define PRG_BANK_SIZE          16384
#define PRG_BANK_COUNT         8
#define PRG_TOTAL_SIZE         (PRG_BANK_SIZE * PRG_BANK_COUNT)
#define CHR_RAM_SIZE           8192
#define PPU_VRAM_SIZE          16384
#define PPU_PATTERN_TABLE_SIZE 4096
#define PPU_NAMETABLE_SIZE     1024
#define OAM_BUFFER_SIZE        256
#define PALETTE_RAM_SIZE       32

#define SUBPIXEL_ACCUM_MAX     256

typedef enum {
    RECON_OK                       =  0,
    RECON_ERR_FILE_NOT_FOUND       = -1,
    RECON_ERR_FILE_IO              = -2,
    RECON_ERR_INVALID_HEADER       = -3,
    RECON_ERR_CHECKSUM_MISMATCH    = -4,
    RECON_ERR_UNSUPPORTED_MAPPER   = -5,
    RECON_ERR_OUT_OF_BOUNDS        = -6,
    RECON_ERR_CORRUPT_DATA         = -7,
    RECON_ERR_NULL_PTR             = -8,
    RECON_ERR_ALLOC_FAILED         = -9
} ReconResult;

typedef enum {
    GAME_ROUTINE_INTRO        = 0,
    GAME_ROUTINE_TITLE        = 1,
    GAME_ROUTINE_DEMO_WAIT    = 2,
    GAME_ROUTINE_START_FLASH  = 3,
    GAME_ROUTINE_CLEAR_RAM    = 4,
    GAME_ROUTINE_PLAY_LEVEL   = 5,
    GAME_ROUTINE_ENDING       = 6
} GameRoutineIndex;

typedef enum {
    LEVEL_1_JUNGLE      = 0,
    LEVEL_2_BASE_1      = 1,
    LEVEL_3_WATERFALL   = 2,
    LEVEL_4_BASE_2      = 3,
    LEVEL_5_SNOW_FIELD  = 4,
    LEVEL_6_ENERGY_ZONE = 5,
    LEVEL_7_HANGAR      = 6,
    LEVEL_8_ALIEN_LAIR  = 7
} ContraLevelId;

typedef struct {
    uint8_t fast;
    uint8_t fract;
    uint8_t accum;
} SubpixelPos;

static inline void subpixel_update(uint8_t *pos, SubpixelPos *sp) {
    uint16_t sum = (uint16_t)((uint16_t)sp->accum + (uint16_t)sp->fract);
    sp->accum = (uint8_t)(sum & 0xFFu);
    *pos = (uint8_t)(*pos + sp->fast + (uint8_t)(sum >> 8));
}

static inline uint8_t reverse_bits_u8(uint8_t b) {
    b = (uint8_t)(((b & 0xF0u) >> 4) | ((b & 0x0Fu) << 4));
    b = (uint8_t)(((b & 0xCCu) >> 2) | ((b & 0x33u) << 2));
    b = (uint8_t)(((b & 0xAAu) >> 1) | ((b & 0x55u) << 1));
    return b;
}

#ifdef __cplusplus
}
#endif

#endif /* RECON_TYPES_H */
