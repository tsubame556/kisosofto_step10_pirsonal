#include "mtk_c.h"
#include <stdio.h>
#include <unistd.h> // for sleep/usleep simulation

/* ユーザタスクが使用するセマフォID (mtk_c.hで定義されたNUMSEMAPHORE=7を前提) */
#define SEM_TASK_A 4 // 応用タスク用セマフォ0
#define SEM_TASK_B 5 // 応用タスク用セマフォ1

/* タスク1: セマフォAをP/V操作し、タスク2に制御を渡す（協調的マルチタスク風）*/
void task1() {
    int i = 0;
    // 最初にP(A)は行わない。task1はreadyキューから開始され、T2のV(A)を待つ。

    while(1) {
        // T1が実行中であることを表示
        printf("Task 1: Running (%d)\n", i++);

        // セマフォBをVする (タスク2をreadyキューに戻す)
        V(SEM_TASK_B);
        
        // セマフォAをPする (タスク1は休眠し、タスクスイッチが発生)
        printf("Task 1: P(A) -> Sleep\n");
        P(SEM_TASK_A); 

        // ここに戻ってきたらセマフォAをタスク2からVされたことを意味する
        printf("Task 1: Woken up (A)\n");
        
        // 短いループで時間消費（タイマ割り込みをシミュレーション）
        for (int j = 0; j < 50000; j++); 
    }
}


/* タスク2: セマフォBをP/V操作し、タスク1に制御を渡す */
void task2() {
    int k = 0;

    while(1) {
        // T2が実行中であることを表示
        printf("Task 2: Running (%d)\n", k++);

        // セマフォAをVする (タスク1をreadyキューに戻す)
        V(SEM_TASK_A);
        
        // セマフォBをPする (タスク2は休眠し、タスクスイッチが発生)
        printf("Task 2: P(B) -> Sleep\n");
        P(SEM_TASK_B); 
        
        // ここに戻ってきたらセマフォBをタスク1からVされたことを意味する
        printf("Task 2: Woken up (B)\n");
        
        // 短いループで時間消費（タイマ割り込みをシミュレーション）
        for (int j = 0; j < 50000; j++); 
    }
}

/* タスク3: 単純な無限ループ（タイマ割り込み確認用） */
void task3() {
    int m = 0;
    while(1) {
        printf("Task 3: Running loop (%d)\n", m++);
        for (int j = 0; j < 100000; j++); // 比較的長い時間実行し、タイマ割り込みによる切り替えを期待
    }
}
