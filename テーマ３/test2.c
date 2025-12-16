#include "mtk_c.h"
#include <stdio.h>
#include <stdlib.h>

/* 【追加】ユーザタスクのプロトタイプ宣言 */
extern void task1();
extern void task2();
extern void task3();

/* 外部関数宣言: ユーザ定義 exit() (PDF 1.4.6節) */
extern void exit(int value);

/* ユーザタスクが使用するセマフォIDの再定義 (user_tasks.cと合わせる) */
#define SEM_TASK_A 4
#define SEM_TASK_B 5

/* ユーザ定義 exit() によるプログラム停止措置 (PDF 1.4.6節) */
void exit(int value) {
    *(char *) 0x00d00039 = 'H'; /* LED0への表示 (HALT) */
    for (;;);                   /* 無限ループトラップで停止させる */
}

void main() {
    
    printf("--- Kernel Initialization Start ---\n");
    
    /* 1. カーネルの初期化 */
    init_kernel();
    
    /* 2. セマフォの初期状態の調整 */
    // タスク1がP(A)で開始されるように、セマフォAの初期値を0に設定
    semaphore[SEM_TASK_A].count = 0; // タスク1を休眠状態で開始
    // タスク2がP(B)で開始されるように、セマフォBの初期値を0に設定
    semaphore[SEM_TASK_B].count = 0; // タスク2を休眠状態で開始
    
    /* 3. ユーザタスクの登録 */
    printf("Setting up tasks...\n");
    set_task(task1);
    set_task(task2);
    set_task(task3);

    printf("Total tasks registered: %d\n", NUMTASK);
    
    printf("--- Begin Scheduling ---\n");
    
    /* 4. マルチタスク処理の開始（ここからは戻らない）*/
    begin_sch();
    
    // ここには到達しないはず
    printf("Scheduler failed to start.\n");
}
