#include "game/player.h"
#include <string.h>

#define AIM_TABLE_ROM_OFFSET 0x1D93Au /* PRG Bank 7 CPU $D93A */

ReconResult player_init(Player *player, uint8_t player_id, const RomData *rom) {
    if (!player) {
        return RECON_ERR_NULL_PTR;
    }

    memset(player, 0, sizeof(Player));
    player->player_id = player_id;
    player->lives = PLAYER_DEFAULT_LIVES;
    player->current_weapon = 0;

    if (rom && rom->prg_data && AIM_TABLE_ROM_OFFSET + 64u <= rom->prg_size) {
        player->aim_table = rom->prg_data + AIM_TABLE_ROM_OFFSET;
    } else {
        player->aim_table = NULL;
    }

    player_spawn(player, (uint16_t)(PLAYER_DEFAULT_SPAWN_X + (uint16_t)player_id * 32u), PLAYER_DEFAULT_SPAWN_Y);
    return RECON_OK;
}

void player_spawn(Player *player, uint16_t spawn_x, uint16_t spawn_y) {
    if (!player) return;

    player->world_x = spawn_x;
    player->world_y = spawn_y;
    player->screen_x = (uint8_t)spawn_x;
    player->screen_y = (uint8_t)spawn_y;

    player->vel_x = 0;
    player->vel_y_fast = 0;
    player->vel_y_fract = 0;
    player->jump_accum = 0;

    player->is_jumping = false;
    player->is_crouching = false;
    player->facing_left = false;
    player->aim_dir = AIM_DIR_RIGHT;
    player->water_state = 0;
    player->edge_fall_code = 0;

    player->invincibility_timer = PLAYER_INVINCIBLE_RESPAWN;
    player->anim_timer = 0;
    player->anim_frame = 0;
    player->sprite_sequence = 0;

    player->state = PLAYER_STATE_SPAWNING;
}

void player_take_hit(Player *player, Apu2A03 *apu, SoundEngine *sound) {
    if (!player) return;
    if (player->invincibility_timer > 0) return; /* Invincible */
    if (player->state != PLAYER_STATE_NORMAL && player->state != PLAYER_STATE_SPAWNING) return;

    if (player->lives > 0) {
        player->lives--;
    }

    if (player->lives == 0) {
        player->state = PLAYER_STATE_GAMEOVER;
    } else {
        player->state = PLAYER_STATE_DYING;
    }

    /* Authentic backward recoil arc */
    player->vel_y_fast = -4;
    player->vel_y_fract = 0;
    player->vel_x = player->facing_left ? 1 : -1;
    player->is_jumping = true;

    if (sound && apu) {
        sound_engine_play_sound(sound, apu, 0x52u); /* Death SFX */
    }
}

void player_update(Player *player, uint8_t input, uint8_t input_diff,
                   uint16_t camera_scroll_x, const CollisionGrid *grid,
                   Apu2A03 *apu, SoundEngine *sound) {
    if (!player) return;

    if (player->state == PLAYER_STATE_GAMEOVER) {
        return;
    }

    if (player->invincibility_timer > 0) {
        player->invincibility_timer--;
    }

    /* 1. Spawning / Dropping into Stage */
    if (player->state == PLAYER_STATE_SPAWNING) {
        player->vel_y_fast = 2;
        player->world_y = (uint16_t)(player->world_y + 2u);

        uint8_t feet_code = collision_grid_get_code(grid, (uint16_t)(player->world_x + 8u), (uint16_t)(player->world_y + 32u));
        if (feet_code == COLLISION_CODE_FLOOR) {
            uint16_t check_y = (uint16_t)(player->world_y + 32u);
            if (check_y >= 16u && check_y < 240u) {
                uint8_t row = (uint8_t)((check_y - 16u) / 16u);
                player->world_y = (uint16_t)(16u + (uint16_t)row * 16u - 32u);
            }
            player->state = PLAYER_STATE_NORMAL;
            player->vel_y_fast = 0;
            player->is_jumping = false;
            if (sound && apu) {
                sound_engine_play_sound(sound, apu, 0x03u); /* Landing SFX */
            }
        }
        if (player->world_x < camera_scroll_x) {
            player->world_x = camera_scroll_x;
        } else if (player->world_x > (uint16_t)(camera_scroll_x + 240u)) {
            player->world_x = (uint16_t)(camera_scroll_x + 240u);
        }
        player->screen_x = (uint8_t)(player->world_x - camera_scroll_x);
        player->screen_y = (uint8_t)player->world_y;
        return;
    }

    /* 2. Dying Animation Arc */
    if (player->state == PLAYER_STATE_DYING) {
        /* Apply Gravity */
        uint16_t grav_sum = (uint16_t)player->vel_y_fract + PLAYER_GRAVITY_ACCEL_FRACT;
        player->vel_y_fract = (uint8_t)(grav_sum & 0xFFu);
        player->vel_y_fast = (int8_t)(player->vel_y_fast + (int8_t)(grav_sum >> 8));

        player->world_y = (uint16_t)(player->world_y + player->vel_y_fast);
        player->world_x = (uint16_t)(player->world_x + player->vel_x);

        if (player->world_y >= 235u) {
            /* Respawn if lives remain */
            if (player->lives > 0) {
                player_spawn(player, (uint16_t)(camera_scroll_x + 48u), PLAYER_DEFAULT_SPAWN_Y);
            } else {
                player->state = PLAYER_STATE_GAMEOVER;
            }
        }
        if (player->world_x < camera_scroll_x) {
            player->world_x = camera_scroll_x;
        } else if (player->world_x > (uint16_t)(camera_scroll_x + 240u)) {
            player->world_x = (uint16_t)(camera_scroll_x + 240u);
        }
        player->screen_x = (uint8_t)(player->world_x - camera_scroll_x);
        player->screen_y = (uint8_t)player->world_y;
        return;
    }

    /* 3. Normal Gameplay State */
    if (player->state == PLAYER_STATE_NORMAL) {
        /* 3.1 Aim Direction & Facing Resolution */
        uint8_t row = 0;
        if (player->is_jumping) {
            row = 0x30u;
        } else if (player->facing_left) {
            row = 0x10u;
        }

        uint8_t dpad = (uint8_t)(input & 0x0Fu);
        if (player->aim_table) {
            player->aim_dir = player->aim_table[row + dpad];
        } else {
            /* Fallback 8-direction aim */
            if (dpad & GAME_INPUT_UP) {
                if (dpad & GAME_INPUT_RIGHT) player->aim_dir = AIM_DIR_UP_RIGHT;
                else if (dpad & GAME_INPUT_LEFT) player->aim_dir = AIM_DIR_UP_LEFT;
                else player->aim_dir = player->facing_left ? AIM_DIR_UP_FACING_LEFT : AIM_DIR_UP_FACING_RIGHT;
            } else if (dpad & GAME_INPUT_DOWN) {
                if (dpad & GAME_INPUT_RIGHT) player->aim_dir = AIM_DIR_DOWN_RIGHT;
                else if (dpad & GAME_INPUT_LEFT) player->aim_dir = AIM_DIR_DOWN_LEFT;
                else player->aim_dir = player->facing_left ? AIM_DIR_CROUCH_LEFT : AIM_DIR_CROUCH_RIGHT;
            } else if (dpad & GAME_INPUT_LEFT) {
                player->aim_dir = AIM_DIR_LEFT;
            } else {
                player->aim_dir = AIM_DIR_RIGHT;
            }
        }

        if (dpad & GAME_INPUT_LEFT) {
            player->facing_left = true;
        } else if (dpad & GAME_INPUT_RIGHT) {
            player->facing_left = false;
        }

        /* 3.2 Water State Handling */
        if (player->water_state > 0) {
            if (input & GAME_INPUT_DOWN) {
                player->water_state = 2; /* Submerged dive */
                player->vel_x = 0;
            } else {
                player->water_state = 1; /* Surface swimming */
                if (input & GAME_INPUT_RIGHT) player->vel_x = 1;
                else if (input & GAME_INPUT_LEFT) player->vel_x = -1;
                else player->vel_x = 0;
            }
            player->is_jumping = false;
            player->is_crouching = false;
        } else {
            /* 3.3 Land Movement, Jump & Crouch */
            if ((input_diff & GAME_INPUT_A) && (input & GAME_INPUT_A)) {
                /* A Button newly pressed */
                if ((input & 0x07u) == GAME_INPUT_DOWN) {
                    /* Down + Jump: Drop Down through floor */
                    if (collision_grid_can_drop_down(grid, (uint16_t)(player->world_x + 8u), player->world_y)) {
                        player->edge_fall_code = 12u;
                        player->is_jumping = true;
                        player->is_crouching = false;
                        player->vel_y_fast = 1;
                        player->vel_y_fract = 0;
                    }
                } else if (!player->is_jumping) {
                    /* Authentic Initial Jump Impulse: -5.9375 px/frame */
                    player->is_jumping = true;
                    player->is_crouching = false;
                    player->vel_y_fast = PLAYER_JUMP_VEL_FAST_OUTDOOR;
                    player->vel_y_fract = PLAYER_JUMP_VEL_FRACT_OUTDOOR;
                    player->jump_accum = 0;

                    if (sound && apu) {
                        sound_engine_play_sound(sound, apu, 0x03u); /* Jump sound */
                    }
                }
            }

            if (!player->is_jumping) {
                if ((input & 0x0Fu) == GAME_INPUT_DOWN) {
                    player->is_crouching = true;
                    player->vel_x = 0;
                } else {
                    player->is_crouching = false;
                    if (input & GAME_INPUT_RIGHT) player->vel_x = 1;
                    else if (input & GAME_INPUT_LEFT) player->vel_x = -1;
                    else player->vel_x = 0;
                }
            } else {
                /* Mid-air steering */
                if (input & GAME_INPUT_RIGHT) player->vel_x = 1;
                else if (input & GAME_INPUT_LEFT) player->vel_x = -1;
                else player->vel_x = 0;
            }
        }

        /* 3.4 Horizontal Motion & Wall Collision */
        if (player->vel_x != 0) {
            int32_t next_x_signed = (int32_t)player->world_x + player->vel_x;
            if (next_x_signed < (int32_t)camera_scroll_x) {
                player->world_x = camera_scroll_x;
            } else {
                uint16_t next_x = (uint16_t)next_x_signed;
                uint8_t side_x = (player->vel_x > 0) ? (uint8_t)16 : (uint8_t)0;
                uint8_t wall_code = collision_grid_get_code(grid, (uint16_t)(next_x + side_x), (uint16_t)(player->world_y + 16u));

                if (wall_code != COLLISION_CODE_SOLID) {
                    player->world_x = next_x;
                }
            }
        }

        /* 3.5 Vertical Motion, Gravity & Floor Collision */
        if (player->is_jumping || player->edge_fall_code > 0) {
            /* Apply Gravity: +0.1367 px/frame^2 */
            uint16_t grav_sum = (uint16_t)player->vel_y_fract + PLAYER_GRAVITY_ACCEL_FRACT;
            player->vel_y_fract = (uint8_t)(grav_sum & 0xFFu);
            player->vel_y_fast = (int8_t)(player->vel_y_fast + (int8_t)(grav_sum >> 8));

            uint16_t y_accum = (uint16_t)player->jump_accum + player->vel_y_fract;
            player->jump_accum = (uint8_t)(y_accum & 0xFFu);
            int16_t delta_y = (int16_t)(player->vel_y_fast + (int16_t)(y_accum >> 8));
            player->world_y = (uint16_t)(player->world_y + delta_y);

            if (player->edge_fall_code > 0) {
                player->edge_fall_code--;
            }

            /* Landing check when descending */
            if (player->vel_y_fast >= 0 && player->edge_fall_code == 0) {
                uint8_t feet_code = collision_grid_get_code(grid, (uint16_t)(player->world_x + 8u), (uint16_t)(player->world_y + 32u));

                if (feet_code == COLLISION_CODE_FLOOR) {
                    uint16_t check_y = (uint16_t)(player->world_y + 32u);
                    if (check_y >= 16u && check_y < 240u) {
                        uint8_t row = (uint8_t)((check_y - 16u) / 16u);
                        player->world_y = (uint16_t)(16u + (uint16_t)row * 16u - 32u);
                    }
                    player->is_jumping = false;
                    player->vel_y_fast = 0;
                    player->vel_y_fract = 0;

                    if (sound && apu) {
                        sound_engine_play_sound(sound, apu, 0x03u); /* Landing SFX */
                    }
                } else if (feet_code == COLLISION_CODE_WATER) {
                    player->water_state = 1; /* Surface swim */
                    player->is_jumping = false;
                    player->vel_y_fast = 0;
                    player->vel_y_fract = 0;
                }
            }
        } else if (player->water_state == 0) {
            /* Check walking off ledge */
            uint8_t feet_code = collision_grid_get_code(grid, (uint16_t)(player->world_x + 8u), (uint16_t)(player->world_y + 33u));
            if (feet_code == COLLISION_CODE_EMPTY) {
                player->is_jumping = true;
                player->vel_y_fast = 0;
                player->vel_y_fract = 0;
            } else if (feet_code == COLLISION_CODE_WATER) {
                player->water_state = 1;
            }
        }

        /* 3.6 Bottom Pit / Death Check */
        if (player->world_y >= 235u) {
            player_take_hit(player, apu, sound);
        }

        if (player->world_x < camera_scroll_x) {
            player->world_x = camera_scroll_x;
        } else if (player->world_x > (uint16_t)(camera_scroll_x + 240u)) {
            player->world_x = (uint16_t)(camera_scroll_x + 240u);
        }
        player->screen_x = (uint8_t)(player->world_x - camera_scroll_x);
        player->screen_y = (uint8_t)player->world_y;
    }
}

void player_render_oam(const Player *player, uint8_t *oam_buffer, size_t oam_entry_start) {
    if (!player || !oam_buffer) return;
    if (player->state == PLAYER_STATE_GAMEOVER) return;

    /* Invincibility flicker: hide every second frame */
    if (player->invincibility_timer > 0 && (player->invincibility_timer & 0x02u)) {
        return;
    }

    size_t oam_offset = oam_entry_start * 4u;
    if (oam_offset + 8u > 256u) return;

    uint8_t attr = (uint8_t)(player->facing_left ? 0x40u : 0x00u);
    attr = (uint8_t)(attr | (player->player_id & 0x03u));

    /* 8x16 sprite mode: upper tile is even index */
    uint8_t tile_idx = 0x00;
    if (player->water_state > 0) {
        /* Water: half submerged, only upper half drawn */
        oam_buffer[oam_offset + 0] = player->screen_y;
        oam_buffer[oam_offset + 1] = tile_idx;
        oam_buffer[oam_offset + 2] = attr;
        oam_buffer[oam_offset + 3] = player->screen_x;
    } else {
        /* Upper 8x16 Torso */
        oam_buffer[oam_offset + 0] = player->screen_y;
        oam_buffer[oam_offset + 1] = tile_idx;
        oam_buffer[oam_offset + 2] = attr;
        oam_buffer[oam_offset + 3] = player->screen_x;

        /* Lower 8x16 Legs */
        oam_buffer[oam_offset + 4] = (uint8_t)(player->screen_y + 16u);
        oam_buffer[oam_offset + 5] = (uint8_t)(tile_idx + 2u);
        oam_buffer[oam_offset + 6] = attr;
        oam_buffer[oam_offset + 7] = player->screen_x;
    }
}
