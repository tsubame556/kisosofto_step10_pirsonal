#include "mtk_c.h"

/* --- 標準ライブラリを使わない定義 --- */
#define NULL ((void *)0)

/* 外部関数 */
extern void outbyte(char c, int uart_ch);
extern char inbyte(int uart_ch);
extern void swtch(void); /* 明示的な切り替えのため復活 */

/* 定数 */
#define PHASE_SETUP     0
#define PHASE_PC_TURN   1
#define PHASE_EXT_TURN  2
#define PHASE_GAMEOVER  3

#define PORT_PC   0
#define PORT_EXT  1

/* グローバル変数 */
char shared_buf[256];

volatile int game_phase = PHASE_SETUP;
char secret_pc[16];
char secret_ext[16];
volatile int setup_pc_done = 0;
volatile int setup_ext_done = 0;

/* --- 自作ライブラリ関数 --- */
void my_strcpy(char *dest, const char *src) { while ((*dest++ = *src++)); }
void my_strcat(char *dest, const char *src) { while (*dest) dest++; while ((*dest++ = *src++)); }
int my_strlen(const char *str) { int len = 0; while (*str++) len++; return len; }
int my_isdigit(char c) { return (c >= '0' && c <= '9'); }

void int_to_str(int value, char *str) {
    char temp[16];
    int i = 0, j = 0;
    if (value == 0) { str[0] = '0'; str[1] = '\0'; return; }
    while (value > 0) { temp[i++] = (value % 10) + '0'; value /= 10; }
    while (i > 0) { str[j++] = temp[--i]; }
    str[j] = '\0';
}

void uart_puts(int ch, const char *str) {
    while (*str) {
        if (*str == '\n') outbyte('\r', ch);
        outbyte(*str++, ch);
    }
}

/* ★修正: 入力待ちの間に swtch() を挟む (協調的マルチタスク) */
void uart_gets(int ch, char *buf, int max_len) {
    int i = 0;
    char c;

    while (1) {
        c = inbyte(ch); /* 入力をチェック (非ブロッキング前提) */

        if (c == 0) {
            /* 入力がない場合、CPUを占有せず相手に譲る */
            swtch();
            continue;
        }

        if (c == '\r') { /* Enter */
            outbyte('\r', ch);
            outbyte('\n', ch);
            buf[i] = '\0';
            break;
        }
        else if (c == '\b' || c == 0x7f) { /* BS */
            if (i > 0) {
                i--;
                outbyte('\b', ch);
                outbyte(' ', ch);
                outbyte('\b', ch);
            }
        }
        else {
            if (i < max_len - 1) {
                buf[i++] = c;
                outbyte(c, ch);
            }
        }
    }
}

void safe_puts(int ch, const char* msg) {
    P(SEM_IO); uart_puts(ch, msg); V(SEM_IO);
}

void make_result_msg(char* buf, const char* prefix, const char* guess, int h, int b) {
    char num_buf[4];
    buf[0] = '\0';
    if (prefix) my_strcat(buf, prefix);
    if (guess) { my_strcat(buf, guess); my_strcat(buf, " -> "); }
    int_to_str(h, num_buf); my_strcat(buf, num_buf); my_strcat(buf, " Hit, ");
    int_to_str(b, num_buf); my_strcat(buf, num_buf); my_strcat(buf, " Blow\n");
}

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

int is_valid_input(const char* str) {
    if (my_strlen(str) != 3) return 0;
    for(int i=0; i<3; i++) if (!my_isdigit(str[i])) return 0;
    return 1;
}

/* --- タスク処理 --- */

void task_pc(){
    static char in_buf[16];
    static int h, b;

    safe_puts(PORT_PC, "Please enter a 3-digit number.\n");
    
    while(1) {
        uart_gets(PORT_PC, in_buf, 15); /* 中で swtch() するのでブロックしない */
        if (is_valid_input(in_buf)) { my_strcpy(secret_pc, in_buf); break; }
        else { safe_puts(PORT_PC, "Invalid input. Please enter 3 digits.\n"); }
    }

    setup_pc_done = 1;
    safe_puts(PORT_PC, "One moment, please.\n");

    /* ★修正: 待機中もCPUを譲る */
    while (!setup_ext_done) swtch();

    safe_puts(PORT_PC, "START\n");
    game_phase = PHASE_PC_TURN;

    while(1){
        if (game_phase == PHASE_PC_TURN) {
            safe_puts(PORT_PC, "\n[YOUR TURN] Enter 3 digits: ");
            uart_gets(PORT_PC, in_buf, 15);

            if (is_valid_input(in_buf)) {
                check_hit_blow(secret_ext, in_buf, &h, &b);
                
                P(SEM_IO);
                make_result_msg(shared_buf, "Result: ", NULL, h, b);
                uart_puts(PORT_PC, shared_buf);
                uart_puts(PORT_EXT, "\nOpponent Guessed: ");
                make_result_msg(shared_buf, NULL, in_buf, h, b);
                uart_puts(PORT_EXT, shared_buf);
                V(SEM_IO);

                if (h == 3) {
                    safe_puts(PORT_PC, "3 Hit You Win !!\n");
                    safe_puts(PORT_EXT, "3 Hit You Lose\n");
                    game_phase = PHASE_GAMEOVER;
                } else {
                    game_phase = PHASE_EXT_TURN;
                }
            } else {
                safe_puts(PORT_PC, "Invalid input.\n");
            }
        }
        else {
             /* 自分のターンでない時もCPUを譲る */
             swtch();
        }
    }
}

void task_ext(){
    static char in_buf[16];
    static int h, b;

    safe_puts(PORT_EXT, "Please enter a 3-digit number.\n");

    while(1) {
        uart_gets(PORT_EXT, in_buf, 15); /* swtch() 込み */
        if (is_valid_input(in_buf)) { my_strcpy(secret_ext, in_buf); break; }
        else { safe_puts(PORT_EXT, "Invalid input. Please enter 3 digits.\n"); }
    }

    setup_ext_done = 1;
    safe_puts(PORT_EXT, "One moment, please.\n");

    /* ★修正: 待機中もCPUを譲る */
    while (!setup_pc_done) swtch();

    safe_puts(PORT_EXT, "START\n");

    while(1){
        if (game_phase == PHASE_EXT_TURN) {
            safe_puts(PORT_EXT, "\n[YOUR TURN] Enter 3 digits: ");
            uart_gets(PORT_EXT, in_buf, 15);

            if (is_valid_input(in_buf)) {
                check_hit_blow(secret_pc, in_buf, &h, &b);
                
                P(SEM_IO);
                make_result_msg(shared_buf, "Result: ", NULL, h, b);
                uart_puts(PORT_EXT, shared_buf);
                uart_puts(PORT_PC, "\nOpponent Guessed: ");
                make_result_msg(shared_buf, NULL, in_buf, h, b);
                uart_puts(PORT_PC, shared_buf);
                V(SEM_IO);

                if (h == 3) {
                    safe_puts(PORT_EXT, "3 Hit You Win !!\n");
                    safe_puts(PORT_PC, "3 Hit You Lose\n");
                    game_phase = PHASE_GAMEOVER;
                } else {
                    game_phase = PHASE_PC_TURN;
                }
            } else {
                safe_puts(PORT_EXT, "Invalid input.\n");
            }
        }
        else {
             swtch();
        }
    }
}

int main(void){
    init_kernel();
    set_task(task_pc);
    set_task(task_ext);
    begin_sch();
    return 0;
}
