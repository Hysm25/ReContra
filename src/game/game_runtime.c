#include "game/game_runtime.h"
#include "rom/chr_extractor.h"
#include "render/nametable.h"
#include <string.h>

ReconResult game_runtime_init(GameRuntime *rt, const RomData *rom) {
    if (!rt || !rom) {
        return RECON_ERR_NULL_PTR;
    }

    memset(rt, 0, sizeof(GameRuntime));
    rt->rom = rom;
    rt->game_routine = GAME_ROUTINE_PLAY_LEVEL;
    rt->current_level = 0;
    rt->player_mode = 0;
    rt->frame_counter = 0;
    rt->random_num = 0;
    rt->is_paused = false;
    rt->konami_code_active = false;
    rt->total_frames = 0;

    ReconResult res = player_init(&rt->players[0], 0, rom);
    if (res != RECON_OK) return res;

    res = player_init(&rt->players[1], 1, rom);
    if (res != RECON_OK) return res;

    return RECON_OK;
}

void game_runtime_set_konami_code(GameRuntime *rt, bool active) {
    if (!rt) return;
    rt->konami_code_active = active;
    if (active) {
        rt->players[0].lives = PLAYER_KONAMI_LIVES;
        rt->players[1].lives = PLAYER_KONAMI_LIVES;
    }
}

ReconResult game_runtime_load_level(GameRuntime *rt, uint8_t level_idx, Ppu2C02 *ppu,
                                    SoundEngine *sound, Apu2A03 *apu) {
    if (!rt || !rt->rom || !ppu) {
        return RECON_ERR_NULL_PTR;
    }

    rt->current_level = level_idx;

    ReconResult res = level_load_header(rt->rom, level_idx, &rt->level_header);
    if (res != RECON_OK) return res;

    uint8_t pal_buffer[PALETTE_RAM_SIZE] = {0};
    res = level_load_palettes(rt->rom, level_idx, pal_buffer);
    if (res != RECON_OK) return res;
    ppu_load_palettes(ppu, pal_buffer);

    res = chr_load_level_graphics(rt->rom, level_idx, ppu->vram, sizeof(ppu->vram));
    if (res != RECON_OK) return res;

    rt->camera_scroll_x = 0;
    rt->camera_scroll_y = 0;
    rt->active_screen_index = 0;

    collision_grid_init(&rt->collision_grid);

    res = nametable_unpack_screen_horizontal(ppu, 0, rt->rom, &rt->level_header, 0);
    if (res != RECON_OK) return res;
    res = collision_grid_unpack_screen(&rt->collision_grid, rt->rom, &rt->level_header, 0, 0);
    if (res != RECON_OK) return res;
    rt->loaded_screens[0] = 0;

    res = nametable_unpack_screen_horizontal(ppu, 1, rt->rom, &rt->level_header, 1);
    if (res != RECON_OK) return res;
    res = collision_grid_unpack_screen(&rt->collision_grid, rt->rom, &rt->level_header, 1, 1);
    if (res != RECON_OK) return res;
    rt->loaded_screens[1] = 1;

    ppu->scroll_x = 0;
    ppu->scroll_y = 0;

    player_spawn(&rt->players[0], PLAYER_DEFAULT_SPAWN_X, PLAYER_DEFAULT_SPAWN_Y);
    if (rt->konami_code_active) {
        rt->players[0].lives = PLAYER_KONAMI_LIVES;
    }

    if (rt->player_mode == 1) {
        player_spawn(&rt->players[1], (uint16_t)(PLAYER_DEFAULT_SPAWN_X + 32u), PLAYER_DEFAULT_SPAWN_Y);
        if (rt->konami_code_active) {
            rt->players[1].lives = PLAYER_KONAMI_LIVES;
        }
    }

    if (sound && apu) {
        /* Stage 1 BGM sound code is 0x2A */
        sound_engine_play_sound(sound, apu, 0x2Au);
    }

    return RECON_OK;
}

void game_runtime_tick(GameRuntime *rt, uint8_t p1_input, uint8_t p2_input,
                       Ppu2C02 *ppu, SoundEngine *sound, Apu2A03 *apu) {
    if (!rt) return;

    rt->total_frames++;
    rt->frame_counter++;
    rt->random_num = (uint8_t)(rt->random_num + rt->frame_counter);

    /* Pause toggle check */
    if ((p1_input & GAME_INPUT_START) && !(rt->prev_inputs[0] & GAME_INPUT_START)) {
        rt->is_paused = !rt->is_paused;
        if (sound && apu) {
            sound_engine_play_sound(sound, apu, rt->is_paused ? 0x56u : 0x57u);
        }
    }

    if (rt->is_paused) {
        if (sound && apu) {
            sound_engine_update_frame(sound, apu);
        }
        return;
    }

    /* Player updates */
    uint8_t p1_diff = (uint8_t)(p1_input & (uint8_t)~rt->prev_inputs[0]);
    player_update(&rt->players[0], p1_input, p1_diff, rt->camera_scroll_x, &rt->collision_grid, apu, sound);
    rt->prev_inputs[0] = p1_input;

    if (rt->player_mode == 1) {
        uint8_t p2_diff = (uint8_t)(p2_input & (uint8_t)~rt->prev_inputs[1]);
        player_update(&rt->players[1], p2_input, p2_diff, rt->camera_scroll_x, &rt->collision_grid, apu, sound);
        rt->prev_inputs[1] = p2_input;
    }

    /* Camera scrolling logic (Outdoor horizontal mode) */
    if (rt->level_header.scrolling_type == 0 && rt->level_header.location_type == 0) {
        uint16_t lead_x = rt->players[0].world_x;
        if (rt->player_mode == 1 && rt->players[1].state == PLAYER_STATE_NORMAL && rt->players[1].world_x > lead_x) {
            lead_x = rt->players[1].world_x;
        }

        if (lead_x >= (uint16_t)(rt->camera_scroll_x + 128u)) {
            uint16_t desired_scroll = (uint16_t)(lead_x - 128u);
            uint16_t max_scroll = (uint16_t)(rt->level_header.stop_scrolling_pos * 256u);
            if (desired_scroll > max_scroll) {
                desired_scroll = max_scroll;
            }
            if (desired_scroll > rt->camera_scroll_x) {
                rt->camera_scroll_x = desired_scroll;
            }
        }

        uint8_t cur_screen = (uint8_t)(rt->camera_scroll_x / 256u);
        rt->active_screen_index = cur_screen;
        uint8_t next_screen = (uint8_t)(cur_screen + 1u);

        if (next_screen <= rt->level_header.stop_scrolling_pos && ppu && rt->rom) {
            uint8_t nt_idx = (uint8_t)(next_screen % 2u);
            if (rt->loaded_screens[nt_idx] != next_screen) {
                nametable_unpack_screen_horizontal(ppu, nt_idx, rt->rom, &rt->level_header, next_screen);
                collision_grid_unpack_screen(&rt->collision_grid, rt->rom, &rt->level_header, next_screen, nt_idx);
                rt->loaded_screens[nt_idx] = next_screen;
            }
        }
    }

    if (ppu) {
        ppu->scroll_x = (uint16_t)(rt->camera_scroll_x % 512u);
        ppu->scroll_y = (uint16_t)(rt->camera_scroll_y % 480u);

        memset(ppu->oam, 0xFF, sizeof(ppu->oam));
        player_render_oam(&rt->players[0], ppu->oam, 0);
        if (rt->player_mode == 1) {
            player_render_oam(&rt->players[1], ppu->oam, 2);
        }

        ppu_render_frame(ppu);
    }

    if (sound && apu) {
        sound_engine_update_frame(sound, apu);
    }
}

void game_runtime_render(GameRuntime *rt, Ppu2C02 *ppu) {
    if (!rt || !ppu) return;

    ppu->scroll_x = (uint16_t)(rt->camera_scroll_x % 512u);
    ppu->scroll_y = (uint16_t)(rt->camera_scroll_y % 480u);

    memset(ppu->oam, 0xFF, sizeof(ppu->oam));
    player_render_oam(&rt->players[0], ppu->oam, 0);
    if (rt->player_mode == 1) {
        player_render_oam(&rt->players[1], ppu->oam, 2);
    }

    ppu_render_frame(ppu);
}

uint32_t game_runtime_get_state_hash(const GameRuntime *rt) {
    if (!rt) return 0;

    uint32_t hash = 0x811C9DC5u;

    #define HASH_BYTE(b) do { hash ^= (uint8_t)(b); hash *= 0x01000193u; } while(0)
    #define HASH_WORD(w) do { HASH_BYTE((uint16_t)(w) & 0xFFu); HASH_BYTE(((uint16_t)(w) >> 8) & 0xFFu); } while(0)

    HASH_BYTE(rt->frame_counter);
    HASH_BYTE(rt->random_num);
    HASH_WORD(rt->camera_scroll_x);
    HASH_WORD(rt->camera_scroll_y);
    HASH_BYTE(rt->active_screen_index);

    for (size_t p = 0; p < MAX_PLAYERS; ++p) {
        const Player *pl = &rt->players[p];
        HASH_BYTE(pl->state);
        HASH_WORD(pl->world_x);
        HASH_WORD(pl->world_y);
        HASH_BYTE(pl->screen_x);
        HASH_BYTE(pl->screen_y);
        HASH_BYTE(pl->vel_x);
        HASH_BYTE(pl->vel_y_fast);
        HASH_BYTE(pl->vel_y_fract);
        HASH_BYTE(pl->jump_accum);
        HASH_BYTE(pl->is_jumping ? 1 : 0);
        HASH_BYTE(pl->facing_left ? 1 : 0);
        HASH_BYTE(pl->aim_dir);
        HASH_BYTE(pl->water_state);
        HASH_BYTE(pl->lives);
        HASH_WORD(pl->invincibility_timer);
    }

    #undef HASH_BYTE
    #undef HASH_WORD

    return hash;
}
