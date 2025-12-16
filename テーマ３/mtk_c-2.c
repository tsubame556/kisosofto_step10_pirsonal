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

/* 【追加】csys68kから呼ばれる入出力ラッパーの本体のプロトタイプ宣言 */
char inbyte_body(int uart_ch);
void outbyte_body(char c, int uart_ch);

/* mtk_c.h で extern 宣言されたグローバル変数*/
TCB_TYPE task_tab[NUMTASK + 1];
STACK_TYPE stacks[NUMTASK];
TASK_ID_TYPE ready;
TASK_ID_TYPE curr_task;
TASK_ID_TYPE new_task;
TASK_ID_TYPE next_task;
SEMAPHORE_TYPE semaphore[NUMSEMAPHORE];

/*p_body(ch):Pシステムコールの本体*/
void p_body(int ch)
{
	*(char*)0x00d00039='A';
    /*セマフォの値を減らす*/
    semaphore[ch].count--;

    /*セマフォが獲得できなければ(count < 0)、sleepを実行して休眠状態に*/
    if (semaphore[ch].count < 0){
        sleep(ch);
    }
	*(char*)0x00d00039='a';
	return;
}

/*v_body(ch):Vシステムコールの本体*/
void v_body(int ch)
{
	*(char*)0x00d00039='B';
    /*セマフォの値を増やす*/
    semaphore[ch].count++;

    /*count<=0ならば、まだタスクがあるのでwakeupを実行*/
    if (semaphore[ch].count <= 0) {
        wakeup(ch);
    }
	*(char*)0x00d00039='b';
	return;
}


/*sleep(ch):タスクを休眠状態にしてタスクスイッチ*/
void sleep(int ch){
	*(char*)0x00d00039='C';
    /*指定されたセマフォの待ち行列に、現在のタスクを追加*/
    addq(&semaphore[ch].task_list, curr_task);
    
    /*next_taskの更新 (最高優先度の実行可能タスクを選択)*/
    sched();
    
    /*タスクを切り替える*/
    swtch();
	*(char*)0x00d00039='c';
	return;
}

/*wakeup(ch):休眠状態のタスクを実行可能状態にする*/
void wakeup(int ch){
	*(char*)0x00d00039='D';
    TASK_ID_TYPE waiting_task;
    
    /*セマフォの待ち行列が空でないとき実行*/
    if(semaphore[ch].task_list != NULLTASKID){ // NULLTASKID = 0
        /*セマフォの待ち行列から先頭のタスクを取り除く*/
        waiting_task = removeq(&semaphore[ch].task_list);
        
        /*取り出したタスクを実行可能キュー(ready)に追加*/
        addq(&ready, waiting_task);
    }
	*(char*)0x00d00039='d';
	return;
}


void init_kernel(){
	*(char*)0x00d00039='E';
    int i;
    
    // TCBの初期化 (タスクID 1からNUMTASKまで、0番も便宜上初期化)
    for(i = 0; i <= NUMTASK; i++){
        task_tab[i].next = NULLTASKID;
        task_tab[i].status = 0; // 0: 未使用
        task_tab[i].priority = 0; // 初期値
        task_tab[i].stack_ptr = NULL; // 初期値
    }

    // readyキューの初期化
    ready = NULLTASKID;
    // 割り込みベクタの初期化 (mtk_c.h 依存)
    *(void **)0x00000084 = pv_handler;

    // セマフォの初期化
    for(i = 0; i < NUMSEMAPHORE; i++) {
        semaphore[i].count = 1;      /* 初期値1 (使用可能) */
        semaphore[i].task_list = NULLTASKID;
        semaphore[i].nst = 0;
    }
    // UARTセマフォも初期値1 (排他制御) のまま

	*(char*)0x00d00039='e';
	return;
}


void set_task(void (*func)()) {
	*(char*)0x00d00039='F';
    TASK_ID_TYPE new_task = NULLTASKID; // 初期値NULLTASKID
    int i;

    /* 1. タスク IDの決定 (空きスロット探索) */
    for(i = 1; i <= NUMTASK; i++) {
        /* status == 0 を未使用と仮定 */
        if (task_tab[i].status == 0) {
            new_task = i;
            break;
        }
    }
    
    // 空きスロットが見つからなかった場合
    if (new_task == NULLTASKID) {
        return;
    }

    /* 2. TCBの更新 */
    task_tab[new_task].task_addr = func;
    task_tab[new_task].status = 1; /* 1: 使用中/実行可能 */
    task_tab[new_task].priority = 0; // 優先度もここで設定されるべき
    
    /* 3. スタックの初期化 */
    task_tab[new_task].stack_ptr = init_stack(new_task);

    /* 4. キューへの登録 */
    addq(&ready, new_task);
	*(char*)0x00d00039='f';
	return;
}

void *init_stack(int id) {
    *(char*)0x00d00039='G';
    
    /* バイト単位で計算するために char* にキャスト */
    /* スタックの底 (一番大きいアドレス) */
    char *sp = (char *)&stacks[id - 1].sstack[STKSIZE]; 

    /* 1. initial PC (4 bytes) */
    /* char* なので単純に -4 で4バイト戻る */
    sp -= 4;
    *(int *)sp = (int)task_tab[id].task_addr;

    /* 2. initial SR (2 bytes) */
    /* char* なので -2 で2バイト戻る。これでPCの直前に隙間なく配置される */
    sp -= 2;
    *(short *)sp = 0x0000;
    
    /* 3. 15本のレジスタ (D0-D7, A0-A6) */
    /* 4バイト * 15本 = 60バイト */
    sp -= 60;
    
    /* 4. initial USP (4 bytes) */
    sp -= 4;
    *(int *)sp = (int)&stacks[id - 1].ustack[STKSIZE];

    /* 初期化完了時点のスタックポインタ(SSP)を返す */
    *(char*)0x00d00039='g'; 
    return (void *)sp;
}


void begin_sch() {
	*(char*)0x00d00039='H';
    /* 1. 最初のタスクの決定 */
    curr_task = removeq(&ready);

    /* 2. タイマの設定 */
    init_timer();

    /* 3. 最初のタスクの起動 */
    /* first_task()は、curr_taskのTCBからスタックポインタを取得し、
       スタックに積まれたレジスタ値を復元してタスクを開始する (戻ってこない) */
    first_task();
	*(char*)0x00d00039='h';
	return;
}


/* sched() : タスクのスケジュール関数 */
void sched() {
	*(char*)0x00d00039='I';
	TASK_ID_TYPE tid;
	
	tid = removeq(&ready);
	
	if (tid == NULLTASKID) {
	while (1);
	}
	
	next_task = tid;
	*(char*)0x00d00039='i';
	return;
}

/* addq() : タスクのキューの最後尾へのTCBの追加 */
void addq(TASK_ID_TYPE *head, TASK_ID_TYPE tid) {
	*(char*)0x00d00039='J';
	TASK_ID_TYPE p = *head;
	
	if (p == NULLTASKID) {
		*head = tid;
		task_tab[tid].next = NULLTASKID;
		return;
	}
	
	while (task_tab[p].next != NULLTASKID) {
		p = task_tab[p].next;
	}
	
	task_tab[p].next = tid;
	task_tab[tid].next = NULLTASKID;
	*(char*)0x00d00039='j';
	return;
}

/* removeq() : タスクのキューの先頭からのTCBの除去 */
TASK_ID_TYPE removeq(TASK_ID_TYPE *head) {
	*(char*)0x00d00039='K';

	TASK_ID_TYPE t = *head;
	
	if (t != NULLTASKID)*head = task_tab[t].next;
	*(char*)0x00d00039='k';	
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
