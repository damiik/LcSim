;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; EWOZ - Extended Woz Monitor
; Port oryginalnego EWOZ 1.2 (Rockwell R6501/R6511, Glitch Works
; R65X1Q SBC) na wlasny asembler i wlasny CPU z ACIA
; (ACIA_DATA/ACIA_STATUS, bit3 statusu = znak gotowy do odczytu -
; ta sama konwencja co w labirynt.asm).
;
; Zmiany wzgledem oryginalu:
;  - usuniete rejestry R6501 (PORTA/MCR/SCCR/SCSR/SCDAT/LATCHx/
;    COUNTx) i SETBR (dobor predkosci transmisji) - ACIA tego nie
;    wymaga, transmisja jest bezposrednia (STA ACIA_DATA)
;  - CIN/COUT przepisane pod ACIA_DATA/ACIA_STATUS
;  - usuniete SEI/CLD - Twoj mikrokod ich nie implementuje
;  - usunieta cala obsluga IRQ (USRIRQ*/IRQ/DEFIRQ/wektory) - CPU
;    nie ma RTI/PHP/PLP/SEI, wiec przerwania i tak nie zadzialaja
;  - SHWMSG: (MSGL),Y -> (MSGL,X) z X=0 i inkrementacja wskaznika,
;    bo Twoj CPU nie ma trybu (zp),Y - dokladnie ten sam zabieg,
;    co juz zrobilismy w PRTXT (labirynt.asm)
;  - '\' -> $5C: literal '\' bez znaku po nim to u Ciebie
;    "unsupported character escape", trzeba podac kod ASCII
;  - .segment -> .org (Twoj asembler nie zna segmentow linkera)
;  - WARIANT LF: wprowadzanie linii (NXTCHR) i skan bufora (NXTITM)
;    koncza sie po LF ($0A) zamiast CR ($0D) - terminal wysyla
;    wylacznie LF (konwencja Linux); LODINT pozostaje oryginalny
;    (LF-only) i dziala bez zmian; te same poprawki naniesione
;    w bloku WOZMON pod $FF00 (bajty pod $FF36 i $FF47)
;
;
; Kod wchodzi pod $F000 (ok. 750 bajtow, wiec $FF00 - tylko 256
; bajtow do konca pamieci - bylo za malo). Jesli w labirynt.asm lub
; gdziekolwiek indziej masz "JMP $FF00 ; powrot do WozMon", zmien to
; na "JMP $F000".
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

ACIA_DATA   = $5000
ACIA_STATUS = $5001

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; ASCII
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
NULL   = $00
CTRLC  = $03
BS     = $08
LF     = $0A
CR     = $0D

CANCEL = CTRLC          ; klawisz anulujacy biezaca linie
MODVAL = $0F             ; ile lokacji na wiersz w EXAMINE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Zero page
; ($00-$3F wolne - u Ciebie nie ma tam rejestrow sprzetowych,
;  ale zostawiam adresy jak w oryginale, zeby latwo porownac)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
XAML       = $43
XAMH       = $44
STL        = $45
STH        = $46
L          = $47
H          = $48
YSAV       = $49
MODE       = $4A
MSGL       = $4B
MSGH       = $4C
COUNTER    = $4D
CKSUM      = $4E
CKSUMFLAG  = $4F

IN = $0100               ; bufor wejsciowy (strona 1)

        .org $F000
SETUP:
        LDX #$FF          ; ustaw wskaznik stosu
        TXS

        LDA #<LOGMSG      ; napis powitalny
        STA MSGL
        LDA #>LOGMSG
        STA MSGH
        JSR SHWMSG

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; SFTRST -- restart monitora
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SFTRST: LDA #CANCEL
NOTCR:  CMP #BS
        BEQ BKSPC
        CMP #CANCEL
        BEQ CANIT
        INY
        BPL NXTCHR
CANIT:  LDA #$5C          ; '\'
        JSR COUT
GETLIN: LDA #LF
        JSR COUT
        LDA #CR
        JSR COUT

        LDY #$01
BKSPC:  DEY
        BMI GETLIN
        LDA #' '
        JSR COUT
        LDA #BS
        JSR COUT
NXTCHR: JSR CIN
        CMP #$60
        BMI NXTCH1
        AND #$5F
NXTCH1: STA IN,Y
        JSR COUT
        CMP #LF          ; WARIANT LF: Enter = $0A (bylo CR)
        BNE NOTCR
        LDY #$FF
        LDA #$00
        TAX
SETSTO: ASL
SETMOD: STA MODE
BLSKIP: INY
NXTITM: LDA IN,Y
        CMP #LF          ; WARIANT LF: koniec wiersza w buforze = $0A (bylo CR)
        BEQ GETLIN
        CMP #'.'
        BCC BLSKIP
        BEQ SETMOD
        CMP #$3A       ; ':'
        BEQ SETSTO
        CMP #'R'
        BEQ RUN
        CMP #'L'
        BEQ DOLOAD
        STX L
        STX H
        STY YSAV
NEXHEX: LDA IN,Y
        EOR #$30
        CMP #$0A
        BCC DIG
        ADC #$88
        CMP #$FA
        BCC NOTHEX
DIG:    ASL
        ASL
        ASL
        ASL
        LDX #$04
HEXSHF: ASL
        ROL L
        ROL H
        DEX
        BNE HEXSHF
        INY
        BNE NEXHEX
NOTHEX: CPY YSAV
        BNE NOCANC
        JMP SFTRST

RUN:    JSR ACTRUN
        JMP SFTRST
ACTRUN: JMP (XAML)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; DOLOAD -- start wczytywania danych Intel HEX
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DOLOAD: JSR LODINT
        JMP SFTRST

NOCANC: BIT MODE
        BVC NTSTOR
        LDA L
        STA (STL,X)
        INC STL
        BNE NXTITM
        INC STH

TONXIT: JMP NXTITM

NTSTOR: LDA MODE
        CMP #'.'
        BEQ XAMNXT

        LDX #$02
SETADR: LDA L-1,X
        STA STL-1,X
        STA XAML-1,X
        DEX
        BNE SETADR

NXTPRT: BNE PRDATA
        LDA #CR
        JSR COUT
        LDA #LF
        JSR COUT
        LDA XAMH
        JSR PRBYTE
        LDA XAML
        JSR PRBYTE
        LDA #$3A       ; ':'
        JSR COUT

PRDATA: LDA #' '
        JSR COUT
        LDA (XAML,X)
        JSR PRBYTE

XAMNXT: STX MODE
        LDA XAML
        CMP L
        LDA XAMH
        SBC H
        BCS TONXIT
        INC XAML
        BNE MODCHK
        INC XAMH

MODCHK: LDA XAML
        AND #MODVAL
        BPL NXTPRT

PRBYTE: PHA
        LSR
        LSR
        LSR
        LSR
        JSR PRHEX
        PLA

PRHEX:  AND #$0F
        ORA #'0'
        CMP #$3A       ; ':'
        BCC PRHEX1
        ADC #$06
PRHEX1: JMP COUT

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; SHWMSG -- wypisz napis zakonczony zerem
;
; pre: MSGL/MSGH wskazuja na napis
; UWAGA: CPU nie ma (zp),Y - uzywamy (zp,X) z X=0 i
; inkrementujemy sam wskaznik (jak w PRTXT z labirynt.asm)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SHWMSG: LDX #$00
SHWMS1: LDA (MSGL,X)
        BEQ SHWMS2
        JSR COUT
        INC MSGL
        BNE SHWMS1
        INC MSGH
        BRA SHWMS1
SHWMS2: RTS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; LODINT -- wczytywanie danych w formacie Intel HEX
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
LODINT: LDA #<ISTMSG
        STA MSGL
        LDA #>ISTMSG
        STA MSGH
        JSR SHWMSG
        LDY #$00
        STY CKSUMFLAG

INTLIN: JSR CIN
        JSR COUT          ; echo - zeby bylo widac co dochodzi do monitora
        STA IN,Y
        INY
        CMP #CANCEL
        BEQ INTDON
        CMP #LF
        BNE INTLIN
        LDY #$FF
FNDCOL: INY
        LDA IN,Y
        CMP #$3A       ; ':'
        BNE FNDCOL
        INY
        LDX #$00
        STX CKSUM
        JSR GETHEX
        STA COUNTER
        CLC
        ADC CKSUM
        STA CKSUM
        JSR GETHEX
        STA STH
        CLC
        ADC CKSUM
        STA CKSUM
        JSR GETHEX
        STA STL
        CLC
        ADC CKSUM
        STA CKSUM
        LDA #'.'
        JSR COUT
NODOT:  JSR GETHEX
        CMP #$01
        BEQ INTDON
        CLC
        ADC CKSUM
        STA CKSUM
INTSTR: JSR GETHEX
        STA (STL,X)
        CLC
        ADC CKSUM
        STA CKSUM
        INC STL
        BNE TSTCNT
        INC STH
TSTCNT: DEC COUNTER
        BNE INTSTR
        JSR GETHEX
        LDY #$00
        CLC
        ADC CKSUM
        BEQ INTLIN
        LDA #$01
        STA CKSUMFLAG
        JMP INTLIN

INTDON: LDA #$00          ; wygasz IN+0: bez tego zostaje ':' z ostatniego
        STA IN            ; rekordu i parser nastepnej komendy wejdzie w
        LDA CKSUMFLAG     ; tryb zapisu (SETSTO) - neutralizacja
        BEQ OKMESS
        LDA #CR
        JSR COUT
        LDA #<IERMSG
        STA MSGL
        LDA #>IERMSG
        STA MSGH
        JSR SHWMSG
        LDA #CR
        JSR COUT
        RTS

OKMESS: LDA #<IOKMSG
        STA MSGL
        LDA #>IOKMSG
        STA MSGH
        JSR SHWMSG
        RTS

GETHEX: LDA IN,Y
        EOR #'0'
        CMP #LF
        BCC DNFRST
        ADC #$08
DNFRST: ASL
        ASL
        ASL
        ASL
        STA L
        INY
        LDA IN,Y
        EOR #'0'
        CMP #LF
        BCC DNSECN
        ADC #$08
DNSECN: AND #$0F
        ORA L
        INY
        RTS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; CIN -- odbierz znak z ACIA (czeka az bedzie gotowy)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CIN:    LDA ACIA_STATUS
        AND #$08
        BEQ CIN
        LDA ACIA_DATA
        RTS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; COUT -- wyslij znak przez ACIA
; (bez oczekiwania na "transmitter empty" - tak jak w
; labirynt.asm, gdzie STA ACIA_DATA dziala od razu)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
COUT:   STA ACIA_DATA
        RTS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Napisy
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
LOGMSG:	.byte $0d,$0a, "EWOZ 1.2", CR, LF, NULL
ISTMSG:	.byte $0d,$0a, "Start Intel Hex code Transfer.", CR, LF, NULL
IOKMSG:	.byte $0d,$0a, "Intel Hex Imported OK.", CR, LF, NULL
IERMSG:	.byte $0d,$0a, "Intel Hex Imported with checksum error.", CR, LF, NULL

.org $FF00
WOZMON: .byte $a9, $1f, $8d, $03, $50, $a9, $0b, $8d, $02, $50, $a9, $1b, $c9, $08, $f0, $13, $c9, $1b, $f0, $03, $c8, $10, $0f, $a9, $5c, $20, $ef, $ff, $a9, $0d, $20, $ef, $ff, $a0, $01, $88, $30, $f6, $ad, $01, $50, $29, $08, $f0, $f9, $ad, $00, $50, $99, $00, $02, $20, $ef, $ff, $c9, $0a, $d0, $d2, $a0, $ff, $a9, $00, $aa, $0a, $0a, $85, $2b, $c8, $b9, $00, $02, $c9, $0a, $f0, $d1, $c9, $2e, $90, $f4, $f0, $ee, $c9, $3a, $f0, $eb, $c9, $52, $f0, $3b, $86, $28, $86, $29, $84, $2a, $b9, $00, $02, $49, $30, $c9, $0a, $90, $06, $69, $88, $c9, $fa, $90, $11, $0a, $0a, $0a, $0a, $a2, $04, $0a, $26, $28, $26, $29, $ca, $d0, $f8, $c8, $d0, $e0, $c4, $2a, $f0, $94, $24, $2b, $50, $10, $a5, $28, $81, $26, $e6, $26, $d0, $b5, $e6, $27, $4c, $44, $ff, $6c, $24, $00, $30, $2b, $a2, $02, $b5, $27, $95, $25, $95, $23, $ca, $d0, $f7, $d0, $14, $a9, $0d, $20, $ef, $ff, $a5, $25, $20, $dc, $ff, $a5, $24, $20, $dc, $ff, $a9, $3a, $20, $ef, $ff, $a9, $20, $20, $ef, $ff, $a1, $24, $20, $dc, $ff, $86, $2b, $a5, $24, $c5, $28, $a5, $25, $e5, $29, $b0, $c1, $e6, $24, $d0, $02, $e6, $25, $a5, $24, $29, $07, $10, $c8, $48, $4a, $4a, $4a, $4a, $20, $e5, $ff, $68, $29, $0f, $09, $30, $c9, $3a, $90, $02, $69, $06, $48, $8d, $00, $50, $68, $60, $00, $00, $00, $00, $00, $00, $0f, $00, $ff, $00, $00
