#include "../lib/libio.h"
#include "../lib/libmem.h"

int CONSTANT = 42;

char SRC_ARRAY[16];
char DEST_ARRAY[16];

int main(int argc, char **argv)
{
    tiny_printf("Should be hello: %s\n", "hello");
    tiny_printf("Should be c: %c\n", 'c');
    tiny_printf("Should be 0xABCD1234: 0x%x\n", 0xABCD1234);
    tiny_printf("Should be 5: %d\n", 5);
    tiny_printf("Should be 5: %u\n", 5);
    tiny_printf("Should be -5: %d\n", -5);
    tiny_printf("Should be 42: %d\n", CONSTANT);

    for (int i = 0; i < 16; i++)
    {
        SRC_ARRAY[i] = (char)i;
    }

    for (int start = 0; start < 16; start++)
    {
        for (int n = 0; n < (16 - start); n++)
        {
            memset(DEST_ARRAY, 0xAA, 16);
            memcpy(&DEST_ARRAY[start], &SRC_ARRAY[start], n);
            for (int i = 0; i < 16; i++)
            {
                if (i < start || i >= (start + n))
                {
                    if (DEST_ARRAY[i] != 0xAA)
                    {
                        tiny_printf("Memcpy overwrote wrong!");
                        return 1;
                    }
                }
                else
                {
                    if (DEST_ARRAY[i] != i)
                    {
                        tiny_printf("Memcpy copied wrong!");
                        return 1;
                    }
                }
            }
        }
    }

    tiny_printf("Done!");

    return 0;
}