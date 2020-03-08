; iNES header data
.segment "HEADER"
	.byte "NES"
	.byte $1a ; iNES header signature
	.byte $02 ; 2*16KB PRG ROM chips
	.byte $01 ; 1*8KB CHR ROM chip
	.byte $00 ; mapping/mirroring info
	.byte $00
	.byte $00
	.byte $00
	.byte $00
	; filler bytes to pad out header
	.byte $00,$00,$00,$00,$00

; zero page for slightly more efficient memory access
.segment "ZEROPAGE"

; actual code segment
.segment "STARTUP"
Reset:
	SEI	; disables interrupts so nothing disturbs startup code
	CLD ; disables decimal mode, which NESASM doesn't support
	
	; disable sound interrupts by writing to mapped sound register
	LDX #$40
	STX $4017

	; initialize the stack
	LDX #$FF
	TXS
	INX	; overflow x-register back to 0

	; disable graphical display by zeroing out graphics registers
	STX $2000
	STX $2001

	; disable PCM channel to prevent weird sounds during startup
	STX $4010

:	; wait for a vblank
	BIT $2002	; retrieve status bit from vblank register
	BPL :-

	TXA	; transfer the 0 from X to A - more efficient than LDA

; subroutine to clear out all the system memory
MEMCLEAR:
	STA $0000, X
	STA $0100, X
	STA $0300, X
	STA $0400, X
	STA $0500, X
	STA $0600, X
	STA $0700, X
	; reserve $0200 => $02FF for graphics
	LDA #$FF
	STA $0200, X
	LDA #$00
	INX	; X will overflow back to 0 when the loop is done
	BNE MEMCLEAR

:	; wait on another vblank
	BIT $2002	; retrieve status bit from vblank register
	BPL :-

	; copy graphics data into the PPU memory
	LDA #$02	; most significant byte of graphics address
	STA $4014	; memory mapped out to the PPU
	NOP	; PPU needs an extra cycle to copy over graphics

	; tell the PPU to write to $3F00 in its memory
	LDA #$3F	; MSB
	STA $2006
	LDA #$00	; LSB
	STA $2006

	; write palette data to PPU memory
	LDX #$00
LoadPalettes:
	LDA PaletteData, X
	STA $2007	; register mapped out to the PPU
	INX
	CPX #$20
	BNE LoadPalettes

	; load the character into entity memory below

	; reenable interrupts
	CLI

	; initialize register $2000 to re-enable vblank and
	; specify location of background tilesheet
	LDA #%10010000
	STA $2000

	; initialize register $2001 to enable drawing
	LDA #%00011110
	STA $2001

GameLoop:	; main game logic loop
	JMP GameLoop

VBLANK:
	
	; copy sprite data from memory into the PPU using
	; memory-mapped $4014 PPU register
	LDA #$02
	STA $4014

	RTI	; interrupt return

; store palette data here
PaletteData:
	.byte $22,$29,$1A,$0F,$22,$36,$17,$0f,$22,$30,$21,$0f,$22,$27,$17,$0F  ;background palette data
	.byte $22,$16,$27,$18,$22,$1A,$30,$27,$22,$16,$30,$27,$22,$0F,$36,$17  ;sprite palette data

; put background nametable here

; interrupt handlers
.segment "VECTORS"
	.word VBLANK
	.word Reset
	; specialized interrupt handler goes here

; external graphics files
.segment "CHARS"
	.incbin "empty.chr"
