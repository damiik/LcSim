; LABIRYNT - test pozycjonowania ANSI na terminalu LcSim
; 65C02 + WozMon; ACIA: $5000 dane, $5001 status (bit3 = klawisz gotowy)
; Uruchomienie z WozMon: 0500R
; Sterowanie: W/A/S/D - ruch, Q - wyjscie
;
; Co testuje:
;  - ESC[2J czyszczenie ekranu + ESC[H home
;  - ESC[r;cH pozycjonowanie 1- i 2-cyfrowe (np. 3;5 oraz 13;30)
;  - nadpisywanie znakow w ustalonych miejscach bez ruszania reszty ekranu
;  - brak scrollingu (nic nie pisze poza obszarem 40x24)
;
; Mapa: ramka '#' w wierszach 2..15, kolumnach 3..34; '@' gracz, '*' skarby.

ACIA_DATA   = $5000
ACIA_STATUS = $5001

PX     = $30          ; kolumna gracza (1-based, jak w ANSI)
PY     = $31          ; wiersz gracza
OLDX   = $32          ; poprzednia pozycja (do wymazania)
OLDY   = $33
SCORE  = $34
MOVES  = $35
GOROW  = $36          ; argumenty GOTOXY
GOCOL  = $37
TXTL   = $38          ; wskaznik napisu zakonczonego zerem
TXTH   = $39
TMP    = $3A          ; licznik petli (PRDEC niszczy A i X!)

        .org $3B       ; tablice skarbow w zero page (CPU nie ma trybu addr,X)
TROW:   .byte 4,13,9
TCOL:   .byte 6,30,22
TALIVE: .byte 1,1,1

        .org $0500
START:
        LDA #18
        STA PX
        STA OLDX
        LDA #8
        STA PY
        STA OLDY
        LDA #0
        STA SCORE
        STA MOVES
        JSR CLS

        LDA #1         ; tytul w wierszu 1
        STA GOROW
        LDA #13
        STA GOCOL
        JSR GOTOXY
        LDA #<TITLE
        STA TXTL
        LDA #>TITLE
        STA TXTH
        JSR PRTXT

        LDX #2         ; ramka mapy
        JSR HLINE
        LDX #15
        JSR HLINE
        LDY #3
        JSR VLINE
        LDY #34
        JSR VLINE

        JSR DRAWTR     ; skarby
        JSR SCORELN    ; linia statusu

        LDA #18        ; instrukcja
        STA GOROW
        LDA #4
        STA GOCOL
        JSR GOTOXY
        LDA #<HELPMSG
        STA TXTL
        LDA #>HELPMSG
        STA TXTH
        JSR PRTXT

        LDA PY         ; gracz na pozycji startowej
        STA GOROW
        LDA PX
        STA GOCOL
        JSR GOTOXY
        LDA #'@'
        STA ACIA_DATA
        JSR PARKCUR

MAIN:
        LDA ACIA_STATUS
        AND #$08
        BEQ MAIN
        LDA ACIA_DATA
        CMP #'W'
        BEQ MUP
        CMP #'S'
        BEQ MDN
        CMP #'A'
        BEQ MLF
        CMP #'D'
        BEQ MRT
        CMP #'Q'
        BEQ QUIT
        BRA MAIN

MUP:    LDA PY         ; dozwolone wiersze 3..14
        CMP #4
        BCC MAIN
        DEC PY
        BRA APPLY
MDN:    LDA PY
        CMP #14
        BCS MAIN
        INC PY
        BRA APPLY
MLF:    LDA PX         ; dozwolone kolumny 4..33
        CMP #5
        BCC MAIN
        DEC PX
        BRA APPLY
MRT:    LDA PX
        CMP #33
        BCS MAIN
        INC PX
        BRA APPLY

APPLY:
        INC MOVES
        LDA OLDY       ; wymaz stara pozycje gracza
        STA GOROW
        LDA OLDX
        STA GOCOL
        JSR GOTOXY
        LDA #$20
        STA ACIA_DATA
        JSR CHECKTR    ; wejscie na skarb?
        LDA PY         ; narysuj gracza w nowym miejscu
        STA OLDY
        STA GOROW
        LDA PX
        STA OLDX
        STA GOCOL
        JSR GOTOXY
        LDA #'@'
        STA ACIA_DATA
        JSR PARKCUR    ; kursor na dol, zeby nie migal na mapie
        BRA MAIN

QUIT:
        LDA #20
        STA GOROW
        LDA #4
        STA GOCOL
        JSR GOTOXY
        LDA #<BYEMSG
        STA TXTL
        LDA #>BYEMSG
        STA TXTH
        JSR PRTXT
        JSR PARKCUR
        JMP $FF00      ; powrot do WozMon

; ---------- procedury wyjsciowe ----------

CLS:                   ; ESC[2J ESC[H
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

GOTOXY:                ; ESC[ GOROW ; GOCOL H   (niszczy A,X)
        LDA #$1B
        STA ACIA_DATA
        LDA #'['
        STA ACIA_DATA
        LDA GOROW
        JSR PRDEC
        LDA #$3B       ; ';' (literal ';' myli parser komentarzy)
        STA ACIA_DATA
        LDA GOCOL
        JSR PRDEC
        LDA #'H'
        STA ACIA_DATA
        RTS

PARKCUR:               ; zaparkuj kursor w rogu 23;1
        LDA #23
        STA GOROW
        LDA #1
        STA GOCOL
        BRA GOTOXY     ; tail-call

PRDEC:                 ; A (0..99) dziesietnie, bez zera wiodacego
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

PRDEC3:                ; A (0..255) zawsze 3 cyfry
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

PRTXT:                 ; napis spod TXTL/TXTH, koniec = bajt zerowy
        LDX #0         ; X=0 na stale: (TXTL,X) dziala jak zwykle (zp) indirect
PT1:    LDA (TXTL,X)
        BEQ PT2
        STA ACIA_DATA
        INC TXTL
        BNE PT1
        INC TXTH
        BRA PT1
PT2:    RTS

HLINE:                 ; pozioma linia: wiersz X, kolumny 3..34
        STX GOROW
        LDY #3
HL1:    STY GOCOL
        JSR GOTOXY
        LDA #'#'
        STA ACIA_DATA
        INY
        CPY #35
        BNE HL1
        RTS

VLINE:                 ; pionowa linia: kolumna Y, wiersze 2..15
        STY GOCOL
        LDA #2
        STA TMP
VL1:    LDA TMP
        STA GOROW
        JSR GOTOXY
        LDA #'#'
        STA ACIA_DATA
        INC TMP
        LDA TMP
        CMP #16
        BNE VL1
        RTS

DRAWTR:                ; '*' na zywych skarbach
        LDA #0
        STA TMP
DT1:    LDX TMP
        LDA TALIVE,X
        BEQ DT2
        LDA TROW,X
        STA GOROW
        LDA TCOL,X
        STA GOCOL
        JSR GOTOXY
        LDA #'*'
        STA ACIA_DATA
DT2:    INC TMP
        LDA TMP
        CMP #3
        BNE DT1
        RTS

CHECKTR:               ; gracz na skarbie -> zebrany, odswiez status
        LDA #0
        STA TMP
CT1:    LDX TMP
        LDA TALIVE,X
        BEQ CT2
        LDA TROW,X
        CMP PY
        BNE CT2
        LDA TCOL,X
        CMP PX
        BNE CT2
        LDA #0
        STA TALIVE,X
        INC SCORE
        JSR SCORELN
CT2:    INC TMP
        LDA TMP
        CMP #3
        BNE CT1
        RTS

SCORELN:               ; wiersz 17: "SKARBY n/3   RUCHY mmm"
        LDA #17
        STA GOROW
        LDA #4
        STA GOCOL
        JSR GOTOXY
        LDA #<SMSG1
        STA TXTL
        LDA #>SMSG1
        STA TXTH
        JSR PRTXT
        LDA SCORE
        JSR PRDEC
        LDA #<SMSG2
        STA TXTL
        LDA #>SMSG2
        STA TXTH
        JSR PRTXT
        LDA MOVES
        JSR PRDEC3
        LDA #$20       ; wymaz resztek przy zmianie liczby cyfr
        STA ACIA_DATA
        STA ACIA_DATA
        RTS

; ---------- dane ----------

TITLE:   .byte "TEST ANSI - LABIRYNT",0
HELPMSG: .byte "W/A/S/D - RUCH   Q - KONIEC",0
SMSG1:   .byte "SKARBY ",0
SMSG2:   .byte "/3   RUCHY ",0
BYEMSG:  .byte "DO WIDZENIA - RESET = 0500R",0