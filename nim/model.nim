type
  Time* = int64
  Net* = uint32

  Logic* = enum lL, lH, lX, lZ

const digitChars* = "01xz"

proc digit*(v: Logic): char {.inline.} = digitChars[ord(v)]

type
  GateType* = enum
    gtUNKNOWN
    gtAND, gtOR, gtXOR, gtNAND, gtNOR, gtNOT, gtBUF, gtTBUF, gtOC
    gtMUX2, gtMUX4, gtDMUX2, gtDMUX4
    gtDFF, gtDLATCH, gtSWITCH
    gtH, gtL, gtPULLUP, gtPULLDOWN, gtCLK, gtINPUT
    gtNODE, gtINOUT, gtOUTPUT, gtBUS, gtDISPLAY, gtOSCILLOSCOPE
    gtROM, gtRAM, gtTERMINAL, gtMODULE

  Element* = object
    typ*: GateType
    name*: string
    ins*: seq[Net]
    outs*: seq[Net]
    module*: int
    cycles*, ns*, setup*, hold*: float
    ioMode*: string
    period*: uint32
    aw*, dw*: uint32
    ioBase*: uint32
    memoryNs*: float
    activeLow*: bool
    memory*: seq[uint64]

  Definition* = object
    name*: string
    nets*: uint32
    ins*, outs*: seq[Net]
    elements*: seq[Element]

  Design* = object
    name*: string
    definitions*: seq[Definition]
    root*: int

  Profile* = object
    name*: string
    tick*, gate*, cq*, setup*, hold*, sw*: Time

proc profileLvc*(): Profile =
  Profile(name: "LVC", tick: 2500, gate: 2000, cq: 2500,
          setup: 1000, hold: 200, sw: 4000)

proc profileFpga*(): Profile =
  Profile(name: "FPGA", tick: 1250, gate: 500, cq: 500,
          setup: 300, hold: 100, sw: 500)