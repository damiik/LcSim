# Architecture

The compiler parses and validates TOML using Python's standard `tomllib`. It
emits `Design`, `Definition` and `Element` data in a `make_design()` function.
Each module definition appears once; instances reference definition indices.
The generated file contains connectivity and configuration, not simulation code
replicated for each instance. Memory initialization is numeric data.

At executable startup the library recursively expands instances, preserves the
instance tree as `Group` records, maps boundary ports, and resolves same-name
NODE aliases inside each instance. Different instances have separate internal
nets. Nested input lists describe multiple drivers of a single pin; these are
joined electrically. Disconnected inputs reference the undriven Z net; each
unused output gets its own sink. Named probes and display metadata survive
expansion. Simulation then uses gate and driver indices without module lookup.

A priority queue stores integer picosecond events. All output events at the
same timestamp are applied before evaluating affected gates. Inertial generation
numbers cancel superseded output changes. A target change in strength matters
even if its logical value does not change. The no-switch path resolves only
modified nets; networks with SW use a passive connectivity pass. UI refresh is
independent of simulation steps, with a bounded per-frame work budget.

Sequential outputs begin at zero. Startup settles the combinational network
with DFF edge capture suppressed and clocks stationary high, then establishes
virtual time zero and starts the clock events. This avoids manufacturing clock
edges from uninitialized gate outputs. INPUTs initially drive high, as in the
source editor. A reset recreates all device state; the GUI then reapplies ROM/RAM
images pasted or cleared through its MEMORY tab.

## What the cache stores

Caching `module inputs -> final outputs` is insufficient for timed simulation:
a pulse may be pending, internal nodes may not have settled, and a latch or RAM
may remember earlier events. LcSim's first cache is therefore an **evaluation
batch cache**, not a final-output truth table and not a stateful macro-model.

For a pure combinational module subtree, at a particular event batch:

1. Build a signature of the dirty gate indices within that module plus each
   dirty gate's current input logic **and strength**, including internal nets.
2. On a miss, recurse into child groups (which may themselves hit cache), then
   evaluate this group's remaining gates normally.
3. Save the resulting per-gate output targets using relative gate indices.
4. On a hit, reuse those targets and pass every one through the same inertial
   scheduler used by uncached simulation.

The signature completely determines these pure evaluations. Cache hits never
skip a timestamp, overwrite sequential state, bypass a driver resolver, or
replace the pending event queue. Incoming edges during propagation therefore
require no speculative rollback. Relative indices allow identical instances
of one definition to share the learned plans. A parent miss can learn from
child hits; a later parent hit skips evaluation of the entire dirty batch below
it. First use starts from ordinary flattened execution.

Groups containing DFF, D_LATCH, RAM, ROM, SW, clocks or sources are not cached as
whole regions. Their eligible descendants still are. Constants currently also
exclude their enclosing group from whole-group caching. No stateful-module
memoization or full response-waveform replay is claimed in this version.

The default cache payload estimate is capped at 16 MiB per simulator; after the
budget fills, existing entries still work but no new entries are inserted.
`cache_bytes` includes estimated entry overhead, not a measurement of allocator
RSS. Cache lookup, key creation and scheduling still cost CPU time. A cache may
hurt a design with little repetition; `--no-cache` provides a direct baseline.
A new simulator/reset/technology selection creates a fresh cache.

## Extending the optimization

A future settled combinational-region cache could store input transitions and
complete relative-time output waveforms, with a proven cancellation/rollback
policy for intervening input edges. A stateful-region cache would additionally
need canonical device state, memory effects and pending-event residual times.
These optimizations belong behind the timestamped trace-equivalence tests.
They must not be enabled merely because a module name looks like a register or
an ALU.

The analyzer subscribes to resolved-net transitions. It reads the same nets as
the main UI and cannot mutate NODE state. It holds bounded per-channel RLE data,
tracks trigger timing in simulated time, and exports a selected retained range.
The unified `lcsim-gui --scope` view reuses both this collector and the same
renderer as the simulator panels; switching views does not create a second
simulation process.

The public memory API enumerates flattened ROM/RAM instances by hierarchical
path and validates replacement images against their depth and data width.
Replacing the active address refreshes the memory output through the normal gate
evaluation path. This is used by the MEMORY tab and remains available to future
headless system peripherals and debuggers.

## Terminal peripheral

The r11 TERMINAL gate is stateful and excluded from pure-module caches. GUI
TERM and headless input/output use its shared runtime FIFO and transcript;
neither bypasses CPU execution. MMIO reads hold one byte per read cycle and
writes commit on /WR release. See [the terminal contract](terminal-r11.md).
