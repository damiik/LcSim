; ============================================================
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
; >>> TA WERSJA DODATKOWO:
;  - 10 skarbow zamiast 3
;  - tablice TROW/TCOL/TALIVE POZA zero page (adres >= $0100),
;    wiec kazdy dostep LDA/STA TALIVE,X musi uzyc trybu absolute,X.
;    To jest wlasnie test nowego opcodu (np. BD lo hi dla LDA abs,X).
; ============================================================

; ============================================================
; BLOK: STALE SPRZETOWE - ACIA
; Opis: adresy rejestrow kontrolera terminala.
; ACIA_DATA   - wpisany bajt idzie na terminal, odczytany to znak klawiatury.
; ACIA_STATUS - bit 3 oznacza, ze w ACIA_DATA czeka znak klawisza.
; ============================================================
ACIA_DATA   = $5000
ACIA_STATUS = $5001

; ============================================================
; BLOK: ZMIENNE W ZERO PAGE
; Opis: szybkie zmienne programu. Zero page jest tu uzywana tylko
;       dla zmiennych skalarnych i wskaznika TXTL/TXTH - tablice
;       skarbow zostaly CELOWO przeniesione poza zeropage.
; ============================================================
PX     = $30          ; kolumna gracza (1-based, jak w ANSI)
PY     = $31          ; wiersz gracza
OLDX   = $32          ; poprzednia pozycja (do wymazania)
OLDY   = $33
SCORE  = $34          ; liczba zebranych skarbow (0..10)
MOVES  = $35          ; licznik wykonanych ruchow (0..255)
GOROW  = $36          ; argumenty GOTOXY: wiersz
GOCOL  = $37          ; argumenty GOTOXY: kolumna
TXTL   = $38          ; wskaznik napisu (low byte adresu)
TXTH   = $39          ; wskaznik napisu (high byte adresu)
TMP    = $3A          ; licznik petli (PRDEC niszczy A i X!)

; ============================================================
; BLOK: PUNKT STARTOWY PROGRAMU
; Opis: inicjalizacja stanu gry, narysowanie ekranu, ramki, skarbow,
;       statusu, instrukcji i gracza. Potem przejscie do glownej petli.
; ============================================================
        .org $0500
START:
        LDA #18        ; ustaw startowa kolumne gracza
        STA PX
        STA OLDX       ; OLDX/OLDY = PX/PY na starcie (nic jeszcze nie wymazujemy)
        LDA #8         ; ustaw startowy wiersz gracza (wiersz 8)
        STA PY
        STA OLDY       ; OLDY = PY
        LDA #0
        STA SCORE      ; zeruj licznik skarbow
        STA MOVES      ; zeruj licznik ruchow
        JSR CLS        ; wyczysc ekran i ustaw kursor w home
        JSR HIDECUR    ; ukryj kursor terminala

        LDA #1         ; tytul w wierszu 1
        STA GOROW
        LDA #13        ; od kolumny 13
        STA GOCOL
        JSR GOTOXY     ; ustaw kursor terminala na wiersz 1, kolumne 13
        LDA #<TITLE    ; zaladuj adres napisu TITLE do wskaznika TXTL/TXTH
        STA TXTL
        LDA #>TITLE    ; starszy bajt adresu TITLE
        STA TXTH
        JSR PRTXT      ; wypisz tytul gry

        LDX #2         ; ramka mapy: gorna pozioma linia w wierszu 2
        JSR HLINE
        LDX #15        ; dolna pozioma linia w wierszu 15
        JSR HLINE
        LDY #3         ; lewa pionowa linia w kolumnie 3
        JSR VLINE
        LDY #34        ; prawa pionowa linia w kolumnie 34
        JSR VLINE

        JSR INITTR     ; inicjalizacja tablic skarbow (TROW/TCOL/TALIVE)
        JSR DRAWTR     ; narysuj wszystkie 10 skarbow ('*')
        JSR SCORELN    ; wypisz linie statusu (SKARBY 0/10   RUCHY 000)

        LDA #18        ; instrukcja sterowania w wierszu 18
        STA GOROW
        LDA #4         ; od kolumny 4
        STA GOCOL
        JSR GOTOXY
        LDA #<HELPMSG  ; adres komunikatu pomocy
        STA TXTL
        LDA #>HELPMSG
        STA TXTH
        JSR PRTXT      ; wypisz podpowiedz "W/A/S/D - RUCH  Q - KONIEC"

        LDA PY         ; gracz na pozycji startowej: wiersz
        STA GOROW
        LDA PX         ; kolumna
        STA GOCOL
        JSR GOTOXY     ; ustaw kursor na polu gracza
        LDA #'@'
        STA ACIA_DATA  ; narysuj gracza znakiem '@'
        ;JSR PARKCUR

; ============================================================
; BLOK: GLOWNA PETLA
; Opis: czeka na znak z ACIA. Rozpoznaje W/A/S/D/Q i skacze do obslugi.
;       Nie robi nic, dopoki bit 3 statusu nie powie, ze jest klawisz.
; ============================================================
MAIN:
        LDA ACIA_STATUS
        AND #$08       ; sprawdz bit "znak gotowy"
        BEQ MAIN       ; brak znaku -> czekaj dalej (busy-wait)
        LDA ACIA_DATA  ; odczytaj znak (czyta = kasuje flage gotowosci)
        CMP #'W'
        BEQ MUP        ; W -> ruch w gore
        CMP #'S'
        BEQ MDN        ; S -> ruch w dol
        CMP #'A'
        BEQ MLF        ; A -> ruch w lewo
        CMP #'D'
        BEQ MRT        ; D -> ruch w prawo
        CMP #'Q'
        BEQ QUIT       ; Q -> zakoncz gre
        BRA MAIN       ; inny klawisz -> ignoruj, czekaj dalej

; ============================================================
; BLOK: OBSLUGA RUCHU W GORE
; Opis: sprawdza granice mapy i zmniejsza PY. Dozwolone wiersze to 3..14.
; ============================================================
MUP:    LDA PY         ; dozwolone wiersze 3..14
        CMP #4
        BCC MAIN        ; jesli PY < 4, nie mozna isc w gore
        DEC PY          ; przesun gracza w gore
        BRA APPLY

; ============================================================
; BLOK: OBSLUGA RUCHU W DOL
; Opis: sprawdza granice mapy i zwieksza PY.
; ============================================================
MDN:    LDA PY
        CMP #14
        BCS MAIN        ; jesli PY >= 14, nie mozna isc w dol
        INC PY          ; przesun gracza w dol
        BRA APPLY

; ============================================================
; BLOK: OBSLUGA RUCHU W LEWO
; Opis: sprawdza granice mapy i zmniejsza PX. Dozwolone kolumny to 4..33.
; ============================================================
MLF:    LDA PX         ; dozwolone kolumny 4..33
        CMP #5
        BCC MAIN        ; jesli PX < 5, nie mozna isc w lewo
        DEC PX          ; przesun gracza w lewo
        BRA APPLY

; ============================================================
; BLOK: OBSLUGA RUCHU W PRAWO
; Opis: sprawdza granice mapy i zwieksza PX.
; ============================================================
MRT:    LDA PX
        CMP #33
        BCS MAIN        ; jesli PX >= 33, nie mozna isc w prawo
        INC PX          ; przesun gracza w prawo
        BRA APPLY

; ============================================================
; BLOK: ZASTOSOWANIE RUCHU
; Opis: zwieksza licznik ruchow, wymazuje gracza w starej pozycji,
;       sprawdza czy nie wszedl na skarb, rysuje gracza w nowej pozycji.
; ============================================================
APPLY:
        INC MOVES       ; kazdy zaakceptowany ruch sie liczy
        LDA OLDY        ; wymaz stara pozycje gracza: wiersz
        STA GOROW
        LDA OLDX        ; kolumna
        STA GOCOL
        JSR GOTOXY      ; ustaw kursor na starej pozycji
        LDA #$20        ; spacja
        STA ACIA_DATA   ; zamazuje '@'
        JSR CHECKTR     ; wejscie na skarb?
        LDA PY          ; narysuj gracza w nowym miejscu
        STA OLDY        ; zapamietaj nowy wiersz jako stary
        STA GOROW
        LDA PX
        STA OLDX        ; zapamietaj nowa kolumne jako stara
        STA GOCOL
        JSR GOTOXY      ; ustaw kursor na nowej pozycji
        LDA #'@'        ; znak gracza
        STA ACIA_DATA
        BRA MAIN        ; wroc do czekania na klawisz

; ============================================================
; BLOK: WYJSCIE Z PROGRAMU
; Opis: wypisuje komunikat pozegnalny, ustawia kursor poza mapa,
;       przywraca kursor i wraca do WozMon.
; ============================================================
QUIT:
        LDA #20        ; komunikat w wierszu 20
        STA GOROW
        LDA #4         ; od kolumny 4
        STA GOCOL
        JSR GOTOXY
        LDA #<BYEMSG   ; adres komunikatu pozegnalnego
        STA TXTL
        LDA #>BYEMSG
        STA TXTH
        JSR PRTXT      ; wypisz "DO WIDZENIA - RESET = 0500R"
        JSR PARKCUR    ; przenies kursor na 23;1
        JSR SHOWCUR    ; przywroc widocznosc kursora
        JMP $FF00      ; powrot do WozMon

; ============================================================
; BLOK: PROCEDURY WYJSCIA TERMINALOWEGO
; Opis: niskopoziomowe komendy ANSI/ACIA: czyszczenie, pozycjonowanie,
;       kursor, drukowanie liczb i napisow.
; ============================================================

; ------------------------------------------------------------
; CLS: czysci ekran i ustawia kursor w lewym gornym rogu.
; Wysyla: ESC[2J ESC[H
; ------------------------------------------------------------
CLS:                   ; ESC[2J ESC[H
        LDA #$1B        ; ESC
        STA ACIA_DATA
        LDA #'['
        STA ACIA_DATA
        LDA #'2'
        STA ACIA_DATA
        LDA #'J'        ; razem: ESC[2J = wyczysc caly ekran
        STA ACIA_DATA
        LDA #$1B        ; ESC
        STA ACIA_DATA
        LDA #'['
        STA ACIA_DATA
        LDA #'H'        ; razem: ESC[H = kursor do pozycji 1;1
        STA ACIA_DATA
        RTS

; ------------------------------------------------------------
; GOTOXY: ustawia kursor terminala w wierszu GOROW i kolumnie GOCOL.
; Wysyla: ESC[ GOROW ; GOCOL H
; Uwaga: PRDEC niszczy A i X.
; ------------------------------------------------------------
GOTOXY:                ; ESC[ GOROW ; GOCOL H   (niszczy A,X)
        LDA #$1B
        STA ACIA_DATA
        LDA #'['
        STA ACIA_DATA
        LDA GOROW
        JSR PRDEC       ; wypisz numer wiersza dziesietnie (1 lub 2 cyfry)
        LDA #$3B        ; ';' (literal ';' myli parser komentarzy)
        STA ACIA_DATA
        LDA GOCOL
        JSR PRDEC       ; wypisz numer kolumny dziesietnie
        LDA #'H'        ; 'H' konczy sekwencje pozycjonowania kursora
        STA ACIA_DATA
        RTS

; ------------------------------------------------------------
; PARKCUR: ustawia kursor w prawym/dolnym obszarze, wiersz 23, kolumna 1.
; Tail-call do GOTOXY.
; ------------------------------------------------------------
PARKCUR:               ; zaparkuj kursor w rogu 23;1
        LDA #23
        STA GOROW
        LDA #1
        STA GOCOL
        BRA GOTOXY

; ------------------------------------------------------------
; HIDECUR: ukrywa kursor terminala.
; Wysyla: ESC[?25l
; ------------------------------------------------------------
HIDECUR:               ; ESC[?25l - ukryj kursor
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

; ------------------------------------------------------------
; SHOWCUR: przywraca widocznosc kursora.
; Wysyla: ESC[?25h
; ------------------------------------------------------------
SHOWCUR:               ; ESC[?25h - przywroc kursor
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

; ------------------------------------------------------------
; PRDEC: wypisuje A jako liczbe dziesietna 0..99, bez zera wiodacego.
; Niszczy A i X.
; ------------------------------------------------------------
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

; ------------------------------------------------------------
; PRDEC3: wypisuje A jako zawsze 3 cyfry dziesietne.
; Niszczy A i X.
; ------------------------------------------------------------
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

; ------------------------------------------------------------
; PRTXT: wypisuje napis zakonczony bajtem zerowym.
; Adres napisu jest w TXTL/TXTH. Modyfikuje TXTL/TXTH.
; ------------------------------------------------------------
PRTXT:                 ; napis spod TXTL/TXTH, koniec = bajt zerowy
        LDX #0
PT1:    LDA (TXTL,X)
        BEQ PT2
        STA ACIA_DATA
        INC TXTL
        BNE PT1
        INC TXTH
        BRA PT1
PT2:    RTS

; ------------------------------------------------------------
; HLINE: rysuje pozioma linie '#' w wierszu X, kolumnach 3..34.
; ------------------------------------------------------------
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

; ------------------------------------------------------------
; VLINE: rysuje pionowa linie '#' w kolumnie Y, wierszach 2..15.
; ------------------------------------------------------------
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


; ------------------------------------------------------------
; INITTR: inicjalizuje tablice skarbow (TALIVE) na same 1.
; >>> Test absolute,X po stronie ZAPISU: TALIVE >= $0100,
;     wiec STA TALIVE,X musi byc zakodowane jako 9D lo hi.
; Niszczy A i X.
; ------------------------------------------------------------
INITTR:
        LDA #1          ; wartosc wpisywana do kazdej komorki
        LDX #0          ; X = indeks skarbu (0..9)
IT1:    STA TALIVE,X    ; TALIVE[X] = 1  (absolute,X)
        INX             ; nastepny indeks
        CPX #10         ; czy doszlismy do 10?
        BNE IT1         ; nie -> powtorz
        RTS

; ------------------------------------------------------------
; DRAWTR: rysuje wszystkie zywe skarby jako '*'.
; >>> TU TESTUJEMY absolute,X: TALIVE/TROW/TCOL sa poza zeropage,
;     wiec LDA TALIVE,X / LDA TROW,X / LDA TCOL,X musza byc
;     zakodowane jako absolutne (np. BD lo hi), nie jako zp,X.
; ------------------------------------------------------------
DRAWTR:                ; '*' na zywych skarbach
        LDA #0
        STA TMP        ; TMP = indeks skarbu (0..9)
DT1:    LDX TMP
        LDA TALIVE,X    ; >>> absolute,X (adres TALIVE >= $0100)
        BEQ DT2         ; jesli nie zywy, pomin
        LDA TROW,X      ; >>> absolute,X
        STA GOROW
        LDA TCOL,X      ; >>> absolute,X
        STA GOCOL
        JSR GOTOXY
        LDA #'*'
        STA ACIA_DATA
DT2:    INC TMP
        LDA TMP
        CMP #10         ; >>> 10 skarbow, nie 3
        BNE DT1
        RTS

; ------------------------------------------------------------
; CHECKTR: sprawdza, czy gracz stoi na zywym skarbie.
; Jesli tak: oznacza skarb jako zebrany, zwieksza SCORE i odswieza status.
; ------------------------------------------------------------
CHECKTR:               ; gracz na skarbie -> zebrany, odswiez status
        LDA #0
        STA TMP        ; TMP = indeks skarbu (0..9)
CT1:    LDX TMP
        LDA TALIVE,X    ; >>> absolute,X
        BEQ CT2
        LDA TROW,X      ; >>> absolute,X
        CMP PY
        BNE CT2
        LDA TCOL,X      ; >>> absolute,X
        CMP PX
        BNE CT2
        LDA #0
        STA TALIVE,X    ; >>> absolute,X (zapis!)
        INC SCORE
        JSR SCORELN
CT2:    INC TMP
        LDA TMP
        CMP #10         ; >>> 10 skarbow, nie 3
        BNE CT1
        RTS

; ------------------------------------------------------------
; SCORELN: odswieza linie statusu w wierszu 17.
; Format: "SKARBY n/10   RUCHY mmm"
; ------------------------------------------------------------
SCORELN:               ; wiersz 17: "SKARBY n/10   RUCHY mmm"
        LDA #17
        STA GOROW
        LDA #4
        STA GOCOL
        JSR GOTOXY
        LDA #<SMSG1     ; "SKARBY "
        STA TXTL
        LDA #>SMSG1
        STA TXTH
        JSR PRTXT
        LDA SCORE       ; liczba zebranych skarbow (0..10)
        JSR PRDEC       ; wypisz 1 lub 2 cyfry
        LDA #<SMSG2     ; "/10   RUCHY "
        STA TXTL
        LDA #>SMSG2
        STA TXTH
        JSR PRTXT
        LDA MOVES
        JSR PRDEC3      ; licznik ruchow zawsze 3 cyfry
        LDA #$20        ; wymaz resztek przy zmianie liczby cyfr
        STA ACIA_DATA
        STA ACIA_DATA
        RTS

; ============================================================
; BLOK: DANE TEKSTOWE
; Opis: napisy zakonczone bajtem zerowym, uzywane przez PRTXT.
; ============================================================
TITLE:   .byte "TEST ANSI - LABIRYNT",0
HELPMSG: .byte "W/A/S/D - RUCH   Q - KONIEC",0
SMSG1:   .byte "SKARBY ",0
SMSG2:   .byte "/10   RUCHY ",0
BYEMSG:  .byte "DO WIDZENIA - RESET = 0500R",0

; ============================================================
; BLOK: TABLICE SKARBOW POZA ZERO PAGE
; Opis: 10 skarbow. Kazda tablica ma po 10 bajtow.
;       Adresy tych tablic sa >= $0600 (sekcja danych po kodzie),
;       wiec kazdy dostep "LDA tab,X" / "STA tab,X" w kodzie
;       powyzej MUSI zostac zakodowany jako absolute,X.
;       To jest cel tego testu: sprawdzenie, ze assembler
;       wybiera amAbsoluteX dla adresow poza zeropage.
;
;       Gdyby ktos chcial zobaczyc roznice, wystarczy przestawic
;       te tablice do zeropage ($3B) - wtedy asembler wygeneruje
;       zp,X (2 bajty) zamiast absolute,X (3 bajty).
; ============================================================
TROW:   .byte 3,3,5,7,8,10,10,12,13,14       ; wiersze 10 skarbow
TCOL:   .byte 5,32,18,7,32,12,25,5,22,32     ; kolumny 10 skarbow
TALIVE: .byte 10, 10, 10, 10, 10, 10, 10, 10, 10, 10