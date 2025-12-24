#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdarg.h> /* fcntl実装に必要 */
#include "mtk_c.h"

/* fcntl.h が無い環境のために定数を定義 */
#ifndef O_RDWR
#define O_RDWR 2
#endif
#ifndef F_GETFL
#define F_GETFL 3
#endif
#ifndef F_SETFL
#define F_SETFL 4
#endif

/* ===============================
   重要: fcntl ダミー実装
   これが無いと fdopen や fgets がクラッシュします
   =============================== */
static int g_fd_flags[16];

/* libcが内部で呼ぶ関数。ただ成功したフリをする。 */
int fcntl(int fd, int cmd, ...) {
    if (fd < 0 || fd >= 16) return 0;

    if (cmd == F_GETFL) {
        /* フラグが未設定なら O_RDWR (読み書き) とみなす */
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

/* ===============================
   定数定義
   =============================== */
#define PHASE_SETUP     0
#define PHASE_PC_TURN   1
#define PHASE_EXT_TURN  2
#define PHASE_GAMEOVER  3

/* ファイル記述子 (mtk仕様) */
#define FD_UART0 3
#define FD_UART1 4

/* ===============================
   グローバル変数
   =============================== */
volatile int game_phase = PHASE_SETUP;
volatile int setup_pc_done = 0;
volatile int setup_ext_done = 0;

char secret_pc[4];
char secret_ext[4];

/* ファイルポインタ */
FILE *fp_uart0 = NULL;
FILE *fp_uart1 = NULL;

/* ===============================
   入出力関数
   =============================== */

/* 文字列出力 */
static void uart_puts_n(FILE *fp, const char *s)
{
    if (!fp) return;
    fputs(s, fp);
}

/* 1行入力 (fgets使用) */
static void uart_readline(FILE *fp, char *buf, int maxlen)
{
    if (!fp) return;

    /* fgetsを使用 */
    if (fgets(buf, maxlen, fp) != NULL) {
        /* 改行削除 */
        size_t len = strlen(buf);
        while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r')) {
            buf[len - 1] = '\0';
            len--;
        }
    } else {
        buf[0] = '\0';
        clearerr(fp);
    }
}

/* ===============================
   ロジック
   =============================== */
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

/* ===============================
   タスク1: PC (UART0)
   =============================== */
void task_pc(void)
{
    char buf[16];
    int h, b;
    FILE *fp = fp_uart0;

    uart_puts_n(fp, "Please enter a 3-digit number.\n");

    while (1) {
        uart_readline(fp, buf, sizeof(buf));
        uart_puts_n(fp, "\n");
        
        if (is_valid_input(buf)) {
            strcpy(secret_pc, buf);
            break;
        }
        uart_puts_n(fp, "Invalid input.\n");
    }

    setup_pc_done = 1;
    uart_puts_n(fp, "One moment, please.\n");
    while (!setup_ext_done) swtch();

    uart_puts_n(fp, "START\n");
    game_phase = PHASE_PC_TURN;

    while (1) {
        if (game_phase == PHASE_PC_TURN) {
            uart_puts_n(fp, "[YOUR TURN] Enter 3 digits: ");
            uart_readline(fp, buf, sizeof(buf));
            uart_puts_n(fp, "\n");

            if (is_valid_input(buf)) {
                check_hit_blow(secret_ext, buf, &h, &b);
                print_result(fp, h, b);

                if (h == 3) {
                    uart_puts_n(fp, "YOU WIN\n");
                    game_phase = PHASE_GAMEOVER;
                } else {
                    game_phase = PHASE_EXT_TURN;
                }
            } else {
                uart_puts_n(fp, "Invalid input.\n");
            }
        } else if (game_phase == PHASE_GAMEOVER) {
            swtch();
        } else {
            swtch();
        }
    }
}

/* ===============================
   タスク2: EXT (UART1)
   =============================== */
void task_ext(void)
{
    char buf[16];
    int h, b;
    FILE *fp = fp_uart1;

    uart_puts_n(fp, "Please enter a 3-digit number.\n");

    while (1) {
        uart_readline(fp, buf, sizeof(buf));
        uart_puts_n(fp, "\n");
        
        if (is_valid_input(buf)) {
            strcpy(secret_ext, buf);
            break;
        }
        uart_puts_n(fp, "Invalid input.\n");
    }

    setup_ext_done = 1;
    uart_puts_n(fp, "One moment, please.\n");
    while (!setup_pc_done) swtch();

    uart_puts_n(fp, "START\n");

    while (1) {
        if (game_phase == PHASE_EXT_TURN) {
            uart_puts_n(fp, "[YOUR TURN] Enter 3 digits: ");
            uart_readline(fp, buf, sizeof(buf));
            uart_puts_n(fp, "\n");

            if (is_valid_input(buf)) {
                check_hit_blow(secret_pc, buf, &h, &b);
                print_result(fp, h, b);

                if (h == 3) {
                    uart_puts_n(fp, "YOU WIN\n");
                    game_phase = PHASE_GAMEOVER;
                } else {
                    game_phase = PHASE_PC_TURN;
                }
            } else {
                uart_puts_n(fp, "Invalid input.\n");
            }
        } else if (game_phase == PHASE_GAMEOVER) {
            swtch();
        } else {
            swtch();
        }
    }
}

/* ===============================
   メイン関数
   =============================== */
int main(void)
{
    init_kernel();

    /* v1で成功した "r+" 方式を採用 */
    /* fcntlダミーがあるのでクラッシュしません */
    fp_uart0 = fdopen(FD_UART0, "r+");
    if (fp_uart0) setvbuf(fp_uart0, NULL, _IONBF, 0);

    fp_uart1 = fdopen(FD_UART1, "r+");
    if (fp_uart1) setvbuf(fp_uart1, NULL, _IONBF, 0);

    if (!fp_uart0 || !fp_uart1) {
        while(1) swtch();
    }
    
    set_task(task_pc);
    set_task(task_ext);
    begin_sch();
    return 0;
}
