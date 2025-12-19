#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "mtk_c.h"
#include <fcntl.h>

/* --- 修正: swtch関数のプロトタイプ宣言を追加 --- */
extern void swtch(void);

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

/* 共有バッファ */
char shared_buf[256];

/* ゲーム状態管理 */
volatile int game_phase = PHASE_SETUP;
char secret_pc[16];
char secret_ext[16];
volatile int setup_pc_done = 0;
volatile int setup_ext_done = 0;

/* --- fcntl ダミー実装 --- */
int fcntl(int fd, int cmd, ...){
    return cmd == F_GETFL ? O_RDWR : 0;
}

/* --- ヘルパー: Hit/Blow計算 --- */
void check_hit_blow(const char* target, const char* guess, int* h, int* b) {
    int i, j;
    *h = 0; *b = 0;
    for (i = 0; i < 3; i++) {
        if (guess[i] == target[i]) (*h)++;
        else {
            for (j = 0; j < 3; j++) {
                if (i != j && guess[i] == target[j]) { (*b)++; break; }
            }
        }
    }
}

/* --- ヘルパー: 入力チェック --- */
int is_valid_input(const char* str) {
    if (strlen(str) != 3) return 0;
    /* 修正: isdigit には unsigned char を渡す (警告対策) */
    for(int i=0; i<3; i++) if (!isdigit((unsigned char)str[i])) return 0;
    return 1;
}

/* セマフォを使った安全な出力関数 */
void safe_print(FILE* fp, const char* msg) {
    P(SEM_IO); 
    fprintf(fp, "%s", msg);
    V(SEM_IO);
}

/******************************************************************
** タスク1: PC (UART0)
******************************************************************/
void task_pc(){
    static char in_buf[16];
    static int h, b;
    unsigned long sp_save;

    P(SEM_IO); fprintf(com0out, "Please enter a 3-digit number.\n"); V(SEM_IO);
    
    while(1) {
        fscanf(com0in, "%15s", in_buf);
        if (is_valid_input(in_buf)) {
            strcpy(secret_pc, in_buf);
            break;
        } else {
            P(SEM_IO); fprintf(com0out, "Invalid input.\n"); V(SEM_IO);
        }
    }

    setup_pc_done = 1;
    P(SEM_IO); fprintf(com0out, "One moment, please.\n"); V(SEM_IO);

    while (!setup_ext_done) swtch();

    P(SEM_IO); fprintf(com0out, "START\n"); V(SEM_IO);
    game_phase = PHASE_PC_TURN;

    /* 修正: %sp -> %%sp (GCCインラインアセンブラのエスケープ) */
    __asm__ volatile ("move.l %%sp, %0" : "=r" (sp_save)); 

    while(1){
        if (game_phase == PHASE_PC_TURN) {
            P(SEM_IO); fprintf(com0out, "\n[YOUR TURN] Enter 3 digits: "); V(SEM_IO);
            fscanf(com0in, "%15s", in_buf);

            if (is_valid_input(in_buf)) {
                check_hit_blow(secret_ext, in_buf, &h, &b);
                
                P(SEM_IO);
                sprintf(shared_buf, "Result: %d Hit, %d Blow\n", h, b);
                fprintf(com0out, "%s", shared_buf);
                
                sprintf(shared_buf, "\nOpponent Guessed: %s -> %d Hit, %d Blow\n", in_buf, h, b);
                fprintf(com1out, "%s", shared_buf);
                V(SEM_IO);

                if (h == 3) {
                    P(SEM_IO);
                    fprintf(com0out, "3 Hit You Win !!\n");
                    fprintf(com1out, "3 Hit You Lose\n");
                    V(SEM_IO);
                    game_phase = PHASE_GAMEOVER;
                } else {
                    game_phase = PHASE_EXT_TURN;
                }
            } else {
                P(SEM_IO); fprintf(com0out, "Invalid input.\n"); V(SEM_IO);
            }
        }
        else {
            swtch();
        }
        /* 修正: %sp -> %%sp */
        __asm__ volatile ("move.l %0, %%sp" : : "r" (sp_save));
    }
}

/******************************************************************
** タスク2: EXT (UART1)
******************************************************************/
void task_ext(){
    static char in_buf[16];
    static int h, b;
    unsigned long sp_save;

    P(SEM_IO); fprintf(com1out, "Please enter a 3-digit number.\n"); V(SEM_IO);

    while(1) {
        fscanf(com1in, "%15s", in_buf);
        if (is_valid_input(in_buf)) {
            strcpy(secret_ext, in_buf);
            break;
        } else {
            P(SEM_IO); fprintf(com1out, "Invalid input.\n"); V(SEM_IO);
        }
    }

    setup_ext_done = 1;
    P(SEM_IO); fprintf(com1out, "One moment, please.\n"); V(SEM_IO);

    while (!setup_pc_done) swtch();

    P(SEM_IO); fprintf(com1out, "START\n"); V(SEM_IO);

    /* 修正: %sp -> %%sp */
    __asm__ volatile ("move.l %%sp, %0" : "=r" (sp_save));

    while(1){
        if (game_phase == PHASE_EXT_TURN) {
            P(SEM_IO); fprintf(com1out, "\n[YOUR TURN] Enter 3 digits: "); V(SEM_IO);
            fscanf(com1in, "%15s", in_buf);

            if (is_valid_input(in_buf)) {
                check_hit_blow(secret_pc, in_buf, &h, &b);
                
                P(SEM_IO);
                sprintf(shared_buf, "Result: %d Hit, %d Blow\n", h, b);
                fprintf(com1out, "%s", shared_buf);
                
                sprintf(shared_buf, "\nOpponent Guessed: %s -> %d Hit, %d Blow\n", in_buf, h, b);
                fprintf(com0out, "%s", shared_buf);
                V(SEM_IO);

                if (h == 3) {
                    P(SEM_IO);
                    fprintf(com1out, "3 Hit You Win !!\n");
                    fprintf(com0out, "3 Hit You Lose\n");
                    V(SEM_IO);
                    game_phase = PHASE_GAMEOVER;
                } else {
                    game_phase = PHASE_PC_TURN;
                }
            } else {
                P(SEM_IO); fprintf(com1out, "Invalid input.\n"); V(SEM_IO);
            }
        }
        else {
            swtch();
        }
        /* 修正: %sp -> %%sp */
        __asm__ volatile ("move.l %0, %%sp" : : "r" (sp_save));
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
