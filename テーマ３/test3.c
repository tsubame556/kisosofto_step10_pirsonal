#include <stdio.h>
#include "mtk_c.h"
#include <fcntl.h>
#include <stdarg.h>
#include <errno.h>

extern SEMAPHORE_TYPE semaphore[NUMSEMAPHORE];

FILE* com0in; 
FILE* com0out;
FILE* com1in;
FILE* com1out;

int fcntl(int fd, int cmd, ...){
	return cmd == F_GETFL ? O_RDWR : 0;
}

void task1(){
    while(1){

    }
}

void task2(){
    while(1){

    }
}

int main(void){
    char key_in;
    com0in	= fdopen(3, "r");
    com0out = fdopen(3, "w");
    com1in	= fdopen(4, "r");
    com1out = fdopen(4, "w");
    
    while(1){
        fscanf(com0in, "%c", &key_in);
        fprintf(com1out, "%c", key_in);
    }
    
    init_kernel();
    set_task(task1);
    set_task(task2);
    begin_sch();
    return 0;
}
