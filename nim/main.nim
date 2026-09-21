import model
import sim
import design
import std/[os, strutils, times]

proc main() =
  var steps: int64 = 1_000_000
  var tech = "lvc"
  var args = commandLineParams()
  var i = 0
  while i < args.len:
    case args[i]
    of "--steps": steps = parseBiggestInt(args[i+1]).int64; i += 2
    of "--technology": tech = args[i+1]; i += 2
    else: i += 1

  let d = makeDesign()
  let prof = if tech == "fpga": profileFpga() else: profileLvc()
  echo "design: ", d.name, "  profile: ", prof.name

  let t0 = epochTime()
  var s = newSimulator(d, prof)
  let tSetup = epochTime() - t0
  echo "flatten+startup: ", tSetup.formatFloat(ffDecimal, 4), " s  (",
       s.gates.len, " gates, ", s.nets.len, " nets)"

  # Warm-up
  s.advance(prof.tick * 100)
  let warmCycles = 100'i64

  # Measured run
  let ticks = steps
  let t1 = epochTime()
  for k in 0 ..< ticks:
    s.advance(prof.tick)
  let dt = epochTime() - t1

  let hz = ticks.float / dt
  echo "steps: ", ticks, "  time: ", dt.formatFloat(ffDecimal, 4), " s"
  echo "cycles/s: ", hz.formatFloat(ffDecimal, 0), "  (",
       (hz / 1_000_000.0).formatFloat(ffDecimal, 3), " MHz)"
  echo "sim time: ", s.now, " ps"

main()
