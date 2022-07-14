#include "libmem.h"

void *memcpy(void *dest, const void *src, size_t n)
{
    if ((((size_t)dest) & 3) == (((size_t)src) & 3) && n > 8)
    {
        size_t unaligned = ((size_t)dest) & 3;
        size_t dest_aligned = ((size_t)dest) & ~((size_t)3);
        size_t src_aligned = ((size_t)src) & ~((size_t)3);
        // Initial unaligned copy of 0-4 bytes
        switch (unaligned)
        {
        case 0:
            ((char *)dest_aligned)[0] = ((const char *)src_aligned)[0];
        case 1:
            ((char *)dest_aligned)[1] = ((const char *)src_aligned)[1];
        case 2:
            ((char *)dest_aligned)[2] = ((const char *)src_aligned)[2];
        case 3:
            ((char *)dest_aligned)[3] = ((const char *)src_aligned)[3];
        default:
            break;
        }
        // Main aligned copy with words
        size_t n_offset = n + unaligned;
        size_t n_aligned = (n_offset & ~((size_t)3));
        for (size_t i = 1; i < n_aligned / 4; i++)
        {
            ((int *)dest_aligned)[i] = ((const int *)src_aligned)[i];
        }
        // Final copy of bytes (0-3) bytes
        for (size_t i = n_aligned; i < n_offset; i++)
        {
            ((char *)dest_aligned)[i] = ((const char *)src_aligned)[i];
        }
    }
    else
    {
        // The src and dest have different alignments, give up and do it naively
        for (size_t i = 0; i < n; i++)
        {
            ((char *)dest)[i] = ((const char *)src)[i];
        }
    }
    return dest;
}
void *memmove(void *dest, const void *src, size_t n)
{
    size_t mask = 3;
    size_t n_word = n & (~mask);
    // dest after src, copy backwards
    if ((size_t)dest > (size_t)src)
    {
        for (size_t i = n - 1; i >= 0; i++)
        {
            ((char *)dest)[i] = ((const char *)src)[i];
        }
    }
    // src after dest, copy forwards
    else
    {
        for (size_t i = 0; i < n; i++)
        {
            ((char *)dest)[i] = ((const char *)src)[i];
        }
    }
    return dest;
}

void *memset(void *s, int c, size_t n)
{
    for (size_t i = 0; i < n; i++)
    {
        ((char *)s)[i] = (char)c;
    }
    return s;
}

int memcmp(const void *s1, const void *s2, size_t n)
{
    unsigned char diff;
    for (size_t i = 0; i < n; i++)
    {
        if ((diff = ((const char *)s1)[i] - ((const char *)s2)[i]))
            return (int)diff;
    }
    return 0;
}
