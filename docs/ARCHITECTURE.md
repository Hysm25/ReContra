# Technical Architecture (`docs/ARCHITECTURE.md`)

> **Project**: 100% Authentic Clean-Room Re-implementation of Contra (1988 NES, US Release)  
> **Tech Stack**: C23 / C++20, SDL3, CMake, Ninja  
> **Target**: Frame-accurate NTSC 60.0988 Hz simulation with zero committed copyrighted assets.

---

## 1. System Overview & Component Diagram

```
+-----------------------------------------------------------------------------------+
|                              Contra SDL3 Architecture                             |
|                                                                                   |
|  +--------------------+      SHA-256 Check      +------------------------------+  |
|  | User Contra.nes    | ----------------------> | rom_loader & chr_extractor   |  |
|  | (128KB PRG, UNROM) |                         | (Banks 0-7, RLE Decompress)  |  |
|  +--------------------+                         +--------------+---------------+  |
|                                                                |                  |
|                                                                v                  |
|  +-------------------------------------------------------------+---------------+  |
|  |                              Game Engine Core                               |  |
|  |  +---------------------+  +----------------------+  +--------------------+  |  |
|  |  | 60Hz State Machine  |  | Fixed-Point Physics  |  | Weapon & Bullet    |  |  |
|  |  | (GAME_ROUTINE $18)  |  | (Fast+Fract Accums)  |  | Pool (16 slots)    |  |  |
|  |  +----------+----------+  +----------+-----------+  +---------+----------+  |  |
|  |             |                        |                        |             |  |
|  |             v                        v                        v             |  |
|  |  +---------------------+  +----------------------+  +--------------------+  |  |
|  |  | Enemy Pool (16)     |  | Nametable & Scroller |  | PRNG Emulation     |  |  |
|  |  | (Routines, HP, Box) |  | (Horizontal/Vert/3D) |  | ($34 Acc / Seeder) |  |  |
|  |  +---------------------+  +----------------------+  +--------------------+  |  |
|  +-------------------------------------+---------------------------------------+  |
|                                        |                                          |
|            +---------------------------+---------------------------+              |
|            |                                                       |              |
|            v                                                       v              |
|  +--------------------+                               +--------------------+      |
|  |   ppu_renderer     |                               |     apu_audio      |      |
|  | (256x240 Framebuf, |                               | (2A03 5-Ch + DPCM, |      |
|  |  OAM $4C Cycling,  |                               |  6 Sound Slots,    |      |
|  |  SDL3 Scaling/CRT) |                               |  SDL_AudioStream)  |      |
|  +---------+----------+                               +---------+----------+      |
|            |                                                       |              |
|            +---------------------------+---------------------------+              |
|                                        |                                          |
|                                        v                                          |
|                       +---------------------------------+                         |
|                       |          input_system           |                         |
|                       | (SDL_Gamepad, Keyboard, Turbo,  |                         |
|                       |  Deterministic .replay Harness) |                         |
|                       +---------------------------------+                         |
+-----------------------------------------------------------------------------------+
```

---

## 2. ROM Loader & Asset Ingestion (`src/rom/`)

### 2.1 iNES & UNROM Mapper 2 Architecture
Contra uses the NES **UNROM (Mapper 2)** board:
- **PRG ROM**: 128 KB (8 banks of 16 KB, `$4000` bytes each).
  - Banks 0–6 are switchable into CPU `$8000`–`$BFFF` via writes to `$8000`–`$FFFF`.
  - Bank 7 is permanently fixed at CPU `$C000`–`$FFFF`.
- **CHR RAM**: 8 KB mapped to PPU `$0000`–`$1FFF`.
  - The cartridge contains no CHR ROM. All tile pattern graphics are stored RLE-compressed inside PRG ROM banks and decompressed into CHR RAM at runtime.
- **Mirroring**: Solder-pad configured for Vertical mirroring (Horizontal scrolling). Bank 7 software routines dynamically handle horizontal mirroring attributes for Stage 3 (Waterfall).

### 2.2 Dynamic RLE CHR Extractor (`src/rom/chr_extractor.c`)
Pattern graphics are compressed in Banks 2, 4, 5, and 6:
- **Format**:
  - Command byte `$FF`: End of graphic data stream.
  - Command byte `$7F`: PPU address reposition command (next 2 bytes = new PPU destination address).
  - Byte `< $7F`: Run-length repeated byte command (count = `byte`, followed by 1 data byte to repeat).
  - Byte `> $7F` (with bit 7 set): Literal uncompressed byte stream (count = `byte & 0x7F`, followed by `count` data bytes).
- **Horizontal Flipping Support**: When loaded with flipping enabled, tiles are reversed bitwise across the horizontal axis for mirrored base/indoor corridor corridors.

---

## 3. PPU & Visual Rendering Subsystem (`src/render/`)

### 3.1 Display Geometry & Framebuffer
- **Internal Resolution**: 256 x 240 pixels (8x8 pixel tiles, 32 x 30 tile matrix).
- **Framebuffer Format**: 32-bit RGBA (`SDL_PIXELFORMAT_RGBA8888`).
- **Aspect Ratio & Scaling**: Integer scaling via `SDL_SetRenderLogicalPresentation(renderer, 256, 240, SDL_LOGICAL_PRESENTATION_INTEGER_SCALE)`. Nearest-neighbor filtering preserves clean pixel boundaries without blurring.

### 3.2 Scrolling & Stage Projection Modes
1. **Horizontal Outdoor Mode (Stages 1, 5, 6, 7, 8)**:
   - Screen composed of 8x7 supertiles (each supertile = 4x4 tiles = 32x32 pixels).
   - Dual-nametable seamless horizontal scroll buffer indexed by `LEVEL_SCREEN_SUPERTILES` (`$0600`).
2. **Vertical Outdoor Mode (Stage 3 Waterfall)**:
   - Screen composed of 8x8 supertiles. Vertical upward scrolling driven by `VERTICAL_SCROLL` (`$FC`).
3. **3D Indoor / Base Mode (Stages 2, 4)**:
   - Perspective corridor rendering with fixed forward wall boundaries and advancing room depth (`INDOOR_SCROLL` `$73`).

### 3.3 Sprite OAM Engine & Priority Cycling
- **OAM Buffer**: 64 sprites x 4 bytes (`$0200`–`$02FF` OAMDMA buffer).
- **Sprite Dimensions**: 8x16 mode (`PPUCTRL` bit 5 set). Top tile is even pattern index, bottom tile is `index + 1`.
- **Hardware Priority Cycling ($4C Shift)**:
  - Authentic NES behavior: Every frame, `draw_sprites` shifts the OAM destination address by `$4C` bytes, cycling which sprites drop out when exceeding 8 sprites per scanline.
  - Re-implementation option: Configurable toggle between **Authentic NES Sprite Flicker** ($4C cycling) and **Unlimited Sprite Mode** (flicker-free rendering).

---

## 4. APU Audio Subsystem (`src/audio/`)

### 4.1 Ricoh 2A03 Emulation
- **Channels**:
  1. **Pulse 1**: Variable duty cycle (12.5%, 25%, 50%, 75%), volume envelope, pitch sweep.
  2. **Pulse 2**: Companion square wave for harmonies and lead SFX.
  3. **Triangle**: 4-bit stepped pseudo-sine wave for bass lines.
  4. **Noise**: 15-bit / 9-bit pseudo-random shift register for percussion and explosions.
  5. **DMC (DPCM)**: 1-bit delta modulation playback for authentic digitized percussion.

### 4.2 Contra 6-Slot Audio Command Architecture
Cross-referenced against `Sound Documentation.md` and `ram.asm` (`$0100`–`$018F`):
- **Slot Allocation**:
  - Slot 0: BGM Pulse 1
  - Slot 1: BGM Pulse 2
  - Slot 2: BGM Triangle
  - Slot 3: BGM Noise / DMC
  - Slot 4: SFX Pulse 1 (Priority over Slot 0)
  - Slot 5: SFX Noise (Priority over Slot 3)
- **Sound Codes**: Interprets authentic bytecodes from Bank 1 (`$88F8`–`$AEAC`), handling duration multipliers, decrescendo pause states, vibrato controls, and note frequency lookups.
- **DPCM Samples**: Directly maps Bank 7 `$FC00`–`$FFCF` samples to DMC register `$4010`–`$4013`.
- **Audio Output**: 48,000 Hz, 32-bit float audio generated dynamically into an `SDL_AudioStream`.

---

## 5. Game Engine Core (`src/game/`)

### 5.1 Deterministic State Machine
Driven by `GAME_ROUTINE_INDEX` (`$18`):
- `0x00`: `game_routine_00` — Zero nametables, load intro graphics and palettes.
- `0x01`: `game_routine_01` — Logo scroll, menu cursor, Konami code check.
- `0x02`: `game_routine_02` — Demo timer wait / attract loop trigger.
- `0x03`: `game_routine_03` — Player start flash confirmation.
- `0x04`: `game_routine_04` — Memory wipe (`$0028`–`$00F0` and sprite buffers).
- `0x05`: `game_routine_05` — Active gameplay execution across 10 level sub-routines.
- `0x06`: `game_routine_06` — Game ending sequence and helicopter escape.

### 5.2 Physics & Mechanics
- **Fixed-Point Motion**:
  ```c
  void update_subpixel_pos(uint8_t* pos, uint8_t* accum, uint8_t fract, uint8_t fast) {
      uint16_t sum = *accum + fract;
      *accum = (uint8_t)(sum & 0xFF);
      *pos += fast + (uint8_t)(sum >> 8);
  }
  ```
- **Player States (`PLAYER_STATE` `$90`)**:
  - Idle, Running, Ducking/Prone, Jumping (parabolic arc via `PLAYER_JUMP_COEFFICIENT`), Swimming (water line clipping via `PLAYER_WATER_STATE`), Hit/Death recoil.
- **Weapon System**:
  - Standard (Rifle): 1 pellet on screen, fast straight.
  - `M` (Machine Gun): Rapid continuous stream.
  - `F` (Fireball): Swirling spiral trajectory using offset tables `f_bullet_outdoor_x/y_swirl_amt_tbl`.
  - `S` (Spread Gun): 5 bullets fanning out across 5 angles.
  - `L` (Laser): 4 connected beam segments moving in unison.
  - `R` (Rapid): Reduces delay between shots.
  - `B` (Barrier): Invincibility timer (`$B0`) with flashing palette cycling.

### 5.3 Pools & Collision Detection
- **Player Bullet Pool**: 16 dedicated slots (`$0368`–`$04B7`).
- **Enemy Object Pool**: 16 dedicated slots (`$04B8`–`$05F7`).
- **Collision Grid**: Supertile collision map (`BG_COLLISION_DATA` `$0680`–`$06FF`) evaluated every other tile. Floor drop-down executed with Down + Jump (`A`).

---

## 6. Input & Replay System (`src/input/`)

- **Controllers**: Full `SDL_Gamepad` support with automatic hotplugging and haptic rumble on damage.
- **Keyboard Mapping**: Fully configurable arrow/WASD + Z/X/Enter/Shift presets.
- **Turbo Support**: Hardware-accurate alternate-frame button pulsing (30 Hz turbo).
- **Deterministic `.replay` Engine**:
  - Encodes inputs per frame: `[uint32_t frame_index, uint8_t p1_mask, uint8_t p2_mask]`.
  - Allows 100% deterministic headless playback for automated speedrun verification and regression testing.
