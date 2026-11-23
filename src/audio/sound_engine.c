#include "audio/sound_engine.h"
#include <string.h>

static inline uint8_t read_prg_byte(const SoundEngine *engine, uint16_t cpu_addr) {
    if (!engine || !engine->prg_data) return 0;
    size_t prg_offset = 0;
    if (cpu_addr >= 0x8000u && cpu_addr <= 0xBFFFu) {
        /* PRG Bank 1 */
        prg_offset = 0x4000u + (size_t)(cpu_addr - 0x8000u);
    } else if (cpu_addr >= 0xC000u) {
        /* PRG Bank 7 (Fixed) */
        prg_offset = 0x1C000u + (size_t)(cpu_addr - 0xC000u);
    } else {
        prg_offset = (size_t)cpu_addr;
    }

    if (prg_offset < engine->prg_size) {
        return engine->prg_data[prg_offset];
    }
    return 0;
}

static inline uint8_t read_prg_offset(const SoundEngine *engine, size_t prg_offset) {
    if (!engine || !engine->prg_data || prg_offset >= engine->prg_size) {
        return 0;
    }
    return engine->prg_data[prg_offset];
}

static void mute_channel(Apu2A03 *apu, uint8_t slot_idx) {
    if (!apu) return;
    switch (slot_idx) {
    case SOUND_SLOT_BGM_PULSE1:
    case SOUND_SLOT_SFX_PULSE1:
        apu_write_register(apu, APU_REG_PULSE1_CTRL, 0x30u);
        break;
    case SOUND_SLOT_BGM_PULSE2:
        apu_write_register(apu, APU_REG_PULSE2_CTRL, 0x30u);
        break;
    case SOUND_SLOT_BGM_TRI:
        apu_write_register(apu, APU_REG_TRI_CTRL, 0x00u);
        break;
    case SOUND_SLOT_BGM_PERC:
    case SOUND_SLOT_SFX_NOISE:
        apu_write_register(apu, APU_REG_NOISE_CTRL, 0x30u);
        break;
    default:
        break;
    }
}

static void write_channel_reg(const SoundEngine *engine, Apu2A03 *apu, uint8_t slot_idx, uint8_t reg_offset, uint8_t val) {
    if (!apu || !engine) return;

    /* Slot priority arbitration */
    if (slot_idx == SOUND_SLOT_BGM_PULSE1 && engine->slots[SOUND_SLOT_SFX_PULSE1].sound_code != 0) {
        return; /* SFX pulse 1 overrides BGM pulse 1 */
    }
    if (slot_idx == SOUND_SLOT_BGM_PERC && engine->slots[SOUND_SLOT_SFX_NOISE].sound_code != 0) {
        return; /* SFX noise overrides BGM noise */
    }

    uint16_t base_reg = 0;
    switch (slot_idx) {
    case SOUND_SLOT_BGM_PULSE1:
    case SOUND_SLOT_SFX_PULSE1:
        base_reg = APU_REG_PULSE1_CTRL;
        break;
    case SOUND_SLOT_BGM_PULSE2:
        base_reg = APU_REG_PULSE2_CTRL;
        break;
    case SOUND_SLOT_BGM_TRI:
        base_reg = APU_REG_TRI_CTRL;
        break;
    case SOUND_SLOT_BGM_PERC:
    case SOUND_SLOT_SFX_NOISE:
        base_reg = APU_REG_NOISE_CTRL;
        break;
    default:
        return;
    }

    apu_write_register(apu, (uint16_t)(base_reg + reg_offset), val);
}

ReconResult sound_engine_init(SoundEngine *engine, const RomData *rom) {
    if (!engine || !rom || !rom->prg_data) {
        return RECON_ERR_NULL_PTR;
    }

    memset(engine, 0, sizeof(SoundEngine));
    engine->prg_data = rom->prg_data;
    engine->prg_size = rom->prg_size;
    engine->is_loaded = true;
    engine->is_paused = false;

    return RECON_OK;
}

void sound_engine_reset(SoundEngine *engine) {
    if (!engine) return;
    const uint8_t *prg = engine->prg_data;
    size_t size = engine->prg_size;

    memset(engine, 0, sizeof(SoundEngine));
    engine->prg_data = prg;
    engine->prg_size = size;
    engine->is_loaded = (prg != NULL);
}

void sound_engine_set_paused(SoundEngine *engine, bool paused) {
    if (!engine) return;
    engine->is_paused = paused;
}

ReconResult sound_engine_play_sound(SoundEngine *engine, Apu2A03 *apu, uint8_t sound_code) {
    if (!engine || !engine->is_loaded || sound_code == 0) {
        return RECON_ERR_NULL_PTR;
    }

    /* 1. DPCM Sample Trigger (sound codes >= 0x5A) */
    if (sound_code >= 0x5Au) {
        if (!apu) return RECON_ERR_NULL_PTR;
        size_t dpcm_entry_offset = ROM_DPCM_TABLE_OFFSET + (size_t)(sound_code - 0x5Au) * 4u;
        if (dpcm_entry_offset + 3u < engine->prg_size) {
            uint8_t dmc_cfg = read_prg_offset(engine, dpcm_entry_offset);
            uint8_t dmc_counter = read_prg_offset(engine, dpcm_entry_offset + 1u);
            uint8_t s_addr = read_prg_offset(engine, dpcm_entry_offset + 2u);
            uint8_t s_len = read_prg_offset(engine, dpcm_entry_offset + 3u);

            /* Enable 5 channels */
            apu_write_register(apu, APU_REG_STATUS, 0x0Fu);
            apu_write_register(apu, APU_REG_DMC_CTRL, dmc_cfg);
            apu_write_register(apu, APU_REG_DMC_DIRECT, dmc_counter);
            apu_write_register(apu, APU_REG_DMC_ADDR, s_addr);
            apu_write_register(apu, APU_REG_DMC_LENGTH, s_len);
            apu_write_register(apu, APU_REG_STATUS, 0x1Fu);
        }
        return RECON_OK;
    }

    /* 2. Standard Sound Table Lookup */
    size_t base_entry_off = ROM_SOUND_TABLE_OFFSET + (size_t)sound_code * 3u;
    if (base_entry_off + 2u >= engine->prg_size) {
        return RECON_ERR_OUT_OF_BOUNDS;
    }

    uint8_t ctrl = read_prg_offset(engine, base_entry_off);
    uint8_t extra_slots = (uint8_t)((ctrl >> 3) & 0x03u);

    for (uint8_t e = 0; e <= extra_slots; ++e) {
        size_t entry_off = ROM_SOUND_TABLE_OFFSET + (size_t)(sound_code + e) * 3u;
        if (entry_off + 2u >= engine->prg_size) break;

        uint8_t c_byte = read_prg_offset(engine, entry_off);
        uint8_t slot_idx = (uint8_t)(c_byte & 0x07u);
        if (slot_idx >= SOUND_SLOT_COUNT) continue;

        uint8_t alo = read_prg_offset(engine, entry_off + 1u);
        uint8_t ahi = read_prg_offset(engine, entry_off + 2u);
        uint16_t addr = (uint16_t)(alo | ((uint16_t)ahi << 8));

        /* SFX priority check: don't overwrite higher code if already playing */
        if (engine->slots[slot_idx].sound_code != 0 && sound_code < engine->slots[slot_idx].sound_code) {
            continue;
        }

        SoundSlot *slot = &engine->slots[slot_idx];
        memset(slot, 0, sizeof(SoundSlot));
        slot->sound_code = sound_code;
        slot->cmd_addr = addr;
        slot->pulse_length = 0xF8u;
        slot->cmd_length = 1u;
        slot->repeat_count = 0u;
        slot->pitch_adjust = 0u;

        uint8_t byte0 = read_prg_byte(engine, addr);
        if (byte0 < 0x30u) {
            slot->flags = 0x01u; /* Low sound code */
        } else {
            slot->flags = 0x00u; /* High sound code */
        }

        /* Initial channel mute / sweep reset */
        if (apu) {
            if (slot_idx == SOUND_SLOT_BGM_PULSE1 || slot_idx == SOUND_SLOT_SFX_PULSE1) {
                write_channel_reg(engine, apu, slot_idx, 0, 0x30u);
                write_channel_reg(engine, apu, slot_idx, 1, 0x7Fu);
            } else if (slot_idx == SOUND_SLOT_BGM_PULSE2) {
                write_channel_reg(engine, apu, slot_idx, 0, 0x30u);
                write_channel_reg(engine, apu, slot_idx, 1, 0x7Fu);
            } else if (slot_idx == SOUND_SLOT_BGM_TRI) {
                write_channel_reg(engine, apu, slot_idx, 0, 0x00u);
            } else if (slot_idx == SOUND_SLOT_BGM_PERC || slot_idx == SOUND_SLOT_SFX_NOISE) {
                write_channel_reg(engine, apu, slot_idx, 0, 0x30u);
            }
        }
    }

    return RECON_OK;
}

static void parse_low_sound_cmd(SoundEngine *engine, Apu2A03 *apu, uint8_t slot_idx) {
    SoundSlot *slot = &engine->slots[slot_idx];

    while (slot->sound_code != 0) {
        uint8_t byte = read_prg_byte(engine, slot->cmd_addr++);

        if (byte >= 0xFDu) {
            if (byte == 0xFDu) {
                /* Subroutine / child call */
                uint8_t lo = read_prg_byte(engine, slot->cmd_addr++);
                uint8_t hi = read_prg_byte(engine, slot->cmd_addr++);
                slot->return_addr = slot->cmd_addr;
                slot->flags = (uint8_t)(slot->flags | 0x08u);
                slot->cmd_addr = (uint16_t)(lo | ((uint16_t)hi << 8));
                continue;
            } else if (byte == 0xFEu) {
                /* Repeat loop */
                slot->repeat_count = (uint8_t)(slot->repeat_count + 1u);
                uint8_t limit = read_prg_byte(engine, slot->cmd_addr++);
                uint8_t lo = read_prg_byte(engine, slot->cmd_addr++);
                uint8_t hi = read_prg_byte(engine, slot->cmd_addr++);
                if (slot->repeat_count < limit) {
                    slot->cmd_addr = (uint16_t)(lo | ((uint16_t)hi << 8));
                } else {
                    slot->repeat_count = 0;
                }
                continue;
            } else if (byte == 0xFFu) {
                /* Return from child or end of stream */
                if (slot->flags & 0x08u) {
                    slot->cmd_addr = slot->return_addr;
                    slot->flags = (uint8_t)(slot->flags & ~0x08u);
                    continue;
                } else {
                    slot->sound_code = 0;
                    mute_channel(apu, slot_idx);
                    break;
                }
            }
        }

        uint8_t hi_nib = (uint8_t)(byte & 0xF0u);
        if (hi_nib == 0x20u) {
            /* Case 1: Length multiplier and APU config high */
            uint8_t lo = (uint8_t)(byte & 0x0Fu);
            if (lo == 0x0Fu) {
                slot->length_multiplier = read_prg_byte(engine, slot->cmd_addr++);
            } else {
                slot->length_multiplier = lo;
            }
            slot->cfg_high = read_prg_byte(engine, slot->cmd_addr++);
            continue;
        } else if (hi_nib == 0x10u) {
            /* Case 2: Sweep control */
            if (byte == 0x10u) {
                uint8_t sweep_val = read_prg_byte(engine, slot->cmd_addr++);
                if (sweep_val != 0) {
                    write_channel_reg(engine, apu, slot_idx, 1, sweep_val);
                    if (slot_idx == SOUND_SLOT_SFX_PULSE1) {
                        slot->vol_duration = sweep_val;
                    }
                } else {
                    write_channel_reg(engine, apu, slot_idx, 1, 0x7Fu);
                }
            }
            continue;
        } else {
            /* Case 4: Note pitch and duration */
            uint8_t vol = (uint8_t)((byte >> 4) & 0x0Fu);
            slot->cmd_length = slot->length_multiplier;
            uint8_t lo = read_prg_byte(engine, slot->cmd_addr++);
            uint8_t hi = read_prg_byte(engine, slot->cmd_addr++);

            uint8_t cfg = (uint8_t)(slot->cfg_high | vol);
            write_channel_reg(engine, apu, slot_idx, 0, cfg);
            write_channel_reg(engine, apu, slot_idx, 2, lo);
            write_channel_reg(engine, apu, slot_idx, 3, hi);
            break;
        }
    }
}

static void parse_percussion_cmd(SoundEngine *engine, Apu2A03 *apu, uint8_t slot_idx) {
    SoundSlot *slot = &engine->slots[slot_idx];

    while (slot->sound_code != 0) {
        uint8_t byte = read_prg_byte(engine, slot->cmd_addr++);
        uint8_t hi_nib = (uint8_t)(byte & 0xF0u);

        if (hi_nib == 0xF0u) {
            uint8_t lo = (uint8_t)(byte & 0x0Fu);
            if (lo == 0x0Du) {
                /* Subroutine / child call */
                uint8_t alo = read_prg_byte(engine, slot->cmd_addr++);
                uint8_t ahi = read_prg_byte(engine, slot->cmd_addr++);
                slot->return_addr = slot->cmd_addr;
                slot->flags = (uint8_t)(slot->flags | 0x08u);
                slot->cmd_addr = (uint16_t)(alo | ((uint16_t)ahi << 8));
                continue;
            } else if (lo == 0x0Eu) {
                /* Repeat loop */
                slot->repeat_count = (uint8_t)(slot->repeat_count + 1u);
                uint8_t limit = read_prg_byte(engine, slot->cmd_addr++);
                uint8_t alo = read_prg_byte(engine, slot->cmd_addr++);
                uint8_t ahi = read_prg_byte(engine, slot->cmd_addr++);
                if (slot->repeat_count < limit) {
                    slot->cmd_addr = (uint16_t)(alo | ((uint16_t)ahi << 8));
                } else {
                    slot->repeat_count = 0;
                }
                continue;
            } else if (lo == 0x0Fu) {
                if (slot->flags & 0x08u) {
                    slot->cmd_addr = slot->return_addr;
                    slot->flags = (uint8_t)(slot->flags & ~0x08u);
                    continue;
                } else {
                    slot->sound_code = 0;
                    mute_channel(apu, slot_idx);
                    break;
                }
            }
        } else if (hi_nib == 0xD0u) {
            slot->length_multiplier = (uint8_t)(byte & 0x0Fu);
            continue;
        } else {
            /* Case 3: Play percussion sound and calculate delay */
            uint8_t factor = (uint8_t)(byte & 0x0Fu);
            slot->cmd_length = (uint8_t)(slot->length_multiplier * (factor + 1u));
            uint8_t perc_idx = (uint8_t)((byte >> 4) & 0x0Fu);
            if (perc_idx < 8u) {
                uint8_t s_code = read_prg_offset(engine, (size_t)(ROM_PERCUSSION_TABLE_OFFSET + perc_idx));
                sound_engine_play_sound(engine, apu, s_code);
                if (perc_idx >= 3u) {
                    sound_engine_play_sound(engine, apu, 0x02u); /* Percussive tick on noise channel */
                }
            }
            break;
        }
    }
}

static void parse_high_sound_cmd(SoundEngine *engine, Apu2A03 *apu, uint8_t slot_idx) {
    SoundSlot *slot = &engine->slots[slot_idx];

    while (slot->sound_code != 0) {
        uint8_t byte = read_prg_byte(engine, slot->cmd_addr++);
        uint8_t hi_nib = (uint8_t)(byte & 0xF0u);

        if (hi_nib < 0xC0u) {
            /* Simple sound command: Note pitch and length multiplier */
            uint8_t factor = (uint8_t)(byte & 0x0Fu);
            slot->cmd_length = (uint8_t)(slot->length_multiplier * (factor + 1u));
            slot->decrescendo_pause = (uint8_t)((factor * slot->cmd_length) >> 4);

            if (slot_idx == SOUND_SLOT_BGM_TRI) {
                write_channel_reg(engine, apu, slot_idx, 0, slot->triangle_cfg);
            } else {
                /* Pulse 1 / 2: Load volume envelope */
                slot->vol_step_index = 0;
                uint16_t env_ptr = (uint16_t)(ROM_PULSE_VOL_TABLE_OFFSET + (size_t)slot->vol_env_index * 2u);
                uint8_t elo = read_prg_offset(engine, env_ptr);
                uint8_t ehi = read_prg_offset(engine, (size_t)(env_ptr + 1u));
                uint16_t env_cpu = (uint16_t)(elo | ((uint16_t)ehi << 8));
                uint8_t first_vol = read_prg_byte(engine, env_cpu);
                slot->pulse_volume = (uint8_t)(first_vol & 0x1Fu);
                write_channel_reg(engine, apu, slot_idx, 0, (uint8_t)(slot->cfg_high | slot->pulse_volume));
            }

            /* Read note pitch from note_period_tbl */
            uint8_t note_idx = (uint8_t)(((byte & 0xF0u) >> 3) + slot->pitch_adjust);
            size_t note_off = ROM_NOTE_PERIOD_OFFSET + (size_t)note_idx;
            uint8_t lo = read_prg_offset(engine, note_off);
            uint8_t hi = read_prg_offset(engine, note_off + 1u);
            uint16_t period = (uint16_t)(lo | ((uint16_t)hi << 8));

            if (slot->period_rotate != 4u) {
                period = (uint16_t)(period >> slot->period_rotate);
            }
            if (slot->flags & 0x10u) {
                period++;
            }

            write_channel_reg(engine, apu, slot_idx, 2, (uint8_t)(period & 0xFFu));
            write_channel_reg(engine, apu, slot_idx, 3, (uint8_t)((period >> 8) | 0x08u));
            break;
        } else {
            /* Regular sound command >= 0xC0 */
            uint8_t routine = (uint8_t)((byte & 0x30u) >> 4);
            if (routine == 0) {
                /* Routine 00: Mute channel */
                uint8_t factor = (uint8_t)(byte & 0x0Fu);
                slot->cmd_length = (uint8_t)(slot->length_multiplier * (factor + 1u));
                slot->flags = (uint8_t)(slot->flags | 0x40u);
                write_channel_reg(engine, apu, slot_idx, 0, (slot_idx == SOUND_SLOT_BGM_TRI) ? 0x00u : 0x30u);
                break;
            } else if (routine == 1) {
                /* Routine 01: Set Config */
                slot->length_multiplier = (uint8_t)(byte & 0x0Fu);
                uint8_t cfg_byte = read_prg_byte(engine, slot->cmd_addr++);
                if (slot_idx == SOUND_SLOT_BGM_TRI) {
                    slot->triangle_cfg = cfg_byte;
                } else {
                    slot->cfg_low = (uint8_t)(cfg_byte & 0x0Fu);
                    slot->cfg_high = (uint8_t)(cfg_byte & 0xF0u);
                    slot->vol_env_index = read_prg_byte(engine, slot->cmd_addr++);
                    uint8_t unk = read_prg_byte(engine, slot->cmd_addr++);
                    (void)unk;
                }
                continue;
            } else if (routine == 2) {
                /* Routine 02: Adjust pitch / vibrato */
                uint8_t sub = (uint8_t)(byte & 0x0Fu);
                if (sub < 5u) {
                    slot->period_rotate = sub;
                } else if (sub == 8u) {
                    slot->flags = (uint8_t)(slot->flags | 0x10u);
                } else if (sub == 0x0Bu) {
                    slot->vibrato_ctrl = read_prg_byte(engine, slot->cmd_addr++);
                } else if (sub == 0x0Cu) {
                    slot->pitch_adjust = (uint8_t)(read_prg_byte(engine, slot->cmd_addr++) * 2u);
                }
                continue;
            } else if (routine == 3) {
                /* Routine 03: Flow control */
                uint8_t sub = (uint8_t)(byte & 0x0Fu);
                if (sub == 0x0Eu) {
                    /* Repeat loop */
                    slot->repeat_count = (uint8_t)(slot->repeat_count + 1u);
                    uint8_t limit = read_prg_byte(engine, slot->cmd_addr++);
                    uint8_t lo = read_prg_byte(engine, slot->cmd_addr++);
                    uint8_t hi = read_prg_byte(engine, slot->cmd_addr++);
                    if (slot->repeat_count < limit) {
                        slot->cmd_addr = (uint16_t)(lo | ((uint16_t)hi << 8));
                    } else {
                        slot->repeat_count = 0;
                    }
                    continue;
                } else if (sub < 0x0Eu) {
                    /* Child call */
                    uint8_t lo = read_prg_byte(engine, slot->cmd_addr++);
                    uint8_t hi = read_prg_byte(engine, slot->cmd_addr++);
                    slot->return_addr = slot->cmd_addr;
                    slot->flags = (uint8_t)(slot->flags | 0x08u);
                    slot->cmd_addr = (uint16_t)(lo | ((uint16_t)hi << 8));
                    continue;
                } else {
                    /* End of stream (0x0F) */
                    if (slot->flags & 0x08u) {
                        slot->cmd_addr = slot->return_addr;
                        slot->flags = (uint8_t)(slot->flags & ~0x08u);
                        continue;
                    } else {
                        slot->sound_code = 0;
                        mute_channel(apu, slot_idx);
                        break;
                    }
                }
            }
        }
    }
}

void sound_engine_update_frame(SoundEngine *engine, Apu2A03 *apu) {
    if (!engine || !engine->is_loaded) return;

    for (uint8_t x = 0; x < SOUND_SLOT_COUNT; ++x) {
        SoundSlot *slot = &engine->slots[x];
        if (slot->sound_code == 0) continue;

        if (engine->is_paused && slot->sound_code != 0x54u) {
            continue;
        }

        if (slot->cmd_length > 0) {
            slot->cmd_length--;
        }

        if (slot->cmd_length == 0) {
            /* Command finished: read next bytecode command */
            if (slot->flags & 0x01u) {
                parse_low_sound_cmd(engine, apu, x);
            } else if (x == SOUND_SLOT_BGM_PERC) {
                parse_percussion_cmd(engine, apu, x);
            } else {
                parse_high_sound_cmd(engine, apu, x);
            }
        } else {
            /* Active command: advance frame volume decay / envelope */
            if (x == SOUND_SLOT_BGM_PULSE1 || x == SOUND_SLOT_BGM_PULSE2 || x == SOUND_SLOT_SFX_PULSE1) {
                if (slot->flags & 0x04u) {
                    /* Automatic decrescendo */
                    if (slot->cmd_length < slot->decrescendo_pause && slot->pulse_volume > 0) {
                        slot->pulse_volume--;
                        write_channel_reg(engine, apu, x, 0, (uint8_t)(slot->cfg_high | slot->pulse_volume));
                    }
                } else {
                    /* Envelope from pulse_volume_ptr_tbl */
                    uint16_t env_ptr = (uint16_t)(ROM_PULSE_VOL_TABLE_OFFSET + (size_t)slot->vol_env_index * 2u);
                    uint8_t elo = read_prg_offset(engine, env_ptr);
                    uint8_t ehi = read_prg_offset(engine, (size_t)(env_ptr + 1u));
                    uint16_t env_cpu = (uint16_t)(elo | ((uint16_t)ehi << 8));
                    uint8_t next_vol = read_prg_byte(engine, (uint16_t)(env_cpu + slot->vol_step_index));

                    if (next_vol >= 0xFEu) {
                        slot->flags = (uint8_t)(slot->flags | 0x04u);
                    } else {
                        slot->vol_step_index++;
                        slot->pulse_volume = (uint8_t)(next_vol & 0x1Fu);
                        write_channel_reg(engine, apu, x, 0, (uint8_t)(slot->cfg_high | slot->pulse_volume));
                    }
                }
            }
        }
    }
}
