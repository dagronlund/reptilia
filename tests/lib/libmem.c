#include "libmem.h"

void *memcpy(void *dest, const void *src, size_t n)
{
    size_t mask = 3;
    size_t n_word = n & (~mask);
    for (size_t i = 0; i < n_word / 4; i++)
    {
        ((int *)dest)[i] = ((const int *)src)[i];
    }
    for (size_t i = n_word; i < n; i++)
    {
        ((char *)dest)[i] = ((const char *)src)[i];
    }
    // for (size_t i = 0; i < n; i++)
    // {
    //     ((char *)dest)[i] = ((const char *)src)[i];
    // }
    return dest;
}
void *memmove(void *dest, const void *src, size_t n)
{
    size_t mask = 3;
    size_t n_word = n & (~mask);
    // dest after src, copy backwards
    if ((size_t)dest > (size_t)src)
    {
        for (size_t i = n - 1; i >= n_word; i++)
        {
            ((char *)dest)[i] = ((const char *)src)[i];
        }
        for (size_t i = (n_word / 4) - 1; i >= 0; i--)
        {
            ((int *)dest)[i] = ((const int *)src)[i];
        }
    }
    // src after dest, copy forwards
    else
    {
        for (size_t i = 0; i < n_word / 4; i++)
        {
            ((int *)dest)[i] = ((const int *)src)[i];
        }
        for (size_t i = n_word; i < n; i++)
        {
            ((char *)dest)[i] = ((const char *)src)[i];
        }
    }
    return dest;
}

void *memset(void *s, int c, size_t n)
{
    size_t mask = 3;
    size_t n_word = n & (~mask);
    int c1 = c & 0xff;
    int c2 = (c1 << 8) | c1;
    int c4 = (c2 << 16) | c2;
    for (size_t i = 0; i < n_word / 4; i++)
    {
        ((int *)s)[i] = c4;
    }
    for (size_t i = n_word; i < n; i++)
    {
        ((char *)s)[i] = (char)c;
    }

    // for (size_t i = 0; i < n; i++)
    // {
    //     ((char *)s)[i] = (char)c;
    // }

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
