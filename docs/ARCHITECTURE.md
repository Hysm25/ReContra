# Technical Architecture (`docs/ARCHITECTURE.md`)

> **Project**: 100% Authentic Clean-Room Re-implementation of Contra (1988 NES, US Release)  
> **Tech Stack**: **Godot 4.3+ (GDScript)**  
> **Target**: Frame-accurate NTSC 60.0988 Hz simulation with zero committed copyrighted assets.

---

## 1. System Overview & Component Diagram

```
+-----------------------------------------------------------------------------------+
|                            Contra Godot 4 Architecture                            |
|                                                                                   |
|  +--------------------+      SHA-256 Check      +------------------------------+  |
|  | User Contra.nes    | ----------------------> | RomLoader (scripts/rom/)     |  |
|  | (128KB PRG, UNROM) |                         | (Banks 0-7, Bus Translation) |  |
|  +--------------------+                         +--------------+---------------+  |
|                                                                |                  |
|             +--------------------------------------------------+                  |
|             v                                                  v                  |
|  +--------------------------+                   +------------------------------+  |
|  | ChrExtractor             |                   | LevelLoader                  |  |
|  | (RLE 8KB CHR-RAM Engine) |                   | (Supertiles, Palettes, RLE)  |  |
|  +----------+---------------+                   +--------------+---------------+  |
|             |                                                  |                  |
|             +------------------------+-------------------------+                  |
|                                      v                                            |
|  +-----------------------------------------------------------------------------+  |
|  |                           Game Engine Core (scripts/game/)                  |  |
|  |  +---------------------+  +----------------------+  +--------------------+  |  |
|  |  | 60Hz State Machine  |  | Fixed-Point Physics  |  | Weapon & Bullet    |  |  |
|  |  | (GAME_ROUTINE $18)  |  | (Fast+Fract Accums)  |  | Pool (16 slots)    |  |  |
|  |  +----------+----------+  +----------+-----------+  +---------+----------+  |  |
|  |             |                        |                        |             |  |
|  |             v                        v                        v             |  |
|  |  +---------------------+  +----------------------+  +--------------------+  |  |
|  |  | Enemy Pool (16)     |  | Collision Grid       |  | PRNG Emulation     |  |  |
|  |  | (Routines, HP, Box) |  | (128B Terrain Map)   |  | ($34 Acc / Seeder) |  |  |
|  |  +---------------------+  +----------------------+  +--------------------+  |  |
|  +-------------------------------------+---------------------------------------+  |
|                                        |                                          |
|            +---------------------------+---------------------------+              |
|            |                                                       |              |
|            v                                                       v              |
|  +-----------------------------+               +-------------------------------+  |
|  | PpuRenderer (scripts/render)|               | ApuSynthesizer & SoundEngine  |  |
|  | (256x240 Software Framebuf, |               | (2A03 5-Ch + DPCM, 6 Slots,   |  |
|  |  OAM $4C Scanline Cycling,  |               |  Non-Linear Mixer & Filter,   |  |
|  |  Godot Image/ImageTexture)  |               |  AudioStreamGenerator Output) |  |
|  +--------------+--------------+               +---------------+---------------+  |
|                 |                                              |                  |
|                 +----------------------+-----------------------+                  |
|                                        v                                          |
|                       +---------------------------------+                         |
|                       | Input System & Replay Harness   |                         |
|                       | (Godot InputMap, Gamepad, Touch,|                         |
|                       |  Deterministic .replay Testing) |                         |
|                       +---------------------------------+                         |
+-----------------------------------------------------------------------------------+
```

---

## 2. ROM Loader & Asset Ingestion (`scripts/rom/`)

### 2.1 iNES & UNROM Mapper 2 Architecture (`scripts/rom/rom_loader.gd`)
Contra uses the NES **UNROM (Mapper 2)** board:
- **PRG ROM**: 128 KB (8 banks of 16 KB, `$4000` bytes each).
  - Banks 0–6 are switchable into CPU `$8000`–`$BFFF` via mapper writes.
  - Bank 7 is permanently fixed at CPU `$C000`–`$FFFF`.
- **CHR RAM**: 8 KB mapped to PPU `$0000`–`$1FFF`.
  - The cartridge contains no CHR ROM. All tile pattern graphics are stored RLE-compressed inside PRG ROM banks and decompressed into CHR RAM at runtime.
- **Mirroring**: Solder-pad configured for Vertical mirroring (Horizontal scrolling). Bank 7 software routines dynamically handle horizontal mirroring attributes for Stage 3 (Waterfall).
- **Cryptographic Guard**: On load, validates the ROM via SHA-256 (`8a6496924d54da80b72448ca33faec2c4a04d5ff645e54c8feefab7593c2a32c`) and CRC32 (`0x34EE3A27`).

### 2.2 Dynamic RLE CHR Extractor (`scripts/rom/chr_extractor.gd`)
Pattern graphics are compressed across Banks 4, 5, 6, and 7, referenced by pointer tables at `$C950` (27 graphic stream descriptors) and `$C8E3` (13 stage graphic sets):
- **Format**:
  - Command byte `$FF`: End of graphic data stream.
  - Command byte `$7F`: PPU destination address update (next 2 bytes = new PPU address).
  - Byte `< $7F`: Run-length repeated byte command (count = `byte`, followed by 1 data byte to repeat).
  - Byte `> $7F` (bit 7 set): Literal uncompressed byte stream (count = `byte & 0x7F`, followed by `count` data bytes).
- **Horizontal Flipping Support**: When loaded with flipping enabled, tiles are reversed bitwise across the horizontal axis (`reverse_bits_u8`) for mirrored base/indoor corridor tiles.

### 2.3 Level Loader & Supertiles (`scripts/rom/level_loader.gd`)
- **Headers**: 32-byte Level Headers in Bank 2 (`$B319`), specifying level type, scrolling mode, palette pointers, and supertile mappings.
- **Supertiles**: Bank 3 defines 4x4 tile matrices (32x32 pixels) along with tile palette attributes.
- **Palettes**: Bank 7 (`$D225`) contains 110 3-color palette sets converted to 2C02 NTSC master palette RGBA8 format.
- **Screen RLE Decompression**: Emulates Bank 7 3-case screen supertile decompressor (`< $80` literal, `$80..$EF` repeat, `>= $F0` row copy).

---

## 3. PPU & Visual Rendering Subsystem (`scripts/render/`)

### 3.1 Display Geometry & Framebuffer (`scripts/render/ppu_renderer.gd`)
- **Internal Resolution**: 256 x 240 pixels (8x8 pixel tiles, 32 x 30 tile matrix).
- **Framebuffer Format**: 32-bit RGBA8 `PackedByteArray` (245,760 bytes).
- **Aspect Ratio & Scaling**: Configured in `project.godot` with `window/stretch/mode="viewport"`, integer scaling (`window/stretch/scale_mode="integer"`), and nearest-neighbor texture filtering (`rendering/textures/canvas_textures/default_texture_filter=0`).
- **Engine Presentation**: Converts raw RGBA8 buffer to Godot `Image` (`Image.create_from_data`) and `ImageTexture` (`ImageTexture.create_from_image`) for zero-overhead canvas rendering.

### 3.2 Scrolling & Stage Projection Modes
1. **Horizontal Outdoor Mode (Stages 1, 5, 6, 7, 8)**:
   - Screen composed of 8x7 supertiles (32x32 pixels each).
   - Dual-nametable seamless horizontal scroll buffer populating `$2000` (NT0) / `$2400` (NT1) and attribute tables at `$23C0` / `$27C0`.
2. **Vertical Outdoor Mode (Stage 3 Waterfall)**:
   - Screen composed of 8x8 supertiles. Vertical upward scrolling driven by `VERTICAL_SCROLL` (`$FC`).
3. **3D Indoor / Base Mode (Stages 2, 4)**:
   - Perspective corridor rendering with fixed forward wall boundaries and advancing room depth (`INDOOR_SCROLL` `$73`).

### 3.3 Sprite OAM Engine & Priority Cycling
- **OAM Buffer**: 64 sprites x 4 bytes (`$0200`–`$02FF` OAMDMA buffer).
- **Sprite Dimensions**: 8x16 mode (`PPUCTRL` bit 5 set). Top tile is even pattern index, bottom tile is `index + 1`.
- **Hardware Priority Cycling ($4C Shift)**:
  - Authentic NES behavior: Every frame, shifts the OAM destination scanline evaluation by `$4C` bytes, authentically cycling drop-out when exceeding 8 sprites per scanline.
  - Option: Toggleable between **Authentic NES Sprite Flicker** ($4C cycling) and **Flicker-Free Mode** (`flicker_free_sprites = true`).

---

## 4. APU Audio Subsystem (`scripts/audio/`)

### 4.1 Ricoh 2A03 Emulation (`scripts/audio/apu_synthesizer.gd`)
- **Channels**:
  1. **Pulse 1**: Variable duty cycle (12.5%, 25%, 50%, 75%), volume envelope, hardware pitch sweep with authentic 1's complement negation quirk.
  2. **Pulse 2**: Companion square wave for harmonies and SFX with 2's complement negation.
  3. **Triangle**: 32-step pseudo-sine sequence, linear counter.
  4. **Noise**: 15-bit / 9-bit pseudo-random shift register (LFSR) with 16 NTSC periods.
  5. **DMC (DPCM)**: 1-bit delta modulation playback for Bank 7 (`$FC00`–`$FFCF`) percussion samples.
- **Non-Linear NES Mixer**: Authentic non-linear curve for Pulse and TND channels followed by first-order high-pass DC-blocking filter.
- **Audio Output**: Streams 48,000 Hz stereo `PackedVector2Array` frames into Godot's `AudioStreamGenerator`.

### 4.2 Contra 6-Slot Audio Command Architecture (`scripts/audio/sound_engine.gd`)
- **Slot Allocation**:
  - Slot 0: BGM Pulse 1
  - Slot 1: BGM Pulse 2
  - Slot 2: BGM Triangle
  - Slot 3: BGM Noise / DMC (Percussion)
  - Slot 4: SFX Pulse 1 (Priority override over Slot 0)
  - Slot 5: SFX Noise (Priority override over Slot 3)
- **Sound Codes**: Interprets bytecodes from Bank 1 (`$88E8`), handling duration multipliers, decrescendo pause states, vibrato controls, pulse volume envelopes (`$8001`), and note frequency periods (`$86D5`).
- **Flow Control**: Subroutine branching (`$FD`), repeat loop counters (`$FE`), and stream terminators (`$FF`).
- **DPCM Samples**: Maps Bank 1 `$88DB` sample descriptors to DMC hardware registers.

---

## 5. Game Engine Core (`scripts/game/`)

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
  ```gdscript
  func update_subpixel_pos(pos: int, accum: int, fract: int, fast: int) -> Array[int]:
      var sum: int = accum + fract
      var new_accum: int = sum & 0xFF
      var new_pos: int = pos + fast + (sum >> 8)
      return [new_pos, new_accum]
  ```
- **Player States (`PLAYER_STATE` `$90`)**:
  - Idle, Running, Ducking/Prone, Jumping (parabolic arc via `PLAYER_JUMP_COEFFICIENT`, `-5.9375` px/frame initial impulse, `+0.1367` px/frame^2 gravity), Swimming (water line clipping via `PLAYER_WATER_STATE`), Hit/Death recoil.
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

## 6. Input & Replay System (`scripts/game/`)

- **Controllers**: Godot `InputMap` integration with gamepad, keyboard, and touchscreen virtual overlay.
- **Turbo Support**: Hardware-accurate alternate-frame button pulsing (30 Hz turbo).
- **Deterministic `.replay` Engine**:
  - Encodes inputs per frame: `[uint32_t frame_index, uint8_t p1_mask, uint8_t p2_mask]`.
  - Enables 100% deterministic headless playback for automated speedrun verification and regression testing.
