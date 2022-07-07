#include "../lib/libio.h"

int CONSTANT = 42;

int main(int argc, char **argv)
{
    tiny_printf("Should be hello: %s\n", "hello");
    tiny_printf("Should be c: %c\n", 'c');
    tiny_printf("Should be 0xABCD1234: 0x%x\n", 0xABCD1234);
    tiny_printf("Should be 5: %d\n", 5);
    tiny_printf("Should be 5: %u\n", 5);
    tiny_printf("Should be -5: %d\n", -5);
    tiny_printf("Should be 42: %d\n", CONSTANT);
    return 0;
}