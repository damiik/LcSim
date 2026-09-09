; LcMon: independently implemented WozMon-style monitor for the r8 CPU subset.
; Commands: address, start.end, address: bytes, address R. Uppercase ASCII.
; Not the original 256-byte Apple-1 ROM; no unsupported 65C02 opcodes required.
; Reserved: ZP $20..$29, input $0200..$027F, RAM trampolines $0300..$030A.
PTR = $20
PTRH = $21
LAST = $22
LASTH = $23
WORD = $24
WORDH = $25
DIGIT = $26
HAVE = $27
MODE = $28
KBD = $D010
STATUS = $D011
DSP = $D012
CONTROL = $D013
READ = $0300
WRITE = $0304
EXEC = $0308
.org $F000
.byte $00
.org $F800
reset:
  ldx #$FF
  txs
  lda #$AD
  sta READ
  lda #$8D
  sta WRITE
  lda #$60
  sta READ+3
  sta WRITE+3
  lda #$4C
  sta EXEC
  lda #$A7
  sta CONTROL
  sta STATUS
  lda #$00
  sta PTR
  sta PTRH
prompt:
  lda #$DC
  jsr echo
  lda #$8D
  jsr echo
  ldx #$00
getkey:
  lda STATUS
  bpl getkey
  lda KBD
  cmp #$9B
  beq prompt
  cmp #$DF
  bne accept_key
  cpx #$00
  beq getkey
  dex
  jsr echo
  jmp getkey
accept_key:
  jsr putbuf
  jsr echo
  cmp #$8D
  beq parse_line
  inx
  bpl getkey
  jmp prompt
parse_line:
  ldx #$00
  lda #$00
  sta MODE
  jsr clear_word
next_char:
  jsr getbuf
  and #$7F
  cmp #$0D
  bne not_end
  jsr commit
  jmp prompt
not_end:
  cmp #$20
  bne not_space
  jsr commit
  jmp advance_char
not_space:
  cmp #$3A
  bne not_colon
  jsr commit
  lda #$01
  sta MODE
  jmp advance_char
not_colon:
  cmp #$2E
  bne not_dot
  jsr commit
  lda #$02
  sta MODE
  jmp advance_char
not_dot:
  cmp #$52
  bne not_run
  jsr commit
  lda PTR
  sta EXEC+1
  lda PTRH
  sta EXEC+2
  jmp EXEC
not_run:
  cmp #$30
  bcc bad_line
  cmp #$3A
  bcc digit_number
  cmp #$41
  bcc bad_line
  cmp #$47
  bcs bad_line
  sec
  sbc #$37
  jmp append_digit
digit_number:
  sec
  sbc #$30
append_digit:
  sta DIGIT
  ldy #$04
shift_digit:
  asl WORD
  rol WORDH
  dey
  bne shift_digit
  lda WORD
  ora DIGIT
  sta WORD
  lda #$01
  sta HAVE
advance_char:
  inx
  jmp next_char
bad_line:
  jmp prompt
clear_word:
  lda #$00
  sta WORD
  sta WORDH
  sta HAVE
  rts
commit:
  lda HAVE
  bne has_word
  rts
has_word:
  lda MODE
  cmp #$01
  beq store_word
  cmp #$02
  beq range_word
  lda WORD
  sta PTR
  lda WORDH
  sta PTRH
  jsr print_cell
  jmp clear_word
store_word:
  lda PTR
  sta WRITE+1
  lda PTRH
  sta WRITE+2
  lda WORD
  jsr WRITE
  jsr increment_ptr
  jmp clear_word
range_word:
  lda WORD
  sta LAST
  lda WORDH
  sta LASTH
range_loop:
  lda PTRH
  cmp LASTH
  bcc range_more
  bne range_done
  lda PTR
  cmp LAST
  bcs range_done
range_more:
  jsr increment_ptr
  jsr print_cell
  jmp range_loop
range_done:
  lda #$00
  sta MODE
  jmp clear_word
increment_ptr:
  inc PTR
  bne increment_done
  inc PTRH
increment_done:
  rts
print_cell:
  lda #$8D
  jsr echo
  lda PTRH
  jsr print_byte
  lda PTR
  jsr print_byte
  lda #$BA
  jsr echo
  lda #$A0
  jsr echo
  lda PTR
  sta READ+1
  lda PTRH
  sta READ+2
  jsr READ
  jsr print_byte
  rts
print_byte:
  pha
  lsr A
  lsr A
  lsr A
  lsr A
  jsr print_nibble
  pla
print_nibble:
  and #$0F
  cmp #$0A
  bcc decimal_digit
  clc
  adc #$07
decimal_digit:
  clc
  adc #$30
  jmp echo
putbuf:
  pha
  stx WRITE+1
  lda #$02
  sta WRITE+2
  pla
  jmp WRITE
getbuf:
  stx READ+1
  lda #$02
  sta READ+2
  jmp READ
echo:
  pha
wait_display:
  lda DSP
  bmi wait_display
  pla
  sta DSP
  rts
; Conventional Apple-1 character output entry point for user programs.
.org $FFEF
  jmp echo
.org $FFFC
  .word reset
  .word $0000
