#include "libio.h"

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
    tiny_printf("Stuff: %d\n", GLOBAL_MEMEZ);
    return 0;
}
