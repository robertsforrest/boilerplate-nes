; TODO:
;	add attribute table loading to level loader

;-------- iNES header data for emulation --------;
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

;----------- Data structures & scopes ------------;


;-------------- Defines & constants --------------;
OAM				= $0200
LVL_METATILES 	= $F0
METATILE_SIZE	= $04

;----- Zero page for efficient memory access -----;
.segment "ZEROPAGE"
loptr:			.res 1	; reserve a 16-bit pointer
hiptr:			.res 1
input:			.res 1	; store input as a 1-byte bit vector
data:			.res 1  ; general purpose data registers
data2:			.res 1
data3:			.res 1
metatile_ptr:	.res 2	; 16-bit pointer to metatile data
load_bg_buf:	.res 64 ; buffer for loading metatiles into PPU
draw_finished:	.res 1  ; flag used to sync game loop w/ vblank

;------------------- Game code -------------------;
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

;---------- Clear out system memory -----------;
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

;----- Initialize graphics data & registers -----;
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

;---------- Load palette data into PPU ----------;
	LDX #$00
LoadPalettes:
	LDA PaletteData, X
	STA $2007	; register mapped out to the PPU
	INX
	CPX #$20
	BNE LoadPalettes

;----- Load initial background data into PPU -----;
LoadBackground:
	; prepare the background pointer
	LDA #.LOBYTE(BackgroundData)
	STA loptr
	LDA #.HIBYTE(BackgroundData)
	STA hiptr
	JSR LoadLevel

;------ Load background attribute table -------;
LoadAttributes:
	LDA $2002	; reset high/low latch
	LDA #$23
	STA $2006	; write high byte of $23C0 (just past background data)
	LDA #$C0
	STA $2006	; write low byte of $23C0
	LDX #$00	; prepare loop counter
:
	LDA AttributeData, X
	STA $2007	; map out to PPU memory
	INX
	CPX #40		; 64 bytes of attribute table data
	BNE :-

;---------- Initialize zeropage data ---------;
	LDA #$00
	STA draw_finished

;-------------- Finishing setup --------------;
	; reenable interrupts
	CLI

	; initialize register $2000 to re-enable vblank and
	; specify location of background tilesheet
	LDA #%10010000
	STA $2000

	; initialize register $2001 to enable drawing
	LDA #%00011110
	STA $2001

;---------- Main logic loop for the game ----------;
GameLoop:
	LDA #$00
	STA draw_finished

;--- Fetch input from register into byte vector ---;
GetInput:
	LDA #$01	; latch and strobe input register
	STA $4016
	LDA #$00
	STA $4016
	LDX #$08	; do some bit shifting to get inputs into zero page vector
:
	LDA $4016	; read in the next bit of the button vector
	LSR A 		; move bit 0 out into the carry bit
	ROL input	; move the carry bit into bit 0 of the Buttons label in the zero page
	DEX
	BNE :-

	; Process the next frame
GameLogicDone:
	LDA draw_finished
	BEQ GameLogicDone
	JMP GameLoop

;----------------- Subroutines ----------------;
; When calling LoadLevel, have pointer pre-loaded into loptr/hiptr
LoadLevel:
	LDA $2002	; reset PPU high/low latch with a read
	LDA #$20
	STA $2006	; write the high byte of $2000 address to mapped register $2006
	LDA #$00
	STA $2006	; write the low byte of $2000 to mapped register $2006
	; prepare loop counters
	LDA #$10
	STA data2	; used for detecting end of y-indexed metatile row
	LDX #$00
	LDY #$00
	; prepare metatile pointer
	LDA #.LOBYTE(Metatiles)
	STA metatile_ptr
	LDA #.HIBYTE(Metatiles)
	STA metatile_ptr+1
MetatileLoop:
	; metatile structure - index points to first of 4 consecutive tiles
	; tiles are loaded at index, index+1, index+row_size, & index+row_size+1
	LDA (loptr), Y
	BNE :+
	; on 0, store 0 in all 4 locations
	STA load_bg_buf, X
	STA load_bg_buf+1, X
	STA load_bg_buf+32, X
	STA load_bg_buf+33, X
	JMP MetatileDone
:
	; fetch metatile address based on loaded index
	;  address = Metatiles+(4*index)
	STY data3	; save Y register
	ASL
	ASL	; shift left twice to multiply by 4
	TAY ; place offset index to Y register
	DEY
	DEY
	DEY
	DEY
	LDA (metatile_ptr), Y
	STA load_bg_buf, X
	INY
	LDA (metatile_ptr), Y
	STA load_bg_buf+1, X
	INY
	LDA (metatile_ptr), Y
	STA load_bg_buf+32, X
	INY
	LDA (metatile_ptr), Y
	STA load_bg_buf+33, X
	LDY data3	; restore Y register
MetatileDone:
	INY
	INX
	INX
	CPY data2
	BNE MetatileLoop
	; copy 32x2 metatile buffer into PPU background
	LDA data2
	CLC
	ADC #$10
	STA data2
	STY data
	LDY #$00
CopyMTBuffer:
	LDA load_bg_buf, Y
	STA $2007
	INY
	CPY #$40
	BNE CopyMTBuffer
	LDX #$00
	LDY data
	CPY #LVL_METATILES
	BNE MetatileLoop
	RTS

;----- Vblank interrupt handles rendering -----;
VBLANK:
	; zero out PPUSCROLL
	LDA #$00
	STA $2006
	STA $2006

	; save registers
	PHA	; push order - A, Y, X, P
	TYA
	PHA
	TXA
	PHA
	PHP
	
	; copy sprite data from memory into the PPU using
	; memory-mapped $4014 PPU register
	LDA #$02
	STA $4014

	; restore registers and return control
	LDA #$01
	STA draw_finished
	PLP	; pull order - P, X, Y, A
	PLA
	TAX
	PLA
	TAY
	PLA
	RTI

;-------------- Binary game data --------------;
PaletteData:
	.byte $22,$29,$1A,$0F,$22,$36,$17,$0f,$22,$30,$21,$0f,$22,$27,$17,$0F  ;background palette data
	.byte $22,$16,$27,$18,$22,$1A,$30,$27,$22,$16,$30,$27,$22,$0F,$36,$17  ;sprite palette data
Metatiles:
	.include "metatiles.asm"
BackgroundData:
	.incbin "background.bin"
AttributeData:
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00

; interrupt handlers
.segment "VECTORS"
	.word VBLANK
	.word Reset
	; specialized interrupt handler goes here

.segment "CHARS"
	.incbin "graphics.chr"
