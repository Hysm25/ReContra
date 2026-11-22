# ReContra

> **Clean-Room 1988 NES Contra Re-Implementation**  
> Built with **C23 / C++20**, **SDL3**, and **CMake / Ninja**.  
> **Target**: 100% authentic behavioral, physics, and audio-visual NTSC fidelity with zero committed copyrighted assets.

---

## Overview

**ReContra** is an independent, clean-room software re-implementation of the classic 1988 Nintendo Entertainment System (NES) game *Contra* (US release, Konami).

The goal of this project is a 100% faithful, frame-accurate simulation of the authentic NES hardware and gameplay mechanics:
- **Simulation Timing**: Exactly locked to NTSC NES master timing: 60.0988 Hz (16.6392 ms per tick).
- **Fixed-Point Physics**: Sub-pixel accumulation matching original NES logic bit-for-bit (`Fast` integer velocity plus `Fract` 0–255/256 accumulator).
- **Collision & Hitboxes**: Strictly implements the disassembly collision tables (`ENEMY_SCORE_COLLISION` `$0588`, `ENEMY_STATE_WIDTH` `$0598`, and supertile collision codes 0: empty, 1: floor, 2: water, 3: solid).
- **Audio Fidelity**: 5-channel 2A03 APU emulation (Pulse 1, Pulse 2, Triangle, Noise, DMC) reproducing Contra's 6-slot sound command engine (`$0100`–`$018F`) and authentic Bank 7 DPCM percussion samples (`$FC00`–`$FFCF`) fed through `SDL_AudioStream`.
- **Full Arsenal & Stages**: All weapons (`Normal`, Machine Gun `M`, Fireball `F`, Spread Gun `S`, Laser `L`, Rapid `R`, Barrier `B`), all 8 stages (horizontal, vertical, and 3D indoor base corridors), bosses, and 2-player simultaneous co-op.
- **Konami Code**: Authentic 10-input sequence (`Up Up Down Down Left Right Left Right B A`) granting 30 lives.

---

## Clean-Room Legal Boundary & Mandatory ROM Ingestion

1. **Zero Copyrighted Assets in Git**: Absolutely no proprietary ROM files (`.nes`), extracted binary dumps, pattern table dumps, or sound recordings are committed to version control.
2. **Dynamic Ingestion Pipeline**: All game assets (CHR pattern tables, palettes, supertiles, sound bytecodes, and DPCM samples) are ingested dynamically at runtime from a user-supplied authentic Contra NES ROM (`Contra (USA).nes` or `contra.nes`).
3. **Cryptographic Guard**: On startup, the engine validates the ROM via SHA-256 (`8a6496924d54da80b72448ca33faec2c4a04d5ff645e54c8feefab7593c2a32c`) and CRC32 (`0x34EE3A27`). If missing or invalid, the game halts and prompts the user.
4. **Reference Disassembly**: The local disassembly reference is strictly excluded from version control and used solely for reverse-engineering verification of authentic formulas, timings, and RAM maps.

---

## Documentation & Architecture

- **[AGENTS.md](AGENTS.md)**: Global execution blueprint, fish shell templates, hardware constraints (Sandy Bridge AVX-only, ARM64 PRoot), and EGM memory protocol.
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**: Modular system architecture (`rom_loader`, `chr_extractor`, `ppu_renderer`, `apu_audio`, `game_engine`, `input_system`).
- **[docs/STATUS.md](docs/STATUS.md)**: Phased implementation roadmap and active session checklist (Goldfish Protocol).
- **[docs/MEMORY.md](docs/MEMORY.md)**: Technical reference with verified UNROM bank mappings (Banks 0–7), NES RAM map (`$0000`–`$07FF`), velocity tables, and ADRs (Elephant Protocol).

---

## Quick Start & Build (`fish` Shell)

```fish
# 1. Configure & Build (CMake + Ninja)
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C build

# 2. Run Interactive Game
./build/contra

# 3. Headless Verification & Replay Testing
./build/contra --headless --frames 3600 --verify-hash
./build/contra --headless --replay tests/replays/stage1_clear.replay

# 4. Run Unit Test Suite
ctest --test-dir build --output-on-failure
```
