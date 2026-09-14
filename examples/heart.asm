; Program wyświetlający serduszko na terminalu ACIA
; Dla symulatora 65C02 z WozMon (ACIA_DATA = $5000)
;
; **  **
;********
;********
;********
; ******
;  ****
;   **

ACIA_DATA = $5000
TEMP      = $00

        .org $0500
        LDA #$0C
        STA ACIA_DATA
        LDA #$0A          ; LF
        STA ACIA_DATA
START:  LDY #$00          ; indeks bajtu serduszka
NEXT:   LDA HEART,Y       ; pobierz bajt wzoru
        STA TEMP          ; zapisz do zmiennej tymczasowej
        LDX #$08          ; 8 bitów do wyświetlenia
BIT:    LDA TEMP          ; załaduj aktualny stan bajtu
        ASL A             ; przesuń w lewo, MSB do carry
        STA TEMP          ; zapisz z powrotem
        BCC SPACE         ; jeśli bit = 0, idź do SPACE
        LDA #'*'          ; bit = 1 -> gwiazdka
        BRA OUT
SPACE:  LDA #' '          ; bit = 0 -> spacja
OUT:    STA ACIA_DATA     ; wyślij znak do terminala
        DEX
        BNE BIT           ; powtórz dla wszystkich 8 bitów
        ;LDA #$0D          ; CR
        ;STA ACIA_DATA
        LDA #$0A          ; LF
        STA ACIA_DATA
        INY
        CPY #$07          ; czy wyświetlono wszystkie 7 wierszy?
        BNE NEXT
        JMP $FF00         ; powrót do WozMon (RESET)

HEART:  .byte $66,$FF,$FF,$FF,$7E,$3C,$18


