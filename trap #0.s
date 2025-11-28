***************************************************************
** TRAP #0 システムコールハンドラ
***************************************************************
TRAP0_HANDLER:
	
	* システムコール番号（%D0）に応じて分岐する
	cmpi.l	#1, %d0					/* %D0 が 1 (GETSTRING) かを比較する。*/
	beq		SYSCALL_GETSTRING
	
	cmpi.l	#2, %d0					/* %D0 が 2 (PUTSTRING) かを比較する。*/
	beq		SYSCALL_PUTSTRING

	cmpi.l	#3, %d0					/* %D0 が 3 (RESET_TIMER) かを比較する。*/
	beq		SYSCALL_RESET_TIMER
	
	cmpi.l	#4, %d0					/* %D0 が 4 (SET_TIMER) かを比較する。*/
	beq		SYSCALL_SET_TIMER

	bra		TRAP0_EXIT				/* どの番号にも一致しない場合、終了へ進む。*/

SYSCALL_GETSTRING:
	* GETSTRING(ch=0, p=%D2, size=%D3)
	move.l	#GETSTRING, %d0
	jsr		GETSTRING				/* GETSTRING を呼び出す。*/
	bra		TRAP0_EXIT
	
SYSCALL_PUTSTRING:
	* PUTSTRING(ch=0, p=%D2, size=%D3)
	move.l	#PUTSTRING, %d0
	jsr		PUTSTRING				/* PUTSTRING を呼び出す。*/
	bra		TRAP0_EXIT

SYSCALL_RESET_TIMER:
	* RESET_TIMER()
	move.l	#RESET_TIMER, %d0
	jsr		RESET_TIMER				/* RESET_TIMER を呼び出す。*/
	bra		TRAP0_EXIT
	
SYSCALL_SET_TIMER:
	* SET_TIMER(t=%D1, p=%D2)
	move.l	#SET_TIMER, %d0
	jsr		SET_TIMER				/* SET_TIMER を呼び出す。*/
	bra		TRAP0_EXIT

TRAP0_EXIT:
	rte								/* 例外から復帰する。*/

