; Program embedded in examples/cpu65c02.toml.
; Transitional r6 stack test for the still 8-bit PC/MAR machine.

.org $00
  ldx #$ff
  txs

  lda #$42
  pha
  ldx #$99
  phx
  ldx #$00
  plx
  stx $83                  ; main RAM[$03] = $99

  lda #$00
  pla
  sta $84                  ; main RAM[$04] = $42

  ldy #$55
  phy
  ldy #$00
  ply
  sty $88                  ; main RAM[$08] = $55

  tsx
  stx $85                  ; S restored to $ff

  ldx #$00
  txs
  ldx #$7e
  phx                      ; stack[$00] = $7e, S wraps to $ff
  tsx
  stx $86                  ; main RAM[$06] = $ff
  plx                      ; S wraps to $00, X = $7e
  stx $87                  ; main RAM[$07] = $7e

done:
  bra done
