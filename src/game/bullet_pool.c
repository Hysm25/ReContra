#include "game/bullet_pool.h"
#include <string.h>

#define BANK6_PRG_BASE 0x18000u
#define BANK6_CPU_BASE 0x8000u
#define PRG_OFFSET(cpu_addr) (BANK6_PRG_BASE + ((size_t)(cpu_addr) - BANK6_CPU_BASE))

ReconResult bullet_pool_init(BulletPool *pool, const RomData *rom) {
    if (!pool || !rom || !rom->prg_data) {
        return RECON_ERR_NULL_PTR;
    }

    memset(pool, 0, sizeof(BulletPool));
    pool->authentic_flicker = false;

    if (rom->prg_size < 0x20000u) {
        return RECON_ERR_OUT_OF_BOUNDS;
    }

    const uint8_t *prg = rom->prg_data;
    pool->tables.pos_offset_ground  = prg + PRG_OFFSET(0xB5FAu);
    pool->tables.pos_offset_air     = prg + PRG_OFFSET(0xB60Eu);
    pool->tables.vel_std_normal     = prg + PRG_OFFSET(0xB6E9u);
    pool->tables.vel_std_rapid      = prg + PRG_OFFSET(0xB719u);
    pool->tables.vel_f_normal       = prg + PRG_OFFSET(0xB779u);
    pool->tables.vel_f_rapid        = prg + PRG_OFFSET(0xB749u);
    pool->tables.f_init_table       = prg + PRG_OFFSET(0xB817u);
    pool->tables.f_swirl_y          = prg + PRG_OFFSET(0xBADEu);
    pool->tables.f_swirl_x          = prg + PRG_OFFSET(0xBAE2u);
    pool->tables.aim_dir_to_s_index = prg + PRG_OFFSET(0xB891u);
    pool->tables.s_index_modifiers  = prg + PRG_OFFSET(0xB89Du);
    pool->tables.s_vel_normal_y     = prg + PRG_OFFSET(0xB8AAu);
    pool->tables.s_vel_normal_x     = prg + PRG_OFFSET(0xB8BAu);
    pool->tables.s_vel_rapid_y      = prg + PRG_OFFSET(0xB8FAu);
    pool->tables.s_vel_rapid_x      = prg + PRG_OFFSET(0xB90Au);
    pool->tables.beam_delays        = prg + PRG_OFFSET(0xB55Du);
    pool->tables.beam_sprites       = prg + PRG_OFFSET(0xBA17u);
    pool->tables.weapon_sounds      = prg + PRG_OFFSET(0xB5A7u);
    pool->tables.weapon_sprites     = prg + PRG_OFFSET(0xB5ABu);

    return RECON_OK;
}

void bullet_pool_clear(BulletPool *pool) {
    if (!pool) return;
    memset(pool->slots, 0, sizeof(pool->slots));
}

static void calculate_spawn_pos(const BulletTables *tables, uint8_t aim_dir,
                                uint8_t player_screen_x, uint8_t player_screen_y,
                                bool is_jumping, uint8_t *out_x, uint8_t *out_y) {
    int8_t off_x = 0;
    int8_t off_y = 0;

    if (is_jumping && tables->pos_offset_air) {
        size_t idx = (size_t)(aim_dir < 12u ? aim_dir : 0u) * 2u;
        off_x = (int8_t)tables->pos_offset_air[idx + 0u];
        off_y = (int8_t)tables->pos_offset_air[idx + 1u];
    } else if (tables->pos_offset_ground) {
        size_t idx = (size_t)(aim_dir < 10u ? aim_dir : 0u) * 2u;
        off_x = (int8_t)tables->pos_offset_ground[idx + 0u];
        off_y = (int8_t)tables->pos_offset_ground[idx + 1u];
    }

    *out_x = (uint8_t)(player_screen_x + off_x);
    *out_y = (uint8_t)(player_screen_y + off_y);
}

static void init_bullet_velocities(const BulletTables *tables, BulletSlot *slot,
                                   WeaponType wtype, bool rapid_fire, uint8_t aim_dir) {
    const uint8_t *vel_table = nullptr;

    if (wtype == WEAPON_TYPE_FIREBALL) {
        vel_table = rapid_fire ? tables->vel_f_rapid : tables->vel_f_normal;
    } else {
        vel_table = rapid_fire ? tables->vel_std_rapid : tables->vel_std_normal;
    }

    if (!vel_table) return;

    size_t idx = (size_t)(aim_dir < 12u ? aim_dir : 0u) * 4u;
    slot->vel_x_fast  = (int8_t)vel_table[idx + 0u];
    slot->vel_x_fract = vel_table[idx + 1u];
    slot->vel_y_fast  = (int8_t)vel_table[idx + 2u];
    slot->vel_y_fract = vel_table[idx + 3u];
}

bool bullet_pool_fire(BulletPool *pool, uint8_t player_id, uint8_t weapon_code,
                      uint8_t aim_dir, uint8_t player_screen_x, uint8_t player_screen_y,
                      bool is_jumping, uint8_t water_state, uint8_t *m_fire_timer,
                      uint8_t input, uint8_t input_diff,
                      Apu2A03 *apu, SoundEngine *sound) {
    if (!pool) return false;

    /* In water: cannot shoot downward */
    if (water_state > 0 && (aim_dir >= 3u && aim_dir <= 6u)) {
        return false;
    }

    WeaponType wtype = (WeaponType)(weapon_code & 0x0Fu);
    bool rapid_fire = (weapon_code & WEAPON_MODIFIER_RAPID_FIRE) != 0;

    /* Continuous fire handling for Machine Gun (M) and Beam (L) */
    if (wtype == WEAPON_TYPE_RAPID) {
        if (!(input & 0x40u)) { /* Button B not held */
            if (m_fire_timer) {
                if ((*m_fire_timer & 0x0Fu) < 7u) {
                    (*m_fire_timer)++;
                } else {
                    *m_fire_timer = (uint8_t)((*m_fire_timer & 0xF0u) | 7u);
                }
            }
            return false;
        }

        /* Button B is held */
        if (m_fire_timer) {
            (*m_fire_timer)++;
            uint8_t t = *m_fire_timer;
            if (t < 0x60u) {
                if ((t & 0x0Fu) != 8u) return false;
            } else {
                if ((t & 0x0Fu) < 0x0Fu) return false;
                t = (uint8_t)(t + 0x0Fu);
                if (t >= 0x70u) {
                    *m_fire_timer = 0;
                } else {
                    *m_fire_timer = (uint8_t)(t & 0xF0u);
                }
            }
        }
    } else if (wtype == WEAPON_TYPE_BEAM) {
        if (!(input & 0x40u) && !(input_diff & 0x40u)) {
            return false;
        }
    } else {
        /* Standard, F, S require newly pressed Button B */
        if (!(input_diff & 0x40u)) {
            return false;
        }
    }

    /* Slot range based on player */
    size_t start_slot = (player_id == 0) ? 0 : 8;
    size_t max_search = (player_id == 0) ? 8 : 16;
    size_t allowed_active = 4;

    if (wtype == WEAPON_TYPE_RAPID) {
        allowed_active = 6;
    } else if (wtype == WEAPON_TYPE_SPREAD) {
        allowed_active = 10;
        start_slot = (player_id == 0) ? 0 : 6;
        max_search = 16;
    }

    /* Count existing active bullets for this player */
    size_t current_count = 0;
    for (size_t i = 0; i < BULLET_POOL_MAX_SLOTS; ++i) {
        if (pool->slots[i].slot_type != 0 && pool->slots[i].owner == player_id) {
            current_count++;
        }
    }

    if (current_count >= allowed_active) {
        return false;
    }

    /* Spawn bullet based on weapon type */
    if (wtype == WEAPON_TYPE_SPREAD) {
        /* Spread gun: up to 5 fan bullets */
        size_t spawned = 0;
        for (size_t k = 0; k < 5u && (current_count + spawned) < allowed_active; ++k) {
            size_t slot_idx = BULLET_POOL_MAX_SLOTS;
            for (size_t s = start_slot; s < max_search; ++s) {
                if (pool->slots[s].slot_type == 0) {
                    slot_idx = s;
                    break;
                }
            }
            if (slot_idx == BULLET_POOL_MAX_SLOTS) break;

            BulletSlot *slot = &pool->slots[slot_idx];
            memset(slot, 0, sizeof(BulletSlot));

            slot->slot_type = (uint8_t)(wtype + 1u);
            slot->owner = player_id;
            slot->aim_dir = aim_dir;
            slot->rapid_flag = rapid_fire ? 1 : 0;
            slot->routine = BULLET_ROUTINE_MOVING;
            slot->sprite_code = 0x1Fu; /* Small bullet */
            slot->sprite_attr = 0x02u;

            calculate_spawn_pos(&pool->tables, aim_dir, player_screen_x, player_screen_y,
                                is_jumping, &slot->pos_x, &slot->pos_y);

            /* Angle calculation using dynamic ROM tables */
            uint8_t base_angle = pool->tables.aim_dir_to_s_index ? pool->tables.aim_dir_to_s_index[aim_dir < 12u ? aim_dir : 0u] : 0u;
            int mod = pool->tables.s_index_modifiers ? (int)(int8_t)pool->tables.s_index_modifiers[k] : 0;
            int angle_sum = (int)base_angle + mod;
            uint8_t angle_idx = (uint8_t)(angle_sum & 0x1F);
            size_t byte_off = (size_t)angle_idx * 2u;

            if (rapid_fire && pool->tables.s_vel_rapid_y && pool->tables.s_vel_rapid_x) {
                slot->vel_y_fract = pool->tables.s_vel_rapid_y[byte_off + 0u];
                slot->vel_y_fast  = (int8_t)pool->tables.s_vel_rapid_y[byte_off + 1u];
                slot->vel_x_fract = pool->tables.s_vel_rapid_x[byte_off + 0u];
                slot->vel_x_fast  = (int8_t)pool->tables.s_vel_rapid_x[byte_off + 1u];
            } else if (pool->tables.s_vel_normal_y && pool->tables.s_vel_normal_x) {
                slot->vel_y_fract = pool->tables.s_vel_normal_y[byte_off + 0u];
                slot->vel_y_fast  = (int8_t)pool->tables.s_vel_normal_y[byte_off + 1u];
                slot->vel_x_fract = pool->tables.s_vel_normal_x[byte_off + 0u];
                slot->vel_x_fast  = (int8_t)pool->tables.s_vel_normal_x[byte_off + 1u];
            }

            spawned++;
        }

        if (spawned > 0 && sound && apu && pool->tables.weapon_sounds) {
            sound_engine_play_sound(sound, apu, pool->tables.weapon_sounds[3]);
        }
        return spawned > 0;
    }

    if (wtype == WEAPON_TYPE_BEAM) {
        /* Beam weapon: 4 connected segments with delay counters */
        size_t spawned = 0;
        for (int k = 3; k >= 0; --k) {
            size_t slot_idx = BULLET_POOL_MAX_SLOTS;
            for (size_t s = start_slot; s < max_search; ++s) {
                if (pool->slots[s].slot_type == 0) {
                    slot_idx = s;
                    break;
                }
            }
            if (slot_idx == BULLET_POOL_MAX_SLOTS) break;

            BulletSlot *slot = &pool->slots[slot_idx];
            memset(slot, 0, sizeof(BulletSlot));

            slot->slot_type = (uint8_t)(wtype + 1u);
            slot->owner = player_id;
            slot->aim_dir = aim_dir;
            slot->rapid_flag = 1;
            slot->routine = BULLET_ROUTINE_INIT; /* Delay phase */
            slot->timer = pool->tables.beam_delays ? pool->tables.beam_delays[(size_t)k] : (uint8_t)((k + 1) * 3);

            calculate_spawn_pos(&pool->tables, aim_dir, player_screen_x, player_screen_y,
                                is_jumping, &slot->pos_x, &slot->pos_y);

            init_bullet_velocities(&pool->tables, slot, wtype, true, aim_dir);
            spawned++;
        }

        if (spawned > 0 && sound && apu && pool->tables.weapon_sounds) {
            sound_engine_play_sound(sound, apu, pool->tables.weapon_sounds[4]);
        }
        return spawned > 0;
    }

    /* Standard, M, and F weapons: single bullet allocation */
    size_t slot_idx = BULLET_POOL_MAX_SLOTS;
    for (size_t s = start_slot; s < max_search; ++s) {
        if (pool->slots[s].slot_type == 0) {
            slot_idx = s;
            break;
        }
    }
    if (slot_idx == BULLET_POOL_MAX_SLOTS) {
        return false;
    }

    BulletSlot *slot = &pool->slots[slot_idx];
    memset(slot, 0, sizeof(BulletSlot));

    slot->slot_type = (uint8_t)(wtype + 1u);
    slot->owner = player_id;
    slot->aim_dir = aim_dir;
    slot->rapid_flag = rapid_fire ? 1 : 0;
    slot->routine = BULLET_ROUTINE_MOVING;

    /* Base sprite code from ROM table */
    if (pool->tables.weapon_sprites) {
        slot->sprite_code = pool->tables.weapon_sprites[(size_t)wtype + 1u];
    } else {
        slot->sprite_code = 0x1Eu;
    }
    slot->sprite_attr = 0x02u;

    calculate_spawn_pos(&pool->tables, aim_dir, player_screen_x, player_screen_y,
                        is_jumping, &slot->pos_x, &slot->pos_y);

    init_bullet_velocities(&pool->tables, slot, wtype, rapid_fire, aim_dir);

    /* F weapon swirl center initialization */
    if (wtype == WEAPON_TYPE_FIREBALL && pool->tables.f_init_table) {
        size_t f_idx = (size_t)(aim_dir < 12u ? aim_dir : 0u) * 3u;
        slot->timer = pool->tables.f_init_table[f_idx + 0u];
        slot->fs_x  = (uint8_t)(slot->pos_x + (int8_t)pool->tables.f_init_table[f_idx + 1u]);
        slot->f_y   = (uint8_t)(slot->pos_y + (int8_t)pool->tables.f_init_table[f_idx + 2u]);
    }

    if (sound && apu && pool->tables.weapon_sounds) {
        sound_engine_play_sound(sound, apu, pool->tables.weapon_sounds[(size_t)wtype]);
    }

    return true;
}

void bullet_pool_update(BulletPool *pool, int16_t scroll_delta, const CollisionGrid *grid) {
    if (!pool) return;

    for (size_t i = 0; i < BULLET_POOL_MAX_SLOTS; ++i) {
        BulletSlot *slot = &pool->slots[i];
        if (slot->slot_type == 0) continue;

        /* Delay routine (Beam segments waiting to activate) */
        if (slot->routine == BULLET_ROUTINE_INIT) {
            if (scroll_delta != 0) {
                slot->pos_x = (uint8_t)(slot->pos_x - scroll_delta);
                slot->fs_x  = (uint8_t)(slot->fs_x - scroll_delta);
            }

            if (slot->timer > 0) {
                slot->timer--;
            }
            if (slot->timer == 0) {
                slot->routine = BULLET_ROUTINE_MOVING;
                if (pool->tables.beam_sprites) {
                    size_t s_idx = (size_t)(slot->aim_dir < 12u ? slot->aim_dir : 0u) * 2u;
                    slot->sprite_code = pool->tables.beam_sprites[s_idx + 0u];
                    slot->sprite_attr = pool->tables.beam_sprites[s_idx + 1u];
                }
            }
            continue;
        }

        /* Active moving bullet */
        if (slot->routine == BULLET_ROUTINE_MOVING) {
            /* Screen scroll delta adjustment */
            if (scroll_delta != 0) {
                slot->pos_x = (uint8_t)(slot->pos_x - scroll_delta);
                slot->fs_x  = (uint8_t)(slot->fs_x - scroll_delta);
            }

            /* Fireball swirl trajectory */
            if (slot->slot_type == (uint8_t)(WEAPON_TYPE_FIREBALL + 1u)) {
                /* Update center coordinates */
                uint16_t y_acc = (uint16_t)slot->vel_f_y_accum + slot->vel_y_fract;
                slot->vel_f_y_accum = (uint8_t)(y_acc & 0xFFu);
                slot->f_y = (uint8_t)(slot->f_y + slot->vel_y_fast + (int8_t)(y_acc >> 8));

                uint16_t x_acc = (uint16_t)slot->vel_fs_x_accum + slot->vel_x_fract;
                slot->vel_fs_x_accum = (uint8_t)(x_acc & 0xFFu);
                slot->fs_x = (uint8_t)(slot->fs_x + slot->vel_x_fast + (int8_t)(x_acc >> 8));

                /* Apply authentic swirl lookup */
                if (pool->tables.f_swirl_x && pool->tables.f_swirl_y) {
                    uint8_t sw_idx = slot->timer & 0x0Fu;
                    slot->pos_x = (uint8_t)(slot->fs_x + (int8_t)pool->tables.f_swirl_x[sw_idx]);
                    slot->pos_y = (uint8_t)(slot->f_y  + (int8_t)pool->tables.f_swirl_y[sw_idx]);
                }

                if (slot->aim_dir == 0x0Au) {
                    slot->timer++;
                } else if (slot->aim_dir >= 5u) {
                    slot->timer--;
                } else {
                    slot->timer++;
                }
            } else {
                /* Standard, M, S, L sub-pixel trajectory */
                uint16_t x_acc = (uint16_t)slot->vel_x_accum + slot->vel_x_fract;
                slot->vel_x_accum = (uint8_t)(x_acc & 0xFFu);
                slot->pos_x = (uint8_t)(slot->pos_x + slot->vel_x_fast + (int8_t)(x_acc >> 8));

                uint16_t y_acc = (uint16_t)slot->vel_y_accum + slot->vel_y_fract;
                slot->vel_y_accum = (uint8_t)(y_acc & 0xFFu);
                slot->pos_y = (uint8_t)(slot->pos_y + slot->vel_y_fast + (int8_t)(y_acc >> 8));

                /* Spread gun distance sprite sizing */
                if (slot->slot_type == (uint8_t)(WEAPON_TYPE_SPREAD + 1u)) {
                    if (slot->dist < 255u) slot->dist++;
                    if (slot->dist >= 32u) {
                        slot->sprite_code = 0x21u; /* Large pellet */
                    } else if (slot->dist >= 16u) {
                        slot->sprite_code = 0x20u; /* Medium pellet */
                    } else {
                        slot->sprite_code = 0x1Fu; /* Small pellet */
                    }
                }
            }

            /* Solid background wall collision */
            if (grid) {
                uint8_t tile_code = collision_grid_get_code(grid, slot->pos_x, slot->pos_y);
                if (tile_code == COLLISION_CODE_SOLID) {
                    slot->routine = BULLET_ROUTINE_IMPACT;
                    slot->timer = 6u;
                    slot->sprite_code = 0x47u; /* Impact hollow ring tile */
                    continue;
                }
            }

            /* Off-screen boundary check */
            if (slot->pos_x < 5u || slot->pos_x > 251u || slot->pos_y < 5u || slot->pos_y > 232u) {
                memset(slot, 0, sizeof(BulletSlot));
            }
            continue;
        }

        /* Impact decay routine */
        if (slot->routine == BULLET_ROUTINE_IMPACT) {
            if (scroll_delta != 0) {
                slot->pos_x = (uint8_t)(slot->pos_x - scroll_delta);
            }
            if (slot->timer > 0) {
                slot->timer--;
            }
            if (slot->timer == 0) {
                memset(slot, 0, sizeof(BulletSlot));
            }
        }
    }
}

size_t bullet_pool_render_oam(const BulletPool *pool, uint8_t *oam_buffer,
                              size_t oam_entry_start, uint8_t frame_counter) {
    if (!pool || !oam_buffer) return 0;

    size_t oam_idx = oam_entry_start;
    size_t rendered_count = 0;

    if (pool->authentic_flicker) {
        /* Authentic NES Contra alternating 8-slot priority cycle */
        uint8_t phase = frame_counter & 0x01u;
        for (uint8_t y = 0; y < 8u; ++y) {
            uint8_t slot_num = (uint8_t)((y * 2u) | phase);
            const BulletSlot *slot = &pool->slots[slot_num];
            if (slot->slot_type == 0 || slot->routine == BULLET_ROUTINE_INACTIVE || slot->routine == BULLET_ROUTINE_INIT) {
                continue;
            }
            if (slot->pos_y >= 240u) continue;

            size_t oam_off = oam_idx * 4u;
            if (oam_off + 4u > 256u) break;

            oam_buffer[oam_off + 0u] = (uint8_t)(slot->pos_y - 8u);
            oam_buffer[oam_off + 1u] = slot->sprite_code;
            oam_buffer[oam_off + 2u] = slot->sprite_attr;
            oam_buffer[oam_off + 3u] = (uint8_t)(slot->pos_x - 4u);

            oam_idx++;
            rendered_count++;
        }
    } else {
        /* Flicker-free rendering of all active bullets */
        for (size_t s = 0; s < BULLET_POOL_MAX_SLOTS; ++s) {
            const BulletSlot *slot = &pool->slots[s];
            if (slot->slot_type == 0 || slot->routine == BULLET_ROUTINE_INACTIVE || slot->routine == BULLET_ROUTINE_INIT) {
                continue;
            }
            if (slot->pos_y >= 240u) continue;

            size_t oam_off = oam_idx * 4u;
            if (oam_off + 4u > 256u) break;

            /* Check 2-tile horizontal laser beam */
            if (slot->sprite_code == 0x24u) {
                if (oam_off + 8u > 256u) break;
                oam_buffer[oam_off + 0u] = (uint8_t)(slot->pos_y - 8u);
                oam_buffer[oam_off + 1u] = 0x24u;
                oam_buffer[oam_off + 2u] = slot->sprite_attr;
                oam_buffer[oam_off + 3u] = (uint8_t)(slot->pos_x - 12u);

                oam_buffer[oam_off + 4u] = (uint8_t)(slot->pos_y - 8u);
                oam_buffer[oam_off + 5u] = 0x24u;
                oam_buffer[oam_off + 6u] = slot->sprite_attr;
                oam_buffer[oam_off + 7u] = (uint8_t)(slot->pos_x - 4u);

                oam_idx += 2u;
                rendered_count += 2u;
                continue;
            }

            oam_buffer[oam_off + 0u] = (uint8_t)(slot->pos_y - 8u);
            oam_buffer[oam_off + 1u] = slot->sprite_code;
            oam_buffer[oam_off + 2u] = slot->sprite_attr;
            oam_buffer[oam_off + 3u] = (uint8_t)(slot->pos_x - 4u);

            oam_idx++;
            rendered_count++;
        }
    }

    return rendered_count;
}
