# CPU65C02 r8 — adresowanie absolutne i JSR/RTS

Schemat bazuje na przesłanym `cpu65c02(2).toml`. Zachowuje istniejące pozycje,
kolory, kształty i dekoracyjne NODE. Rozdziela jedynie przypadkowe zwarcie
`PC_ADR.PC15` z `PC_ADR.PC14`. Nowa logika składa się ze zwykłych modułów i bramek;
nie dodaje instrukcji CPU do silnika LcSim.

Zapis pamięci został doprecyzowany w [poprawce r9](cpu65c02-memory-radix-r9.md).
Każde słowo inline `m` ma teraz jawny prefiks `0x`.

## Uruchomienie

Domyślny ProgramROM zawiera już `examples/cpu65c02-absolute-call.hex`, a Control
ROM zawiera nowy mikrokod. Nie trzeba ręcznie wklejać obrazów pamięci.

```sh
# W katalogu LcSim:
make test test-cpu
make gui DESIGN=examples/cpu65c02.toml BUILD=build-cpu
./build-cpu/lcsim-gui --technology lvc
```

`RAYLIB_DIR` zachowuje dotychczasową wartość `../third_party/raylib`.
Dla headless użyj `make DESIGN=examples/cpu65c02.toml BUILD=build-cpu`, a następnie:

```sh
./build-cpu/lcsim --technology fpga --steps 20000 --vcd cpu-r8.vcd
```

RESET odczytuje `$FFFC/$FFFD`, w tym przykładzie `$F000`. Po około 17000 kroków
symulacji test dochodzi do pętli `done` pod `$F180`. Nie zmieniaj okresu CLK na
potrzeby tego testu. Są to kroki LcSim, nie cykle oryginalnego procesora 65C02.

| Adres MainRAM | Oczekiwane | Znaczenie |
|---|---|---|
| `$0FFF` | `$A5` | sukces całego programu; `$DE` oznacza wejście do `fail` |
| `$0200` | `$42` | odczyt, zapis, INC/DEC i przesunięcia absolutne |
| `$0201` | `$7F` | operand ALU |
| `$0202` | `$33` | wykonanie zagnieżdżonego podprogramu |
| `$0300` | `$99` | STX/LDX |
| `$0FFE` | `$55` | STY/LDY przy końcu RAM |
| `$02F0` | `$FF` | S po zagnieżdżonym wywołaniu |
| `$02F1` | `$00` | S po wywołaniu z zawinięciem stosu |
| `$0100` | `$F0` | starszy bajt powrotu zapisany przy S=00 |
| `$01FF`, `$01FE` | `$F1`, `$00` | adres powrotu F100: starszy bajt, potem młodszy |

Końcowo `S=$FF`; w pętli końcowej widoczny PC to `$F180` lub `$F181` zależnie
od mikrokroku. Stos jest częścią MainRAM: w przeglądarce wspólnego RAM adresy
stosu to `$0100..$01FF`, nie `$00..$FF`.

## Instrukcje i tor adresowy

Nowe 23 formy podnoszą profil `mos6502-safe` do 107 form / 54 mnemoników:

| Instrukcja | Opcode absolutny |
|---|---|
| JMP, JSR, RTS (RTS bez argumentu) | 4C, 20, 60 |
| LDA, LDX, LDY | AD, AE, AC |
| STA, STX, STY | 8D, 8E, 8C |
| AND, ORA, EOR | 2D, 0D, 4D |
| ADC, SBC | 6D, ED |
| CMP, CPX, CPY | CD, EC, CC |
| INC, DEC | EE, CE |
| ASL, LSR, ROL, ROR | 0E, 4E, 2E, 6E |

Operand 16-bitowy jest kodowany jako młodszy, potem starszy bajt. TMP przechowuje
młodszy bajt, nowy rejestr ADH — starszy. `MAR_IN_S1:S0=11` wybiera `ADH:TMP`;
pozostałe wybory pozostają: 00=zp/DBR, 01=PC, 10=zp indexed/EA. `MAR_STACK` ma
nadal priorytet i wymusza `$0100|S`. Mapa RAM/ROM nie zmienia się względem r7.

`PC_ADDR` wybiera `ADH:TMP` jako źródło ładowania PC; wybór wektora resetu ma
pierwszeństwo. Nowy bufor PCH uzupełnia istniejący bufor PCL na magistrali DATA.

JSR zapisuje `adres instrukcji + 2`, najpierw PCH, potem PCL, zmniejszając S po
każdym zapisie. RTS zwiększa S przed każdym odczytem, odczytuje PCL, następnie
PCH, ładuje PC i zwiększa go o jeden. JSR i RTS zachowują flagi. Program sprawdza
wywołania zagnieżdżone, mieszanie z PHA/PLA, zawijanie S i wywołanie z operandem
przechodzącym przez granicę `$F0FF/$F100`.

## Mikrokod i wgrywanie ROM

STEP ma teraz 4 bity, a słowo sterujące 45 bitów. Bity 0..41 zachowują funkcje.

| Bit | Sygnał | Aktywność |
|---:|---|---|
| 42 | ADH_LOAD | 1: przechwycenie DATA do ADH |
| 43 | PC_ADDR | 1: źródło PC = ADH:TMP |
| 44 | PCH_OE_N | 0: starszy bajt PC na DATA |

Control ROM ma `aw=13`, `dw=45`: A0..7=IR, A8..11=STEP, A12=BOOT.ACTIVE.
`lcct lut` generuje **4096 słów banku wykonania**. Skrypt instalujący dopisuje
4096 słów banku rozruchowego `10600009F7F1`, zwalniających także PCH_OE_N.
Nie wklejaj samego banku wykonania w miejsce całej pamięci Control ROM.
Stare 2048-słowowe obrazy r6/r7 nie pasują do tego schematu.

Po zastosowaniu osobnego patcha do narzędzi Nim i przebudowie `lcct`:

```sh
lcct asm examples/cpu65c02-absolute-call.asm --isa:mos6502-safe \
  -o:examples/cpu65c02-absolute-call.hex --listing:build/cpu-r8.lst
lcct lut --isa:mos6502-safe -o:build/control-r8.hex --explain:build/microcode-r8.md
python3 tools/cpu65c02_image.py examples/cpu65c02.toml \
  --program examples/cpu65c02-absolute-call.hex --control build/control-r8.hex
```

Skrypt nadal rozpoznaje starszy schemat r7 i jego format 2048×42, ale odrzuca
obrazy sterowania o niezgodnym rozmiarze. Obraz programu jest liczony od F000,
zawiera 4094..4096 bajtów wraz z wektorem RESET; brakujące końcowe bajty są zerowane.
Wgrywanie nie zmienia układu graficznego schematu.

## Sprawdzone i pozostałe etapy

C++: program r8 i poprzedni r7 w LVC/FPGA, cache włączony/wyłączony; porównanie
pełnych znaczników czasu i wartości zmian sygnałów. Nim: rzeczywista kompilacja,
assembler, generator LUT, disassembler i niezależny model instrukcyjny wykonujący
wszystkie 23 nowe formy. Test r7 jest ładowany osobno, aby nadal sprawdzać reset,
zawijanie PC, skoki względne przez granice stron oraz stos A/X/Y.

To nadal podzbiór 65C02 z binarnymi ADC/SBC. Następne etapy: absolutne X/Y i tryby
pośrednie, PHP/PLP oraz BRK/RTI/IRQ/NMI, następnie terminal i klawiatura mapowane
w pamięci. Nie ma jeszcze zgodności cyklowej ani pełnej emulacji KIM-1.
