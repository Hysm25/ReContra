# Implementation Roadmap & Status (`docs/STATUS.md`)

> **Active Session State (Goldfish Protocol)**: Tracks current sprint milestone, implementation checklist, and verification status across development sessions.

---

## 1. Current Phase: Phase 2 — PPU 256x240 Renderer & OAM Sprite Engine

- **Phase Objective**: Implement 256x240 software framebuffer renderer, background nametable decoding, scrolling engine, and 8x16 OAM sprite engine.
- **Current Milestone**: Phase 2.1 — Framebuffer & Nametable Renderer (READY).
- **Status**: Phase 0 (Build & Harness) and Phase 1 (ROM Loader & CHR RLE Decompressor) COMPLETED & 100% CTest Verified.

---

## 2. Phased Implementation Roadmap

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
- [ ] Implement 256x240 32-bit RGBA native framebuffer.
- [ ] Implement SDL3 integer-scaled rendering with nearest-neighbor texture filtering.
- [ ] Build Nametable background renderer:
  - Supertile matrix decoder (4x4 tiles per supertile).
  - Horizontal scrolling engine (Stages 1, 5, 6, 7, 8).
  - Vertical scrolling engine (Stage 3 Waterfall).
  - 3D perspective corridor renderer (Stages 2, 4 Base levels).
- [ ] Build 64-sprite OAM engine (`$0200`–`$02FF`):
  - 8x16 sprite composition.
  - Horizontal and vertical flipping.
  - Priority bit masking (behind background).
  - Authentic `$4C` offset frame priority cycling with optional flicker-free toggle.

### Phase 3: 2A03 APU Synthesizer & DPCM Audio (`src/audio/`)
- [ ] Implement Ricoh 2A03 5-channel sound synthesis (Pulse 1, Pulse 2, Triangle, Noise, DMC).
- [ ] Implement Contra 6-slot audio command engine (`$0100`–`$018F`):
  - Slot priorities and channel routing.
  - Bytecode parser for BGM tracks and SFX commands.
  - Envelope timers, decrescendo pauses, vibrato logic.
- [ ] Implement Bank 7 DPCM sample decoder (`$FC00`–`$FFCF`) for percussion beats and explosions.
- [ ] Stream synthesized audio via `SDL_AudioStream` (48 kHz 32-bit float).

### Phase 4: Core Gameplay Physics, Player State & Controls (`src/game/`)
- [ ] Implement deterministic 60.0988 Hz fixed-timestep game loop (`GAME_ROUTINE_INDEX` `$18`).
- [ ] Implement sub-pixel fixed-point physics (`Fast` + `Fract` accumulators).
- [ ] Build Player State Machine (`PLAYER_STATE` `$90`):
  - 8-direction aiming (`PLAYER_AIM_DIR` `$C2`).
  - Running, ducking, prone crawling, jumping arc (`PLAYER_JUMP_COEFFICIENT`).
  - Water mechanics (swimming and submerged diving via `PLAYER_WATER_STATE`).
  - Hit recoil, death animation, invincibility respawn timer.
- [ ] Implement background collision checks (`BG_COLLISION_DATA` `$0680`–`$06FF`):
  - Floor landing and drop-down (Down + Jump).
  - Water tiles and solid wall barriers.

### Phase 5: Weapon System & Bullet Pool (`src/game/weapons/`)
- [ ] Implement 16-slot Player Bullet Pool (`$0368`–`$04B7`).
- [ ] Implement Standard Rifle weapon.
- [ ] Implement `M` (Machine Gun) rapid-fire weapon.
- [ ] Implement `F` (Fireball) swirling trajectory weapon with authentic offset lookup tables.
- [ ] Implement `S` (Spread Gun) 5-way angled bullet fan.
- [ ] Implement `L` (Laser Gun) 4-segment continuous destructive beam.
- [ ] Implement `R` (Rapid Fire) upgrade modifier.
- [ ] Implement `B` (Barrier / Falcon) invincibility power-up.

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
- [ ] Validate compilation and test pass on EndeavourOS Sandy Bridge (AVX-only, `-mno-avx2`).
- [ ] Validate compilation and headless test pass inside Fedora PRoot ARM64.
- [ ] Package standalone desktop release with desktop entry and assets extractor.

---

## 3. Session Change Log
- **2026-11-23**: Completed Phase 0 & Phase 1: implemented CMake build system, C23 crypto primitives (SHA-256, CRC-32), UNROM Mapper 2 ROM loader, Bank 7 dynamic RLE CHR tile decompressor, Bank 2/3 level header and supertile parsers, 2C02 NTSC RGBA palette mapping, headless CLI deterministic test harness, and 100% passing automated unit test suite.
- **2026-11-22**: Initialized clean-room project documentation foundation tailored to `nes-contra-us` disassembly symbols, RAM addresses, UNROM bank layouts, and SDL3 architecture.
