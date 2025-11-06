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


* キューのオフセットと必要領域計算
.section .bss

	.equ	B_SIZE,	256	
	.equ	TOP,	0
	.equ	BOTTOM,	B_SIZE
	.equ	IN,	BOTTOM + 4
	.equ	OUT,	IN + 4
	.equ	S,	OUT + 4
	.equ	SIZE,	S + 2

* キュー用のメモリ領域確保
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
	SYS_STK_TOP: /* システムスタック領域の最後尾 */
********************
** PUT/GETSTRING用変数の確保
********************

* sz:		.ds.l 1 /* 修正点: 再入可能化のためグローバル変数szを削除 */
* i:		.ds.l 1 /* 修正点: 再入可能化のためグローバル変数iを削除 */

* SET_TIMER のコールバックルーチンポインタ
task_p:
	.ds.l 1		/* 4バイトの領域を確保 */




***************************************************************
** 初期化
** 内部デバイスレジスタには特定の値が設定されている．
** その理由を知るには，付録 B にある各レジスタの仕様を参照すること．
***************************************************************

	.section .text
	.even
boot: /* スーパーバイザ & 各種設定を行っている最中の割込禁止 */
	move.w #0x2700,%SR
	lea.l SYS_STK_TOP, %SP /* Set SSP */
****************
** 割り込みコントローラの初期化
****************
	move.b #0x40, IVR	/* ユーザ割り込みベクタ番号を 0x40+level に設定． */
	move.l #0x00ffffff,IMR	/* 全割り込みマスク */

****************
** 送受信 (UART1) 関係の初期化 (割り込みレベルは 4 に固定されている)
****************
	move.w #0x0000, USTCNT1	/* リセット */
	move.w #0xe100, USTCNT1	/* 送受信可能, パリティなし, 1 stop, 8 bit, */
				/* 送受割り込み禁止 */
	move.w #0x0038, UBAUD1	/* baud rate = 230400 bps */


* キューの初期化
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
				/* システムクロックの 1/16 を単位として計時，*/
				/* タイマ使用停止 */

						
	* TRAP #0 ハンドラをベクタテーブルに登録
	move.l	#TRAP0_HANDLER, 0x0080
	* TRAP 0 (ベクタ番号 32) のアドレスにハンドラを設定
	/* UART1 割り込み(レベル4, ベクタ68) ハンドラを設定 */
	/* ( IVR 0x40 + Level 4 = 0x44 (68), Address 68 * 4 = 0x110 ) */
	move.l #send_or_receive, 0x110
	
	/* タイマ1 割り込み(レベル6, ベクタ70) ハンドラを設定 */
	/* ( IVR 0x40 + Level 6 = 0x46 (70), Address 70 * 4 = 0x118 ) */
	move.l #timer1_interrupt, 0x118
	
	/* UART(レベル4)の割り込みマスクをIMRで解除 */
	/* IMRのビット2,1を0にする */
	andi.l #0xfffffff9, IMR
	
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
	move.w #0xE10C, USTCNT1



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
move.w #10000, %D1		/* 10000 (1秒) に変更 */
move.l #TT_KADAI1, %D2	/* TT_KADAI1 に変更 */
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
* タイマのテスト (オリジナル)
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

******************************
* 課題1用 タイマコールバック (バグ修正版)
* 1秒ごとに呼ばれ、メッセージを切り替えて表示する
******************************
TT_KADAI1:
    movem.l %D0-%D7/%A0-%A6,-(%SP) /* (1) 全てのレジスタを退避 */
    
    * TTC カウンタをインクリメント
    addi.w #1,TTC 
    
    * TTC の値に基づいて表示するメッセージを決定
    move.w  TTC, %D4
    move.l  %D4, %D5
    
    divu.w  #3, %D5
    swap    %D5
    andi.l  #0x0000FFFF, %D5
    
    cmpi.l  #0, %D5
    beq     SHOW_MSG1
    cmpi.l  #1, %D5
    beq     SHOW_MSG2
    bra     SHOW_MSG3       

SHOW_MSG1:
    move.l  #0, %D1         /* ch = 0 */
    move.l  #MSG1, %D2      /* p = #MSG1 */
    move.l  #23, %D3        /* 修正点: size = 23 (ユーザ指定) */
    jsr     PUTSTRING       /* 修正点: jsr で直接呼び出す */
    bra     TT_KADAI1_END
    
SHOW_MSG2:
    move.l  #0, %D1         /* ch = 0 */
    move.l  #MSG2, %D2      /* p = #MSG2 */
    move.l  #23, %D3        /* size = 23 */
    jsr     PUTSTRING       /* 修正点: jsr で直接呼び出す */
    bra     TT_KADAI1_END
    
SHOW_MSG3:
    move.l  #0, %D1         /* ch = 0 */
    move.l  #MSG3, %D2      /* p = #MSG3 */
    move.l  #23, %D3        /* size = 23 */
    jsr     PUTSTRING       /* 修正点: jsr で直接呼び出す */
    bra     TT_KADAI1_END
    
TT_KADAI1_END:
    movem.l (%SP)+,%D0-%D7/%A0-%A6 /* (1) で退避したレジスタを復帰 */
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

* --- 課題1用 追加データ (ユーザ指定・アラインメント修正版) ---
MSG1:   .ascii "Message 1: Hello !   \r\n"
.even   /* 奇数長(23B)のため .even を追加 */
LEN1:   .dc.l 23
MSG2:   .ascii "Message 2: This is OS.\r\n"
.even   /* 奇数長(23B)のため .even を追加 */
LEN2:   .dc.l 23
MSG3:   .ascii "Message 3: M68k Timer.\r\n"
.even   /* 奇数長(23B)のため .even を追加 */
LEN3:   .dc.l 23
.even
* --- 課題1用 追加データ 終了 ---

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
	move.w	URX1, %d3	/* URX1レジスタ(受信)を読み込み */
	move.b	%d3, %d2	/* %d2 にデータ部(bit 7-0)を先に保存 */
	andi.w	#0x2000, %d3	/* DATA READYフラグ(bit 13)をチェック */
	beq		check_send	/* フラグが0 (受信データなし) なら、送信チェックへ進む */

* --- 受信データがあった場合の処理 ---
receive_init:
	move.l	#0, %d1		/* ch=0 (UART1) */
	jsr		INTERGET	/* %d2のデータを使ってINTERGETを実行し、キューに入れる */
					/* INTERGETは %d2 のデータを使用します */
	
* --- 2. 送信処理をチェック ---
check_send:
	move.w	UTX1, %d3	/* UTX1レジスタ(送信)を読み込み */
	andi.w 	#0x8000, %d3	/* FIFO EMPTYフラグ(bit 15)をチェック */
	beq		SoR_end		/* フラグが0 (送信不可) なら、ハンドラを終了 */

* --- 送信可能だった場合の処理 ---
send_init:
	move.l	#0, %d1		/* ch=0 (UART1) */
	jsr		INTERPUT	/* INTERPUTを実行し、キューからデータを取り出し送信 */

* --- 終了処理 ---
SoR_end:
	movem.l	(%sp)+, %d0-%d7/%a0-%a7 /* 退避したレジスタを復帰 */
	rte


***************************************************************
** TRAP #0 システムコールハンドラ
** (Step 8: OSサービスの呼び出しに対応)
***************************************************************
TRAP0_HANDLER:
	
	* サービス番号（%D0）に応じて分岐する
	cmpi.l	#1, %d0					/* %D0 が 1 (GETSTRING) かを比較する。*/
	beq		SYSCALL_GETSTRING
	
	cmpi.l	#2, %d0					/* %D0 が 2 (PUTSTRING) かを比較する。*/
	beq		SYSCALL_PUTSTRING

	cmpi.l	#3, %d0					/* %D0 が 3 (RESET_TIMER) かを比較する。*/
	beq		SYSCALL_RESET_TIMER
	
	cmpi.l	#4, %d0					/* %D0 が 4 (SET_TIMER) かを比較する。*/
	beq		SYSCALL_SET_TIMER

	bra		TRAP0_EXIT				/* どのサービス番号にも一致しない場合、終了へ進む。*/

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
	cmp.w	#B_SIZE,%d3					/* (3) s == 256 ならば %d0 を 0(失敗)に設定し，(7) へ */
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
	add.w	#1,%d3						/* (6) s++, */
	move.w	%d3,S(%a1)
	move.l	#1,%d2						/* %D0 を 1（成功）に設定 */

PUT_BUF_Finish:
	move.l	%d2,%d0
	rts

**-----------------------------------------------------------------------
** OUTQ：番号noのキューからデータを一つ取り出す
** 入力：	キュー番号 no -> %d0.l
** 戻り値：	失敗0/成功1 -> %d0.l
** 取り出した8bitデータ data -> %d1.b
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
	cmp.w	#0x00,%d3					/* (3) s == 0 ならば %d0 を 0(失敗)に設定し，(7) へ */
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
	sub.w	#1,%d3						/* (6) s-- */
	move.w	%d3,S(%a1)
	move.l	#1,%d2						/* %D0 を 1（成功）に設定 */

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
	ori.w #0x0700,%SR
	
	/*(2) chが0でないならば，何もせずに復帰*/
	cmp.l #0,%d1
	bne END_OF_INTERPUT
	
	/*(3) OUTQ(1,data) を実行する*/
	move.l #1,%d0
	jsr OUTQ
	
	/*(4) OUTQの戻り値が0(失敗)ならば，送信割り込みをマスク(USTCNT1 を操作)して復帰*/
	cmp.l #0,%d0			
	beq MASK
	
	/*(5) dataを送信レジスタUTX1に代入して送信*/
	move.l %d1,%d0		
	andi.l #0x000000ff, %d0	
	add.l #0x0800,%d0		/*ヘッダの付与*/
	move.w %d0,UTX1	
	bra END_OF_INTERPUT
	

MASK:
	move.w #0xe108,USTCNT1
	/*move.l #0x00fffffb, IMR*/
	/*move.w #0x2000, %SR*/
	
	

END_OF_INTERPUT:	
	movem.l	(%sp)+, %a0-%a2/%d0 /*レジスタ退復帰*/
	rts

*****************************************
* PUTSTRING (再入可能バージョン)
* 入力:
* %d1.l : チャネル ch
* %d2.l : データ読み込み先の先頭アドレス p
* %d3.l : 送信するデータ数 size
* 戻り値:
* %d0.l : 実際に送信したデータ数 sz
*****************************************
PUTSTRING:
    movem.l %d1-%d7/%a0-%a6,-(%sp)  /* (A) 呼び出し元で使用中のレジスタを全て退避 */
    
    move.l %d1, %d6     /* 引数を安全なレジスタに保存: d6 = ch */
    move.l %d2, %a0     /* a0 = p (文字ポインタ) */
    move.l %d3, %d7     /* d7 = size (送信すべき合計サイズ) */
    
    move.l #0, %d5      /* d5 = sz (キューに入れた文字数カウンタ) */
    
    /* (1) chが0でないならば，何もせずに復帰 */
    cmp.l #0, %d6
    bne .L_PUTSTRING_END
    
    /* (3) size = 0 ならば(10)へ (アンマスクのみ行う) */
    cmp.l #0, %d7
    beq .L_PUTSTRING_UNMASK
    
.L_PUTSTRING_LOOP:
    /* (4) sz = size (送信すべき文字数 = キューに入れた文字数) なら (9) へ */
    cmp.l %d5, %d7
    beq .L_PUTSTRING_UNMASK
    
    /* (5) INQ(1, *p) を実行 */
    move.l #1, %d0      /* no = 1 (送信キュー) */
    move.b (%a0), %d1   /* data = *p (ポインタが指す文字) */
    
    jsr INQ             /* INQ(1, data) を呼び出す */
    /* INQ は %d0 に 0(失敗) or 1(成功) を返す */

    /* (6) INQの復帰値が0(失敗/queue full)なら(9)へ */
    cmp.l #0, %d0
    beq .L_PUTSTRING_UNMASK

    /* (7) sz++, p++ */
    addq.l #1, %d5      /* sz++ */
    addq.l #1, %a0      /* p++ */

    /* (8) (4) へ */
    bra .L_PUTSTRING_LOOP

.L_PUTSTRING_UNMASK:
    /* (9) USTCNT1 を操作して送信割り込み許可 (アンマスク) */
    move.w #0xe10c,USTCNT1

.L_PUTSTRING_END:
    /* (10) %D0 <- sz (戻り値セット) */
    move.l %d5, %d0
    
    movem.l (%sp)+, %d1-%d7/%a0-%a6 /* (A) 退避したレジスタを全て復帰 */
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
	move.l	%d2,%a0					/* i <- p */

GETSTRING2:
	cmp.l	%d3,%d4					/* (3) sz = size なら (9) へ */
	beq	GETSTRING3
	move.l	#0,%d0					/* (4) OUTQ(0,data)により受信キューから8bitデータ読み込み */
	jsr	OUTQ
	cmp.l	#0,%d0					/* (5) OUTQの復帰値(%d0の値)が 0(失敗) なら (9) へ */
	beq	GETSTRING3
	move.b	%d1,(%a0)				/* (6) i番地にdataをコピー */
	addq.l	#1,%d4					/* (7) sz++ */
	adda.l	#1,%a0					/* i++ */
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
* RESET_TIMER ルーチン (タイマ停止 & 割り込み禁止)
*
* 役割: タイマーを安全に停止し、割り込みを禁止する。
*----------------------------------------------------------------------
RESET_TIMER:
	move.l #TCTL1, %A0	/* A0 に TCTL1 のアドレスをロード */
	andi.w #0xFFFE, (%A0)	/* タイマー停止 (TCTL1 Bit 0 'TEN' = 0) */
	
	move.l #IMR, %A0	/* A0 に IMR のアドレスをロード */
	* IMR Bit 1 (Timer1) を 1 (マスク/禁止) に設定する
	ori.l #0x00000002, (%A0)
	
	move.w #0x0000, TSTAT1	/* 保留中の割り込みフラグをクリア */
	rts

*----------------------------------------------------------------------
* SET_TIMER ルーチン (タイマ設定 & 割り込み許可)
*
* 役割: 指定時間後に指定ルーチンを呼び出すよう設定する。
* 引数:
* %D1.W : タイムアウト時間 t (0.1msec単位)
* %D2.L : コールバックルーチン p のアドレス
*----------------------------------------------------------------------
SET_TIMER:
	move.l #TCTL1, %A0	/* A0 に TCTL1 のアドレスをロード */
	andi.w #0xFFFE, (%A0)	/* タイマーを一旦停止 (安全のため) */
	
	lea.l task_p, %A0	/* A0 に task_p 変数のアドレスをロード */
	move.l %D2, (%A0)	/* task_p にコールバックのアドレス (%D2) を保存 */
	
	move.w #206, TPRER1	/* プリスケーラを 0.1ms 周期に設定 */
	move.w %D1, TCMP1	/* 割り込み発生時間を設定 */
	move.w #0x0000, TSTAT1	/* 古いフラグをクリア */
	
	move.l #IMR, %A0	/* A0 に IMR のアドレスをロード */
	* IMR Bit 1 (Timer1) を 0 (許可/アンマスク) に設定する
	andi.l #0xFFFFFFFD, (%A0)
	
	* タイマー起動
	* (TCTL1 = 0x0015 -> IRQEN=1, FRR=1, TEN=1)
	move.w #0x0015, TCTL1
	rts

*----------------------------------------------------------------------
* CALL_RP ルーチン (コールバック呼び出し)
*
* 役割: 割り込みハンドラから呼び出され、task_p のルーチンを実行する。
*----------------------------------------------------------------------
CALL_RP:
	lea.l task_p, %A0	/* A0 に task_p 変数のアドレスをロード */
	move.l (%A0), %A0	/* A0 に task_p の中身 (コールバックアドレス) をロード */
	jsr (%A0)		/* コールバックルーチンを実行 */
	rts

*----------------------------------------------------------------------
* タイマ1 割り込みハンドラ (ベクタ番号 70)
*
* 役割: タイマー割り込み発生時にCPUから直接呼び出される。
* (bootルーチンで 0x118 番地にこのアドレスを登録する必要あり)
*----------------------------------------------------------------------
timer1_interrupt:
	* 全てのレジスタをスタックに退避
	movem.l %D0-%D7/%A0-%A6, -(%SP)

	* 割り込み要因を確認 (mon.s 方式)
	move.w TSTAT1, %D0	/* TSTAT1 (16bit) を %D0 に読み込む */
	andi.w #0x0001, %D0	/* Bit 0 (COMPフラグ) だけを取り出す */
	beq .L_TIMER_EXIT	/* Bit 0 が 0 なら（タイマー要因でないなら）終了 */

	* タイマー割り込みの処理
	move.w #0x0000, TSTAT1	/* フラグをクリア */
	jsr CALL_RP		/* コールバック呼び出し */

.L_TIMER_EXIT:
	* 全てのレジスタをスタックから復帰
	movem.l (%SP)+, %D0-%D7/%A0-%A6
	rte			/* 割り込みから復帰 */





*----------------------------------------------------------------------
* キュー定義
*----------------------------------------------------------------------
.section .data

TDATA1: .ascii "0123456789ABCDEF"
TDATA2: .ascii "klmnopqrstuvwxyz"
.end
