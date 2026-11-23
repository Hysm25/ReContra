# ReContra

> **Clean-Room 1988 NES Contra Re-Implementation**  
> Built with **Godot 4 (GDScript)**.  
> **Target**: 100% authentic behavioral, physics, and audio-visual NTSC fidelity with zero committed copyrighted assets.

---

## Overview

**ReContra** is an independent, clean-room software re-implementation of the classic 1988 Nintendo Entertainment System (NES) game *Contra* (US release, Konami).

The project achieves a 100% faithful, frame-accurate simulation of the authentic NES hardware and gameplay mechanics:
- **Simulation Timing**: Exactly locked to NTSC NES master timing: 60.0988 Hz (16.6392 ms per tick).
- **Fixed-Point Physics**: Sub-pixel accumulation matching original NES logic bit-for-bit (`Fast` integer velocity plus `Fract` 0–255/256 accumulator).
- **Collision & Hitboxes**: Strictly implements the disassembly collision tables (`ENEMY_SCORE_COLLISION` `$0588`, `ENEMY_STATE_WIDTH` `$0598`, and supertile collision codes 0: empty, 1: floor, 2: water, 3: solid).
- **2C02 PPU Software Rendering**: 256x240 integer-scaled viewport, nearest-neighbor texture filtering, 16 KB VRAM emulation, dual-nametable scrolling, 32-byte palette RAM mirror folding, and 64 8x16 OAM sprites with toggleable authentic cyclic `$4C` scanline limit vs flicker-free mode.
- **2A03 APU Audio Fidelity**: 5-channel APU emulation (Pulse 1, Pulse 2, Triangle, Noise, DMC) reproducing Contra's 6-slot sound command engine (`$0100`–`$018F`) and authentic Bank 7 DPCM percussion samples (`$FC00`–`$FFCF`) fed through Godot's `AudioStreamGenerator`.
- **Full Arsenal & Stages**: All weapons (`Normal`, Machine Gun `M`, Fireball `F`, Spread Gun `S`, Laser `L`, Rapid `R`, Barrier `B`), all 8 stages (horizontal, vertical, and 3D indoor base corridors), bosses, and 2-player co-op.
- **Konami Code**: Authentic 10-input sequence (`Up Up Down Down Left Right Left Right B A`) granting 30 lives.

---

## Clean-Room Legal Boundary & Mandatory ROM Ingestion

1. **Zero Copyrighted Assets in Git**: Absolutely no proprietary ROM files (`.nes`), extracted binary dumps, pattern table dumps, or sound recordings are committed to version control.
2. **Dynamic Ingestion Pipeline**: All game assets (CHR pattern tables, palettes, supertiles, sound bytecodes, and DPCM samples) are ingested dynamically at runtime from a user-supplied authentic Contra NES ROM (`Contra (USA).nes` or `contra.nes`) via `RomLoader`.
3. **Cryptographic Guard**: On startup, the engine validates the ROM via SHA-256 (`8a6496924d54da80b72448ca33faec2c4a04d5ff645e54c8feefab7593c2a32c`) and CRC32 (`0x34EE3A27`). If missing or invalid, the game halts and prompts the user cleanly.
4. **Reference Disassembly**: The local disassembly reference is strictly excluded from version control and used solely for reverse-engineering verification of authentic formulas, timings, and RAM maps.

---

## Repository Layout

```
ReContra/
├── project.godot                     # Godot 4 project configuration (256x240 integer viewport)
├── AGENTS.md                         # Autonomous agent execution blueprint & rules
├── README.md                         # Project overview, architecture, & quickstart
├── docs/
│   ├── ARCHITECTURE.md               # Technical architecture & subsystem design
│   ├── STATUS.md                     # Roadmap, sprint milestones, & verification checklist
│   └── MEMORY.md                     # Architectural decision records (ADR-001..ADR-019) & NES RAM map
├── scripts/
│   ├── rom/
│   │   ├── rom_loader.gd             # iNES header validator & UNROM Mapper 2 memory bus mapper
│   │   ├── chr_extractor.gd          # RLE CHR pattern table decompressor & bit reversal
│   │   └── level_loader.gd           # Level headers, supertiles, palettes, & screen decompressor
│   ├── render/
│   │   └── ppu_renderer.gd           # 2C02 PPU 256x240 framebuffer, dual-nametables & OAM sprites
│   ├── audio/
│   │   ├── apu_synthesizer.gd        # 2A03 APU 5-channel synthesizer & non-linear mixer
│   │   └── sound_engine.gd           # 6-slot audio command engine & bytecode sequencer
│   ├── game/                         # Physics, player state machine, weapons, & enemies
│   └── tests/
│       └── run_headless_tests.gd     # 156-assertion headless verification suite
└── scenes/                           # Godot scenes
```

---

## Quick Start & Verification (`fish` Shell)

```fish
# 1. Run Headless Verification Test Suite
set -gx GODOT_SILENCE_ROOT_WARNING 1
godot --headless --script scripts/tests/run_headless_tests.gd

# 2. Run Headless Verification with Explicit ROM Path
godot --headless --script scripts/tests/run_headless_tests.gd --rom /path/to/Contra.nes

# 3. Launch Interactive Game (Development / GUI)
godot --path .
```
