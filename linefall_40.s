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

** トルクスイッチ (DIPSW) の定義
	.equ DIPSW, IOBASE+0x041	/* 修正: 0x031 -> 0x041 (TSW のアドレス) */


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
** コールバックルーチンポインタ
********************
* SET_TIMER のコールバックルーチンポインタ
task_p:
	.ds.l 1		/* 4バイトの領域を確保 */

****************************************************************
** ゲーム用データ構造 (BSS領域: 初期値なし)
****************************************************************
.section .bss
.even

* --- 画面定義 (5x40) ---
	.equ SCR_WIDTH, 40	/* 画面幅 (列数) */
	.equ SCR_HEIGHT, 5	/* 画面高さ (5行) */
	.equ MIN_X, 1		
	.equ MAX_X, 40		
	.equ PLAYER_ROW_BOTTOM, (SCR_HEIGHT-1) /* プレイヤーのY座標 (床=4行目) */

* --- プレイヤー (1名) ---
PLAYER_X:	.ds.w 1		/* プレイヤーのX座標 (固定) */
PLAYER_Y:	.ds.w 1		/* プレイヤーのY座標 (可変) */
PLAYER_VY:	.ds.w 1		/* Y軸速度 (VY) */
PLAYER_ON_FLOOR:.ds.w 1	/* 0=空中, 1=接地, 2=2段ジャンプ済 */

* --- 弾 (最大10発) ---
	.equ MAX_BULLETS, 10
BULLET_STATE:	.ds.b MAX_BULLETS	/* 0=off, 1=on */
BULLET_X:	.ds.b MAX_BULLETS	/* X座標 */
BULLET_Y:	.ds.b MAX_BULLETS	/* Y座標 */

* --- 敵 (最大20体) ---
	.equ MAX_ENEMIES, 20
ENEMY_STATE:	.ds.b MAX_ENEMIES	/* 0=off, 1='l', 2='l-l-l' */
ENEMY_X:	.ds.b MAX_ENEMIES	/* X座標 (byte) */
ENEMY_Y:	.ds.b MAX_ENEMIES	/* Y座標 (byte) */

* --- 画面描画バッファ ---
	.equ FRAME_BUF_SIZE, (SCR_WIDTH + 10) * SCR_HEIGHT + 100 /* 制御コード分も考慮 */
FRAME_BUF:
	.ds.b FRAME_BUF_SIZE	/* ターミナル送信用の一次バッファ */
FRAME_LEN:
	.ds.l 1			/* 構築されたバッファの実サイズ */

* --- 追加: ゲームオーバー/プレイ中 共通バッファ ---
FINAL_SCORE_LINE:
	.ds.b 40		/* Y=4 または Y=1 の行バッファ (SCR_WIDTH と同じ) */


***************************************************************
** 初期化
***************************************************************

	.section .text
	.even
boot:
	move.w #0x2700,%SR
	lea.l SYS_STK_TOP, %SP
****************
** 割り込みコントローラの初期化
****************
	move.b #0x40, IVR
	move.l #0x00ffffff,IMR
****************
** 送受信 (UART1) 関係の初期化
****************
	move.w #0x0000, USTCNT1
	move.w #0xe100, USTCNT1
	move.w #0x0038, UBAUD1
* キューの初期化
QueueInitialize:
	movem.l	%d0-%d1,-(%sp)		/* 修正: D/A 分離 */
	movem.l	%a0-%a2,-(%sp)
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
	movem.l	(%sp)+,%a0-%a2		/* 修正: D/A 分離 */
	movem.l	(%sp)+,%d0-%d1
	
****************
** タイマ関係の初期化
*****************
	move.w #0x0004, TCTL1
						
	* TRAP #0 ハンドラをベクタテーブルに登録
	move.l	#TRAP0_HANDLER, 0x0080
	
	/* UART1 割り込み(レベル4, ベクタ68) ハンドラを設定 */
	move.l #send_or_receive, 0x110
	
	/* タイマ1 割り込み(レベル6, ベクタ70) ハンドラを設定 */
	move.l #timer1_interrupt, 0x118
	
	/* UART(レベル4)の割り込みマスクをIMRで解除 */
	andi.l #0xfffffff9, IMR
	
	bra INIT
******************
** 初期化（追加部分）
******************
.section .text
.even
INIT:
	move.w	#0x2000, %SR
	move.w #0xE10C, USTCNT1


***************
** システムコール番号 (ゲーム用)
***************
.equ SYSCALL_NUM_PUTSTRING, 2
.equ SYSCALL_NUM_RESET_TIMER, 3
.equ SYSCALL_NUM_SET_TIMER, 4
.equ SYSCALL_NUM_OUTQ, 5
.equ SYSCALL_NUM_GET_DIPSW, 6	

****************************************************************
*** プログラム領域 (ゲームメイン)
****************************************************************
.section .text
.even
MAIN:
** 走行モードとレベルの設定 (「ユーザモード」への移行処理)
	move.w #0x0000, %SR
	lea.l USR_STK_TOP,%SP

* --- ゲームプログラム ---

* (1) ゲーム初期化 (初回1回のみ)
	jsr GAME_INIT
	
* (2) 0.1秒タイマーを起動 (t=1000 * 0.1ms = 100ms = 0.1s)
	move.l #SYSCALL_NUM_SET_TIMER, %D0
	move.l #1000, %D1		
	move.l #CLOCK_TICK, %D2
	trap #0
	
* (3) 最初のフレームを描画フラグを立てる
	move.w #1, UPDATE_FLAG

* (4) メインループ
.MAIN_LOOP:
	* (A) タイマーフラグ(0.1秒)が立つまでひたすら待機
	move.w UPDATE_FLAG, %D0
	cmpi.w #0, %D0
	beq .MAIN_LOOP		/* 0ならループ (待機) */

	* --- 0.1秒ごとの処理 (フラグが 1 だった場合) ---
	move.w #0, UPDATE_FLAG	/* (B) フラグをリセット */
	
	* (C) タイミングが来たので、キー入力を処理する
.L_Input_Drain:
	move.l #SYSCALL_NUM_OUTQ, %D0
	move.l #0, %D1			
	trap #0
	
	cmp.l #0,%d0
	beq .L_Input_Done	/* キューが空になったら入力処理完了 */
	
	move.l %d1, %d0		/* D0に入力文字(d1)を渡す */
	jsr HANDLE_INPUT	
	bra .L_Input_Drain	/* キューにまだあるかチェック */
.L_Input_Done:

	* (D) ゲームロジック更新 (物理演算 + 敵ロジック + 衝突検知)
	jsr GAME_UPDATE_LOGIC	

	* (E) 画面バッファ構築 (ANSIコード, 枠, オブジェクト描画)
	jsr GAME_RENDER_SCREEN

	* (F) 画面バッファを一括送信
	move.l #SYSCALL_NUM_PUTSTRING, %D0
	move.l #0, %D1
	move.l #FRAME_BUF, %D2
	move.l FRAME_LEN, %D3
	trap #0

	* (G) メインループの先頭に戻り、次のタイマーを待つ
	bra .MAIN_LOOP

****************************************************************
*** ゲーム用サブルーチン
****************************************************************
GAME_INIT:
* 役割: ゲーム開始時に1回だけ呼ばれる
	move.l %d0,-(%sp)		/* 修正: D/A 分離 */
	move.l %a0,-(%sp)

	* (1) 修正: トルクスイッチ読み取り (機能追加)
	move.l #SYSCALL_NUM_GET_DIPSW, %d0
	trap #0
	andi.l #0x0001, %d0		/* ビット0 (TSW) のみ読み取り */
	move.w %d0, DIFFICULTY
	
	* (2) 状態初期化 (Time関連削除)
	move.l #0, GAME_SCORE
	move.w #1, GAME_STATE		/* 1 = プレイ中 */
	move.w #(MIN_X+2), PLAYER_X	/* X座標は 3 (1+2) で固定 */
	move.w #PLAYER_ROW_BOTTOM, PLAYER_Y /* Y座標は床(4)で開始 */
	move.w #0, PLAYER_VY		/* Y速度は 0 で開始 */
	move.w #1, PLAYER_ON_FLOOR	/* 接地状態で開始 */
	move.w #0, SPAWN_COUNTER
	
	* (3) 弾と敵のリストをクリアする処理
	moveq #0, %d0			/* d0 = i (カウンタ) */
	lea.l ENEMY_STATE, %a0
.L_Clear_Enemy:
	move.b #0, (%a0)+		/* 修正: (An, Dn.W) -> (An)+ */
	addq.w #1, %d0
	cmpi.w #MAX_ENEMIES, %d0
	bne .L_Clear_Enemy
	
	* (3b) 弾リストのクリア
	moveq #0, %d0			/* d0 = i (カウンタ) */
	lea.l BULLET_STATE, %a0
.L_Clear_Bullet:
	move.b #0, (%a0)+		/* 修正: (An, Dn.W) -> (An)+ */
	addq.w #1, %d0
	cmpi.w #MAX_BULLETS, %d0
	bne .L_Clear_Bullet
	
	move.l (%sp)+, %a0
	move.l (%sp)+, %d0
	rts

*--------------------------------------------------------------
* HANDLE_INPUT (リスタート 'r' を再実装)
*--------------------------------------------------------------
HANDLE_INPUT:
* 役割: メインループからキー文字(D0)を受け取り処理する
	
	cmpi.b #' ', %d0
	beq .FIRE_JUMP		/* スペースキー */
	
	cmpi.b #'r', %d0
	beq .RESTART_GAME	/* 'r' キー */
	
	bra .INPUT_END		/* 上記以外は無視 */

.FIRE_JUMP:
	* (A) プレイヤーが床(Y=4)にいるかチェック
	move.w PLAYER_ON_FLOOR, %d0
	cmpi.w #1, %d0
	beq .DO_FIRST_JUMP	/* 床にいる -> 1段目ジャンプへ */
	
	* (B) 既に空中にいる場合 (2段目ジャンプの判定)
	cmpi.w #0, %d0		/* 0=ジャンプ中か？ (2段ジャンプ未使用) */
	beq .DO_SECOND_JUMP	/* 2段ジャンプ実行へ */
	
	bra .INPUT_END		/* (PLAYER_ON_FLOOR が 2=2段目使用済 の場合) 何もしない */
	
.DO_FIRST_JUMP:
	move.w #-2, PLAYER_VY		/* 1段目のジャンプ力 */
	move.w #0, PLAYER_ON_FLOOR	/* 状態を「ジャンプ中(0)」に */
	bra .INPUT_END

.DO_SECOND_JUMP:
	move.w #-2, PLAYER_VY		/* 2段目のジャンプ力 (1段目と同じ力) */
	move.w #2, PLAYER_ON_FLOOR	/* 状態を「2段ジャンプ使用済(2)」に */
	bra .INPUT_END

.RESTART_GAME:
	* (C) ゲームオーバー状態(2)の時だけリスタート
	move.w GAME_STATE, %d0
	cmpi.w #2, %d0
	bne .INPUT_END		/* ゲーム中でなければ無視 */
	
	jsr GAME_INIT		/* ゲームを初期化 */

.INPUT_END:
	rts

*--------------------------------------------------------------
* GAME_UPDATE_LOGIC (衝突検知を追加)
*--------------------------------------------------------------
GAME_UPDATE_LOGIC:
	movem.l %d0,-(%sp)		/* d0レジスタを退避 */
	
	* (1) ゲームがプレイ中(1)か確認
	move.w GAME_STATE, %d0
	cmpi.w #1, %d0
	bne .L_GUL_EXIT		/* プレイ中以外は何もしない */

	* (2) プレイヤーのY軸物理演算
	* (2A) 重力を加える (VY = VY + 1)
	addq.w #1, PLAYER_VY
	
	* (2B) 速度を位置に反映 (Y = Y + VY)
	move.w PLAYER_Y, %d0
	add.w PLAYER_VY, %d0
	move.w %d0, PLAYER_Y
	
	* (2C) 床との衝突判定
	cmpi.w #PLAYER_ROW_BOTTOM, %d0	/* Y >= 床(4) か？ */
	blt .L_GUL_NO_FLOOR		/* Yが床より上(2,3)なら衝突しない */
	
	* (衝突した場合)
	move.w #PLAYER_ROW_BOTTOM, PLAYER_Y	/* 位置を床(4)に固定 */
	move.w #0, PLAYER_VY		/* 速度を 0 にリセット */
	move.w #1, PLAYER_ON_FLOOR	/* 状態を「接地(1)」に */

.L_GUL_NO_FLOOR:
	* (3) 敵のロジック (出現・移動)
	jsr MOVE_ENEMIES
	jsr SPAWN_ENEMY
	
	* (4) TODO: 弾のロジック (移動)

	* (5) TODO: 当たり判定 (弾 vs 敵)

	* (6) プレイヤー vs 敵 当たり判定
	jsr CHECK_COLLISIONS

.L_GUL_EXIT:
	movem.l (%sp)+, %d0		/* d0レジスタを復帰 */
	rts

*--------------------------------------------------------------
* 修正: MOVE_ENEMIES (アセンブルエラー回避)
*--------------------------------------------------------------
MOVE_ENEMIES:
	movem.l %d0-%d2,-(%sp)	/* 修正: D/A 分離 */
	movem.l %a0-%a3,-(%sp)	/* a3も使用 */
	
	moveq #0, %d2			/* d2 = i (インデックス) */
	lea.l ENEMY_STATE, %a0
	lea.l ENEMY_X, %a1
.MOVE_LOOP:
	move.l %a0, %a3		/* a3 = STATE_Base */
	add.w %d2, %a3		/* a3 = STATE_Base + index */
	move.b (%a3), %d0		/* 修正: (An, Dn.W) -> (An) */
	
	cmpi.b #0, %d0
	beq .MOVE_NEXT		/* STATE == 0 (非アクティブ) */

	* (1) 敵を左に1マス移動
	move.l %a1, %a3		/* a3 = X_Base */
	add.w %d2, %a3		/* a3 = X_Base + index */
	subq.b #1, (%a3)		/* 修正: (An, Dn.W) -> (An) */
	
	* (2) 画面外 (X < MIN_X) に出たかチェック
	move.b (%a3), %d0		/* (%a3) は X_Base + index のまま */
	cmpi.b #MIN_X, %d0
	bge .MOVE_NEXT		/* 1以上ならOK */
	
	* (3) 画面外に出たら STATE = 0 (非アクティブ) に
	move.l %a0, %a3		/* a3 = STATE_Base */
	add.w %d2, %a3		/* a3 = STATE_Base + index */
	move.b #0, (%a3)		/* 修正: (An, Dn.W) -> (An) */

.MOVE_NEXT:
	addq.w #1, %d2
	cmpi.w #MAX_ENEMIES, %d2
	bne .MOVE_LOOP

	movem.l (%sp)+,%a0-%a3	/* 修正: D/A 分離 */
	movem.l (%sp)+,%d0-%d2
	rts

*--------------------------------------------------------------
* 修正: SPAWN_ENEMY (0=HARD, 1=EASY + 3:2:2:1)
*--------------------------------------------------------------
SPAWN_ENEMY:
	movem.l %d0-%d3,-(%sp)	/* 修正: D/A 分離 */
	movem.l %a0-%a1,-(%sp)

	* (1) 出現タイミングのランダム化 (1/19)
	move.l GAME_SCORE, %d0
	add.w SPAWN_COUNTER, %d0
	andi.l #0xFFFF, %d0		/* 16bitマスク */
	move.w #19, %d1
	divu.w %d1, %d0
	swap %d0
	andi.l #0xFFFF, %d0
	cmpi.w #0, %d0
	bne .SPAWN_EXIT		/* 余り 0 (1/19の確率) でなければ終了 */

	addq.w #1, SPAWN_COUNTER

	* (2) 修正: パターン決定 ( (GAME_SCORE % 10) + SPAWN_COUNTER )
	move.l GAME_SCORE, %d0	/* d0 = GAME_SCORE (32bit) */
	move.w #10, %d1
	divu.w %d1, %d0		/* d0.w = 商, d0.h = 余り */
	swap %d0		/* d0.w = 余り (0-9) */
	andi.l #0xFFFF, %d0	/* d0 = GAME_SCORE % 10 */

	add.w SPAWN_COUNTER, %d0	/* d0 = (GAME_SCORE % 10) + SPAWN_COUNTER */
	move.l %d0, %d3		/* d3 = (GAME_SCORE % 10) + SPAWN_COUNTER */
	
	* (3) 難易度(DIPSW)に応じてパターン範囲を決定
	move.w DIFFICULTY, %d0
	cmpi.w #0, %d0
	bne .SPAWN_EASY_MODE	/* 修正: bne (0=HARD, 1=EASY) */

.SPAWN_HARD_MODE:		/* 0 (ON) なら Hard (4パターン) */
	move.w #8, %d1		/*  3:2:2:1 (合計8) */
	move.l %d3, %d0		/* d0 = (GAME_SCORE % 10) + SPAWN_COUNTER */
	andi.l #0xFFFF, %d0	/* 16bitマスク */
	divu.w %d1, %d0		/* d0 = [余り]/[商] (16bit除算) */
	swap %d0		/* d0 = [商]/[余り] */
	andi.l #0xFFFF, %d0	/* d0 = パターンID (0-7) */
	move.w %d0, %d3		/* d3 に ID を戻す */

	* (3H) パターンID (d3) に応じて分岐 (3:2:2:1)
	cmpi.w #2, %d3		/* IDが 0,1,2 か？ (3/8) */
	ble .SPAWN_PATT_1	/* Pattern 1: Ground */
	cmpi.w #4, %d3		/* IDが 3,4 か？ (2/8) */
	ble .SPAWN_PATT_2	/* Pattern 2: Air */
	cmpi.w #6, %d3		/* IDが 5,6 か？ (2/8) */
	ble .SPAWN_PATT_3	/* Pattern 3: Ground + Air */
	bra .SPAWN_PATT_4	/* IDが 7 の場合 (1/8) */
	
.SPAWN_EASY_MODE:		/* 1 (OFF) なら Easy (2パターン) */
	move.w #2, %d1		/*  1:1 (合計2) */
	move.l %d3, %d0		/* d0 = (GAME_SCORE % 10) + SPAWN_COUNTER */
	andi.l #0xFFFF, %d0	/* 16bitマスク */
	divu.w %d1, %d0		/* d0 = [余り]/[商] (16bit除算) */
	swap %d0		/* d0 = [商]/[余り] */
	andi.l #0xFFFF, %d0	/* d0 = パターンID (0-1) */
	
	* (3E) パターンID (d0) に応じて分岐 (1:1)
	cmpi.w #0, %d0
	beq .SPAWN_PATT_1
	bra .SPAWN_PATT_2

* --- パターン1: 地上 (Y=4) ---
.SPAWN_PATT_1:
	jsr FIND_SLOT		/* 戻り値: d0 (index or -1) */
	cmpi.w #-1, %d0
	beq .SPAWN_EXIT
	move.w #PLAYER_ROW_BOTTOM, %d1	/* Y=4 */
	move.w #1, %d2			/* STATE=1 */
	jsr SPAWN_SINGLE	/* (d0, d1, d2) で 1体生成 */
	bra .SPAWN_EXIT

* --- パターン2: 空中 (Y=3) ---
.SPAWN_PATT_2:
	jsr FIND_SLOT
	cmpi.w #-1, %d0
	beq .SPAWN_EXIT
	move.w #(PLAYER_ROW_BOTTOM-1), %d1 ; Y=3
	move.w #1, %d2
	jsr SPAWN_SINGLE
	bra .SPAWN_EXIT
	
* --- パターン3: 地上(Y=4) + 空中(Y=3) ---
.SPAWN_PATT_3:
	jsr FIND_TWO_SLOTS	/* 戻り値: d0=idx1, d1=idx2 (or d0=-1) */
	cmpi.w #-1, %d0
	beq .SPAWN_EXIT
	
	move.l %d1, -(%sp)	/* idx2 (d1) をスタックに一時退避 */

	* 1体目 (d0 = idx1)
	move.w #PLAYER_ROW_BOTTOM, %d1	/* Y=4 */
	move.w #1, %d2			/* STATE=1 */
	jsr SPAWN_SINGLE	
	
	move.l (%sp)+, %d0	/* idx2 を d0 に復帰 */

	* 2体目 (d0 = idx2)
	move.w #(PLAYER_ROW_BOTTOM-1), %d1 ; Y=3
	move.w #1, %d2
	jsr SPAWN_SINGLE
	bra .SPAWN_EXIT

* --- パターン4: 地上(Y=4) + 天井(Y=2) ---
.SPAWN_PATT_4:
	jsr FIND_TWO_SLOTS	/* 戻り値: d0=idx1, d1=idx2 (or d0=-1) */
	cmpi.w #-1, %d0
	beq .SPAWN_EXIT
	
	move.l %d1, -(%sp)	/* idx2 (d1) をスタックに一時退避 */
	
	* 1体目 (d0 = idx1)
	move.w #PLAYER_ROW_BOTTOM, %d1	/* Y=4 */
	move.w #1, %d2
	jsr SPAWN_SINGLE
	
	move.l (%sp)+, %d0	/* idx2 を d0 に復帰 */

	* 2体目 (d0 = idx2)
	move.w #(PLAYER_ROW_BOTTOM-2), %d1 ; バスエラー修正: Y=2
	move.w #1, %d2
	jsr SPAWN_SINGLE
	bra .SPAWN_EXIT

.SPAWN_EXIT:
	movem.l (%sp)+,%a0-%a1
	movem.l (%sp)+,%d0-%d3
	rts

*--------------------------------------------------------------
* 追加: FIND_SLOT (アセンブルエラー回避)
* Output: d0 = index (見つからない場合 -1)
*--------------------------------------------------------------
FIND_SLOT:
	movem.l %d2-%d3,-(%sp)	/* 修正: D/A 分離 */
	movem.l %a0-%a1,-(%sp)	/* a1も使用 */

	moveq #0, %d2			/* d2 = i (インデックス) */
	lea.l ENEMY_STATE, %a0
.L_FIND_LOOP:
	move.l %a0, %a1		/* a1 = STATE_Base */
	add.w %d2, %a1		/* a1 = STATE_Base + index */
	move.b (%a1), %d3		/* 修正: (An, Dn.W) -> (An) */
	
	cmpi.b #0, %d3
	beq .L_FIND_FOUND	/* STATE == 0 (empty) */
	
	addq.w #1, %d2
	cmpi.w #MAX_ENEMIES, %d2
	bne .L_FIND_LOOP
	
	moveq #-1, %d2		/* 見つからなかった */
.L_FIND_FOUND:
	move.w %d2, %d0		/* 戻り値を d0 に設定 (インデックスとして) */
	movem.l (%sp)+,%a0-%a1	/* 修正: D/A 分離 */
	movem.l (%sp)+,%d2-%d3
	rts

*--------------------------------------------------------------
* 追加: FIND_TWO_SLOTS (アセンブルエラー回避)
* Output: d0 = index1, d1 = index2 (見つからない場合 d0 = -1)
*--------------------------------------------------------------
FIND_TWO_SLOTS:
	movem.l %d2-%d4,-(%sp)	/* 修正: D/A 分離 */
	movem.l %a0-%a1,-(%sp)	/* a1も使用 */

	moveq #0, %d2			/* d2 = i (インデックス) */
	moveq #-1, %d4			/* d4 = index1 (最初は-1) */
	lea.l ENEMY_STATE, %a0
.L_FIND2_LOOP:
	move.l %a0, %a1		/* a1 = STATE_Base */
	add.w %d2, %a1		/* a1 = STATE_Base + index */
	move.b (%a1), %d3		/* 修正: (An, Dn.W) -> (An) */

	cmpi.b #0, %d3
	bne .L_FIND2_NEXT	/* 空きスロットではない */
	
	* 空きスロットを発見
	cmpi.w #-1, %d4
	bne .L_FIND2_FOUND_SECOND	/* d4が-1でなければ、2つ目を発見 */
	
	move.w %d2, %d4		/* 1つ目。d2 (インデックス) を d4 (index1) に保存 */
	bra .L_FIND2_NEXT

.L_FIND2_FOUND_SECOND:
	* d4 (idx1) と d2 (idx2) が見つかった
	bra .L_FIND2_END
	
.L_FIND2_NEXT:
	addq.w #1, %d2
	cmpi.w #MAX_ENEMIES, %d2
	bne .L_FIND2_LOOP

.L_FIND2_END:
	* ループ終了
	cmpi.w #MAX_ENEMIES, %d2
	bge .L_FIND2_FAIL		/* 2つ目が見つかる前にループが終了した */
	
	* 成功: d4=idx1, d2=idx2 (どちらもインデックス)
	move.w %d4, %d0		/* 戻り値 d0 = idx1 */
	move.w %d2, %d1		/* 戻り値 d1 = idx2 */
	movem.l (%sp)+,%a0-%a1	/* 修正: D/A 分離 */
	movem.l (%sp)+,%d2-%d4
	rts

.L_FIND2_FAIL:
	moveq #-1, %d0		/* 失敗 (d0 = -1) */
	movem.l (%sp)+,%a0-%a1	/* 修正: D/A 分離 */
	movem.l (%sp)+,%d2-%d4
	rts

*--------------------------------------------------------------
* 追加: SPAWN_SINGLE (アセンブルエラー回避)
* Input: d0 = index, d1 = Y, d2 = STATE
*--------------------------------------------------------------
SPAWN_SINGLE:
	movem.l %a0-%a1,-(%sp)	/* Aレジスタのみ退避 */
	* d0 = index, d1 = Y, d2 = STATE
	
	lea.l ENEMY_Y, %a1
	add.w %d0, %a1			/* 修正: Y_Base + index */
	move.b %d1, (%a1)		/* 修正: (An, Dn.W) -> (An) */
	
	lea.l ENEMY_X, %a1
	add.w %d0, %a1			/* 修正: X_Base + index */
	move.b #MAX_X, (%a1)		/* 修正: (An, Dn.W) -> (An) */
	
	lea.l ENEMY_STATE, %a0
	add.w %d0, %a0			/* 修正: STATE_Base + index */
	move.b %d2, (%a0)		/* 修正: (An, Dn.W) -> (An) */
	
	movem.l (%sp)+, %a0-%a1	/* Aレジスタ復帰 */
	rts

*--------------------------------------------------------------
* 修正: CHECK_COLLISIONS (アセンブルエラー回避)
*--------------------------------------------------------------
CHECK_COLLISIONS:
	movem.l %d0-%d3,-(%sp)	/* 修正: D/A 分離 */
	movem.l %a0-%a3,-(%sp)	/* a3も使用 */

	move.w PLAYER_X, %d0		/* d0 = Player X */
	move.w PLAYER_Y, %d1		/* d1 = Player Y */

	moveq #0, %d2			/* d2 = i (インデックス) */
	lea.l ENEMY_STATE, %a0
	lea.l ENEMY_X, %a1
	lea.l ENEMY_Y, %a2
.COLL_LOOP:
	move.l %a0, %a3		/* a3 = STATE_Base */
	add.w %d2, %a3		/* a3 = STATE_Base + index */
	move.b (%a3), %d3		/* 修正: (An, Dn.W) -> (An) */

	cmpi.b #0, %d3
	beq .COLL_NEXT		/* STATE == 0 (非アクティブ) */

	* (1) 敵のY座標とプレイヤーのY座標を比較
	move.l %a2, %a3		/* a3 = Y_Base */
	add.w %d2, %a3		/* a3 = Y_Base + index */
	cmp.b (%a3), %d1		/* 修正: (An, Dn.W) -> (An) */
	bne .COLL_NEXT		/* Yが違う */
	
	* (2) 敵のX座標とプレイヤーのX座標を比較
	move.l %a1, %a3		/* a3 = X_Base */
	add.w %d2, %a3		/* a3 = X_Base + index */
	cmp.b (%a3), %d0		/* 修正: (An, Dn.W) -> (An) */
	bne .COLL_NEXT		/* Xが違う */
	
	* (3) 衝突！
	move.w #2, GAME_STATE		/* GAME_STATE を 2 (Game Over) に */
	bra .COLL_EXIT		/* 衝突検知終了 */

.COLL_NEXT:
	addq.w #1, %d2
	cmpi.w #MAX_ENEMIES, %d2
	bne .COLL_LOOP

.COLL_EXIT:
	movem.l (%sp)+,%a0-%a3	/* 修正: D/A 分離 */
	movem.l (%sp)+,%d0-%d3
	rts

*--------------------------------------------------------------
* 修正: GAME_RENDER_SCREEN (Y=2 天井描画対応 + アセンブルエラー回避)
*--------------------------------------------------------------
GAME_RENDER_SCREEN:
	movem.l %d0-%d7,-(%sp)	/* 修正: D/A 分離 */
	movem.l %a0-%a6,-(%sp)
	
	lea.l FRAME_BUF, %a6		/* a6 = FRAME_BUF 書込ポインタ */

	* (1) ANSI Clear Screen + Home (画面クリア)
	move.l #0x1B5B324A, (%a6)+	/* "\x1b[2J" */
	move.l #0x1B5B4800, (%a6)+	/* "\x1b[H" */
	
	* (A) GAME_STATE によって描画内容を分岐
	move.w GAME_STATE, %d0
	cmpi.w #1, %d0
	beq .RENDER_GAME_PLAY		/* 1=プレイ中 */
	
	bra .RENDER_GAME_OVER		/* 2=ゲームオーバー */

*------------------
* (B) プレイ中の描画
*------------------
.RENDER_GAME_PLAY:
	* (2-1) ステータスライン (Y=1)
	
	* 修正: テンプレートをBSSバッファ(FINAL_SCORE_LINE)にコピー
	lea.l STATUS_LINE_BUF, %a0	/* テンプレート(DATA)を a0 に */
	lea.l FINAL_SCORE_LINE, %a1	/* BSSの一時バッファを a1 に */
	moveq #(STATUS_LINE_LEN-1), %d7
.L_Copy_Status_TPL:
	move.b (%a0)+, (%a1)+
	dbra %d7, .L_Copy_Status_TPL

	* 修正: モードをBSSバッファに書き込む (0=HARD, 1=EASY)
	move.w DIFFICULTY, %d0
	cmpi.w #0, %d0
	bne .DRAW_PLY_MODE_EASY		/* 0=HARD, 1=EASY */
	
.DRAW_PLY_MODE_HARD:
	lea.l MSG_HARD, %a0
	bra .DRAW_PLY_MODE_COPY
.DRAW_PLY_MODE_EASY:
	lea.l MSG_EASY, %a0
	
.DRAW_PLY_MODE_COPY:
	lea.l FINAL_SCORE_LINE+6, %a1	/* BSSバッファの "Mode: " の後へ */
	moveq #(MODE_STR_LEN-1), %d1	/* 5回ループ */
.L_Copy_Ply_Mode:
	move.b (%a0)+, (%a1)+
	dbra %d1, .L_Copy_Ply_Mode
	
	* スコア(5桁)を計算し、BSSバッファに書き込む
	move.l GAME_SCORE, %d0
	lea.l FINAL_SCORE_LINE+20, %a0	/* BSSバッファの "score:00000" の "0" の位置 */
	jsr BIN_TO_ASCII_5		
	
	* 修正: BSSバッファを FRAME_BUF にコピー (STATUS_LINE_LEN まで)
	lea.l FINAL_SCORE_LINE, %a0
	move.w #1, %d7			/* d7 = Xカウンタ */
.L_Copy_Status:
	move.b (%a0)+, (%a6)+
	addq.w #1, %d7
	cmpi.w #(STATUS_LINE_LEN+1), %d7
	bne .L_Copy_Status
	
	* 修正: 残りを '-' で埋める (STATUS_LINE_LEN から SCR_WIDTH まで)
.L_Fill_Status:
	move.b #'-', (%a6)+
	addq.w #1, %d7
	cmpi.w #(SCR_WIDTH+1), %d7	/* X=41 になるまで */
	bne .L_Fill_Status
	
	move.w #0x0D0A, (%a6)+		/* "\r\n" */

	* (2-2) プレイエリア (Y=2, 天井)
	move.w #1, %d0			/* d0 = Xカウンタ (X=1) */
.L_Render_Y2_X:
	* (B) プレイヤーの描画判定
	cmpi.w #2, PLAYER_Y		/* プレイヤーY == 2 か？ */
	bne .L_Draw_Enemy_Y2
	cmp.w PLAYER_X, %d0		/* プレイヤーX == X か？ */
	bne .L_Draw_Enemy_Y2
	move.b #'@', (%a6)+		/* プレイヤー(@)を描画 */
	bra .L_Render_X2_Next
	
.L_Draw_Enemy_Y2:
	* (C) 敵の描画判定 (Y=2)
	moveq #0, %d2			/* d2 = i (敵インデックス) */
	lea.l ENEMY_STATE, %a0
	lea.l ENEMY_X, %a1
	lea.l ENEMY_Y, %a2
.L_Enemy_Y2_Loop:
	move.l %a0, %a3		/* 修正: Base address */
	add.w %d2, %a3		/* 修正: Add index */
	move.b (%a3), %d3		/* 修正: (An, Dn.W) */
	cmpi.b #0, %d3
	beq .L_Enemy_Y2_Next
	
	move.l %a2, %a3		/* 修正: Y */
	add.w %d2, %a3
	cmpi.b #2, (%a3)		/* 修正: (An, Dn.W) */
	bne .L_Enemy_Y2_Next
	
	move.l %a1, %a3		/* 修正: X */
	add.w %d2, %a3
	cmp.b (%a3), %d0		/* 修正: (An, Dn.W) */
	bne .L_Enemy_Y2_Next
	
	move.b #'l', (%a6)+		/* 敵 'l' を描画 */
	bra .L_Render_X2_Next
.L_Enemy_Y2_Next:
	addq.w #1, %d2
	cmpi.w #MAX_ENEMIES, %d2
	bne .L_Enemy_Y2_Loop
	
	* (D) TODO: 弾の描画 (Y=2)
	
.L_Draw_Empty_Y2:
	move.b #' ', (%a6)+		/* 空白を描画 */
	
.L_Render_X2_Next:
	addq.w #1, %d0			/* X++ */
	cmpi.w #(SCR_WIDTH+1), %d0
	bne .L_Render_Y2_X		/* Xループ */
	move.w #0x0D0A, (%a6)+		/* "\r\n" */

	* (2-3) プレイエリア (Y=3)
	move.w #1, %d0			/* d0 = Xカウンタ (X=1) */
.L_Render_Y3_X:
	* (B) プレイヤーの描画判定
	cmpi.w #3, PLAYER_Y		/* プレイヤーY == 3 か？ */
	bne .L_Draw_Enemy_Y3
	cmp.w PLAYER_X, %d0		/* プレイヤーX == X か？ */
	bne .L_Draw_Enemy_Y3
	move.b #'@', (%a6)+		/* プレイヤー(@)を描画 */
	bra .L_Render_X3_Next
	
.L_Draw_Enemy_Y3:
	* (C) 敵の描画判定 (Y=3)
	moveq #0, %d2			/* d2 = i (敵インデックス) */
	lea.l ENEMY_STATE, %a0
	lea.l ENEMY_X, %a1
	lea.l ENEMY_Y, %a2
.L_Enemy_Y3_Loop:
	move.l %a0, %a3		/* 修正 */
	add.w %d2, %a3
	move.b (%a3), %d3		/* 修正 */
	cmpi.b #0, %d3
	beq .L_Enemy_Y3_Next
	
	move.l %a2, %a3		/* 修正 */
	add.w %d2, %a3
	cmpi.b #3, (%a3)		/* 修正 */
	bne .L_Enemy_Y3_Next
	
	move.l %a1, %a3		/* 修正 */
	add.w %d2, %a3
	cmp.b (%a3), %d0		/* 修正 */
	bne .L_Enemy_Y3_Next
	
	move.b #'l', (%a6)+		/* 敵 'l' を描画 */
	bra .L_Render_X3_Next
.L_Enemy_Y3_Next:
	addq.w #1, %d2
	cmpi.w #MAX_ENEMIES, %d2
	bne .L_Enemy_Y3_Loop
	
	* (D) TODO: 弾の描画 (Y=3)
	
.L_Draw_Empty_Y3:
	move.b #' ', (%a6)+		/* 空白を描画 */
	
.L_Render_X3_Next:
	addq.w #1, %d0			/* X++ */
	cmpi.w #(SCR_WIDTH+1), %d0
	bne .L_Render_Y3_X		/* Xループ */
	move.w #0x0D0A, (%a6)+		/* "\r\n" */

	* (2-4) プレイエリア (Y=4, 床)
	move.w #1, %d0			/* d0 = Xカウンタ (X=1) */
.L_Render_Y4_X:
	* (B) プレイヤーの描画判定
	cmpi.w #4, PLAYER_Y		/* プレイヤーY == 4 か？ */
	bne .L_Draw_Enemy_Y4
	cmp.w PLAYER_X, %d0		/* プレイヤーX == X か？ */
	bne .L_Draw_Enemy_Y4
	move.b #'@', (%a6)+		/* プレイヤー(@)を描画 */
	bra .L_Render_X4_Next

.L_Draw_Enemy_Y4:
	* (C) 敵の描画判定 (Y=4)
	moveq #0, %d2			/* d2 = i (敵インデックス) */
	lea.l ENEMY_STATE, %a0
	lea.l ENEMY_X, %a1
	lea.l ENEMY_Y, %a2
.L_Enemy_Y4_Loop:
	move.l %a0, %a3		/* 修正 */
	add.w %d2, %a3
	move.b (%a3), %d3		/* 修正 */
	cmpi.b #0, %d3
	beq .L_Enemy_Y4_Next
	
	move.l %a2, %a3		/* 修正 */
	add.w %d2, %a3
	cmpi.b #4, (%a3)		/* 修正 */
	bne .L_Enemy_Y4_Next
	
	move.l %a1, %a3		/* 修正 */
	add.w %d2, %a3
	cmp.b (%a3), %d0		/* 修正 */
	bne .L_Enemy_Y4_Next
	
	move.b #'l', (%a6)+		/* 敵 'l' を描画 */
	bra .L_Render_X4_Next
.L_Enemy_Y4_Next:
	addq.w #1, %d2
	cmpi.w #MAX_ENEMIES, %d2
	bne .L_Enemy_Y4_Loop
	
	* (D) TODO: 弾の描画 (Y=4)

.L_Draw_Empty_Y4:
	move.b #' ', (%a6)+		/* 空白を描画 */
	
.L_Render_X4_Next:
	addq.w #1, %d0			/* X++ */
	cmpi.w #(SCR_WIDTH+1), %d0
	bne .L_Render_Y4_X		/* Xループ */
	move.w #0x0D0A, (%a6)+		/* "\r\n" */

	* (2-5) 境界線 (Y=5)
	move.b #'+', (%a6)+		/* '+' */
	moveq #(SCR_WIDTH-2-1), %d7	/* 37回ループ */
.L_Bottom_Line:
	move.b #'-', (%a6)+
	dbra %d7, .L_Bottom_Line
	move.b #'+', (%a6)+		/* '+' */
	* 修正: 最後の行の \r\n を削除
	
	bra .RENDER_FINISH		/* 描画終了へ */

*------------------
* (C) 修正: ゲームオーバー画面 (スコア + モード表示)
*------------------
.RENDER_GAME_OVER:
	* 5x40 のバッファを構築する
	* (1) 1行目 (Y=1)
	lea.l MSG_GO_L1, %a0
	moveq #(SCR_WIDTH-1), %d7
.L_Copy_GO_L1:
	move.b (%a0)+, (%a6)+
	dbra %d7, .L_Copy_GO_L1
	move.w #0x0D0A, (%a6)+		/* "\r\n" */

	* (2) 2行目 (Y=2) - "GAME OVER"
	lea.l MSG_GO_L2, %a0
	moveq #(SCR_WIDTH-1), %d7
.L_Copy_GO_L2:
	move.b (%a0)+, (%a6)+
	dbra %d7, .L_Copy_GO_L2
	move.w #0x0D0A, (%a6)+		/* "\r\n" */

	* (3) 3行目 (Y=3) - "Press 'R'..."
	lea.l MSG_GO_L3, %a0
	moveq #(SCR_WIDTH-1), %d7
.L_Copy_GO_L3:
	move.b (%a0)+, (%a6)+
	dbra %d7, .L_Copy_GO_L3
	move.w #0x0D0A, (%a6)+		/* "\r\n" */

	* (4) 4行目 (Y=4) - 修正: 最終スコア + モード表示
	* (4A) テンプレートをBSSバッファにコピー
	lea.l MSG_GO_L4_TPL, %a0
	lea.l FINAL_SCORE_LINE, %a1
	moveq #(SCR_WIDTH-1), %d7
.L_Copy_TPL_L4:
	move.b (%a0)+, (%a1)+
	dbra %d7, .L_Copy_TPL_L4
	
	* (4B) スコアをBSSバッファに書き込む
	move.l GAME_SCORE, %d0
	lea.l FINAL_SCORE_LINE+10, %a0	/* 修正: "   Score: 00000" の 0 の位置 */
	jsr BIN_TO_ASCII_5
	
	* (4C) 修正: モード文字列をBSSバッファに書き込む (ロジック反転)
	move.w DIFFICULTY, %d0
	cmpi.w #0, %d0
	bne .DRAW_MODE_EASY		/* 修正: 0=HARD, 1=EASY */
	
.DRAW_MODE_HARD:
	lea.l MSG_HARD, %a0		/* (0 の場合) */
	bra .DRAW_MODE_COPY
.DRAW_MODE_EASY:
	lea.l MSG_EASY, %a0		/* (0 以外の場合) */
	
.DRAW_MODE_COPY:
	lea.l FINAL_SCORE_LINE+28, %a1	/* デスティネーション (Mode: の後) */
	moveq #(MODE_STR_LEN-1), %d1	/* d1 = 4 (5回ループ) */
.L_Copy_Mode_Str:
	move.b (%a0)+, (%a1)+
	dbra %d1, .L_Copy_Mode_Str
	
	* (4D) BSSバッファをFRAME_BUFにコピー
	lea.l FINAL_SCORE_LINE, %a0
	moveq #(SCR_WIDTH-1), %d7
.L_Copy_GO_L4:
	move.b (%a0)+, (%a6)+
	dbra %d7, .L_Copy_GO_L4
	move.w #0x0D0A, (%a6)+		/* "\r\n" */
	
	* (5) 5行目 (Y=5)
	lea.l MSG_GO_L5, %a0
	moveq #(SCR_WIDTH-1), %d7
.L_Copy_GO_L5:
	move.b (%a0)+, (%a6)+
	dbra %d7, .L_Copy_GO_L5
	* 修正: 最後の行の \r\n を削除
	
.RENDER_FINISH:
	* (7) 最終的なバッファの長さ(バイト数)を FRAME_LEN に保存する
	lea.l FRAME_BUF, %a0		/* バッファの開始アドレス */
	move.l %a6, %d0			/* バッファの終了アドレス */
	sub.l %a0, %d0			/* d0 = 終了 - 開始 = 長さ */
	move.l %d0, FRAME_LEN		/* FRAME_LEN 変数に保存 */
	
	movem.l (%sp)+,%a0-%a6	/* 修正: D/A 分離 */
	movem.l (%sp)+,%d0-%d7
	rts
*--------------------------------------------------------------
* 修正: CLOCK_TICK (D/A 分離)
*--------------------------------------------------------------
CLOCK_TICK:
	movem.l %d0-%d2,-(%SP)	/* 修正: D/A 分離 */
	move.l %a0,-(%SP)

	* (1) ゲームがプレイ中(1)か確認
	move.w GAME_STATE, %d0
	cmpi.w #1, %d0
	beq .L_CT_IS_PLAYING	/* プレイ中ならスコア加算へ */
	
	* (2) プレイ中以外 (ゲームオーバー中など)
	bra .L_CT_SET_FLAG

.L_CT_IS_PLAYING:
	* (2) スコア(生存フレーム)をインクリメント
	movea.l #GAME_SCORE, %a0
	addq.l #1, (%a0)
	
.L_CT_SET_FLAG:
	* (3) 更新フラグをセット (常に実行)
	move.w #1, UPDATE_FLAG

.CT_EXIT:
	move.l (%sp)+,%a0
	movem.l (%sp)+,%d0-%d2
	rts
	
*--------------------------------------------------------------
* 修正: BIN_TO_ASCII (2桁数値 -> バグ修正)
*--------------------------------------------------------------
BIN_TO_ASCII:
* Input: d0.w, a0 (address)
	movem.l %d1-%d3,-(%sp)
	
	move.l %D0, %D1		/* d1 = d0 (入力値, 例: 12) */
	andi.l #0xFFFF, %D1	
	divu.w #10, %D1		/* d1 = (余り=2) / (商=1) */
	
	move.l %d1, %d2		/* d2 = (余り=2) / (商=1) */
	swap %d2		/* d2 = (商=1) / (余り=2) */
	
	* 1の位 (余り)
	move.l %d2, %d3		/* d3 = (商=1) / (余り=2) */
	andi.l #0xFFFF, %d3	/* d3 = 余り (2) */
	add.b #'0', %d3
	move.b %d3, 1(%a0)
	
	* 10の位 (商)
	andi.l #0xFFFF, %d2	/* d2 = 商 (1) */
	add.b #'0', %d2
	move.b %d2, (%a0)
	
	movem.l (%sp)+, %d1-%d3
	rts

*--------------------------------------------------------------
* 修正: BIN_TO_ASCII_5 (5桁数値 -> スコア計算バグ修正)
*--------------------------------------------------------------
BIN_TO_ASCII_5:
* Input: d0.l (score), a0 (address for 5 chars)
	movem.l %d1-%d3,-(%sp)
	
	move.l %d0, %d1		/* d1 = score (オリジナルを保持) */
	
	* 10000の位
	move.l %d1, %d2		/* d2 = score */
	move.w #10000, %d3
	divu.w %d3, %d2		/* d2.w(下位)=商 */
	andi.l #0xFFFF, %d2
	add.b #'0', %d2
	move.b %d2, (%a0)+
	
	* 1000の位
	move.l %d1, %d2		/* 修正: d1 (オリジナル) から再計算 */
	move.w #10000, %d3
	divu.w %d3, %d2
	swap %d2		/* 余り(10000) */
	andi.l #0xFFFF, %d2
	move.w #1000, %d3
	divu.w %d3, %d2		/* d2.w(下位)=商 */
	andi.l #0xFFFF, %d2
	add.b #'0', %d2
	move.b %d2, (%a0)+

	* 100の位
	move.l %d1, %d2		/* 修正: d1 (オリジナル) から再計算 */
	move.w #1000, %d3
	divu.w %d3, %d2
	swap %d2		/* 余り(1000) */
	andi.l #0xFFFF, %d2
	move.w #100, %d3
	divu.w %d3, %d2		/* d2.w(下位)=商 */
	andi.l #0xFFFF, %d2
	add.b #'0', %d2
	move.b %d2, (%a0)+

	* 10の位
	move.l %d1, %d2		/* 修正: d1 (オリジナル) から再計算 */
	move.w #100, %d3
	divu.w %d3, %d2
	swap %d2		/* 余り(100) */
	andi.l #0xFFFF, %d2
	move.w #10, %d3
	divu.w %d3, %d2		/* d2.w(下位)=商 */
	andi.l #0xFFFF, %d2
	add.b #'0', %d2
	move.b %d2, (%a0)+

	* 1の位
	move.l %d1, %d2		/* 修正: d1 (オリジナル) から再計算 */
	move.w #10, %d3
	divu.w %d3, %d2
	swap %d2		/* 余り(10) */
	andi.l #0xFFFF, %d2
	add.b #'0', %d2
	move.b %d2, (%a0)+
	
	movem.l (%sp)+, %d1-%d3
	rts
	
****************************************************************
*** 初期値のあるデータ領域 (ゲーム用データ)
****************************************************************
.section .data

* --- ゲーム状態管理 ---
GAME_STATE:
	.dc.w 0		/* 0=タイトル, 1=プレイ中, 2=ゲームオーバー */
GAME_SCORE:
	.dc.l 0		/* 生存フレーム数 */
DIFFICULTY:
	.dc.w 0		/* 0=低, 1=中, 2=高 (INITで設定) */
UPDATE_FLAG:
	.dc.w 0		/* 0: 更新不要, 1: 更新必要 */
SPAWN_COUNTER:
	.dc.w 0		
.even

* --- 修正: ステータスラインのテンプレート (モード表示対応) ---
STATUS_LINE_BUF:
	.ascii "Mode:       score:00000 "	/* 修正: 25 bytes */
	.equ STATUS_LINE_LEN, 25		/* 修正: 13 -> 25 */
.even
* --- 修正: ゲームオーバー画面用文字列 (Dumb Terminal + 40列) ---
MSG_GO_L1:
	.ascii "+--------------------------------------+"
.even
MSG_GO_L2:
	.ascii "        GAME OVER                 "
.even
MSG_GO_L3:
	.ascii "     Press 'R' to Restart         "
.even
MSG_GO_L4_TPL:	/* 修正: 4行目をテンプレートに変更 */
	.ascii "   Score: 00000     Mode:          " /* 40 chars */
.even
MSG_GO_L5:
	.ascii "+--------------------------------------+"
.even

* --- 追加: モード表示用文字列 ---
MSG_HARD:
	.ascii "HARD "	/* 5バイト (EASYと合わせる) */
.even
MSG_EASY:
	.ascii "EASY "	/* 5バイト */
.even
	.equ MODE_STR_LEN, 5

****************************************************************
*** 初期値の無いデータ領域 (BSS領域の再配置)
****************************************************************
.section .bss
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
	movem.l	%d0-%d7,-(%sp)	/* 修正: D/A 分離 */
	movem.l	%a0-%a7,-(%sp)
check_receive:
	move.w	URX1, %d3	
	move.b	%d3, %d2	
	andi.w	#0x2000, %d3	
	beq		check_send	
receive_init:
	move.l	#0, %d1		
	jsr		INTERGET	
check_send:
	move.w	UTX1, %d3	
	andi.w 	#0x8000, %d3	
	beq		SoR_end		
send_init:
	move.l	#0, %d1		
	jsr		INTERPUT	
SoR_end:
	movem.l	(%sp)+,%a0-%a7	/* 修正: D/A 分離 */
	movem.l	(%sp)+,%d0-%d7
	rte


***************************************************************
** TRAP #0 (GET_DIPSW を追加)
***************************************************************
TRAP0_HANDLER:
	cmpi.l	#2, %d0		
	beq		SYSCALL_PUTSTRING
	cmpi.l	#3, %d0		
	beq		SYSCALL_RESET_TIMER
	cmpi.l	#4, %d0		
	beq		SYSCALL_SET_TIMER
	cmpi.l	#5, %d0		
	beq		SYSCALL_OUTQ
	cmpi.l	#6, %d0		
	beq		SYSCALL_GET_DIPSW

	bra		TRAP0_EXIT
	
SYSCALL_PUTSTRING:
	move.l	#PUTSTRING, %d0
	jsr		PUTSTRING
	bra		TRAP0_EXIT
SYSCALL_RESET_TIMER:
	move.l	#RESET_TIMER, %d0
	jsr		RESET_TIMER
	bra		TRAP0_EXIT
SYSCALL_SET_TIMER:
	move.l	#SET_TIMER, %d0
	jsr		SET_TIMER
	bra		TRAP0_EXIT
SYSCALL_OUTQ:
	move.l	%d1, %d0	
	jsr		OUTQ
	bra		TRAP0_EXIT
	
SYSCALL_GET_DIPSW:
	/* 新規: DIPSW (IOBASE+0x041) を読み取り D0 に返す */
	move.b DIPSW, %d0
	andi.l #0x00FF, %d0	/* 上位ビットをクリア */
	bra TRAP0_EXIT

TRAP0_EXIT:
	rte

**-----------------------------------------------------------------------
** INQ (アラインメント対応 + D0/D1退避しない)
**----------------------------------------------------------------------
INQ:
	movem.l	%d2-%d3,-(%sp)	/* 修正: D/A 分離 */
	movem.l	%a1-%a3,-(%sp)
	move.w	%SR,%d2				
	move.l	%d2,-(%sp)			
	move.w	#0x2700,%SR			
	lea.l	QUEUES,%a1
	mulu.w	#SIZE,%d0
	adda.l	%d0,%a1
	jsr	PUT_BUF				
	move.l	(%sp)+,%d2			
	move.w	%d2,%SR				
	movem.l	(%sp)+,%a1-%a3	/* 修正: D/A 分離 */
	movem.l	(%sp)+,%d2-%d3
	rts
PUT_BUF:
	move.l	#0,%d2
	move.w	S(%a1),%d3
	cmp.w	#B_SIZE,%d3
	beq	PUT_BUF_Finish
	movea.l	IN(%a1),%a2
	move.b	%d1,(%a2)
	adda.l	#1,%a2
	lea.l	BOTTOM(%a1),%a3
	cmpa.l	%a3,%a2
	bcs	PUT_BUF_STEP1
	lea.l	TOP(%a1),%a2
PUT_BUF_STEP1:
	move.l	%a2,IN(%a1)
	add.w	#1,%d3
	move.w	%d3,S(%a1)
	move.l	#1,%d2
PUT_BUF_Finish:
	move.l	%d2,%d0
	rts

**-----------------------------------------------------------------------
** OUTQ (アラインメント対応 + D0/D1退避しない)
**----------------------------------------------------------------------
OUTQ:
	movem.l	%d2-%d3,-(%sp)	/* 修正: D/A 分離 */
	movem.l	%a1-%a3,-(%sp)
	move.w	%SR,%d2				
	move.l	%d2,-(%sp)			
	move.w	#0x2700,%SR			
	lea.l	QUEUES,%a1
	mulu.w	#SIZE,%d0
	adda.l	%d0,%a1
	jsr	GET_BUF				
	move.l	(%sp)+,%d2			
	move.w	%d2,%SR				
	movem.l	(%sp)+,%a1-%a3	/* 修正: D/A 分離 */
	movem.l	(%sp)+,%d2-%d3
	rts
GET_BUF:
	move.l	#0,%d2
	move.w	S(%a1),%d3
	cmp.w	#0x00,%d3
	beq	GET_BUF_Finish
	movea.l	OUT(%a1),%a2
	move.b	(%a2),%d1
	adda.l	#1,%a2
	lea.l	BOTTOM(%a1),%a3
	cmpa.l	%a3,%a2
	bcs	GET_BUF_STEP1
	lea.l	TOP(%a1),%a2
GET_BUF_STEP1:
	move.l	%a2,OUT(%a1)
	sub.w	#1,%d3
	move.w	%d3,S(%a1)
	move.l	#1,%d2
GET_BUF_Finish:	
	move.l	%d2,%d0
	rts

*****************************************
** (以下、変更なし)
*****************************************
INTERPUT:
	move.l %d0,-(%sp)		/* 修正: D/A 分離 */
	movem.l	 %a0-%a2,-(%sp)
	ori.w #0x0700,%SR
	cmp.l #0,%d1
	bne END_OF_INTERPUT
	move.l #1,%d0
	jsr OUTQ
	cmp.l #0,%d0			
	beq MASK
	move.l %d1,%d0		
	andi.l #0x000000ff, %d0	
	add.l #0x0800,%d0		
	move.w %d0,UTX1	
	bra END_OF_INTERPUT
MASK:
	move.w #0xe108,USTCNT1
END_OF_INTERPUT:	
	movem.l	(%sp)+, %a0-%a2
	move.l (%sp)+,%d0
	rts
*****************************************
* PUTSTRING
*****************************************
PUTSTRING:
	movem.l %d1-%d7,-(%sp)	/* 修正: D/A 分離 */
	movem.l %a0-%a6,-(%sp)
	move.l %d1, %d6 	
	move.l %d2, %a0 	
	move.l %d3, %d7 	
	move.l #0, %d5 		
	cmp.l #0, %d6
	bne .L_PUTSTRING_END
	cmp.l #0, %d7
	beq .L_PUTSTRING_UNMASK
.L_PUTSTRING_LOOP:
	cmp.l %d5, %d7
	beq .L_PUTSTRING_UNMASK
	move.l #1, %d0 		
	move.b (%a0), %d1 	
	jsr INQ 		
	cmp.l #0, %d0
	beq .L_PUTSTRING_UNMASK
	addq.l #1, %d5 		
	addq.l #1, %a0 		
	bra .L_PUTSTRING_LOOP
.L_PUTSTRING_UNMASK:
	move.w #0xe10c,USTCNT1
.L_PUTSTRING_END:
	move.l %d5, %d0
	movem.l (%sp)+, %a0-%a6
	movem.l (%sp)+, %d1-%d7
	rts
*----------------------------------------------------------------------
* INTERGET
*----------------------------------------------------------------------
INTERGET:
	movem.l	%d0-%d1,-(%sp)			
	cmp.l	#0,%d1					
	bne	INTERGET_Finish
	move.l	#0,%d0					
	move.l	%d2,%d1
	jsr	INQ
INTERGET_Finish:
	movem.l	(%sp)+,%d0-%d1			
	rts
*----------------------------------------------------------------------
* RESET_TIMER
*----------------------------------------------------------------------
RESET_TIMER:
	move.l #TCTL1, %A0	
	andi.w #0xFFFE, (%A0)	
	move.l #IMR, %A0	
	ori.l #0x00000002, (%A0)
	move.w #0x0000, TSTAT1	
	rts
*----------------------------------------------------------------------
* SET_TIMER
*----------------------------------------------------------------------
SET_TIMER:
	move.l #TCTL1, %A0	
	andi.w #0xFFFE, (%A0)	
	lea.l task_p, %A0	
	move.l %D2, (%A0)	
	move.w #206, TPRER1	
	move.w %D1, TCMP1	
	move.w #0x0000, TSTAT1	
	move.l #IMR, %A0	
	andi.l #0xFFFFFFFD, (%A0)
	move.w #0x0015, TCTL1	
	rts
*----------------------------------------------------------------------
* CALL_RP
*----------------------------------------------------------------------
CALL_RP:
	lea.l task_p, %A0	
	move.l (%A0), %A0	
	jsr (%A0)		
	rts
*----------------------------------------------------------------------
* timer1_interrupt
*----------------------------------------------------------------------
timer1_interrupt:
	movem.l %D0-%d7, -(%SP)	/* 修正: D/A 分離 */
	movem.l %a0-%a6, -(%SP)
	move.w TSTAT1, %D0	
	andi.w #0x0001, %d0	
	beq .L_TIMER_EXIT	
	move.w #0x0000, TSTAT1	
	jsr CALL_RP		
.L_TIMER_EXIT:
	movem.l (%sp)+, %a0-%a6
	movem.l (%sp)+, %D0-%d7
	rte			
.end
