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
- CPU stack-lab, both technologies, both cache settings: main-RAM signature,
  stack-bank signature, final S, loop PC and matching complete transition hashes.

## CPU measurement

One observed run, 18,000 simulation steps per configuration, excluding
construction time, using the supplied circuit with MAR `pc=4` and cleared RAM:

| Profile | Cache off, steps/s | Cache on, steps/s | Estimated cache bytes |
|---|---:|---:|---:|
| LVC | 13,830 | 49,086 | 426,906 |
| FPGA | 15,445 | 52,807 | 425,790 |

The flattened CPU stack-lab contains 741 simulated gates/devices and 2,995
allocated net slots (including aliased and unused slots). NODEs and module
boundaries are connectivity, not gates to recompute. These numbers are not
directly comparable to the editor's component count.

The workload includes all eight initial stack instructions, both S wraparound
directions and the final BRA pass loop. The timing is
an indicative measurement in a shared environment, not a universal speedup or
a claim of host execution at the simulated technology's MHz. Re-run
`make test-cpu` on the target machine. The cache was roughly 3.4–3.6× faster in
this run, but lookup overhead can dominate a different workload.

Transition FNV regression fingerprints in this build:

- LVC: `531666357012246857` with cache both on and off.
- FPGA: `478034219658109357` with cache both on and off.

These compare the two C++ execution paths, not bit-for-bit event traces against
the TypeScript engine. Cross-engine validation here is the CPU program outcome
and the port/timing semantics exercised by the focused tests.

## GUI validation boundary

`src/gui.cpp` passed a strict C++ syntax check against a local declaration-only
raylib API shim. The shim was only a scratch validation aid and is not shipped.
No graphics functions were executed, and no screenshot was fabricated. Linking
against actual raylib and visual/interaction QA remain outstanding. The source
and documented build targets are provided so that those checks can be performed
on a machine with raylib installed.
