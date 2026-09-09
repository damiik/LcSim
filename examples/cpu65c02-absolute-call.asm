; r8: absolute addressing + nested JSR/RTS + stack/page boundaries.
; All checks jump to fail ($FF00), which stores $DE at $0FFF.
.org $F000
start:
  ldx #$FF
  txs
  jsr absolute_test
  jsr call_outer
  tsx
  stx $02F0
  ldx #$00
  txs
  jsr wrap_call
  tsx
  stx $02F1
  ldx #$FF
  txs
  jmp boundary_call
.org $F0FE
boundary_call:
  jsr leaf                  ; pushes F100; RTS returns to F101
boundary_return:
  lda #$A5
  sta $0FFF
  jmp done
.org $F180
done:
  bra done
.org $F200
absolute_test:
  lda #$42
  sta $0200
  lda #$00
  lda $0200
  cmp #$42
  beq check_1
  jmp fail
check_1:
  ldx #$99
  stx $0300
  ldx #$00
  ldx $0300
  cpx #$99
  beq check_2
  jmp fail
check_2:
  ldy #$55
  sty $0FFE
  ldy #$00
  ldy $0FFE
  cpy #$55
  beq check_3
  jmp fail
check_3:
  lda #$7F
  sta $0201
  clc
  lda #$01
  adc $0201
  bcc check_4
  jmp fail
check_4:
  bvs check_5
  jmp fail
check_5:
  bmi check_6
  jmp fail
check_6:
  cmp #$80
  beq check_7
  jmp fail
check_7:
  sec
  lda #$90
  sbc $0201
  bcs check_8
  jmp fail
check_8:
  bvs check_9
  jmp fail
check_9:
  cmp #$11
  beq check_10
  jmp fail
check_10:
  lda #$F0
  and $0200
  cmp #$40
  beq check_11
  jmp fail
check_11:
  ora $0201
  cmp #$7F
  beq check_12
  jmp fail
check_12:
  eor $0200
  cmp #$3D
  beq check_13
  jmp fail
check_13:
  lda #$7F
  cmp $0201
  beq check_14
  jmp fail
check_14:
  bcs check_15
  jmp fail
check_15:
  ldx #$42
  cpx $0200
  beq check_16
  jmp fail
check_16:
  ldy #$41
  cpy $0200
  bcc check_17
  jmp fail
check_17:
  inc $0200
  lda $0200
  cmp #$43
  beq check_18
  jmp fail
check_18:
  dec $0200
  lda $0200
  cmp #$42
  beq check_19
  jmp fail
check_19:
  asl $0200
  bcc check_20
  jmp fail
check_20:
  bmi check_21
  jmp fail
check_21:
  rol $0200
  bcs check_22
  jmp fail
check_22:
  ror $0200
  bcc check_23
  jmp fail
check_23:
  lsr $0200
  bcc check_24
  jmp fail
check_24:
  lda $0200
  cmp #$42
  beq check_25
  jmp fail
check_25:
  lda $FE00
  cmp #$69
  beq check_26
  jmp fail
check_26:
  rts
.org $F500
call_outer:
  lda #$AA
  pha
  jsr call_inner
outer_return:
  pla
  cmp #$AA
  beq check_27
  jmp fail
check_27:
  rts
.org $F600
call_inner:
  lda #$33
  sta $0202
  rts
.org $F700
wrap_call:
  lda #$5A
  pha
  pla
  cmp #$5A
  beq check_28
  jmp fail
check_28:
  rts
.org $F800
leaf:
  rts
.org $FE00
.byte $69
.org $FF00
fail:
  lda #$DE
  sta $0FFF
fail_loop:
  bra fail_loop
.org $FFFC
.word start
.word $0000
