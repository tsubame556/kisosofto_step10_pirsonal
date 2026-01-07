.include "equdefs.inc"
.section .text

/* --- グローバルシンボル定義 --- */
.global swtch
.global pv_handler
.global init_timer
.global first_task
.global hard_clock

/* C言語から呼ばれるシステムコールラッパー */
/* 小文字(p, v, set_sem)で定義することでリンクエラーを解消 */
.global p
.global v
.global set_sem

/* --- 外部シンボル参照 --- */
.extern p_body
.extern v_body
.extern task_tab
.extern curr_task
.extern next_task
.extern addq
.extern sched
.extern ready
.extern semaphore  /* set_semで直接値を書き換えるために参照 */


/* =========================================================
   システムコール ラッパー関数 (C言語呼び出し用)
   ========================================================= */

/* void p(int sem_id) */
.text
.even
p:
    movem.l %d1-%d2/%a1,-(%sp)  | レジスタ退避
    move.l  #0, %d0             | d0 = 0 (p_body呼び出し用ID)
    
    /* 引数 sem_id の取得 */
    /* スタック: [d1,d2,a1(12byte)] [RetAddr(4byte)] [Arg1(4byte)] */
    movea.l %sp, %a1
    move.l  #16, %d2
    adda.l  %d2, %a1
    move.l  (%a1), %d1          | d1 = sem_id

    trap    #1                  | pv_handler 呼び出し
    movem.l (%sp)+, %d1-%d2/%a1 | レジスタ復帰
    rts

/* void v(int sem_id) */
.text
.even
v:
    movem.l %d1-%d2/%a1,-(%sp)  | レジスタ退避
    move.l  #1, %d0             | d0 = 1 (v_body呼び出し用ID)
    
    /* 引数 sem_id の取得 */
    movea.l %sp, %a1
    move.l  #16, %d2
    adda.l  %d2, %a1
    move.l  (%a1), %d1          | d1 = sem_id

    trap    #1
    movem.l (%sp)+, %d1-%d2/%a1 | レジスタ復帰
    rts

/* void set_sem(int sem_id, int value) */
.text
.even
set_sem:
    movem.l %d1-%d2/%a1,-(%sp)  | レジスタ退避
    move.l  #2, %d0             | d0 = 2 (set_sem呼び出し用ID)

    /* 引数の取得 */
    /* スタック: [regs(12)] [Ret(4)] [Arg1(4)] [Arg2(4)] */
    movea.l %sp, %a1
    move.l  #16, %d2
    adda.l  %d2, %a1
    move.l  (%a1), %d1          | d1 = sem_id
    move.l  4(%a1), %d2         | d2 = value

    trap    #1
    movem.l (%sp)+, %d1-%d2/%a1 | レジスタ復帰
    rts


/* =========================================================
   TRAP #1 ハンドラ (セマフォ操作)
   ========================================================= */
.text
.even
pv_handler:
    move.w  %SR, -(%sp)     | 現走行レベルの退避
    movem.l %d0/%a0, -(%sp) | 作業用レジスタ退避
    move.w  #0x2700, %SR    | 割り込み禁止 (レベル7)

    /* d0の値で分岐 */
    cmp.l   #0, %d0
    beq     SYSCALL_p
    cmp.l   #1, %d0
    beq     SYSCALL_v
    cmp.l   #2, %d0         | d0=2 なら set_sem へ
    beq     SYSCALL_set
    bra     pv_FINISH       | 不正な番号なら終了

SYSCALL_p:
    move.l  #p_body, %d0
    bra     JUMP_pv

SYSCALL_v:
    move.l  #v_body, %d0
    bra     JUMP_pv

SYSCALL_set:
    /* セマフォの値を直接書き換える処理 */
    /* semaphore[d1].count = d2 */
    lea     semaphore, %a0  | a0 = &semaphore[0]
    lsl.l   #3, %d1         | d1 = id * 8 (構造体サイズ8byteと仮定)
    adda.l  %d1, %a0        | a0 = &semaphore[id]
    move.l  %d2, (%a0)      | countメンバ(offset 0) に値を格納
    bra     pv_FINISH

JUMP_pv:
    movea.l %d0, %a0
    move.l  %d1, -(%sp)     | 引数(sem_id)をスタックに積む
    jsr     (%a0)           | p_body or v_body 呼び出し
    addq.l  #4, %sp         | 引数除去

pv_FINISH:
    movem.l (%sp)+, %d0/%a0 | レジスタ復帰
    move.w  (%sp)+, %SR     | 旧走行レベル回復
    rte


/* =========================================================
   コンテキストスイッチ関連
   ========================================================= */
swtch:
    /* 1. SR退避 (RTE用) */
    move.w  %sr, -(%sp)

    /* 2. 実行中タスクのレジスタ退避 */
    movem.l %d0-%d7/%a0-%a6, -(%sp)
    move.l  %USP, %a6
    move.l  %a6, -(%sp)

    /* 3. SSPの保存 */
    move.l  #0, %d0
    move.l  curr_task, %d0
    lea.l   task_tab, %a0
    mulu    #20, %d0        | TCBサイズ20byteと仮定
    adda.l  %d0, %a0
    addq.l  #4, %a0         | stack_ptrへのオフセット
    move.l  %sp, (%a0)

    /* 4. curr_taskを変更 */
    lea.l   curr_task, %a1
    move.l  next_task, (%a1)

    /* 5. 次のタスクのSSP読み出し */
    move.l  curr_task, %d0
    lea.l   task_tab, %a0
    mulu    #20, %d0
    adda.l  %d0, %a0
    addq.l  #4, %a0
    move.l  (%a0), %sp

    /* 6. 次のタスクのレジスタ復帰 */
    move.l  (%sp)+, %a6
    move.l  %a6, %USP
    movem.l (%sp)+, %d0-%d7/%a0-%a6

    /* 7. タスク切り替え */
    rte

first_task:
    /* 1. TCB先頭番地の計算 */
    move.l  #0, %d1
    move.l  curr_task, %d1
    lea.l   task_tab, %a0
    mulu    #20, %d1
    adda.l  %d1, %a0

    /* 2. SSP, USPの回復 */
    addq.l  #4, %a0
    move.l  (%a0), %sp
    move.l  (%sp)+, %a6
    move.l  %a6, %USP

    /* 3. 残りの全レジスタ回復 */
    movem.l (%sp)+, %d0-%d7/%a0-%a6

    /* 4. ユーザタスク起動 */
    move.b  #'8', LED7
    rte


/* =========================================================
   タイマー関連
   ========================================================= */
init_timer:
    movem.l %d0-%d2, -(%sp)

    move.l  #SYSCALL_NUM_RESET_TIMER, %d0  | 3
    trap    #0

    move.l  #SYSCALL_NUM_SET_TIMER, %d0    | 4
    move.w  #10000, %d1                    | 10ms (100Hz)
    move.l  #hard_clock, %d2
    trap    #0

    movem.l (%sp)+, %d0-%d2
    rts

hard_clock:
    /* 1. レジスタ退避 */
    movem.l %d0-%d1/%a1, -(%sp)

    /* モードチェック (スーパーバイザなら切り替えない) */
    movea.l %sp, %a1
    move.l  #12, %d0        | 退避したレジスタ3つ分(12byte)
    adda.l  %d0, %a1        | a1 = スタック上のSRの位置
    move.w  (%a1), %d1
    andi.w  #0x2000, %d1
    cmpi.w  #0x2000, %d1    | Sビットチェック
    beq     hard_clock_end

    /* 2. addq(&ready, curr_task) */
    move.l  curr_task, -(%sp)
    move.l  #ready, -(%sp)
    jsr     addq
    add.l   #8, %sp

    /* 3. sched() */
    jsr     sched

    /* 4. swtch() */
    jsr     swtch

hard_clock_end:
    /* 5. レジスタ復帰 */
    movem.l (%sp)+, %d0-%d1/%a1
    rts
