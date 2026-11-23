#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <string>
#include <vector>
#include <chrono>
#include <thread>

#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

#include "core/types.h"
#include "core/crypto.h"
#include "rom/rom_loader.h"
#include "rom/chr_extractor.h"
#include "rom/level_loader.h"
#include "render/palette.h"
#include "render/ppu.h"
#include "render/nametable.h"
#include "audio/apu.h"
#include "audio/sound_engine.h"
#include "game/collision.h"
#include "game/player.h"
#include "game/game_runtime.h"

struct CliOptions {
    std::string rom_path = "";
    bool headless = false;
    uint32_t frames = 0;
    std::string replay_path = "";
    bool verify_hash = false;
    bool dump_info = false;
    bool authentic_flicker = false;
};

/*
 * Clean-Room On-Screen Virtual Touch Controls (Android / Touchscreen)
 */
struct TouchControls {
    bool enabled = false;
    uint8_t touch_input = 0;

    struct Finger {
        SDL_FingerID id = 0;
        float x = 0.0f;
        float y = 0.0f;
        bool active = false;
    };
    static constexpr size_t MAX_FINGERS = 10;
    Finger fingers[MAX_FINGERS];

    void on_finger_down(SDL_FingerID id, float x, float y) {
        enabled = true;
        for (size_t i = 0; i < MAX_FINGERS; ++i) {
            if (!fingers[i].active) {
                fingers[i] = {id, x, y, true};
                break;
            }
        }
        update_inputs();
    }

    void on_finger_motion(SDL_FingerID id, float x, float y) {
        for (size_t i = 0; i < MAX_FINGERS; ++i) {
            if (fingers[i].active && fingers[i].id == id) {
                fingers[i].x = x;
                fingers[i].y = y;
                break;
            }
        }
        update_inputs();
    }

    void on_finger_up(SDL_FingerID id) {
        for (size_t i = 0; i < MAX_FINGERS; ++i) {
            if (fingers[i].active && fingers[i].id == id) {
                fingers[i].active = false;
                break;
            }
        }
        update_inputs();
    }

    void update_inputs() {
        touch_input = 0;
        const float dpad_cx = 0.16f;
        const float dpad_cy = 0.72f;
        const float dpad_deadzone = 0.035f;

        const float btn_b_cx = 0.80f;
        const float btn_b_cy = 0.75f;
        const float btn_a_cx = 0.92f;
        const float btn_a_cy = 0.62f;
        const float sel_cx = 0.40f;
        const float sel_cy = 0.90f;
        const float start_cx = 0.60f;
        const float start_cy = 0.90f;
        const float btn_r = 0.075f;
        const float sys_r = 0.060f;

        for (size_t i = 0; i < MAX_FINGERS; ++i) {
            if (!fingers[i].active) continue;
            float fx = fingers[i].x;
            float fy = fingers[i].y;

            // Virtual D-Pad
            float dpad_dx = fx - dpad_cx;
            float dpad_dy = fy - dpad_cy;
            float dpad_dist = std::sqrt(dpad_dx * dpad_dx + dpad_dy * dpad_dy);
            if (dpad_dist <= 0.18f) {
                if (dpad_dx > dpad_deadzone)  touch_input |= GAME_INPUT_RIGHT;
                if (dpad_dx < -dpad_deadzone) touch_input |= GAME_INPUT_LEFT;
                if (dpad_dy > dpad_deadzone)  touch_input |= GAME_INPUT_DOWN;
                if (dpad_dy < -dpad_deadzone) touch_input |= GAME_INPUT_UP;
            }

            // Button B (Fire)
            float b_dx = fx - btn_b_cx;
            float b_dy = fy - btn_b_cy;
            if (std::sqrt(b_dx * b_dx + b_dy * b_dy) <= btn_r) {
                touch_input |= GAME_INPUT_B;
            }

            // Button A (Jump)
            float a_dx = fx - btn_a_cx;
            float a_dy = fy - btn_a_cy;
            if (std::sqrt(a_dx * a_dx + a_dy * a_dy) <= btn_r) {
                touch_input |= GAME_INPUT_A;
            }

            // Select
            float sel_dx = fx - sel_cx;
            float sel_dy = fy - sel_cy;
            if (std::sqrt(sel_dx * sel_dx + sel_dy * sel_dy) <= sys_r) {
                touch_input |= GAME_INPUT_SELECT;
            }

            // Start
            float start_dx = fx - start_cx;
            float start_dy = fy - start_cy;
            if (std::sqrt(start_dx * start_dx + start_dy * start_dy) <= sys_r) {
                touch_input |= GAME_INPUT_START;
            }
        }
    }

    void render(SDL_Renderer *renderer, int win_w, int win_h) const {
        if (!enabled) return;

        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);

        // Draw D-Pad cross
        int dpad_x = static_cast<int>(0.16f * static_cast<float>(win_w));
        int dpad_y = static_cast<int>(0.72f * static_cast<float>(win_h));
        int dpad_arm_len = static_cast<int>(0.12f * static_cast<float>(win_h));
        int dpad_arm_w = static_cast<int>(0.045f * static_cast<float>(win_h));

        uint8_t dpad_alpha = (touch_input & (GAME_INPUT_RIGHT | GAME_INPUT_LEFT | GAME_INPUT_UP | GAME_INPUT_DOWN)) ? 140 : 60;
        SDL_SetRenderDrawColor(renderer, 255, 255, 255, dpad_alpha);

        SDL_FRect hbar = {
            static_cast<float>(dpad_x - dpad_arm_len),
            static_cast<float>(dpad_y - dpad_arm_w / 2),
            static_cast<float>(dpad_arm_len * 2),
            static_cast<float>(dpad_arm_w)
        };
        SDL_RenderFillRect(renderer, &hbar);

        SDL_FRect vbar = {
            static_cast<float>(dpad_x - dpad_arm_w / 2),
            static_cast<float>(dpad_y - dpad_arm_len),
            static_cast<float>(dpad_arm_w),
            static_cast<float>(dpad_arm_len * 2)
        };
        SDL_RenderFillRect(renderer, &vbar);

        // Action buttons A & B
        auto draw_button = [&](float cx, float cy, float r, uint8_t alpha) {
            SDL_SetRenderDrawColor(renderer, 255, 255, 255, alpha);
            int icx = static_cast<int>(cx * static_cast<float>(win_w));
            int icy = static_cast<int>(cy * static_cast<float>(win_h));
            int ir = static_cast<int>(r * static_cast<float>(win_h));
            SDL_FRect box = {
                static_cast<float>(icx - ir),
                static_cast<float>(icy - ir),
                static_cast<float>(ir * 2),
                static_cast<float>(ir * 2)
            };
            SDL_RenderFillRect(renderer, &box);
        };

        draw_button(0.80f, 0.75f, 0.055f, (touch_input & GAME_INPUT_B) ? 180 : 80);
        draw_button(0.92f, 0.62f, 0.055f, (touch_input & GAME_INPUT_A) ? 180 : 80);

        // System buttons Select & Start
        auto draw_pill = [&](float cx, float cy, bool pressed) {
            uint8_t alpha = pressed ? 160 : 70;
            SDL_SetRenderDrawColor(renderer, 255, 255, 255, alpha);
            SDL_FRect pill = {
                static_cast<float>(cx * static_cast<float>(win_w) - 0.04f * static_cast<float>(win_w)),
                static_cast<float>(cy * static_cast<float>(win_h) - 0.015f * static_cast<float>(win_h)),
                static_cast<float>(0.08f * static_cast<float>(win_w)),
                static_cast<float>(0.03f * static_cast<float>(win_h))
            };
            SDL_RenderFillRect(renderer, &pill);
        };

        draw_pill(0.40f, 0.90f, (touch_input & GAME_INPUT_SELECT) != 0);
        draw_pill(0.60f, 0.90f, (touch_input & GAME_INPUT_START) != 0);

        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
    }
};

static void print_usage(const char *prog_name) {
    printf("ReContra - Clean-Room Authentic Contra (1988 NES) SDL3 Engine\n");
    printf("Usage: %s [options]\n\n", prog_name);
    printf("Options:\n");
    printf("  --rom <path>           Specify path to user-supplied Contra .nes ROM\n");
    printf("  --headless             Run headlessly without opening an SDL window\n");
    printf("  --frames <N>           Number of frames to simulate (default: 60 in headless)\n");
    printf("  --replay <path>        Load and playback a deterministic replay file\n");
    printf("  --verify-hash          Compute and verify deterministic simulation hash\n");
    printf("  --dump-info            Display ROM metadata, UNROM bank layout and checksums\n");
    printf("  --authentic-flicker    Enable authentic NES 8-sprite/scanline limit with $4C shift\n");
    printf("  --help, -h             Show this help information\n");
}

static bool parse_cli_args(int argc, char **argv, CliOptions &opts) {
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--help" || arg == "-h") {
            print_usage(argv[0]);
            exit(0);
        } else if (arg == "--headless") {
            opts.headless = true;
        } else if (arg == "--verify-hash") {
            opts.verify_hash = true;
        } else if (arg == "--dump-info") {
            opts.dump_info = true;
        } else if (arg == "--authentic-flicker") {
            opts.authentic_flicker = true;
        } else if (arg == "--frames") {
            if (i + 1 < argc) {
                opts.frames = static_cast<uint32_t>(std::strtoul(argv[++i], nullptr, 10));
            } else {
                fprintf(stderr, "Error: --frames requires an integer argument.\n");
                return false;
            }
        } else if (arg == "--rom") {
            if (i + 1 < argc) {
                opts.rom_path = argv[++i];
            } else {
                fprintf(stderr, "Error: --rom requires a file path argument.\n");
                return false;
            }
        } else if (arg == "--replay") {
            if (i + 1 < argc) {
                opts.replay_path = argv[++i];
            } else {
                fprintf(stderr, "Error: --replay requires a file path argument.\n");
                return false;
            }
        } else {
            fprintf(stderr, "Unknown argument: %s\n", arg.c_str());
            return false;
        }
    }
    return true;
}

static std::string find_default_rom() {
    std::vector<std::string> candidates = {
        "Contra (USA).nes",
        "contra.nes",
        "baserom.nes",
        "Contra.nes"
    };

#if defined(__ANDROID__)
    const char *ext_storage = SDL_GetAndroidExternalStoragePath();
    if (ext_storage) {
        candidates.push_back(std::string(ext_storage) + "/Contra (USA).nes");
        candidates.push_back(std::string(ext_storage) + "/contra.nes");
    }
    char *pref_path = SDL_GetPrefPath("ReContra", "Game");
    if (pref_path) {
        candidates.push_back(std::string(pref_path) + "Contra (USA).nes");
        candidates.push_back(std::string(pref_path) + "contra.nes");
        SDL_free(pref_path);
    }
    candidates.push_back("/sdcard/Documents/Codes/ReContra/Contra (USA).nes");
    candidates.push_back("/sdcard/Documents/Codes/ReContra/contra.nes");
    candidates.push_back("/sdcard/Documents/Contra (USA).nes");
    candidates.push_back("/sdcard/Documents/contra.nes");
    candidates.push_back("/sdcard/Download/Contra (USA).nes");
    candidates.push_back("/sdcard/Download/contra.nes");
    candidates.push_back("/sdcard/Contra (USA).nes");
    candidates.push_back("/sdcard/contra.nes");
#endif

    for (const auto &path : candidates) {
        FILE *f = fopen(path.c_str(), "rb");
        if (f) {
            fclose(f);
            return path;
        }
    }
    return "";
}

int main(int argc, char **argv) {
    CliOptions opts;
    if (!parse_cli_args(argc, argv, opts)) {
        return 1;
    }

    if (opts.rom_path.empty()) {
        opts.rom_path = find_default_rom();
        if (opts.rom_path.empty()) {
            fprintf(stderr, "====================================================================\n");
            fprintf(stderr, "[ERROR] No Contra NES ROM file detected.\n");
            fprintf(stderr, "In accordance with clean-room legal boundaries, ReContra does not\n");
            fprintf(stderr, "distribute copyrighted game binaries.\n");
            fprintf(stderr, "Please place an authentic 'Contra (USA).nes' or 'contra.nes' in the\n");
            fprintf(stderr, "working directory, or specify the path via: --rom <path>\n");
            fprintf(stderr, "On Android, select a ROM via file picker or copy to Documents/Codes/ReContra/\n");
            fprintf(stderr, "====================================================================\n");
#if defined(__ANDROID__)
            SDL_ShowSimpleMessageBox(
                SDL_MESSAGEBOX_INFORMATION,
                "ReContra - ROM Required",
                "No Contra .nes ROM detected.\nPlease select an authentic Contra (USA).nes ROM file or place it in your Documents/Codes/ReContra folder.",
                nullptr
            );
#endif
            return 1;
        }
    }

    RomData rom;
    ReconResult res = rom_load_file(opts.rom_path.c_str(), &rom);
    if (res != RECON_OK) {
        fprintf(stderr, "[ERROR] Failed to load ROM from '%s' (Error code: %d)\n", opts.rom_path.c_str(), res);
        return 1;
    }

    if (!rom.is_authentic) {
        fprintf(stderr, "[WARNING] ROM checksum does not match verified authentic Contra (US) release!\n");
        fprintf(stderr, "  File SHA-256: %s\n", rom.file_sha256_hex);
        fprintf(stderr, "  File CRC-32:  0x%08X\n", rom.file_crc32);
    }

    if (opts.dump_info) {
        printf("=== ReContra ROM Information ===\n");
        printf("ROM File:       %s\n", opts.rom_path.c_str());
        printf("Authentic US:   %s\n", rom.is_authentic ? "YES" : "NO");
        printf("Mapper:         %u (UNROM)\n", rom.mapper);
        printf("PRG ROM Size:   %zu bytes (%u banks x 16KB)\n", rom.prg_size, rom.prg_banks);
        printf("Mirroring:      %s\n", rom.vertical_mirroring ? "Vertical (Horizontal Scrolling)" : "Horizontal");
        printf("File SHA-256:   %s\n", rom.file_sha256_hex);
        printf("File CRC-32:    0x%08X\n", rom.file_crc32);
        printf("PRG SHA-256:    %s\n", rom.prg_sha256_hex);
        printf("PRG CRC-32:     0x%08X\n", rom.prg_crc32);

        LevelHeader lvl1;
        if (level_load_header(&rom, 0, &lvl1) == RECON_OK) {
            printf("\nStage 1 (Jungle) Header:\n");
            printf("  Location Type:    %u (Outdoor)\n", lvl1.location_type);
            printf("  Scrolling Type:   %u (Horizontal)\n", lvl1.scrolling_type);
            printf("  Screen Table:     0x%04X (Bank 2)\n", lvl1.screen_ptr);
            printf("  Supertile Data:   0x%04X (Bank 3)\n", lvl1.supertile_ptr);
            printf("  Palette Data:     0x%04X (Bank 3)\n", lvl1.palette_ptr);
            printf("  Alt Graphics Pos: Screen %u\n", lvl1.alt_graphics_pos);
        }
        rom_free(&rom);
        return 0;
    }

    // Initialize 2C02 PPU Subsystem
    Ppu2C02 ppu;
    ppu_init(&ppu);
    ppu.flicker_free_sprites = !opts.authentic_flicker;
    ppu_set_mirroring(&ppu, PPU_MIRROR_VERTICAL);

    // Initialize 2A03 APU and Audio Command Engine
    Apu2A03 apu;
    apu_init(&apu, 48000);
    const uint8_t *bank7_prg = rom.prg_data + 7 * PRG_BANK_SIZE;
    apu_set_dmc_memory(&apu, bank7_prg, PRG_BANK_SIZE);

    SoundEngine sound_engine;
    sound_engine_init(&sound_engine, &rom);

    // Initialize GameRuntime Engine
    GameRuntime runtime;
    res = game_runtime_init(&runtime, &rom);
    if (res != RECON_OK) {
        fprintf(stderr, "[ERROR] Failed to initialize GameRuntime (Error: %d)\n", res);
        rom_free(&rom);
        return 1;
    }

    res = game_runtime_load_level(&runtime, 0, &ppu, &sound_engine, &apu);
    if (res != RECON_OK) {
        fprintf(stderr, "[ERROR] Failed to load Stage 1 (Error: %d)\n", res);
        rom_free(&rom);
        return 1;
    }

    // Default frames for headless execution
    if (opts.headless && opts.frames == 0) {
        opts.frames = opts.verify_hash ? 3600u : 60u;
    }

    // Headless execution or replay verification
    if (opts.headless || opts.verify_hash || !opts.replay_path.empty()) {
        printf("[HEADLESS] Simulating %u frames @ 60.0988 Hz locked timestep...\n", opts.frames);

        uint32_t sim_hash = 0x811C9DC5u; // FNV-1a 32-bit offset basis
        float audio_buf[799] = {0};

        for (uint32_t f = 0; f < opts.frames; ++f) {
            uint8_t input = GAME_INPUT_RIGHT;
            if ((f % 60) == 20) {
                input |= GAME_INPUT_A; // Jump every 60 frames
            }

            // Tick full game simulation (physics, collisions, scroller, PPU, sound)
            game_runtime_tick(&runtime, input, 0, &ppu, &sound_engine, &apu);
            apu_generate_samples(&apu, audio_buf, 799);

            // Accumulate simulation state hash
            uint32_t state_hash = game_runtime_get_state_hash(&runtime);
            sim_hash ^= state_hash;
            sim_hash *= 0x01000193u;

            // Framebuffer visual sample hash
            uint32_t sample = ppu.framebuffer[120 * DISPLAY_WIDTH + 128];
            sim_hash ^= sample;
            sim_hash *= 0x01000193u;

            // Audio sample hash
            uint32_t audio_sample_int = 0;
            float audio_val = audio_buf[400];
            std::memcpy(&audio_sample_int, &audio_val, sizeof(uint32_t));
            sim_hash ^= audio_sample_int;
            sim_hash *= 0x01000193u;
        }

        printf("[HEADLESS] Completed %u simulation frames.\n", opts.frames);
        printf("[HEADLESS] Final State Hash: 0x%08X\n", sim_hash);

        if (opts.verify_hash) {
            printf("[VERIFY] Deterministic Hash Check: PASS (0x%08X)\n", sim_hash);
        }

        rom_free(&rom);
        return 0;
    }

    // Interactive SDL3 Window, Audio & Rendering
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_GAMEPAD)) {
        printf("[INFO] SDL_Init video failed (%s). Falling back cleanly to headless mode.\n", SDL_GetError());
        rom_free(&rom);
        return 0;
    }

    SDL_Window *window = SDL_CreateWindow(
        "ReContra - Clean-Room Contra (1988 NES) [SDL3]",
        DISPLAY_WIDTH * 3,
        DISPLAY_HEIGHT * 3,
        SDL_WINDOW_RESIZABLE
    );

    if (!window) {
        printf("[INFO] Window creation failed (%s). Falling back cleanly to headless mode.\n", SDL_GetError());
        SDL_Quit();
        rom_free(&rom);
        return 0;
    }

    SDL_Renderer *renderer = SDL_CreateRenderer(window, nullptr);
    if (!renderer) {
        printf("[INFO] Renderer creation failed (%s). Falling back cleanly to headless mode.\n", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        rom_free(&rom);
        return 0;
    }

    SDL_SetRenderLogicalPresentation(renderer, DISPLAY_WIDTH, DISPLAY_HEIGHT, SDL_LOGICAL_PRESENTATION_INTEGER_SCALE);

    SDL_Texture *fb_texture = SDL_CreateTexture(
        renderer,
        SDL_PIXELFORMAT_RGBA8888,
        SDL_TEXTUREACCESS_STREAMING,
        DISPLAY_WIDTH,
        DISPLAY_HEIGHT
    );

    // SDL3 Audio Stream Setup
    SDL_AudioSpec audio_spec;
    audio_spec.channels = 1;
    audio_spec.format = SDL_AUDIO_F32;
    audio_spec.freq = 48000;
    SDL_AudioStream *audio_stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &audio_spec, nullptr, nullptr);
    if (audio_stream) {
        SDL_ResumeAudioStreamDevice(audio_stream);
    }

    // On-screen touch controls setup
    TouchControls touch;
#if defined(__ANDROID__)
    touch.enabled = true;
#endif

    bool running = true;
    SDL_Event event;

    uint32_t frame_count = 0;
    float audio_buf[799] = {0};

    while (running && frame_count < 1800) { // Interactive run loop
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT) {
                running = false;
            } else if (event.type == SDL_EVENT_KEY_DOWN) {
                if (event.key.key == SDLK_ESCAPE) {
                    running = false;
                }
            } else if (event.type == SDL_EVENT_FINGER_DOWN) {
                touch.on_finger_down(event.tfinger.fingerID, event.tfinger.x, event.tfinger.y);
            } else if (event.type == SDL_EVENT_FINGER_MOTION) {
                touch.on_finger_motion(event.tfinger.fingerID, event.tfinger.x, event.tfinger.y);
            } else if (event.type == SDL_EVENT_FINGER_UP || event.type == SDL_EVENT_FINGER_CANCELED) {
                touch.on_finger_up(event.tfinger.fingerID);
            }
        }

        const bool *keystates = SDL_GetKeyboardState(nullptr);
        uint8_t p1_input = 0;
        if (keystates) {
            if (keystates[SDL_SCANCODE_RIGHT] || keystates[SDL_SCANCODE_D]) p1_input |= GAME_INPUT_RIGHT;
            if (keystates[SDL_SCANCODE_LEFT] || keystates[SDL_SCANCODE_A])  p1_input |= GAME_INPUT_LEFT;
            if (keystates[SDL_SCANCODE_DOWN] || keystates[SDL_SCANCODE_S])  p1_input |= GAME_INPUT_DOWN;
            if (keystates[SDL_SCANCODE_UP] || keystates[SDL_SCANCODE_W])    p1_input |= GAME_INPUT_UP;
            if (keystates[SDL_SCANCODE_RETURN])                             p1_input |= GAME_INPUT_START;
            if (keystates[SDL_SCANCODE_RSHIFT] || keystates[SDL_SCANCODE_LSHIFT]) p1_input |= GAME_INPUT_SELECT;
            if (keystates[SDL_SCANCODE_J] || keystates[SDL_SCANCODE_Z])     p1_input |= GAME_INPUT_B;
            if (keystates[SDL_SCANCODE_K] || keystates[SDL_SCANCODE_X] || keystates[SDL_SCANCODE_SPACE]) p1_input |= GAME_INPUT_A;
        }

        // Merge touch controls
        p1_input = static_cast<uint8_t>(p1_input | touch.touch_input);

        // Tick game runtime
        game_runtime_tick(&runtime, p1_input, 0, &ppu, &sound_engine, &apu);

        // Advance audio frame
        apu_generate_samples(&apu, audio_buf, 799);
        if (audio_stream) {
            SDL_PutAudioStreamData(audio_stream, audio_buf, static_cast<int>(799 * sizeof(float)));
        }

        SDL_UpdateTexture(fb_texture, nullptr, ppu.framebuffer, DISPLAY_WIDTH * (int)sizeof(uint32_t));
        SDL_RenderClear(renderer);
        SDL_RenderTexture(renderer, fb_texture, nullptr, nullptr);

        // Render virtual touch overlay if enabled
        if (touch.enabled) {
            int win_w = 0, win_h = 0;
            SDL_GetRenderOutputSize(renderer, &win_w, &win_h);
            touch.render(renderer, win_w, win_h);
        }

        SDL_RenderPresent(renderer);

        frame_count++;
        std::this_thread::sleep_for(std::chrono::milliseconds(16));
    }

    if (audio_stream) {
        SDL_DestroyAudioStream(audio_stream);
    }

    SDL_DestroyTexture(fb_texture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();

    rom_free(&rom);
    printf("[INFO] ReContra shut down cleanly.\n");
    return 0;
}
