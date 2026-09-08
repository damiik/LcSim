# CPU65C02 system roadmap

## Accepted r6 memory map

The address subsystem is widened before the physical stack is added:

| Range | Size | Use |
| --- | ---: | --- |
| `$0000..$00FF` | 256 B | zero page |
| `$0100..$01FF` | 256 B | hardware stack (`$0100 | S`) |
| `$0200..$0FFF` | 3584 B | general RAM |
| `$1000..$EFFF` | — | future I/O and expansion |
| `$F000..$FFFB` | 4092 B | program ROM |
| `$FFFC..$FFFD` | 2 B | little-endian RESET vector |
| `$FFFE..$FFFF` | 2 B | reserved IRQ/BRK vector |

This layout is suitable for a small monitor-based computer, but is not the
historical KIM-1 map. KIM-1 compatibility will require a separate 6530-style
I/O/timer decoder and its original monitor map.

## Current boundary

The supplied r6 Nim patch defines the 16-bit reference model, compact 4 KiB ROM
images, S and the first stack instructions. The checked-in TOML fixture now has
a transitional `stack-lab` implementation:

- `PC`, `MAR` and normal memory decoding are still 8-bit;
- S is an 8-bit load/inc/dec register with a tri-state data-bus output;
- a separate 256-byte bank models logical addresses `$0100 | S`;
- a MAR-load latch keeps that bank selected for the following memory step;
- the control ROM is 42 bits wide and exercises A/X/Y push/pull plus TSX/TXS;
- the ISA exposes implied, immediate, zero-page/indexed and relative forms;
- call, return, interrupt and the unified 16-bit address bus remain future work.

The shift/rotate and indexed programs remain useful toolchain regressions. The
LcSim TOML regression now runs the stack-lab program in both technologies and
with cache disabled/enabled. It is not yet a full 65C02 address-space test.
A CPU without decimal ADC/SBC can be highly compatible with the 65C02, but it
should be described as a **non-decimal 65C02 subset**, not a complete 65C02.

LcSim itself already accepts RAM/ROM address widths up to 20 bits and data widths
up to 64 bits. The main work belongs in the CPU schematic, microcode and Nim
toolchain rather than in the basic memory engine.

## Recommended implementation order

### 1. Freeze the current 8-bit machine

Keep the supplied shift/rotate/rotate and indexed programs as regression tests.
Record the expected RAM signature and cycle limit for FPGA and LVC. This protects
the working data path while address and control paths are replaced.

### 2. Widen only the address subsystem

Keep the data bus and ALU at 8 bits. Replace PC8 and MAR8 with paired low/high
registers:

- `PCL`, `PCH` form the 16-bit program counter;
- `MARL`, `MARH` form the 16-bit memory address;
- increment PCL and propagate carry into PCH;
- preserve a separate 8-bit zero-page/index calculation path;
- add a high-byte temporary register for absolute and indirect operands.

The external memory interface becomes `A[15:0]`, `D[7:0]`, `/OE` and `/WE`.
ROM/RAM decoding should remain explicit in TOML so the same CPU can be embedded
in different systems.

### 3. Add the hardware stack

Add an 8-bit S register with reset value `$FF`. Its effective address is
`$0100 | S`; this avoids a second physical address space and matches 65C02
software. Add independent `S_INC`, `S_DEC`, `S_OE_N`, `S_LOAD_N` and a stack
address selection state for MAR.

The r6 tool contract implements TSX/TXS, PHA/PLA, PHX/PLX and PHY/PLY. Wire and
test the physical TOML in this order:

1. `TSX`, `TXS`;
2. `PHA`, `PLA`, `PHP`, `PLP`;
3. `PHX`, `PLX`, `PHY`, `PLY`;
4. `JSR`, `RTS` with verified return-address byte order;
5. `BRK`, `RTI`, then RESET/IRQ/NMI vector fetch.

Push must write before decrementing S; pull must increment S before reading.
Status pushes need fixed B/unused-bit rules rather than copying a raw internal
flags byte.

### 4. Extend addressing and the Nim tools

In `model.nim`, change PC/effective addresses to `uint16`, add `regS`, absolute
and indirect address modes, three-byte instruction lengths and stack/call
semantic kinds. In `reference_cpu.nim`, use 65536 bytes of memory and keep
zero-page index arithmetic modulo 256.

In `assembler.nim`, widen origins, labels and emitted addresses to `0..65535`;
retain signed 8-bit relative-branch validation. Add absolute, absolute-X/Y,
indexed-indirect, indirect-indexed, zero-page-indirect and JMP-indirect forms to
the single ISA declaration in `isa.nim`. The LUT generator should derive the new
microcode from those declarations rather than introduce a second opcode table.

### 5. Add a memory-mapped terminal and keyboard

The terminal should be a stateful LcSim peripheral shared by GUI and headless
builds. A small register interface is sufficient:

| Register | Read | Write |
| --- | --- | --- |
| `TTY_DATA` | remove one byte from keyboard FIFO | append one byte to terminal |
| `TTY_STATUS` | RX-ready and TX-ready bits | ignored |
| `TTY_CONTROL` | interrupt-enable state | update control bits |

Addresses belong to the system TOML memory map, not the LcSim engine. The GUI
can render a text terminal in PANELS and forward key presses to the FIFO.
Headless mode should accept an input file/string and capture terminal output so
CPU tests remain deterministic. Terminal and keyboard state must be excluded
from hierarchical combinational caches, just like RAM, ROM, clocks and latches.

## Milestone tests

1. Existing shift/rotate and indexed programs still pass unchanged.
2. A 16-bit fetch crosses `$00FF -> $0100` and `$FFFF -> $0000` correctly.
3. Stack test verifies all push/pull instructions and S wraparound.
4. JSR/RTS nested-call test verifies the exact return PC.
5. Interrupt test verifies vector fetch and RTI status restoration.
6. Terminal echo program polls `TTY_STATUS`, reads a key and writes it back.
7. The same terminal program produces identical bytes in FPGA, LVC and
   headless modes.

The first useful system milestone is stages 1–3 plus a polling terminal. Full
interrupt-driven I/O and the remaining addressing modes can then be added
without changing the external device model.
