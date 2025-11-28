.global inbyte
.extern start
.global monitor_begin	

*****************
** 各種レジスタ定義
*****************


** レジスタ群の先頭 ***************
	.equ REGBASE, 0xFFF000	/* DMAP を使用． */
	.equ IOBASE, 0x00d00000


** 割り込み関係のレジスタ***************
	.equ IVR, REGBASE+0x300	/* 割り込みベクタレジスタ */
	.equ IMR, REGBASE+0x304	/* 割り込みマスクレジスタ */
	.equ ISR, REGBASE+0x30c	/* 割り込みステータスレジスタ */
	.equ IPR, REGBASE+0x310	/* 割り込みペンディングレジスタ */

** タイマ関係のレジスタ ***************
	.equ TCTL1, REGBASE+0x600	/* タイマ１コントロールレジスタ */
	.equ TPRER1, REGBASE+0x602	/* タイマ１プリスケーラレジスタ */
	.equ TCMP1, REGBASE+0x604	/* タイマ１コンペアレジスタ */
	.equ TCN1, REGBASE+0x608	/* タイマ１カウンタレジスタ */
	.equ TSTAT1, REGBASE+0x60a	/* タイマ１ステータスレジスタ */


/* キューのオフセットと必要領域計算 */
.section .bss

	.equ	B_SIZE,	256	
	.equ	TOP,	0
	.equ	BOTTOM,	B_SIZE
	.equ	IN,	BOTTOM + 4
	.equ	OUT,	IN + 4
	.equ	S,	OUT + 4
	.equ	SIZE,	S + 2

/* キュー用のメモリ領域確保 */
QUEUES:		.ds.b	SIZE * 4


** UART1（送受信）関係のレジスタ 
	.equ USTCNT1, REGBASE+0x900	/* UART1 ステータス/コントロールレジスタ*/
	.equ UBAUD1, REGBASE+0x902	/* UART1 ボーコントロールレジスタ */
	.equ URX1, REGBASE+0x904	/* UART1 受信レジスタ */
	.equ UTX1, REGBASE+0x906	/* UART1 送信レジスタ */

***************
** LED
**ボード搭載の LED 用レジスタ,使用法については付録 A.4.3.1
***************
	.equ LED7, IOBASE+0x000002f
	.equ LED6, IOBASE+0x000002d 
	.equ LED5, IOBASE+0x000002b
	.equ LED4, IOBASE+0x0000029
	.equ LED3, IOBASE+0x000003f
	.equ LED2, IOBASE+0x000003d
	.equ LED1, IOBASE+0x000003b
	.equ LED0, IOBASE+0x0000039

********************
** スタック領域の確保 
********************
	.section .bss
	.even
SYS_STK:
	.ds.b 0x4000	/* システムスタック領域 */
	.even 
	SYS_STK_TOP: /*| システムスタック領域の最後尾 */
********************
** PUT/GETSTRING用変数の確保 
********************

sz:		.ds.l 1
i:		.ds.l 1

* SET_TIMER のコールバックルーチンポインタ
task_p:
    .ds.l   1       /* 4バイトの領域を確保 */




***************************************************************
** 初期化 
** 内部デバイスレジスタには特定の値が設定されている． 
** その理由を知るには，付録 B にある各レジスタの仕様を参照すること． 
***************************************************************

	.section .text
	.even
monitor_begin: /* スーパーバイザ & 各種設定を行っている最中の割込禁止 */
	move.w #0x2700,%SR
	lea.l SYS_STK_TOP, %SP /* | Set SSP */
****************
** 割り込みコントローラの初期化
****************
	move.b #0x40, IVR	/* | ユーザ割り込みベクタ番号を| 0x40+level に設定． */
	move.l #0x00ffffff,IMR	/* | 全割り込みマスク */

****************
** 送受信 (UART1) 関係の初期化 (割り込みレベルは 4 に固定されている) 
****************
	move.w #0x0000, USTCNT1	/* | リセット */
	move.w #0xe100, USTCNT1	/* | 送受信可能, パリティなし, 1 stop, 8 bit, */
				/* | 送受割り込み禁止 */
	move.w #0x0038, UBAUD1	/* | baud rate = 230400 bps */


/* キューの初期化 */
QueueInitialize:
	movem.l	%d0-%d1/%a0-%a2,-(%sp)
	lea.l	QUEUES,%a0
	moveq	#4,%d0
	
InitLoop:
	movea.l	%a0,%a1
	lea.l	TOP(%a1),%a2
	move.l	%a2,IN(%a1)
	move.l	%a2,OUT(%a1)
	move.w	#0,S(%a1)
	adda.l	#SIZE,%a0
	subq.l	#1,%d0
	bne	InitLoop
	movem.l	(%sp)+,%d0-%d1/%a0-%a2
	


****************
** タイマ関係の初期化 (割り込みレベルは 6 に固定されている) 
*****************
	move.w #0x0004, TCTL1	/* restart, 割り込み不可 */
                        **システムクロックの 1/16 を単位として計時，
                        **タイマ使用停止

						
	* TRAP #0 ハンドラをベクタテーブルに登録
	move.l	#TRAP0_HANDLER, 0x0080
	* TRAP 0 (ベクタ番号 32) のアドレスにハンドラを設定 
	/* UART1 割り込み(レベル4, ベクタ68) ハンドラを設定 */
    /* ( IVR 0x40 + Level 4 = 0x44 (68), Address 68 * 4 = 0x110 ) */
    move.l  #send_or_receive, 0x110
    
    /* タイマ1 割り込み(レベル6, ベクタ70) ハンドラを設定 */
    /* ( IVR 0x40 + Level 6 = 0x46 (70), Address 70 * 4 = 0x118 ) */
    move.l  #timer1_interrupt, 0x118
    
    /* UARTとタイマの割り込みマスクをIMRで解除 */
    /* IMRのビット2,1を0にする */
    andi.l  #0xff3ff9, IMR
	
	bra INIT
******************
** 初期化（追加部分）
******************

.section .text
.even
INIT:
	* 走行レベル0で開始（スーパバイザモード）
	move.w	#0x2000, %SR

    * UART 割り込み許可（送受信割り込みON）
	move.w  #0xE10C, USTCNT1

	jmp start



***************
** システムコール番号
***************
.equ SYSCALL_NUM_GETSTRING, 1
.equ SYSCALL_NUM_PUTSTRING, 2
.equ SYSCALL_NUM_RESET_TIMER, 3
.equ SYSCALL_NUM_SET_TIMER, 4
****************************************************************
*** プログラム領域
****************************************************************
.section .text
.even
MAIN:
** 走行モードとレベルの設定 (「ユーザモード」への移行処理)
move.w #0x0000, %SR /* USER MODE, LEVEL 0 */
lea.l USR_STK_TOP,%SP /* user stack の設定 */
** システムコールによる RESET_TIMER の起動
move.l #SYSCALL_NUM_RESET_TIMER,%D0
trap #0
** システムコールによる SET_TIMER の起動
move.l #SYSCALL_NUM_SET_TIMER, %D0
move.w #50000, %D1
move.l #TT, %D2
trap #0
******************************
* sys_GETSTRING, sys_PUTSTRING のテスト
* ターミナルの入力をエコーバックする
******************************
LOOP:
move.l #SYSCALL_NUM_GETSTRING, %D0
move.l #0, %D1 /* ch = 0 */
move.l #BUF, %D2 /* p = #BUF */
move.l #256, %D3 /* size = 256 */
trap #0
move.l %D0, %D3 /* size = %D0 (length of given string) */
move.l #SYSCALL_NUM_PUTSTRING, %D0
move.l #0, %D1 /* ch = 0 */
move.l #BUF,%D2 /* p = #BUF */
trap #0
bra LOOP
******************************
* タイマのテスト
* ’******’ を表示し改行する．
* ５回実行すると，RESET_TIMER をする．
******************************
TT:
movem.l %D0-%D7/%A0-%A6,-(%SP)
cmpi.w #5,TTC /* TTC カウンタで 5 回実行したかどうか数える */
beq TTKILL /* 5 回実行したら，タイマを止める */
move.l #SYSCALL_NUM_PUTSTRING,%D0
move.l #0, %D1 /* ch = 0 */
move.l #TMSG, %D2 /* p = #TMSG */
move.l #8, %D3 /* size = 8 */
trap #0
addi.w #1,TTC /* TTC カウンタを 1 つ増やして */
bra TTEND /* そのまま戻る */
TTKILL:
move.l #SYSCALL_NUM_RESET_TIMER,%D0
trap #0
TTEND:
movem.l (%SP)+,%D0-%D7/%A0-%A6
rts
****************************************************************
*** 初期値のあるデータ領域
****************************************************************
.section .data
TMSG:
.ascii "******\r\n" /* \r: 行頭へ (キャリッジリターン) */
.even /* \n: 次の行へ (ラインフィード) */
TTC:
.dc.w 0
.even
****************************************************************
*** 初期値の無いデータ領域
****************************************************************
.section .bss
BUF:
.ds.b 256 /* BUF[256] */
.even
USR_STK:
.ds.b 0x4000 /* ユーザスタック領域 */
.even
USR_STK_TOP: /* ユーザスタック領域の最後尾 */



.section .text
.even
********************************
** 受信割り込みか送信割り込みかを判定
********************************
send_or_receive:
    movem.l	%d0-%d7/%a0-%a7,-(%sp) /* 安全のため全レジスタを退避 */

* --- 1. 受信処理を優先的にチェック ---
check_receive:
    move.w	URX1, %d3       /* URX1レジスタ(受信)を読み込み */
    move.b	%d3, %d2        /* %d2 にデータ部(bit 7-0)を先に保存 */
    andi.w	#0x2000, %d3    /* DATA READYフラグ(bit 13)をチェック */
    beq		check_send      /* フラグが0 (受信データなし) なら、送信チェックへ進む */

* --- 受信データがあった場合の処理 ---
receive_init:
    move.l	#0, %d1         /* ch=0 (UART1) */
    jsr		INTERGET        /* %d2のデータを使ってINTERGETを実行し、キューに入れる */
                            /* INTERGETは %d2 のデータを使用します */
    
* --- 2. 送信処理をチェック ---
check_send:
    move.w	UTX1, %d3       /* UTX1レジスタ(送信)を読み込み */
    andi.w 	#0x8000, %d3    /* FIFO EMPTYフラグ(bit 15)をチェック */ 
    beq		SoR_end         /* フラグが0 (送信不可) なら、ハンドラを終了 */

* --- 送信可能だった場合の処理 ---
send_init:
    move.l	#0, %d1         /* ch=0 (UART1) */
    jsr		INTERPUT        /* INTERPUTを実行し、キューからデータを取り出し送信 */

* --- 終了処理 ---
SoR_end:
    movem.l	(%sp)+, %d0-%d7/%a0-%a7 /* 退避したレジスタを復帰 */
    rte


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


**-----------------------------------------------------------------------
** INQ：番号noのキューにデータを入れる
** 入力：	キュー番号 no -> %d0.l
**			書き込む8bitデータ data -> %d1.b108
** 戻り値：	失敗0/成功1 -> %d0.l
**----------------------------------------------------------------------
INQ:
	move.w	%SR,-(%sp)					/* (1) 現走行レベルの退避 */
	move.w	#0x2700,%SR					/* (2) 割り込み禁止(= 走行レベルを 7 に) */
	movem.l	%d2-%d3/%a1-%a3,-(%sp)		/* レジスタの退避 */
	lea.l	QUEUES,%a1					/* 指定された番号のキューのアドレスを計算 */
	mulu.w	#SIZE,%d0
	adda.l	%d0,%a1
	jsr	PUT_BUF							/* (3) ～ (6) */
	movem.l	(%sp)+,%d2-%d3/%a1-%a3		/* レジスタの回復 */
	move.w	(%sp)+,%SR					/* (7) 旧走行レベルの回復 */
	rts

PUT_BUF:
	move.l	#0,%d2
	move.w	S(%a1),%d3
	cmp.w	#B_SIZE,%d3					/* (3)  s == 256 ならば %d0 を 0(失敗)に設定し，(7) へ */
	beq	PUT_BUF_Finish
	movea.l	IN(%a1),%a2
	move.b	%d1,(%a2)					/* (4) m[in] = data */
	adda.l	#1,%a2						/* in++ ( (5) の else ) */
	lea.l	BOTTOM(%a1),%a3
	cmpa.l	%a3,%a2						/* (5) if (in == bottom) in=top */
	bcs	PUT_BUF_STEP1
	lea.l	TOP(%a1),%a2

PUT_BUF_STEP1:
	move.l	%a2,IN(%a1)
	add.w	#1,%d3						/* (6) s++,                  */
	move.w	%d3,S(%a1)
	move.l	#1,%d2						/*     %D0 を 1（成功）に設定 */

PUT_BUF_Finish:
	move.l	%d2,%d0
	rts

**-----------------------------------------------------------------------
** OUTQ：番号noのキューからデータを一つ取り出す
** 入力：	キュー番号 no -> %d0.l
** 戻り値：	失敗0/成功1 -> %d0.l
** 			取り出した8bitデータ data -> %d1.b
**----------------------------------------------------------------------
OUTQ:
	move.w	%SR,-(%sp)					/* (1) 現走行レベルの退避 */
	move.w	#0x2700,%SR					/* (2) 割り込み禁止(= 走行レベルを 7 に) */
	movem.l	%d2-%d3/%a1-%a3,-(%sp)		/* レジスタの退避 */
	lea.l	QUEUES,%a1					/* 指定された番号のキューのアドレスを計算 */
	mulu.w	#SIZE,%d0
	adda.l	%d0,%a1
	jsr	GET_BUF							/* (3) ～ (6) */
	movem.l	(%sp)+,%d2-%d3/%a1-%a3		/* レジスタの回復 */
	move.w	(%sp)+,%SR					/* (7) 旧走行レベルの回復 */
	rts

GET_BUF:
	move.l	#0,%d2
	move.w	S(%a1),%d3
	cmp.w	#0x00,%d3					/* (3)  s == 0 ならば %d0 を 0(失敗)に設定し，(7) へ */
	beq	GET_BUF_Finish
	movea.l	OUT(%a1),%a2
	move.b	(%a2),%d1					/* (4) data = m[out] */
	adda.l	#1,%a2						/* out++ ( (5) の else ) */
	lea.l	BOTTOM(%a1),%a3
	cmpa.l	%a3,%a2						/* (5) if (out == bottom) iout=top */
	bcs	GET_BUF_STEP1
	lea.l	TOP(%a1),%a2

GET_BUF_STEP1:
	move.l	%a2,OUT(%a1)
	sub.w	#1,%d3						/* (6) s--                   */
	move.w	%d3,S(%a1)
	move.l	#1,%d2						/*     %d0 を 1（成功）に設定 */

GET_BUF_Finish:	
	move.l	%d2,%d0
	rts


*****************************************
**入力
  **チャネル ch→%d1
**戻り値
  **なし 
*****************************************


INTERPUT:
	movem.l	 %a0-%a2/%d0,-(%sp)	/*レジスタ退避*/
	
	/*(1) 割り込み禁止（走行レベルを7に）*/
	ori.w  #0x0700,%SR
	
	/*(2) chが0でないならば，何もせずに復帰*/
	cmp.l #0,%d1
	bne  END_of_INTERPUT
	
	/*(3) OUTQ(1,data) を実行する*/
	move.l  #1,%d0
	jsr  OUTQ
	
	/*(4) OUTQの戻り値が0(失敗)ならば，送信割り込みをマスク(USTCNT1 を操作)して復帰*/
	cmp.l #0,%d0			
	beq MASK
	
	/*(5) dataを送信レジスタUTX1に代入して送信*/
	move.l  %d1,%d0		
	andi.l  #0x000000ff, %d0	
	add.l   #0x0800,%d0		/*ヘッダの付与*/
	move.w  %d0,UTX1		/*UTX1についてはp85のB.3.3.4参照*/
	bra    END_of_INTERPUT
	

MASK:
	move.w #0xe108,USTCNT1	/*USTCNT1についてはp82のB.3.3.2 or p85のB.3.4.3参照*/
	

END_of_INTERPUT:	
	movem.l	(%sp)+, %a0-%a2/%d0 /*レジスタ復帰*/
	rts

*****************************************
**入力
  **チャネル ch→%d1
  **データ読み込み先の先頭アドレス p→%d2
  **送信するデータ数 size→%d3
**戻り値
  **実際に送信したデータ数 sz→ %d0 
*****************************************
	

PUTSTRING:
	movem.l	 %a0-%a3,-(%sp)	/*レジスタ退避*/
	
	/*(1) chが0でないならば，何もせずに復帰*/
	cmp.l    #0,%d1			
	bne      END_of_PUTSTRING	/*chが0でないならば何もせずに復帰*/
	
	/*(2) sz ← 0 , i ← p*/
	lea.l    sz,%a0
	lea.l    i,%a1
    move.l   #0,(%a0) /*szを初期化*/
	move.l   %d2,(%a1)		/*iに文字列ポインタを保存*/
	
	/*(3) size = 0 ならば(10)へ*/
	cmp.l    #0,%d3
 	beq      sz_SET			/*(10)へ*/
	
	/*(4) sz = size ならば (9) へ*/
loop_PUTSTRING:	
	cmp.l    (%a0),%d3
	beq      UNMASK			/*sizeが0ならばアンマスク(9)へ*/
	
	/*(5) INQ(1,i)を実行し，送信キューへi番地のデータを書き込む*/
	move.l   #1,%d0		
	movea.l  (%a1),%a3
	move.b   (%a3),%d1		/*dataにp[i]をセット*/
	jsr 	 INQ

	/*(6) INQの復帰値が0(失敗/queue full)なら(9)へ*/
	cmp      #0,%d0
	beq      UNMASK

	/*(7) sz++, i++*/
	addq.l   #1,(%a0)			/*sz++*/
	addq.l   #1,(%a1)			/*i++*/

	/*(8) (4) へ*/
	bra      loop_PUTSTRING

/*(9) USTCNT1 を操作して送信割り込み許可 (アンマスク)*/
UNMASK:
	move.w #0xe10c,USTCNT1

/*(10) %D0 ←− sz*/
sz_SET:
	move.l   (%a0),%d0		/*szをセット*/

END_of_PUTSTRING:	
	movem.l	(%sp)+, %a0-%a3
	rts
	
*----------------------------------------------------------------------
* GETSTRING と INTERGET 
*----------------------------------------------------------------------
GETSTRING:
	movem.l	%d1-%d4/%a0,-(%sp)		/* レジスタの退避 */
	cmp.l	#0,%d1					/* (1) ch ≠ 0 なら何も実行せず復帰 */
	bne	GETSTRING_END

GETSTRING1:
	move.l	#0,%d4					/* (2) sz <- 0 */
	move.l	%d2,%a0					/*     i <- p */

GETSTRING2:
	cmp.l	%d3,%d4					/* (3) sz = size なら (9) へ */
	beq	GETSTRING3
	move.l	#0,%d0					/* (4) OUTQ(0,data)により受信キューから8bitデータ読み込み */
	jsr	OUTQ
	cmp.l	#0,%d0					/* (5) OUTQの復帰値(%d0の値)が 0(失敗) なら (9) へ */
	beq	GETSTRING3
	move.b	%d1,(%a0)				/* (6) i番地にdataをコピー */
	addq.l	#1,%d4					/* (7) sz++ */
	adda.l	#1,%a0					/*     i++ */
	bra	GETSTRING2					/* (8) (3) へ */

GETSTRING3:
	move.l	%d4,%d0					/* (9) %d0 <- sz */
	bra	GETSTRING_Finish
	
GETSTRING_END:
	move.l	#0,%d0

GETSTRING_Finish:
	movem.l	(%sp)+,%d1-%d4/%a0		/* レジスタの回復 */
	rts

INTERGET:
	movem.l	%d0-%d1,-(%sp)			/* レジスタの退避 */
	cmp.l	#0,%d1					/* (1) ch ≠ 0 ならば何も実行せず復帰 */
	bne	INTERGET_Finish
	move.l	#0,%d0					/* (2) INQ(0,data) */
	move.l	%d2,%d1
	jsr	INQ

INTERGET_Finish:
	movem.l	(%sp)+,%d0-%d1			/* レジスタの回復 */
	rts


*----------------------------------------------------------------------
* ★★★ timer1_handler.s のコードをここから追加 ★★★
*----------------------------------------------------------------------
*----------------------------------------------------------------------
* RESET_TIMER ルーチン (タイマ停止 & 割り込み禁止)
*
* 役割: タイマーを安全に停止し、割り込みを禁止する。
*プログラムがタイマーを再設定する前や、タイマーの使用を完全に終えるときに、システムコール（TRAP #0経由のSYSCALL_RESET_TIMER）として呼び出される。
*----------------------------------------------------------------------
RESET_TIMER:
        move.l  #TCTL1, %A0        /* A0 に TCTL1 のアドレスをロード */
        *タイマー1の動作を制御するレジスタ（TCTL1）にアクセスする準備として、そのメモリアドレス（REGBASE+0x600）をアドレスレジスタ%A0にロード
        andi.w  #0xFFFE, (%A0)     /* タイマー停止 (TCTL1 Bit 0 'TEN' = 0) */
        *TCTL1レジスタのビット0（Timer Enable, TEN）のみを強制的に0にし、
        *0xFFFE は2進数で ...1111 1110であり、andi.w　命令は、(%A0)が指すTCTL1レジスタの現在の値と0xFFFEのビット単位のAND演算を行いビット0（TENフラグ）は & 0 されて 0 となり、他のビット（ビット1～15）は & 1 されてそのままの値が保持される。
     
        move.l  #IMR, %A0          /* A0 に IMR のアドレスをロード */
        *次にCPU全体の割り込みマスクレジスタ（IMR）を操作するため、そのアドレス（REGBASE+0x304）を%A0にロード
        * IMR Bit 1 (Timer1) を 1 (マスク/禁止) に設定する
        ori.l   #0x00000002, (%A0)
        *0x00000002 は2進数で ...0010であり、ori.l命令は、IMRの現在の値と0x00000002のビット単位のOR演算を行う。
        *このハードウェアでは、タイマー1の割り込みはIMRのビット1に対応している。このビットを1にすることで、タイマー1の割り込みがマスクされる。
     
        move.w  #0x0000, TSTAT1   /* 保留中の割り込みフラグをクリア */
        *タイマー1のステータスレジスタ（TSTAT1）をクリアし、万が一、タイマー停止処理（andi.w）と割り込みマスク（ori.l）の間にコンペアマッチが発生して割り込みフラグ（COMPフラグ）が立っていたとしても、それをリセット
        rts
        *呼び出し元（TRAP0_HANDLER）に処理を戻す
        *TSTAT1のビット0（COMPフラグ）は、0を書き込むことでクリアされる仕様になっている。これを怠ると、次にタイマーを有効化した瞬間に、古いフラグによって意図しない割り込みが発生する可能性があるため、安全策として必須の処理である。

*----------------------------------------------------------------------
* SET_TIMER ルーチン (タイマ設定 & 割り込み許可)
*
* 役割: 指定時間後に指定ルーチンを呼び出すよう設定する。
* 引数:
* %D1.W : タイムアウト時間 t (0.1msec単位)
* %D2.L : コールバックルーチン p のアドレス
*このルーチンは、指定された時間（0.1ms単位）が経過した後に、指定されたルーチン（%D2にアドレスを設定）を1回だけ呼び出すようにタイマー1を設定し、起動するものである。
*これもシステムコール経由で呼び出される。
*----------------------------------------------------------------------
SET_TIMER:
        move.l  #TCTL1, %A0        /* A0 に TCTL1 のアドレスをロード */
        andi.w  #0xFFFE, (%A0)     /* タイマーを一旦停止 (安全のため) */
        *RESET_TIMERと同様。タイマーの各種設定（プリスケーラ、コンペア値など）を変更中にタイマーが動作し、中途半端な設定で意図しない割り込みが発生することを防ぐため、設定変更前に必ずタイマーを停止する。
     
        lea.l   task_p, %A0        /* A0 に task_p 変数のアドレスをロード */
        *割り込み発生時に呼び出すべきルーチン（コールバックルーチン）のアドレスを一時的に保存するためのグローバル変数task_pの実効アドレスを%A0にロード
        move.l  %D2, (%A0)        /* task_p にコールバックのアドレス (%D2) を保存 */
        *システムコールの引数として%D2で渡されたコールバックルーチンのアドレスを、task_p変数が存在するメモリ領域（(%A0)が指す場所）に書き込む。
        *これにより、後の割り込みハンドラがtask_pの値を読み出すことで、「どのルーチンを呼び出すべきか」を知ることができるようになる。
     
        move.w  #206, TPRER1      /* プリスケーラを 0.1ms 周期に設定 */
        *TPRER1（プリスケーラレジスタ）に206を設定する。この値は、CPUのシステムクロック周波数から計算された特定の値であり、この設定によってタイマーカウンター（TCN1）が0.1msごとに1ずつ増加するようになる。
        move.w  %D1, TCMP1        /* 割り込み発生時間を設定 */
        *システムコールの引数%D1（タイムアウト時間）の値をTCMP1（コンペアレジスタ）に設定する。タイマーカウンター（TCN1）が0からカウントアップし、このTCMP1の値と一致（コンペアマッチ）した瞬間に、割り込み要求フラグ（TSTAT1のCOMPフラグ）が1になる。
        *例えば%D1に50000が設定されれば、50000 * 0.1ms = 5000ms = 5秒後に割り込みが発生する。
        move.w  #0x0000, TSTAT1   /* 古いフラグをクリア */
     
        move.l  #IMR, %A0          /* A0 に IMR のアドレスをロード */
        * IMR Bit 1 (Timer1) を 0 (許可/アンマスク) に設定する
        andi.l  #0xFFFFFFFD, (%A0)
        *タイマー1からの割り込み要求をCPUが受け付けるように許可
        *0xFFFFFFFDは2進数で ...1101であり、andi.l命令により、IMRのビット1（タイマー1のマスクビット）を強制的に0にする。他のビットは & 1 されて変更されない。
     
        * タイマー起動
        *全ての設定が完了したため、タイマーを起動
        * (TCTL1 = 0x0015 -> IRQEN=1, FRR=1, TEN=1)
        *-------------------------------------------
        *TCTL1に0x0015（2進数で 0001 0101）を書き込む。
        *ビット0 (TEN): 1 = Timer Enable。タイマーのカウントを開始
        *ビット2 (FRR): 1 = Free Run/Restart。コンペアマッチ発生後、カウンター（TCN1）を0にリセットし、再びカウントを開始する（フリーランモード）。
        *ビット4 (IRQEN): 1 = Interrupt Request Enable。コンペアマッチ発生時に、CPUに対して割り込みを要求する。
        *-------------------------------------------
        move.w  #0x0015, TCTL1
        *呼び出し元（TRAP0_HANDLER）に処理を戻す
        rts

*----------------------------------------------------------------------
* CALL_RP ルーチン (コールバック呼び出し)
*
* 役割: 割り込みハンドラから呼び出され、task_p のルーチンを実行する。
*コールバックルーチンを、実際に実行する役割
*----------------------------------------------------------------------
CALL_RP:
        lea.l   task_p, %A0        /* A0 に task_p 変数のアドレスをロード */
        move.l  (%A0), %A0         /* A0 に task_p の中身 (コールバックアドレス) をロード */
        *task_pのメモリ領域（(%A0)）から、実際に保存されている値（＝コールバックルーチンのアドレス）を%A0に読み込む。
        jsr     (%A0)              /* コールバックルーチンを実行 */
        *jsr（Jump to Subroutine）命令が%A0の指すアドレスにジャンプし、ルーチンの処理を実行する。ルーチンがrtsで終了すると、処理はCALL_RPのこのjsrの次の行に戻ってくる。
        rts
        *呼び出し元（timer1_interrupt）に処理を戻す

*----------------------------------------------------------------------
* タイマ1 割り込みハンドラ (ベクタ番号 70)
*
* 役割: タイマー割り込み発生時にCPUから直接呼び出される。
* (bootルーチンで 0x118 番地にこのアドレスを登録する必要あり)
*タイマー1のコンペアマッチによってハードウェアから直接呼び出される「割り込みハンドラ」（割り込み処理ルーチン）である。
*bootルーチンでベクタテーブルの0x118番地（ベクタ番号70）に、このルーチンのアドレスが登録されている。
*----------------------------------------------------------------------
timer1_interrupt:
        * 全てのレジスタをスタックにpush(退避)
        movem.l %D0-%D7/%A0-%A6, -(%SP)
        *割り込みハンドラの処理（CALL_RPの実行など）が、割り込み発生時に実行中だったメインプログラムの使用していたレジスタを破壊しないように、使用する可能性のある全レジスタの値をスタックに一時保存（退避）

        * 割り込み要因を確認 
        move.w  TSTAT1, %D0       /* TSTAT1 (16bit) を %D0 に読み込む */
        *割り込みが発生した正確な理由を確認するため、タイマー1のステータスレジスタ（TSTAT1）の値を読み出す。
        andi.w  #0x0001, %D0      /* Bit 0 (COMPフラグ) だけを取り出す */
        *TSTAT1の様々なフラグ（未使用のフラグも含む）の中から、今回の割り込みトリガーであるはずのビット0（COMPフラグ）だけを分離する。
        beq     .L_TIMER_EXIT     /* Bit 0 が 0 なら（タイマー要因でないなら）終了 */
        *もしCOMPフラグが0であった場合（andi.wの結果が0になる）、それは期待したコンペアマッチ割り込みではない（あるいは既に処理済み）と判断し、何もせずに終了処理（.L_TIMER_EXIT）へジャンプする。
        *これは、複数の割り込み要因が同じハンドラを共有している場合（今回は違うが）や、予期せぬ割り込み（スプリアス割り込み）に対する防御的なコーディング（堅牢化）である。

        * タイマー割り込みの処理
        move.w  #0x0000, TSTAT1   /* フラグをクリア */
        *割り込み要求の元となったCOMPフラグをクリアする。
        
        *TSTAT1に0を書き込むことで、ビット0のCOMPフラグがリセットされる。
        *これを怠ると、このハンドラがrteで終了した瞬間に、フラグが立ったままであるためCPUが「まだ割り込みが要求されている」と判断し、即座に再度timer1_interruptが呼び出され、メインプログラムが一切動作できなくなる（無限割り込みループ）。
        jsr     CALL_RP            /* コールバック呼び出し */
        *タイマー割り込み発生時に実行すべき本来のタスク（SET_TIMERで登録されたルーチン）を実行させるため、CALL_RPヘルパーサブルーチンを呼び出す。
        
.L_TIMER_EXIT:
        * 全てのレジスタをスタックから復帰
        *割り込み処理が完了したため、ハンドラ実行前にスタックに退避していたメインプログラムのレジスタ情報を完全に復元する。
        movem.l (%SP)+, %D0-%D7/%A0-%A6
        *割り込みハンドラから、割り込まれたメインプログラムの実行に復帰する。
        rte                     /* 割り込みから復帰 */
