; ============================================================
; LUNAR MODULE  -  symulator ladowania w stylu Apollo LM
; 65C02 + ACIA (WozMon), ANSI 40x24
; Uruchomienie: 0500R
; Sterowanie: 0-9 = ciag silnika, Q = koniec
; ============================================================

ACIA_DATA   = $5000
ACIA_STATUS = $5001

; --- zero page ---
LALT   = $30   ; wysokosc 0..20 (1 jedn. = 10 m)
LVEL   = $31   ; predkosc pionowa (signed, + = w dol)
LFUEL  = $32   ; paliwo 0..30
LTHR   = $33   ; ciag 0..9
LROW   = $35   ; aktualny wiersz landera
LOLD   = $36   ; poprzedni wiersz landera
LSTATE = $37   ; 0=leci, 1=wyladowal, 2=rozbity
GOROW  = $38
GOCOL  = $39
TXTL   = $3A
TXTH   = $3B
TMP    = $3C

ALT_INIT   = 20
FUEL_INIT  = 30
SAFE_VEL   = 3
LANDER_COL = 30
GROUND_ROW = 23

        .org $0500
START:
        LDA #ALT_INIT      ; startowa wysokosc
        STA LALT
        LDA #FUEL_INIT
        STA LFUEL
        LDA #0
        STA LVEL
        STA LTHR
        STA LSTATE
        LDA #22            ; sentinel: pierwsze "wymazanie" na dole
        STA LOLD
        JSR CLS
        JSR HIDECUR
        JSR DRAWS          ; statyczne elementy raz
        JSR DRAWDYN        ; pierwsze wartosci i lander

; ============================================================
; GLOWNA PETLA
; ============================================================
MAIN:
        JSR POLLKEY        ; nieblokujace czytanie klawisza
        JSR DELAY          ; reguluje tempo gry
        JSR PHYSICS        ; krok fizyki
        JSR DRAWDYN        ; odswiez ekran
        BRA MAIN

; ============================================================
; POLLKEY - jesli jest klawisz, obsluz. Nie czeka.
; ============================================================
POLLKEY:
        LDA ACIA_STATUS
        AND #$08
        BEQ PK_EXIT
        LDA ACIA_DATA
        CMP #'Q'
        BEQ DOQUIT
        CMP #'0'
        BCC PK_EXIT
        CMP #58            ; '9' + 1
        BCS PK_EXIT
        SEC
        SBC #'0'
        STA LTHR
PK_EXIT:
        RTS
DOQUIT: JMP QUIT

; ============================================================
; DELAY - tempo gry. Zmien LDX aby przyspieszyc/zwolnic.
; ============================================================
DELAY:
        LDX #$01
DL1:    LDY #$FF
DL2:    DEY
        BNE DL2
        DEX
        BNE DL1
        RTS

; ============================================================
; PHYSICS - jeden krok symulacji
; ============================================================
PHYSICS:
        LDA LSTATE
        BNE PH_EXIT        ; po wyladowaniu/rozbiciu nic nie robimy
        LDX LTHR
        LDA THR_DELTA,X    ; delta_v z tabeli
        LDX LFUEL
        BNE PH_FUEL_OK
        LDA #1             ; brak paliwa -> tylko grawitacja
        STA LTHR
PH_FUEL_OK:
        CLC
        ADC LVEL
        STA LVEL
        LDA LTHR
        BEQ PH_NOFUEL
        DEC LFUEL
PH_NOFUEL:
        LDA LALT
        SEC
        SBC LVEL
        STA LALT
        BMI PH_LAND
        BEQ PH_LAND
        RTS
PH_LAND:
        LDA #0
        STA LALT
        LDA LVEL
        BMI PH_SAFE        ; ujemna predkosc = wznoszenie, bezpieczne
        CMP #SAFE_VEL
        BCC PH_SAFE
        LDA #2
        STA LSTATE
        RTS
PH_SAFE:
        LDA #1
        STA LSTATE
PH_EXIT:
        RTS

; delta_v = 1 - THRUST/3 (przyblizone)
THR_DELTA:
        .byte 1,1,1,0,0,0,$FF,$FF,$FF,$FE

; ============================================================
; DRAWS - statyczne elementy ekranu (raz na starcie)
; ============================================================
DRAWS:
        ; tytul row 1
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

        ; STEROWANIE: + 2 linie
        LDA #8
        STA GOROW
        LDA #1
        STA GOCOL
        JSR GOTOXY
        LDA #<HELP1
        STA TXTL
        LDA #>HELP1
        STA TXTH
        JSR PRTXT

        LDA #9
        STA GOROW
        LDA #1
        STA GOCOL
        JSR GOTOXY
        LDA #<HELP2
        STA TXTL
        LDA #>HELP2
        STA TXTH
        JSR PRTXT

        LDA #10
        STA GOROW
        LDA #1
        STA GOCOL
        JSR GOTOXY
        LDA #<HELP3
        STA TXTL
        LDA #>HELP3
        STA TXTH
        JSR PRTXT

        ; grunt na prawym viewporcie
        LDA #GROUND_ROW
        STA GOROW
        LDA #21
        STA GOCOL
        JSR GOTOXY
        LDA #'^'
        LDX #20
DGR1:   STA ACIA_DATA
        DEX
        BNE DGR1
        RTS

; ============================================================
; DRAWDYN - dynamiczne wartosci + lander
; ============================================================
DRAWDYN:
        ; --- ALT row 3 ---
        LDA #3
        STA GOROW
        LDA #1
        STA GOCOL
        JSR GOTOXY
        LDA #<LBL_ALT
        STA TXTL
        LDA #>LBL_ALT
        STA TXTH
        JSR PRTXT
        LDA LALT           ; ALT*10 = ALT*8 + ALT*2
        ASL A
        STA TMP
        ASL A
        ASL A
        CLC
        ADC TMP
        JSR PRDEC3
        LDA #' '
        STA ACIA_DATA
        LDA #'M'
        STA ACIA_DATA

        ; --- VEL row 4 ---
        LDA #4
        STA GOROW
        LDA #1
        STA GOCOL
        JSR GOTOXY
        LDA #<LBL_VEL
        STA TXTL
        LDA #>LBL_VEL
        STA TXTH
        JSR PRTXT
        LDA LVEL
        BPL VELPOS
        LDA #'-'
        STA ACIA_DATA
        LDA #0
        SEC
        SBC LVEL
        JMP VELMAG
VELPOS: LDA #'+'
        STA ACIA_DATA
        LDA LVEL
VELMAG: JSR PRDEC2
        LDA #' '
        STA ACIA_DATA
        LDA #'M'
        STA ACIA_DATA
        LDA #'/'
        STA ACIA_DATA
        LDA #'S'
        STA ACIA_DATA

        ; --- FUEL row 5 ---
        LDA #5
        STA GOROW
        LDA #1
        STA GOCOL
        JSR GOTOXY
        LDA #<LBL_FUEL
        STA TXTL
        LDA #>LBL_FUEL
        STA TXTH
        JSR PRTXT
        LDA LFUEL
        JSR PRDEC2

        ; --- THR row 6 ---
        LDA #6
        STA GOROW
        LDA #1
        STA GOCOL
        JSR GOTOXY
        LDA #<LBL_THR
        STA TXTL
        LDA #>LBL_THR
        STA TXTH
        JSR PRTXT
        LDA LTHR
        JSR PRDEC

        ; --- STATUS row 12 ---
        LDA #12
        STA GOROW
        LDA #1
        STA GOCOL
        JSR GOTOXY
        LDA LSTATE
        CMP #1
        BEQ ST_L
        CMP #2
        BEQ ST_C
        LDA LFUEL
        BEQ ST_NF
        LDA #<ST_OK
        STA TXTL
        LDA #>ST_OK
        STA TXTH
        JSR PRTXT
        BRA ST_DONE
ST_NF:  LDA #<ST_NOFUEL
        STA TXTL
        LDA #>ST_NOFUEL
        STA TXTH
        JSR PRTXT
        BRA ST_DONE
ST_L:   LDA #<ST_LAND
        STA TXTL
        LDA #>ST_LAND
        STA TXTH
        JSR PRTXT
        BRA ST_DONE
ST_C:   LDA #<ST_CRASH
        STA TXTL
        LDA #>ST_CRASH
        STA TXTH
        JSR PRTXT
ST_DONE:

        ; --- lander: wymaz stary, narysuj nowy ---
        LDA LOLD
        STA GOROW
        LDA #LANDER_COL
        STA GOCOL
        JSR GOTOXY
        LDA #$20
        STA ACIA_DATA
        LDA #22
        SEC
        SBC LALT
        STA LROW
        STA LOLD
        STA GOROW
        LDA #LANDER_COL
        STA GOCOL
        JSR GOTOXY
        LDA #'@'
        STA ACIA_DATA
        RTS

; ============================================================
; WYJSCIE
; ============================================================
QUIT:
        LDA #20
        STA GOROW
        LDA #1
        STA GOCOL
        JSR GOTOXY
        LDA #<BYEMSG
        STA TXTL
        LDA #>BYEMSG
        STA TXTH
        JSR PRTXT
        JSR PARKCUR
        JSR SHOWCUR
        JMP $FF00

; ============================================================
; PROCEDURY TERMINALOWE (identyczne jak w labiryncie)
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

PARKCUR:
        LDA #23
        STA GOROW
        LDA #1
        STA GOCOL
        BRA GOTOXY

HIDECUR:
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
PT1:    LDA (TXTL,X)
        BEQ PT2
        STA ACIA_DATA
        INC TXTL
        BNE PT1
        INC TXTH
        BRA PT1
PT2:    RTS

PRDEC:                  ; A (0..99) bez zera wiodacego
        LDX #$30
PD1:    CMP #10
        BCC PD2
        SBC #10
        INX
        BRA PD1
PD2:    PHA
        TXA
        CMP #$30
        BEQ PD3
        STA ACIA_DATA
PD3:    PLA
        ORA #$30
        STA ACIA_DATA
        RTS

PRDEC2:                 ; A (0..99) zawsze 2 cyfry
        LDX #$30
PD21:   CMP #10
        BCC PD22
        SBC #10
        INX
        BRA PD21
PD22:   PHA
        TXA
        STA ACIA_DATA
        PLA
        ORA #$30
        STA ACIA_DATA
        RTS

PRDEC3:                 ; A (0..255) zawsze 3 cyfry
        LDX #$30
P3A:    CMP #100
        BCC P3B
        SBC #100
        INX
        BRA P3A
P3B:    PHA
        TXA
        STA ACIA_DATA
        PLA
        LDX #$30
P3C:    CMP #10
        BCC P3D
        SBC #10
        INX
        BRA P3C
P3D:    PHA
        TXA
        STA ACIA_DATA
        PLA
        ORA #$30
        STA ACIA_DATA
        RTS

; ============================================================
; DANE
; ============================================================
TITLE:      .byte "LUNAR MODULE - APOLLO",0
LBL_ALT:    .byte "ALT   ",0
LBL_VEL:    .byte "VEL   ",0
LBL_FUEL:   .byte "FUEL  ",0
LBL_THR:    .byte "THR   ",0
HELP1:      .byte "STEROWANIE:",0
HELP2:      .byte "0-9  CIAG SILNIKA",0
HELP3:      .byte "Q    KONIEC",0
ST_OK:      .byte "STATUS: LECI      ",0
ST_NOFUEL:  .byte "STATUS: BRAK PAL. ",0
ST_LAND:    .byte "LADOWANIE OK!     ",0
ST_CRASH:   .byte "ROZBITE!          ",0
BYEMSG:     .byte "DO WIDZENIA",0