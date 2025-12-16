#include "mtk_c.h"
#include <stdio.h>
#include <stdlib.h>


void sleep(int ch);
void wakeup(int ch);
void sched();
void swtch();

/* 【追加】UART制御用のセマフォIDを定義 (mtk_c.hでNUMSEMAPHORE=7を前提) */
#define SEM_UART0_IN  0 // UART0(ポート0)の入力制御用
#define SEM_UART0_OUT 1 // UART0(ポート0)の出力制御用
#define SEM_UART1_IN  2 // UART1(ポート1)の入力制御用
#define SEM_UART1_OUT 3 // UART1(ポート1)の出力制御用

/* 外部関数宣言 (モニタシステムコールへのインターフェースと仮定) */
extern int mtk_getstring(int uart_ch, char *buf, int len);
extern int mtk_putstring(int uart_ch, char *buf, int len);

/* 【追加】csys68kから呼ばれる入出力ラッパーの本体 */
char inbyte_body(int uart_ch);
void outbyte_body(char c, int uart_ch);

/* mtk_c.h で extern 宣言されたグローバル変数*/
TCB_TYPE task_tab[NUMTASK + 1];
// ... (中略) ...
SEMAPHORE_TYPE semaphore[NUMSEMAPHORE];

/*p_body(ch):Pシステムコールの本体*/
void p_body(int ch)
{
// ... (中略) ...
	return;
}

/*v_body(ch):Vシステムコールの本体*/
void v_body(int ch)
{
// ... (中略) ...
	return;
}


/*sleep(ch):タスクを休眠状態にしてタスクスイッチ*/
void sleep(int ch){
// ... (中略) ...
	return;
}

/*wakeup(ch):休眠状態のタスクを実行可能状態にする*/
void wakeup(int ch){
// ... (中略) ...
	return;
}


void init_kernel(){
// ... (中略) ...
	return;
}


void set_task(void (*func)()) {
// ... (中略) ...
	return;
}

void *init_stack(int id) {
// ... (中略) ...
    return (void *)sp;
}


void begin_sch() {
// ... (中略) ...
	return;
}

void sched() {
// ... (中略) ...
	return;
}

void addq(TASK_ID_TYPE *head, TASK_ID_TYPE tid) {
// ... (中略) ...
	return;
}

TASK_ID_TYPE removeq(TASK_ID_TYPE *head) {
// ... (中略) ...
	return t;
}

/* ======================================================= */
/* 【追加】テーマ3: I/Oシステムコール処理の本体 (排他制御セマフォ利用) */
/* ======================================================= */

/* inbyte_body(uart_ch): 1文字入力システムコール本体 */
char inbyte_body(int uart_ch) {
    char c = 0;
    int sem_ch = (uart_ch == UART0) ? SEM_UART0_IN : SEM_UART1_IN;
    
    // P操作: 入力リソースの獲得 (排他制御)
    P(sem_ch); 
    
    // モニタのGETSTRINGシステムコールを呼び出し
    // 1文字入力が保証されるまでリトライが必要（1.4.2節）とあるが、ここでは1度のコールで完結すると仮定
    while (mtk_getstring(uart_ch, &c, 1) != 1) {
        /* リトライが必要な場合はここにループ処理を追加 */
    }
    
    // V操作: 入力リソースの解放
    V(sem_ch);
    
    return c;
}

/* outbyte_body(c, uart_ch): 1文字出力システムコール本体 */
void outbyte_body(char c, int uart_ch) {
    int sem_ch = (uart_ch == UART0) ? SEM_UART0_OUT : SEM_UART1_OUT;
    
    // P操作: 出力リソースの獲得 (排他制御)
    P(sem_ch);
    
    // モニタのPUTSTRINGシステムコールを呼び出し
    while (mtk_putstring(uart_ch, &c, 1) != 1) {
        /* リトライが必要な場合はここにループ処理を追加 */
    }
    
    // V操作: 出力リソースの解放
    V(sem_ch);
}

// inbyte/outbyteのcsys68kからのラッパー関数 (mtk_asm.sでJSRされる関数)
char inbyte(int uart_ch) {
    // 戻り値はD0に格納される（アセンブリ側で処理）
    return inbyte_body(uart_ch);
}

void outbyte(unsigned char c, int uart_ch) {
    outbyte_body((char)c, uart_ch);
}
