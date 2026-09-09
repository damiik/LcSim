# LcSim

Gate-level virtual silicon compiled from Logic Cosmos TOML. LcSim generates a
C++ design that links against a shared simulation library and, optionally,
a raylib presentation library. There is no TypeScript or TOML parser in the
resulting simulation executable.

This initial project targets the existing FPGA and LVC profiles. It includes:

- `bin/lc_compile`: TOML v2 → C++ compiler (Python 3.11+, standard library only).
- `liblcsim.a`: C++17 event engine, runtime hierarchy expansion, strength-aware
  digital resolution, hierarchical evaluation cache, and analyzer capture/export.
- `liblcsim_symbols.a`: raylib controls, output/display/pixel presentation and
  waveform rendering.
- `lcsim-gui`: one generated simulation/analyzer application. `PANELS`,
  `SCOPE` and `TERM` switch views in the same process and retain the same simulation state.
- `lcsim`: headless executable for regression tests, measurements and VCD export.

The project is deliberately gate-level. Explicit NMOS/PMOS elements are rejected
with a diagnostic instead of silently approximated as FPGA gates.

## Build without graphics

Requirements: Python 3.11 or later, GNU Make, GCC with C++17 support, `ar`.

```sh
make
./build/lcsim --steps 10000 --technology lvc --vcd capture.vcd
make test test-cpu
```

The counter example starts with `Enable=1`, matching Logic Cosmos's high initial
INPUT state. Inputs accept `--input Enable=0`, `--input Enable=Z`, or a hex bus
value such as `--input DATA.D=0x81`. Named NODE monitors are read-only.

For another design, use a separate build directory:

```sh
make DESIGN=examples/cpu65c02.toml BUILD=build-cpu
./build-cpu/lcsim --technology fpga --steps 18000 --vcd cpu.vcd
./build-cpu/lcsim --technology lvc --steps 18000 --no-cache
```

The [r11 terminal guide](docs/terminal-r11.md) adds a TERM view, a polling
keyboard/display device and a working WozMon-style monitor computer. Build
`examples/cpu65c02-term.toml` to use it; the original WozMon ROM and full
65C02 ISA are not yet supported.

The [r10 ALU selector fix](docs/cpu65c02-alu-selector-r10.md) replaces shared-output
TBUFs with MUX4 to avoid transient contention when selecting an ALU operation.

For a file from r8, apply the [r9 memory radix fix](docs/cpu65c02-memory-radix-r9.md)
before running it in LogicCosmos. Memory words must carry an explicit `0x` prefix.

The r8 CPU fixture preserves the supplied editor layout and decorative NODEs.
PC/MAR are 16-bit; RAM occupies `$0000..$0FFF`, ROM `$F000..$FFFF`, and the
reset vector is at `$FFFC/$FFFD`. It adds absolute addressing and JSR/RTS.
The embedded test starts at `$F000`, ends at `$F180`, and writes
`MainRAM[$0FFF]=$A5`. It checks nested calls, stack wrap and all 23 new forms.

See [r8 instructions, signatures and ROM loading](docs/cpu65c02-absolute-call.md).
`make test-cpu` also executes the previous r7 program. Use the matching r8 Nim
patch to generate the new 4096×45-bit control image, then install it with
`tools/cpu65c02_image.py`, which supplies the boot bank. This is still a
non-decimal 65C02 subset; indirect addressing and interrupts remain future work.

## Generate and link explicitly

```sh
bin/lc_compile examples/counter.toml build/counter.cpp
make build/liblcsim.a
g++ -O3 -std=c++17 -Iinclude build/counter.cpp src/main.cpp \
    build/liblcsim.a -o build/counter
```

`gcc` can also be used, but C++ linkage must be explicit:

```sh
gcc -O3 -std=c++17 -Iinclude build/counter.cpp src/main.cpp \
    build/liblcsim.a -lstdc++ -lm -o build/counter
```

## Build ready-made raylib tools

Install/build raylib separately; its headers and libraries are not vendored.
The frontend uses the raylib 5.5 API subset documented in the
[official raylib reference](https://www.raylib.com/cheatsheet/cheatsheet.html).
The scripts expect a checkout at `../third_party/raylib` relative to this
directory. They check for `src/raylib.h` and a built `src/libraylib.a` (or a
shared-library equivalent) before invoking Make.

From `LcSim/`, build one TOML design into the headless tool and one unified GUI:

```sh
scripts/build_tool.sh examples/cpu65c02.toml cpu65c02
./build-cpu65c02/lcsim-gui --technology lvc
./build-cpu65c02/lcsim-gui --scope --technology fpga
```

Build all three included examples with separate generated designs and caches:

```sh
scripts/build_examples.sh
```

This creates `build-counter/`, `build-cpu65c02/` and `build-cpu65c02-term/`, each containing
`lcsim` (headless) and `lcsim-gui` (simulator/analyzer view). Set `RAYLIB_DIR`
to use another checkout and `BUILD_ROOT`
to choose the parent directory for `build_examples.sh`; `BUILD_DIR` chooses a
single output directory for `build_tool.sh`:

```sh
RAYLIB_DIR=/opt/raylib BUILD_DIR=build-my-design \
  scripts/build_tool.sh /path/to/design.toml my-design
```

The equivalent direct Make command, including the requested external-raylib
flags, is:

```sh
make tools DESIGN=examples/cpu65c02.toml BUILD=build-cpu65c02 \
  RAYLIB_CFLAGS='-I../third_party/raylib/src' \
  RAYLIB_LIBS='-L../third_party/raylib/src -lraylib -lGL -lm -lpthread -ldl -lrt -lX11'
```

`src/gui.cpp` is the current GUI translation unit (the equivalent of the
`alu_gui.cpp` name used in an earlier command). Core/headless targets never
include raylib; only `make gui`/`make tools` link it. To use a system raylib,
override `RAYLIB_DIR`, `RAYLIB_CFLAGS` and `RAYLIB_LIBS` explicitly.

**Validation status:** the C++ engine and compiler were built and exercised with
GCC, including the CPU self-test in both technologies. The frontend received a
C++ syntax check against the official raylib 5.5 header, but this environment did not
contain raylib/X11 development libraries or a display server. It has **not**
been linked against real raylib or visually tested here. Do not interpret the
headless test results as GUI verification.

## Controls and layout

The dark layout has top controls, a main `PANELS` workspace and a compact
`SCOPE` channel sidebar. In `PANELS`, INPUT controls are cards in the workspace;
NODE monitors are not repeated in a separate sidebar. Status, time, event and
cache information is shown in the bottom status bar. RUN/PAUSE, STEP, RESET,
AUTO CLK, technology selection and a logarithmic target step-rate slider are
available. Actual host throughput is separate from simulated nanoseconds.
Changing technology resets the simulation to avoid reinterpreting already
queued timestamps.

When `assets/fonts/MapleMono-Regular.ttf` is present, it is loaded for the UI.
The product title `LcSim` and the `Main workspace` label intentionally retain
the default raylib font. UI text is rendered at twice the previous size. If the
asset is unavailable, the UI falls back to the default font at the same size.

INPUTs have `0/1/Z` controls; bus INPUTs have an editable binary/hex field.
Repeated named NODE aliases are deduplicated. Contiguous suffixes such as
`DATA.D0..DATA.D7` form the little-endian monitor `DATA.D`. NODEs cannot drive nets.
OUTPUT and DISPLAY elements retain their relative schematic coordinates, fitted
uniformly into the workspace. DISPLAY supports hex, decimal and ASCII modes. A display without `n` derives its label from the common NODE bus prefix, such as `BUS.D0..D7` → `BUS`.
A NODE with a non-default `nsh`, `non` or `nof` is rendered as an unlabelled
pixel (circle/square); ordinary NODEs are available from the SCOPE channel tab.

F10 closes the window. Escape cancels bus input editing.

## Analyzer

SCOPE switches the main workspace to the analyzer; `lcsim-gui --scope` starts in
this view. PANELS and SCOPE use the exact same engine, event timestamps and
simulation state.

- Up to 64 channels; names and common acquisition settings are imported from
  the first workspace OSCILLOSCOPE. The Scope sidebar lists NODE/INPUT probes
  with checkboxes for adding/removing channels. Logical bus names are resolved
  from NODEs.
- Channel rows have `^`, `v` and `x` controls for moving a channel up/down or
  removing it. Clicking a waveform label still selects the trigger channel.
- The sidebar has CHANNELS and MEMORY tabs. MEMORY lists every flattened ROM
  and RAM instance, supports clipboard paste, clear and a scrollable hexadecimal
  word browser. `@address` in pasted text changes the write cursor; bare words
  are hexadecimal, matching TOML memory data.
- RLE transition history, rather than a sample per simulation tick.
- Multi-bit traces use diamond-ended bus segments. High-impedance scalar and
  bus intervals use dashed lines.
- AUTO, NORMAL and SINGLE modes; rising/falling/both edges; trigger bit;
  pretrigger and holdoff; ARM; single capture also completes on a quiet signal.
- Click a channel name to select the trigger. Wheel zooms time; Shift+wheel
  scrolls channels; middle drag pans; left/right clicks place time cursors.
- VCD/CSV buttons or V/C export retained history to `capture.vcd`/`capture.csv`.
  Hold Shift to export the interval between cursors instead.
- Export uses 1 ps VCD units and never substitutes zero for X/Z values.
- `scope_memory_samples` is a bounded transition capacity **per channel** here,
  not a fixed-rate sample count. `scope_samples_per_second` is unnecessary:
  every resolved transition is recorded.

This is the first native analyzer implementation, not a claim of complete UI
parity with Logic Cosmos. It does not yet have multiple simultaneous trigger
conditions, glow/analog traces, channel color editing, a file chooser, or
attachment to another running simulator process. Digital conflicts currently
appear as X; a separate C diagnostic channel is not exported.

## Documentation

- [TERM, monitor commands and MMIO](docs/terminal-r11.md)
- [Architecture and cache correctness](docs/architecture.md)
- [TOML and simulation semantics](docs/format-and-timing.md)
- [Verification and performance](docs/verification.md)
- [CPU65C02 system roadmap](docs/cpu65c02-system-roadmap.md)

Use `--dump` for hierarchical gate input/output diagnostics, `--no-cache` for
the reference execution path, and `--help` for command-line options.
