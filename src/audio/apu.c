#include "audio/apu.h"
#include <string.h>

static const uint8_t LENGTH_TABLE[32] = {
    10, 254, 20,  2, 40,  4, 80,  6, 160,  8, 60, 10, 14, 12, 26, 14,
    12,  16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30
};

static const uint8_t DUTY_TABLE[4][8] = {
    { 0, 1, 0, 0, 0, 0, 0, 0 }, /* 12.5% */
    { 0, 1, 1, 0, 0, 0, 0, 0 }, /* 25.0% */
    { 0, 1, 1, 1, 1, 0, 0, 0 }, /* 50.0% */
    { 1, 0, 0, 1, 1, 1, 1, 1 }  /* 75.0% / inverted 25% */
};

static const uint8_t TRIANGLE_TABLE[32] = {
    15, 14, 13, 12, 11, 10,  9,  8,  7,  6,  5,  4,  3,  2,  1,  0,
     0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15
};

static const uint16_t NOISE_PERIODS[16] = {
    4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068
};

static const uint16_t DMC_PERIODS[16] = {
    428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54
};

static inline uint16_t pulse_target_period(const PulseChannel *pulse) {
    uint16_t delta = (uint16_t)(pulse->timer_period >> pulse->sweep_shift);
    if (pulse->sweep_negate) {
        if (pulse->is_pulse2) {
            return (pulse->timer_period >= delta) ? (uint16_t)(pulse->timer_period - delta) : 0u;
        } else {
            return (pulse->timer_period > delta) ? (uint16_t)(pulse->timer_period - delta - 1u) : 0u;
        }
    } else {
        return (uint16_t)(pulse->timer_period + delta);
    }
}

static inline bool pulse_is_muted(const PulseChannel *pulse) {
    if (pulse->timer_period < 8u) {
        return true;
    }
    uint16_t target = pulse_target_period(pulse);
    if (target > 0x07FFu) {
        return true;
    }
    return false;
}

static void clock_envelope(bool *envelope_start, bool loop, bool constant_vol,
                           uint8_t volume, uint8_t *divider, uint8_t *counter) {
    if (*envelope_start) {
        *envelope_start = false;
        *counter = 15;
        *divider = volume;
    } else {
        if (*divider == 0) {
            *divider = volume;
            if (*counter > 0) {
                (*counter)--;
            } else if (loop) {
                *counter = 15;
            }
        } else {
            (*divider)--;
        }
    }
    (void)constant_vol;
}

static void clock_pulse_sweep(PulseChannel *pulse) {
    if (pulse->sweep_reload) {
        pulse->sweep_divider = pulse->sweep_period;
        pulse->sweep_reload = false;
    } else if (pulse->sweep_divider > 0) {
        pulse->sweep_divider--;
    } else {
        pulse->sweep_divider = pulse->sweep_period;
        if (pulse->sweep_enabled && pulse->sweep_shift > 0 && !pulse_is_muted(pulse)) {
            pulse->timer_period = pulse_target_period(pulse);
        }
    }
}

void apu_init(Apu2A03 *apu, uint32_t sample_rate) {
    if (!apu) return;
    memset(apu, 0, sizeof(Apu2A03));

    apu->sample_rate = (sample_rate > 0) ? sample_rate : APU_DEFAULT_SAMPLE_RATE;
    apu->cycles_per_sample = (float)APU_NTSC_CPU_CLOCK / (float)apu->sample_rate;
    apu->noise.lfsr = 1;
    apu->noise.timer_period = NOISE_PERIODS[0];
    apu->dmc.rate_period = DMC_PERIODS[0];
    apu->dmc.silence = true;
    apu->pulse2.is_pulse2 = true;
}

void apu_reset(Apu2A03 *apu) {
    if (!apu) return;
    uint32_t rate = apu->sample_rate;
    const uint8_t *dmc_mem = apu->dmc.sample_memory;
    size_t dmc_size = apu->dmc.sample_memory_size;

    apu_init(apu, rate);
    apu_set_dmc_memory(apu, dmc_mem, dmc_size);
}

void apu_set_dmc_memory(Apu2A03 *apu, const uint8_t *mem, size_t size) {
    if (!apu) return;
    apu->dmc.sample_memory = mem;
    apu->dmc.sample_memory_size = size;
}

void apu_write_register(Apu2A03 *apu, uint16_t reg, uint8_t val) {
    if (!apu) return;

    switch (reg) {
    /* Pulse 1 */
    case APU_REG_PULSE1_CTRL:
        apu->pulse1.duty = (uint8_t)((val >> 6) & 0x03u);
        apu->pulse1.length_halt = (val & 0x20u) != 0;
        apu->pulse1.constant_vol = (val & 0x10u) != 0;
        apu->pulse1.volume = (uint8_t)(val & 0x0Fu);
        break;
    case APU_REG_PULSE1_SWEEP:
        apu->pulse1.sweep_enabled = (val & 0x80u) != 0;
        apu->pulse1.sweep_period = (uint8_t)((val >> 4) & 0x07u);
        apu->pulse1.sweep_negate = (val & 0x08u) != 0;
        apu->pulse1.sweep_shift = (uint8_t)(val & 0x07u);
        apu->pulse1.sweep_reload = true;
        break;
    case APU_REG_PULSE1_TIMER_LO:
        apu->pulse1.timer_period = (uint16_t)((apu->pulse1.timer_period & 0x0700u) | val);
        break;
    case APU_REG_PULSE1_TIMER_HI:
        apu->pulse1.timer_period = (uint16_t)((apu->pulse1.timer_period & 0x00FFu) | ((uint16_t)(val & 0x07u) << 8));
        if (apu->pulse1.enabled) {
            apu->pulse1.length_counter = LENGTH_TABLE[(val >> 3) & 0x1Fu];
        }
        apu->pulse1.sequence_step = 0;
        apu->pulse1.envelope_start = true;
        break;

    /* Pulse 2 */
    case APU_REG_PULSE2_CTRL:
        apu->pulse2.duty = (uint8_t)((val >> 6) & 0x03u);
        apu->pulse2.length_halt = (val & 0x20u) != 0;
        apu->pulse2.constant_vol = (val & 0x10u) != 0;
        apu->pulse2.volume = (uint8_t)(val & 0x0Fu);
        break;
    case APU_REG_PULSE2_SWEEP:
        apu->pulse2.sweep_enabled = (val & 0x80u) != 0;
        apu->pulse2.sweep_period = (uint8_t)((val >> 4) & 0x07u);
        apu->pulse2.sweep_negate = (val & 0x08u) != 0;
        apu->pulse2.sweep_shift = (uint8_t)(val & 0x07u);
        apu->pulse2.sweep_reload = true;
        break;
    case APU_REG_PULSE2_TIMER_LO:
        apu->pulse2.timer_period = (uint16_t)((apu->pulse2.timer_period & 0x0700u) | val);
        break;
    case APU_REG_PULSE2_TIMER_HI:
        apu->pulse2.timer_period = (uint16_t)((apu->pulse2.timer_period & 0x00FFu) | ((uint16_t)(val & 0x07u) << 8));
        if (apu->pulse2.enabled) {
            apu->pulse2.length_counter = LENGTH_TABLE[(val >> 3) & 0x1Fu];
        }
        apu->pulse2.sequence_step = 0;
        apu->pulse2.envelope_start = true;
        break;

    /* Triangle */
    case APU_REG_TRI_CTRL:
        apu->triangle.control_flag = (val & 0x80u) != 0;
        apu->triangle.linear_reload_val = (uint8_t)(val & 0x7Fu);
        break;
    case APU_REG_TRI_TIMER_LO:
        apu->triangle.timer_period = (uint16_t)((apu->triangle.timer_period & 0x0700u) | val);
        break;
    case APU_REG_TRI_TIMER_HI:
        apu->triangle.timer_period = (uint16_t)((apu->triangle.timer_period & 0x00FFu) | ((uint16_t)(val & 0x07u) << 8));
        if (apu->triangle.enabled) {
            apu->triangle.length_counter = LENGTH_TABLE[(val >> 3) & 0x1Fu];
        }
        apu->triangle.linear_reload_flag = true;
        break;

    /* Noise */
    case APU_REG_NOISE_CTRL:
        apu->noise.length_halt = (val & 0x20u) != 0;
        apu->noise.constant_vol = (val & 0x10u) != 0;
        apu->noise.volume = (uint8_t)(val & 0x0Fu);
        break;
    case APU_REG_NOISE_PERIOD:
        apu->noise.mode = (val & 0x80u) != 0;
        apu->noise.period_idx = (uint8_t)(val & 0x0Fu);
        apu->noise.timer_period = NOISE_PERIODS[apu->noise.period_idx];
        break;
    case APU_REG_NOISE_LENGTH:
        if (apu->noise.enabled) {
            apu->noise.length_counter = LENGTH_TABLE[(val >> 3) & 0x1Fu];
        }
        apu->noise.envelope_start = true;
        break;

    /* DMC */
    case APU_REG_DMC_CTRL:
        apu->dmc.irq_enabled = (val & 0x80u) != 0;
        apu->dmc.loop = (val & 0x40u) != 0;
        apu->dmc.rate_idx = (uint8_t)(val & 0x0Fu);
        apu->dmc.rate_period = DMC_PERIODS[apu->dmc.rate_idx];
        break;
    case APU_REG_DMC_DIRECT:
        apu->dmc.output_level = (uint8_t)(val & 0x7Fu);
        break;
    case APU_REG_DMC_ADDR:
        apu->dmc.sample_addr_cpu = (uint16_t)(0xC000u + ((uint16_t)val << 6));
        break;
    case APU_REG_DMC_LENGTH:
        apu->dmc.sample_len_bytes = (uint16_t)(((uint16_t)val << 4) + 1u);
        break;

    /* Status Control */
    case APU_REG_STATUS:
        apu->pulse1.enabled = (val & 0x01u) != 0;
        if (!apu->pulse1.enabled) apu->pulse1.length_counter = 0;

        apu->pulse2.enabled = (val & 0x02u) != 0;
        if (!apu->pulse2.enabled) apu->pulse2.length_counter = 0;

        apu->triangle.enabled = (val & 0x04u) != 0;
        if (!apu->triangle.enabled) apu->triangle.length_counter = 0;

        apu->noise.enabled = (val & 0x08u) != 0;
        if (!apu->noise.enabled) apu->noise.length_counter = 0;

        if (val & 0x10u) {
            apu->dmc.enabled = true;
            if (apu->dmc.bytes_remaining == 0) {
                apu->dmc.current_addr = apu->dmc.sample_addr_cpu;
                apu->dmc.bytes_remaining = apu->dmc.sample_len_bytes;
                apu->dmc.silence = false;
            }
        } else {
            apu->dmc.enabled = false;
            apu->dmc.bytes_remaining = 0;
            apu->dmc.silence = true;
        }
        break;

    case APU_REG_FRAME_COUNTER:
        apu->frame_5step = (val & 0x80u) != 0;
        apu->frame_step = 0;
        apu->frame_cycles = 0;
        if (apu->frame_5step) {
            apu_clock_frame_quarter(apu);
            apu_clock_frame_half(apu);
        }
        break;

    default:
        break;
    }
}

uint8_t apu_read_status(Apu2A03 *apu) {
    if (!apu) return 0;
    uint8_t st = 0;
    if (apu->pulse1.length_counter > 0)   st |= 0x01u;
    if (apu->pulse2.length_counter > 0)   st |= 0x02u;
    if (apu->triangle.length_counter > 0) st |= 0x04u;
    if (apu->noise.length_counter > 0)    st |= 0x08u;
    if (apu->dmc.bytes_remaining > 0)     st |= 0x10u;
    return st;
}

void apu_clock_frame_quarter(Apu2A03 *apu) {
    if (!apu) return;

    /* Envelopes */
    clock_envelope(&apu->pulse1.envelope_start, apu->pulse1.length_halt, apu->pulse1.constant_vol,
                   apu->pulse1.volume, &apu->pulse1.envelope_divider, &apu->pulse1.envelope_counter);
    clock_envelope(&apu->pulse2.envelope_start, apu->pulse2.length_halt, apu->pulse2.constant_vol,
                   apu->pulse2.volume, &apu->pulse2.envelope_divider, &apu->pulse2.envelope_counter);
    clock_envelope(&apu->noise.envelope_start, apu->noise.length_halt, apu->noise.constant_vol,
                   apu->noise.volume, &apu->noise.envelope_divider, &apu->noise.envelope_counter);

    /* Triangle Linear Counter */
    if (apu->triangle.linear_reload_flag) {
        apu->triangle.linear_counter = apu->triangle.linear_reload_val;
    } else if (apu->triangle.linear_counter > 0) {
        apu->triangle.linear_counter--;
    }
    if (!apu->triangle.control_flag) {
        apu->triangle.linear_reload_flag = false;
    }
}

void apu_clock_frame_half(Apu2A03 *apu) {
    if (!apu) return;

    /* Length Counters */
    if (!apu->pulse1.length_halt && apu->pulse1.length_counter > 0) {
        apu->pulse1.length_counter--;
    }
    if (!apu->pulse2.length_halt && apu->pulse2.length_counter > 0) {
        apu->pulse2.length_counter--;
    }
    if (!apu->triangle.control_flag && apu->triangle.length_counter > 0) {
        apu->triangle.length_counter--;
    }
    if (!apu->noise.length_halt && apu->noise.length_counter > 0) {
        apu->noise.length_counter--;
    }

    /* Sweep Units */
    clock_pulse_sweep(&apu->pulse1);
    clock_pulse_sweep(&apu->pulse2);
}

void apu_generate_samples(Apu2A03 *apu, float *out_buffer, size_t count) {
    if (!apu || !out_buffer || count == 0) return;

    for (size_t s = 0; s < count; ++s) {
        /* Advance frame counter sequencer */
        apu->frame_cycles += (uint32_t)apu->cycles_per_sample;
        while (apu->frame_cycles >= APU_FRAME_QUARTER_CYCLES) {
            apu->frame_cycles -= APU_FRAME_QUARTER_CYCLES;
            apu->frame_step++;
            if (!apu->frame_5step) {
                /* 4-step sequence */
                switch (apu->frame_step & 0x03u) {
                case 1: apu_clock_frame_quarter(apu); break;
                case 2: apu_clock_frame_quarter(apu); apu_clock_frame_half(apu); break;
                case 3: apu_clock_frame_quarter(apu); break;
                case 0: apu_clock_frame_quarter(apu); apu_clock_frame_half(apu); break;
                default: break;
                }
            } else {
                /* 5-step sequence */
                switch (apu->frame_step % 5u) {
                case 1: apu_clock_frame_quarter(apu); break;
                case 2: apu_clock_frame_quarter(apu); apu_clock_frame_half(apu); break;
                case 3: apu_clock_frame_quarter(apu); break;
                case 4: break;
                case 0: apu_clock_frame_quarter(apu); apu_clock_frame_half(apu); break;
                default: break;
                }
            }
        }

        /* 1. Pulse 1 */
        uint8_t pulse1_out = 0;
        if (apu->pulse1.enabled && apu->pulse1.length_counter > 0 && !pulse_is_muted(&apu->pulse1)) {
            apu->pulse1.timer_counter -= apu->cycles_per_sample * 0.5f;
            while (apu->pulse1.timer_counter <= 0.0f) {
                apu->pulse1.timer_counter += (float)(apu->pulse1.timer_period + 1u);
                apu->pulse1.sequence_step = (uint8_t)((apu->pulse1.sequence_step + 1u) & 0x07u);
            }
            if (DUTY_TABLE[apu->pulse1.duty][apu->pulse1.sequence_step]) {
                pulse1_out = apu->pulse1.constant_vol ? apu->pulse1.volume : apu->pulse1.envelope_counter;
            }
        }

        /* 2. Pulse 2 */
        uint8_t pulse2_out = 0;
        if (apu->pulse2.enabled && apu->pulse2.length_counter > 0 && !pulse_is_muted(&apu->pulse2)) {
            apu->pulse2.timer_counter -= apu->cycles_per_sample * 0.5f;
            while (apu->pulse2.timer_counter <= 0.0f) {
                apu->pulse2.timer_counter += (float)(apu->pulse2.timer_period + 1u);
                apu->pulse2.sequence_step = (uint8_t)((apu->pulse2.sequence_step + 1u) & 0x07u);
            }
            if (DUTY_TABLE[apu->pulse2.duty][apu->pulse2.sequence_step]) {
                pulse2_out = apu->pulse2.constant_vol ? apu->pulse2.volume : apu->pulse2.envelope_counter;
            }
        }

        /* 3. Triangle */
        uint8_t tri_out = 0;
        if (apu->triangle.enabled && apu->triangle.length_counter > 0 && apu->triangle.linear_counter > 0) {
            apu->triangle.timer_counter -= apu->cycles_per_sample;
            while (apu->triangle.timer_counter <= 0.0f) {
                apu->triangle.timer_counter += (float)(apu->triangle.timer_period + 1u);
                if (apu->triangle.timer_period > 2u) {
                    apu->triangle.sequence_step = (uint8_t)((apu->triangle.sequence_step + 1u) & 0x1Fu);
                }
            }
            tri_out = TRIANGLE_TABLE[apu->triangle.sequence_step];
        }

        /* 4. Noise */
        uint8_t noise_out = 0;
        if (apu->noise.enabled && apu->noise.length_counter > 0) {
            apu->noise.timer_counter -= apu->cycles_per_sample;
            while (apu->noise.timer_counter <= 0.0f) {
                apu->noise.timer_counter += (float)apu->noise.timer_period;
                uint16_t feedback = (uint16_t)((apu->noise.lfsr & 1u) ^ (apu->noise.mode ? ((apu->noise.lfsr >> 6) & 1u) : ((apu->noise.lfsr >> 1) & 1u)));
                apu->noise.lfsr = (uint16_t)((apu->noise.lfsr >> 1) | (feedback << 14));
            }
            if (!(apu->noise.lfsr & 1u)) {
                noise_out = apu->noise.constant_vol ? apu->noise.volume : apu->noise.envelope_counter;
            }
        }

        /* 5. DMC */
        if (apu->dmc.enabled && apu->dmc.bytes_remaining > 0) {
            apu->dmc.timer_counter -= apu->cycles_per_sample;
            while (apu->dmc.timer_counter <= 0.0f) {
                apu->dmc.timer_counter += (float)apu->dmc.rate_period;
                if (apu->dmc.bits_remaining == 0) {
                    if (apu->dmc.bytes_remaining > 0 && apu->dmc.sample_memory) {
                        size_t prg_offset = (size_t)(apu->dmc.current_addr - 0xC000u);
                        if (prg_offset < apu->dmc.sample_memory_size) {
                            apu->dmc.shift_reg = apu->dmc.sample_memory[prg_offset];
                        } else {
                            apu->dmc.shift_reg = 0;
                        }
                        apu->dmc.current_addr++;
                        if (apu->dmc.current_addr == 0) {
                            apu->dmc.current_addr = 0x8000u;
                        }
                        apu->dmc.bytes_remaining--;
                        apu->dmc.bits_remaining = 8;
                        apu->dmc.silence = false;
                    } else if (apu->dmc.loop) {
                        apu->dmc.current_addr = apu->dmc.sample_addr_cpu;
                        apu->dmc.bytes_remaining = apu->dmc.sample_len_bytes;
                    } else {
                        apu->dmc.silence = true;
                    }
                }

                if (!apu->dmc.silence && apu->dmc.bits_remaining > 0) {
                    uint8_t bit = (uint8_t)(apu->dmc.shift_reg & 0x01u);
                    apu->dmc.shift_reg >>= 1;
                    apu->dmc.bits_remaining--;

                    if (bit) {
                        if (apu->dmc.output_level <= 125u) {
                            apu->dmc.output_level = (uint8_t)(apu->dmc.output_level + 2u);
                        }
                    } else {
                        if (apu->dmc.output_level >= 2u) {
                            apu->dmc.output_level = (uint8_t)(apu->dmc.output_level - 2u);
                        }
                    }
                }
            }
        }
        uint8_t dmc_out = apu->dmc.output_level;

        /* Non-linear NES Mixer */
        float pulse_sum = (float)pulse1_out + (float)pulse2_out;
        float pulse_out = 0.0f;
        if (pulse_sum > 0.0f) {
            pulse_out = 95.88f / ((8128.0f / pulse_sum) + 100.0f);
        }

        float tnd_sum = ((float)tri_out / 8227.0f) + ((float)noise_out / 12241.0f) + ((float)dmc_out / 22638.0f);
        float tnd_out = 0.0f;
        if (tnd_sum > 0.0f) {
            tnd_out = 159.79f / ((1.0f / tnd_sum) + 100.0f);
        }

        float mixed = (pulse_out + tnd_out) * 1.8f - 0.4f;

        /* High-pass DC Blocking Filter */
        float filtered = mixed - apu->dc_filter_in + 0.995f * apu->dc_filter_out;
        apu->dc_filter_in = mixed;
        apu->dc_filter_out = filtered;

        /* Clamp output to [-1.0f, +1.0f] */
        if (filtered > 1.0f) filtered = 1.0f;
        if (filtered < -1.0f) filtered = -1.0f;

        out_buffer[s] = filtered;
    }
}
