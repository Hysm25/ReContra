# Implementation Roadmap & Status (`docs/STATUS.md`)

> **Active Implementation State**: Tracks current sprint milestone, implementation checklist, and verification status across development sessions.

---

## 1. Current Phase: Godot 4 Migration — Step 4 of 5 (2A03 APU Synthesizer & 6-Slot Audio Engine)

- **Phase Objective**: Migrate engine from C23/SDL3 to a clean-room Godot 4.3+ (GDScript) architecture.
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
- [ ] **Step 5: Physics, Player State Machine, Weapon Pools & Deterministic Replay Verification**
  - [ ] Implement `scripts/game/player.gd` (player state machine, aiming, parabolic jump, water diving, death recoil).
  - [ ] Implement `scripts/game/weapons.gd` (16-slot bullet pool, Normal, M, F, S, L, R, B).
  - [ ] Implement `scripts/game/collision.gd` (128-byte background collision grid and drop-through ledge timer).
  - [ ] Implement `scripts/game/game_loop.gd` (60.0988 Hz fixed timestep coordinator and camera scroller).
  - [ ] Add replay verification tests to `scripts/tests/run_headless_tests.gd`.

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
