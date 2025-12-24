#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdarg.h> /* fcntl実装に必要 */
#include "mtk_c.h"

/* --- fcntl ダミー実装 (必須) --- */
#ifndef O_RDWR
#define O_RDWR 2
#endif
#ifndef F_GETFL
#define F_GETFL 3
#endif
#ifndef F_SETFL
#define F_SETFL 4
#endif

static int g_fd_flags[16];

int fcntl(int fd, int cmd, ...) {
    if (fd < 0 || fd >= 16) return 0;
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

/* --- 定数定義 --- */
#define PHASE_SETUP     0
#define PHASE_PC_TURN   1
#define PHASE_EXT_TURN  2
#define PHASE_GAMEOVER  3

#define FD_UART0 3
#define FD_UART1 4

/* --- グローバル変数 --- */
volatile int game_phase = PHASE_SETUP;
volatile int setup_pc_done = 0;
volatile int setup_ext_done = 0;

char secret_pc[4];
char secret_ext[4];

/* ストリームを分離して保持 */
FILE *fp0_in  = NULL; /* UART0 入力用 ("r") */
FILE *fp0_out = NULL; /* UART0 出力用 ("w") */
FILE *fp1_in  = NULL; /* UART1 入力用 ("r") */
FILE *fp1_out = NULL; /* UART1 出力用 ("w") */

/* --- 入出力関数 --- */

/* 文字列出力 */
static void uart_puts_n(FILE *fp, const char *s)
{
    if (!fp) return;
    fputs(s, fp);
}

/* 1行入力 (fgetc使用) */
/* fgetsよりもさらに原始的な fgetc を使い、ライブリの複雑な処理を回避 */
static void uart_readline(FILE *fp, char *buf, int maxlen)
{
    int i = 0;
    int c;

    if (!fp) return;

    while (1) {
        /* 1文字読み込み */
        c = fgetc(fp);

        /* エラーまたはEOF */
        if (c == EOF) {
            clearerr(fp);
            continue; /* リトライ */
        }

        /* 改行判定 (\r または \n) */
        if (c == '\r' || c == '\n') {
            buf[i] = '\0';
            return;
        }

        /* バッファ格納 (改行以外) */
        if (i < maxlen - 1) {
            buf[i++] = (char)c;
        }
    }
}

/* --- ロジック --- */
static int is_valid_input(const char *s)
{
    int i;
    if (strlen(s) != 3) return 0;
    for (i = 0; i < 3; i++) {
        if (!isdigit((unsigned char)s[i])) return 0;
    }
    return 1;
}

static void check_hit_blow(const char *t, const char *g, int *h, int *b)
{
    int i, j;
    *h = 0; *b = 0;
    for (i = 0; i < 3; i++) {
        if (g[i] == t[i]) (*h)++;
        else {
            for (j = 0; j < 3; j++) {
                if (i != j && g[i] == t[j]) { (*b)++; break; }
            }
        }
    }
}

static void print_result(FILE *fp, int h, int b)
{
    fprintf(fp, "Result: %d Hit, %d Blow\n", h, b);
}

/* --- タスク1: PC (UART0) --- */
void task_pc(void)
{
    char buf[16];
    int h, b;
    /* 入力には in、出力には out を使う */
    FILE *in  = fp0_in;
    FILE *out = fp0_out;

    uart_puts_n(out, "Please enter a 3-digit number.\n");

    while (1) {
        uart_readline(in, buf, sizeof(buf));
        uart_puts_n(out, "\n");
        
        if (is_valid_input(buf)) {
            strcpy(secret_pc, buf);
            break;
        }
        uart_puts_n(out, "Invalid input.\n");
    }

    setup_pc_done = 1;
    uart_puts_n(out, "One moment, please.\n");
    while (!setup_ext_done) swtch();

    uart_puts_n(out, "START\n");
    game_phase = PHASE_PC_TURN;

    while (1) {
        if (game_phase == PHASE_PC_TURN) {
            uart_puts_n(out, "[YOUR TURN] Enter 3 digits: ");
            uart_readline(in, buf, sizeof(buf));
            uart_puts_n(out, "\n");

            if (is_valid_input(buf)) {
                check_hit_blow(secret_ext, buf, &h, &b);
                print_result(out, h, b);

                if (h == 3) {
                    uart_puts_n(out, "YOU WIN\n");
                    game_phase = PHASE_GAMEOVER;
                } else {
                    game_phase = PHASE_EXT_TURN;
                }
            } else {
                uart_puts_n(out, "Invalid input.\n");
            }
        } else if (game_phase == PHASE_GAMEOVER) {
            swtch();
        } else {
            swtch();
        }
    }
}

/* --- タスク2: EXT (UART1) --- */
void task_ext(void)
{
    char buf[16];
    int h, b;
    /* 入力には in、出力には out を使う */
    FILE *in  = fp1_in;
    FILE *out = fp1_out;

    uart_puts_n(out, "Please enter a 3-digit number.\n");

    while (1) {
        uart_readline(in, buf, sizeof(buf));
        uart_puts_n(out, "\n");
        
        if (is_valid_input(buf)) {
            strcpy(secret_ext, buf);
            break;
        }
        uart_puts_n(out, "Invalid input.\n");
    }

    setup_ext_done = 1;
    uart_puts_n(out, "One moment, please.\n");
    while (!setup_pc_done) swtch();

    uart_puts_n(out, "START\n");

    while (1) {
        if (game_phase == PHASE_EXT_TURN) {
            uart_puts_n(out, "[YOUR TURN] Enter 3 digits: ");
            uart_readline(in, buf, sizeof(buf));
            uart_puts_n(out, "\n");

            if (is_valid_input(buf)) {
                check_hit_blow(secret_pc, buf, &h, &b);
                print_result(out, h, b);

                if (h == 3) {
                    uart_puts_n(out, "YOU WIN\n");
                    game_phase = PHASE_GAMEOVER;
                } else {
                    game_phase = PHASE_PC_TURN;
                }
            } else {
                uart_puts_n(out, "Invalid input.\n");
            }
        } else if (game_phase == PHASE_GAMEOVER) {
            swtch();
        } else {
            swtch();
        }
    }
}

/* --- メイン関数 --- */
int main(void)
{
    init_kernel();

    /* 重要修正:
       1. "r" (入力) と "w" (出力) を別々にオープンする。
          これにより、ライブラリが内部でモード切替(seek等)を行おうとしてクラッシュするのを防ぐ。
       2. _IONBF (バッファなし) は継続して使用。
    */

    /* UART0 (FD=3) */
    fp0_in  = fdopen(FD_UART0, "r");
    fp0_out = fdopen(FD_UART0, "w");

    /* UART1 (FD=4) */
    fp1_in  = fdopen(FD_UART1, "r");
    fp1_out = fdopen(FD_UART1, "w");

    /* バッファリング無効化 */
    if (fp0_in)  setvbuf(fp0_in,  NULL, _IONBF, 0);
    if (fp0_out) setvbuf(fp0_out, NULL, _IONBF, 0);
    if (fp1_in)  setvbuf(fp1_in,  NULL, _IONBF, 0);
    if (fp1_out) setvbuf(fp1_out, NULL, _IONBF, 0);

    /* 万が一オープン失敗したら停止 */
    if (!fp0_in || !fp0_out || !fp1_in || !fp1_out) {
        while(1) swtch();
    }
    
    set_task(task_pc);
    set_task(task_ext);
    begin_sch();
    return 0;
}
