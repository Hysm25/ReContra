# Global Execution Blueprint (`AGENTS.md`)

> **Purpose**: Global operational blueprint and execution rules for AI agents across all sessions for the Contra (1988 NES) Godot 4 (GDScript) clean-room re-implementation.

---

## 1. Context Injections
- **User Profile & Environment**: [USER.md](file:///root/.gemini/antigravity-cli/brain/8340af84-b171-4a71-a44a-1f5b5d3cc80d/USER.md) (Global Rule)
- **Assistant Persona & Guardrails**: [SOUL.md](file:///root/.gemini/antigravity-cli/brain/8340af84-b171-4a71-a44a-1f5b5d3cc80d/SOUL.md) (Global Rule)
- **Persistent Technical Memory & ADRs**: [docs/MEMORY.md](file:///sdcard/Documents/Codes/ReContra/docs/MEMORY.md)
- **Architecture & System Design**: [docs/ARCHITECTURE.md](file:///sdcard/Documents/Codes/ReContra/docs/ARCHITECTURE.md)
- **Implementation Roadmap & Status**: [docs/STATUS.md](file:///sdcard/Documents/Codes/ReContra/docs/STATUS.md)

---

## 2. Universal Build & Run Templates (`fish` Shell)
> All interactive commands must be formatted for the `fish` shell.

```fish
# 1. Run Headless Verification Test Suite
set -gx GODOT_SILENCE_ROOT_WARNING 1
godot --headless --script tests/run_headless_tests.gd

# 2. Run Headless Verification with Explicit ROM Path
godot --headless --script tests/run_headless_tests.gd --rom /path/to/Contra.nes

# 3. Launch Interactive Game (Development / GUI)
godot --path .
```

---

## 3. Core Engineering Mandates

### 3.1 100% Behavioral & Audio-Visual Fidelity
- **Simulation Timing**: Exactly locked to NTSC NES master timing: 60.0988 Hz (16.6392 ms per tick). Never use variable delta-time for gameplay logic.
- **Fixed-Point Physics**: Match NES sub-pixel accumulation bit-for-bit: `Fast` integer velocity plus `Fract` (0–255 / 256) accumulator.
- **Hitboxes & Collisions**: Strictly implement the verified disassembly collision tables (`ENEMY_SCORE_COLLISION` `$0588`, `ENEMY_STATE_WIDTH` `$0598`, and supertile collision codes 0: empty, 1: floor, 2: water, 3: solid).
- **PRNG Fidelity**: Emulate the authentic NES Contra accumulator loop (`FRAME_COUNTER` + `RANDOM_NUM` at `$34`), with optional seedable deterministic PRNG for headless replay regression testing.
- **2A03 + DPCM Audio**: 5-channel APU simulation (Pulse 1, Pulse 2, Triangle, Noise, DMC) reproducing Contra's 6-slot sound command engine (`$0100`–`$018F`) and authentic Bank 7 DPCM percussion samples (`$FC00`–`$FFCF`) fed through Godot's `AudioStreamGenerator`.

### 3.2 Clean-Room Legal Boundary
- **Zero Committed Assets**: Absolutely no `.nes` ROM files, extracted binary dumps, pattern table dumps, or sound recordings may ever be committed to git.
- **Dynamic Ingestion Pipeline**: Assets (CHR pattern tables, palettes, supertiles, sound bytecode, DPCM samples) must be extracted dynamically at runtime from a user-supplied authentic Contra NES ROM (`Contra (USA).nes` or `contra.nes`) via `RomLoader`.
- **Cryptographic Guard**: On startup, validate the user ROM via SHA-256 (`8a6496924d54da80b72448ca33faec2c4a04d5ff645e54c8feefab7593c2a32c`) and CRC32 (`0x34EE3A27`). If missing or invalid, halt and prompt the user cleanly.

### 3.3 Modern Godot 4 & GDScript Conventions
- **Language Standards**: Godot 4.3+ GDScript with static typing (`class_name`, `extends RefCounted` / `Node2D`, typed variables, explicit return types).
- **Code Completeness**: Zero unchecked stubs, zero `TODO` placeholders, and fully realized production logic.
- **Architecture**: Domain logic and data processing implemented as modular `RefCounted` objects (`RomLoader`, `ChrExtractor`, `LevelLoader`, `PpuRenderer`, `ApuSynthesizer`, `SoundEngine`). Visual output rendered through a native 256x240 integer viewport and software framebuffer (`Image` / `ImageTexture`).

### 3.4 Hardware-Aware Portability
- **Desktop (OptiPlex 390 Sandy Bridge)**: AVX-only CPU (NO AVX2 / FMA3). Avoid binary extensions that trigger `SIGILL`.
- **Mobile (Fedora PRoot ARM64)**: Optimize for cache-locality, low memory consumption (<64MB RAM footprint), and zero dependency on systemd.

---

## 4. Repository Documentation & State Protocol

`docs/STATUS.md` and `docs/MEMORY.md` serve as the sole, self-contained project tracking and memory files within the repository. To ensure continuous, drift-free execution across autonomous sessions:

1. **Long-Term Memory (`docs/MEMORY.md`)**:
   - Persists long-term, immutable architectural decision records (ADRs), verified NES RAM addresses, UNROM bank layouts, disassembly formulas, and hardware quirks.
   - Any newly verified hardware symbol, register behavior, or architectural decision must be appended to `docs/MEMORY.md` immediately.

2. **Active Milestone Tracking (`docs/STATUS.md`)**:
   - Manages active session sprint milestones, technical task checklists, and verification results.
   - Every development session begins by reading `docs/STATUS.md` and `docs/MEMORY.md` to identify the current milestone and constraints.
   - Before completing work, the agent must update `docs/STATUS.md` with completed checklist items, session change logs, and current build/test verification status.
