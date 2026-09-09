# r10: konflikt wewnętrznego selektora ALU

Przy PC=F270 procesor wciąż wykonuje AND $0200 (opcode 2D spod F26D), mikrokrok
T7. PC wskazuje już kolejną instrukcję CMP #40. Problem odtworzono w TypeScript
w obu technologiach, z identycznym komunikatem: ALU_OUT.D4..D7 oraz ALU_N.

ALU8 wybierało ADD/SUB, AND, OR lub XOR przez cztery TBUF na każdy bit, łącząc
ich wyjścia. Dekoder OP0/OP1 używa również negatorów, więc przy zmianie wyboru
nowy bufor może włączyć się przed wyłączeniem starego. Powstaje krótki rzeczywisty
konflikt wewnętrznych nadajników. NEGATIVE jest tym samym bitem co R7.
Raport na głównym schemacie pokazuje port modułu ALU, a nie parę wewnętrznych TBUF.

Przed poprawką alarm pojawia się w teście LVC na kroku 5514 i znika na następnym;
w FPGA odpowiednio 5512/5513. To próbki na granicach kroków, nie pomiar dokładnej
długości impulsu. Interfejs zatrzymuje symulację na alarmie, podczas gdy poprzedni
test headless sprawdzał końcową sygnaturę i pozwalał układowi dalej pracować.

## Zmiana

32 bufory selektora zastąpiono 8 bramkami MUX4:

| OP1:OP0 | Wejście MUX4 | Wynik |
|---|---|---|
| 00 | I0 | ADD/SUB |
| 01 | I1 | AND |
| 10 | I2 | OR |
| 11 | I3 | XOR |

OP0 jest młodszym bitem adresu (A), OP1 starszym (B). Każdy bit ma jeden nadajnik.
MUX4 zachowuje opóźnienie z wybranej technologii. Nie wyłączono detekcji konfliktów.
Istniejące NODE, porty ALU i punkty obserwacji dekodera OpXX pozostają w schemacie.
Nie zmieniono workspace, programu, mikrokodu ani zawartości pamięci.

## Instalacja i test

Patch jest przyrostowy względem r9. W katalogu zawierającym LcSim:

```sh
git apply --check logic-cosmos-lcsim-alu-selector-r10.patch
git apply logic-cosmos-lcsim-alu-selector-r10.patch
```

Ponownie wczytaj `LcSim/examples/cpu65c02.toml` w LogicCosmos i uruchom od resetu.
Dla skompilowanego LcSim przebuduj program z nowego TOML. Nie trzeba regenerować
LUT ani przebudowywać narzędzi Nim.

Test TypeScript sprawdza teraz konflikty po krokach symulacji przy zmianie ich
rewizji, używając tej samej funkcji co interfejs. Ze starym r9 test odtwarza pięć
zgłoszonych linii i kończy się błędem; z r10 cały program przechodzi bez tych
alarmów w LVC i FPGA. Sprawdza też PC=F180/F181, S=FF i RAM[0FFF]=A5.

```sh
cd /sciezka/do/logic_cosmos
node --import tsx /sciezka/do/LcSim/tests/cpu_logiccosmos.ts .
# Opcjonalny trzeci argument: inny plik cpu65c02.toml z tym samym programem testowym.
```

Test C++ `make test-cpu` obejmuje nadal programy r8 oraz r7, obie technologie,
cache wyłączony/włączony i zgodność przebiegów przy zmianie ustawienia cache.
