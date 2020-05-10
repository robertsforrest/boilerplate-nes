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


;----- Zero page for efficient memory access -----;
.segment "ZEROPAGE"
loptr:	.res 1	; reserve a 16-bit pointer
hiptr:	.res 1

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
	LDA $2002	; reset PPU high/low latch with a read
	LDA #$20
	STA $2006	; write the high byte of $2000 address to mapped register $2006
	LDA #$00
	STA $2006	; write the low byte of $2000 to mapped register $2006
	; prepare the background pointer
	LDA #.LOBYTE(BackgroundData)
	STA loptr
	LDA #.HIBYTE(BackgroundData)
	STA hiptr
	; prepare loop counters
	LDX #$00
	LDY #$00
@loop:
	LDA (loptr), Y
	STA $2007	; map out to PPU memory
	INY
	CPY #$00	; check if y counter has overflowed
	BNE @loop
	; now see if the x counter (hi byte) has hit is limit
	INC hiptr
	INX
	CPX #$04
	BNE @loop

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

;-------- Main logic loop for the game --------;
GameLoop:
	JMP GameLoop

;----- Vblank interrupt handles rendering -----;
VBLANK:
	
	; copy sprite data from memory into the PPU using
	; memory-mapped $4014 PPU register
	LDA #$02
	STA $4014

	RTI	; interrupt return

;-------------- Binary game data --------------;
PaletteData:
	.byte $22,$29,$1A,$0F,$22,$36,$17,$0f,$22,$30,$21,$0f,$22,$27,$17,$0F  ;background palette data
	.byte $22,$16,$27,$18,$22,$1A,$30,$27,$22,$16,$30,$27,$22,$0F,$36,$17  ;sprite palette data

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
	.incbin "empty.chr"
