#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "mtk_c.h"
#include <fcntl.h>

/* --- 定数定義 --- */
#define PHASE_SETUP     0
#define PHASE_PC_TURN   1
#define PHASE_EXT_TURN  2
#define PHASE_GAMEOVER  3

/* --- グローバル変数 (共有資源) --- */
FILE* com0in; 
FILE* com0out;
FILE* com1in;
FILE* com1out;

/* ゲーム状態管理 */
volatile int game_phase = PHASE_SETUP;
char secret_pc[16];   /* PC側の秘密の数字 */
char secret_ext[16];  /* EXT側の秘密の数字 */
volatile int setup_pc_done = 0;
volatile int setup_ext_done = 0;

/* --- fcntl ダミー実装 --- */
int fcntl(int fd, int cmd, ...){
    return cmd == F_GETFL ? O_RDWR : 0;
}

/* --- ヘルパー関数: HitとBlowを計算 --- */
void check_hit_blow(const char* target, const char* guess, int* h, int* b) {
    int i, j;
    *h = 0;
    *b = 0;
    for (i = 0; i < 3; i++) {
        if (guess[i] == target[i]) {
            (*h)++;
        } else {
            for (j = 0; j < 3; j++) {
                if (i != j && guess[i] == target[j]) {
                    (*b)++;
                    break;
                }
            }
        }
    }
}

/* --- ヘルパー関数: 入力チェック --- */
int is_valid_input(const char* str) {
    if (strlen(str) != 3) return 0;
    for(int i=0; i<3; i++) {
        if (!isdigit(str[i])) return 0;
    }
    return 1;
}

/******************************************************************
** タスク1: PC (UART0) 制御
******************************************************************/
void task_pc(){
    /* staticにしてスタック操作の影響を受けないようにする */
    static char buf[16];
    static int h, b;
    unsigned long sp_save; /* スタックポインタ保存用 */

    /* --- 設定フェーズ --- */
    fprintf(com0out, "Please enter a 3-digit number.\n");
    
    while(1) {
        fscanf(com0in, "%15s", buf);
        if (is_valid_input(buf)) {
            strcpy(secret_pc, buf);
            break;
        } else {
            fprintf(com0out, "Invalid input. Please enter 3 digits.\n");
        }
    }

    setup_pc_done = 1;
    fprintf(com0out, "One moment, please.\n");

    while (!setup_ext_done) {
        swtch();
    }

    fprintf(com0out, "START\n");
    
    game_phase = PHASE_PC_TURN;

    /* ★ここで現在のスタックポインタ(SP)を保存 */
    __asm__ volatile ("move.l %sp, %0" : "=r" (sp_save));

    /* --- 対戦フェーズ --- */
    while(1){
        if (game_phase == PHASE_PC_TURN) {
            fprintf(com0out, "\n[YOUR TURN] Enter 3 digits: ");
            fscanf(com0in, "%15s", buf);

            if (is_valid_input(buf)) {
                check_hit_blow(secret_ext, buf, &h, &b);
                
                fprintf(com0out, "Result: %d Hit, %d Blow\n", h, b);
                fprintf(com1out, "\nOpponent Guessed: %s -> %d Hit, %d Blow\n", buf, h, b);

                if (h == 3) {
                    fprintf(com0out, "3 Hit You Win !!\n");
                    fprintf(com1out, "3 Hit You Lose\n");
                    game_phase = PHASE_GAMEOVER;
                } else {
                    game_phase = PHASE_EXT_TURN;
                }
            } else {
                fprintf(com0out, "Invalid input.\n");
            }
        }
        else if (game_phase == PHASE_GAMEOVER) {
            swtch();
        }
        else {
            swtch();
        }

        /* ★ループの末尾でスタックポインタを強制的に巻き戻す */
        /* これにより、ループ内で蓄積したゴミデータが全て破棄される */
        __asm__ volatile ("move.l %0, %sp" : : "r" (sp_save));
    }
}

/******************************************************************
** タスク2: EXT (UART1) 制御
******************************************************************/
void task_ext(){
    /* staticにしてスタック操作の影響を受けないようにする */
    static char buf[16];
    static int h, b;
    unsigned long sp_save; /* スタックポインタ保存用 */

    /* --- 設定フェーズ --- */
    fprintf(com1out, "Please enter a 3-digit number.\n");

    while(1) {
        fscanf(com1in, "%15s", buf);
        if (is_valid_input(buf)) {
            strcpy(secret_ext, buf);
            break;
        } else {
            fprintf(com1out, "Invalid input. Please enter 3 digits.\n");
        }
    }

    setup_ext_done = 1;
    fprintf(com1out, "One moment, please.\n");

    while (!setup_pc_done) {
        swtch();
    }

    fprintf(com1out, "START\n");

    /* ★ここで現在のスタックポインタ(SP)を保存 */
    __asm__ volatile ("move.l %sp, %0" : "=r" (sp_save));

    /* --- 対戦フェーズ --- */
    while(1){
        if (game_phase == PHASE_EXT_TURN) {
            fprintf(com1out, "\n[YOUR TURN] Enter 3 digits: ");
            fscanf(com1in, "%15s", buf);

            if (is_valid_input(buf)) {
                check_hit_blow(secret_pc, buf, &h, &b);
                
                fprintf(com1out, "Result: %d Hit, %d Blow\n", h, b);
                fprintf(com0out, "\nOpponent Guessed: %s -> %d Hit, %d Blow\n", buf, h, b);

                if (h == 3) {
                    fprintf(com1out, "3 Hit You Win !!\n");
                    fprintf(com0out, "3 Hit You Lose\n");
                    game_phase = PHASE_GAMEOVER;
                } else {
                    game_phase = PHASE_PC_TURN;
                }
            } else {
                fprintf(com1out, "Invalid input.\n");
            }
        }
        else if (game_phase == PHASE_GAMEOVER) {
            swtch();
        }
        else {
            swtch();
        }

        /* ★ループの末尾でスタックポインタを強制的に巻き戻す */
        __asm__ volatile ("move.l %0, %sp" : : "r" (sp_save));
    }
}

/******************************************************************
** メイン関数
******************************************************************/
int main(void){
    com0in  = fdopen(3, "r");
    com0out = fdopen(3, "w");
    com1in  = fdopen(4, "r");
    com1out = fdopen(4, "w");
    
    init_kernel();

    set_task(task_pc);
    set_task(task_ext);

    begin_sch();
    return 0;
}
