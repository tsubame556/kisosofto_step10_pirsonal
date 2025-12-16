* mtk_asm.s - マルチタスクカーネル アセンブリ言語ルーチン
*
* 役割: タイマー割り込みを初期化し、hard_clock をタスクスイッチのコールバックとして登録する。
* ----------------------------------------------------------------------
* 外部参照（C言語カーネル部や他のアセンブリルーチン）
* ----------------------------------------------------------------------
	.extern curr_task		/* 現在実行中のタスクIDを保持するC変数 */
	.extern next_task		/* 次に実行するタスクIDを保持するC変数 */
	.extern ready			/* Readyキューの先頭ポインタを保持するC変数 */
	.extern addq			/* タスクをキューに追加するC関数 (addq(queue, task_id)) */
	.extern sched			/* 次タスクを選定するスケジューラC関数 */
	/*.extern swtch			/* タスクのコンテキストスイッチ本体アセンブリ関数 */
	.extern	task_tab

* ----------------------------------------------------------------------
* グローバル宣言
* ----------------------------------------------------------------------
	.global init_timer		/* C言語から呼び出される初期化関数 */
	.global hard_clock		/* hard_clockも外部から参照される（割り込みベクタ登録用） */
	.global pv_handler      /*init_karnelから呼び出される関数*/
	.global P				/* C言語から呼び出される */
	.global V				/* C言語から呼び出される */
	.global swtch

* ----------------------------------------------------------------------
* 定義（equdefs.incからの流用を想定）
* ----------------------------------------------------------------------
	.equ SYSCALL_NUM_SET_TIMER, 4	/* SET_TIMER システムコール番号 */
	.equ TIMER_PERIOD_0_1MS, 10000	/* 1秒 = 10,000 * 0.1ms */
	.equ TSTAT1, 0xFFF60a	/* タイマ１ステータスレジスタ (mon.sより) */

.text
.even

*----------------------------------------------------------------------
* init_timer: タイマー割り込み開始ルーチン
* 役割: mon.s のシステムコールを利用し、hard_clockをタイマー割り込みに登録・起動する。
* 戻り値なし。
*----------------------------------------------------------------------
init_timer:
    move.b #'L', LED0
	* (1) レジスタの退避
	* システムコールで使用するD0, D1, D2を退避する。
	movem.l	%D0/%D1/%D2, -(%SP)	

	* (2) SET_TIMER システムコール引数の設定
	move.l	#SYSCALL_NUM_SET_TIMER, %D0	/* D0 = システムコール番号 4 (SET_TIMER) */
	
	move.w	#TIMER_PERIOD_0_1MS, %D1	/* D1 = タイムアウト時間 (1秒 = 10000) */
	
	move.l	#hard_clock, %D2			/* D2 = コールバックルーチンアドレス (hard_clock) */

	* (3) システムコール呼び出し
	trap	#0							/* システムコールを実行し、タイマーを起動 */

	* (4) レジスタの復帰
	movem.l	(%SP)+, %D0/%D1/%D2		/* 退避したレジスタを復帰 */

    move.b #'l', LED0
	rts								/* C言語の呼び出し元に復帰 */

	


*----------------------------------------------------------------------
* hard_clock: タイマー割り込みハンドラ
* 役割: タイマ割り込み時にタスクをReadyキューに戻し、次のタスクへ切り替える。
* (割り込み駆動であるが、前期インターフェースから呼ばれるため、RTSで復帰する)
*----------------------------------------------------------------------
hard_clock:
    move.b #'M', LED0
	* 1. 実行中のタスクのレジスタの退避
	* 割り込み時に使用されていたレジスタをスーパーバイザスタックに退避する。
	movem.l %D0-%D7/%A0-%A6, -(%SP) 	/* D0-D7, A0-A6 をスタックに退避 */

	* タイマー割り込み要因フラグのクリア（mon.sの処理を継続）
	move.w 	#0x0000, TSTAT1 		/* TSTAT1 (タイマステータスレジスタ) のCOMPフラグをクリア */

	* ==================================================================
	* 【タスクスイッチ処理の中核】
	* ==================================================================

	* 2. addq()により、curr_taskをreadyの末尾に追加。
	* 引数設定: addq(ready, curr_task)
	
	* 引数2 (curr_task ID) のプッシュ
	lea.l 	curr_task, %A0			/* curr_task変数のアドレスをA0に */
	move.l 	(%A0), %D0				/* D0 = curr_task ID をロード */
	move.l 	%D0, -(%SP)				/* 引数2: curr_task ID をプッシュ */

	* 引数1 (readyキューのアドレス) のプッシュ
	lea.l 	ready, %A0				/* readyキュー変数のアドレスをA0に */
	move.l 	%A0, -(%SP)				/* 引数1: readyアドレス をプッシュ */

	* addq 関数を呼び出す
	jsr 	addq					/* addq(ready, curr_task) を実行 */
	
	* スタックポインタの補正 (呼び出し側が引数分のスタックをクリーンアップ)
	adda.l 	#8, %SP					/* 引数2つ分 (4byte * 2 = 8byte) をスタックから除去 */

	* 3. schedを起動
	* 次に実行されるタスクの ID (next_task) を選定する。
	jsr 	sched					/* sched() (スケジューラ) を実行 */

	* 4. swtchを起動
	* コンテキストの切り替えを実行する。
	jsr 	swtch					/* swtch() (コンテキストスイッチ本体) を実行 */

	* ==================================================================

.hard_clock_exit:
	* 5. レジスタの復帰
	* swtchがRTEで復帰するため、通常は実行されないが、念のため配置。
	movem.l (%SP)+, %D0-%D7/%A0-%A6 	/* 退避したレジスタを復帰 */

	move.b #'m', LED0
	rts							/* 呼び出し元（割り込みインターフェース）に復帰 */
	
* ----------------------------------------------------------------------
* 【注】 swtch, first_task, pv_handler などは、このファイルの後続に実装する。
* ----------------------------------------------------------------------


.section .text
    .even
    .global first_task
    
    /* 外部変数の参照宣言 */
    .extern curr_task
    .extern task_tab

/*----------------------------------------------------------------
 * first_task: 最初のタスクの起動 [cite: 854]
 * C言語の begin_sch() から呼ばれる。スーパバイザモードで動作。
 *----------------------------------------------------------------*/
 
first_task:
	move.b #'N', LED0
	move.w #0x2700,%SR
    /* 1. TCB 先頭番地の計算 */
    /* curr_task (ID) を取得 */
    move.l  curr_task, %d0
    
    /* TCBのアドレス計算: task_tab + (id * sizeof(TCB)) */
    /* sizeof(TCB) は構造体定義によるが、ここでは仮にオフセット計算を行う */
    /* Cコンパイラの出力に合わせて調整が必要だが、通常 TCB配列へのアクセスは */
    /* ポインタ演算で行うのが楽。アセンブリで配列アクセスする場合： */
    
    /* task_tab のアドレスを A0 に */
    lea     task_tab, %a0
    
    /* TCBのサイズを掛ける (例えばTCBが20バイトなら 20倍) */
    /* ここでは簡略化のため、C側で計算されたポインタ等が使えれば楽だが、直接計算する。TCB_TYPEのサイズ計算が必要。*/
    /*ptr(4) + ptr(4) + int(4) + int(4) + int(4) = 20 byte と仮定 */
    mulu    #20, %d0        /* D0 = id * 20 */
    adda.l  %d0, %a0        /* A0 = &task_tab[curr_task] */

    /* 2. USP, SSPの値の回復 [cite: 859] */
    /* TCBのメンバ stack_ptr (オフセット4) から保存されたSSPを取り出す */
    /* stack_ptr は task_addr(4byte) の次にあるので 4(%a0) */
    move.l  4(%a0), %sp     /* SSP を回復 (これでスタックが切り替わる) */

    /* スタックトップにある USP の値を回復 */
    /* init_stack で積んだ順序の逆を行う */
    /* 現在のSPが指している場所に USP の初期値がある */
    move.l  (%sp)+, %a1     /* スタックからUSPの値を取り出し A1 へ */
    move.l  %a1, %usp       /* USP レジスタに設定 */

    /* 3. 残りの全レジスタの回復 [cite: 861] */
    /* スタックには D0-D7, A0-A6 が積まれているはず */
    movem.l (%sp)+, %d0-%d7/%a0-%a6

    /* 4. ユーザタスクの起動 [cite: 863] */
    /* スタックには SR, PC が残っている */
	move.w #0x2000,%SR
	move.b #'n', LED0
    rte
	

**-----------------------
** P
** Cプログラムから呼ばれる
** 引数：セマフォID
**-----------------------

P:
	move.b #'O', LED0
	movem.l	%d0-%d1/%a0, -(%sp)	/* レジスタ退避 */
	move.l	#0, %d0		/* PのID */
	move.l	%sp, %a0
	add.l	#16, %a0
	move.l	(%a0), %d1	/* セマフォID */
	trap	#1
	movem.l	(%sp)+, %d0-%d1/%a0	/* レジスタ回復 */
	move.b #'o', LED0
	rts
	
	
**-----------------------
** V
** Cプログラムから呼ばれる
** 引数：セマフォID
**-----------------------

V:
	move.b #'P', LED0
	movem.l	%d0-%d1/%a0, -(%sp)	/* レジスタ退避 */
	move.l	#1, %d0		/* VのID */
	move.l	%sp, %a0
	add.l	#16, %a0
	move.l	(%a0), %d1	/* セマフォID */
	trap	#1
	movem.l	(%sp)+, %d0-%d1/%a0	/* レジスタ回復 */
	move.b #'p', LED0
	rts
	
	
**-------------------------
** pv_handler
** TRAP#1によって呼ばれる
** 引数：
** d0: システムコールの種類
** d1: セマフォID
**-------------------------
pv_handler:
	move.b #'Q', LED0
	movem.l	%d0-%d1, -(%sp)	/* レジスタ退避 */
	move.w	%SR, -(%sp)
	move.w	#0x2700, %SR	/* 割り込み禁止（走行レベル7） */
	move.l	%d1, -(%sp)	/* 引数としてセマフォIDをスタックに積む */
	cmp	#0, %d0
	beq	call_p_body	/* p_body()呼び出し */
	bra	call_v_body	/* v_body()呼び出し */
	
call_p_body:
	jsr	p_body
	bra	pv_handler_end
	
call_v_body:
	jsr	v_body
	bra	pv_handler_end
	
pv_handler_end:
	addq.l	#4, %sp		/* スタックの引数の分を戻す */
	move.w	(%sp)+, %SR	/* 割り込み禁止解除 */
	movem.l	(%sp)+, %d0-%d1	/* レジスタ回復 */
	move.b #'q', LED0
	rte
	


/*------- swtch: タスクスイッチ関数 -----------*/
.section .text
.even

swtch:
	move.b #'R', LED0
	/* 1: SR をスタックに積んで，RTE で復帰できるようにする． */
	move.w	%sr, -(%sp)
	
	/* 2: 実行中のタスクのレジスタの退避 */
	movem.l	%d0-%d7/%a0-%a6, -(%sp)
	move.l	%usp, %a1
	move.l	%a1, -(%sp)
	
	/* 3: SSP の保存 */
	move.l	curr_task, %d1
	
	lea	task_tab, %a0
	mulu	#20, %d1
	adda.l	%d1, %a0
	
	move.l	%sp, 4(%a0)
	
	/* 4: curr task を変更 */
	move.l	next_task, %d1
	move.l	%d1, curr_task
	
	/* 5: 次のタスクの SSP の読み出し */
	lea	task_tab, %a0
	mulu	#20, %d1
	adda.l	%d1, %a0
	
	move.l	4(%a0), %sp
	
	/* 6: 次のタスクのレジスタの読み出し */
	move.l	(%sp)+, %a1
	move.l	%a1, %usp
	movem.l	(%sp)+, %d0-%d7/%a0-%a6
	
	/* 7: タスク切り替えをおこす */
	move.b #'r', LED0
	rte
	


***************
** LED
**ボード搭載の LED 用レジスタ,使用法については付録 A.4.3.1
***************
	.equ IOBASE , 0x00d00000
	.equ LED7, IOBASE+0x000002f
	.equ LED6, IOBASE+0x000002d 
	.equ LED5, IOBASE+0x000002b
	.equ LED4, IOBASE+0x0000029
	.equ LED3, IOBASE+0x000003f
	.equ LED2, IOBASE+0x000003d
	.equ LED1, IOBASE+0x000003b
	.equ LED0, IOBASE+0x0000039


/* 外部参照（C言語カーネル部や他のアセンブリルーチン）に追加 */
    .extern inbyte_body     /* C言語のinbyte処理本体（モニタシステムコールラッパー） */
    .extern outbyte_body    /* C言語のoutbyte処理本体（モニタシステムコールラッパー） */

.section .text
.even

**-----------------------
** inbyte
** Cプログラムから呼ばれる: char inbyte(int uart_ch)
**-----------------------
inbyte:
	move.b #'S', LED0
	movem.l	%d0/%d1/%a0, -(%sp)	/* レジスタ退避 (使用するD0, D1, A0) */
	
    /* 1. 引数(uart_ch)をスタックから取り出しD1にセット */
	move.l	%sp, %a0
	add.l	#12, %a0            /* スタックトップ + 退避レジスタ(4*3) = 引数の位置 */
	move.l	(%a0), %d1	        /* D1 = uart_ch をロード */
	
    /* 2. C関数 inbyte_body(uart_ch) を呼び出し */
	move.l	%d1, -(%sp)		    /* 引数(uart_ch)をプッシュ */
	jsr 	inbyte_body
	addq.l	#4, %sp		        /* スタックの引数の分を戻す */

    /* 3. 戻り値D0をCの戻り値として扱う (inbyte_bodyがD0にセットしていることを前提) */
    
	movem.l	(%sp)+, %d0/%d1/%a0	/* レジスタ回復 */
	move.b #'s', LED0
	rts
	
	
**-----------------------
** outbyte
** Cプログラムから呼ばれる: void outbyte(unsigned char c, int uart_ch)
**-----------------------
outbyte:
	move.b #'T', LED0
	movem.l	%d0/%d1/%a0, -(%sp)	/* レジスタ退避 (使用するD0, D1, A0) */
	
    /* 1. 引数(c, uart_ch)をスタックから取り出しD1, D0にセット */
    /* スタック: [SP] -> (uart_ch), [SP+4] -> (c) の順で積まれていると仮定 */
	move.l	%sp, %a0
	add.l	#12, %a0            /* A0を第1引数(uart_ch)のアドレスへ */
	move.l	(%a0), %d1	        /* D1 = uart_ch (第1引数) をロード */
    
	add.l	#4, %a0             /* A0を第2引数(c)のアドレスへ */
	move.l	(%a0), %d0	        /* D0 = c (第2引数, 32bit拡張済み) をロード */
	
    /* 2. C関数 outbyte_body(c, uart_ch) を呼び出し */
    /* C関数側の定義: outbyte_body(c, ch) -> スタックに (ch), (c) の順でプッシュ */
	move.l	%d1, -(%sp)		    /* 引数2: uart_ch をプッシュ */
	move.l	%d0, -(%sp)		    /* 引数1: c をプッシュ */
    
	jsr 	outbyte_body
	adda.l	#8, %sp		        /* 引数2つ分 (8byte) をスタックから除去 */
	
	movem.l	(%sp)+, %d0/%d1/%a0	/* レジスタ回復 */
	move.b #'t', LED0
	rts
