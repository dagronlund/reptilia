#include <stdint.h>

#include "math.h"
#include "libio.h"
// #include "dhrystone/dhrystone_main.h"
// #include "dhrystone/encoding.h"

volatile float a = 1.0f;
volatile float b = 2.0f;
volatile float c = 3.0f;
volatile float d = 4.0f;

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

    GLOBAL_MEMEZ = 42;

    // float d = a + b;
    // float e = fsqrt(c);
    tiny_printf("Should be 3: %d, 2: %d\n", (int) (a + b), (int) (a / c * 100.0f));

    // tiny_printf("Time: %u, Instructions: %d\n", time, instret);
    tiny_printf("Should be hello: %s\n", "hello");
    rv_ecall(1, 'a');
    tiny_printf("Should be 42: %d\n", GLOBAL_MEMEZ);
    // tiny_printf("Should be c: %c\n", 'c');
    // tiny_printf("Should be 0xABCD1234: 0x%x\n", 0xABCD1234);
    // tiny_printf("Should be 5: %d\n", 5);
    // tiny_printf("Should be 5: %u\n", 5);
    // tiny_printf("Should be -5: %d\n", -5);
    /// tiny_printf("Should be 69: %d\n", GLOBAL_MEMEZ);
    // *((int*)0x0) = 0x69;
    return 0;
    // return dhrystone_main();
}
