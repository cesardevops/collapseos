#include "user.inc"

; *** Consts ***
; Number of rows in the "single" argspec string
ARGSPEC_SINGLE_CNT	.equ	7
; Number of rows in the argspec table
ARGSPEC_TBL_CNT		.equ	12
; Number of rows in the primary instructions table
INSTR_TBLP_CNT		.equ	30
; size in bytes of each row in the primary instructions table
INSTR_TBLP_ROWSIZE	.equ	8

; *** Code ***
.org	USER_CODE
call	parseLine
ld	b, 0
ld	c, a	; written bytes
ret

unsetZ:
	push	bc
	ld	b, a
	inc	b
	cp	b
	pop	bc
	ret

; run RLA the number of times specified in B
rlaX:
	; first, see if B == 0 to see if we need to bail out
	dec	b
	ret	c	; C flag means we went negative. nothing to do
	inc	b
.loop:	rla
	djnz	.loop
	ret

; Sets Z is A is ';', CR, LF, or null.
isLineEnd:
	cp	';'
	ret	z
	cp	0
	ret	z
	cp	0x0d
	ret	z
	cp	0x0a
	ret

; Sets Z is A is ' ' or ','
isSep:
	cp	' '
	ret	z
	cp	','
	ret

; Sets Z is A is ' ', ',', ';', CR, LF, or null.
isSepOrLineEnd:
	call	isSep
	ret	z
	call	isLineEnd
	ret

; read word in (HL) and put it in (DE), null terminated. A is the read
; length. HL is advanced to the next separator char.
readWord:
	push	bc
	ld	b, 4
.loop:
	ld	a, (hl)
	call	isSepOrLineEnd
	jr	z, .success
	call	JUMP_UPCASE
	ld	(de), a
	inc	hl
	inc	de
	djnz	.loop
.success:
	xor	a
	ld	(de), a
	ld	a, 4
	sub	a, b
	jr	.end
.error:
	xor	a
	ld	(de), a
.end:
	pop	bc
	ret

; (HL) being a string, advance it to the next non-sep character.
; Set Z if we could do it before the line ended, reset Z if we couldn't.
toWord:
.loop:
	ld	a, (hl)
	call	isLineEnd
	jr	z, .error
	call	isSep
	jr	nz, .success
	inc	hl
	jr	.loop
.error:
	; we need the Z flag to be unset and it is set now. Let's CP with
	; something it can't be equal to, something not a line end.
	cp	'a'	; Z flag unset
	ret
.success:
	; We need the Z flag to be set and it is unset. Let's compare it with
	; itself to return a set Z
	cp	a
	ret


; Read arg from (HL) into argspec at (DE)
; HL is advanced to the next word. Z is set if there's a next word.
readArg:
	push	de
	ld	de, tmpVal
	call	readWord
	push	hl
	ld	hl, tmpVal
	call	parseArg
	pop	hl
	pop	de
	ld	(de), a
	call	toWord
	ret

; Read line from (HL) into (curWord), (curArg1) and (curArg2)
readLine:
	push	de
	xor	a
	ld	(curWord), a
	ld	(curArg1), a
	ld	(curArg2), a
	ld	de, curWord
	call	readWord
	call	toWord
	jr	nz, .end
	ld	de, curArg1
	call	readArg
	jr	nz, .end
	ld	de, curArg2
	call	readArg
.end:
	pop	de
	ret

; Returns length of string at (HL) in A.
strlen:
	push	bc
	push	hl
	ld	bc, 0
	ld	a, 0	; look for null char
.loop:
	cpi
	jp	z, .found
	jr	.loop
.found:
	; How many char do we have? the (NEG BC)-1, which started at 0 and
	; decreased at each CPI call. In this routine, we stay in the 8-bit
	; realm, so C only.
	ld	a, c
	neg
	dec	a
	pop	hl
	pop	bc
	ret

; find argspec for string at (HL). Returns matching argspec in A.
; Return value 0xff holds a special meaning: arg is not empty, but doesn't match
; any argspec (A == 0 means arg is empty). A return value of 0xff means an
; error.
parseArg:
	call	strlen
	cp	0
	ret	z		; empty string? A already has our result: 0

	push	bc
	push	de
	push	hl

	cp	1
	jr	z, .matchsingle	; Arg is one char? We have a "single" type.

	; Not a "single" arg. Do the real thing then.
	ld	de, argspecTbl
	; DE now points the the "argspec char" part of the entry, but what
	; we're comparing in the loop is the string next to it. Let's offset
	; DE by one so that the loop goes through strings.
	inc	de
	ld	b, ARGSPEC_TBL_CNT
.loop1:
	ld	a, 4
	call	JUMP_STRNCMP
	jr	z, .found		; got it!
	ld	a, 5
	call	JUMP_ADDDE
	djnz	.loop1
	; exhausted? we have a problem os specifying a wrong argspec. This is
	; an internal consistency error.
	ld	a, 0xff
	jr	.end
.found:
	; found the matching argspec row. Our result is one byte left of DE.
	dec	de
	ld	a, (de)
	jr	.end

.matchsingle:
	ld	a, (hl)
	ld	hl, argspecsSingle
	ld	bc, ARGSPEC_SINGLE_CNT
.loop2:
	cpi
	jr	z, .end		; found! our result is already in A. go straight
				; to end.
	jp	po, .loop2notfound
	jr	.loop2
.loop2notfound:
	; something's wrong. error
	ld	a, 0xff
	jr	.end

.end:
	pop	hl
	pop	de
	pop	bc
	ret

; Returns, with Z, whether A is a groupId
isGroupId:
	cp	0xc	; max group id + 1
	jr	nc, .notgroup	; >= 0xc? not a group
	cp	0
	jr	z, .notgroup	; 0? not supposed to happen. something's wrong.
	; A is a group. ensure Z is set
	cp	a
	ret
.notgroup:
	call	unsetZ
	ret

; Find argspec A in group id H.
; Set Z according to whether we found the argspec
; If found, the value in A is the argspec value in the group (it's index).
findInGroup:
	push	bc
	push	hl
	cp	0	; is our arg empty? If yes, we have nothing to do
	jr	z, .notfound

	push	de
	ld	de, argGrpTbl
	; group ids start at 1. decrease it, then multiply by two to have a
	; proper offset in argGrpTbl
	dec	h
	push	af
	ld	a, h
	add	a, a
	call	JUMP_ADDDE	; At this point, DE points to our group
	pop	af
	ex	hl, de
	pop	de

	ld	bc, 4
.loop:
	cpi
	jr	z, .found
	jp	po, .notfound
	jr	.loop
.found:
	; we found our result! Now, what we want to put in A is the index of
	; the found argspec. We have this in C (4 - C + 1). The +1 is because
	; cpi always decreases BC, whether we match or not.
	ld	a, 3	; 4 - 1
	sub	c
	cp	a	; ensure Z is set
	jr	.end
.notfound:
	call	unsetZ
.end:
	pop	hl
	pop	bc
	ret

; Compare argspec from instruction table in A with argument in (HL).
; For constant args, it's easy: if A == (HL), it's a success.
; If A is a group ID, we do something else: we check that (HL) exists in the
; groupspec (argGrpTbl)
matchArg:
	cp	a, (hl)
	ret	z
	; A bit of a delicate situation here: we want A to go in H but also
	; (HL) to go in A. If not careful, we overwrite each other. EXX is
	; necessary to avoid invoving other registers.
	push	hl
	exx
	ld	h, a
	push	hl
	exx
	ld	a, (hl)
	pop	hl
	call	findInGroup
	pop	hl
	ret

; Compare primary row at (DE) with string at curWord. Sets Z flag if there's a
; match, reset if not.
matchPrimaryRow:
	push	hl
	push	ix
	ld	hl, curWord
	ld	a, 4
	call	JUMP_STRNCMP
	jr	nz, .end
	; name matches, let's see the rest
	ld	ixh, d
	ld	ixl, e
	ld	hl, curArg1
	ld	a, (ix+4)
	call	matchArg
	jr	nz, .end
	ld	hl, curArg2
	ld	a, (ix+5)
	call	matchArg
.end:
	pop	ix
	pop	hl
	ret

; Parse line at (HL) and write resulting opcode(s) in (DE). Returns the number
; of bytes written in A.
parseLine:
	call	readLine
	push	de
	ld	de, instrTBlPrimary
	ld	b, INSTR_TBLP_CNT
.loop:
	ld	a, (de)
	call	matchPrimaryRow
	jr	z, .match
	ld	a, INSTR_TBLP_ROWSIZE
	call	JUMP_ADDDE
	djnz	.loop
	; no match
	xor	a
	pop	de
	ret
.match:
	; We have our matching instruction row. We're getting pretty near our
	; goal here!
	; First, let's go in IX mode. It's easier to deal with offsets here.
	push	ix
	ld	ixh, d
	ld	ixl, e
	; First, let's see if we're dealing with a group here
	ld	a, (ix+4)	; first argspec
	call	isGroupId
	jr	nz, .notgroup
	; A is a group, good, now let's get its value
	push	hl
	ld	h, a
	ld	a, (curArg1)
	call	findInGroup	; we don't check for match, it's supposed to
				; always match. Something is very wrong if it
				; doesn't
	; Now, we have our arg "group value" in A. Were going to need to
	; displace it left by the number of steps specified in the table.
	push	bc
	push	af
	ld	a, (ix+6)	; displacement bit
	ld	b, a
	pop	af
	call	rlaX
	pop	bc

	; At this point, we have a properly displaced value in A. We'll want
	; to OR it with the opcode.
	or	(ix+7)		; upcode
	pop	hl

	; Success!
	jr	.end
.notgroup:
	; not a group? easy as pie: we return the opcode directly.
	ld	a, (ix+7)	; upcode is on 8th byte
.end:
	; At the end, we have our final opcode in A!
	pop	ix
	pop	de
	ld	(de), a
	ld	a, 1
	ret

; In instruction metadata below, argument types arge indicated with a single
; char mnemonic that is called "argspec". This is the table of correspondance.
; Single letters are represented by themselves, so we don't need as much
; metadata.
; Special meaning:
; 0 : no arg
; 1-10 : group id (see Groups section)
; 0xff: error

argspecsSingle:
	.db	"ABCDEHL"

; Format: 1 byte argspec + 4 chars string
argspecTbl:
	.db	'h', "HL", 0, 0
	.db	'l', "(HL)"
	.db	'd', "DE", 0, 0
	.db	'e', "(DE)"
	.db	'b', "BC", 0, 0
	.db	'c', "(BC)"
	.db	'a', "AF", 0, 0
	.db	'f', "AF'", 0
	.db	'x', "(IX)"
	.db	'y', "(IY)"
	.db	's', "SP", 0, 0
	.db	'p', "(SP)"
; we also need argspecs for the condition flags
	.db	'Z', "Z", 0, 0, 0
	.db	'z', "NZ",   0, 0
	.db	'^', "C", 0, 0, 0
	.db	'=', "NC",   0, 0
	.db	'+', "P", 0, 0, 0
	.db	'-', "M", 0, 0, 0
	.db	'1', "PO",   0, 0
	.db	'2', "PE",   0, 0

; argspecs not in the list:
; N -> NN
; n -> (NN)

; Groups
; Groups are specified by strings of argspecs. To facilitate jumping to them,
; we have a fixed-sized table. Because most of them are 2 or 4 bytes long, we
; have a table that is 4 in size to minimize consumed space. We treat the two
; groups that take 8 bytes in a special way.
;
; The table below is in order, starting with group 0x01
argGrpTbl:
	.db	"bdha"		; 0x01
	.db	"Zz^="		; 0x02

argGrpCC:
	.db	"Zz^=+-12"	; 0xa
argGrpABCDEHL:
	.db	"BCDEHL_A"	; 0xb

; This is a list of primary instructions (single upcode) that lead to a
; constant (no group code to insert). Format:
;
; 4 bytes for the name (fill with zero)
; 1 byte for arg constant
; 1 byte for 2nd arg constant
; 1 byte displacement for group arguments
; 1 byte for upcode
instrTBlPrimary:
	.db "ADD", 0, 'A', 'h', 0, 0x86		; ADD A, HL
	.db "AND", 0, 'l', 0,   0, 0xa6		; AND (HL)
	.db "AND", 0, 0xa, 0,   0, 0b10100000	; AND r
	.db "CCF", 0, 0,   0,   0, 0x3f		; CCF
	.db "CPL", 0, 0,   0,   0, 0x2f		; CPL
	.db "DAA", 0, 0,   0,   0, 0x27		; DAA
	.db "DI",0,0, 0,   0,   0, 0xf3		; DI
	.db "EI",0,0, 0,   0,   0, 0xfb		; EI
	.db "EX",0,0, 'p', 'h', 0, 0xe3		; EX (SP), HL
	.db "EX",0,0, 'a', 'f', 0, 0x08		; EX AF, AF'
	.db "EX",0,0, 'd', 'h', 0, 0xeb		; EX DE, HL
	.db "EXX", 0, 0,   0,   0, 0xd9		; EXX
	.db "HALT",   0,   0,   0, 0x76		; HALT
	.db "INC", 0, 'l', 0,   0, 0x34		; INC (HL)
	.db "JP",0,0, 'l', 0,   0, 0xe9		; JP (HL)
	.db "LD",0,0, 'c', 'A', 0, 0x02		; LD (BC), A
	.db "LD",0,0, 'e', 'A', 0, 0x12		; LD (DE), A
	.db "LD",0,0, 'A', 'c', 0, 0x0a		; LD A, (BC)
	.db "LD",0,0, 'A', 'e', 0, 0x0a		; LD A, (DE)
	.db "LD",0,0, 's', 'h', 0, 0x0a		; LD SP, HL
	.db "NOP", 0, 0,   0,   0, 0x00		; NOP
	.db "OR",0,0, 'l', 0,   0, 0xb6		; OR (HL)
	.db "POP", 0, 0x1, 0,   4, 0b11000001	; POP qq
	.db "RET", 0, 0,   0,   0, 0xc9		; RET
	.db "RET", 0, 0xb, 0,   3, 0b11000000	; RET cc
	.db "RLA", 0, 0,   0,   0, 0x17		; RLA
	.db "RLCA",   0,   0,   0, 0x07		; RLCA
	.db "RRA", 0, 0,   0,   0, 0x1f		; RRA
	.db "RRCA",   0,   0,   0, 0x0f		; RRCA
	.db "SCF", 0, 0,   0,   0, 0x37		; SCF


; *** Variables ***
; enough space for 4 chars and a null
curWord:
	.db	0, 0, 0, 0, 0

; Args are 3 bytes: argspec, then values of numerical constants (when that's
; appropriate)
curArg1:
	.db	0, 0, 0
curArg2:
	.db	0, 0, 0

; space for tmp stuff
tmpVal:
	.db	0, 0, 0, 0, 0
