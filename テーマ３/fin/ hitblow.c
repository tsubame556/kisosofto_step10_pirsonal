#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mtk_c.h"
#include <unistd.h>

/* --- プロトタイプ宣言 --- */
/* mtk_c.c に追加した yield 関数を利用する */
void yield(void);

/* --- 定数定義 --- */
#define PHASE_SETUP     0
#define PHASE_PC_TURN   1
#define PHASE_EXT_TURN  2
#define PHASE_GAMEOVER  3

#define UART0_FD 3
#define UART1_FD 4

/* --- グローバル変数 (静的確保・アライメント配慮) --- */
volatile int game_phase = PHASE_SETUP;
volatile int setup_pc_done = 0;
volatile int setup_ext_done = 0;

/* バッファ類は int (4バイト) で宣言することで、
   必ず4バイト境界(偶数アドレス)に配置されるように強制する。
   M68kのAddress Error(EXCEPTION 3)を回避するための処置。
*/
static int secret_pc_storage[4];  /* 16 bytes */
static int secret_ext_storage[4]; /* 16 bytes */
static int pc_input_storage[8];   /* 32 bytes */
static int ext_input_storage[8];  /* 32 bytes */

/* 読み書き用ポインタ（キャストの手間を省くため） */
#define SECRET_PC   ((char*)secret_pc_storage)
#define SECRET_EXT  ((char*)secret_ext_storage)
#define BUF_PC      ((char*)pc_input_storage)
#define BUF_EXT     ((char*)ext_input_storage)

/* タスク間通信用構造体 */
typedef struct {
    char guess[16];     
    int h;              
    int b;              
    volatile int ready; 
} ResultData;

ResultData res_to_ext;
ResultData res_to_pc;

/* --- 簡易ウェイト関数 --- */
/* ポーリングループが高速すぎてCPUを占有しすぎないためのウェイト */
void simple_delay() {
    volatile int i;
    for (i = 0; i < 1000; i++);
}

/* --- 自作ユーティリティ --- */

size_t my_strlen(const char* s) {
    const char* p = s;
    while (*p) p++;
    return (size_t)(p - s);
}

void my_strcpy(char* dst, const char* src) {
    while ((*dst++ = *src++) != 0);
}

int my_isdigit(char c) {
    return (c >= '0' && c <= '9');
}

void uart_puts(int fd, const char* s) {
    if (!s) return;
    write(fd, s, my_strlen(s));
}

void uart_putn(int fd, int n) {
    /* スタック上のchar配列はアライメント違反のリスクがあるため、
       staticなint配列をバッファとして使う */
    static int num_buf_storage[4]; /* 16 bytes */
    char* buf = (char*)num_buf_storage;
    
    int i = 0;
    int sign = n;
    
    if (n == 0) {
        write(fd, "0", 1);
        return;
    }

    if (n < 0) n = -n;

    while (n > 0) {
        buf[i++] = (n % 10) + '0';
        n /= 10;
    }
    if (sign < 0) buf[i++] = '-';

    while (i > 0) {
        write(fd, &buf[--i], 1);
    }
}

/* --- 改良版 readline --- */
/* readに渡すバッファのアドレスを必ず偶数にする。
   データ待ちの間は yield() を呼んで他タスクへCPUを譲る。
*/
int uart_readline(int fd, char* target_buf, int bufsz) {
    int pos = 0;
    int n;
    
    /* readシステムコール用の1バイトバッファ。
       intで宣言することでスタック上でも必ず偶数アドレス(4バイト境界)になる */
    int c_storage = 0; 
    char* c_ptr = (char*)&c_storage;

    if (!target_buf || bufsz == 0) return 0;
    
    /* バッファクリア */
    for(int i=0; i<bufsz; i++) target_buf[i] = 0;

    while (pos < bufsz - 1) {
        /* システムコールには必ずアライメントされたアドレスを渡す */
        n = read(fd, c_ptr, 1);

        if (n > 0) {
            char c = *c_ptr;
            if (c == '\r' || c == '\n') {
                target_buf[pos] = '\0';
                return 1;
            }
            target_buf[pos++] = c;
        } else {
            /* 読み込みデータがない場合は、少し待ってからタスクを譲る */
            simple_delay(); 
            yield(); /* 【重要】swtch() から yield() へ変更 */
        }
    }
    target_buf[pos] = '\0';
    return 1;
}

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

int is_valid_input(const char* str) {
    if (!str) return 0;
    if (my_strlen(str) != 3) return 0;
    for (int i = 0; i < 3; i++) {
        if (!my_isdigit(str[i])) return 0;
    }
    return 1;
}

/******************************************************************
** タスク1: PC (UART0)
******************************************************************/
void task_pc() {
    int h, b;
    res_to_pc.ready = 0;

    uart_puts(UART0_FD, "Please enter a 3-digit number.\n");

    while (1) {
        uart_readline(UART0_FD, BUF_PC, 32);
        if (is_valid_input(BUF_PC)) {
            my_strcpy(SECRET_PC, BUF_PC);
            break;
        } else {
            uart_puts(UART0_FD, "Invalid input.\n");
        }
    }

    setup_pc_done = 1;
    uart_puts(UART0_FD, "One moment, please.\n");

    /* 相手のセットアップ完了待ち */
    while (!setup_ext_done) {
        yield(); /* 【重要】swtch() から yield() へ変更 */
    }

    uart_puts(UART0_FD, "START\n");
    game_phase = PHASE_PC_TURN;

    while (1) {
        if (game_phase == PHASE_PC_TURN) {
            uart_puts(UART0_FD, "\n[YOUR TURN] Enter 3 digits: ");
            uart_readline(UART0_FD, BUF_PC, 32);

            if (is_valid_input(BUF_PC)) {
                check_hit_blow(SECRET_EXT, BUF_PC, &h, &b);
                
                uart_puts(UART0_FD, "Result: ");
                uart_putn(UART0_FD, h);
                uart_puts(UART0_FD, " Hit, ");
                uart_putn(UART0_FD, b);
                uart_puts(UART0_FD, " Blow\n");

                my_strcpy(res_to_ext.guess, BUF_PC);
                res_to_ext.h = h;
                res_to_ext.b = b;
                res_to_ext.ready = 1; 

                if (h == 3) {
                    uart_puts(UART0_FD, "3 Hit You Win !!\n");
                    game_phase = PHASE_GAMEOVER;
                } else {
                    game_phase = PHASE_EXT_TURN;
                }
            } else {
                uart_puts(UART0_FD, "Invalid input.\n");
            }
        }
        else if (res_to_pc.ready) {
            uart_puts(UART0_FD, "\nOpponent Guessed: ");
            uart_puts(UART0_FD, res_to_pc.guess);
            uart_puts(UART0_FD, " -> ");
            uart_putn(UART0_FD, res_to_pc.h);
            uart_puts(UART0_FD, " Hit, ");
            uart_putn(UART0_FD, res_to_pc.b);
            uart_puts(UART0_FD, " Blow\n");
            
            if (res_to_pc.h == 3) {
                uart_puts(UART0_FD, "3 Hit You Lose\n");
            }
            res_to_pc.ready = 0;
        }
        else {
            /* 待ち時間はCPUを譲る */
            simple_delay();
            yield(); /* 【重要】swtch() から yield() へ変更 */
        }
    }
}

/******************************************************************
** タスク2: EXT (UART1)
******************************************************************/
void task_ext() {
    int h, b;
    res_to_ext.ready = 0;

    uart_puts(UART1_FD, "Please enter a 3-digit number.\n");

    while (1) {
        uart_readline(UART1_FD, BUF_EXT, 32);
        if (is_valid_input(BUF_EXT)) {
            my_strcpy(SECRET_EXT, BUF_EXT);
            break;
        } else {
            uart_puts(UART1_FD, "Invalid input.\n");
        }
    }

    setup_ext_done = 1;
    uart_puts(UART1_FD, "One moment, please.\n");

    /* 相手のセットアップ完了待ち */
    while (!setup_pc_done) {
        yield(); /* 【重要】swtch() から yield() へ変更 */
    }

    uart_puts(UART1_FD, "START\n");

    while (1) {
        if (game_phase == PHASE_EXT_TURN) {
            uart_puts(UART1_FD, "\n[YOUR TURN] Enter 3 digits: ");
            uart_readline(UART1_FD, BUF_EXT, 32);

            if (is_valid_input(BUF_EXT)) {
                check_hit_blow(SECRET_PC, BUF_EXT, &h, &b);

                uart_puts(UART1_FD, "Result: ");
                uart_putn(UART1_FD, h);
                uart_puts(UART1_FD, " Hit, ");
                uart_putn(UART1_FD, b);
                uart_puts(UART1_FD, " Blow\n");

                my_strcpy(res_to_pc.guess, BUF_EXT);
                res_to_pc.h = h;
                res_to_pc.b = b;
                res_to_pc.ready = 1;

                if (h == 3) {
                    uart_puts(UART1_FD, "3 Hit You Win !!\n");
                    game_phase = PHASE_GAMEOVER;
                } else {
                    game_phase = PHASE_PC_TURN;
                }
            } else {
                uart_puts(UART1_FD, "Invalid input.\n");
            }
        }
        else if (res_to_ext.ready) {
            uart_puts(UART1_FD, "\nOpponent Guessed: ");
            uart_puts(UART1_FD, res_to_ext.guess);
            uart_puts(UART1_FD, " -> ");
            uart_putn(UART1_FD, res_to_ext.h);
            uart_puts(UART1_FD, " Hit, ");
            uart_putn(UART1_FD, res_to_ext.b);
            uart_puts(UART1_FD, " Blow\n");

            if (res_to_ext.h == 3) {
                uart_puts(UART1_FD, "3 Hit You Lose\n");
            }
            res_to_ext.ready = 0;
        }
        else {
            /* 待ち時間はCPUを譲る */
            simple_delay();
            yield(); /* 【重要】swtch() から yield() へ変更 */
        }
    }
}

int main(void) {
    init_kernel();
    set_task(task_pc);
    set_task(task_ext);
    begin_sch();
    return 0;
}
