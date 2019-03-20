#include "libmem.h"

void *memcpy(void *dest, const void *src, size_t n) {
    for(size_t i = 0; i < n; i++) {
        ((char *)dest)[i] = ((const char *)src)[i];
    }

    return dest;
}
void *memmove(void *dest, const void *src, size_t n) {
    //dest after src, copy backwards
    if((size_t)dest > (size_t)src) {
        for(size_t i = n-1; i >= 0; i--) {
            ((char *)dest)[i] = ((const char *)src)[i];
        }
    }
    //src after dest, copy forwards
    else {
        for(size_t i = 0; i < n; i++) {
            ((char *)dest)[i] = ((const char *)src)[i];
        }
    }
    return dest;
}

void *memset(void *s, int c, size_t n){
    for(size_t i = 0; i < n; i++) {
        ((char *)s)[i] = (char)c;
    }
    
    return s;
}

int memcmp(const void *s1, const void *s2, size_t n) {
    unsigned char diff;
    for(size_t i = 0; i < n; i++) {
        if((diff = ((const char *)s1)[i] - ((const char *)s2)[i]))
            return (int)diff;
    }
    
    return 0;
}
