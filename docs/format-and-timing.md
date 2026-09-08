# Format and timing contract

Only Logic Cosmos `format_version = 2` is accepted. Re-save legacy files in the
editor before compiling them. Module interface order is the order of the
`inputs`/`outputs` arrays. Numeric wire 0 is disconnected. Scalars are accepted
for single ports; arrays represent ordered ports. A nested list such as
`i = [[1,2],3]` joins wires 1 and 2 at input zero, and feeds wire 3 to input one.

`inherit` is limited to `t,x,y,cd,nnp`, reset separately for inputs, gates and
outputs. Names and connectivity are not inherited. Modern `n/o/i` interface
fields and transitional `k/ix/s` aliases are accepted. Same-name NODEs connect
only inside the same module instance. `in/on` legacy display labels are ignored;
module interface names come from the definition. Missing ports are padded with
0; excessive ports, dangling wires, unknown gate types, recursive module
instantiation and invalid timing values are errors.

| Model parameter | FPGA | LVC |
|---|---:|---:|
| Simulation tick | 1.25 ns | 2.5 ns |
| Default combinational propagation | 0.5 ns | 2 ns |
| DFF CLK→Q | 0.5 ns | 2.5 ns |
| DFF setup | 0.3 ns | 1 ns |
| DFF hold | 0.1 ns | 0.2 ns |
| SW OE propagation | 0.5 ns | 4 ns |

These are the existing Logic Cosmos model profiles, not timing guarantees for
an arbitrary physical FPGA or LVC part. Host steps/second is not circuit MHz.

`pc` overrides propagation in simulation ticks; `pd` is legacy ns. If both are
present, `pc` takes precedence. Zero is a real zero delay. DFF uses CLK→Q for
this override and `tsu/th` for setup/hold in ns. `CLK.p` is one half-period in
ticks: `p=8` means a full clock period of 16 ticks. Internal event time is integer
ps; fractional timing fields round to the nearest ps. Zero-delay oscillation is
reported instead of locking the UI forever.

Supported elements: AND, OR, NOT, BUF, XOR, NAND, NOR, TBUF, OC, DFF,
D_LATCH, MUX2, MUX4, DMUX2, DMUX4, SW/SWITCH, H, L, PULL/PULLUP, PULLDOWN,
CLK, NODE, INOUT (passive connection), BUS (metadata), DISPLAY, OSCILLOSCOPE,
ROM, RAM, and user module definitions. `DFF` is the primitive spelling; a custom
module named `D_FF` remains a user module.

- Logic states are 0/1/X/Z. Strong drivers override weak pull resistors;
  disagreeing equal-strength drivers resolve to X.
- TBUF is directional and preserves source strength. Enable defaults active
  high (`eal=true` selects low). Unknown enable or undriven data releases the
  output, matching the source editor's discrete model.
- OC is the inverting open-collector primitive: high input pulls low; otherwise
  it releases. Weak pull-ups provide high. An X input releases in this model.
- DFF ports: CLK,D → Q,Q_N. Rising edges capture data; setup/hold violations
  produce X. Latch ports: D,LE → Q,Q_N. The existing Logic Cosmos Hi-Z-hold
  convention is retained: an undriven D does not overwrite storage even while
  LE is active. Driven X does overwrite an open latch. This is an explicit
  simulator convention, not a universal property of physical LVC/FPGA latches.
- MUX2: I0,I1,A → Q; MUX4: I0,I1,I2,I3,A,B → Q. A is the low selector bit.
  Unknown selectors merge all possible results. DMUX2/4: D,A[,B] → Q0..Qn;
  inactive outputs are zero.
- SW: A,OE_N,B → B,A. A input/output aliases are one terminal; B aliases are
  the other. SW uses active-low OE_N by default (`0` enables the connection;
  `1` disconnects it). Enabled SW connects them passively in both directions; it never
  re-drives its own resolved signal. Unknown OE conservatively makes differing
  terminal states unknown. Delay applies to OE, not data propagation.
- Memory address width is 1..20 and data width 1..64. ROM ports are address
  bits (LSB first), /OE → data bits. RAM inputs add data bits and /WE before /OE.
  Memory initialization uses whitespace-separated hexadecimal words (`0x`
  optional; `0b` is also accepted), or `mf` relative to the TOML file.
- `delay_ns` is address-to-data delay, independent of technology. The last
  settled word remains available while a new address settles, matching Logic
  Cosmos. /OE releases outputs immediately. A write to the settled address
  updates the word without a new address delay. Writes with unknown address or
  data are rejected and counted; they never silently become writes to zero.

Only top-level presentation elements are shown in the main workspace. Module
internals remain available through `--dump`; the GUI is a simulation front panel,
not a replacement schematic editor.
