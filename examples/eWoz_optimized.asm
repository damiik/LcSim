;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; EWOZ - Extended Woz Monitor
; Port oryginalnego EWOZ 1.2 (Rockwell R6501/R6511, Glitch Works
; R65X1Q SBC) na wlasny a sembler i wlasny CPU z ACIA
; (ACIA_DATA/ACIA_STATUS, bit3 statusu = znak gotowy do odczytu -
; ta sama konwencja co w labirynt.asm).
;
; Zmiany wzgledem oryginalu:
;  - usuniete r ejestry R6501 (PORTA/MCR/SCCR/SCSR/SCDAT/LATCHx/
;    COUNTx) i SETBR (dobor predkosci transmisji) - ACIA tego nie
;    wymaga, transmisja jest bezposrednia (STA ACIA_DATA)
;  - CI N/COUT przepisane pod ACIA_DATA/ACIA_STATUS
;  - usuniete SEI/CLD - Twoj mikrokod ich nie implementuje
;  - usunieta cala obsluga IRQ (USRIRQ*/IRQ/DEFIRQ/wektory) - CPU
;    nie ma  RTI/PHP/PLP/SEI, wiec przerwania i tak nie zadzialaja
;  - SHWMSG: (MSGL),Y -> (MSGL,X) z X=0 i inkrementacja wskaznika,
;    bo Twoj CPU nie ma trybu (zp),Y - dokladnie ten sam zabieg,
;    co juz zrobilismy w PRTXT (labirynt.asm)
;  - '' -> $5C: literal '' bez znaku po nim to u Ciebie
;     "unsupported character escape ", trzeba podac kod ASCII
;  - .segment -> .org (Twoj asembler nie zna segmentow linkera)
;  - klawisz k uruchamia szybka, strumieniowa wersje LODINTK bez echa;
;  - LODINTK dekoduje cyfry HEX inline - bez GETHEXK/JSR/RTS  w petli;
;  - komendy monitora sa male litery: r=run, l=load, k=fast load;
;  - WARIANT LF: wprowadzanie linii (NXTCHR) i skan bufora (NXTITM)
;    koncza sie po LF ($0A) zamiast  CR ($0D) - terminal wysyla
;    wylacznie LF (konwencja Linux); LODINT pozostaje oryginalny
;    (LF-only) i dziala bez zmian; te same poprawki naniesione
;    w bloku WOZMON pod $ FF00 (bajty pod $FF36 i $FF47)
;  - POPRAWKA BUFORA: IN=$0100 to strona stosu, znaki sa pisane od
;    IN+1 (Y=1). Parser NXTITM musi zaczynac od Y=1, aby czytal
;    wlasciwe znaki, a nie smieci z IN+0.
;
;
; Kod wchodzi pod $F000 (ok. 750 bajtow, wiec $FF00 - tylko 256
; bajtow do konca pamieci - bylo za malo). Jesli w labirynt.asm lub
; gdziekolwie k indziej masz  "JMP $FF00 ; powrot do WozMon ", zmien to
; na  "JMP $F000 ".
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
CANIT:  LDA #$5C          ; ''
JSR COUT

GETLIN:
LDA #LF
JSR COUT
LDY #$01              ; Zapisujemy znaki od IN+1, aby nie ruszac IN+0 ($0100)
BKSPC:  DEY
BMI GETLIN
LDA #' '
JSR COUT
LDA #BS
JSR COUT
NXTCHR: JSR CIN
NXTCH1: STA IN,Y
JSR COUT

CMP #LF          ; WARIANT LF: Enter = $0A (bylo CR)
BNE NOTCR
; JSR DBGBUF       ; opcjonalny zrzut bufora
LDY #$FF         ; [POPRAWKA] Przygotowanie Y=-1, aby INY ponizej ustawilo Y=0
LDA #$00
TAX
SETSTO: ASL
SETMOD: STA MODE
BLSKIP: INY      ; Y staje sie 0


; --- DEBUG: pokaż Y i pierwszy czytany znak ---
; PHA
; TYA
; JSR PRBYTE
; LDA #' '
; JSR COUT
; LDA IN,Y
; JSR PRBYTE
; LDA #' '
; JSR COUT
; PLA
; --- koniec debug ---


NXTITM: LDA IN,Y ; [POPRAWKA] Czyta od IN+1 (gdzie jest pierwszy znak)
CMP #LF          ; WARIANT LF: koniec wiersza w buforze = $0A (bylo CR)
BEQ GETLIN
CMP #'.'
BCC BLSKIP
BEQ SETMOD
CMP #$3A       ; ':'
BEQ SETSTO
CMP #'r'
BEQ RUN
CMP #'l'
BEQ DOLOAD
CMP #'k'
BEQ DOKLOAD
STX L
STX H
STY YSAV

NEXHEX: LDA IN,Y
        CMP #'a'
        BCC HEXUP        ; < 'a' → zostaw (cyfry, 'A'-'Z', itd.)
        SBC #$20         ; 'a'-'z' → 'A'-'Z' (carry ustawione przez CMP)
HEXUP:  EOR #$30
        CMP #$0A
        BCC DIG
        ADC #$88
        CMP #$FA
        BCC NOTHEX

DIG:
ASL
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
; K = szybkie wczytywanie Intel HEX: bez echa znakow,
; bez bufora IN i bez ponownego skanowania linii.
DOKLOAD: JSR LODINTK
LDY #$01
JMP GETLIN
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
LDA #LF
JSR COUT
LDA #<IERMSG
STA MSGL
LDA #>IERMSG
STA MSGH
JSR SHWMSG
LDA #LF
JSR COUT
RTS
OKMESS: LDA #<IOKMSG
STA MSGL
LDA #>IOKMSG
STA MSGH
JSR SHWMSG
RTS
; LODINTK -- szybkie wczytywanie Intel HEX
;
; Wersja strumieniowa: czeka na ':' i od razu dekoduje rekord
; z ACIA. Nie kopiuje linii do IN, nie wypisuje kazdego znaku
; i nie skanuje bufora w poszukiwaniu ':'. Kropka oznacza rekord.
;
; Format obslugiwany tak samo jak LODINT: rekord typu $01 konczy
; transfer, pozostale typy sa traktowane jako rekordy danych.
; Po kazdym rekordzie odczytywany jest bajt checksum i sprawdzany
; jest caly rekord.
LODINTK: LDA #<ISTMSG
STA MSGL
LDA #>ISTMSG
STA MSGH
JSR SHWMSG
; Szybki loader aplikacji:
;   - brak bufora IN
;   - brak checksum
;   - CIN jest zawsze inline (brak JSR/RTS)
;   - jedna kropka na rekord
;   - obslugiwane sa rekordy danych ($00) oraz EOF ($01)
; X=0 przez caly transfer, dzieki czemu zapis jest STA (STL,X).
KWAIT:  LDA ACIA_STATUS
AND #$08
BEQ KWAIT
LDA ACIA_DATA
CMP #CANCEL
BNE KNOTCANCEL
JMP KINTDON
KNOTCANCEL:
CMP #$3A
BNE KWAIT
LDA #'.'
STA ACIA_DATA
LDX #$00
; byte count
KBC1:   LDA ACIA_STATUS
AND #$08
BEQ KBC1
LDA ACIA_DATA
EOR #'0'
CMP #$0A
BCC KBC1A
ADC #$08
KBC1A:  ASL
ASL
ASL
ASL
STA L
KBC2:   LDA ACIA_STATUS
AND #$08
BEQ KBC2
LDA ACIA_DATA
EOR #'0'
CMP #$0A
BCC KBC2A
ADC #$08
KBC2A:  AND #$0F
ORA L
STA COUNTER
; address high
KAH1:   LDA ACIA_STATUS
AND #$08
BEQ KAH1
LDA ACIA_DATA
EOR #'0'
CMP #$0A
BCC KAH1A
ADC #$08
KAH1A:  ASL
ASL
ASL
ASL
STA L
KAH2:   LDA ACIA_STATUS
AND #$08
BEQ KAH2
LDA ACIA_DATA
EOR #'0'
CMP #$0A
BCC KAH2A
ADC #$08
KAH2A:  AND #$0F
ORA L
STA STH
; address low
KAL1:   LDA ACIA_STATUS
AND #$08
BEQ KAL1
LDA ACIA_DATA
EOR #'0'
CMP #$0A
BCC KAL1A
ADC #$08
KAL1A:  ASL
ASL
ASL
ASL
STA L
KAL2:   LDA ACIA_STATUS
AND #$08
BEQ KAL2
LDA ACIA_DATA
EOR #'0'
CMP #$0A
BCC KAL2A
ADC #$08
KAL2A:  AND #$0F
ORA L
STA STL
; record type
KRT1:   LDA ACIA_STATUS
AND #$08
BEQ KRT1
LDA ACIA_DATA
EOR #'0'
CMP #$0A
BCC KRT1A
ADC #$08
KRT1A:  ASL
ASL
ASL
ASL
STA L
KRT2:   LDA ACIA_STATUS
AND #$08
BEQ KRT2
LDA ACIA_DATA
EOR #'0'
CMP #$0A
BCC KRT2A
ADC #$08
KRT2A:  AND #$0F
ORA L
CMP #$01
BNE KDATA
JMP KEOF1
; data bytes
KDATA:  LDA ACIA_STATUS
AND #$08
BEQ KDATA
LDA ACIA_DATA
EOR #'0'
CMP #$0A
BCC KDATA1
ADC #$08
KDATA1: ASL
ASL
ASL
ASL
STA L
KDATA2: LDA ACIA_STATUS
AND #$08
BEQ KDATA2
LDA ACIA_DATA
EOR #'0'
CMP #$0A
BCC KDATA3
ADC #$08
KDATA3: AND #$0F
ORA L
STA (STL,X)
INC STL
BNE KDATAC
INC STH
KDATAC: DEC COUNTER
BNE KDATA
; checksum is intentionally ignored: consume two hex digits
KCK1:   LDA ACIA_STATUS
AND #$08
BEQ KCK1
LDA ACIA_DATA
KCK2:   LDA ACIA_STATUS
AND #$08
BEQ KCK2
LDA ACIA_DATA
; consume LF and start next record
KLF:    LDA ACIA_STATUS
AND #$08
BEQ KLF
LDA ACIA_DATA
CMP #LF
BNE KLF
JMP KWAIT
; EOF: consume checksum and line ending, then finish
KEOF1:  LDA ACIA_STATUS
AND #$08
BEQ KEOF1
LDA ACIA_DATA
KEOF2:  LDA ACIA_STATUS
AND #$08
BEQ KEOF2
LDA ACIA_DATA
KEOFL:  LDA ACIA_STATUS
AND #$08
BEQ KEOFL
LDA ACIA_DATA
CMP #LF
BNE KEOFL

KINTDON: LDA #<IOKMSG
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
; DBGBUF -- wypisz pierwsze 16 bajtów bufora IN jako HEX
; procedura pomocnicza do debugowania bufora IN
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DBGBUF: PHA
    LDA #LF
    JSR COUT
    LDA #'>'
    JSR COUT

    LDY #$00
DBGBUF1:
    LDA IN,Y
    JSR PRBYTE
    LDA #' '
    JSR COUT
    INY
    CPY #$10
    BNE DBGBUF1

    PLA
    RTS


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Napisy
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
LOGMSG:	.byte $0d,$0a, "eWoz 1.5", CR, LF, NULL
ISTMSG:	.byte $0d,$0a, "Start Intel Hex code Transfer.", CR, LF, NULL
IOKMSG:	.byte $0d,$0a, "Intel Hex Imported OK.", CR, LF, NULL
IERMSG:	.byte $0d,$0a, "Intel Hex Imported with checksum error.", CR, LF, NULL
.org $FFFA
.word $0F00
.word SETUP
.word $0000
