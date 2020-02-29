#include <stdio.h>
#include <stdint.h>
#include <fenv.h>
#include <math.h>

uint32_t isqrt_test(uint32_t num) {
    uint32_t res = 0;
    uint32_t bit = 1 << 30; // The second-to-top bit is set: 1 << 30 for 32 bits
 
    // "bit" starts at the highest power of four <= the argument.
    while (bit > num)
        bit >>= 2;
        
    while (bit != 0) {
        if (num >= res + bit) {
            num -= res + bit;
            res += bit << 1;
        }
        
        res >>= 1;
        bit >>= 2;
    }
    return res;
}

typedef struct {
    uint32_t sign;
    uint32_t exp;
    uint32_t mant;
} float_fields_t;

uint32_t create_mask(uint32_t bits) {
    if (bits >= 32) {
        return (uint32_t) -1;
    } else {
        return (1 << bits) - 1;
    }
}

uint32_t construct_float_bits(float_fields_t fields) {
    return ((fields.sign & create_mask(1)) << 31) | 
            ((fields.exp & create_mask(8)) << 23) | 
            (fields.mant & create_mask(23)); 
}

float_fields_t deconstruct_float_bits(uint32_t float_bits) {
    float_fields_t result;
    result.sign = (float_bits >> 31) & create_mask(1);
    result.exp = (float_bits >> 23) & create_mask(8);
    result.mant = (float_bits) & create_mask(23);
    return result;
}

void print_float_info(float_fields_t fields) {
    // Double check no field goes outside bounds
    fields.sign &= create_mask(1);
    fields.exp &= create_mask(8);
    fields.mant &= create_mask(23);

    if (fields.exp == 0x7F) {
        if (fields.mant != 0) {
            printf("NaN");
        } else {
            printf("%sInfinity", fields.sign ? "-" : "+");
        }
    } else {
        printf(fields.sign ? "-" : "+"); // Print Sign
        printf((fields.exp != 0) ? "1." : "0.");
        for (int i = 23; i >= 0; i--) {
            printf(((fields.mant >> i) & 0x1) ? "1" : "0");
        }
        printf("^(%d)\n", (fields.exp != 0) ? (fields.exp - 127) : (-126));
    }
}

uint32_t float_to_bits(float x) {
    return *(uint32_t*)&x;
}

float bits_to_float(uint32_t x) {
    return *(float*)&x;
}

void print_rounding_mode() {
    printf("current rounding method:    ");
    switch (fegetround()) {
           case FE_TONEAREST:  printf ("FE_TONEAREST");  break;
           case FE_DOWNWARD:   printf ("FE_DOWNWARD");   break;
           case FE_UPWARD:     printf ("FE_UPWARD");     break;
           case FE_TOWARDZERO: printf ("FE_TOWARDZERO"); break;
           default:            printf ("unknown");
    };
    printf("\n");
}

int main(int argc, char** argv) {
    
    float a = 1.0f;
    uint32_t a_int = float_to_bits(a);
    printf("%8x\n", a_int);
    a = bits_to_float(a_int);
    printf("%f\n", a);

    float_fields_t fields;
    fields.sign = 1;
    fields.exp = 0x0;
    fields.mant = 0xFFFFFFFF;

    // printf("%8x\n", construct_float_bits(fields));

    float b = NAN;//using the macro in math.h
    float inf_test = -INFINITY;

    float f = nanf("");//using the function version 

    // if (isnan(b)) {
    //     puts("b is a not a number!(NAN)\n");
    // }

    fields.sign = 0;
    fields.exp = 1;
    fields.mant = 0x10000;

    uint32_t bits = construct_float_bits(fields);
    
    print_float_info(fields);

    float fbits = bits_to_float(bits);
    float sqbits = sqrt(fbits);
    bits = float_to_bits(sqbits);


    fields = deconstruct_float_bits(bits);

    // printf("%8x\n", bits);
    printf("%8x\n", fields.sign);
    printf("%8x\n", fields.exp);
    printf("%8x\n", fields.mant);

    print_float_info(fields);

    printf("%8x\n", isqrt_test(1));
    printf("%8x\n", isqrt_test(4));
    printf("%8x\n", isqrt_test(20));
    printf("%8x\n", isqrt_test(-1));
    printf("%8x\n", isqrt_test(1<<30));

    // printf("args: %d\n", argc);

    // print_rounding_mode();
    // fesetround(FE_TONEAREST);
    // print_rounding_mode();
    // fesetround(FE_DOWNWARD);
    // print_rounding_mode();
    // fesetround(FE_UPWARD);
    // print_rounding_mode();
    // fesetround(FE_TOWARDZERO);
    // print_rounding_mode();

    return 0;
}
