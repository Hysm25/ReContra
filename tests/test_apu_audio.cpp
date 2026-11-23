#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <vector>

#include "core/types.h"
#include "core/crypto.h"
#include "rom/rom_loader.h"
#include "audio/apu.h"
#include "audio/sound_engine.h"

#define TEST_CHECK(cond, msg) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "[FAIL] %s:%d: %s\n", __FILE__, __LINE__, msg); \
            return 1; \
        } \
    } while (0)

int main(int argc, char **argv) {
    const char *rom_path = "Contra (USA).nes";
    if (argc > 1) {
        rom_path = argv[1];
    }

    printf("[TEST] Testing 2A03 APU Synthesizer and 6-Slot Audio Engine with '%s'...\n", rom_path);

    RomData rom;
    TEST_CHECK(rom_load_file(rom_path, &rom) == RECON_OK, "Load authentic ROM");

    // 1. Standalone APU Channel Synthesis Verification
    Apu2A03 apu;
    apu_init(&apu, 48000);

    // Pulse 1 Channel Tone Generation
    apu_write_register(&apu, APU_REG_STATUS, 0x01); // Enable Pulse 1
    apu_write_register(&apu, APU_REG_PULSE1_CTRL, 0xB8); // Duty 50% (2), constant vol 8
    apu_write_register(&apu, APU_REG_PULSE1_TIMER_LO, 0xCF);
    apu_write_register(&apu, APU_REG_PULSE1_TIMER_HI, 0x02); // Period = 0x02CF (~155 Hz, D#3)

    float samples[800] = {0};
    apu_generate_samples(&apu, samples, 800);

    float pulse_energy = 0.0f;
    for (int i = 0; i < 800; ++i) {
        pulse_energy += samples[i] * samples[i];
    }
    printf("  Pulse 1 Tone Energy: %f\n", (double)pulse_energy);
    TEST_CHECK(pulse_energy > 0.05f, "Pulse 1 must produce non-silent waveform");

    // Triangle Channel Tone Generation
    apu_reset(&apu);
    apu_write_register(&apu, APU_REG_STATUS, 0x04); // Enable Triangle
    apu_write_register(&apu, APU_REG_TRI_CTRL, 0xFF); // Linear counter reload = 127
    apu_write_register(&apu, APU_REG_TRI_TIMER_LO, 0xCF);
    apu_write_register(&apu, APU_REG_TRI_TIMER_HI, 0x01); // Period = 0x01CF

    apu_generate_samples(&apu, samples, 800);
    float tri_energy = 0.0f;
    for (int i = 0; i < 800; ++i) {
        tri_energy += samples[i] * samples[i];
    }
    printf("  Triangle Tone Energy: %f\n", (double)tri_energy);
    TEST_CHECK(tri_energy > 0.05f, "Triangle must produce non-silent waveform");

    // Noise Channel Tone Generation
    apu_reset(&apu);
    apu_write_register(&apu, APU_REG_STATUS, 0x08); // Enable Noise
    apu_write_register(&apu, APU_REG_NOISE_CTRL, 0x3A); // Constant vol 10
    apu_write_register(&apu, APU_REG_NOISE_PERIOD, 0x04); // Period index 4
    apu_write_register(&apu, APU_REG_NOISE_LENGTH, 0x08); // Length counter

    apu_generate_samples(&apu, samples, 800);
    float noise_energy = 0.0f;
    for (int i = 0; i < 800; ++i) {
        noise_energy += samples[i] * samples[i];
    }
    printf("  Noise Tone Energy: %f\n", (double)noise_energy);
    TEST_CHECK(noise_energy > 0.05f, "Noise channel must produce non-silent waveform");

    // 2. DPCM Sample Extraction & DMC Playback
    apu_reset(&apu);
    // Wire Bank 7 ROM data to DMC
    const uint8_t *bank7_prg = rom.prg_data + 7 * PRG_BANK_SIZE;
    apu_set_dmc_memory(&apu, bank7_prg, PRG_BANK_SIZE);

    SoundEngine engine;
    TEST_CHECK(sound_engine_init(&engine, &rom) == RECON_OK, "Init sound engine with ROM");

    // Play DPCM Sample 0x5B (Snare drum sample)
    TEST_CHECK(sound_engine_play_sound(&engine, &apu, 0x5B) == RECON_OK, "Trigger DPCM sound 0x5B");
    TEST_CHECK(apu.dmc.enabled, "DMC channel must be enabled");
    TEST_CHECK(apu.dmc.bytes_remaining == 593, "DPCM sample 0x5B must have 593 bytes");

    apu_generate_samples(&apu, samples, 800);
    float dmc_energy = 0.0f;
    for (int i = 0; i < 800; ++i) {
        dmc_energy += samples[i] * samples[i];
    }
    printf("  DMC Playback Energy: %f (remaining bytes: %u)\n", (double)dmc_energy, apu.dmc.bytes_remaining);
    TEST_CHECK(dmc_energy > 0.01f, "DMC sample playback must generate audio energy");
    TEST_CHECK(apu.dmc.bytes_remaining < 593, "DMC bytes remaining must decrease as samples are read");

    // 3. Sound Engine Bytecode Execution: Stage 1 Jungle BGM (Sound 0x2A)
    apu_reset(&apu);
    apu_set_dmc_memory(&apu, bank7_prg, PRG_BANK_SIZE);
    sound_engine_reset(&engine);

    TEST_CHECK(sound_engine_play_sound(&engine, &apu, 0x2A) == RECON_OK, "Trigger BGM 0x2A");
    TEST_CHECK(engine.slots[SOUND_SLOT_BGM_PULSE1].sound_code == 0x2A, "Slot 0 must have BGM Pulse 1");
    TEST_CHECK(engine.slots[SOUND_SLOT_BGM_PULSE2].sound_code == 0x2A, "Slot 1 must have BGM Pulse 2");
    TEST_CHECK(engine.slots[SOUND_SLOT_BGM_TRI].sound_code == 0x2A, "Slot 2 must have BGM Triangle");
    TEST_CHECK(engine.slots[SOUND_SLOT_BGM_PERC].sound_code == 0x2A, "Slot 3 must have BGM Percussion");

    // Simulate 120 frames (~2 seconds) of BGM playback
    float total_bgm_energy = 0.0f;
    for (int f = 0; f < 120; ++f) {
        sound_engine_update_frame(&engine, &apu);
        apu_generate_samples(&apu, samples, 799);
        for (int i = 0; i < 799; ++i) {
            total_bgm_energy += samples[i] * samples[i];
        }
    }
    printf("  BGM 0x2A (120 frames) Total Synthesized Energy: %f\n", (double)total_bgm_energy);
    TEST_CHECK(total_bgm_energy > 10.0f, "BGM must produce substantial audio energy across 120 frames");

    // 4. Slot Priority Arbitration: SFX Slot 4 over BGM Slot 0
    // Trigger Shotgun SFX (Sound 0x0A)
    TEST_CHECK(sound_engine_play_sound(&engine, &apu, 0x0A) == RECON_OK, "Trigger SFX 0x0A");
    TEST_CHECK(engine.slots[SOUND_SLOT_SFX_PULSE1].sound_code == 0x0A, "Slot 4 must be active with SFX 0x0A");

    // Verify Slot 4 is active
    sound_engine_update_frame(&engine, &apu);
    TEST_CHECK(engine.slots[SOUND_SLOT_SFX_PULSE1].sound_code == 0x0A, "Slot 4 remains active");

    // 5. Deterministic Audio Simulation Hash Test
    // Run two identical 60-frame simulations and check CRC32 of audio output
    uint32_t crc_run1 = 0;
    uint32_t crc_run2 = 0;

    // Run 1
    {
        Apu2A03 apu1;
        apu_init(&apu1, 48000);
        apu_set_dmc_memory(&apu1, bank7_prg, PRG_BANK_SIZE);
        SoundEngine eng1;
        sound_engine_init(&eng1, &rom);
        sound_engine_play_sound(&eng1, &apu1, 0x2A);

        std::vector<float> all_samples;
        for (int f = 0; f < 60; ++f) {
            sound_engine_update_frame(&eng1, &apu1);
            float fbuf[799];
            apu_generate_samples(&apu1, fbuf, 799);
            all_samples.insert(all_samples.end(), fbuf, fbuf + 799);
        }
        crc_run1 = recon_crc32(reinterpret_cast<const uint8_t*>(all_samples.data()), all_samples.size() * sizeof(float));
    }

    // Run 2
    {
        Apu2A03 apu2;
        apu_init(&apu2, 48000);
        apu_set_dmc_memory(&apu2, bank7_prg, PRG_BANK_SIZE);
        SoundEngine eng2;
        sound_engine_init(&eng2, &rom);
        sound_engine_play_sound(&eng2, &apu2, 0x2A);

        std::vector<float> all_samples;
        for (int f = 0; f < 60; ++f) {
            sound_engine_update_frame(&eng2, &apu2);
            float fbuf[799];
            apu_generate_samples(&apu2, fbuf, 799);
            all_samples.insert(all_samples.end(), fbuf, fbuf + 799);
        }
        crc_run2 = recon_crc32(reinterpret_cast<const uint8_t*>(all_samples.data()), all_samples.size() * sizeof(float));
    }

    printf("  Audio Determinism Check: Run 1 CRC=0x%08X, Run 2 CRC=0x%08X\n", crc_run1, crc_run2);
    TEST_CHECK(crc_run1 == crc_run2, "Audio simulation must be 100% bit-for-bit deterministic");
    TEST_CHECK(crc_run1 != 0, "Audio CRC must not be zero");

    rom_free(&rom);
    printf("[PASS] All APU & Sound Engine unit tests passed successfully!\n");
    return 0;
}
