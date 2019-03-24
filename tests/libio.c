#include "libio.h"

#include <stdint.h>
#include <stdarg.h>

static const uint32_t dv[] = {
 // 4294967296      // 32 bit unsigned max
    1000000000,     // +0
     100000000,     // +1
      10000000,     // +2
       1000000,     // +3
        100000,     // +4
 //      65535      // 16 bit unsigned max     
         10000,     // +5
          1000,     // +6
           100,     // +7
            10,     // +8
             1,     // +9
};

static void xtoa(uint32_t x, const uint32_t *dp)
{
    char c;
    uint32_t d;
    if(x) {
        while(x < *dp) ++dp;
        do {
            d = *dp++;
            c = '0';
            while(x >= d) ++c, x -= d;
            _putchar(c);
        } while(!(d & 1));
    } else {
        _putchar('0');
    }
}

static void puth(uint32_t n)
{
    static const char hex[16] = { '0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F'};
    _putchar(hex[n & 0xf]);
}

void tiny_printf(char *format, ...)
{
    char c;
    uint32_t i;
    int32_t n;

    va_list a;
    va_start(a, format);
    while(c = *format++) {
        if(c == '%') {
            switch(c = *format++) {
            case 's':                       // String
                _putstring(va_arg(a, char*));
                break;
            case 'c':                       // Char
                _putchar(va_arg(a, int)); // char argument gets elevated to int
                break;
            // case 'd':                       // 16 bit Integer
            // case 'u':                       // 16 bit Unsigned
            //     i = va_arg(a, int);
            //     if(c == 'd' && i < 0) i = -i, _putchar('-');
            //     xtoa((unsigned)i, dv + 5);
            //     break;
            case 'd':                       // 32 bit Long
            case 'u':                       // 32 bit uNsigned loNg
                n = va_arg(a, int);
                if(c == 'd' &&  n < 0) {
                    n = -n;
                    _putchar('-');
                }
                xtoa((unsigned int) n, dv);
                break;
            case 'x':                       // 16 bit heXadecimal
                i = va_arg(a, int);
                puth(i >> 28);
                puth(i >> 24);
                puth(i >> 20);
                puth(i >> 16);
                puth(i >> 12);
                puth(i >> 8);
                puth(i >> 4);
                puth(i);
                break;
            case '\0':
                va_end(a); 
                return;
            default: 
                _putchar('%');
                _putchar(c);
                // goto bad_fmt;
            }
        } else if (c == '\0') {
            va_end(a);
            return;
        } else {
            _putchar(c);
        }
    }
    va_end(a);
}
