# TERM and the monitor computer (r11)

TERM is a third view of the same `lcsim-gui` process, alongside PANELS and
SCOPE. Switching views preserves the CPU, RAM, capture and terminal state.
Keyboard/display logic belongs to the shared C++ simulator, so headless tests
exercise the same device as the GUI. No CPU instructions are emulated in the
terminal: the monitor executes on the flattened gates of the supplied CPU.

## Build and run

Apply the r11 patch from the repository directory containing `LcSim/`, after r10:

```sh
git apply --check logic-cosmos-lcsim-terminal-r11.patch
git apply logic-cosmos-lcsim-terminal-r11.patch
cd LcSim
scripts/build_tool.sh examples/cpu65c02-term.toml cpu65c02-term
./build-cpu65c02-term/lcsim-gui --technology lvc
```

The script uses `-I../third_party/raylib/src` and
`-L../third_party/raylib/src -lraylib` plus the existing Linux dependencies.
Select TERM and leave RUN and AUTO CLK enabled. The boot prompt is `\`.
Terminal designs start with a target of 100,000 simulation steps/s; actual host
throughput is shown separately. A CPU instruction takes many gate simulation
steps. Input is buffered, so a pasted command may take time to execute.

The screen uses MapleMono when available, green text, 40 columns, a blinking
cursor and mouse-wheel scrollback. Type directly while TERM is selected.
Enter sends CR; Escape abandons the current monitor line; Backspace sends the
monitor's underscore erase command. PASTE or Ctrl+V queues clipboard text;
COPY copies the output transcript; CLEAR clears the screen/history only.
Lowercase is converted to uppercase; CRLF is normalized. Only ASCII is sent.
The keyboard queue holds 4096 characters, scrollback 512 lines and the output
transcript 65536 characters. An oversized paste is rejected as a whole.
The transcript retains printed bytes (including wrapped lines without inserted
newlines); erase controls affect the visible screen rather than rewriting it.
F10 still closes the window. RESET or changing technology recreates the device,
clearing its input queue, controls and screen along with the simulator reset.

## Monitor commands

The included `wozmon-lcsim.asm` is **LcMon, an independently implemented monitor
with basic WozMon command syntax**. It is not the original 256-byte WozMon ROM
and does not claim binary-compatible firmware or full Apple-1 emulation.
The current CPU still implements the r8 non-decimal subset, including absolute
loads/stores and JSR/RTS; absolute indexed/indirect addressing and several other
instructions needed by the original monitor remain future work.

```text
0400: 41 42
0400.0401
0500: A9 21 8D 12 D0 4C 00 F8
0500R
```

The first line stores two bytes. The second prints `0400: 41` and `0401: 42`.
The third installs `LDA #$21; STA $D012; JMP $F800`. The last runs it: `!`
appears and the monitor restarts. This script is also `examples/terminal-demo.txt`.
An address alone examines one byte, `start.end` examines an inclusive range,
`address: bytes` stores successive bytes, and `address R` jumps to that address.
Addresses and data are hexadecimal. Each examined byte is printed on its own
line. Store commands first examine the original byte before writing. R jumps
without creating an RTS return frame; return with `JMP $F800`. `JSR $FFEF`
is the monitor character-output entry (ASCII in A). Lines are limited to
127 characters; overflow or an invalid character abandons the command.
Memory outside installed RAM/ROM/I/O is undriven and must not be examined as
if it contained valid bytes.

### Memory map and reserved areas

| Address | Purpose |
| --- | --- |
| `$0000..$0FFF` | MainRAM, including hardware stack `$0100..$01FF` |
| `$0020..$0028` | monitor working variables |
| `$0200..$027F` | monitor input line buffer |
| `$0300..$030A` | monitor self-modifying load/store/jump trampolines |
| `$0400..$0FFF` | convenient user program/data area |
| `$D010..$D013` | terminal registers |
| `$F000..$FFFF` | ProgramROM; monitor starts at `$F800` |
| `$FFEF` | JMP to character-output routine |
| `$FFFC/$FFFD` | reset vector `$F800` |

Do not store programs or persistent test data in the monitor's reserved RAM.
In particular, typing a command overwrites `$0200`, so it is unsuitable for a
store/read test. The monitor uses the real hardware stack for calls.

## Terminal device contract

`TERMINAL` is an **LcSim extension**; the current LogicCosmos editor does not
implement this primitive. Keep `cpu65c02.toml` for editing/testing there and
create the separate `cpu65c02-term.toml` for LcSim. The generator retains all
existing modules, NODE decorations and positions and adds one device plus eight
DATA bus aliases. It replaces only ProgramROM, leaving the working control LUT.

The default `io_base` is `$D010` (53264); it must be a four-byte-aligned 16-bit
address. Port order is fixed, all bits least-significant first:

- `i`: A0..A15, write D0..D7, RD_N, WR_N (26 inputs).
- `o`: read D0..D7 (8 outputs, joined to the named DATA bus).

Address selection is internal. RD_N=0/WR_N=1 enables a read; WR_N=0/RD_N=1
enables a write. All other combinations release the outputs to Z. This is a
polling Apple-1-style register interface, not a complete 6820 PIA or UART.
It has no IRQ, baud rate or emulated video scan timing.

| Register | Read | Write |
| --- | --- | --- |
| `$D010` KBD | queued ASCII byte with bit 7 set; 0 if empty | ignored |
| `$D011` KBDCR | bit 7 = key ready, bits 0..6 = control | keyboard control |
| `$D012` DSP | 0: transmitter immediately ready | print low 7 bits when DSPCR bit 2 is set |
| `$D013` DSPCR | display control byte | display control |

Initialize DSPCR with `$A7` (or at least bit 2). A KBD read latches its byte
for the complete read cycle and consumes it once when the cycle ends; status
reads never consume input. A display/control write commits once at the rising
WR_N edge using the last valid data sampled while WR_N was low. Invalid data
or loss of address selection prevents output. These semantics avoid repeated
characters as gates settle. The device and its ancestors are excluded from
combinational result caches; independent combinational submodules still cache.

## Rebuild firmware and regenerate a customized schematic

The checked-in TOML contains its ROM images, so normal builds need no Nim tools.
To change the monitor, use the matching r8+ CPU tools:

```sh
lcct asm examples/wozmon-lcsim.asm --isa:mos6502-safe \
  --format:mem -o:examples/wozmon-lcsim.hex
python3 tools/prepare_terminal.py examples/cpu65c02.toml \
  examples/wozmon-lcsim.hex examples/cpu65c02-term.toml
```

The ROM file has 4096 bytes starting at `$F000`, including the reset vector.
The generator can take a revised r10 CPU schematic with the same named memory
signals. It rejects a source that already contains a terminal.

## Headless operation and tests

```sh
make DESIGN=examples/cpu65c02-term.toml BUILD=build-term
./build-term/lcsim --technology fpga --steps 900000 \
  --terminal-input examples/terminal-demo.txt --terminal-output terminal.txt
make test test-cpu test-term-cpu
```

The terminal input/output options select headless execution even in the GUI
binary. Input is queued before simulation; output is captured after the requested
step count. These options and TERM currently address the first terminal device.
A short step budget can leave commands unfinished. Scope capture/VCD continues
to work with this design. The CPU integration test executes store, range read,
and a RAM program returning to the monitor in LVC/FPGA with cache on/off, and
compares complete output transcripts. Runtime tests cover selection, Hi-Z,
read consumption, write-edge behavior, invalid data and bounded storage.
