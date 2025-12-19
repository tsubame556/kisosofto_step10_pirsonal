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
    char buf[16];
    int h, b;

    /* --- 設定フェーズ --- */
    fprintf(com0out, "Please enter a 3-digit number.\n");
    
    /* 有効な入力があるまで繰り返す */
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

    /* 相手の入力完了を待つ (ビジーループ回避のためswtchを入れる) */
    while (!setup_ext_done) {
        swtch();
    }

    /* 同時にSTART表示 */
    fprintf(com0out, "START\n");
    
    /* 先攻なのでフェーズを進める */
    game_phase = PHASE_PC_TURN;

    /* --- 対戦フェーズ --- */
    while(1){
        if (game_phase == PHASE_PC_TURN) {
            fprintf(com0out, "\n[YOUR TURN] Enter 3 digits: ");
            fscanf(com0in, "%15s", buf);

            if (is_valid_input(buf)) {
                /* 判定 */
                check_hit_blow(secret_ext, buf, &h, &b);
                
                /* 結果表示 */
                fprintf(com0out, "Result: %d Hit, %d Blow\n", h, b);
                fprintf(com1out, "\nOpponent Guessed: %s -> %d Hit, %d Blow\n", buf, h, b);

                if (h == 3) {
                    /* 勝利条件 */
                    fprintf(com0out, "3 Hit You Win !!\n");
                    fprintf(com1out, "3 Hit You Lose\n");
                    game_phase = PHASE_GAMEOVER;
                } else {
                    /* ターン交代 */
                    game_phase = PHASE_EXT_TURN;
                }
            } else {
                fprintf(com0out, "Invalid input.\n");
            }
        }
        else if (game_phase == PHASE_GAMEOVER) {
            /* ゲーム終了時の待機 (必要ならリセット処理を実装) */
            swtch();
        }
        else {
            /* 相手のターン中はCPUを譲る */
            swtch();
        }
    }
}

/******************************************************************
** タスク2: EXT (UART1) 制御
******************************************************************/
void task_ext(){
    char buf[16];
    int h, b;

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

    /* 相手の入力完了を待つ */
    while (!setup_pc_done) {
        swtch();
    }

    /* 同時にSTART表示 */
    fprintf(com1out, "START\n");

    /* --- 対戦フェーズ --- */
    while(1){
        if (game_phase == PHASE_EXT_TURN) {
            fprintf(com1out, "\n[YOUR TURN] Enter 3 digits: ");
            fscanf(com1in, "%15s", buf);

            if (is_valid_input(buf)) {
                /* 判定 */
                check_hit_blow(secret_pc, buf, &h, &b);
                
                /* 結果表示 */
                fprintf(com1out, "Result: %d Hit, %d Blow\n", h, b);
                fprintf(com0out, "\nOpponent Guessed: %s -> %d Hit, %d Blow\n", buf, h, b);

                if (h == 3) {
                    /* 勝利条件 */
                    fprintf(com1out, "3 Hit You Win !!\n");
                    fprintf(com0out, "3 Hit You Lose\n");
                    game_phase = PHASE_GAMEOVER;
                } else {
                    /* ターン交代 */
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
            /* 相手のターン中はCPUを譲る */
            swtch();
        }
    }
}

/******************************************************************
** メイン関数
******************************************************************/
int main(void){
    /* ファイルオープン (fd3=UART0, fd4=UART1) */
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
