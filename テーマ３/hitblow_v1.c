#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdarg.h>
#include "mtk_c.h"
#include <fcntl.h>

/* --- 定数定義 --- */
#define PHASE_SETUP     0
#define PHASE_PC_TURN   1
#define PHASE_EXT_TURN  2
#define PHASE_GAMEOVER  3

#define UART0_FD 3
#define UART1_FD 4

/* --- グローバル変数 (共有資源) --- */
static FILE* com0 = NULL;  /* UART0: 読み書き兼用 */
static FILE* com1 = NULL;  /* UART1: 読み書き兼用 */

/* ゲーム状態管理 */
volatile int game_phase = PHASE_SETUP;
char secret_pc[16];   /* PC側の秘密の数字 */
char secret_ext[16];  /* EXT側の秘密の数字 */
volatile int setup_pc_done = 0;
volatile int setup_ext_done = 0;

/* --- fcntl ダミー実装（必要な環境向け） ---
   環境によっては libc が fcntl を要求するが実装が無いことがある。
   最低限、F_GETFL/F_SETFL を「それっぽく」通す。
*/
static int g_fd_flags[16];

int fcntl(int fd, int cmd, ...) {
    if (fd < 0 || fd >= (int)(sizeof(g_fd_flags) / sizeof(g_fd_flags[0]))) {
        return 0;
    }

    if (cmd == F_GETFL) {
        if (g_fd_flags[fd] == 0) g_fd_flags[fd] = O_RDWR;
        return g_fd_flags[fd];
    }

    if (cmd == F_SETFL) {
        va_list ap;
        int flags = 0;
        va_start(ap, cmd);
        flags = va_arg(ap, int);
        va_end(ap);
        g_fd_flags[fd] = flags;
        return 0;
    }

    return 0;
}

/* --- UART 出力（必ず flush） --- */
static void uart_printf(FILE* f, const char* fmt, ...) {
    if (!f) return;
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fflush(f);
}

/* --- ヘルパー関数: 末尾の改行除去 --- */
static void chomp_newline(char* s) {
    if (!s) return;
    size_t n = strlen(s);
    while (n > 0 && (s[n - 1] == '\n' || s[n - 1] == '\r')) {
        s[n - 1] = '\0';
        n--;
    }
}

/* --- ヘルパー関数: 1行読む（必要なら待つ） --- */
static int uart_readline(FILE* f, char* buf, size_t bufsz) {
    if (!f || !buf || bufsz == 0) return 0;

    while (1) {
        if (fgets(buf, (int)bufsz, f) != NULL) {
            chomp_newline(buf);
            return 1;
        }

        /* 何らかのエラー/一時的に読めない等を想定してクリアして譲る */
        clearerr(f);
        swtch();
    }
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
    if (!str) return 0;
    if (strlen(str) != 3) return 0;
    for (int i = 0; i < 3; i++) {
        if (!isdigit((unsigned char)str[i])) return 0;
    }
    return 1;
}

/******************************************************************
** タスク1: PC (UART0) 制御
******************************************************************/
void task_pc() {
    char buf[16];
    int h, b;

    /* --- 設定フェーズ --- */
    uart_printf(com0, "Please enter a 3-digit number.\n");

    /* 有効な入力があるまで繰り返す */
    while (1) {
        uart_readline(com0, buf, sizeof(buf));
        if (is_valid_input(buf)) {
            strcpy(secret_pc, buf);
            break;
        } else {
            uart_printf(com0, "Invalid input. Please enter 3 digits.\n");
        }
    }

    setup_pc_done = 1;
    uart_printf(com0, "One moment, please.\n");

    /* 相手の入力完了を待つ（CPUを譲る） */
    while (!setup_ext_done) {
        swtch();
    }

    /* 同時にSTART表示 */
    uart_printf(com0, "START\n");

    /* 先攻なのでフェーズを進める */
    game_phase = PHASE_PC_TURN;

    /* --- 対戦フェーズ --- */
    while (1) {
        if (game_phase == PHASE_PC_TURN) {
            uart_printf(com0, "\n[YOUR TURN] Enter 3 digits: ");
            uart_readline(com0, buf, sizeof(buf));

            if (is_valid_input(buf)) {
                /* 判定 */
                check_hit_blow(secret_ext, buf, &h, &b);

                /* 結果表示 */
                uart_printf(com0, "Result: %d Hit, %d Blow\n", h, b);
                uart_printf(com1, "\nOpponent Guessed: %s -> %d Hit, %d Blow\n", buf, h, b);

                if (h == 3) {
                    /* 勝利条件 */
                    uart_printf(com0, "3 Hit You Win !!\n");
                    uart_printf(com1, "3 Hit You Lose\n");
                    game_phase = PHASE_GAMEOVER;
                } else {
                    /* ターン交代 */
                    game_phase = PHASE_EXT_TURN;
                }
            } else {
                uart_printf(com0, "Invalid input.\n");
            }
        } else if (game_phase == PHASE_GAMEOVER) {
            /* ゲーム終了時の待機 */
            swtch();
        } else {
            /* 相手のターン中はCPUを譲る */
            swtch();
        }
    }
}

/******************************************************************
** タスク2: EXT (UART1) 制御
******************************************************************/
void task_ext() {
    char buf[16];
    int h, b;

    /* --- 設定フェーズ --- */
    uart_printf(com1, "Please enter a 3-digit number.\n");

    while (1) {
        uart_readline(com1, buf, sizeof(buf));
        if (is_valid_input(buf)) {
            strcpy(secret_ext, buf);
            break;
        } else {
            uart_printf(com1, "Invalid input. Please enter 3 digits.\n");
        }
    }

    setup_ext_done = 1;
    uart_printf(com1, "One moment, please.\n");

    /* 相手の入力完了を待つ */
    while (!setup_pc_done) {
        swtch();
    }

    /* 同時にSTART表示 */
    uart_printf(com1, "START\n");

    /* --- 対戦フェーズ --- */
    while (1) {
        if (game_phase == PHASE_EXT_TURN) {
            uart_printf(com1, "\n[YOUR TURN] Enter 3 digits: ");
            uart_readline(com1, buf, sizeof(buf));

            if (is_valid_input(buf)) {
                /* 判定 */
                check_hit_blow(secret_pc, buf, &h, &b);

                /* 結果表示 */
                uart_printf(com1, "Result: %d Hit, %d Blow\n", h, b);
                uart_printf(com0, "\nOpponent Guessed: %s -> %d Hit, %d Blow\n", buf, h, b);

                if (h == 3) {
                    /* 勝利条件 */
                    uart_printf(com1, "3 Hit You Win !!\n");
                    uart_printf(com0, "3 Hit You Lose\n");
                    game_phase = PHASE_GAMEOVER;
                } else {
                    /* ターン交代 */
                    game_phase = PHASE_PC_TURN;
                }
            } else {
                uart_printf(com1, "Invalid input.\n");
            }
        } else if (game_phase == PHASE_GAMEOVER) {
            swtch();
        } else {
            /* 相手のターン中はCPUを譲る */
            swtch();
        }
    }
}

/******************************************************************
** メイン関数
******************************************************************/
int main(void) {
    /* まずカーネル初期化（UART FD がここで準備される環境がある） */
    init_kernel();

    /* UART0/UART1 を「1本のFILE*」で開く（同一fdに複数streamを作らない） */
    com0 = fdopen(UART0_FD, "r+");
    com1 = fdopen(UART1_FD, "r+");

    /* バッファリングを切る（表示遅延・未出力・タスク切替時の不整合を避ける） */
    if (com0) setvbuf(com0, NULL, _IONBF, 0);
    if (com1) setvbuf(com1, NULL, _IONBF, 0);

    /* ここが NULL だと task_ext / task_pc の最初の fprintf で落ち得るので必ず止める */
    if (!com0) {
        /* com0 が開けないと何も出せないので停止 */
        while (1) {
            swtch();
        }
    }
    if (!com1) {
        uart_printf(com0, "ERROR: UART1 (fd=%d) open failed. Check fd number.\n", UART1_FD);
        while (1) {
            swtch();
        }
    }

    /* タスク登録 */
    set_task(task_pc);
    set_task(task_ext);

    /* スケジューラ開始 */
    begin_sch();

    return 0;
}
