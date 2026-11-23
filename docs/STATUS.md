# Implementation Roadmap & Status (`docs/STATUS.md`)

> **Active Implementation State**: Tracks current sprint milestone, implementation checklist, and verification status across development sessions.

---

## 1. Current Phase: Godot 4 Migration Complete — Advancing to Milestone 6 (Stage 1 Enemies & Boss)

- **Phase Objective**: Migrate engine from C23/SDL3 to a clean-room Godot 4.3+ (GDScript) architecture.
- **Current Milestone**: Godot 4 Clean-Room Migration Completed (Steps 1–5 / 100% Verified). Next Active Milestone: Milestone 6 — Stage 1 (Jungle) & Enemies.
- **Status**: Implemented `src/game/collision.gd`, `src/game/player.gd`, `src/game/weapons.gd`, `src/game/game_loop.gd`, `src/main.tscn`, and `src/main.gd`. Headless verification test suite passing 187/187 assertions with deterministic state hash `0x811C9DC5` and audio hash `0x0C295808` across 6 modular test suites under `tests/` orchestrated by `tests/run_headless_tests.gd`.

---

## 2. Godot 4 Migration Roadmap (5 Steps)

- [x] **Step 1: Clean-Room Engine Foundation & UNROM Mapper 2 RomLoader**
  - [x] Remove legacy CMake, C/C++ `src/`, `tests/`, `.github/`, and `android/` directories.
  - [x] Configure `project.godot` (256x240 viewport, integer stretch, nearest-neighbor filter) and `.gitignore`.
  - [x] Implement generic, strongly-typed `src/rom/rom_loader.gd` (zero `TODO`s, iNES validation, SHA-256 / CRC-32 verification, `read_cpu` mapping).
  - [x] Create and pass headless verification test suite `tests/test_rom_loader.gd` (30/30 passing).
- [x] **Step 2: CHR Pattern Table RLE Decompressor & Palette Subsystem**
  - [x] Implement `src/rom/chr_extractor.gd` (Bank 7 pointers $C950/$C8E3, 4 RLE commands, bit-reversal, 8KB/16KB VRAM decompression).
  - [x] Implement `src/rom/level_loader.gd` (Bank 2 $B319 headers, Bank 3 supertiles, Bank 7 $D225 palettes, 3-case screen RLE decompression).
  - [x] Add comprehensive tests to `tests/test_chr_extractor.gd` (16/16 passing) and `tests/test_level_loader.gd` (70/70 passing).
- [x] **Step 3: PPU 256x240 Software / Tilemap Renderer & 8x16 OAM Sprite Engine**
  - [x] Implement `src/render/ppu_renderer.gd` (16KB VRAM, Vertical/Horizontal mirroring, $3F10-$3F1C palette folding, 256x240 RGBA8 buffer to Image/ImageTexture).
  - [x] Implement horizontal (8x7 supertiles), vertical (8x8 supertiles), and corridor perspective nametable + attribute table unpacking ($2000/$2400 and $23C0/$27C0).
  - [x] Implement 64 8x16 OAM sprite rasterizer with H/V flip, background priority masking, and authentic $4C cyclic 8-sprite scanline limit vs flicker-free toggle.
  - [x] Add PPU rendering and deterministic CRC-32 verification tests to `tests/test_ppu_renderer.gd` (17/17 passing, CRC-32 `0x820ABB35`).
- [x] **Step 4: 2A03 APU Synthesizer & 6-Slot Audio Engine**
  - [x] Implement `src/audio/apu_synthesizer.gd` generating 48 kHz stereo `PackedVector2Array` and `PackedFloat32Array` (Pulse 1, Pulse 2, Triangle, Noise, DMC, non-linear mixer curves, DC-blocking filter).
  - [x] Implement `src/audio/sound_engine.gd` dynamically parsing Bank 1 bytecode tables ($88E8, $88DB, $82CD, $8001, $86D5) with 6-slot priority arbitration (SFX Slot 4 over BGM Slot 0, SFX Slot 5 over BGM Slot 3) and sequencer flow control ($FD, $FE, $FF).
  - [x] Add APU & sound engine verification tests to `tests/test_apu_sound.gd` (23/23 assertions passing, deterministic audio CRC-32 `0x0C295808`).
- [x] **Step 5: Physics, Player State Machine, Weapon Pools & Deterministic Replay Verification**
  - [x] Implement `src/game/player.gd` (player state machine, aiming, parabolic jump `-5.9375 px/frame` + `+0.1367` gravity, water diving, death recoil, Bank 1 `$B030` OAM frame unpacking).
  - [x] Implement `src/game/weapons.gd` (16-slot bullet pool, Normal, M, F, S, L, R, B, Bank 6 ballistics tables, solid wall impact ring tile `0x47`).
  - [x] Implement `src/game/collision.gd` (128-byte background collision grid `$0680-$06FF`, quadrant unpacking from 4x4 supertiles, 2-bit collision codes, Down+Jump drop-through scan).
  - [x] Implement `src/game/game_loop.gd` (60.0988 Hz fixed timestep coordinator, dual-nametable outdoor camera scrolling, 32-bit FNV-1a `get_state_hash()`).
  - [x] Create `src/main.tscn` and `src/main.gd` with 256x240 integer viewport, 48 kHz stereo audio via `AudioStreamGenerator`, multi-platform input handling (keyboard, gamepad, touch overlay), and fallback `FileDialog`.
  - [x] Add replay verification tests to `tests/test_gameplay_simulation.gd` (31/31 assertions passing, 180-frame state hash `0x811C9DC5`).

---

## 3. Subsequent Gameplay Milestones (Godot 4)

- [ ] **Milestone 6: Stage 1 (Jungle) & Enemies**
  - Soldier generation (`SOLDIER_GENERATION_ROUTINE` `$79`).
  - Red Turrets, Snipers, Flying Falcons, and Exploding Bridges.
  - Stage 1 Wall Defense Boss.
- [ ] **Milestone 7: Stages 2 & 4 (Base 1 & 2 3D Corridors)**
  - 3D perspective corridor movement, rolling grenades, and electric barriers.
  - Garma Kiru Defense Boss (Stage 2) and Godomuga Boss (Stage 4).
- [ ] **Milestone 8: Stage 3 (Waterfall Vertical Scroll)**
  - Vertical upward camera scrolling and tumbling boulders.
  - Gomeramos King Alien Boss.
- [ ] **Milestone 9: Stages 5–8 & Final Alien Boss**
  - Snow Field, Energy Zone, Hangar, Alien's Lair.
  - Emperor Demon Dragon God Java & Pulsing Alien Heart.
- [ ] **Milestone 10: 2P Co-Op, Konami Code & Final Polish**
  - 2-Player simultaneous co-op mode (Bill & Lance).
  - Konami Code 30-lives detector (`Up Up Down Down Left Right Left Right B A`).
  - High score persistence and attract demo playback.

---

## 4. Session Change Log

- **2026-11-23**: Reorganized repository architecture into modular layout standard for Godot engine projects:
  1. Relocated application source code under `src/` (`src/rom/`, `src/render/`, `src/audio/`, `src/game/`, `src/main.tscn`, `src/main.gd`), updating all `res://` resource paths and `project.godot` (`run/main_scene="res://src/main.tscn"`).
  2. Partitioned monolithic test suite into 6 single-responsibility test modules under `tests/` (`test_rom_loader.gd`, `test_chr_extractor.gd`, `test_level_loader.gd`, `test_ppu_renderer.gd`, `test_apu_sound.gd`, `test_gameplay_simulation.gd`) driven by unified runner `tests/run_headless_tests.gd` (and alias `tests/run_tests.gd`).
  3. Verified 100% test passage across all 187 assertions in headless mode.
- **2026-11-23**: Executed Step 5 of 5 for Godot 4 (GDScript) Clean-Room Migration:
  1. Implemented `scripts/game/collision.gd`: 128-byte background collision grid (`$0680-$06FF`), quadrant unpacking from 4x4 supertiles, 2-bit collision decoding (`EMPTY=0`, `FLOOR=1`, `WATER=2`, `SOLID=3`), and `can_drop_down()` scan.
  2. Implemented `scripts/game/player.gd`: 8-direction aim table resolution via Bank 7 `$D93A`, authentic jump kinematics (`-5.9375` px/frame initial impulse, `+0.1367` px/frame^2 gravity), Down+Jump floor bypass (12-frame timer), water surface swim and dive states, damage recoil arc, and Bank 1 `$B030` OAM sprite frame unpacking.
  3. Implemented `scripts/game/weapons.gd`: 16-slot bullet pool with Bank 6 dynamic table ingestion (19 tables at `$B55D-$BAE2`), Standard rifle (quota 4, 3 px/frame), Machine Gun `M` (quota 6, `m_fire_timer`), Fireball `F` (16-step circular swirl tables), Spread Gun `S` (5-way angled fan with distance scaling), Laser `L` (4 sequential segments with staggered delay timers), Rapid Fire `R` velocity upgrade, and solid wall impact ring tile `0x47`.
  4. Implemented `scripts/game/game_loop.gd`: 60.0988 Hz fixed-timestep runtime coordinating players, bullet pool, dual-nametable horizontal camera scrolling, PPU frame submission, and 32-bit FNV-1a deterministic state hashing (`get_state_hash()`).
  5. Implemented `scenes/main.tscn` and `scripts/main.gd`: 256x240 integer viewport presentation via `TextureRect`, 48 kHz stereo audio via `AudioStreamGeneratorPlayback`, multi-platform input gathering, touch control overlay, and fallback `FileDialog` ROM selection.
  6. Expanded `scripts/tests/run_headless_tests.gd` with 31 new assertions covering collision unpacking, 8-direction player aim resolution, jump parabola/gravity, bullet pool weapons (Normal, M, S, L, F), solid wall impact ring tile `0x47`, and 180-frame deterministic simulation replay verification (`0x811C9DC5`) across 187 passing assertions.
- **2026-11-23**: Reorganized project layout and aligned all Markdown documentation with Godot 4:
  1. Pruned empty legacy directories (`src/`), created clean directories (`scripts/game/`, `scenes/`).
  2. Updated `AGENTS.md`, `README.md`, and `docs/ARCHITECTURE.md` to reflect Godot 4.3+ GDScript architecture, `fish` shell `godot --headless` run/test commands, and clean-room ROM ingestion rules.
  3. Cleaned up `docs/STATUS.md` and `docs/MEMORY.md` into well-structured, concise, and conflict-free specifications.
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
