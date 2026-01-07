#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mtk_c.h"
#include <unistd.h>

/* --- プロトタイプ宣言 --- */
void yield(void);

/* テーマ2で作成した関数名 */
extern void p(int id);
extern void v(int id);
extern void set_sem(int id, int val);

#define sys_wait_sem(id)    p(id)
#define sys_signal_sem(id)  v(id)
#define sys_set_sem(id, val) set_sem(id, val)

/* --- 定数定義 --- */
#define PHASE_SETUP     0
#define PHASE_PLAYING   1
#define PHASE_GAMEOVER  3

#define UART0_FD 3
#define UART1_FD 4

/* --- バリア同期設定 --- */
#define SEM_M  0  /* 排他制御用 (Mutex) */
#define SEM_W  1  /* 待ち合わせ用 (Wait) */
#define K      2  /* 参加タスク数 */

/* --- グローバル変数 --- */
volatile int game_phase = PHASE_SETUP;

/* バリア同期用共有変数 */
volatile int FM = 0; 

/* アライメント配慮されたバッファ */
static int secret_pc_storage[4];  /* 16 bytes */
static int secret_ext_storage[4]; /* 16 bytes */
static int pc_input_storage[8];   /* 32 bytes */
static int ext_input_storage[8];  /* 32 bytes */

#define SECRET_PC   ((char*)secret_pc_storage)
#define SECRET_EXT  ((char*)secret_ext_storage)
#define BUF_PC      ((char*)pc_input_storage)
#define BUF_EXT     ((char*)ext_input_storage)

/* タスク間通信用構造体 (メールボックス形式) */
typedef struct {
    char guess[16];     
    int h;              
    int b;              
    volatile int has_mail; /* 1なら未読メッセージあり */
} Mailbox;

Mailbox res_to_ext; /* PC -> EXT への通知BOX */
Mailbox res_to_pc;  /* EXT -> PC への通知BOX */

/* --- 簡易ウェイト関数 --- */
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
    static int num_buf_storage[4];
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

/* --- セットアップ用 同期入力関数 --- */
int uart_readline(int fd, char* target_buf, int bufsz) {
    int pos = 0;
    int n;
    int c_storage = 0; 
    char* c_ptr = (char*)&c_storage;

    if (!target_buf || bufsz == 0) return 0;
    for(int i=0; i<bufsz; i++) target_buf[i] = 0;

    while (pos < bufsz - 1) {
        n = read(fd, c_ptr, 1);
        if (n > 0) {
            char c = *c_ptr;
            if (c == '\r' || c == '\n') {
                target_buf[pos] = '\0';
                uart_puts(fd, "\r\n");
                return 1;
            }
            target_buf[pos++] = c;
        } else {
            simple_delay(); 
            yield(); 
        }
    }
    target_buf[pos] = '\0';
    return 1;
}

/* --- 【修正】相手からの通知をチェックして表示する関数 --- */
int check_opponent_update(int my_fd, Mailbox* my_inbox) {
    int finished = 0;

    sys_wait_sem(SEM_M);

    if (my_inbox->has_mail) {
        uart_puts(my_fd, "\r\n[NOTICE] Opponent Guessed: ");
        uart_puts(my_fd, my_inbox->guess);
        uart_puts(my_fd, " -> ");
        uart_putn(my_fd, my_inbox->h);
        uart_puts(my_fd, " Hit, ");
        uart_putn(my_fd, my_inbox->b);
        uart_puts(my_fd, " Blow\r\n");

        /* 相手が3Hit = 自分の負け */
        if (my_inbox->h == 3) {
            uart_puts(my_fd, "\r\n*** You Lose... ***\r\n");
            
            /* 【修正点】負けが確定したこの瞬間に END を出す */
            uart_puts(my_fd, "--- END ---\r\n");
            
            game_phase = PHASE_GAMEOVER;
            finished = 1;
        }

        my_inbox->has_mail = 0;
    }
    
    if (game_phase == PHASE_GAMEOVER) {
        finished = 1;
    }

    sys_signal_sem(SEM_M);

    return finished;
}

/* --- 非同期対応 readline (ゲームプレイ用) --- */
int uart_readline_async(int fd, char* target_buf, int bufsz, Mailbox* my_inbox) {
    int pos = 0;
    int n;
    int c_storage = 0; 
    char* c_ptr = (char*)&c_storage;
    int updated;

    if (!target_buf || bufsz == 0) return 0;
    for(int i=0; i<bufsz; i++) target_buf[i] = 0;
    
    while (pos < bufsz - 1) {
        n = read(fd, c_ptr, 1);

        if (n > 0) {
            char c = *c_ptr;
            if (c == '\r' || c == '\n') {
                target_buf[pos] = '\0';
                uart_puts(fd, "\r\n");
                return 1;
            }
            target_buf[pos++] = c;
        } else {
            /* 入力待ち中 */
            updated = check_opponent_update(fd, my_inbox);
            if (updated) {
                /* ゲーム終了なら入力中断して戻る */
                return 0; 
            }
            /* まだ続くなら入力を継続 */
            simple_delay();
            yield(); 
        }
    }
    target_buf[pos] = '\0';
    return 1;
}

void check_hit_blow(const char* target, const char* guess, int* h, int* b) {
    int i, j;
    *h = 0; *b = 0;
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

/* --- バリア同期関数 --- */
void barrier_sync(void) {
    sys_wait_sem(SEM_M);
    FM++; 
    if (FM < K) {
        sys_signal_sem(SEM_M);
        sys_wait_sem(SEM_W);
    } else {
        FM = 0; 
        sys_signal_sem(SEM_M);
        sys_signal_sem(SEM_W);
    }
}

/******************************************************************
** タスク1: PC (UART0)
******************************************************************/
void task_pc() {
    int h, b;
    
    sys_wait_sem(SEM_M);
    res_to_ext.has_mail = 0;
    sys_signal_sem(SEM_M);

    /* セットアップ */
    uart_puts(UART0_FD, "Setup Secret Number.\n");
    while(1) {
        uart_readline(UART0_FD, BUF_PC, 32); 
        if (is_valid_input(BUF_PC)) {
            my_strcpy(SECRET_PC, BUF_PC);
            break;
        } else {
            uart_puts(UART0_FD, "Invalid input.\n");
        }
    }

    uart_puts(UART0_FD, "Waiting for opponent...\n");
    barrier_sync(); 

    uart_puts(UART0_FD, "START! (Free Input)\n");
    game_phase = PHASE_PLAYING;

    /* メインループ */
    while (game_phase != PHASE_GAMEOVER) {
        uart_puts(UART0_FD, "Input> ");
        
        /* 0が返ってきたらゲーム終了(敗北など) */
        if (!uart_readline_async(UART0_FD, BUF_PC, 32, &res_to_pc)) {
            break; 
        }

        if (is_valid_input(BUF_PC)) {
            check_hit_blow(SECRET_EXT, BUF_PC, &h, &b);
            
            uart_puts(UART0_FD, " -> ");
            uart_putn(UART0_FD, h);
            uart_puts(UART0_FD, "H ");
            uart_putn(UART0_FD, b);
            uart_puts(UART0_FD, "B\n");

            /* 相手に通知 */
            sys_wait_sem(SEM_M);
            my_strcpy(res_to_ext.guess, BUF_PC);
            res_to_ext.h = h;
            res_to_ext.b = b;
            res_to_ext.has_mail = 1;
            sys_signal_sem(SEM_M);

            if (h == 3) {
                uart_puts(UART0_FD, "\r\n*** YOU WIN !! ***\r\n");
                /* 【修正点】勝ちが確定したこの瞬間に END を出す */
                uart_puts(UART0_FD, "--- END ---\r\n");
                
                game_phase = PHASE_GAMEOVER;
                break;
            }
        } else {
            uart_puts(UART0_FD, "Invalid input.\n");
        }
    }
    
    /* ループ終了後の停止処理 (END表示はループ内で行うので削除) */
    while(1) {
        simple_delay();
        yield();
    }
}

/******************************************************************
** タスク2: EXT (UART1)
******************************************************************/
void task_ext() {
    int h, b;
    
    sys_wait_sem(SEM_M);
    res_to_pc.has_mail = 0;
    sys_signal_sem(SEM_M);

    uart_puts(UART1_FD, "Setup Secret Number.\n");
    while(1) {
        uart_readline(UART1_FD, BUF_EXT, 32); 
        if (is_valid_input(BUF_EXT)) {
            my_strcpy(SECRET_EXT, BUF_EXT);
            break;
        } else {
            uart_puts(UART1_FD, "Invalid input.\n");
        }
    }

    uart_puts(UART1_FD, "Waiting for opponent...\n");
    barrier_sync(); 

    uart_puts(UART1_FD, "START! (Free Input)\n");

    while (game_phase != PHASE_GAMEOVER) {
        uart_puts(UART1_FD, "Input> ");
        
        if (!uart_readline_async(UART1_FD, BUF_EXT, 32, &res_to_ext)) {
            break;
        }

        if (is_valid_input(BUF_EXT)) {
            check_hit_blow(SECRET_PC, BUF_EXT, &h, &b);

            uart_puts(UART1_FD, " -> ");
            uart_putn(UART1_FD, h);
            uart_puts(UART1_FD, "H ");
            uart_putn(UART1_FD, b);
            uart_puts(UART1_FD, "B\n");

            sys_wait_sem(SEM_M);
            my_strcpy(res_to_pc.guess, BUF_EXT);
            res_to_pc.h = h;
            res_to_pc.b = b;
            res_to_pc.has_mail = 1;
            sys_signal_sem(SEM_M);

            if (h == 3) {
                uart_puts(UART1_FD, "\r\n*** YOU WIN !! ***\r\n");
                /* 【修正点】勝ちが確定したこの瞬間に END を出す */
                uart_puts(UART1_FD, "--- END ---\r\n");
                
                game_phase = PHASE_GAMEOVER;
                break;
            }
        } else {
            uart_puts(UART1_FD, "Invalid input.\n");
        }
    }

    /* ループ終了後の停止処理 */
    while(1) {
        simple_delay();
        yield();
    }
}

int main(void) {
    init_kernel();
    sys_wait_sem(SEM_W); 
    FM = 0;

    set_task(task_pc);
    set_task(task_ext);
    begin_sch();
    return 0;
}
