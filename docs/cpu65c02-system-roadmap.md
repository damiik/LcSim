# CPU65C02 system roadmap

## Implemented memory map (r7/r8)

PC and MAR are now 16-bit; the physical stack uses the unified RAM:

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

The r8 TOML implements PC16, MAR16, reset-vector boot, unified RAM stack,
absolute addressing and JSR/RTS. It adds ADH, a PCH bus driver, a four-bit STEP
counter and a 45-bit control word. See [r8 implementation](cpu65c02-absolute-call.md).
The toolchain has 107 forms / 54 mnemonics. Absolute indexed and indirect
addressing, PHP/PLP and interrupts remain to be added. This is a **non-decimal
65C02 subset**, not a complete 65C02 or KIM-1 emulator.

LcSim itself already accepts RAM/ROM address widths up to 20 bits and data widths
up to 64 bits. The main work belongs in the CPU schematic, microcode and Nim
toolchain rather than in the basic memory engine.

## Recommended implementation order

### 1. Preserve regressions (completed through r8)

Keep the supplied shift/rotate/rotate and indexed programs as regression tests.
Record the expected RAM signature and cycle limit for FPGA and LVC. This protects
the working data path while address and control paths are replaced.

### 2. Widen only the address subsystem (PC/MAR/reset/ADH completed)

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

### 3. Add the hardware stack (S, A/X/Y push/pull and JSR/RTS completed)

Add an 8-bit S register with reset value `$FF`. Its effective address is
`$0100 | S`; this avoids a second physical address space and matches 65C02
software. Add independent `S_INC`, `S_DEC`, `S_OE_N`, `S_LOAD_N` and a stack
address selection state for MAR.

The physical TOML tests TSX/TXS, PHA/PLA, PHX/PLX, PHY/PLY and JSR/RTS.
Remaining work: PHP/PLP with the architectural status layout, then BRK/RTI and
IRQ/NMI vector fetch. RESET is already implemented.

Push must write before decrementing S; pull must increment S before reading.
Status pushes need fixed B/unused-bit rules rather than copying a raw internal
flags byte.

### 4. Extend addressing and the Nim tools

The Nim model already uses 16-bit PC/effective addresses, regS, a 64 KiB
reference memory, three-byte absolute instructions and call/return semantics.
The assembler retains signed 8-bit branch validation, and the disassembler
accepts `--origin:0xF000`. Known byte addresses use zero-page forms when possible;
forward references conservatively use absolute forms.

Next add absolute-X/Y, indexed-indirect, indirect-indexed, zero-page-indirect
and JMP-indirect forms to `isa.nim`, with matching hardware address paths and
microcode. Keep zero-page index/pointer arithmetic modulo 256. The LUT must
continue to be derived from the single ISA declaration.

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
