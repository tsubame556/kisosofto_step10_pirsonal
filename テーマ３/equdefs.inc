
/******************************************************/
/* 各種レジスタ定義
/******************************************************/
*******************
** レジスタ群の先頭
*******************
.equ REGBASE, 0xFFF000 | DMAP を使用．
.equ IOBASE,  0x00d00000

*************************
** 割り込み関係のレジスタ
*************************
.equ IVR, REGBASE+0x300 | 割り込みベクタレジスタ
.equ IMR, REGBASE+0x304 | 割り込みマスクレジスタ
.equ ISR, REGBASE+0x30c | 割り込みステータスレジスタ
.equ IPR, REGBASE+0x310 | 割り込みペンディングレジスタ

***********************
** タイマ関係のレジスタ
***********************
.equ TCTL1,  REGBASE+0x600 | タイマ１コントロールレジスタ
.equ TPRER1, REGBASE+0x602 | タイマ１プリスケーラレジスタ
.equ TCMP1,  REGBASE+0x604 | タイマ１コンペアレジスタ
.equ TCN1,   REGBASE+0x608 | タイマ１カウンタレジスタ
.equ TSTAT1, REGBASE+0x60a | タイマ１ステータスレジスタ

********************************
** UART1（送受信）関係のレジスタ
********************************
.equ USTCNT1, REGBASE+0x900 | UART1 ステータス/コントロールレジスタ
.equ UBAUD1,  REGBASE+0x902 | UART1 ボーコントロールレジスタ
.equ URX1,    REGBASE+0x904 | UART1 受信レジスタ
.equ UTX1,    REGBASE+0x906 | UART1 送信レジスタ

********************************
** UART2（送受信）関係のレジスタ
********************************
.equ USTCNT2, REGBASE+0x910 | UART2 ステータス/コントロールレジスタ
.equ UBAUD2,  REGBASE+0x912 | UART2 ボーコントロールレジスタ
.equ URX2,    REGBASE+0x914 | UART2 受信レジスタ
.equ UTX2,    REGBASE+0x916 | UART2 送信レジスタ




***********
** LED
***********
.equ LED7, IOBASE+0x000002f | ボード搭載の LED 用レジスタ
.equ LED6, IOBASE+0x000002d | 使用法については付録 A.4.3.1
.equ LED5, IOBASE+0x000002b
.equ LED4, IOBASE+0x0000029
.equ LED3, IOBASE+0x000003f
.equ LED2, IOBASE+0x000003d
.equ LED1, IOBASE+0x000003b
.equ LED0, IOBASE+0x0000039

.equ     top,    0
.equ     bottom, 255
.equ     in,     256
.equ     out,    260
.equ     s,      264
.equ     Q_SIZE, 266
/* キューの各先頭アドレスを EQU でシンボル化 */
.equ    Q0_START, 0x5000   |キュー#0の先頭アドレスを設定
.equ    Q_BASE, Q0_START   |2つのキュー構造体全体が配置されている



***************
** システムコール番号
***************
.equ SYSCALL_NUM_GETSTRING,   1
.equ SYSCALL_NUM_PUTSTRING,   2
.equ SYSCALL_NUM_RESET_TIMER, 3
.equ SYSCALL_NUM_SET_TIMER,   4
.equ SYSCALL_NUM_SET_SKIPMT,  5

