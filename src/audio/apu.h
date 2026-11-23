#ifndef RECON_APU_H
#define RECON_APU_H

#include "core/types.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define APU_DEFAULT_SAMPLE_RATE 48000u
#define APU_NTSC_CPU_CLOCK      1789773u
#define APU_FRAME_QUARTER_CYCLES 7457u

/* APU Register Address Map */
#define APU_REG_PULSE1_CTRL     0x4000u
#define APU_REG_PULSE1_SWEEP    0x4001u
#define APU_REG_PULSE1_TIMER_LO 0x4002u
#define APU_REG_PULSE1_TIMER_HI 0x4003u

#define APU_REG_PULSE2_CTRL     0x4004u
#define APU_REG_PULSE2_SWEEP    0x4005u
#define APU_REG_PULSE2_TIMER_LO 0x4006u
#define APU_REG_PULSE2_TIMER_HI 0x4007u

#define APU_REG_TRI_CTRL        0x4008u
#define APU_REG_TRI_TIMER_LO    0x400Au
#define APU_REG_TRI_TIMER_HI    0x400Bu

#define APU_REG_NOISE_CTRL      0x400Cu
#define APU_REG_NOISE_PERIOD    0x400Eu
#define APU_REG_NOISE_LENGTH    0x400Fu

#define APU_REG_DMC_CTRL        0x4010u
#define APU_REG_DMC_DIRECT      0x4011u
#define APU_REG_DMC_ADDR        0x4012u
#define APU_REG_DMC_LENGTH      0x4013u

#define APU_REG_STATUS          0x4015u
#define APU_REG_FRAME_COUNTER   0x4017u

typedef struct {
    bool enabled;
    uint8_t duty;
    bool length_halt;
    bool constant_vol;
    uint8_t volume;
    uint8_t envelope_divider;
    uint8_t envelope_counter;
    bool envelope_start;

    bool sweep_enabled;
    uint8_t sweep_period;
    bool sweep_negate;
    uint8_t sweep_shift;
    uint8_t sweep_divider;
    bool sweep_reload;

    uint16_t timer_period;
    float timer_counter;
    uint8_t sequence_step;
    uint8_t length_counter;
    bool is_pulse2;
} PulseChannel;

typedef struct {
    bool enabled;
    bool control_flag;
    uint8_t linear_reload_val;
    uint8_t linear_counter;
    bool linear_reload_flag;

    uint16_t timer_period;
    float timer_counter;
    uint8_t sequence_step;
    uint8_t length_counter;
} TriangleChannel;

typedef struct {
    bool enabled;
    bool length_halt;
    bool constant_vol;
    uint8_t volume;
    uint8_t envelope_divider;
    uint8_t envelope_counter;
    bool envelope_start;

    bool mode;
    uint8_t period_idx;
    uint16_t timer_period;
    float timer_counter;
    uint16_t lfsr;
    uint8_t length_counter;
} NoiseChannel;

typedef struct {
    bool enabled;
    bool loop;
    bool irq_enabled;
    uint8_t rate_idx;
    uint16_t rate_period;
    float timer_counter;
    uint8_t output_level;

    uint16_t sample_addr_cpu;
    uint16_t sample_len_bytes;
    uint16_t current_addr;
    uint16_t bytes_remaining;
    uint8_t shift_reg;
    uint8_t bits_remaining;
    bool silence;

    const uint8_t *sample_memory;
    size_t sample_memory_size;
} DmcChannel;

typedef struct {
    PulseChannel pulse1;
    PulseChannel pulse2;
    TriangleChannel triangle;
    NoiseChannel noise;
    DmcChannel dmc;

    uint32_t sample_rate;
    float cycles_per_sample;
    float dc_filter_in;
    float dc_filter_out;

    /* Frame sequencer */
    uint32_t frame_cycles;
    uint8_t frame_step;
    bool frame_5step;
} Apu2A03;

void apu_init(Apu2A03 *apu, uint32_t sample_rate);
void apu_reset(Apu2A03 *apu);
void apu_set_dmc_memory(Apu2A03 *apu, const uint8_t *mem, size_t size);
void apu_write_register(Apu2A03 *apu, uint16_t reg, uint8_t val);
uint8_t apu_read_status(Apu2A03 *apu);
void apu_clock_frame_quarter(Apu2A03 *apu);
void apu_clock_frame_half(Apu2A03 *apu);
void apu_generate_samples(Apu2A03 *apu, float *out_buffer, size_t count);

#ifdef __cplusplus
}
#endif

#endif /* RECON_APU_H */
