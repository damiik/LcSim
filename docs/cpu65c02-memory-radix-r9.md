# r9: jednoznaczny zapis pamięci dla LcSim i LogicCosmos

Poprawka dotyczy zapisu pamięci, bez zmian bramek, połączeń, mikrokodu ani silnika
symulacji. LcSim traktuje słowo bez prefiksu jako hex. LogicCosmos zachowuje
historyczną regułę: same cyfry oznaczają liczbę dziesiętną; litery A–F lub prefiks
0x oznaczają hex. Dlatego każdy zapisany do TOML wyraz pamięci musi mieć `0x`.

## Przyczyna zwarcia

W Control ROM słowo dla `LDY #imm`, opcode A0, mikrokrok T3, ma wartość
`0x106180099773`. W r8 zapisano je jako `106180099773`. LogicCosmos odczytywał
liczbę dziesiętną, czyli `0x18B8D3BEBD`:

| Sygnał | Prawidłowo | Błędna interpretacja |
|---|---:|---:|
| A_OE_N (bit 8) | 1 | 0 |
| S_OE_N (bit 38) | 1 | 0 |
| PCH_OE_N (bit 44) | 1 | 0 |

To rzeczywiste jednoczesne włączenie buforów w modelu, a nie fałszywy alarm
analizatora. Przy pierwszym LDY rejestry A=42, S=FD i PCH=F2 sterują DATA różnymi
wartościami. Wszystkie trzy mają bit 6 równy 1, stąd brak zgłoszenia DATA.D6.

Przesłany VCD kończy się na T3 przy PC=F223 (LDY #55), tuż przed opublikowaniem
tego słowa. Wcześniejszy stos 01FF=F0, 01FE=05 jest poprawnym zapisem adresu
powrotu z pierwszego JSR. ProgramROM ma ten sam problem dla zapisów takich jak
`20`, `55`, `80`; dlatego poprawka obejmuje obie pamięci ROM.

## Zastosowanie

Patch jest przyrostowy względem r8. Zawiera poprawiony przykład oraz skrypt.
Jeśli lokalny TOML został już przeedytowany lub ROM był wklejany ręcznie,
zastosuj zmiany kodu z pominięciem przykładu (z katalogu zawierającego LcSim):

```sh
git apply --exclude=LcSim/examples/cpu65c02.toml logic-cosmos-lcsim-memory-radix-r9.patch
cd LcSim
python3 tools/cpu65c02_image.py examples/cpu65c02.toml --canonical-hex
```

`--canonical-hex` zachowuje znaczenie liczb według LcSim i nadaje im jawny prefiks
0x. Zachowuje współrzędne, opisy, NODE, połączenia i inne właściwości; aktualizuje
wyłącznie zapis inline `m`. Może objąć także RAM. Nie odczytuje plików `mf`.
Opcja służy do migracji pliku działającego w LcSim — nie do zgadywania podstawy
liczb w dowolnym pliku zawierającym zamierzone wartości dziesiętne. Można użyć
`-o poprawiony.toml`, aby zapisać wynik pod inną nazwą.

Po ponownym wczytaniu pliku w LogicCosmos uruchom test od resetu.
Oczekiwane: PC=F180/F181, S=FF, MainRAM[0FFF]=A5, stos 01FB..01FF = 05 F5 AA 00 F1.

Nowe instalacje przez `--program` i `--control` zawsze zapisują prefiksy, nawet
jeśli wartości liczbowe są identyczne z dotychczasowymi. Polecenie `lcct lut`
pozostaje poprawne; problem wprowadzał etap przepisywania jego wyniku do TOML.
Nie ma nowego patcha Nim ani zmian formatu sprzętowego (nadal 4096×45 plus bank boot).

## Weryfikacja

- Odtworzono awarię w TypeScript z poprawnym ProgramROM i niejednoznacznym Control ROM.
- Po jawnych prefiksach cały program r8 przechodzi w TypeScript LVC i FPGA:
  zagnieżdżone JSR/RTS, stos i pełna sygnatura RAM.
- Opcjonalny test integracyjny z zewnętrznym checkoutem LogicCosmos:

```sh
cd /sciezka/do/logic_cosmos
node --import tsx /sciezka/do/LcSim/tests/cpu_logiccosmos.ts .
```

- Testy Python sprawdzają problematyczne słowo LDY, jawne prefiksy, migrację,
  zachowanie danych i ponowne uruchomienie bez kolejnych zmian.
- Generowany C++ pozostaje identyczny: zmienił się tylko jednoznaczny zapis liczb.

Weryfikacja r8 obejmowała wcześniej parser/serializer TypeScript, ale wykonanie
CPU sprawdzano w C++. Sam round-trip nie wykrył problemu, ponieważ parser
zachowuje surowy tekst pamięci; dopiero silnik interpretuje podstawę liczb.
