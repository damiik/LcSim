import model
import sim
import design
import std/[os, strutils, tables]
from std/times import epochTime

# ---------------------------------------------------------------------------
# Definicje magistral do podglądu w trace.
# Kolejnosc bitow: LSB -> MSB (bit 0 pierwszy).
# Nazwa magistrali moze wystapic w liscie `watch` zamiast pojedynczych bitow.
# ---------------------------------------------------------------------------
const busDefs* = [
  ("DATA",       @["DATA.D0","DATA.D1","DATA.D2","DATA.D3",
                   "DATA.D4","DATA.D5","DATA.D6","DATA.D7"]),
  ("IR.D",       @["IR.D0","IR.D1","IR.D2","IR.D3",
                   "IR.D4","IR.D5","IR.D6","IR.D7"]),
  ("DBR.D",      @["DBR.D0","DBR.D1","DBR.D2","DBR.D3",
                   "DBR.D4","DBR.D5","DBR.D6","DBR.D7"]),
  ("A_OUT.D",    @["A_OUT.D0","A_OUT.D1","A_OUT.D2","A_OUT.D3",
                   "A_OUT.D4","A_OUT.D5","A_OUT.D6","A_OUT.D7"]),
  ("X_OUT.D",    @["X_OUT.D0","X_OUT.D1","X_OUT.D2","X_OUT.D3",
                   "X_OUT.D4","X_OUT.D5","X_OUT.D6","X_OUT.D7"]),
  ("Y_OUT.D",    @["Y_OUT.D0","Y_OUT.D1","Y_OUT.D2","Y_OUT.D3",
                   "Y_OUT.D4","Y_OUT.D5","Y_OUT.D6","Y_OUT.D7"]),
  ("ALU_OUT.D",  @["ALU_OUT.D0","ALU_OUT.D1","ALU_OUT.D2","ALU_OUT.D3",
                   "ALU_OUT.D4","ALU_OUT.D5","ALU_OUT.D6","ALU_OUT.D7"]),
  ("ALU_A.D",    @["ALU_A.D0","ALU_A.D1","ALU_A.D2","ALU_A.D3",
                   "ALU_A.D4","ALU_A.D5","ALU_A.D6","ALU_A.D7"]),
  ("ALU_B.D",    @["ALU_B.D0","ALU_B.D1","ALU_B.D2","ALU_B.D3",
                   "ALU_B.D4","ALU_B.D5","ALU_B.D6","ALU_B.D7"]),
  ("S.D",        @["S.D0","S.D1","S.D2","S.D3",
                   "S.D4","S.D5","S.D6","S.D7"]),
  ("TMP.D",      @["TMP.D0","TMP.D1","TMP.D2","TMP.D3",
                   "TMP.D4","TMP.D5","TMP.D6","TMP.D7"]),
  ("ADH.D",      @["ADH.D0","ADH.D1","ADH.D2","ADH.D3",
                   "ADH.D4","ADH.D5","ADH.D6","ADH.D7"]),
  ("EA_OUT.A",   @["EA_OUT.A0","EA_OUT.A1","EA_OUT.A2","EA_OUT.A3",
                   "EA_OUT.A4","EA_OUT.A5","EA_OUT.A6","EA_OUT.A7"]),
  ("PC_ADR",     @["PC_ADR.PC0","PC_ADR.PC1","PC_ADR.PC2","PC_ADR.PC3",
                   "PC_ADR.PC4","PC_ADR.PC5","PC_ADR.PC6","PC_ADR.PC7",
                   "PC_ADR.PC8","PC_ADR.PC9","PC_ADR.PC10","PC_ADR.PC11",
                   "PC_ADR.PC12","PC_ADR.PC13","PC_ADR.PC14","PC_ADR.PC15"]),
  ("MEM.A",      @["MEM.A0","MEM.A1","MEM.A2","MEM.A3",
                   "MEM.A4","MEM.A5","MEM.A6","MEM.A7",
                   "MEM.A8","MEM.A9","MEM.A10","MEM.A11",
                   "MEM.A12","MEM.A13","MEM.A14","MEM.A15"]),
  ("MAR.A",      @["MAR.A0","MAR.A1","MAR.A2","MAR.A3",
                   "MAR.A4","MAR.A5","MAR.A6","MAR.A7",
                   "MAR.A8","MAR.A9","MAR.A10","MAR.A11",
                   "MAR.A12","MAR.A13","MAR.A14","MAR.A15"]),
  ("PTR.A",      @["PTR.A0","PTR.A1","PTR.A2","PTR.A3",
                   "PTR.A4","PTR.A5","PTR.A6","PTR.A7",
                   "PTR.A8","PTR.A9","PTR.A10","PTR.A11",
                   "PTR.A12","PTR.A13","PTR.A14","PTR.A15"]),
  ("VECTOR",     @["VECTOR.V0","VECTOR.V1","VECTOR.V2","VECTOR.V3",
                   "VECTOR.V4","VECTOR.V5","VECTOR.V6","VECTOR.V7",
                   "VECTOR.V8","VECTOR.V9","VECTOR.V10","VECTOR.V11",
                   "VECTOR.V12","VECTOR.V13","VECTOR.V14","VECTOR.V15"]),
  ("STEP.S",     @["STEP.S0","STEP.S1","STEP.S2","STEP.S3"]),
  ("ALU_OP",     @["ALU_OP.0","ALU_OP.1"]),
  ("ALU_A_SEL",  @["ALU_A_SEL0","ALU_A_SEL1"]),
  ("ALU_B_SEL",  @["ALU_B_SEL0","ALU_B_SEL1"]),
  ("MAR_IN_S",   @["MAR_IN_S0","MAR_IN_S1","MAR_IN_S2"]),
]

type
  WatchItem = object
    label: string
    locals: seq[int]   # LSB-first; -1 oznacza brak dopasowania

# Surowe numery lokalne netów workspace (bez nazwy w findNetName).
# Przydatne do śledzenia anonimowych netów pośrednich, np. wyjść BUF/AND.
const watchRaw* = [
  ("536",  536), ("516", 516), ("58",  58), ("986", 986), ("329", 329),
  ("1389", 1389), ("1390",1390), ("1391",1391), ("1392",1392),
  ("1393", 1393), ("1394",1394), ("1395",1395), ("1396",1396),
  ("1373", 1373), ("1374",1374), ("1375",1375), ("1376",1376),
  ("1377", 1377), ("1378",1378), ("1379",1379), ("1380",1380),
]

proc resolveWatchItem(name: string,
                      nameToLocal: Table[string, int]): WatchItem =
  ## Jesli `name` jest nazwa magistrali z busDefs, zwraca WatchItem
  ## z wieloma locals; w przeciwnym razie traktuje jako pojedynczy sygnal.
  for (bname, members) in busDefs:
    if bname == name:
      result.label = bname
      for m in members:
        result.locals.add(nameToLocal.getOrDefault(m, -1))
      return
  result.label = name
  result.locals = @[nameToLocal.getOrDefault(name, -1)]

proc renderWatchItem(s: Simulator, it: WatchItem): string =
  ## Pojedynczy bit -> "0"/"1"/"x"/"z"; magistrala -> "0xNN"/"X"/"Z".
  if it.locals.len == 1:
    let ln = it.locals[0]
    if ln <= 0:
      return "?"
    return $digit(s.topNetValue(ln))
  var hasX = false
  var hasZ = false
  var v: uint64 = 0
  for i, ln in it.locals:
    if ln <= 0:
      hasX = true
      continue
    case s.topNetValue(ln)
    of lL: discard
    of lH: v = v or (1'u64 shl i)
    of lX: hasX = true
    of lZ: hasZ = true
  if hasX:
    return "X"
  if hasZ:
    return "Z"
  let nibbles = (it.locals.len + 3) div 4
  return "0x" & toHex(v, nibbles)

proc main() =
  var steps: int64 = 1_000_000
  var tech = "lvc"
  var runMode = false
  var dumpMode = false
  var runMs = 5000
  var traceNets = 0
  var args = commandLineParams()
  var i = 0
  while i < args.len:
    case args[i]
    of "--steps":
      if i+1 >= args.len: quit("--steps needs a value")
      steps = parseBiggestInt(args[i+1]).int64
      i += 2
    of "--technology":
      if i+1 >= args.len: quit("--technology needs a value")
      tech = args[i+1]
      i += 2
    of "--run":
      runMode = true
      i += 1
    of "--run-ms":
      if i+1 >= args.len: quit("--run-ms needs a value")
      runMs = parseInt(args[i+1])
      i += 2
    of "--dump":
      dumpMode = true
      i += 1
    of "--trace-nets":
      if i+1 >= args.len: quit("--trace-nets needs a value")
      traceNets = parseInt(args[i+1])
      i += 2    
    of "--help", "-h":
      echo "Usage: lcsim-nim [--steps N] [--technology lvc|fpga]"
      echo "                 [--run] [--run-ms MS]"
      quit(0)
    else:
      i += 1

  let d = makeDesign()
  let prof = if tech == "fpga": profileFpga() else: profileLvc()
  echo "design: ", d.name, "  profile: ", prof.name

  let t0 = epochTime()
  var s = newSimulator(d, prof)
  echo "flatten+startup: ", (epochTime() - t0).formatFloat(ffDecimal, 4),
       " s  (", s.gates.len, " gates, ", s.nets.len, " nets)"

  # --- Periodyczny trace kluczowych nazwanych netów i magistral workspace ---
  # Kazda pozycja w `watch` moze byc:
  #   * nazwa pojedynczego netu z findNetName (np. "RAW.IR_LOAD_N"),
  #   * nazwa magistrali z busDefs (np. "DATA", "PC_ADR", "STEP.S").
  # Magistrale renderowane sa jako hex (0xNN), pojedyncze bity jako 0/1/x/z.
  block:
    const watch = [
      "RESET", "BOOT.ACTIVE", "CLK", "PHI1", "PHI2",
      "STEP.S",                              # magistrala 4-bit
      "RAW.IR_LOAD_N", "RAW.PC_LOAD", "PC_LOAD", "MAR_LOAD",
      "RAW.MEM_OE_N", "RAW.MEM_WE_EN",
      "MAR_IN_S",                            # magistrala 3-bit
      "ALU_OP", "ALU_A_SEL", "ALU_B_SEL",
      "VECTOR_HI",
      "IR.D",                                # magistrala 8-bit
      "PC_ADR",                              # magistrala 16-bit
      "MEM.A",                               # magistrala 16-bit
      "DATA",                                # magistrala 8-bit
      "DBR.D",                               # magistrala 8-bit
      "VECTOR",                              # magistrala 16-bit
    ]

    # Zbuduj mape nazwa -> lokalny numer netu w top (workspace).
    var nameToLocal = initTable[string, int]()
    for localN in 1 ..< s.topNetCount():
      let nm = findNetName(d.root, Net(localN))
      if nm.len > 0:
        nameToLocal[nm] = localN

    # Rozwiaz watch -> WatchItem (pojedyncze sygnaly i magistrale).
    var watchItems: seq[WatchItem]
    var missing: seq[string]
    for nm in watch:
      let it = resolveWatchItem(nm, nameToLocal)
      var allFound = true
      for ln in it.locals:
        if ln <= 0:
          allFound = false
          break
      if not allFound:
        missing.add(nm)
      watchItems.add(it)

    # Dolacz surowe lokalne numery netow (np. wyjscia BUF/AND posrednie).
    # Renderowane jako pojedyncze bity (locals.len == 1).
    for (label, ln) in watchRaw:
      watchItems.add(WatchItem(label: label, locals: @[ln]))

    let traceTicks = if traceNets > 0: traceNets else: 500
    echo "--- trace: ", traceTicks, " ticks, ", watchItems.len,
         " pozycji (w tym ", busDefs.len, " magistral zdefiniowanych) ---"
    if missing.len > 0:
      echo "!!! brakuje nazw w findNetName: ", missing.join(", ")

    for step in 0 ..< traceTicks:
      s.advance(prof.tick)
      # Pierwsze 20 ticków co tick, potem co 10 (1 okres CLK przy LVC p=10)
      if step < 20 or step mod 10 == 0:
        var line = "t=" & $s.now & "ps"
        for it in watchItems:
          line &= " " & it.label & "=" & renderWatchItem(s, it)
        echo line
    if dumpMode:
      s.dumpProbes()
    # return

  if runMode:
    echo "--- terminal (host console as device) ---"
    echo "--- running for ", runMs, " ms, Ctrl+C to exit ---"
    let deadline = epochTime() + runMs.float / 1000.0
    const pollIntervalSec = 0.002   # 2 ms between host stdin polls
    var stepsDone: int64 = 0
    var lastPoll = 0.0
    var nextLog: int64 = 1_000_000
    while epochTime() < deadline:
      let wall = epochTime()
      if wall - lastPoll >= pollIntervalSec:
        lastPoll = wall
        s.pollTerminal()
      # Run for a bounded burst of simulated ticks between stdin polls.
      for k in 0 ..< 200:
        s.advance(prof.tick * 5)
      stepsDone += 1000
      if stepsDone >= nextLog:
        stderr.writeLine("[run] steps=", stepsDone, " sim=", s.now, " ps")
        nextLog += 1_000_000
    echo ""
    if dumpMode:
      s.dumpProbes()
    echo "--- done: ", stepsDone, " ticks, sim time ", s.now, " ps ---"
    return

  # benchmark mode
  s.advance(prof.tick * 100)
  let ticks = steps
  let t1 = epochTime()
  for k in 0 ..< ticks:
    s.advance(prof.tick)
  let dt = epochTime() - t1
  let hz = ticks.float / dt
  echo "steps: ", ticks, "  time: ", dt.formatFloat(ffDecimal, 4), " s"
  echo "cycles/s: ", int(hz), "  (",
       (hz / 1_000_000.0).formatFloat(ffDecimal, 3), " MHz)"
  if dumpMode:   
    s.dumpProbes()
  echo "sim time: ", s.now, " ps"

main()