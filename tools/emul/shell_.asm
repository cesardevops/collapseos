; named shell_.asm to avoid infinite include loop.
RAMSTART	.equ	0x4000
RAMEND		.equ	0x5000
STDIO_PORT	.equ	0x00
FS_DATA_PORT	.equ	0x01
FS_SEEKL_PORT	.equ	0x02
FS_SEEKH_PORT	.equ	0x03

jp	init

#include "core.asm"
.define STDIO_GETC	call emulGetC
.define STDIO_PUTC	call emulPutC
STDIO_RAMSTART	.equ	RAMEND
#include "stdio.asm"

BLOCKDEV_RAMSTART	.equ	STDIO_RAMEND
BLOCKDEV_COUNT		.equ	2
#include "blockdev.asm"
; List of devices
.dw	emulGetC, emulPutC, 0, 0
.dw	fsdevGetC, fsdevPutC, fsdevSeek, fsdevTell

#include "blockdev_cmds.asm"

.equ	FS_RAMSTART	BLOCKDEV_RAMEND
.equ	FS_HANDLE_COUNT	2
#include "fs.asm"

SHELL_RAMSTART	.equ	FS_RAMEND
.define SHELL_IO_GETC	call blkGetCW
.define SHELL_IO_PUTC	call blkPutC
SHELL_EXTRA_CMD_COUNT .equ 6
#include "shell.asm"
.dw	blkBselCmd, blkSeekCmd, fsOnCmd, flsCmd, fnewCmd, fdelCmd

init:
	di
	; setup stack
	ld	hl, RAMEND
	ld	sp, hl
	call	fsInit
	ld	a, 1	; select fsdev
	ld	de, BLOCKDEV_GETC
	call	blkSel
	call	fsOn
	xor	a	; select ACIA
	ld	de, BLOCKDEV_GETC
	call	blkSel
	call	shellInit
	jp	shellLoop

emulGetC:
	; Blocks until a char is returned
	in	a, (STDIO_PORT)
	cp	a		; ensure Z
	ret

emulPutC:
	out	(STDIO_PORT), a
	ret

fsdevGetC:
	in	a, (FS_DATA_PORT)
	ret

fsdevPutC:
	out	(FS_DATA_PORT), a
	ret

fsdevSeek:
	ld	a, l
	out	(FS_SEEKL_PORT), a
	ld	a, h
	out	(FS_SEEKH_PORT), a
	ret

fsdevTell:
	in	a, (FS_SEEKL_PORT)
	ld	l, a
	in	a, (FS_SEEKH_PORT)
	ld	h, a
	ret