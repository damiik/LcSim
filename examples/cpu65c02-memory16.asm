; r7 gate-level PC16/MAR16 / unified RAM regression.
; Assemble with lcct asm ... --isa:mos6502-safe --format:mem.
; The first byte anchors compact output at ROM base $F000.
.org $F000
.byte $EA
.org $F0D0
start:
  ldx #$ff
  txs

  lda #$42
  pha
  ldx #$99
  phx
  ldx #$00
  plx
  stx $83                  ; RAM[$0083] = $99

  lda #$00
  pla
  sta $84                  ; RAM[$0084] = $42

  ldy #$55
  phy
  ldy #$00
  ply
  sty $88                  ; RAM[$0088] = $55

  tsx
  stx $85                  ; S restored to $ff

  ldx #$00
  txs
  ldx #$7e
  phx                      ; RAM[$0100] = $7e, S wraps to $ff
  tsx
  stx $86                  ; RAM[$0086] = $ff
  plx                      ; S wraps to $00, X = $7e
  stx $87                  ; RAM[$0087] = $7e

; F0FA: exercise sequential carry and a taken backward branch across a page.
  ldx #$03
page_loop:                  ; F0FC
  dex
  nop
  nop
  bne page_loop             ; F0FF: next PC F101 + (-5) = F0FC
  stx $89                   ; RAM[$0089] = 0
  bra forward_page          ; F103 -> F180
.org $F180
forward_page:
  bra success               ; F180 + 2 + 126 = F200
.org $F200
success:
  lda #$A5
  sta $8A                   ; success signature, RAM[$008A] = $A5
done:                       ; F204
  bra done
.org $FFFC
.word start                 ; D0 F0, little endian reset vector
.word $0000                 ; IRQ/BRK reserved, not implemented
