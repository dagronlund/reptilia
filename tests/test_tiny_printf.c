#include "libio.h"

#include <stdio.h>

int GLOBAL_MEMEZ = 69;

void _putchar(char c) {
    printf("%c", c);
}

void _putstring(char *s) {
    char c;
    while ((c = *s++) != '\0') {
        _putchar(c);
    }
}

int main(int argc, char **argv) {
    // tiny_printf("Should be hello: %s\n", "hello");
    // tiny_printf("Should be c: %c\n", 'c');
    // tiny_printf("Should be 0xABCD1234: 0x%x\n", 0xABCD1234);
    // tiny_printf("Should be 5: %d\n", 5);
    // tiny_printf("Should be 5: %u\n", 5);
    // tiny_printf("Should be -5: %d\n", -5);
    tiny_printf("Should be 69: %d\n", GLOBAL_MEMEZ);
    return 0;
}