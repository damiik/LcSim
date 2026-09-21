; ============================================================
; LUNAR MODULE v4 - panel exactly according to new layout
; 65C02-like CPU + ACIA, no interrupts, polled input
; Terminal: ANSI/VT-like, 40x24
; Start in eWoz: 0500R
;
; Controls:
;   j/k   decrease/increase throttle
;   0..9  direct throttle
;   a/d   RCS translation
;   q     quit to monitor
;   r     restart after mission end
; ============================================================

ACIA_DATA   = $5000
ACIA_STATUS = $5001

; ------------------------------------------------------------
; Zero page
; ------------------------------------------------------------
LALT    = $30       ; altitude, metres
LVEL    = $31       ; vertical velocity, signed, + = down
LFUEL   = $32       ; fuel units
LTHR    = $33       ; throttle 0..9
LSTATE  = $34       ; 0=fly, 1=landed OK, 2=crash, 3=off-pad
LFRAME  = $35       ; physics frame divider
SURFPOS = $37       ; terrain viewport offset
SURFOLD = $38       ; previous terrain viewport offset
LROW    = $39       ; current lander row
LOLD    = $3A       ; previous lander row
GOROW   = $3B
GOCOL   = $3C
TXTL    = $3D
TXTH    = $3E
TMP     = $3F
TMP2    = $40
FUELACC = $50       ; fuel burn accumulator
DIRTY   = $51       ; redraw request

; ------------------------------------------------------------
; Simulation constants
; ------------------------------------------------------------
ALT_INIT   = 180
ALT_MAX    = 180
ALT_LIMIT  = 181
ALT_SCALE  = 12     ; metres per screen row

FUEL_INIT  = 70
FUEL_RATE  = 12

VEL_MAX    = 20
VEL_LIMIT  = 21
VEL_MIN    = $EC    ; -20 signed

SAFE_VEL   = 3
SAFE_LIMIT = 4      ; SAFE_VEL + 1
LOW_FUEL   = 15
PHYS_DIV   = 4

; ------------------------------------------------------------
; Screen constants
; ------------------------------------------------------------
GROUND_ROW        = 19
FLIGHT_BOTTOM_ROW = 18
FLIGHT_TOP_ROW    = 2

VIEW_COL      = 21
LANDER_COL    = 31
LANDER_OFFSET = 10

PAD_INDEX = 30
SURF_INIT = 20
SURF_MAX  = 40

STATE_FLY   = 0
STATE_OK    = 1
STATE_CRASH = 2
STATE_OFF   = 3

    .org $0
    .byte $00

    .org $0500

; ============================================================
; START
; ============================================================
START:
    LDX #$FF
    TXS

    LDA #ALT_INIT
    STA LALT

    LDA #FUEL_INIT
    STA LFUEL

    LDA #0
    STA LVEL
    STA LTHR
    STA LSTATE
    STA LFRAME
    STA FUELACC
    STA DIRTY

    LDA #SURF_INIT
    STA SURFPOS

    LDA #$FF
    STA SURFOLD

    LDA #FLIGHT_BOTTOM_ROW
    STA LOLD

    JSR CLS
    JSR HIDECUR
    JSR DRAWS
    JSR DRAWDYN

    LDA #0
    STA DIRTY

; ============================================================
; MAIN LOOP
; ============================================================
MAIN:
    JSR POLLKEY
    JSR DELAY

    LDA LSTATE
    BNE MAIN_DRAWCHECK

    INC LFRAME
    LDA LFRAME
    CMP #PHYS_DIV
    BCC MAIN_DRAWCHECK

    LDA #0
    STA LFRAME
    JSR PHYSICS
    LDA #1
    STA DIRTY

MAIN_DRAWCHECK:
    LDA DIRTY
    BEQ MAIN
    JSR DRAWDYN
    LDA #0
    STA DIRTY
    BRA MAIN

; ============================================================
; POLLKEY
; ============================================================
POLLKEY:
    LDA ACIA_STATUS
    AND #$08
    BEQ PK_DONE

    LDA ACIA_DATA
    STA TMP

    LDA LSTATE
    BNE PK_END

    LDA TMP
    CMP #'q'
    BNE N_DOQUIT
    JMP DOQUIT
N_DOQUIT:
    CMP #'Q'
    BNE N_DOQUIT2
    JMP DOQUIT

N_DOQUIT2:
    CMP #'j'
    BEQ THR_DOWN
    CMP #'J'
    BEQ THR_DOWN

    CMP #'k'
    BEQ THR_UP
    CMP #'K'
    BEQ THR_UP

    CMP #'a'
    BEQ RCS_LEFT
    CMP #'A'
    BEQ RCS_LEFT

    CMP #'d'
    BEQ RCS_RIGHT
    CMP #'D'
    BEQ RCS_RIGHT

    CMP #'0'
    BCC PK_DONE
    CMP #58
    BCS PK_DONE

    SEC
    SBC #'0'
    TAX

    LDA LFUEL
    BNE PK_SETTHR
    CPX #0
    BNE PK_DONE

PK_SETTHR:
    STX LTHR
    LDA #1
    STA DIRTY

PK_DONE:
    RTS

PK_END:
    LDA TMP
    CMP #'q'
    BEQ DOQUIT
    CMP #'Q'
    BEQ DOQUIT
    CMP #'r'
    BEQ RESTART
    CMP #'R'
    BEQ RESTART
    RTS

THR_DOWN:
    LDA LTHR
    BEQ TD_DONE
    DEC LTHR
    LDA #1
    STA DIRTY
TD_DONE:
    RTS

THR_UP:
    LDA LFUEL
    BEQ TU_DONE
    LDA LTHR
    CMP #9
    BCS TU_DONE
    INC LTHR
    LDA #1
    STA DIRTY
TU_DONE:
    RTS

RCS_LEFT:
    LDA SURFPOS
    BEQ RL_DONE
    DEC SURFPOS
    LDA #1
    STA DIRTY
RL_DONE:
    RTS

RCS_RIGHT:
    LDA SURFPOS
    CMP #SURF_MAX
    BCS RR_DONE
    INC SURFPOS
    LDA #1
    STA DIRTY
RR_DONE:
    RTS

DOQUIT:
    JMP QUIT

RESTART:
    JMP START

; ============================================================
; DELAY
; ============================================================
DELAY:
    LDX #$01
DL_OUT:
    LDY #$FF
DL_IN:
    DEY
    BNE DL_IN
    DEX
    BNE DL_OUT
    RTS

; ============================================================
; PHYSICS
; ============================================================
PHYSICS:
    LDA LSTATE
    BNE PH_EXIT

    LDA LFUEL
    BNE PH_HAVE_FUEL
    LDA #0
    STA LTHR

PH_HAVE_FUEL:
    LDX LTHR
    LDA THR_DELTA,X
    CLC
    ADC LVEL
    STA LVEL
    JSR CLAMPVEL

    ; Fuel burn proportional to throttle.
    LDA LTHR
    BEQ PH_NOBURN
    CLC
    ADC FUELACC
    STA FUELACC
    CMP #FUEL_RATE
    BCC PH_NOBURN

    SEC
    SBC #FUEL_RATE
    STA FUELACC

    LDA LFUEL
    BEQ PH_NOBURN
    DEC LFUEL

PH_NOBURN:
    LDA LVEL
    BMI PH_ASCEND

    ; Descending.
    LDA LALT
    SEC
    SBC LVEL
    STA LALT
    BCC PH_GROUND

    LDA LALT
    BEQ PH_GROUND

    CMP #ALT_LIMIT
    BCC PH_EXIT

    LDA #ALT_MAX
    STA LALT
    RTS

PH_ASCEND:
    ; Ascending: add absolute upward velocity.
    LDA #0
    SEC
    SBC LVEL
    CLC
    ADC LALT
    STA LALT
    BCS PH_CLAMP_HIGH

    CMP #ALT_LIMIT
    BCC PH_EXIT

PH_CLAMP_HIGH:
    LDA #ALT_MAX
    STA LALT

PH_EXIT:
    RTS

PH_GROUND:
    LDA #0
    STA LALT

    LDA LVEL
    BMI PH_CHECKPAD
    CMP #SAFE_LIMIT
    BCS PH_CRASH

PH_CHECKPAD:
    JSR GETSURF
    CMP #'X'
    BEQ PH_OK
    CMP #'='
    BEQ PH_OK

    LDA #STATE_OFF
    STA LSTATE
    RTS

PH_OK:
    LDA #STATE_OK
    STA LSTATE
    RTS

PH_CRASH:
    LDA #STATE_CRASH
    STA LSTATE
    RTS

; ============================================================
; CLAMPVEL
; ============================================================
CLAMPVEL:
    LDA LVEL
    BPL CV_POS

    CMP #VEL_MIN
    BCS CV_RTS
    LDA #VEL_MIN
    STA LVEL
    RTS

CV_POS:
    CMP #VEL_LIMIT
    BCC CV_RTS
    LDA #VEL_MAX
    STA LVEL

CV_RTS:
    RTS

; ============================================================
; GETSURF - terrain character under the lander
; ============================================================
GETSURF:
    LDA #<SURFACE
    CLC
    ADC SURFPOS
    STA TXTL

    LDA #>SURFACE
    ADC #0
    STA TXTH

    LDA TXTL
    CLC
    ADC #LANDER_OFFSET
    STA TXTL
    BCC GS_NOHIGH
    INC TXTH

GS_NOHIGH:
    LDX #0
    LDA (TXTL,X)
    RTS

; ============================================================
; DRAWDYN
; ============================================================
DRAWDYN:
    JSR DRAWALT
    JSR DRAWVEL
    JSR DRAWFUEL
    JSR DRAWTHR
    JSR DRAWPAD
    JSR DRAWSTAT
    JSR DRAWLANDER
    JSR DRAWGROUND
    RTS

; ============================================================
; DRAWALT - row 3, digits start in column 8
; Pattern: | ALT  000 m       |
; ============================================================
DRAWALT:
    LDA #3
    STA GOROW
    LDA #8
    STA GOCOL
    JSR GOTOXY

    LDA LALT
    JSR PRDEC3
    RTS

; ============================================================
; DRAWVEL - row 4, sign column 7, digits column 8
; Pattern: | VEL +000 m/s     |
; ============================================================
DRAWVEL:
    LDA #4
    STA GOROW
    LDA #7
    STA GOCOL
    JSR GOTOXY

    LDA LVEL
    BPL DV_POS

    LDA #'-'
    STA ACIA_DATA
    LDA #0
    SEC
    SBC LVEL
    BRA DV_MAG

DV_POS:
    LDA #'+'
    STA ACIA_DATA
    LDA LVEL

DV_MAG:
    JSR PRDEC3
    RTS

; ============================================================
; DRAWFUEL - row 6, digits start in column 8
; Pattern: | FUEL 070 %       |
; ============================================================
DRAWFUEL:
    LDA #6
    STA GOROW
    LDA #8
    STA GOCOL
    JSR GOTOXY

    LDA LFUEL
    JSR PRDEC3
    RTS

; ============================================================
; DRAWTHR - row 7, bar starts in column 9
; Pattern: | THR  <##########>|
; ============================================================
DRAWTHR:
    LDA #7
    STA GOROW
    LDA #9
    STA GOCOL
    JSR GOTOXY

    ; 10 visible bar segments for throttle 0..9.
    LDA LTHR
    BEQ THR_ZERO
    CLC
    ADC #1
    STA TMP
    BRA THR_DRAW

THR_ZERO:
    LDA #0
    STA TMP

THR_DRAW:
    LDY #0
THR_LOOP:
    CPY TMP
    BCS THR_EMPTY

    LDA #'#'
    BRA THR_OUT

THR_EMPTY:
    LDA #'.'

THR_OUT:
    STA ACIA_DATA
    INY
    CPY #10
    BCC THR_LOOP

    RTS

; ============================================================
; DRAWPAD - row 9, digits start in column 8
; Pattern: | PAD  000 m       |
; ============================================================
DRAWPAD:
    LDA #9
    STA GOROW
    LDA #8
    STA GOCOL
    JSR GOTOXY

    ; centre = SURFPOS + LANDER_OFFSET
    LDA SURFPOS
    CLC
    ADC #LANDER_OFFSET
    STA TMP

    CMP #PAD_INDEX
    BEQ DP_ZERO
    BCC DP_RIGHT

    LDA TMP
    SEC
    SBC #PAD_INDEX
    BRA DP_DIST

DP_RIGHT:
    LDA #PAD_INDEX
    SEC
    SBC TMP

DP_DIST:
    ; *10 metres
    ASL
    STA TMP2
    ASL
    ASL
    CLC
    ADC TMP2
    BRA DP_PRINT

DP_ZERO:
    LDA #0

DP_PRINT:
    JSR PRDEC3
    RTS

; ============================================================
; DRAWSTAT - row 12, message starts in column 6
; Pattern: STAT CRASH: TOO FAST
; ============================================================
DRAWSTAT:
    LDA #12
    STA GOROW
    LDA #6
    STA GOCOL
    JSR GOTOXY

    ; Clear 15-character message field.
    LDX #15
DS_CLEAR:
    LDA #' '
    STA ACIA_DATA
    DEX
    BNE DS_CLEAR

    LDA #12
    STA GOROW
    LDA #6
    STA GOCOL
    JSR GOTOXY

    LDA LSTATE
    CMP #STATE_OK
    BEQ DS_LAND
    CMP #STATE_CRASH
    BEQ DS_CRASH
    CMP #STATE_OFF
    BEQ DS_OFF

    ; Urgent warning: too fast near ground.
    LDA LALT
    CMP #31
    BCS DS_FUEL

    LDA LVEL
    BMI DS_FUEL
    CMP #SAFE_LIMIT
    BCC DS_FUEL
    BRA DS_FAST

DS_FUEL:
    LDA LFUEL
    BEQ DS_NOFUEL
    CMP #LOW_FUEL
    BCC DS_LOW

    JSR GETSURF
    CMP #'X'
    BEQ DS_PAD
    CMP #'='
    BEQ DS_PAD
    BRA DS_OK

DS_FAST:
    LDA #<ST_FAST
    STA TXTL
    LDA #>ST_FAST
    STA TXTH
    JSR PRTXT
    RTS

DS_NOFUEL:
    LDA #<ST_NOFUEL
    STA TXTL
    LDA #>ST_NOFUEL
    STA TXTH
    JSR PRTXT
    RTS

DS_LOW:
    LDA #<ST_LOWFUEL
    STA TXTL
    LDA #>ST_LOWFUEL
    STA TXTH
    JSR PRTXT
    RTS

DS_PAD:
    LDA #<ST_PAD
    STA TXTL
    LDA #>ST_PAD
    STA TXTH
    JSR PRTXT
    RTS

DS_OK:
    LDA #<ST_OK
    STA TXTL
    LDA #>ST_OK
    STA TXTH
    JSR PRTXT
    RTS

DS_LAND:
    LDA #<ST_LAND
    STA TXTL
    LDA #>ST_LAND
    STA TXTH
    JSR PRTXT
    RTS

DS_CRASH:
    LDA #<ST_CRASH
    STA TXTL
    LDA #>ST_CRASH
    STA TXTH
    JSR PRTXT
    RTS

DS_OFF:
    LDA #<ST_OFF
    STA TXTL
    LDA #>ST_OFF
    STA TXTH
    JSR PRTXT
    RTS

; ============================================================
; DRAWLANDER
; ============================================================
DRAWLANDER:
    ; row = 18 - ALT / 12
    LDA LALT
    LDX #0

LD_DIV:
    CMP #ALT_SCALE
    BCC LD_DIV_DONE
    SEC
    SBC #ALT_SCALE
    INX
    BRA LD_DIV

LD_DIV_DONE:
    TXA
    STA TMP

    LDA #FLIGHT_BOTTOM_ROW
    SEC
    SBC TMP
    BCS LD_HAVE_ROW

    LDA #FLIGHT_TOP_ROW

LD_HAVE_ROW:
    CMP #FLIGHT_TOP_ROW
    BCS LD_ROW_OK
    LDA #FLIGHT_TOP_ROW

LD_ROW_OK:
    STA LROW

    ; Erase old lander if inside flight area.
    LDA LOLD
    CMP #FLIGHT_TOP_ROW
    BCC LD_SKIP_OLD
    CMP #GROUND_ROW
    BCS LD_SKIP_OLD

    STA GOROW
    LDA #LANDER_COL
    STA GOCOL
    JSR GOTOXY

    LDA #' '
    STA ACIA_DATA

LD_SKIP_OLD:
    LDA LROW
    STA LOLD
    STA GOROW

    LDA #LANDER_COL
    STA GOCOL
    JSR GOTOXY

    LDA LSTATE
    CMP #STATE_CRASH
    BEQ LD_CRASHCHAR

    LDA #'@'
    BRA LD_DRAWCHAR

LD_CRASHCHAR:
    LDA #'*'

LD_DRAWCHAR:
    STA ACIA_DATA
    RTS

; ============================================================
; DRAWGROUND - moon level in row 19, columns 21..40
; ============================================================
DRAWGROUND:
    LDA SURFPOS
    CMP SURFOLD
    BEQ DG_SKIP
    STA SURFOLD

    LDA #GROUND_ROW
    STA GOROW
    LDA #VIEW_COL
    STA GOCOL
    JSR GOTOXY

    LDA #<SURFACE
    CLC
    ADC SURFPOS
    STA TXTL

    LDA #>SURFACE
    ADC #0
    STA TXTH

    LDX #0
    LDY #20

DG_LOOP:
    LDA (TXTL,X)
    BEQ DG_PAD

    STA ACIA_DATA

    INC TXTL
    BNE DG_NEXT
    INC TXTH

DG_NEXT:
    DEY
    BNE DG_LOOP
    RTS

DG_PAD:
    LDA #' '

DG_PADLOOP:
    STA ACIA_DATA
    DEY
    BNE DG_PADLOOP

DG_SKIP:
    RTS

; ============================================================
; DRAWS - static panel exactly according to pattern
; ============================================================
DRAWS:
    ; Row 1: Lunar Module
    LDA #1
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<TITLE
    STA TXTL
    LDA #>TITLE
    STA TXTH
    JSR PRTXT

    ; Row 2: border
    LDA #2
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<BORDER
    STA TXTL
    LDA #>BORDER
    STA TXTH
    JSR PRTXT

    ; Row 3: ALT
    LDA #3
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<ROW_ALT
    STA TXTL
    LDA #>ROW_ALT
    STA TXTH
    JSR PRTXT

    ; Row 4: VEL
    LDA #4
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<ROW_VEL
    STA TXTL
    LDA #>ROW_VEL
    STA TXTH
    JSR PRTXT

    ; Row 5: border
    LDA #5
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<BORDER
    STA TXTL
    LDA #>BORDER
    STA TXTH
    JSR PRTXT

    ; Row 6: FUEL
    LDA #6
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<ROW_FUEL
    STA TXTL
    LDA #>ROW_FUEL
    STA TXTH
    JSR PRTXT

    ; Row 7: THR
    LDA #7
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<ROW_THR
    STA TXTL
    LDA #>ROW_THR
    STA TXTH
    JSR PRTXT

    ; Row 8: empty panel row
    LDA #8
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<ROW_EMPTY
    STA TXTL
    LDA #>ROW_EMPTY
    STA TXTH
    JSR PRTXT

    ; Row 9: PAD
    LDA #9
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<ROW_PAD
    STA TXTL
    LDA #>ROW_PAD
    STA TXTH
    JSR PRTXT

    ; Row 10: border
    LDA #10
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<BORDER
    STA TXTL
    LDA #>BORDER
    STA TXTH
    JSR PRTXT

    ; Row 12: STAT prefix
    LDA #12
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<STATLBL
    STA TXTL
    LDA #>STATLBL
    STA TXTH
    JSR PRTXT

    ; Row 14: border
    LDA #14
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<BORDER2
    STA TXTL
    LDA #>BORDER2
    STA TXTH
    JSR PRTXT

    ; Row 15: landing objective
    LDA #15
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<OBJLINE
    STA TXTL
    LDA #>OBJLINE
    STA TXTH
    JSR PRTXT

    ; Row 16: border
    LDA #16
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<BORDER2
    STA TXTL
    LDA #>BORDER2
    STA TXTH
    JSR PRTXT

    ; Row 18: restart / quit
    LDA #18
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<KEYEND
    STA TXTL
    LDA #>KEYEND
    STA TXTH
    JSR PRTXT

    ; Row 20: throttle / RCS help
    LDA #20
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<KEY1
    STA TXTL
    LDA #>KEY1
    STA TXTH
    JSR PRTXT

    ; Row 22: direct throttle help + three spaces before viewport
    LDA #22
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY
    LDA #<KEY2
    STA TXTL
    LDA #>KEY2
    STA TXTH
    JSR PRTXT

    LDA #' '
    STA ACIA_DATA
    LDA #' '
    STA ACIA_DATA
    LDA #' '
    STA ACIA_DATA

    RTS

; ============================================================
; QUIT
; ============================================================
QUIT:
    LDA #24
    STA GOROW
    LDA #1
    STA GOCOL
    JSR GOTOXY

    LDA #<BYEMSG
    STA TXTL
    LDA #>BYEMSG
    STA TXTH
    JSR PRTXT

    JSR SHOWCUR
    JMP $F000

; ============================================================
; Terminal helpers
; ============================================================
CLS:
    LDA #$1B
    STA ACIA_DATA
    LDA #'['
    STA ACIA_DATA
    LDA #'2'
    STA ACIA_DATA
    LDA #'J'
    STA ACIA_DATA

    LDA #$1B
    STA ACIA_DATA
    LDA #'['
    STA ACIA_DATA
    LDA #'H'
    STA ACIA_DATA
    RTS

GOTOXY:
    LDA #$1B
    STA ACIA_DATA
    LDA #'['
    STA ACIA_DATA

    LDA GOROW
    JSR PRDEC

    LDA #$3B
    STA ACIA_DATA

    LDA GOCOL
    JSR PRDEC

    LDA #'H'
    STA ACIA_DATA
    RTS

HIDECUR:
    ; ANSI-style hide: ESC [ 25 l
    LDA #$1B
    STA ACIA_DATA
    LDA #'['
    STA ACIA_DATA
    LDA #'2'
    STA ACIA_DATA
    LDA #'5'
    STA ACIA_DATA
    LDA #'l'
    STA ACIA_DATA

    ; DEC-style hide: ESC [ ?25 l
    LDA #$1B
    STA ACIA_DATA
    LDA #'['
    STA ACIA_DATA
    LDA #'?'
    STA ACIA_DATA
    LDA #'2'
    STA ACIA_DATA
    LDA #'5'
    STA ACIA_DATA
    LDA #'l'
    STA ACIA_DATA
    RTS

SHOWCUR:
    ; ANSI-style show: ESC [ 25 h
    LDA #$1B
    STA ACIA_DATA
    LDA #'['
    STA ACIA_DATA
    LDA #'2'
    STA ACIA_DATA
    LDA #'5'
    STA ACIA_DATA
    LDA #'h'
    STA ACIA_DATA

    ; DEC-style show: ESC [ ?25 h
    LDA #$1B
    STA ACIA_DATA
    LDA #'['
    STA ACIA_DATA
    LDA #'?'
    STA ACIA_DATA
    LDA #'2'
    STA ACIA_DATA
    LDA #'5'
    STA ACIA_DATA
    LDA #'h'
    STA ACIA_DATA
    RTS

PRTXT:
    LDX #0
PT_LOOP:
    LDA (TXTL,X)
    BEQ PT_DONE
    STA ACIA_DATA

    INC TXTL
    BNE PT_NEXT
    INC TXTH

PT_NEXT:
    BRA PT_LOOP

PT_DONE:
    RTS

; A = 0..99, no leading zero except single 0
PRDEC:
    LDX #$30
PD_LOOP:
    CMP #10
    BCC PD_DONE
    SEC
    SBC #10
    INX
    BRA PD_LOOP

PD_DONE:
    PHA
    TXA
    CMP #$30
    BEQ PD_SKIP_TENS
    STA ACIA_DATA

PD_SKIP_TENS:
    PLA
    ORA #$30
    STA ACIA_DATA
    RTS

; A = 0..255, always three digits
PRDEC3:
    LDX #$30
P3_HUND:
    CMP #100
    BCC P3_HUND_DONE
    SEC
    SBC #100
    INX
    BRA P3_HUND

P3_HUND_DONE:
    PHA
    TXA
    STA ACIA_DATA
    PLA

    LDX #$30
P3_TENS:
    CMP #10
    BCC P3_TENS_DONE
    SEC
    SBC #10
    INX
    BRA P3_TENS

P3_TENS_DONE:
    PHA
    TXA
    STA ACIA_DATA
    PLA

    ORA #$30
    STA ACIA_DATA
    RTS

; ============================================================
; Data
; ============================================================

THR_DELTA:
    .byte 1,1,1,0,0,$FF,$FF,$FE,$FE,$FD

TITLE:
    .byte "   Lunar Module",0

BORDER:
    .byte "+------------------+",0

BORDER2:
    .byte "====================",0
ROW_ALT:
    .byte "| ALT  000 m       |",0

ROW_VEL:
    .byte "| VEL +000 m/s     |",0

ROW_FUEL:
    .byte "| FUEL 070 %       |",0

ROW_THR:
    .byte "| THR  <##########>|",0

ROW_EMPTY:
    .byte "|                  |",0

ROW_PAD:
    .byte "| PAD  000 m       |",0

STATLBL:
    .byte "STAT>",0

OBJLINE:
    .byte "-LAND ON PAD <=3m/s-",0

KEYEND:
    .byte "r-Restart, q-Quit",0

KEY1:
    .byte "j/k-Throttle a/d-RCS",0

KEY2:
    .byte "0..9-Set throttle",0

ST_OK:
    .byte "NOMINAL",0

ST_NOFUEL:
    .byte "NO FUEL",0

ST_LOWFUEL:
    .byte "LOW FUEL",0

ST_FAST:
    .byte "TOO FAST!",0

ST_PAD:
    .byte "PAD ALIGNED",0

ST_LAND:
    .byte "TOUCHDOWN OK!",0

ST_CRASH:
    .byte "CRASH: TOO FAST",0

ST_OFF:
    .byte "OFF PAD LANDING",0

BYEMSG:
    .byte "RETURNING TO MONITOR",0

; 60-character terrain world.
; Landing pad is =X= around index 30.
SURFACE:
    .byte "----^-----"
    .byte "--^--^--.-"
    .byte "--...----="
    .byte "X=--------"
    .byte "...^------"
    .byte "^----^^^^."
    .byte 0
