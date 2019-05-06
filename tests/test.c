#include <stdint.h>

#include "math.h"
#include "libio.h"
#include "air.h"
// #include "dhrystone/dhrystone_main.h"
// #include "dhrystone/encoding.h"

#define LOAD_F0(value) __asm__ volatile("fmax.s f0, %0, %0" : : f (value))

volatile float a = 1.0f;
volatile float b = 2.0f;
volatile float c = 3.0f;
volatile float d = 4.0f;

const float one_hundred = 100.0f;

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

uint32_t rv_swap_csr_frm(uint32_t new_value) {
    uint32_t old_value;
    __asm__ volatile("csrrw %0, 0x002, %1" : "=r" (old_value) : "r" (new_value));
    return old_value;
}

uint32_t rv_swap_csr_vl(uint32_t new_value) {
    uint32_t old_value;
    __asm__ volatile("csrrw %0, 0xC20, %1" : "=r" (old_value) : "r" (new_value));
    return old_value;
}

void rv_load_f0_four(float *new_values) {
    register float* ptr __asm__ ("a0") = new_values;
    __asm__ volatile("flw f0, 0(a0)" : : "r" (ptr) : "f0");
    __asm__ volatile("flw f0, 4(a0)" : : "r" (ptr) : "f0");
    __asm__ volatile("flw f0, 8(a0)" : : "r" (ptr) : "f0");
    __asm__ volatile("flw f0, 12(a0)" : : "r" (ptr) : "f0");
}

float add(float a, float b) {
    return a + b;
}

// float rv_unload_fp() {

// }

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

    // GLOBAL_MEMEZ = 42;
    vfaddvv(2, 2, 32);

    float test_floats [4];
    test_floats[0] = 16.0f;
    test_floats[1] = 16.0f;
    test_floats[2] = 16.0f;
    test_floats[3] = 16.0f;

    rv_load_f0_four(test_floats);

    // LOAD_F0(123.123f);

    // float d = a + b;
    // float e = fsqrt(c);
    float temp = a / c * one_hundred;
    float temp2 = d - a;
    tiny_printf("Should be 3: %d,   33: %d,   3: %d\n", 
        (int) (a + b), 
        (int) temp,
        (int) temp2);

    // tiny_printf("Time: %u, Instructions: %d\n", time, instret);
    tiny_printf("Should be hello: %s\n", "hello");
    rv_ecall(1, 'a');
    tiny_printf("Should be 42: %d\n", GLOBAL_MEMEZ);

    uint32_t old_vl = rv_swap_csr_vl(16);
    uint32_t new_vl = rv_swap_csr_vl(1);
    tiny_printf("VL should be 1: %d, 16: %d\n", old_vl, new_vl);

    uint32_t old_frm = rv_swap_csr_frm(3);
    uint32_t new_frm = rv_swap_csr_frm(0);
    tiny_printf("FRM should be 0: %d, 3: %d\n", old_frm, new_frm);

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
