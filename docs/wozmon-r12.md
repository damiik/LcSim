# r12: the supplied ACIA Woz monitor on the gate-level CPU

This release runs the **WozMon ACIA adaptation supplied in the conversation**,
not the independently implemented LcMon from r11. The fixed 255-iteration
transmit delay is removed because this simulated ACIA acknowledges output
immediately. The monitor logic is otherwise unchanged. The leading ROM padding
`.org $F000; .byte $00` makes a 4096-byte image for this computer. The monitor
remains at `$FF00`, ECHO at `$FFEF`, with RESET vector `$FF00`. The original
`.org $8000` padding is not a new RAM/ROM mapping.

## Build

Apply `logic-cosmos-lcsim-wozmon-r12.patch` after r11 from the directory containing
`LcSim/`. The separate `logic-cosmos-nim-wozmon-r12.patch` applies in the Nim tools
repository after the r8 absolute/call patch. Checked-in ROMs mean that building
the simulator does not require rebuilding the Nim tools first.

```sh
cd LcSim
scripts/build_tool.sh examples/cpu65c02-wozmon.toml cpu65c02-wozmon
./build-cpu65c02-wozmon/lcsim-gui --technology lvc
```

Select TERM and leave RUN/AUTO CLK enabled. The initial prompt is `\`.
Use `assets/fonts/MapleMono-Regular.ttf` and the existing external raylib setup
(`../third_party/raylib/src`). There is still only one GUI application.

Type or paste `examples/wozmon-demo.txt`:

```text
0400: 41 42
0400.0401
0500: A9 21 8D 00 50 4C 00 FF
0500R
```

The monitor stores and examines `41 42`, installs a RAM program, then executes
it. That program writes `!` to ACIA_DATA and jumps back to `$FF00`. Commands are
hexadecimal; `R` jumps to the most recently opened address. `JSR $FFEF` prints A;
`JMP $FF00` restarts the monitor. R does not create an RTS return frame.

`ECHO` writes directly to ACIA_DATA and returns. The former delay executed about
510 unnecessary `DEC`/`BNE` instructions for every displayed character; UART
baud and framing are intentionally outside this terminal model. The ACTUAL value
is host throughput, not an emulated baud rate. Keystrokes/paste are queued.
Enter sends CR, Backspace sends `$08`, Escape sends `$1B`; lowercase becomes
uppercase. The r11 limits, COPY/CLEAR and scrollback remain unchanged.

## Instructions and hardware

| Opcode | Form | Semantics tested |
| --- | --- | --- |
| `$24` | `BIT zp` | Z from A AND memory; N/V from memory bits 7/6; preserve A/C |
| `$6C` | `JMP (abs)` | full 16-bit pointer; `$xxFF` reads next page, not the NMOS bug |
| `$A1` | `LDA (zp,X)` | add X modulo 256, read little-endian zero-page pointer, load A |
| `$81` | `STA (zp,X)` | same pointer formation, store A |
| `$B9` | `LDA abs,Y` | 16-bit addition including page carry and wrap at `$FFFF` |
| `$99` | `STA abs,Y` | same address calculation, store A |

The assembler also accepts `DEC` / `DEC A` as aliases for DEA (`$3A`) and
`INC` / `INC A` for INA (`$1A`) in the safe profile. These are aliases, not extra
opcodes. Accumulator ASL/LSR/ROL/ROR already accept the operand-less spelling.
Unsupported forms such as `LDA ($20),Y` are rejected, not misencoded as abs,Y.
The safe table now has **113 forms / 55 mnemonics**, still a non-decimal subset.
This is not a claim of a complete 65C02, interrupts, decimal mode or KIM-1.

The schematic adds a 16-bit PTR snapshot register, pointer increment logic,
ADH carry addition for abs,Y, MAR source muxes and BIT flag input muxes. All are
ordinary gates and flip-flops. C is not clocked while PRES_C is asserted, avoiding
a transient conflict in the original tri-state feedback during preservation.
Y is selected before the low/high operand fetch completes, giving ripple carry
time to settle. Direct/zero-page operand reads gain a settling microstep before
MAR capture. This release models instruction semantics, **not WDC bus-cycle
counts**. Timing is still technology-scaled as in the existing CPU.

The 50-bit control word appends these active-high signals without moving bits
0..44:

| Bit | Signal | Purpose |
| --- | --- | --- |
| 45 | PTR_LOAD | capture stable MAR before reading a pointer's high byte |
| 46 | MAR_PTR_NEXT | select incremented pointer as MAR input |
| 47 | PTR_ZP | force high byte to zero for zero-page pointer wrap |
| 48 | MAR_ABSY | select ADH:TMP + Y as MAR input |
| 49 | FLAGS_BIT | use TMP7/TMP6 as N/V inputs |

The execution image remains 4096 words: opcode bits A0..7, STEP bits A8..11.
The physical control ROM is **8192 x 50**, with A12 selecting the existing boot
bank. STEP remains four bits. Do not load an old 45-bit LUT into the new CPU or
use the new LUT with an old schematic.

## Memory and terminal

RAM remains `$0000..$0FFF`; ROM `$F000..$FFFF`. Hardware stack uses `$0100..$01FF`.
WozMon reserves zero page `$24..$2B` and buffer `$0200..$027F`. Use `$0400` onward
for user examples. The NMI/IRQ vector words are retained but interrupt hardware
is not implemented. No ACIA address overlaps RAM or ROM.

The TERMINAL primitive now accepts `io_mode="apple1"` (default, backward
compatible) or `io_mode="acia"`. The Woz example explicitly uses
`io_base=20480` (`$5000`), `io_mode="acia"`, and the same 26 inputs / 8 outputs
as r11. This is a **polling 6551-style register interface**, not a complete ACIA:

| Address | Read | Write |
| --- | --- | --- |
| `$5000` DATA | next ASCII byte, bit 7 clear; 0 when empty | print character |
| `$5001` STATUS | bit 3 RX-ready, bit 4 TX-ready; other bits zero | modeled reset: clear RX queue and command |
| `$5002` COMMAND | stored command byte | store command byte |
| `$5003` CONTROL | stored control byte | store control byte |

The `$0B`/`$1F` initialization is accepted. Baud rate, framing, parity, IRQ and
serial wire timing are not modeled. TX is immediately ready. A DATA read holds
one byte for the complete read cycle and consumes it once on release; writes
commit once at WR_N rising. Unselected read outputs are Z. Apple-1 behavior at
`$D010..$D013` remains available for the old LcMon example.

`TERMINAL` remains an LcSim-only extension. Use `cpu65c02.toml` for LogicCosmos
editing and CPU tests; use `cpu65c02-wozmon.toml` for LcSim. Existing NODEs,
coordinates, styles and module definitions are preserved by the CPU upgrade.
Only required signal connections/control ROM and appended hardware change.

## Rebuild ROMs

After applying the Nim patch and rebuilding `lcct`:

```sh
lcct lut -o:control-lut.mem --explain:microcode.md --isa:mos6502-safe
python3 tools/cpu65c02_image.py examples/cpu65c02.toml --control control-lut.mem
lcct asm examples/wozmon-acia.asm --isa:mos6502-safe --format:mem \
  -o:examples/wozmon-acia.hex
python3 tools/prepare_terminal.py --mode acia examples/cpu65c02.toml \
  examples/wozmon-acia.hex examples/cpu65c02-wozmon.toml
```

`examples/control-r12.mem` is the matching generated execution bank. The image
helper validates 50-bit words and reconstructs the boot bank. `upgrade_cpu_r12.py`
is a one-time migration helper for the r10/r11 row ordering; it is not a general
netlist rewriter and rejects an already-upgraded CPU. The checked-in CPU is
already upgraded: **do not run that migration on it again**.

## Tests and validation boundary

```sh
make test test-cpu test-woz-instructions test-term-cpu
make test-wozmon
make DESIGN=examples/cpu65c02-wozmon.toml BUILD=build-woz
./build-woz/lcsim --technology fpga --steps 1000000 \
  --terminal-input examples/wozmon-demo.txt --terminal-output wozmon.txt
```

The instruction regression checks BIT combinations, real nonzero X, indexed
page carry, zero-page pointer wrapping (both addition and high-byte read),
`JMP ($03FF)` and `JMP ($FFFF)`. Success is RAM `$0800=$A5`, failure is
`$08FF=$EE`; the done loop is `$F385`. The same ROM runs in the independent Nim
model and both FPGA/LVC engines (C++ and TypeScript). The monitor test checks
store, block examine and a RAM program returning to the prompt in all four
C++ technology/cache combinations. The complete script now finishes after
469,500 simulation ticks; the one-million-tick test ceiling prevents the fixed
delay loop from being accidentally restored. The previous stack/call/reset and
LcMon tests remain separate regressions.

GUI code is compile-checked against the official raylib 5.5 header; visual and
interactive testing still requires a machine with raylib and a display server.
No claim of a complete 6551, 65C02, Apple-1 or KIM-1 is implied.

Instruction semantics reference: [WDC W65C02S datasheet](https://www.westerndesigncenter.com/documentation/w65c02s.pdf).
Firmware: the ACIA-adapted WozMon listing supplied by the user in this task;
only its redundant simulated-transmitter delay is removed. The patch does not
replace it with LcMon or a host-side monitor interpreter.
