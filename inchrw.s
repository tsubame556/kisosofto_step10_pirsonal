.include "equdefs.inc"
.global inbyte

.text
.even

inbyte:
	movem.l %a0/%d1-%d3, -(%SP)		/* STORE REGISTERS */
	lea.l ibDATA, %a0				/* SET ADDRESS OF ibDATA TO a0 */
inbyte_loop:
	/* SYSCALL: GETSTRING */
	move.l #SYSCALL_NUM_GETSTRING, %D0
	move.l #0,  %d1         		| ch   = 0
	move.l %a0, %d2         		| p    = #ibDATA
	move.l #1, %d3          		| size = 1
	trap #0

	/* FLAG CHECK */
	cmp.l #0, %d0					/* see if GETSTRING is successful */
	beq inbyte_loop					/* if false, retry */

	/* SUCCESS */
	move.b (%a0), %d0				/* copy retuned data to d0 */
	move.b %d0, LED7
	movem.l (%SP)+, %a0/%d1-%d3		/* STORE REGISTERS */
	rts
        
.section .bss
.even

.global DATA
ibDATA:
	.ds.b 1
	.even
