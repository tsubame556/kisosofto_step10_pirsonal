#include <stdio.h>
#include "mtk_c.h"

/* --- タスク状態の定義 --- */
#ifndef UNDEFINED
#define UNDEFINED 0
#endif
#ifndef OCCUPIED
#define OCCUPIED 1
#endif
#ifndef FINISHED
#define FINISHED 2
#endif

/* --- 外部関数宣言 --- */
extern void pv_handler();
extern void first_task();
extern void swtch();
extern void init_timer();

/* --- 内部関数プロトタイプ --- */
void sleep(int ch);
void wakeup(int ch);
void *init_stack(TASK_ID_TYPE id);
void yield(void); /* プロトタイプ追加 */

/* --- グローバル変数 --- */
SEMAPHORE_TYPE  semaphore[NUMSEMAPHORE];
TCB_TYPE        task_tab[NUMTASK + 1];
STACK_TYPE      stacks[NUMTASK];

TASK_ID_TYPE    curr_task;
TASK_ID_TYPE    new_task;
TASK_ID_TYPE    next_task;
TASK_ID_TYPE    ready;

/******************************************************************
** カーネル初期化
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
    *(int*) 0x0084 = (int)pv_handler; /* TRAP #1 */

    for(i = 0; i < NUMSEMAPHORE; i++){
        semaphore[i].count = 1;
        semaphore[i].task_list = NULLTASKID;
    }
}

/******************************************************************
** タスク登録
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
** スタック初期化 (修正版: USPアライメント対応)
******************************************************************/
void *init_stack(TASK_ID_TYPE id){
    /* SSPのアライメント調整 */
    unsigned long stack_ptr = (unsigned long)&stacks[id-1].sstack[STKSIZE];
    int *ssp = (int *)(stack_ptr & ~3L); 

    /* 1. Initial PC */
    *(--ssp) = (int)task_tab[id].task_addr;

    /* 2. Initial SR (0x2000: Supervisor, Interrupt Enabled) */
    unsigned short *short_ssp = (unsigned short *)ssp;
    *(--short_ssp) = 0x2000;

    /* 3. レジスタ保存領域 (15個) */
    ssp = (int *)short_ssp;
    ssp -= 15;

    /* 4. Initial USP (修正: 4バイト境界に強制) */
    unsigned long usp_ptr = (unsigned long)&stacks[id-1].ustack[STKSIZE];
    *(--ssp) = (int)(usp_ptr & ~3L);

    return (void *)ssp;
}

/******************************************************************
** スケジューラ開始
******************************************************************/
void begin_sch(){
    curr_task = removeq(&ready);
    init_timer();
    first_task();
}

/* --- キュー操作 --- */
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
        /* タスクが尽きた場合は無限ループで停止 */
        while(1); 
    }
}

/* --- セマフォ --- */
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

/******************************************************************
** 自発的なタスク切り替え (新規追加)
******************************************************************/
void yield(void){
    /* 自分を待ち行列の最後尾に並べ直す */
    addq(&ready, curr_task);
    
    /* 次のタスクを決める */
    sched();
    
    /* コンテキスト切り替え */
    swtch();
}
