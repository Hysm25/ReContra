# Implementation Roadmap & Status (`docs/STATUS.md`)

> **Active Implementation State**: Tracks current sprint milestone, implementation checklist, and verification status across development sessions.

---

## 1. Current Phase: Godot 4 Migration — Step 4 of 5 (2A03 APU Synthesizer & 6-Slot Audio Engine)

- **Phase Objective**: Migrate engine from C23/SDL3 to a clean-room Godot 4 (GDScript) architecture.
- **Current Milestone**: Step 4 of 5 — 2A03 APU Synthesizer & 6-Slot Audio Engine (COMPLETED & 100% Verified).
- **Status**: Implemented `scripts/audio/apu_synthesizer.gd` and `scripts/audio/sound_engine.gd`; headless verification test suite passing 156/156 assertions with deterministic audio simulation hash `0x0C295808`.

---

## 2. Godot 4 Migration Roadmap (5 Steps)

- [x] **Step 1: Clean-Room Engine Foundation & UNROM Mapper 2 RomLoader**
  - [x] Remove legacy CMake, C/C++ `src/`, `tests/`, `.github/`, and `android/` directories.
  - [x] Configure `project.godot` (256x240 viewport, integer stretch, nearest-neighbor filter) and `.gitignore`.
  - [x] Implement generic, strongly-typed `scripts/rom/rom_loader.gd` (zero `TODO`s, iNES validation, SHA-256 / CRC-32 verification, `read_cpu` mapping).
  - [x] Create and pass headless verification test suite `scripts/tests/run_headless_tests.gd` (35/35 passing).
- [x] **Step 2: CHR Pattern Table RLE Decompressor & Palette Subsystem**
  - [x] Implement `scripts/rom/chr_extractor.gd` (Bank 7 pointers $C950/$C8E3, 4 RLE commands, bit-reversal, 8KB/16KB VRAM decompression).
  - [x] Implement `scripts/rom/level_loader.gd` (Bank 2 $B319 headers, Bank 3 supertiles, Bank 7 $D225 palettes, 3-case screen RLE decompression).
  - [x] Add comprehensive tests to `scripts/tests/run_headless_tests.gd` (116/116 passing).
- [x] **Step 3: PPU 256x240 Software / Tilemap Renderer & 8x16 OAM Sprite Engine**
  - [x] Implement `scripts/render/ppu_renderer.gd` (16KB VRAM, Vertical/Horizontal mirroring, $3F10-$3F1C palette folding, 256x240 RGBA8 buffer to Image/ImageTexture).
  - [x] Implement horizontal (8x7 supertiles), vertical (8x8 supertiles), and corridor perspective nametable + attribute table unpacking ($2000/$2400 and $23C0/$27C0).
  - [x] Implement 64 8x16 OAM sprite rasterizer with H/V flip, background priority masking, and authentic $4C cyclic 8-sprite scanline limit vs flicker-free toggle.
  - [x] Add PPU rendering and deterministic CRC-32 verification tests to `scripts/tests/run_headless_tests.gd` (133/133 passing, CRC-32 `0x820ABB35`).
- [x] **Step 4: 2A03 APU Synthesizer & 6-Slot Audio Engine**
  - [x] Implement `scripts/audio/apu_synthesizer.gd` generating 48 kHz stereo `PackedVector2Array` and `PackedFloat32Array` (Pulse 1, Pulse 2, Triangle, Noise, DMC, non-linear mixer curves, DC-blocking filter).
  - [x] Implement `scripts/audio/sound_engine.gd` dynamically parsing Bank 1 bytecode tables ($88E8, $88DB, $82CD, $8001, $86D5) with 6-slot priority arbitration (SFX Slot 4 over BGM Slot 0, SFX Slot 5 over BGM Slot 3) and sequencer flow control ($FD, $FE, $FF).
  - [x] Add APU & sound engine verification tests to `scripts/tests/run_headless_tests.gd` (156/156 assertions passing, deterministic audio CRC-32 `0x0C295808`).
- [ ] **Step 5: Physics, Player State Machine & Deterministic Replay Verification**

---

## 3. Session Change Log
- **2026-11-23**: Executed Step 4 of 5 for Godot 4 (GDScript) Clean-Room Migration:
  1. Implemented `scripts/audio/apu_synthesizer.gd` providing 48 kHz cycle-stepped emulation of Ricoh 2A03 5 channels (Pulse 1, Pulse 2, Triangle, Noise, 1-bit DMC), non-linear mixer curve calculation, and high-pass DC-blocking filter, outputting `PackedVector2Array` for `AudioStreamGenerator` and `PackedFloat32Array` for testing.
  2. Implemented `scripts/audio/sound_engine.gd` dynamically parsing Bank 1 sound tables ($88E8 sound commands, $88DB DPCM descriptors, $82CD percussion triggers, $8001 pulse envelopes, $86D5 note periods) via `RomLoader`. Handled 6 priority slots (SFX Pulse 1 Slot 4 over BGM Pulse 1 Slot 0; SFX Noise Slot 5 over BGM Percussion Slot 3) and bytecode control routines ($FD child calls, $FE repeat loops, $FF terminators, automatic decrescendo).
  3. Expanded `scripts/tests/run_headless_tests.gd` with 23 new unit tests verifying individual channel synthesis energy, DPCM sample extraction & playback (593-byte snare sample `0x5B`), 120-frame Stage 1 BGM (`0x2A`) simulation, SFX slot 4 priority override, stereo Vector2 format, and bit-for-bit deterministic simulation CRC-32 (`0x0C295808`) across 156 passing assertions.
- **2026-11-23**: Executed Step 3 of 5 for Godot 4 (GDScript) Clean-Room Migration:
  1. Implemented `scripts/render/ppu_renderer.gd` outputting 256x240 RGBA8 framebuffer convertible to Godot `Image` and `ImageTexture`, emulating 16 KB VRAM, nametable mirroring, 32-byte palette RAM folding, and fast precomputed 256-byte RGBA palette cache.
  2. Built dual-nametable horizontal (8x7 supertiles), vertical (8x8 supertiles), and 3D indoor perspective corridor unpackers populating nametables at `$2000/$2400` and attribute tables at `$23C0/$27C0`.
  3. Built 64 8x16 OAM sprite rasterizer with H/V flip, background priority masking, and toggleable authentic 8-sprite per scanline limit with cyclic `$4C` priority advance per frame.
  4. Expanded `scripts/tests/run_headless_tests.gd` with 17 new unit tests verifying PPU mirroring, Stage 1 background rendering (>33k active colored pixels), sprite flip and priority flags, cyclic `$4C` priority offset advance, and deterministic framebuffer CRC-32 (`0x820ABB35`) across 133 passing assertions.
- **2026-11-23**: Executed Step 2 of 5 for Godot 4 (GDScript) Clean-Room Migration:
  1. Implemented `scripts/rom/chr_extractor.gd` resolving Bank 7 graphics pointer tables ($C950 and $C8E3), 4 RLE stream commands ($FF end, $7F PPU jump, < $7F run repeat, > $7F literal stream), and horizontal bit-reversal (`reverse_bits_u8`).
  2. Implemented `scripts/rom/level_loader.gd` parsing 32-byte Level Headers from Bank 2 ($B319), 4x4 supertiles from Bank 3, and 110 3-color palette sets from Bank 7 ($D225), complete with 2C02 NTSC master palette RGBA8 conversion and authentic 3-case RLE screen supertile decompression.
  3. Expanded `scripts/tests/run_headless_tests.gd` with 81 new unit tests covering all 27 individual graphic codes, 13 level graphic sets, 8 level headers, palettes, supertiles, and RLE screen decompression (116/116 assertions passing).
- **2026-11-23**: Executed Step 1 of 5 for Godot 4 (GDScript) Clean-Room Migration:
  1. Purged old CMake build files, C/C++ sources (`src/`), unit tests (`tests/`), CI workflows (`.github/`), and Android packaging (`android/`).
  2. Created `project.godot` with 256x240 native viewport, integer scaling, and nearest-neighbor texture filtering; updated `.gitignore` with `.godot/`, `*.nes`, and `build/`.
  3. Implemented `scripts/rom/rom_loader.gd` in strongly-typed GDScript validating iNES header (Mapper 2 UNROM, 128 KB PRG, 0 CHR), computing whole-file and PRG SHA-256 and CRC-32 checksums against `docs/MEMORY.md`, and mapping CPU addresses ($8000-$BFFF to banks 0..6, $C000-$FFFF to Bank 7).
  4. Implemented `scripts/tests/run_headless_tests.gd` verifying all 35 test assertions under `godot --headless --script scripts/tests/run_headless_tests.gd`.


### Phase 0: Project Setup, Build Infrastructure & Replay Harness
- [x] Inspect local Contra `.nes` ROM (`Contra (USA).nes`) and ca65 disassembly (`nes-contra-us/`).
- [x] Establish clean-room legal boundary and `.gitignore`.
- [x] Deploy foundational documentation: `AGENTS.md`, `docs/ARCHITECTURE.md`, `docs/STATUS.md`, and `docs/MEMORY.md`.
- [x] Configure `CMakeLists.txt` with C23/C++20, SDL3 integration, `-Wall -Wextra -Werror`, and Sandy Bridge AVX-only support (`-mno-avx2`).
- [x] Implement headless CLI test harness (`--headless`, `--frames`, `--replay`, `--verify-hash`).

### Phase 1: ROM Loader & CHR RLE Decompressor (`src/rom/`)
- [x] Implement iNES header validator and SHA-256 / CRC32 checksum verifier for authentic Contra ROM.
- [x] Implement UNROM (Mapper 2) PRG bank reader (Banks 0–7, 16KB switchable + 16KB fixed).
- [x] Implement RLE decompression engine (`write_graphic_data_to_ppu`) matching disassembly algorithm:
  - Command `$FF` (End of stream).
  - Command `$7F` (PPU address update).
  - Run-length repetition (`< $7F`).
  - Literal byte stream (`> $7F`).
  - Horizontal flipping support for indoor corridor tiles.
- [x] Extract level palettes (`PALETTE_CPU_BUFFER` `$07C0`–`$07DF`) and supertile definitions.
- [x] Automated headless test verifying 100% byte-accurate tile extraction against disassembly references.

### Phase 2: PPU 256x240 Renderer & OAM Sprite Engine (`src/render/`)
- [x] Implement 256x240 32-bit RGBA native framebuffer.
- [x] Implement SDL3 integer-scaled rendering with nearest-neighbor texture filtering.
- [x] Build Nametable background renderer:
  - Supertile matrix decoder (4x4 tiles per supertile).
  - Horizontal scrolling engine (Stages 1, 5, 6, 7, 8).
  - Vertical scrolling engine (Stage 3 Waterfall).
  - 3D perspective corridor renderer (Stages 2, 4 Base levels).
- [x] Build 64-sprite OAM engine (`$0200`–`$02FF`):
  - 8x16 sprite composition.
  - Horizontal and vertical flipping.
  - Priority bit masking (behind background).
  - Authentic `$4C` offset frame priority cycling with optional flicker-free toggle.

### Phase 3: 2A03 APU Synthesizer & DPCM Audio (`src/audio/`)
- [x] Implement Ricoh 2A03 5-channel sound synthesis (Pulse 1, Pulse 2, Triangle, Noise, DMC).
- [x] Implement Contra 6-slot audio command engine (`$0100`–`$018F`):
  - Slot priorities and channel routing.
  - Bytecode parser for BGM tracks and SFX commands.
  - Envelope timers, decrescendo pauses, vibrato logic.
- [x] Implement Bank 7 DPCM sample decoder (`$FC00`–`$FFCF`) for percussion beats and explosions.
- [x] Stream synthesized audio via `SDL_AudioStream` (48 kHz 32-bit float).

### Phase 4: Core Gameplay Physics, Player State & Controls (`src/game/`)
- [x] Implement deterministic 60.0988 Hz fixed-timestep game loop (`GAME_ROUTINE_INDEX` `$18`).
- [x] Implement sub-pixel fixed-point physics (`Fast` + `Fract` accumulators).
- [x] Build Player State Machine (`PLAYER_STATE` `$90`):
  - 8-direction aiming (`PLAYER_AIM_DIR` `$C2`) mapped dynamically from Bank 7 `$D93A`.
  - Running, ducking, prone crawling, jumping arc (`PLAYER_JUMP_COEFFICIENT`, `-5.9375` px/frame initial impulse, `+0.1367` px/frame^2 gravity).
  - Water mechanics (swimming and submerged diving via `PLAYER_WATER_STATE`).
  - Hit recoil, death animation, invincibility respawn timer.
- [x] Implement background collision checks (`BG_COLLISION_DATA` `$0680`–`$06FF`):
  - Floor landing and drop-down (Down + Jump) with 12-frame floor bypass timer.
  - Water tiles and solid wall barriers.
- [x] Build GameRuntime coordination engine for camera scrolling, dual-nametable streaming, and PPU OAM sprite rendering.

### Phase 5: Weapon System & Bullet Pool (`src/game/weapons/`)
- [x] Implement 16-slot Player Bullet Pool (`$0368`–`$04B7`).
- [x] Implement Standard Rifle weapon.
- [x] Implement `M` (Machine Gun) rapid-fire weapon.
- [x] Implement `F` (Fireball) swirling trajectory weapon with authentic offset lookup tables.
- [x] Implement `S` (Spread Gun) 5-way angled bullet fan.
- [x] Implement `L` (Laser Gun) 4-segment continuous destructive beam.
- [x] Implement `R` (Rapid Fire) upgrade modifier.
- [x] Implement `B` (Barrier / Falcon) invincibility power-up.

### Phase 6: Stage 1 (Jungle) & Enemies (`src/game/stages/`)
- [ ] Implement Stage 1 horizontal scrolling progression.
- [ ] Implement Soldier generation routine (`SOLDIER_GENERATION_ROUTINE` `$79`).
- [ ] Implement Red Turrets, Snipers, Flying Falcons, and Exploding Bridges.
- [ ] Implement Stage 1 Wall Boss (Defense Wall sensors, gun, and core).

### Phase 7: Stages 2 & 4 (Base 1 & 2 3D Corridors)
- [ ] Implement 3D base perspective movement and electric barriers.
- [ ] Implement Rolling Grenade mechanics and ducking roll under fire.
- [ ] Implement Garma Kiru Defense System Boss (Stage 2) and Godomuga Boss (Stage 4).

### Phase 8: Stage 3 (Waterfall Vertical Scroll)
- [ ] Implement vertical upward scrolling and screen-wrap mechanics.
- [ ] Implement tumbling boulders, flame throwers, and scuba divers.
- [ ] Implement Gomeramos King Alien Boss (seeking dragon arm tentacle orb).

### Phase 9: Stages 5–8 & Final Alien Boss
- [ ] Implement Stage 5 (Snow Field) hovercraft tanks.
- [ ] Implement Stage 6 (Energy Zone) flame barriers and giant boss.
- [ ] Implement Stage 7 (Hangar) moving minecarts and alien gates.
- [ ] Implement Stage 8 (Alien's Lair) alien eggs, arachnid spawners, and tentacles.
- [ ] Implement Final Boss: Emperor Demon Dragon God Java & Pulsing Alien Heart.

### Phase 10: 2P Co-Op, Konami Code, Polish & Headless Verification
- [ ] Implement 2-Player simultaneous co-op mode (Bill & Lance).
- [ ] Implement Konami Code 30-lives sequence detector (`$08, $08, $04, $04, $02, $01, $02, $01, $40, $80`).
- [ ] Implement persistent high scores and game completion loop counter.
- [ ] Implement attract demo playback (`DEMO_MODE` `$1C`).
- [ ] Record and pass 100% deterministic headless replays for all 8 stages.

### Phase 11: Cross-Platform Packaging & Performance Optimization
- [x] Implement clean-room Android APK packaging (`arm64-v8a`) with Gradle, Prefab, and SDL3.
- [x] Implement Android Storage Access Framework (SAF) document picker and multi-touch on-screen overlay controls.
- [x] Deploy automated GitHub Actions CI workflow (`.github/workflows/android.yml`) building and uploading debug APK artifacts.
- [ ] Validate compilation and test pass on EndeavourOS Sandy Bridge (AVX-only, `-mno-avx2`).
- [x] Validate compilation and headless test pass inside Fedora PRoot ARM64.
- [ ] Package standalone desktop release with desktop entry and assets extractor.

---

## 3. Session Change Log
- **2026-11-23**: Fixed Visual, Attribute, and Player Rendering Subsystems (ADR-013, ADR-014, ADR-015):
  1. **Stage 1 Supertile RLE Decompression & Authentic Nametable / Attribute Alignment**: Implemented `level_decompress_screen_supertiles()` with authentic 3-case RLE decompression (`< $80` literal, `$80..$EF` repeat, `>= $F0` row copy). Fixed nametable tile indexing to begin at row 0 (PPU `$2000` / `$2400`, 28 tile rows) and attribute table indexing to begin at row 0 (PPU `$23C0` / `$27C0`, 7 attribute rows) directly from Bank 3 `level_1_palette_data`, removing the erroneous 2-row downward HUD offset. Updated `collision_grid_unpack_screen()` with decompressed supertiles so the collision grid matches authentic stage terrain.
  2. **Player OAM Sprite Tile Unpacking & Palette Assignment**: Implemented dynamic Bank 1 sprite unpacker querying `sprite_ptr_tbl_0` at CPU `$B030` with `$80` shared-sprite chaining. Mapped player state machine to authentic CHR tile indices and sprite palettes: standing (`0x0F`, torso `0x94`/legs `0x3C`), running (6-frame anim sequence `0x02..0x06` cycling every 8 frames), somersault jumping (`0x08`/`0x09` alternating every 6 frames, tiles `0x44`/`0x4C`), crouching (`0x17`, tile `0x9C`), and water states (surface swim `0x1D`/submerged dive `0x19`, tiles `0xDE`). Assigned Sprite Palette 0 (`$3F11-$3F13`) for Player 1 and Sprite Palette 1 (`$3F15-$3F17`) for Player 2, and implemented authentic horizontal flip X-mirroring (`-8 - rel_x`).
  3. **Android Viewport & Virtual Touch Controls Overlay**: Enforced strict `landscape` orientation in `android/app/src/main/AndroidManifest.xml`. Explicitly cleared the SDL renderer to pure black (`0, 0, 0, 255`) on every frame to eliminate letterbox margin flashing. Decoupled touch controls overlay rendering from integer-scaled logical presentation, drawing directly in window pixel coordinates matching normalized touch event coordinates. Added `--touch` CLI flag and enabled by default on Android.
  4. Verified all 8 CTest suites pass cleanly (100% passing) and verified deterministic headless simulation hash (`0x17600FEB`).
- **2026-11-23**: Completed Phase 5: implemented 16-slot Player Bullet Pool (`$0368`–`$04B7`), dynamic ROM Bank 6 table resolution for 19 trajectory, velocity, aim modifier, and sound/sprite tables (`$B55D`, `$B5A7`, `$B5AB`, `$B5FA`, `$B60E`, `$B6E9`, `$B719`, `$B749`, `$B779`, `$B817`, `$B891`, `$B89D`, `$B8AA`, `$B8BA`, `$B8FA`, `$B90A`, `$BA17`, `$BADE`, `$BAE2`). Built authentic Standard Rifle (max 4 bullets), Machine Gun (continuous stream with `m_fire_timer` burst/cooldown logic, max 6 bullets), Fireball (`F`) with non-linear 16-step circular swirling trajectory around center coordinates, Spread Gun (`S`) with 5-way angled bullet fan and travel distance-based sprite progression (`0x1F` -> `0x20` -> `0x21`), Laser Gun (`L`) with 4-segment continuous destructive beam and staggered delay routines (10, 7, 4, 1), Rapid Fire (`R`) velocity speed-up, and Barrier (`B`) invincibility protection with 8-frame tick cadence. Integrated into `GameRuntime` fixed-timestep simulation, OAM sprite rendering, and achieved 100% CTest pass rate (8/8 tests passing).
- **2026-11-23**: Fixed Clang NDK `-Wsign-conversion` compilation errors in `src/audio/apu.c` by ensuring timer periods, DMC addresses/lengths, and LFSR feedback bitshifts use explicit unsigned promotion (`uint32_t`) with unsigned shift literals (`8u`, `6u`, `4u`, `14u`). Verified clean compilation across all source files under Clang with `-Wall -Wextra -Wpedantic -Wconversion -Werror`, and confirmed 100% desktop/headless CTest pass rate (7/7 tests passing).
- **2026-11-23**: Added clean-room Android APK packaging (`arm64-v8a`) and automated GitHub Actions CI workflow (`.github/workflows/android.yml`). Configured `CMakeLists.txt` for conditional `libmain.so` shared library compilation with SDL3 Prefab support, built minimal self-contained `android/` Gradle project with automated SDL3 AAR fetching, implemented Android document picker (`ACTION_OPEN_DOCUMENT`) and multi-path ROM discovery, and created responsive on-screen virtual touch controls (D-Pad, A, B, Select, Start) with alpha-blended rendering.
- **2026-11-23**: Completed Phase 4: implemented 128-byte background collision grid (`BG_COLLISION_DATA` `$0680`–`$06FF`), player state machine (`PLAYER_STATE` `$90`), 8-direction authentic aim table dynamically loaded from Bank 7 `$D93A`, parabolic jump physics (`-5.9375` px/frame initial impulse, `+0.1367` px/frame^2 gravity), Down + Jump platform drop-down with 12-frame floor bypass timer (`edge_fall_code`), water swimming/submerged diving, damage recoil arc, `GameRuntime` 60.0988 Hz fixed-timestep coordinator with dual-nametable horizontal scrolling, and 100% CTest verification pass (7/7 passing, 3600-frame hash `0xEFB99A22`).
- **2026-11-23**: Completed Phase 3: implemented Ricoh 2A03 5-channel sound synthesizer (Pulse 1, Pulse 2, Triangle, Noise, DMC), 6-slot audio command engine (`$0100`–`$018F`), Bank 1 bytecode interpreter and volume envelopes (`$88E8`, `$88DB`, `$82CD`, `$8001`, `$86D5`), Bank 7 DPCM percussion sample ingestion (`$FC00`–`$FFCF`), SDL3 `SDL_AudioStream` integration, and 100% deterministic audio hash verification.
- **2026-11-23**: Completed Phase 2: implemented 2C02 PPU 256x240 software framebuffer renderer, 4-way nametable mirroring, supertile matrix unpackers for horizontal, vertical, and perspective corridor modes, 8x16 OAM sprite rasterizer with horizontal/vertical flipping, priority masking, authentic $4C cyclic priority shifting, and flicker-free toggle.
- **2026-11-23**: Completed Phase 0 & Phase 1: implemented CMake build system, C23 crypto primitives (SHA-256, CRC-32), UNROM Mapper 2 ROM loader, Bank 7 dynamic RLE CHR tile decompressor, Bank 2/3 level header and supertile parsers, 2C02 NTSC RGBA palette mapping, headless CLI deterministic test harness, and 100% passing automated unit test suite.
- **2026-11-22**: Initialized clean-room project documentation foundation tailored to `nes-contra-us` disassembly symbols, RAM addresses, UNROM bank layouts, and SDL3 architecture.
