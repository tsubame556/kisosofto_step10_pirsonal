.include "equdefs.inc"
.global outbyte

.text
.even

outbyte:
	movem.l %d1-%d3/%a1, -(%SP)	/* STORE REGISTERS */
outbyte_loop:
	/* OBTAIN ARGUMENTS TO DISPLAY */
	/* By the stack storing above, */
	/*     the values of 4 registers and PC re are stored */
	/*     which means that, the value of stack pointer is decreased */
	/* To execute GETSTRING, calculate the address where the actual data to display is stored */

	/* Add 3 bytes because the argument is stored begin sign-extended 4 bytes from 1 byte */
	/* 23 [bytes] = 5 [registers] * 4 [bytes/register] + 3 [byte] */

	movea.l	%sp,   %a1			/* copy head address of stack pointer */
	move.l	#23,   %d2			/* calculate the necessary address number to obtain the argument */
	adda.l	%d2,   %a1			/* by summing, go to the target to display */

	move.b	(%a1), obDATA		/* copy data to obDATA */
	move.b obDATA, LED6

	/* SYSCALL: PUTSTRING */
	move.l #SYSCALL_NUM_PUTSTRING, %D0
	move.l #0,  %D1         	| ch = 0
	move.l #obDATA, %D2       	| p  = #obDATA
	move.l #1, %D3          	| size = 1
	trap #0

	/* FLAG CHECK */
	cmp.l #0, %d0				/* see if PUTSTRING is successful */
	beq outbyte_loop			/* if false, retry */

	/* SUCCESS */
	movem.l (%SP)+, %d1-%d3/%a1 /* RESTORE REGISTERS */
	rts
        
.section .bss
.even

.global obDATA
obDATA:
	.ds.b 1
	.even
