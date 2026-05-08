# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Context

This is a **FrogPilot** fork of openpilot, based on **openpilot 0.9.7**. It's being used for a retrofit research project: adapting openpilot to a stripped 2005 Toyota Corolla/Matrix using 2016 Corolla EPS and ADAS components, a Comma 3, Comma Pedal, and two Ocelot devices.

Key FrogPilot value: the newer tinygrad-based driving model (split vision/policy architecture) is backported to run on C3 hardware, which stock openpilot no longer supports.

Car fingerprint target: `TOYOTA COROLLA` (2016 non-TSS2).

## Build

```bash
# Full build
scons -u -j$(nproc)

# On-device, the manager handles building automatically via:
# system/manager/build.py → scons
```

SCons expects ~2820 nodes. Build cache lives at `/tmp/scons_cache` (or `/data/scons_cache` on device). Incremental builds use MD5-timestamp checking.

## Dev Environment Setup (macOS)

```bash
tools/mac_setup.sh        # Installs brew deps, pyenv, Qt5, Python env
tools/install_python_dependencies.sh  # Poetry-based Python deps
```

There is no `op.sh` on the stable branch. The devcontainer (`.devcontainer/`) is the officially recommended approach for non-Ubuntu systems.

Python version: 3.11. Dependency management: Poetry (`pyproject.toml` + `poetry.lock`).

## Tests

```bash
# Run all tests
pytest

# Run a single test file
pytest selfdrive/car/toyota/tests/test_toyota.py

# Run a specific test
pytest selfdrive/car/toyota/tests/test_toyota.py::TestToyota::test_name -x

# Parallel execution (uses xdist)
pytest -n auto
```

pytest config is in `pyproject.toml`. Markers: `slow`, `tici` (device-only tests, auto-skipped off-device).

## Linting

```bash
# Python (ruff)
ruff check .
ruff format .

# Type checking
mypy selfdrive/

# Pre-commit (runs ruff, cppcheck, cpplint, codespell, mypy)
pre-commit run --all-files
```

Ruff config: line length 160, Python 3.11 target. Excludes third-party repos (panda, opendbc, tinygrad_repo, etc.).

## Architecture

### Process Model
openpilot runs as a set of communicating processes managed by `system/manager/manager.py`. Processes exchange messages via `cereal` (Cap'n Proto) over `msgq` (ZMQ-based IPC).

Launch chain: `launch_openpilot.sh` → `launch_chffrplus.sh` → `system/manager/build.py` → `system/manager/manager.py`

### Key Directories

- **`selfdrive/car/`** — Car interface layer. Each brand (toyota/, honda/, etc.) has:
  - `interface.py` — `CarInterface`: params, safety config, fingerprinting
  - `carstate.py` — CAN → `CarState` parsing
  - `carcontroller.py` — `CarControl` → CAN message generation
  - `values.py` — Constants, car model enums, DBC mappings, tuning params
  - `toyotacan.py` — CAN message builders (steer commands, accel, UI)
  - `fingerprints.py` — CAN address → car model matching
- **`selfdrive/controls/`** — Control loops: `controlsd.py`, `plannerd.py`, `radard.py`
- **`selfdrive/modeld/`** — Driving model inference
- **`frogpilot/`** — FrogPilot additions on top of openpilot:
  - `tinygrad_modeld/` — Backported tinygrad model runner (C3 support)
  - `classic_modeld/` — Legacy SNPE/thneed model runner
  - `controls/` — Extended planner (publishes `frogpilotPlan`)
  - `common/frogpilot_variables.py` — 200+ FrogPilot toggles/params
  - `frogpilot_process.py` — Main FrogPilot async process
- **`panda/`** — CAN interface firmware + Python API. Ocelot uses same USB VID/PID (`bbaa`)
- **`opendbc/`** — DBC files for CAN message definitions
- **`system/`** — Hardware abstraction, camera, sensors, logging, cloud (athena)

### Car Interface Flow

1. **Fingerprinting**: `selfdrive/car/` identifies the car via CAN messages or forced env vars (`FINGERPRINT`, `SKIP_FW_QUERY`)
2. **CarInterface._get_params()**: Sets vehicle parameters (mass, wheelbase, steer ratio, safety config)
3. **CarState.update()**: Parses CAN → structured state each tick
4. **CarController.update()**: Generates CAN commands from control decisions
5. **toyotacan.py**: Builds specific CAN frames (steer, accel, UI HUD)

### Forcing Fingerprint (for retrofit)

In `launch_openpilot.sh` (NOT `launch_env.sh`):
```bash
export FINGERPRINT="TOYOTA COROLLA"
export SKIP_FW_QUERY=1
```

In `selfdrive/car/toyota/interface.py`: set `ret.dashcamOnly = False`.

### Toyota CAN Messages (retrofit-relevant)

DBC files: `toyota_new_mc_pt_generated` + `toyota_adas`. Key messages:
- `0x2E4` LKA_INPUT — steering torque command to EPS
- `0xaa` WHEEL_SPEEDS, `0x25` STEER_ANGLE_SENSOR, `0xb4` SPEED — EPS init
- `0x1d2` PCM_CRUISE, `0x1d3` PCM_CRUISE_2 — cruise state
- `0x3bc` GEAR_PACKET, `0x620` SEATS_DOORS — vehicle state

Two checksum implementations exist: `can_cksum` (wocsor style) and `toyota_checksum` (addr+data+len sum). Both valid, used for different message IDs.

## Retrofit Research Docs

See `../retrofit-research/` for detailed hardware/software documentation from Notion research notes:
- EPS wiring, 220-ohm termination resistor, corolla_bench.py
- Full Arduino CAN spoofing code with checksums
- Ocelot setup, SavvyCAN config, fingerprinting procedure

## FrogPilot Branch Structure

| Branch | OP Base | Use |
|--------|---------|-----|
| `FrogPilot` (stable) | 0.9.7 | Current release — use this |
| `FrogPilot-Staging` | 0.9.7 | Beta testing |
| `FrogPilot-Development` | 0.10.3 | Dev-only, hardcoded to developer's device |
| `MAKE-PRS-HERE` | 0.10.3 | PR workspace, auto-syncs with stable |

A migration from 0.9.7 → 0.10.3 is in progress. When it ships, car code moves from `selfdrive/car/toyota/` to `opendbc_repo/opendbc/car/toyota/` and imports change from `openpilot.selfdrive.car` to `opendbc.car`. The actual steering/CAN logic is structurally identical.
