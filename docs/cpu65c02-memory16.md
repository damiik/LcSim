# CPU65C02 r7 — PC16, MAR16 i wspólna pamięć

Opis historycznego etapu r7. Aktualny schemat i domyślny program opisuje
[etap r8](cpu65c02-absolute-call.md), który zmienia szerokość i bankowanie Control ROM.

Ten etap rozszerza tor adresowy istniejącego schematu, zachowując jego
8-bitową magistralę danych, ALU i zestaw instrukcji z r6. Nowe obwody są
modułami z bramek, multiplekserów i przerzutników. Silnik LcSim nie zawiera
specjalnej instrukcji „wykonaj CPU”.

## Mapa pamięci

| Adres CPU | Element / offset w panelu Memory |
| --- | --- |
| `$0000–$00FF` | `MainRAM`, `$000–$0FF`: strona zerowa |
| `$0100–$01FF` | `MainRAM`, `$100–$1FF`: stos |
| `$0200–$0FFF` | `MainRAM`, `$200–$FFF`: pozostały RAM |
| `$1000–$EFFF` | nieobsadzone; odczyt daje Z, brak zapisu |
| `$F000–$FFFF` | `ProgramROM`, `$000–$FFF` |
| `$FFFC/$FFFD` | `ProgramROM[$FFC/$FFD]`: młodszy/starszy bajt wektora resetu |

Stos nie jest już osobnym bankiem. `MAR_STACK` wybiera `$0100 | S` przed
zatrzaśnięciem MAR. `PHA/PHX/PHY` zapisują, następnie zmniejszają S;
`PLA/PLX/PLY` zwiększają S przed odczytem. S zawija się w obrębie 8 bitów.
Adresy portów pamięci podawane są od najmłodszego bitu.

Mapa stosu i kolejność bajtów wektora odpowiadają dokumentacji
[WDC W65C02S, sekcje 3.11 i 4.10](https://www.westerndesigncenter.com/wdc/documentation/w65c02s.pdf).
Nie jest to historyczna mapa KIM-1 ani zgodność czasowa pin po pinie z W65C02S.

## Reset i czas

`In_Reset` pozostaje aktywny w stanie 0. Po utworzeniu symulacji układ
`BOOT16` sam wykonuje rozruch. Przy resecie wejściowym trzymaj 0 przez co
najmniej dwa pełne okresy CLK, następnie ustaw 1. CLK musi pracować.

BOOT16 blokuje zwykłe sterowanie, czyta `$FFFC`, potem `$FFFD`, zatrzaskuje
oba bajty i ładuje PC. CPU rusza po ośmiu narastających zboczach surowego CLK
od zwolnienia resetu. To sekwencja tego projektu, nie siedmiocyklowy reset
oryginalnego układu. Wektor nie jest stałą `$F000`: test startuje pod `$F0D0`.
Ponowny reset wejściowy odczytuje aktualny wektor i zachowuje zawartość RAM.
Przycisk RESET aplikacji odtwarza całą symulację według zasad LcSim.

Pierwszy przerzutnik BOOT16 próbkuje wejście użytkownika z `tsu=0, th=0`.
Jest to jawny, idealny model wejścia resetu: kliknięcie dokładnie na zboczu
nie powinno wprowadzać X do całego sekwencera. Pozostałe przerzutniki mają
normalne czasy technologii; ten model nie odwzorowuje analogowej metastabilności.

S resetuje się synchronicznie do `$FF`; jego impuls zapisu przechodzi przez
istniejące `pc=8`, po ustaleniu multiplekserów danych. Usunięto bezpośrednie
połączenie zbocza resetu z zegarem S, które przy ponownym resecie powodowało X.
Oprogramowanie nadal powinno jawnie inicjalizować S przez `LDX #$FF / TXS`.

PC16 używa równoległego wyliczania przeniesienia przy inkrementacji. Skok
względny oblicza `PC + sign_extend(TMP) + 1` na 16 bitach: PC w tym momencie
wskazuje bajt przesunięcia. Indeksowanie strony zerowej nadal zawija się na
8 bitach. Nowe opóźnienia zapisano w cyklach, poza jawnym modelem wejścia resetu.

`PC_ADR` i `MAR` mają teraz 16 bitów. `MEM.A0..A15` pokazuje adres na pamięci:
normalnie MAR, podczas rozruchu adresy wektora. `VECTOR.V0..V15` pokazuje
odczytany wektor; `BOOT.RUN` i `BOOT.ACTIVE` pokazują stan rozruchu.
Dotychczasowe pozycje i właściwości ozdobnych NODE zachowano; rozszerzenia
adresowe umieszczono w nowym obszarze schematu.

## Uruchomienie testu

TOML zawiera już obraz `cpu65c02-memory16.hex`. W `LcSim/`:

```sh
make test test-cpu
scripts/build_tool.sh examples/cpu65c02.toml cpu65c02
./build-cpu65c02/lcsim-gui --technology lvc
```

Po wykonaniu programu PC zatrzymuje się w pętli `$F204` (podczas pobierania
przesunięcia widać również `$F205`). W `MainRAM`:

| Offset | Wartość | Znaczenie |
| --- | --- | --- |
| `$083` | `$99` | PHX/PLX |
| `$084` | `$42` | PHA/PLA |
| `$085` | `$FF` | TSX po odtworzeniu stosu |
| `$086` | `$FF` | zawinięcie S w dół |
| `$087` | `$7E` | odczyt po zawinięciu S w górę |
| `$088` | `$55` | PHY/PLY |
| `$089` | `$00` | zakończona pętla ze skokiem przez granicę strony |
| `$08A` | `$A5` | program doszedł do końca |
| `$100` | `$7E` | stos S=$00 |
| `$1FE` | `$99` | pozostałość wcześniejszego push |
| `$1FF` | `$55` | pozostałość wcześniejszego push |

S kończy z wartością `$00`. Stary `cpu65c02-stack-lab.asm` pozostaje zapisem
regresji r6 dla dawnej mapy; do r7 używaj `cpu65c02-memory16.asm`.

## Wgrywanie własnego programu i mikrokodu

Obraz ProgramROM musi zaczynać się od offsetu 0 odpowiadającego `$F000`.
W źródle assemblera umieść `.org $F000` i przynajmniej jeden bajt, nawet gdy
właściwy program zaczyna się dalej. Na końcu użyj `.org $FFFC / .word start`.
Nie wklejaj krótkiego programu z `.org $00` bez zmiany wektora i adresowania.

Z narzędziami Nim po patchu r6:

```sh
lcct asm examples/cpu65c02-memory16.asm -o:build/program.hex --isa:mos6502-safe --format:mem
python3 tools/cpu65c02_image.py examples/cpu65c02.toml --program build/program.hex
```

Skrypt przyjmuje 4094–4096 bajtów hex, uzupełnia końcówkę zerami i zmienia tylko
zawartość właściwego ROM. Możesz użyć `-o inny.toml`, aby zapisać kopię.
Format obsługuje zarówno `A9`, jak i `0xA9`; nie jest to format Intel HEX.
W GUI wklej pełny obraz do **ProgramROM**, następnie wykonaj reset.

Mikrokod zachowuje 42 bity i 8 kroków instrukcji z r6. Control ROM ma teraz
12 bitów adresu: A0..A7=IR, A8..A10=STEP, A11=BOOT.ACTIVE. Bank 0 to oryginalne
2048 słów, bank 1 zawiera wyłącznie bezczynne słowo `0600009F7F1`.

```sh
lcct lut -o:build/control.hex --isa:mos6502-safe
python3 tools/cpu65c02_image.py examples/cpu65c02.toml --control build/control.hex
```

Nie zastępuj całego Control ROM samym 2048-słowowym wynikiem `lcct lut`:
skasowałoby to bank rozruchowy. Skrypt dodaje go automatycznie. Zmiana obrazu
w TOML wymaga ponownego zbudowania programu C++; wklejenie w panelu Memory
zmienia pamięć bieżącej symulacji.

## Zakres tego etapu

To nadal podzbiór 65C02 bez korekcji dziesiętnej. Nie dodano jeszcze
adresowania absolutnego/pośredniego, JSR/RTS, PHP/PLP, BRK/RTI ani IRQ/NMI.
PC może pobierać kod z całej obsadzonej przestrzeni, lecz zwykłe dotychczasowe
rozkazy danych adresują stronę zerową; rozkazy stosu — stronę pierwszą.
Dostęp instrukcjami danych do `$0200–$0FFF` wymaga następnego etapu: rejestru
wysokiego bajtu operandu i rozszerzenia mikrokodu. IRQ/BRK pod `$FFFE/$FFFF`
nie są jeszcze obsługiwane. Terminal, klawiatura i KIM-1 pozostają planem.

Testy C++ potwierdzają działanie bramkowe obu technologii i zgodność śladów
cache. Parser i round-trip edytora TypeScript sprawdzono osobno; nie jest to
porównanie pełnych przebiegów dwóch różnych silników. Narzędzia Nim nie były
uruchamiane w środowisku przygotowania tego patcha.
