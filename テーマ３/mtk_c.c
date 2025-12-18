#include <stdio.h>
#include "mtk_c.h"

/* --- タスク状態の定義 --- */
/* mtk_c.h で定義されていない場合に備え、ここで明示的に定義する */
#ifndef UNDEFINED
#define UNDEFINED 0
#endif
#ifndef OCCUPIED
#define OCCUPIED 1
#endif
#ifndef FINISHED
#define FINISHED 2
#endif

/* --- 外部関数宣言（アセンブラルーチン） --- */
extern void pv_handler();
extern void first_task();
extern void swtch();
extern void init_timer();

/* --- 内部関数プロトタイプ宣言 --- */
/* コンパイル警告（implicit declaration）を防ぐために必要 */
void sleep(int ch);
void wakeup(int ch);
void *init_stack(TASK_ID_TYPE id);

/* --- グローバル変数定義 --- */
SEMAPHORE_TYPE 	semaphore[NUMSEMAPHORE];
TCB_TYPE 	    task_tab[NUMTASK + 1];
STACK_TYPE	    stacks[NUMTASK];

TASK_ID_TYPE	curr_task;
TASK_ID_TYPE	new_task;
TASK_ID_TYPE	next_task;
TASK_ID_TYPE	ready;

/******************************************************************
** カーネルの初期化: init_kernel()
******************************************************************/
void init_kernel(){
    int i;
    
    for(i = 0; i < NUMTASK + 1; i++){
        task_tab[i].task_addr = NULL;
        task_tab[i].stack_ptr = NULL;
        task_tab[i].priority = 0;
        task_tab[i].status = UNDEFINED;
        task_tab[i].next = NULLTASKID;							
    }

    ready = NULLTASKID;

    /* TRAP #1 割り込みベクタ(0x0084)へ登録 */
    *(int*) 0x0084 = (int)pv_handler;

    for(i = 0; i < NUMSEMAPHORE; i++){
        semaphore[i].count = 1;
        semaphore[i].task_list = NULLTASKID;
    }
}

/******************************************************************
** ユーザタスクの登録: set_task()
******************************************************************/
void set_task(void (*usertask_ptr)()){
    TASK_ID_TYPE i;
    
    for(i = 1; i < NUMTASK + 1; i++){
        if((task_tab[i].status == UNDEFINED) || (task_tab[i].status == FINISHED)){
            new_task = i;
            task_tab[i].task_addr = usertask_ptr;
            task_tab[i].status = OCCUPIED;
            task_tab[i].stack_ptr = init_stack(new_task);
            addq(&ready, new_task);
            break;
        }
    }
}

/******************************************************************
** ユーザタスク用のスタックの初期化: init_stack()
******************************************************************/
void *init_stack(TASK_ID_TYPE id){
    /* スタック成長方向(高番地から低番地)を考慮し、4バイト境界に調整 */
    unsigned long stack_ptr = (unsigned long)&stacks[id-1].sstack[STKSIZE];
    int *ssp = (int *)(stack_ptr & ~3L); 

    /* 1. Initial PC (4byte): ポインタをintにキャストして警告回避 */
    *(--ssp) = (int)task_tab[id].task_addr;

    /* 2. Initial SR (2byte): 型変換を用いて安全にプッシュ */
    unsigned short *short_ssp = (unsigned short *)ssp;
    *(--short_ssp) = 0x2000; /* スーパーバイザモード、割り込み許可 */

    /* 3. レジスタ保存領域 (15個のlong) を確保 */
    ssp = (int *)short_ssp;
    ssp -= 15;

    /* 4. Initial USP (4byte): 型変換の警告を回避 */
    *(--ssp) = (int)&stacks[id-1].ustack[STKSIZE];

    return (void *)ssp;
}

/******************************************************************
** スケジューラの開始: begin_sch()
******************************************************************/
void begin_sch(){
    curr_task = removeq(&ready);
    init_timer();
    first_task();
}

/* --- キュー操作関数群 --- */
void addq(TASK_ID_TYPE *que_ptr, TASK_ID_TYPE id){
    if(*que_ptr == NULLTASKID){
        *que_ptr = id;
    } else {
        TCB_TYPE *task_ptr = &task_tab[*que_ptr];
        while(task_ptr->next != NULLTASKID){
            task_ptr = &task_tab[task_ptr->next];
        }
        task_ptr->next = id;
    }
}

TASK_ID_TYPE removeq(TASK_ID_TYPE *que_ptr){
    TASK_ID_TYPE r_id = *que_ptr;
    if(r_id != NULLTASKID){
        *que_ptr = task_tab[r_id].next;
        task_tab[r_id].next = NULLTASKID;
    }
    return r_id;
}

void sched(){
    next_task = removeq(&ready);
    if(next_task == NULLTASKID){
        while(1); /* アイドル状態の無限ループ */
    }
}

/* --- セマフォ操作ボディ --- */
void p_body(TASK_ID_TYPE s_id){
    semaphore[s_id].count--;
    if(semaphore[s_id].count < 0){
        sleep(s_id);
    }
}

void v_body(TASK_ID_TYPE s_id){
    semaphore[s_id].count++;
    if(semaphore[s_id].count <= 0){
        wakeup(s_id);
    }
}

void sleep(int ch){
    addq(&semaphore[ch].task_list, curr_task);
    sched();
    swtch();
}

void wakeup(int ch){
    TASK_ID_TYPE wakeup_id = removeq(&semaphore[ch].task_list);
    if(wakeup_id != NULLTASKID){
        addq(&ready, wakeup_id);
    }
}
