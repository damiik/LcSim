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

; ==========================================================
; REJESTRY UKLADU ACIA (port szeregowy terminala)
; ==========================================================
ACIA_DATA   = $5000   ; zapis = wyslij znak na terminal; odczyt = pobierz znak
ACIA_STATUS = $5001   ; bit3 = 1, gdy w ACIA_DATA czeka nowy znak z klawiatury

; ==========================================================
; ZMIENNE GRY (zero page)
; ==========================================================
PX     = $30          ; kolumna gracza (1-based, jak w ANSI)
PY     = $31          ; wiersz gracza
OLDX   = $32          ; poprzednia pozycja (do wymazania)
OLDY   = $33
SCORE  = $34          ; liczba zebranych skarbow (0..3)
MOVES  = $35          ; licznik wykonanych ruchow (0..255)
GOROW  = $36          ; argumenty GOTOXY
GOCOL  = $37
TXTL   = $38          ; wskaznik napisu zakonczonego zerem (low byte adresu)
TXTH   = $39          ; wskaznik napisu zakonczonego zerem (high byte adresu)
TMP    = $3A          ; licznik petli (PRDEC niszczy A i X!)

; ==========================================================
; TABLICE SKARBOW (rownolegle, indeksowane 0..2)
; TROW/TCOL - wspolrzedne skarbu, TALIVE - czy jeszcze niezebrany
; ==========================================================
        .org $3B       ; tablice skarbow w zero page (CPU nie ma trybu addr,X)
TROW:   .byte 4,13,9   ; wiersze trzech skarbow
TCOL:   .byte 6,30,22  ; kolumny trzech skarbow
TALIVE: .byte 1,1,1    ; 1 = skarb obecny na mapie, 0 = juz zebrany

; ==========================================================
; START - inicjalizacja gry i narysowanie calej planszy
; (wywolywane raz, z WozMon poleceniem 0500R)
; ==========================================================
        .org $0500
START:
        LDA #18        ; ustaw pozycje startowa gracza: kolumna 18
        STA PX
        STA OLDX       ; OLDX/OLDY = PX/PY na starcie (nic jeszcze nie wymazujemy)
        LDA #8         ; wiersz 8
        STA PY
        STA OLDY
        LDA #0         ; wyzeruj licznik skarbow i ruchow
        STA SCORE
        STA MOVES
        JSR CLS        ; wyczysc ekran terminala
        JSR HIDECUR    ; ukryj kursor (zeby nie migal po mapie)

        LDA #1         ; tytul w wierszu 1
        STA GOROW
        LDA #13
        STA GOCOL
        JSR GOTOXY     ; ustaw kursor terminala na wiersz 1, kolumne 13
        LDA #<TITLE    ; zaladuj adres napisu TITLE do wskaznika TXTL/TXTH
        STA TXTL
        LDA #>TITLE
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

        JSR DRAWTR     ; narysuj skarby ('*')
        JSR SCORELN    ; wypisz linie statusu (SKARBY/RUCHY)

        LDA #18        ; instrukcja sterowania w wierszu 18
        STA GOROW
        LDA #4
        STA GOCOL
        JSR GOTOXY
        LDA #<HELPMSG
        STA TXTL
        LDA #>HELPMSG
        STA TXTH
        JSR PRTXT      ; wypisz podpowiedz "W/A/S/D - RUCH  Q - KONIEC"

        LDA PY         ; ustaw kursor na pozycji startowej gracza
        STA GOROW
        LDA PX
        STA GOCOL
        JSR GOTOXY
        LDA #'@'
        STA ACIA_DATA  ; narysuj gracza znakiem '@'
        ;JSR PARKCUR

; ==========================================================
; MAIN - glowna petla gry: czekaj na klawisz, rozpoznaj go
; i skocz do odpowiedniej obslugi ruchu
; ==========================================================
MAIN:
        LDA ACIA_STATUS
        AND #$08       ; sprawdz bit "znak gotowy"
        BEQ MAIN       ; brak znaku -> czekaj dalej (busy-wait)
        LDA ACIA_DATA  ; odczytaj wcisniety klawisz (czyta = kasuje flage gotowosci)
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

; ==========================================================
; OBSLUGA RUCHU - kazda etykieta sprawdza granice ramki (kolizja
; ze sciana '#'), a jesli ruch jest legalny, zmienia PX/PY
; i skacze do APPLY, ktory rysuje efekt na ekranie
; ==========================================================
MUP:    LDA PY         ; dozwolone wiersze 3..14
        CMP #4
        BCC MAIN       ; PY<4 -> juz przy scianie, ignoruj ruch
        DEC PY         ; PY-- (gora)
        BRA APPLY
MDN:    LDA PY
        CMP #14
        BCS MAIN       ; PY>=14 -> przy scianie, ignoruj ruch
        INC PY         ; PY++ (dol)
        BRA APPLY
MLF:    LDA PX         ; dozwolone kolumny 4..33
        CMP #5
        BCC MAIN       ; PX<5 -> przy scianie, ignoruj ruch
        DEC PX         ; PX-- (lewo)
        BRA APPLY
MRT:    LDA PX
        CMP #33
        BCS MAIN       ; PX>=33 -> przy scianie, ignoruj ruch
        INC PX         ; PX++ (prawo)
        BRA APPLY

; ==========================================================
; APPLY - narysuj skutek wykonanego ruchu: wymaz gracza w starym
; miejscu, sprawdz zebranie skarbu, narysuj gracza w nowym miejscu
; ==========================================================
APPLY:
        INC MOVES      ; policz kolejny ruch
        LDA OLDY       ; wymaz stara pozycje gracza (postaw spacje)
        STA GOROW
        LDA OLDX
        STA GOCOL
        JSR GOTOXY
        LDA #$20
        STA ACIA_DATA
        JSR CHECKTR    ; wejscie na skarb? (uzywa aktualnych PX/PY)
        LDA PY         ; zapamietaj nowa pozycje jako "stara" na przyszly ruch
        STA OLDY
        STA GOROW
        LDA PX
        STA OLDX
        STA GOCOL
        JSR GOTOXY
        LDA #'@'
        STA ACIA_DATA  ; narysuj gracza w nowym miejscu
        ;JSR PARKCUR    ; kursor na dol, zeby nie migal na mapie
        BRA MAIN       ; wroc do petli glownej, czekaj na kolejny klawisz

; ==========================================================
; QUIT - zakonczenie gry: pozegnanie i powrot do monitora WozMon
; ==========================================================
QUIT:
        LDA #20        ; komunikat pozegnalny w wierszu 20
        STA GOROW
        LDA #4
        STA GOCOL
        JSR GOTOXY
        LDA #<BYEMSG
        STA TXTL
        LDA #>BYEMSG
        STA TXTH
        JSR PRTXT      ; wypisz "DO WIDZENIA - RESET = 0500R"
        JSR PARKCUR    ; przenies kursor terminala w bezpieczne miejsce (23;1)
        JSR SHOWCUR    ; przywroc widocznosc kursora
        JMP $FF00      ; powrot do WozMon

; ---------- procedury wyjsciowe ----------

; ==========================================================
; CLS - wyczysc caly ekran i ustaw kursor terminala w rogu 1;1
; wysyla sekwencje ANSI: ESC[2J (czysc ekran) + ESC[H (kursor home)
; ==========================================================
CLS:
        LDA #$1B       ; ESC
        STA ACIA_DATA
        LDA #'['
        STA ACIA_DATA
        LDA #'2'
        STA ACIA_DATA
        LDA #'J'       ; razem: ESC[2J = wyczysc caly ekran
        STA ACIA_DATA
        LDA #$1B       ; ESC
        STA ACIA_DATA
        LDA #'['
        STA ACIA_DATA
        LDA #'H'       ; razem: ESC[H = kursor do pozycji 1;1
        STA ACIA_DATA
        RTS

; ==========================================================
; GOTOXY - przestaw kursor terminala na wiersz GOROW, kolumne GOCOL
; wysyla ANSI: ESC[ <wiersz> ; <kolumna> H   (niszczy A,X)
; ==========================================================
GOTOXY:
        LDA #$1B       ; ESC
        STA ACIA_DATA
        LDA #'['
        STA ACIA_DATA
        LDA GOROW
        JSR PRDEC      ; wypisz numer wiersza dziesietnie (1 lub 2 cyfry)
        LDA #$3B       ; ';' (literal ';' myli parser komentarzy)
        STA ACIA_DATA
        LDA GOCOL
        JSR PRDEC      ; wypisz numer kolumny dziesietnie (1 lub 2 cyfry)
        LDA #'H'       ; 'H' konczy sekwencje pozycjonowania kursora
        STA ACIA_DATA
        RTS

; ==========================================================
; PARKCUR - przenies kursor terminala w bezpieczny rog (23;1),
; z dala od mapy, zeby migajacy kursor jej nie zaslanial
; ==========================================================
PARKCUR:
        LDA #23
        STA GOROW
        LDA #1
        STA GOCOL
        BRA GOTOXY     ; tail-call do GOTOXY (RTS z GOTOXY wraca do wywolujacego PARKCUR)

; ==========================================================
; HIDECUR - ukryj kursor terminala (ANSI ESC[?25l)
; ==========================================================
HIDECUR:
        LDA #$1B       ; ESC
        STA ACIA_DATA
        LDA #'['
        STA ACIA_DATA
        LDA #'?'
        STA ACIA_DATA
        LDA #'2'
        STA ACIA_DATA
        LDA #'5'
        STA ACIA_DATA
        LDA #'l'       ; razem: ESC[?25l = ukryj kursor
        STA ACIA_DATA
        RTS

; ==========================================================
; SHOWCUR - przywroc widocznosc kursora terminala (ANSI ESC[?25h)
; ==========================================================
SHOWCUR:
        LDA #$1B       ; ESC
        STA ACIA_DATA
        LDA #'['
        STA ACIA_DATA
        LDA #'?'
        STA ACIA_DATA
        LDA #'2'
        STA ACIA_DATA
        LDA #'5'
        STA ACIA_DATA
        LDA #'h'       ; razem: ESC[?25h = pokaz kursor
        STA ACIA_DATA
        RTS

; ==========================================================
; PRDEC - wypisz A (0..99) dziesietnie, bez zera wiodacego
; (niszczy A i X - stad TMP jest osobna zmienna dla wywolujacych)
; ==========================================================
PRDEC:
        LDX #$30       ; X = cyfra dziesiatek, startuje od '0'
PD1:    CMP #10
        BCC PD2        ; A<10 -> koniec odejmowania dziesiatek
        SBC #10        ; odejmij 10, policz kolejna dziesiatke
        INX
        BRA PD1
PD2:    PHA            ; zachowaj reszte (cyfra jednosci) na stosie
        TXA
        CMP #$30       ; czy dziesiatki to '0' (czyli liczba < 10)?
        BEQ PD3        ; tak -> pomin wypisanie zera wiodacego
        STA ACIA_DATA  ; wypisz cyfre dziesiatek
PD3:    PLA            ; zdejmij cyfre jednosci ze stosu
        ORA #$30       ; zamien liczbe 0..9 na znak ASCII '0'..'9'
        STA ACIA_DATA  ; wypisz cyfre jednosci
        RTS

; ==========================================================
; PRDEC3 - wypisz A (0..255) dziesietnie, zawsze na 3 cyfrach
; (z zerami wiodacymi - uzywane do licznika ruchow, zeby nie
; zostawialy sie "smieci" po ekranie przy zmianie liczby cyfr)
; ==========================================================
PRDEC3:
        LDX #$30       ; X = cyfra setek, startuje od '0'
P3A:    CMP #100
        BCC P3B        ; A<100 -> koniec odejmowania setek
        SBC #100       ; odejmij 100, policz kolejna setke
        INX
        BRA P3A
P3B:    PHA            ; zachowaj reszte (dziesiatki+jednosci) na stosie
        TXA
        STA ACIA_DATA  ; wypisz cyfre setek (zawsze, nawet '0')
        PLA
        LDX #$30       ; X = cyfra dziesiatek, startuje od '0'
P3C:    CMP #10
        BCC P3D        ; A<10 -> koniec odejmowania dziesiatek
        SBC #10        ; odejmij 10, policz kolejna dziesiatke
        INX
        BRA P3C
P3D:    PHA            ; zachowaj reszte (cyfra jednosci) na stosie
        TXA
        STA ACIA_DATA  ; wypisz cyfre dziesiatek (zawsze)
        PLA
        ORA #$30       ; zamien reszte 0..9 na znak ASCII
        STA ACIA_DATA  ; wypisz cyfre jednosci
        RTS

; ==========================================================
; PRTXT - wypisz napis (string) spod wskaznika TXTL/TXTH,
; koniec napisu oznacza bajt zerowy
; ==========================================================
PRTXT:
        LDX #0         ; X=0 na stale: (TXTL,X) dziala jak zwykle (zp) indirect
PT1:    LDA (TXTL,X)   ; odczytaj kolejny znak spod wskaznika
        BEQ PT2        ; bajt zerowy -> koniec napisu
        STA ACIA_DATA  ; wyslij znak na terminal
        INC TXTL       ; przesun wskaznik o 1 bajt (low byte)
        BNE PT1        ; brak przepelnienia -> nastepny znak
        INC TXTH       ; przepelnienie low byte -> zwieksz high byte
        BRA PT1
PT2:    RTS

; ==========================================================
; HLINE - narysuj pozioma linie sciany '#' w wierszu X,
; obejmuje kolumny 3..34 (uzywane dla gornej i dolnej ramki)
; ==========================================================
HLINE:
        STX GOROW      ; wiersz linii = X przekazane przez wywolujacego
        LDY #3         ; start od kolumny 3
HL1:    STY GOCOL
        JSR GOTOXY
        LDA #'#'
        STA ACIA_DATA  ; postaw znak sciany
        INY            ; nastepna kolumna
        CPY #35
        BNE HL1        ; powtarzaj do kolumny 34 wlacznie (Y=35 konczy)
        RTS

; ==========================================================
; VLINE - narysuj pionowa linie sciany '#' w kolumnie Y,
; obejmuje wiersze 2..15 (uzywane dla lewej i prawej ramki)
; ==========================================================
VLINE:
        STY GOCOL      ; kolumna linii = Y przekazane przez wywolujacego
        LDA #2         ; start od wiersza 2
        STA TMP
VL1:    LDA TMP
        STA GOROW
        JSR GOTOXY
        LDA #'#'
        STA ACIA_DATA  ; postaw znak sciany
        INC TMP        ; nastepny wiersz
        LDA TMP
        CMP #16
        BNE VL1        ; powtarzaj do wiersza 15 wlacznie (TMP=16 konczy)
        RTS

; ==========================================================
; DRAWTR - narysuj znak '*' na kazdym jeszcze niezebranym skarbie
; (przechodzi po tablicach TROW/TCOL/TALIVE, indeks TMP=0..2)
; ==========================================================
DRAWTR:
        LDA #0
        STA TMP        ; TMP = indeks skarbu (0,1,2)
DT1:    LDX TMP
        LDA TALIVE,X
        BEQ DT2        ; skarb juz zebrany (0) -> pomin rysowanie
        LDA TROW,X     ; wczytaj wspolrzedne skarbu nr TMP
        STA GOROW
        LDA TCOL,X
        STA GOCOL
        JSR GOTOXY
        LDA #'*'
        STA ACIA_DATA  ; narysuj skarb
DT2:    INC TMP        ; nastepny skarb
        LDA TMP
        CMP #3
        BNE DT1        ; powtorz dla wszystkich 3 skarbow
        RTS

; ==========================================================
; CHECKTR - sprawdz, czy gracz (PX,PY) stoi na zywym skarbie;
; jesli tak - oznacz jako zebrany, zwieksz SCORE i odswiez status
; ==========================================================
CHECKTR:
        LDA #0
        STA TMP        ; TMP = indeks skarbu (0,1,2)
CT1:    LDX TMP
        LDA TALIVE,X
        BEQ CT2        ; skarb juz zebrany wczesniej -> pomin
        LDA TROW,X
        CMP PY
        BNE CT2        ; wiersz skarbu != wiersz gracza -> nie ten skarb
        LDA TCOL,X
        CMP PX
        BNE CT2        ; kolumna skarbu != kolumna gracza -> nie ten skarb
        LDA #0
        STA TALIVE,X   ; trafienie: oznacz skarb jako zebrany
        INC SCORE      ; zwieksz licznik zebranych skarbow
        JSR SCORELN    ; odswiez linie statusu na ekranie
CT2:    INC TMP        ; nastepny skarb do sprawdzenia
        LDA TMP
        CMP #3
        BNE CT1        ; powtorz dla wszystkich 3 skarbow
        RTS

; ==========================================================
; SCORELN - wypisz/odswiez linie statusu w wierszu 17:
; "SKARBY n/3   RUCHY mmm"
; ==========================================================
SCORELN:
        LDA #17        ; linia statusu zawsze w wierszu 17
        STA GOROW
        LDA #4
        STA GOCOL
        JSR GOTOXY
        LDA #<SMSG1
        STA TXTL
        LDA #>SMSG1
        STA TXTH
        JSR PRTXT      ; wypisz "SKARBY "
        LDA SCORE
        JSR PRDEC      ; wypisz liczbe zebranych skarbow (1 cyfra)
        LDA #<SMSG2
        STA TXTL
        LDA #>SMSG2
        STA TXTH
        JSR PRTXT      ; wypisz "/3   RUCHY "
        LDA MOVES
        JSR PRDEC3     ; wypisz liczbe ruchow zawsze na 3 cyfrach
        LDA #$20       ; wymaz resztek przy zmianie liczby cyfr
        STA ACIA_DATA
        STA ACIA_DATA
        RTS

; ==========================================================
; DANE - teksty gry, kazdy zakonczony bajtem zerowym (0)
; ==========================================================

TITLE:   .byte "TEST ANSI - LABIRYNT",0            ; tytul, wiersz 1
HELPMSG: .byte "W/A/S/D - RUCH   Q - KONIEC",0      ; podpowiedz, wiersz 18
SMSG1:   .byte "SKARBY ",0                          ; poczatek linii statusu
SMSG2:   .byte "/3   RUCHY ",0                      ; srodek linii statusu
BYEMSG:  .byte "DO WIDZENIA - RESET = 0500R",0      ; komunikat pozegnalny