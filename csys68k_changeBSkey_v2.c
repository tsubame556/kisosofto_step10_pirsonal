extern void outbyte(unsigned char c, int uart_ch); // ポート指定引数 ch を追加
extern char inbyte(int uart_ch);                  // ポート指定引数 ch を追加
extern void outbyte_r(unsigned char c);           // inbyte/outbyteのラッパー関数 (mtk_asm.s内のGETSTRING/PUTSTRINGコールを使用する)

// Replace backspace keycode from '\x8' to BS defined as macro.
// #define BS '\x8'
#define XTBS '\x7f'
#define ASBS '\x8'

/* ファイルディスクリプタをRS232Cポート番号にマッピングする関数 */
int fd_to_uart_ch_read(int fd) {
    if (fd == 0 || fd == 3) {
        return 0; // 標準入力(0)とfd=3はポート0 (UART1)
    } else if (fd == 4) {
        return 1; // fd=4はポート1 (UART2)
    }
    return -1; // EBADF相当
}

int fd_to_uart_ch_write(int fd) {
    if (fd == 1 || fd == 2 || fd == 3) {
        return 0; // 標準出力(1), 標準エラー(2), fd=3はポート0 (UART1)
    } else if (fd == 4) {
        return 1; // fd=4はポート1 (UART2)
    }
    return -1; // EBADF相当
}

int read(int fd, char *buf, int nbytes)
{
  char c;
  int  i;
  int uart_ch = fd_to_uart_ch_read(fd); // fdからUARTチャンネルを決定

  if (uart_ch < 0) {
      /* エラー処理: EBADFに相当 (ここでは簡単のため0を返す) */
      return 0;
  }

  for (i = 0; i < nbytes; i++) {
    c = inbyte(uart_ch); // ポート指定付きinbyteを呼び出し

    if (c == '\r' || c == '\n'){ /* CR -> CRLF */
      outbyte('\r', uart_ch); // ポート指定付きoutbyteを呼び出し
      outbyte('\n', uart_ch); // ポート指定付きoutbyteを呼び出し
      *(buf + i) = '\n';

    } else if (c == XTBS){      /* backspace */
      if (i > 0){
        outbyte(ASBS, uart_ch); /* bs  */
        outbyte(' ', uart_ch);   /* spc */
        outbyte(ASBS, uart_ch); /* bs  */
        i--;
      }
      i--;
      continue;

    } else {
      outbyte(c, uart_ch); // ポート指定付きoutbyteを呼び出し
      *(buf + i) = c;
    }

    if (*(buf + i) == '\n'){
      return (i + 1);
    }
  }
  return (i);
}

int write (int fd, char *buf, int nbytes)
{
  int i, j;
  int uart_ch = fd_to_uart_ch_write(fd); // fdからUARTチャンネルを決定

  if (uart_ch < 0) {
      /* エラー処理: EBADFに相当 (ここでは簡単のため0を返す) */
      return 0;
  }

  for (i = 0; i < nbytes; i++) {
    if (*(buf + i) == '\n') {
      outbyte ('\r', uart_ch);          /* LF -> CRLF */ // ポート指定付きoutbyteを呼び出し
    }
    outbyte (*(buf + i), uart_ch); // ポート指定付きoutbyteを呼び出し
    for (j = 0; j < 300; j++);
  }
  return (nbytes);
}

// fcntl(): 簡易実装 (常にO_RDWRを返す)
#define F_GETFL 3 
#define O_RDWR 0x0002 

/* fcntl(): 簡易実装 (常にO_RDWRを返す) */
int fcntl(int fd, int cmd, ...)
{
    // 可変引数だがF_GETFLの場合は無視
    if (cmd == F_GETFL) {
        // 常に読み書き可能を返す
        return O_RDWR;
    }
    // その他は0を返す
    return 0;
}
