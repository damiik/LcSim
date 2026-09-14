; r12 gate-level regression: BIT flags, indexed carry and indirect wrap.
.org $F000
start:
  lda #$C0
  sta $60
  lda #$0F
  sec
  bit $60
  beq check_1
  jmp fail
check_1:
  bmi check_2
  jmp fail
check_2:
  bvs check_3
  jmp fail
check_3:
  bcs check_4
  jmp fail
check_4:
  cmp #$0F
  beq check_5
  jmp fail
check_5:
  lda #$40
  sta $60
  lda #$80
  clc
  bit $60
  beq check_6
  jmp fail
check_6:
  bpl check_7
  jmp fail
check_7:
  bvs check_8
  jmp fail
check_8:
  bcc check_9
  jmp fail
check_9:
  cmp #$80
  beq check_10
  jmp fail
check_10:
  lda #$80
  sta $60
  lda #$80
  sec
  bit $60
  bne check_11
  jmp fail
check_11:
  bmi check_12
  jmp fail
check_12:
  bvc check_13
  jmp fail
check_13:
  bcs check_14
  jmp fail
check_14:
  cmp #$80
  beq check_15
  jmp fail
check_15:
  lda #$01
  sta $60
  lda #$01
  clc
  bit $60
  bne check_16
  jmp fail
check_16:
  bpl check_17
  jmp fail
check_17:
  bvc check_18
  jmp fail
check_18:
  bcc check_19
  jmp fail
check_19:
  cmp #$01
  beq check_20
  jmp fail
check_20:
  ldy #$02
  lda #$42
  sta $04FE,Y
  lda $04FE,Y
  cmp #$42
  beq check_21
  jmp fail
check_21:
  lda #$7F
  sta $0503,Y
  lda $0503,Y
  cmp #$7F
  beq check_22
  jmp fail
check_22:
  lda #$00
  sta $FF
  lda #$05
  sta $00
  ldx #$05
  lda ($FA,X)
  cmp #$42
  beq check_23
  jmp fail
check_23:
  lda #$A5
  sta ($FA,X)
  lda $0500
  cmp #$A5
  beq check_24
  jmp fail
check_24:
  lda #$01
  sta $00
  lda #$05
  sta $01
  lda #$33
  sta ($FB,X)
  lda $0501
  cmp #$33
  beq check_25
  jmp fail
check_25:
  lda ($FB,X)
  cmp #$33
  beq check_26
  jmp fail
check_26:
  ldy #$01
  lda #$9A
  sta $FFFF,Y
  lda $FFFF,Y
  cmp #$9A
  beq check_27
  jmp fail
check_27:
  lda #$00
  sta $03FF
  lda #$F3
  sta $0400
  lda #$00
  sta $0300
  jmp ($03FF)
.org $F300
page_target:
  lda #$F3
  sta $00
  jmp ($FFFF)
.org $F380
done:
  lda #$A5
  sta $0800
halt:
  bra halt
.org $F3F0
fail:
  lda #$EE
  sta $08FF
failed:
  bra failed
.org $FFFC
.word start
.byte $00, $80
