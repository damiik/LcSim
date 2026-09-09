# Verification record

Validation environment: Linux, GCC 13.3.0, C++17, Python 3. Standard-library-only
headless build; no raylib/X11 development installation or display server.

Commands:

```sh
make test test-cpu CXXFLAGS='-O3 -DNDEBUG -std=c++17 -Wall -Wextra -Werror'
```

All executed tests passed:

- Scaled propagation deadlines in both technologies, including explicit zero
  and inertial cancellation of a pulse shorter than the gate delay.
- DFF edge capture and setup violation; latch hold on Z versus overwrite by X.
- Bidirectional SW, conflict resolution, and separation of its two terminals
  when disabled.
- Exhaustive MUX2/MUX4 data/address combinations and DMUX2/DMUX4 selector order.
- RAM address delay with old-word retention, immediate /OE, and rejecting writes
  whose data is unknown.
- ROM/RAM enumeration plus validated paste/replace and clear operations used by
  the GUI memory browser.
- Weak-drive preservation through TBUF and inverting OC release behavior.
- Scope trigger timestamps, single capture completion on quiet inputs, rearm,
  transition-capacity bounds, VCD/CSV export.
- Compiler inheritance, recursive modules, dangling wires, unknown gates and
  nested multiple-driver input arrays.
- Cache-on versus cache-off exact timestamped transition equality in a focused
  hierarchical test containing short pulses and Z input changes.
- Previous r7 program on the r8 CPU, LVC/FPGA, cache off/on: unified RAM signature, S wraparound,
  PC16 sequential carry, signed backward/forward branches across pages,
  reset-vector reads at FFFC/FFFD, warm reset with a changed vector and RAM
  retention, instruction fetch from RAM at 0200/0F80, PC FFFF-to-0000 rollover.
- r8 absolute/call ROM in LVC/FPGA, cache off/on: all 23 new forms, nested
  calls, stack wrap, return byte order and JSR operand crossing F0FF/F100.
  Success is RAM[0FFF]=A5, S=FF, PC=F180/F181.
- ROM image installation rejects bad sizes/word widths, preserves schematic
  properties, and regenerates the boot-idle control bank.
- The TypeScript parser and serializer round-trip the r8 file: 1124 workspace
  nodes, 1374 workspace wires, 20 custom modules. This checks format/graph
  compatibility, not TypeScript CPU execution or equality of engine traces.

The C++ CPU regression also passed after compiling the TypeScript-serialized
TOML, including all four technology/cache combinations.

## CPU regression

Run `make test-cpu` for the checked-in r8 ROM and the separate r7 regression
ROM. Each runs 20,000 steps. The r7 scenario also performs an input reset with
a changed vector. Additional instances
execute code in both ends of RAM and test full PC rollover. Complete timestamped
transition hashes must match for cache on/off within each technology; elapsed
host time is printed only for local comparison. No clock-rate benchmark is
inferred from the technology's nominal MHz.

The r8 changes are in the schematic, tests, ROM helper and Nim toolchain; no
CPU-specific behavior was added to the C++ engine. Nim 2.2.4 compiled the CLI
and ran both available suites (7 tests). The independent instruction model
executes all new forms; assembler tests cover forward targets, little-endian
encoding and rejection of overflow/unsupported indexed operands. Disassembly
checks cover origins, branch targets and truncated input. Both ISA profiles
pass microcode validation. For all 84 previous safe opcodes, the first eight
microsteps preserve the original lower 42 control bits.

The embedded 4096-word execution bank matches the actual Nim-generated LUT.
The embedded program matches the actual Nim-assembled example. The ROM helper
reinstalls both as a byte-for-byte no-op. A semantic layout comparison verifies
all original coordinates, labels and styles, including 1247 NODEs across the
workspace/modules; only the accidental PC15-to-PC14 alias is repaired.

See [the r8 guide](cpu65c02-absolute-call.md) for signatures and boundaries.

## GUI validation boundary

`src/gui.cpp` passed a strict C++ syntax check against a local declaration-only
raylib API shim. The shim was only a scratch validation aid and is not shipped.
No graphics functions were executed, and no screenshot was fabricated. Linking
against actual raylib and visual/interaction QA remain outstanding. The source
and documented build targets are provided so that those checks can be performed
on a machine with raylib installed.
