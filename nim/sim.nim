import model
import std/[tables, sets, deques]
from std/posix import STDIN_FILENO, TPollfd, Tnfds, POLLIN, poll, read
from std/times import epochTime

const
  MAX_GATE_INPUTS = 88

type
  Driver = object
    net: Net
    value, target: Logic
    weak, targetWeak: bool
    pending: bool
    generation: uint64

  Wire = object
    value: Logic
    weak: bool
    drivers: seq[int32]
    users: seq[int32]

  Gate = object
    e: Element
    driverBegin, driverCount: int32
    delay, period: Time
    stored, lastClock, lastData: Logic
    dataChanged, edge: Time
    address, settledAddress: int64
    readWord: uint64
    ready: bool
    readGeneration: uint64
    memoryDelay: Time
    fastClock: bool
    activeLow: bool
    # TERMINAL latch state (PIA and ACIA)
    terminalRead: bool
    terminalReadReg: int
    terminalReadValue: uint8
    terminalKeyLatched: bool
    terminalWrite: bool
    terminalWriteReg: int
    terminalWriteValue: uint8

  Event = object
    generation: uint64
    id: int32
    kind: uint8
    value: Logic
    weak: bool

  Bucket = object
    at: Time
    events: seq[Event]

  Simulator* = ref object
    profile*: Profile
    now*: Time
    autoClock*: bool
    initializing: bool

    parent*: seq[Net]
    nets*: seq[Wire]
    drivers*: seq[Driver]
    gates*: seq[Gate]

    buckets: seq[Bucket]
    bucketHead: int

    touched: seq[Net]
    touchedFlag: seq[uint8]
    touchedList: seq[Net]

    dirty: seq[bool]
    dirtyGates: seq[int32]

    probes: seq[tuple[name: string, net: Net]]

    # Mapowanie lokalny numer netu w definicji top (Main Workspace) -> net
    # symulatora. Wypełniane tylko dla wywołania flatten(..., top=true),
    # po zakończeniu wszystkich joinów zrootowane przez union-find.
    # Używane przez main.nim razem z findNetName() z design.nim.
    topMap*: seq[Net]

    # Terminal I/O
    terminalOut*: File
    terminalFifo: Deque[uint8]
    terminalKbdControl: uint8
    terminalDispControl: uint8
    terminalLastNl: bool
    lastPollWall: float
    pollInterval: float

# ---------- helpers ----------

# Emit one byte to the host terminal, matching C++ Terminal::put_char
# semantics for CR/LF/BS. Used only by the TERMINAL handler.
proc emitTerminalChar(s: Simulator, ch: uint8) =
  let c = ch and 0x7f
  if c == 0x0d or c == 0x0a:
    # CR or LF: one newline, but a LF immediately after CR is absorbed.
    if c == 0x0a and s.terminalLastNl:
      return
    s.terminalOut.write('\n')
    s.terminalOut.flushFile()
    s.terminalLastNl = true
  elif c == 0x08 or c == 0x7f:
    s.terminalOut.write('\b')
    s.terminalOut.flushFile()
    s.terminalLastNl = false
  elif c >= 0x20 and c < 0x7f:
    s.terminalOut.write(char(c))
    s.terminalOut.flushFile()
    s.terminalLastNl = false
  # Everything else (control chars) is silently dropped, same as C++.


proc inv*(x: Logic): Logic {.inline.} =
  case x
  of lL: lH
  of lH: lL
  else: lX

proc binary*(x: Logic): Logic {.inline.} =
  if x == lZ: lX else: x

proc isPure(t: GateType): bool {.inline.} =
  t in {gtAND, gtOR, gtXOR, gtNAND, gtNOR, gtNOT, gtBUF, gtTBUF, gtOC,
        gtMUX2, gtMUX4, gtDMUX2, gtDMUX4}

# ---------- host stdin ----------
# Non-blocking host stdin poller. Called from the main loop, not per
# simulator tick, so a benchmark run performs zero syscalls.
proc pollTerminal*(s: Simulator) =
  var fds: array[1, TPollfd]
  fds[0].fd = cint(STDIN_FILENO)
  fds[0].events = POLLIN
  let r = poll(fds[0].addr, Tnfds(1), 0)
  if r <= 0:
    return
  if (fds[0].revents and POLLIN) == 0:
    return
  var buf: array[256, char]
  let n = read(cint(STDIN_FILENO), buf[0].addr, buf.len)
  var i = 0
  while i < n:
    s.terminalFifo.addLast(uint8(buf[i]))
    inc i

# ---------- union-find ----------

proc alloc(s: Simulator): Net =
  result = Net(s.parent.len)
  s.parent.add(result)
  s.nets.add(Wire(value: lZ))

proc root(s: Simulator, n: Net): Net =
  var x = n
  while s.parent[x] != x:
    x = s.parent[x]
  var y = n
  while s.parent[y] != y:
    let z = s.parent[y]
    s.parent[y] = x
    y = z
  return x

proc join(s: Simulator, a, b: Net) =
  if a != Net(0) and b != Net(0):
    s.parent[s.root(b)] = s.root(a)

# ---------- flatten ----------

proc flatten(s: Simulator, d: Design, defIdx: int,
             ins, outs: seq[Net], top: bool) =
  let m = d.definitions[defIdx]
  var map = newSeq[Net](m.nets.int + 1)
  for n in 1 .. m.nets.int:
    map[n] = s.alloc()
  if top:
    s.topMap = map
  for i in 0 ..< ins.len:
    s.join(ins[i], map[m.ins[i].int])
  for i in 0 ..< outs.len:
    s.join(outs[i], map[m.outs[i].int])

  var named = initTable[string, Net]()
  for e in m.elements:
    if e.typ in {gtNODE, gtINOUT}:
      let w = map[e.outs[0].int]
      s.join(w, map[e.ins[0].int])
      if e.name.len > 0:
        if e.name in named:
          s.join(w, named[e.name])
        else:
          named[e.name] = w

  for e0 in m.elements:
    var e = e0
    for i in 0 ..< e.ins.len:
      e.ins[i] = map[e.ins[i].int]
    for i in 0 ..< e.outs.len:
      if e.outs[i] != Net(0):
        e.outs[i] = map[e.outs[i].int]
      else:
        e.outs[i] = s.alloc()

    if e.module >= 0:
      s.flatten(d, e.module, e.ins, e.outs, false)
      continue

    if e.typ == gtSWITCH:
      # Trivial joins jak w C++; sam SWITCH jest bramka stateful (patrz
      # evaluateStateful), ktora w resolve() dynamicznie scala A<->B.
      s.join(e.ins[0], e.outs[1])
      s.join(e.ins[2], e.outs[0])
      # (bez continue - SWITCH nadal trafia do gates)

    # Collect top-level named probes (mirrors C++ flatten).
    if top and e.name.len > 0:
      if e.typ == gtOUTPUT and e.ins.len > 0:
        s.probes.add((e.name, e.ins[0]))
      elif e.typ in {gtNODE, gtINPUT} and e.outs.len > 0:
        s.probes.add((e.name, e.outs[0]))

    if e.typ in {gtNODE, gtOUTPUT, gtINOUT, gtBUS, gtDISPLAY, gtOSCILLOSCOPE}:
      continue
    if e.typ == gtINPUT and not top:
      continue

    var g: Gate
    g.e = e
    # Zgodnie z C++ flatten(): kazda pamiec ROM/RAM rozszerzana do 2^aw
    # (pady zerami). Bez tego odczyt poza dlugoscia seq jest UB.
    if g.e.typ in {gtROM, gtRAM}:
      let depth = 1 shl g.e.aw.int
      if g.e.memory.len < depth:
        g.e.memory.setLen(depth)
    g.stored = lL
    g.lastClock = lL
    g.lastData = lX
    g.dataChanged = -1000000000
    g.edge = -1000000000
    g.address = -2
    g.settledAddress = -2
    g.activeLow = e.activeLow
    g.driverBegin = s.drivers.len.int32
    g.driverCount = e.outs.len.int32
    for n in e.outs:
      s.drivers.add(Driver(net: n, value: lZ, target: lZ))
    s.gates.add(g)

# ---------- event queue ----------

proc enqueue(s: Simulator, at: Time, kind: uint8, id: int32,
             v: Logic, gen: uint64, weak: bool) =
  let e = Event(generation: gen, id: id, kind: kind, value: v, weak: weak)
  for k in s.bucketHead ..< s.buckets.len:
    if s.buckets[k].at == at:
      s.buckets[k].events.add(e)
      return
    if s.buckets[k].at > at:
      var nb: Bucket
      nb.at = at
      nb.events = @[e]
      s.buckets.insert(nb, k)
      return
  var nb: Bucket
  nb.at = at
  nb.events = @[e]
  s.buckets.add(nb)

proc schedule(s: Simulator, id: int32, v: Logic, dt: Time, weak = false) =
  let d = s.drivers[id.int].addr
  if d.pending and d.target == v and d.targetWeak == weak:
    return
  if not d.pending and d.value == v and d.weak == weak:
    return
  d.generation.inc
  d.pending = false
  d.target = v
  d.targetWeak = weak
  if d.value == v and d.weak == weak:
    return
  d.pending = true
  s.enqueue(s.now + dt, 0'u8, id, v, d.generation, weak)

# ---------- resolve ----------

proc markDirty(s: Simulator, gate: int32) {.inline.} =
  if s.dirty[gate.int]:
    return
  s.dirty[gate.int] = true
  s.dirtyGates.add(gate)

proc resolve(s: Simulator) =
  for n in s.touched:
    if s.touchedFlag[n.int] != 0:
      continue
    s.touchedFlag[n.int] = 1
    s.touchedList.add(n)
  s.touched.setLen(0)

  for n in s.touchedList:
    let w = s.nets[n.int].addr
    if w.drivers.len == 1:
      let d = s.drivers[w.drivers[0].int]
      if d.value == w.value and d.weak == w.weak:
        continue
      w.value = d.value
      w.weak = d.weak
      for u in w.users:
        s.markDirty(u)
      continue
    var strongV = lZ
    var weakV = lZ
    for id in w.drivers:
      let d = s.drivers[id.int]
      if d.value == lZ:
        continue
      if d.weak:
        if weakV == lZ:
          weakV = d.value
        elif weakV != d.value:
          weakV = lX
      else:
        if strongV == lZ:
          strongV = d.value
        elif strongV != d.value:
          strongV = lX
    let v = if strongV == lZ: weakV else: strongV
    let isWeak = strongV == lZ
    if v == w.value and isWeak == w.weak:
      continue
    w.value = v
    w.weak = isWeak
    for u in w.users:
      s.markDirty(u)

  for n in s.touchedList:
    s.touchedFlag[n.int] = 0
  s.touchedList.setLen(0)

# ---------- delay ----------

proc delayFor(s: Simulator, g: Gate): Time =
  if g.e.cycles >= 0:
    # cycles/pc sa w krokach biezacej technologii (profile.tick), nie w ns.
    # Zgodne z C++: llround(cycles * profile.tick).
    return Time(g.e.cycles * float(s.profile.tick) + 0.5)
  if g.e.ns >= 0:
    return Time(g.e.ns * 1000.0 + 0.5)
  case g.e.typ
  of gtDFF:
    return s.profile.cq
  of gtSWITCH:
    return s.profile.sw
  else:
    return s.profile.gate

# ---------- pure gate evaluation ----------

proc evaluatePure(s: Simulator, id: int32) =
  let g = s.gates[id.int].addr
  let t = g.e.typ
  var v: array[MAX_GATE_INPUTS, Logic]
  let nin = g.e.ins.len
  for i in 0 ..< nin:
    v[i] = s.nets[g.e.ins[i].int].value

  var outs: array[4, Logic]
  var nout = 1
  outs[0] = lX
  let dt = g.delay
  let ins0 = g.e.ins

  case t
  of gtTBUF:
    var en = binary(v[1])
    if g.activeLow:
      en = inv(en)
    outs[0] = if en == lH: v[0] else: lZ
  of gtOC:
    outs[0] = if v[0] == lH: lL else: lZ
  of gtNOT:
    outs[0] = inv(binary(v[0]))
  of gtBUF:
    outs[0] = binary(v[0])
  of gtAND, gtNAND:
    var r = lH
    for i in 0 ..< nin:
      let x = binary(v[i])
      if x == lL:
        r = lL
        break
      if x == lX:
        r = lX
    outs[0] = if t == gtNAND: inv(r) else: r
  of gtOR, gtNOR:
    var r = lL
    for i in 0 ..< nin:
      let x = binary(v[i])
      if x == lH:
        r = lH
        break
      if x == lX:
        r = lX
    outs[0] = if t == gtNOR: inv(r) else: r
  of gtXOR:
    var r = lL
    for i in 0 ..< nin:
      let x = binary(v[i])
      if x == lX or r == lX:
        r = lX
      elif x == lH:
        r = inv(r)
    outs[0] = r
  of gtMUX2, gtMUX4, gtDMUX2, gtDMUX4:
    for i in 0 ..< nin:
      if v[i] == lZ:
        v[i] = lX
    let dem    = t == gtDMUX2 or t == gtDMUX4
    let count  = if t == gtMUX4 or t == gtDMUX4: 4 else: 2
    let offset = if dem: 1 else: count
    nout       = if dem: count else: 1
    for p in 0 ..< nout:
      outs[p] = lX
    var first = true
    for c in 0 ..< count:
      if v[offset] != lX and ord(v[offset]) != (c and 1):
        continue
      if count == 4 and v[offset + 1] != lX and
         ord(v[offset + 1]) != (c shr 1):
        continue
      for p in 0 ..< nout:
        let x: Logic =
          if dem:
            (if p == c: v[0] else: lL)
          else:
            v[c]
        if first or outs[p] == x:
          outs[p] = x
        else:
          outs[p] = lX
      first = false
  else:
    discard

  let isWeak = (t == gtTBUF) and s.nets[ins0[0].int].weak
  for p in 0 ..< nout:
    s.schedule(g.driverBegin + int32(p), outs[p], dt, isWeak)

# ---------- stateful gate evaluation ----------

proc evaluateStateful(s: Simulator, id: int32) =
  let g = s.gates[id.int].addr
  let t = g.e.typ
  var v: array[MAX_GATE_INPUTS, Logic]
  let nin = g.e.ins.len
  for i in 0 ..< nin:
    v[i] = s.nets[g.e.ins[i].int].value
  let dt = g.delay
  let drvBegin = g.driverBegin.int

  case t
  of gtDFF:
    let clk = binary(v[0])
    let data = binary(v[1])
    let setupD =
      if g.e.setup >= 0: Time(g.e.setup * 1000 + 0.5)
      else: s.profile.setup
    let holdD =
      if g.e.hold >= 0: Time(g.e.hold * 1000 + 0.5)
      else: s.profile.hold
    if data != g.lastData:
      g.dataChanged = s.now
      if g.edge >= 0 and s.now - g.edge < holdD:
        g.stored = lX
      g.lastData = data
    if not s.initializing and clk == lH and g.lastClock != lH:
      g.edge = s.now
      if s.now - g.dataChanged < setupD:
        g.stored = lX
      else:
        g.stored = data
    g.lastClock = clk
    s.schedule(drvBegin.int32, g.stored, dt)
    s.schedule(drvBegin.int32 + 1, inv(g.stored), dt)
  of gtDLATCH:
    let en = binary(v[1])
    let data = binary(v[0])
    if v[0] != lZ:
      if en == lH:
        g.stored = data
      elif en == lX and data != g.stored:
        g.stored = lX
    s.schedule(drvBegin.int32, g.stored, dt)
    s.schedule(drvBegin.int32 + 1, inv(g.stored), dt)

  of gtTERMINAL:
    # Matches src/terminal.hpp and the C++ simulator TERMINAL path:
    #   Apple-1 PIA (ioMode == "apple1"):
    #     reg 0 KBD     read: key value
    #     reg 1 KBDCR   read: kbd control | (key ready ? 0x80 : 0); write: control
    #     reg 2 DSP     write: char (requires display_control bit 2)
    #     reg 3 DSPCR   write: display control
    #   ACIA 6551-lite (ioMode == "acia"), used by eWoz:
    #     reg 0 DATA    read: key value; write: char
    #     reg 1 STATUS  read: 0x10 | (key ready ? 0x08 : 0); write: reset
    #     reg 2 CMD     read/write kbd control
    #     reg 3 CTRL    read/write display control
    let acia = g.e.ioMode == "acia"

    var a: uint64 = 0
    var aValid = true
    for b in 0 ..< 16:
      let x = v[b]
      if x != lL and x != lH:
        aValid = false
        break
      if x == lH:
        a = a or (1'u64 shl b)
    var reg = -1
    if aValid:
      let base = g.e.ioBase.uint64
      if a >= base and a < base + 4:
        reg = int(a - base)
    let rd = reg >= 0 and v[24] == lL and v[25] == lH
    let wr = reg >= 0 and v[25] == lL and v[24] == lH

    # Debug output for TERMINAL reads/writes, matching C++ Terminal::evaluate() debug output.
    # if reg >= 0:
    #   stderr.writeLine("[TERM] t=", s.now, " reg=", reg,
    #                    " rd=", rd, " wr=", wr,
    #                    " v24=", digit(v[24]), " v25=", digit(v[25]))

    # --- WRITE latch on falling /WR, commit on rising /WR ---
    if wr and not g.terminalWrite:
      var bv: uint8 = 0
      for b in 0 ..< 8:
        if v[16 + b] == lH:
          bv = bv or (1'u8 shl b)
      g.terminalWrite = true
      g.terminalWriteReg = reg
      g.terminalWriteValue = bv
    if g.terminalWrite and not wr:
      # Only commit if /WR is now actually high AND the address is still
      # in the window at the same register. Matches C++ commit conditions.
      if v[25] == lH and reg == g.terminalWriteReg:
        let wreg = g.terminalWriteReg
        let wval = g.terminalWriteValue
        if acia:
          case wreg
          of 0:
            s.emitTerminalChar(wval)
          of 1:
            s.terminalFifo.clear()
            s.terminalKbdControl = 0
          of 2:
            s.terminalKbdControl = wval
          of 3:
            s.terminalDispControl = wval
          else:
            discard
        else:
          case wreg
          of 1:
            s.terminalKbdControl = wval
          of 2:
            if (s.terminalDispControl and 0x04) != 0:
              s.emitTerminalChar(wval)
          of 3:
            s.terminalDispControl = wval
          else:
            discard
      g.terminalWrite = false

    # --- READ: consume on rising /RD (or address change) ---
    if g.terminalRead and (not rd or reg != g.terminalReadReg):
      if g.terminalKeyLatched and s.terminalFifo.len > 0:
        discard s.terminalFifo.popFirst()
      g.terminalRead = false

    # --- READ latch on falling /RD ---
    if rd and not g.terminalRead:
      g.terminalRead = true
      g.terminalReadReg = reg
      g.terminalKeyLatched = false   # unconditionally reset, then set for reg 0
      if acia:
        case reg
        of 0:
          if s.terminalFifo.len > 0:
            g.terminalReadValue = s.terminalFifo[0]
            g.terminalKeyLatched = true
          else:
            g.terminalReadValue = 0'u8
        of 1:
          var bv: uint8 = 0x10'u8
          if s.terminalFifo.len > 0:
            bv = bv or 0x08'u8
          g.terminalReadValue = bv
        of 2:
          g.terminalReadValue = s.terminalKbdControl
        of 3:
          g.terminalReadValue = s.terminalDispControl
        else:
          g.terminalReadValue = 0'u8
      else:
        case reg
        of 0:
          if s.terminalFifo.len > 0:
            g.terminalReadValue = s.terminalFifo[0]
            g.terminalKeyLatched = true
          else:
            g.terminalReadValue = 0'u8
        of 1:
          var bv = s.terminalKbdControl and 0x7f'u8
          if s.terminalFifo.len > 0:
            bv = bv or 0x80'u8
          g.terminalReadValue = bv
        of 2:
          g.terminalReadValue = 0'u8
        of 3:
          g.terminalReadValue = s.terminalDispControl
        else:
          g.terminalReadValue = 0'u8

    # --- drive data outputs: latched value while /RD low, else Z ---
    let rv = g.terminalReadValue
    for b in 0 ..< 8:
      var outV = lZ
      if rd:
        if ((rv shr b) and 1) == 1:
          outV = lH
        else:
          outV = lL
      s.schedule(g.driverBegin.int32 + int32(b), outV, 0)

  of gtROM, gtRAM:
    var memAddr: int64 = 0
    var valid = true
    for b in 0 ..< g.e.aw.int:
      let x = v[b]
      if x != lL and x != lH:
        valid = false
        break
      if x == lH:
        memAddr = memAddr or (1'i64 shl b)
    if not valid:
      memAddr = -1
    var changed = false
    if t == gtRAM:
      let we = v[g.e.aw.int + g.e.dw.int]
      if we == lL:
        var wvalid = memAddr >= 0
        var word: uint64 = 0
        for b in 0 ..< g.e.dw.int:
          let x = v[g.e.aw.int + b]
          if x != lL and x != lH:
            wvalid = false
            break
          if x == lH:
            word = word or (1'u64 shl b)
        if wvalid:
          let i = memAddr.int
          changed = g.e.memory[i] != word
          g.e.memory[i] = word
    if memAddr != g.address:
      g.address = memAddr
      if g.memoryDelay == 0:
        g.ready = true
        g.settledAddress = memAddr
        if memAddr >= 0:
          g.readWord = g.e.memory[memAddr.int]
        else:
          g.readWord = 0
      else:
        g.readGeneration.inc
        s.enqueue(s.now + g.memoryDelay, 2'u8, id, lX,
                  g.readGeneration, false)
    elif changed and g.settledAddress == memAddr and memAddr >= 0:
      g.readWord = g.e.memory[memAddr.int]

    let oeIdx =
      if t == gtROM: g.e.aw.int
      else: g.e.aw.int + g.e.dw.int + 1
    let oe = v[oeIdx]
    for b in 0 ..< g.e.dw.int:
      var outV = lZ
      if oe == lL:
        if not g.ready:
          outV = lZ
        elif g.settledAddress < 0:
          outV = lX
        elif ((g.readWord shr b) and 1) == 1:
          outV = lH
        else:
          outV = lL
      elif oe != lH:
        outV = lX
      s.schedule(g.driverBegin.int32 + int32(b), outV, 0)
  else:
    discard

proc evaluateDirty(s: Simulator) =
  if s.dirtyGates.len == 0:
    return
  for g in s.dirtyGates:
    if isPure(s.gates[g.int].e.typ):
      s.evaluatePure(g)
    else:
      s.evaluateStateful(g)
  for g in s.dirtyGates:
    s.dirty[g.int] = false
  s.dirtyGates.setLen(0)

# ---------- main loop ----------

proc advance*(s: Simulator, duration: Time) =
  let stopAt = s.now + duration
  var sameTime = 0
  var prev: Time = -1
  s.evaluateDirty()
  while s.bucketHead < s.buckets.len and
        s.buckets[s.bucketHead].at <= stopAt:
    let t = s.buckets[s.bucketHead].at
    s.now = t
    if t != prev:
      sameTime = 0
      prev = t
    var changed = false
    var i = 0
    while i < s.buckets[s.bucketHead].events.len:
      let e = s.buckets[s.bucketHead].events[i]
      inc i
      sameTime.inc
      if sameTime > 1_000_000:
        raise newException(ValueError, "zero-delay oscillation")
      case e.kind
      of 0'u8:
        let d = s.drivers[e.id.int].addr
        if d.generation != e.generation:
          continue
        d.pending = false
        d.value = e.value
        d.weak = e.weak
        s.touched.add(d.net)
        changed = true
      of 1'u8:
        let g = s.gates[e.id.int].addr
        if s.autoClock:
          if g.fastClock:
            let dr = g.driverBegin.int
            let n = s.drivers[dr].net
            let nv = inv(s.drivers[dr].value)
            s.drivers[dr].value = nv
            s.drivers[dr].target = nv
            s.drivers[dr].pending = false
            s.drivers[dr].weak = false
            if s.nets[n.int].value != nv or s.nets[n.int].weak:
              s.nets[n.int].value = nv
              s.nets[n.int].weak = false
              for u in s.nets[n.int].users:
                s.markDirty(u)
          else:
            s.schedule(g.driverBegin,
                       inv(s.drivers[g.driverBegin.int].value), 0)
        s.enqueue(s.now + g.period, 1'u8, e.id, lX, 0, false)
      of 2'u8:
        let g = s.gates[e.id.int].addr
        if e.generation != g.readGeneration:
          continue
        g.ready = true
        g.settledAddress = g.address
        if g.address >= 0:
          g.readWord = g.e.memory[g.address.int]
        s.markDirty(e.id)
      else:
        discard
    s.buckets[s.bucketHead].events.setLen(0)
    s.bucketHead.inc
    if changed:
      s.resolve()
    s.evaluateDirty()
  if s.bucketHead > 64 and s.bucketHead * 2 > s.buckets.len:
    s.buckets = s.buckets[s.bucketHead .. ^1]
    s.bucketHead = 0
  s.now = stopAt

# ---------- construction ----------

proc newSimulator*(d: Design, prof: Profile): Simulator =
  new(result)
  result.profile = prof
  result.autoClock = true
  result.initializing = true
  result.terminalOut = stdout
  result.terminalFifo = initDeque[uint8](64)
  result.probes = @[]
  result.terminalKbdControl = 0
  result.terminalDispControl = 0
  result.terminalLastNl = false
  result.lastPollWall = 0.0
  result.pollInterval = 0.005
  discard result.alloc()
  result.flatten(d, d.root, @[], @[], true)
  # Po wszystkich joinach sprowadź mapę top do reprezentantów, żeby main
  # mógł indeksować nazwane nete workspace bez wywoływania root().
  for i in 1 ..< result.topMap.len:
    if result.topMap[i] != Net(0):
      result.topMap[i] = result.root(result.topMap[i])

  result.touchedFlag = newSeq[uint8](result.nets.len)
  result.touched = newSeqOfCap[Net](256)
  result.touchedList = newSeqOfCap[Net](256)
  result.buckets = newSeqOfCap[Bucket](32)

  for i in 0 ..< result.gates.len:
    let g = result.gates[i].addr
    for j in 0 ..< g.e.ins.len:
      g.e.ins[j] = result.root(g.e.ins[j])
    for j in 0 ..< g.e.outs.len:
      g.e.outs[j] = result.root(g.e.outs[j])
  for i in 0 ..< result.drivers.len:
    result.drivers[i].net = result.root(result.drivers[i].net)
    result.nets[result.drivers[i].net.int].drivers.add(i.int32)
  for i in 0 ..< result.gates.len:
    for n in result.gates[i].e.ins:
      result.nets[n.int].users.add(i.int32)
  for i in 0 ..< result.nets.len:
    var seen = initHashSet[int32]()
    var uniq: seq[int32]
    for u in result.nets[i].users:
      if not seen.containsOrIncl(u):
        uniq.add(u)
    result.nets[i].users = uniq

  for i in 0 ..< result.gates.len:
    let g = result.gates[i].addr
    g.delay = result.delayFor(g[])
    case g.e.typ
    of gtCLK:
      g.period = Time(result.profile.tick) * Time(g.e.period)
    of gtROM, gtRAM:
      g.memoryDelay = Time(g.e.memoryNs * 1000.0 + 0.5)
    else:
      discard

  for i in 0 ..< result.gates.len:
    let g = result.gates[i].addr
    if g.e.typ != gtCLK:
      continue
    if g.driverCount == 0:
      continue
    let dr = g.driverBegin.int
    let n = result.drivers[dr].net
    if result.nets[n.int].drivers.len == 1:
      g.fastClock = true

  result.dirty = newSeq[bool](result.gates.len)
  result.dirtyGates = newSeqOfCap[int32](result.gates.len)
  for i in 0 ..< result.gates.len:
    result.markDirty(i.int32)

  for i in 0 ..< result.gates.len:
    let g = result.gates[i].addr
    let t = g.e.typ
    if t in {gtINPUT, gtCLK, gtH, gtL, gtPULLUP, gtPULLDOWN}:
      let initV = if t in {gtINPUT, gtCLK, gtH, gtPULLUP}: lH else: lL
      let isWeak = t in {gtPULLUP, gtPULLDOWN}
      for d in 0 ..< g.driverCount:
        result.schedule(g.driverBegin + int32(d), initV, 0, isWeak)

  # # --- DIAGNOSTIC (tymczasowy) ---
  # block:
  #   stderr.writeLine("[profile] name=", result.profile.name,
  #                    " tick=", result.profile.tick,
  #                    " gate=", result.profile.gate,
  #                    " cq=", result.profile.cq)
  #   var shown = 0
  #   for i in 0 ..< result.gates.len:
  #     let g = result.gates[i].addr
  #     if g.e.cycles >= 0 and shown < 20:
  #       stderr.writeLine("[delay] gate#", i,
  #                        " typ=", $g.e.typ,
  #                        " cycles=", g.e.cycles,
  #                        " ns=", g.e.ns,
  #                        " computed=", g.delay, " ps")
  #       inc shown

  result.advance(0)
  var guard = 0
  while result.bucketHead < result.buckets.len:
    guard.inc
    if guard > 10000:
      raise newException(ValueError, "startup did not settle")
    let nextAt = result.buckets[result.bucketHead].at
    if nextAt > 100_000_000:
      raise newException(ValueError, "startup >100us")
    result.advance(nextAt - result.now)

  # Root probe nets through union-find now that all joins are done.
  for k in 0 ..< result.probes.len:
    let rooted = result.root(result.probes[k].net)
    result.probes[k] = (result.probes[k].name, rooted)

  result.now = 0
  result.initializing = false
  for i in 0 ..< result.gates.len:
    let g = result.gates[i].addr
    g.dataChanged = -1000000000
    g.edge = -1000000000
    if g.e.typ == gtCLK:
      result.enqueue(result.profile.tick * Time(g.e.period),
                     1'u8, int32(i), lX, 0, false)

proc topNetValue*(s: Simulator, localN: int): Logic =
  ## Bieżąca wartość netu top po lokalnym numerze w definicji workspace.
  ## Ten sam numer przyjmuje findNetName() z design.nim.
  if localN <= 0 or localN >= s.topMap.len:
    return lZ
  let n = s.topMap[localN]
  if n == Net(0):
    return lZ
  return s.nets[n.int].value

proc topNetCount*(s: Simulator): int =
  return s.topMap.len

proc dumpProbes*(s: Simulator) =
  ## Print every top-level named probe with its current value to stdout.
  echo "--- probes (", s.probes.len, ") ---"
  for (nm, n) in s.probes:
    echo nm, "=", digit(s.nets[n.int].value)

proc probeValue*(s: Simulator, name: string): char =
  for (nm, n) in s.probes:
    if nm == name:
      return digit(s.nets[n.int].value)
  return '?'