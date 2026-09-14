# LcSim i WozMon — od asemblera do działającego programu

Instrukcja dla wersji r12 z monitorem WozMon ACIA. Używamy pliku
`examples/cpu65c02-wozmon.toml`, a nie starszego `cpu65c02-term.toml` z LcMon.

Najwygodniejszy sposób pracy: raz zbuduj LcSim z WozMon, a kolejne programy
ładuj do RAM przez zakładkę TERM. Zmiana programu w RAM nie wymaga ponownej
kompilacji symulatora. Schemat i początkowa zawartość ROM są natomiast
wbudowane w wygenerowany program C++.

## 1. Przygotuj asembler

Po nałożeniu patcha r12 dla narzędzi Nim zbuduj `lcct`:

```bash
cd ~/sourcecode/nim/logic_cosmos_cpu_tools
nim c -d:release -o:lcct src/lcct.nim
```

Przejdź do LcSim. Wszystkie dalsze polecenia wykonuj w tym katalogu:

```bash
cd ~/sourcecode/cpp/LcSim
LCCT="$HOME/sourcecode/nim/logic_cosmos_cpu_tools/lcct"
mkdir -p programs
```

Dostosuj ścieżkę `LCCT`, jeśli narzędzia Nim masz gdzie indziej. Wymagane są
również Python 3.11+, GNU make, g++ obsługujący C++17 i zbudowana biblioteka raylib.

## 2. Zbuduj i uruchom komputer z WozMon

Gotowy TOML r12 zawiera już właściwy mikrokod i ROM monitora:

```bash
RAYLIB_DIR=../third_party/raylib \
  scripts/build_tool.sh examples/cpu65c02-wozmon.toml cpu65c02-wozmon

./build-cpu65c02-wozmon/lcsim-gui --technology lvc
```

Ścieżka do raylib jest liczona względem `LcSim`. Skrypt dodaje między innymi
`-I../third_party/raylib/src` oraz `-L../third_party/raylib/src -lraylib`.
Możesz użyć `--technology fpga` zamiast `lvc`.

W aplikacji wybierz **TERM**, uruchom symulację i włącz **AUTO CLK**.
Poczekaj na znak `\`. To znak gotowości monitora. WozMon ma programową pętlę
opóźniającą wysyłanie znaków, więc odpowiedzi mogą pojawiać się powoli.

## 3. Napisz pierwszy program

Zapisz plik `programs/hello.asm`:

```asm
.org $0400
START:
    LDA #$21       ; ASCII: !
    STA $5000      ; Wyślij znak do terminala ACIA.
    JMP $FF00      ; Wróć do początku WozMon.
```

Ten program wypisuje `!`, po czym wraca do monitora. Używa adresu RAM `$0400`.
Nie kończ programu instrukcją `RTS`: polecenie `R` monitora wykonuje skok,
nie wywołanie `JSR`, więc nie odkłada adresu powrotnego na stosie.

## 4. Złóż program do kodu maszynowego

```bash
"$LCCT" asm programs/hello.asm --isa:mos6502-safe --format:bin \
  -o:programs/hello.bin --listing:programs/hello.lst
```

`hello.lst` pokazuje adresy i instrukcje. `hello.bin` zawiera same bajty kodu,
bez adresu ładowania. W tym przykładzie jest to osiem bajtów:

```text
A9 21 8D 00 50 4C 00 FF
```

Pierwsze `.org $0400` określa adres składania; nie dodaje do pliku binarnego
1024 bajtów początkowych zer. Przy ładowaniu trzeba ponownie podać adres `$0400`.

## 5. Wczytaj program przez WozMon i uruchom

W zakładce **TERM** wpisz kolejno, zatwierdzając każdą linię Enterem:

```text
0400: A9 21 8D 00 50 4C 00 FF
0400.0407
0400R
```

Pierwsza linia zapisuje kod w RAM. Druga pozwala sprawdzić osiem zapisanych
bajtów. Trzecia uruchamia program od `$0400`. Zobaczysz `!`, a następnie `\`
i powrót monitora do oczekiwania na polecenia. Adresy i dane wpisujemy szesnastkowo,
bez prefiksu `$` lub `0x`.

Dla dłuższego programu wygeneruj tekst do wklejenia automatycznie:

```bash
python3 - <<'PY'
from pathlib import Path

base = 0x0400  # Musi odpowiadać pierwszemu .org w pliku ASM.
code = Path('programs/hello.bin').read_bytes()
assert code and 0x0400 <= base and base + len(code) <= 0x1000
lines = [
    f'{base + offset:04X}: ' + code[offset:offset + 16].hex(' ').upper()
    for offset in range(0, len(code), 16)
]
Path('programs/hello.woz.txt').write_text('\n'.join(lines) + '\n')
PY
```

Skopiuj zawartość `programs/hello.woz.txt` i użyj **PASTE** lub **Ctrl+V**
w **TERM**. Poczekaj, aż monitor przetworzy wszystkie linie, potem wpisz `0400R`.
Podział na 16 bajtów mieści polecenia w limicie długości linii WozMon.
Duże pliki wklejaj partiami, czekając na opróżnienie kolejki klawiatury.

Wklejanie w **SCOPE → Memory** działa inaczej: zastępuje obraz wybranej pamięci,
nie wykonuje poleceń monitora. Do opisanej procedury używaj **TERM**.

## 6. Kiedy kompilować symulator ponownie?

| Zmiana | Co zrobić |
| --- | --- |
| Kod programu uruchamianego w RAM | Ponownie złożyć ASM i wczytać nowe bajty przez TERM. |
| Schemat lub początkowa zawartość ROM w TOML | Ponownie wykonać `scripts/build_tool.sh` i uruchomić nowy plik wykonywalny. |
| Źródła monitora WozMon | Złożyć ROM monitora, zaktualizować TOML i przebudować symulator — polecenia poniżej. |
| Obsługa instrukcji / generator mikrokodu | Zbudować `lcct`, wygenerować zgodny LUT i dopiero przebudować komputer. Sam program użytkownika tego nie wymaga. |

Aby odtworzyć TOML z ROM-em WozMon po zmianie monitora lub bazowego schematu:

```bash
"$LCCT" asm examples/wozmon-acia.asm --isa:mos6502-safe --format:mem \
  -o:programs/wozmon-acia.hex

python3 tools/prepare_terminal.py --mode acia examples/cpu65c02.toml \
  programs/wozmon-acia.hex programs/cpu65c02-wozmon.toml

scripts/build_tool.sh programs/cpu65c02-wozmon.toml cpu65c02-wozmon
./build-cpu65c02-wozmon/lcsim-gui --technology lvc
```

Bazą jest już zaktualizowany schemat r12 `examples/cpu65c02.toml`.
Skrypt dodaje terminal i wstawia obraz ROM. Zachowaj w źródle monitora
wypełnienie od `$F000`, kod od `$FF00` i wektor resetu pod `$FFFC`.
Nie wstawiaj `hello.bin` do ROM monitora: to program złożony do uruchamiania w RAM.

## Adresy, o których trzeba pamiętać

| Zakres / adres | Zastosowanie |
| --- | --- |
| `$0000..$0FFF` | RAM; WozMon zajmuje `$24..$2B` oraz bufor `$0200..$027F`. |
| `$0100..$01FF` | Stos sprzętowy — nie umieszczaj tu kodu. |
| `$0400..$0FFF` | Proponowany obszar na własny kod i dane; sam pilnuj ich rozdzielenia. |
| `$5000` | Dane terminala ACIA: zapis znaku / odczyt klawiatury. |
| `$5001` | Status: bit 3 oznacza gotowy znak z klawiatury. |
| `$F000..$FFFF` | ROM komputera. |
| `$FF00` | Początek tej wersji WozMon. |

Po ponownym uruchomieniu aplikacji wczytaj program do RAM jeszcze raz.
Dla kolejnych prób zwykle wystarczy edytować ASM, złożyć go i powtórzyć krok 5.
Profil `mos6502-safe` opisuje zaimplementowany podzbiór instrukcji; nie jest
pełnym zestawem 65C02. Asembler zgłasza nieobsługiwane formy.
