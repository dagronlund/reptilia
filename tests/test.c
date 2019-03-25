#include <stdint.h>

#include "libio.h"
#include "dhrystone/dhrystone_main.h"
#include "dhrystone/encoding.h"

int GLOBAL_ZERO = 0;
int GLOBAL_MEMEZ = 69;

void rv_ebreak(int status) {
    register int arg0 __asm__ ("a0") = status;
    __asm__ volatile("ebreak" : : "r" (arg0));
}

void rv_ecall(int func, int value) {
    register int arg0 __asm__ ("a0") = func;
    register int arg1 __asm__ ("a1") = value;
    __asm__ volatile("ecall" : : "r" (arg0), "r"(arg1));
}

void _putchar(char c) {
    rv_ecall(0, c);
}

void _putstring(char *s) {
    char c;
    while ((c = *s++) != '\0') {
        _putchar(c);
    }
}

int main() {
// #define rdtime() read_csr(time)
// #define rdcycle() read_csr(cycle)
// #define rdinstret() read_csr(instret)

    // uint32_t time = rdtime();
    // uint32_t instret = rdinstret();

    // tiny_printf("Time: %u, Instructions: %d\n", time, instret);
    // tiny_printf("Should be hello: %s\n", "hello");
    // tiny_printf("Should be c: %c\n", 'c');
    // tiny_printf("Should be 0xABCD1234: 0x%x\n", 0xABCD1234);
    // tiny_printf("Should be 5: %d\n", 5);
    // tiny_printf("Should be 5: %u\n", 5);
    // tiny_printf("Should be -5: %d\n", -5);
    // tiny_printf("Should be 69: %d\n", GLOBAL_MEMEZ);
    // return 0;
    return dhrystone_main();
}
