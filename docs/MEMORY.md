# Persistent Disassembly Memory & ADRs (`docs/MEMORY.md`)

> **Long-Term Memory (Elephant Protocol)**: Persists verified Contra NES disassembly memory maps, UNROM bank layouts, mathematical constants, and Architectural Decision Records (ADRs).

---

## 1. UNROM (Mapper 2) PRG ROM Bank Layout

Contra (US) is built on the UNROM board with 128 KB PRG ROM (8 banks of 16 KB) and 8 KB CHR RAM:

| Bank | ROM File Offset | CPU Address | Content / Disassembly Source | Key Labels & Routines |
| :--- | :--- | :--- | :--- | :--- |
| **Bank 0** | `$00010`–`$03D7A` | `$8000`–`$BD7A` | Enemy Logic & AI Routines (`bank0.asm`) | `exe_enemy_routine`, `aim_and_create_enemy_bullet` |
| **Bank 1** | `$04010`–`$07DF4` | `$8000`–`$BDF4` | Sound Engine & Encoded Sprites (`bank1.asm`) | `sound_init`, `play_sound`, `draw_sprites`, `sprite_ptr_tbl` |
| **Bank 2** | `$08010`–`$0BD4B` | `$8000`–`$BD4B` | Screen Supertiles, CHR Data, Player State (`bank2.asm`) | `level_supertiles_screen_ptr_table`, `player_state_routine` |
| **Bank 3** | `$0C010`–`$0FFBE` | `$8000`–`$BFBE` | Supertile Definitions & Palettes (`bank3.asm`) | `level_supertile_data`, `end_level_routine` |
| **Bank 4** | `$10010`–`$13DD0` | `$8000`–`$BDD0` | Compressed CHR Graphics & Ending Credits (`bank4.asm`) | `graphic_data_01/03/04/06/08/09/0a/0f/10/11/12/13` |
| **Bank 5** | `$14010`–`$17643` | `$8000`–`$B643` | Compressed CHR Graphics & Demo Inputs (`bank5.asm`) | `graphic_data_05/07/0b/14/17/18/19/1a`, `demo_input_table` |
| **Bank 6** | `$18010`–`$1BD35` | `$8000`–`$BD35` | Compressed CHR Graphics & Weapons Logic (`bank6.asm`) | `fire_weapon_routine_ptr_tbl`, `run_player_bullet_routines` |
| **Bank 7** | `$1C010`–`$1FFFF` | `$C000`–`$FFFF` | **Fixed Bank**: Game Engine Core & Vectors (`bank7.asm`) | `nmi_start`, `game_loop`, `load_level_graphic_data`, DPCM (`$FC00`) |

---

## 2. NES CPU Memory Map ($0000–$07FF) Cross-Reference

Cross-referenced directly against `nes-contra-us/src/ram.asm` and `constants.asm`:

### 2.1 Zero Page ($0000–$00FF)
- `$18`: `GAME_ROUTINE_INDEX` — Major game state lock (0: Intro, 1: Title/Konami, 2: Demo wait, 3: Start flash, 4: Clear RAM, 5: Level, 6: Ending).
- `$1A`: `FRAME_COUNTER` — Increments every NMI vertical blanking interrupt.
- `$1C`: `DEMO_MODE` — 1 if game is running in attract demo mode.
- `$22`: `PLAYER_MODE` — 0 = 1 Player, 1 = 2 Players.
- `$24`: `KONAMI_CODE_STATUS` — Set to 1 upon entering full 10-input Konami Code.
- `$25`: `PAUSE_STATE` — 1 if paused (freezes gameplay updates).
- `$2C`: `LEVEL_ROUTINE_INDEX` — Sub-routine index for the active level (0..9).
- `$30`: `CURRENT_LEVEL` — 0 = Jungle, 1 = Base 1, 2 = Waterfall, 3 = Base 2, 4 = Snow Field, 5 = Energy Zone, 6 = Hangar, 7 = Alien's Lair.
- `$31`: `GAME_COMPLETION_COUNT` — Tracks loop number (increments after beating game).
- `$32`: `P1_NUM_LIVES`, `$33`: `P2_NUM_LIVES` — Active player lives (Default: 3, Konami Code: 30).
- `$34`: `RANDOM_NUM` — PRNG accumulator continuously updated in CPU wait loop (`FRAME_COUNTER + RANDOM_NUM`).
- `$40`: `LEVEL_LOCATION_TYPE` — 0 = Outdoor (scrolling), 1 = Indoor (3D Base).
- `$41`: `LEVEL_SCROLLING_TYPE` — 0 = Horizontal scrolling, 1 = Vertical scrolling.
- `$42`–`$43`: `LEVEL_SCREEN_SUPERTILES_PTR` — Pointer to supertile index assignments for screens.
- `$44`–`$45`: `LEVEL_SUPERTILE_DATA_PTR` — Pointer to 4x4 tile makeup of level supertiles.
- `$49`–`$4B`: Collision index boundaries (`COLLISION_CODE_1/0/2_TILE_INDEX`).
- `$64`: `LEVEL_SCREEN_NUMBER` — Active screen index within the stage.
- `$65`: `LEVEL_SCREEN_SCROLL_OFFSET` — Pixel scroll position within active screen.
- `$68`: `FRAME_SCROLL` — Screen scroll delta for the current frame.
- `$90`: `PLAYER_STATE` (P1 `$90`, P2 `$91`) — Idle, Run, Prone, Jump, Swim, Death.
- `$94`: `PLAYER_JUMP_COEFFICIENT` — Parabolic jump physics multiplier.
- `$98`: `PLAYER_X_VELOCITY` — Horizontal player velocity.
- `$A0`: `PLAYER_JUMP_STATUS` — 0 = On ground, 1 = Airborne jumping.
- `$AA`: `P1_CURRENT_WEAPON`, `$AB`: `P2_CURRENT_WEAPON` — Low nibble: weapon type (0=Std, 1=M, 2=F, 3=S, 4=L); Bit 7: Rapid Fire (R) upgrade.
- `$B0`: `INVINCIBILITY_TIMER` — Barrier/power-up invincibility timer.
- `$B2`: `PLAYER_WATER_STATE` — 0 = Dry land, 1 = Swimming at surface, 2 = Submerged.
- `$C2`: `PLAYER_AIM_DIR` — 8-direction aim index (0: Right, 1: Down-Right, 2: Down, 3: Down-Left, 4: Left, 5: Up-Left, 6: Up, 7: Up-Right).
- `$C4`: `PLAYER_Y_FRACT_VELOCITY`, `$C6`: `PLAYER_Y_FAST_VELOCITY` — Sub-pixel vertical velocity.
- `$F1`–`$F2`: `CONTROLLER_STATE` — Current joypad bitmask (P1, P2).
- `$F5`–`$F6`: `CONTROLLER_STATE_DIFF` — Newly pressed buttons this frame.
- `$FC`: `VERTICAL_SCROLL`, `$FD`: `HORIZONTAL_SCROLL` — PPU scroll registers.

### 2.2 Sound Engine Buffers ($0100–$018F)
- `$0100`–`$0105`: `SOUND_CMD_LENGTH` — Remaining duration in frames for the 6 sound slots.
- `$0106`–`$010B`: `SOUND_CODE` — Sound effect or music track code for each slot.
- `$010C`–`$0111`: `SOUND_PULSE_LENGTH` — Pulse channel duration.
- `$0112`–`$011D`: `SOUND_CMD_LOW/HIGH_ADDR` — 16-bit pointers to current sound bytecode streams.
- `$0120`: `SOUND_CURRENT_SLOT` — Active parsing slot (0: Pulse 1, 1: Pulse 2, 2: Triangle, 3: Noise/DMC, 4: Pulse 1 SFX, 5: Noise SFX).
- `$0124`–`$0129`: `SOUND_FLAGS` — Slot flags (Bit 6: Mute, Bit 7: Sweep).
- `$0148`–`$014D`: `SOUND_REPEAT_COUNT` — Loop counter for sound command parts (`#$FE`).
- `$0160`–`$0165`: `PULSE_VOLUME` — Volume level for pulse channels.
- `$0178`–`$0179`: `VIBRATO_CTRL` — Pitch modulation mode.

### 2.3 OAM DMA Sprite Buffer ($0200–$02FF)
- 256 bytes copied to NES PPU OAM via DMA every VBlank. 64 sprites x 4 bytes: `[Y_Pos, Tile_Index, Attributes, X_Pos]`.

### 2.4 Sprite CPU Buffer ($0300–$0367)
- `$0300`–`$0309`: `PLAYER_SPRITES` — 10 bytes: P1, P2, and bullet sprite codes.
- `$030A`–`$0319`: `ENEMY_SPRITES` — 16 bytes: 16 active enemy sprite codes.
- `$031A`–`$0323`: `SPRITE_Y_POS` (10 bytes).
- `$0324`–`$0333`: `ENEMY_Y_POS` (16 bytes).
- `$0334`–`$033D`: `SPRITE_X_POS` (10 bytes).
- `$033E`–`$034D`: `ENEMY_X_POS` (16 bytes).
- `$034E`–`$0357`: `SPRITE_ATTR` (10 bytes).
- `$0358`–`$0367`: `ENEMY_SPRITE_ATTR` (16 bytes).

### 2.5 Player Bullet Pool ($0368–$04B7) — 16 Slots
- `$0368`: `PLAYER_BULLET_SPRITE_CODE` (16 bytes).
- `$0378`: `PLAYER_BULLET_SPRITE_ATTR` (16 bytes).
- `$0388`: `PLAYER_BULLET_SLOT` (16 bytes) — 0 = empty, 1 = Normal, 2 = M, 3 = F, 4 = S, 5 = L.
- `$0398`: `PLAYER_BULLET_Y_VEL_ACCUM`, `$03A8`: `PLAYER_BULLET_X_VEL_ACCUM` (16 bytes each).
- `$03B8`: `PLAYER_BULLET_Y_POS`, `$03C8`: `PLAYER_BULLET_X_POS` (16 bytes each).
- `$03D8`: `PLAYER_BULLET_Y_VEL_FRACT`, `$03E8`: `PLAYER_BULLET_X_VEL_FRACT` (16 bytes each).
- `$03F8`: `PLAYER_BULLET_Y_VEL_FAST`, `$0408`: `PLAYER_BULLET_X_VEL_FAST` (16 bytes each).
- `$0418`: `PLAYER_BULLET_TIMER` (16 bytes) — F swirl step, indoor S scale, L spread delay.
- `$0428`: `PLAYER_BULLET_AIM_DIR` (16 bytes).
- `$0438`: `PLAYER_BULLET_ROUTINE` (16 bytes).
- `$0448`: `PLAYER_BULLET_OWNER` (16 bytes) — 0 = Player 1, 1 = Player 2.
- `$0458`: `PLAYER_BULLET_F_RAPID` / `S_INDOOR_ADJ` (16 bytes).
- `$0468`: `PLAYER_BULLET_DIST` (16 bytes).
- `$0478`: `PLAYER_BULLET_FS_X` (16 bytes) — Center X swirl position for F weapon.
- `$0488`: `PLAYER_BULLET_F_Y` (16 bytes) — Center Y swirl position for F weapon.
- `$0498`: `PLAYER_BULLET_VEL_FS_X_ACCUM`, `$04A8`: `PLAYER_BULLET_VEL_F_Y_ACCUM` (16 bytes each).

### 2.6 Enemy Pool ($04B8–$05F7) — 16 Slots
- `$04B8`: `ENEMY_ROUTINE` (16 bytes) — Routine index dispatch into `enemy_routine_ptr_tbl`.
- `$04C8`: `ENEMY_Y_VEL_ACCUM`, `$04D8`: `ENEMY_X_VEL_ACCUM` (16 bytes each).
- `$04E8`: `ENEMY_Y_VELOCITY_FAST`, `$04F8`: `ENEMY_Y_VELOCITY_FRACT` (16 bytes each).
- `$0508`: `ENEMY_X_VELOCITY_FAST`, `$0518`: `ENEMY_X_VELOCITY_FRACT` (16 bytes each).
- `$0528`: `ENEMY_TYPE` (16 bytes) — Enemy classification index.
- `$0538`: `ENEMY_ANIMATION_DELAY` (16 bytes).
- `$0548`: `ENEMY_VAR_A` (16 bytes) — Hit SFX code / position adjustments.
- `$0558`: `ENEMY_ATTACK_DELAY` / `ENEMY_VAR_B` (16 bytes) — Trajectory arc / attack timer.
- `$0568`: `ENEMY_FRAME` (16 bytes) — Animation frame index into sprite tables.
- `$0578`: `ENEMY_HP` (16 bytes) — Hit points remaining.
- `$0588`: `ENEMY_SCORE_COLLISION` (16 bytes) — Score value, hitbox type, and explosion type.
- `$0598`: `ENEMY_STATE_WIDTH` (16 bytes) — Bit 7: Pass-through bullets; Bit 6: Can land on enemy; Bits 4–5: Box code; Bit 0: Skip player collision.
- `$05A8`: `ENEMY_ATTRIBUTES` (16 bytes).
- `$05B8`–`$05E8`: `ENEMY_VAR_1` through `ENEMY_VAR_4` (16 bytes each).

### 2.7 Nametable, Buffers & Scores ($0600–$07ED)
- `$0600`–`$067F`: `LEVEL_SCREEN_SUPERTILES` (128 bytes) — 2 screens of active supertile indices.
- `$0680`–`$06FF`: `BG_COLLISION_DATA` (128 bytes) — 2 bits per collision point:
  - `0`: Empty (passable).
  - `1`: Floor (can land, drop through with Down + A).
  - `2`: Water (half-submerged, disables jumping).
  - `3`: Solid barrier (impassable).
- `$0700`–`$07BF`: `CPU_GRAPHICS_BUFFER` — Staging buffer for VRAM transfers.
- `$07C0`–`$07DF`: `PALETTE_CPU_BUFFER` (32 bytes) — 16 background + 16 sprite NES palette entries.
- `$07E0`–`$07E1`: `HIGH_SCORE_LOW/HIGH`.
- `$07E2`–`$07E3`: `PLAYER_1_SCORE_LOW/HIGH`.
- `$07E4`–`$07E5`: `PLAYER_2_SCORE_LOW/HIGH`.
- `$07EC`: `PREVIOUS_ROM_BANK`, `$07ED`: `PREVIOUS_ROM_BANK_1`.

---

## 3. Mathematical Constants & Angle Lookups

### 3.1 Bullet Fractional Velocity Table (`bullet_fract_vel_tbl`)
Derived from disassembly Bank 6 / Bank 0 for 24-direction aiming:
| Angle off Axis | X Velocity Fraction | Y Velocity Fraction | Floating Equivalent (X / Y) |
| :--- | :--- | :--- | :--- |
| **0°** | `$FF` | `$00` | 0.9961 / 0.0000 |
| **15°** | `$F7` | `$42` | 0.9648 / 0.2578 |
| **30°** | `$DD` | `$80` | 0.8633 / 0.5000 |
| **45°** | `$B5` | `$B5` | 0.7070 / 0.7070 |
| **60°** | `$80` | `$DD` | 0.5000 / 0.8633 |
| **75°** | `$42` | `$F7` | 0.2578 / 0.9648 |
| **90°** | `$00` | `$FF` | 0.0000 / 0.9961 |

### 3.2 Konami Code Sequence
`konami_code_lookup_table`: `$08, $08, $04, $04, $02, $01, $02, $01, $40, $80`  
- Order: Up, Up, Down, Down, Left, Right, Left, Right, B, A (Length: 10).
- Bitmask: `Up=0x08, Down=0x04, Left=0x02, Right=0x01, B=0x40, A=0x80`. Filtered with `and #$CF` (ignores Start/Select during entry).

---

## 4. Architectural Decision Records (ADRs)

### ADR-001: Clean-Room Dynamic ROM Ingestion
- **Context**: Distributing proprietary Nintendo / Konami ROMs or extracted graphics/sound violates copyright.
- **Decision**: The repository will contain zero `.nes` ROMs or extracted binary dumps. All assets (CHR tiles, palettes, sound bytecodes, DPCM samples) are ingested dynamically at runtime/build-time from a user-supplied ROM verified via SHA-256 (`8a6496924d54da80b72448ca33faec2c4a04d5ff645e54c8feefab7593c2a32c`).

### ADR-002: Modern C23 / C++20 and SDL3 Stack
- **Context**: Ensure low memory footprint, high portability across Linux desktop and Android PRoot, and modern audio-video stream management.
- **Decision**: Use C23 for core decompresors/loaders and C++20 for engine subsystems. Use SDL3 for windowing, hardware-accelerated integer scaling, `SDL_AudioStream`, and `SDL_Gamepad`.

### ADR-003: Fixed-Timestep NTSC 60.0988 Hz Simulation
- **Context**: Variable delta-time introduces physics drift, bullet desynchronization, and non-deterministic replays.
- **Decision**: All physics, timers, bullet trajectories, and enemy routines execute on a strict 60.0988 Hz fixed timestep (`16.6392 ms` per tick).

### ADR-004: Hardware Constraints (AVX-Only Desktop & ARM64 Mobile)
- **Context**: OptiPlex 390 (Core i5-2400) lacks AVX2/FMA3. Mobile node runs in Fedora PRoot ARM64.
- **Decision**: Force `-mno-avx2` / `-march=sandybridge` in CMake configurations. Keep memory overhead below 64MB.

### ADR-005: Deterministic Headless Replay Harness
- **Context**: Regression testing and behavioral verification require fast automated validation without manual playthroughs.
- **Decision**: Implement a headless CLI replay harness (`--headless --replay <file> --verify-hash`) logging frame-by-frame state hashes.

### ADR-006: Android PRoot `noexec` Execution Handling
- **Context**: Mobile dev node runs under Termux PRoot with workspace in `/sdcard`, which is an emulated Android FUSE mount enforcing `noexec`. Executing binaries directly from the build directory triggers `EACCES`.
- **Decision**: Provide `scripts/test_runner.py` that transparently detects `noexec` file systems and stages binaries in `/tmp` before execution, ensuring `ctest` runs with 100% pass rate in all PRoot and container environments.

### ADR-007: Runtime Dynamic Hardware Pointer Ingestion
- **Context**: Strictly adhere to clean-room legal boundary and zero hardcoded data tables.
- **Decision**: All graphics pointers, level layouts, palettes, and supertile mappings are resolved dynamically at runtime by querying PRG Bank 7 (`$C950`, `$C8E3`, `$D225`) and PRG Bank 2 (`$B319`), preventing hardcoded asset data in engine source. Verified authentic ROM hashes: Headered SHA-256 `26541a5550ee22deeb3d5484e4a96130219b58cff74d068fb1eb6567fa5e5519` (CRC-32 `0xC50A8304`), PRG SHA-256 `d41e28b1a33b3b6768e7c39c9fdfb1fda4b49940542d14085911fabd399e1ca9` (CRC-32 `0xF6035030`).

### ADR-008: 2C02 PPU Software Rasterizer & 8x16 OAM Sprite Architecture
- **Context**: Ensure pixel-perfect, frame-accurate rendering matching authentic NES hardware without relying on full PPU cycle-by-cycle overhead.
- **Decision**: Implemented high-performance scanline-based software rasterizer outputting 256x240 RGBA8888. Supports Vertical and Horizontal nametable mirroring, 4x4 supertile matrix unpacking, 32-byte internal Palette RAM with mirror folding, and full 8x16 OAM sprite rendering (`[Y, Tile, Attr, X]`) with vertical/horizontal flipping and background priority masking. Features a user-configurable toggle between authentic NES 8-sprite per scanline limit (with frame-by-frame `$4C` cyclic priority offset shifting) and modern flicker-free rendering.

### ADR-009: Ricoh 2A03 5-Channel Sound Synthesizer & 6-Slot Command Engine
- **Context**: Authentic 8-bit sound synthesis reproducing BGM tracks, digitized DPCM percussion samples, and sound effects with slot priority arbitration and zero committed audio assets.
- **Decision**: Implemented modular Ricoh 2A03 software APU synthesizer featuring Pulse 1 & Pulse 2 with 4-step duty cycle sequencer and sweep unit, 32-step Triangle generator, 15-bit/9-bit LFSR pseudo-random Noise generator, and 1-bit DMC delta modulation channel with 48,000 Hz float output and DC-blocking filter. Implemented authentic 6-slot command engine reading sound bytecode streams dynamically from Bank 1 (`$88E8`, `$88DB`, `$82CD`, `$8001`, `$86D5`) and streaming DPCM digitized samples from Bank 7 (`$FC00`–`$FFCF`). Enforced authentic slot priority arbitration where SFX Pulse 1 (Slot 4) overrides BGM Pulse 1 (Slot 0), and SFX Noise (Slot 5) overrides BGM Noise (Slot 3). Headless simulation hash updated to `0x9C8A7224`.
