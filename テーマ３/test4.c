#include <stdio.h>
#include "mtk_c.h"
#include <fcntl.h>

/* グローバル変数としてファイルポインタを定義し、全タスクで共有する */
FILE* com0in; 
FILE* com0out;
FILE* com1in;
FILE* com1out;

/* 既存の fcntl 実装 */
int fcntl(int fd, int cmd, ...){
    return cmd == F_GETFL ? O_RDWR : 0;
}

/******************************************************************
** タスク1: PC (UART0) -> EXT (UART1) への転送
******************************************************************/
void task_pc_to_ext(){
    char key_in;
    while(1){
        /* PCからの入力を1文字読み込む */
        /* csys68kの実装により、入力があるまでブロックされるが、
           割り込み(hard_clock)によりコンテキストスイッチが行われる前提 */
        if(fscanf(com0in, "%c", &key_in) != EOF) {
            /* EXTへ出力する */
            fprintf(com1out, "%c", key_in);
        }
    }
}

/******************************************************************
** タスク2: EXT (UART1) -> PC (UART0) への転送
******************************************************************/
void task_ext_to_pc(){
    char key_in;
    while(1){
        /* EXTからの入力を1文字読み込む */
        if(fscanf(com1in, "%c", &key_in) != EOF) {
            /* PCへ出力する */
            fprintf(com0out, "%c", key_in);
        }
    }
}

/******************************************************************
** メイン関数
******************************************************************/
int main(void){
    /* ファイルオープンの初期化 */
    /* fd=3: UART0 (Standard I/O), fd=4: UART1 (External) */
    com0in  = fdopen(3, "r");
    com0out = fdopen(3, "w");
    com1in  = fdopen(4, "r");
    com1out = fdopen(4, "w");
    
    /* カーネルの初期化 */
    init_kernel();

    /* タスクの登録 */
    set_task(task_pc_to_ext);
    set_task(task_ext_to_pc);

    /* スケジューリング開始 */
    /* ここで制御がカーネルに移り、登録されたタスクが並行動作を開始する */
    begin_sch();

    return 0;
}
