#include <iostream> // getline
#include <string.h> // strings
#include <sstream>
#include <fstream>
#include <unistd.h>
#include <fenv.h>   // rounding modes
#include <cmath>   // sqrt
#include <cstdlib> // abs

using namespace std;

int main(void) 
{
    int items, operation, n, i, op, mode;
    float a, b, y;
    string request;
    getline(cin, request);
    items = sscanf(request.c_str(), "%d %d\n", &operation, &n);
    //printf("%d, %x\n", operation, rand());
    
    op = operation;
    for (i=0; i<n; i++) {
        if (operation==5) op = rand()%5;
        a = rand();
        b = rand();
        mode = (rand())%4;

        a = *(float*)&a;
        b = *(float*)&b;

        switch(mode) {
            case 0: {
                fesetround(FE_TONEAREST);
                break;
            }
            case 1: {
                fesetround(FE_DOWNWARD);
                break;
            }
            case 2: {
                fesetround(FE_UPWARD);
                break;
            }
            case 3: {
                fesetround(FE_TOWARDZERO);
                break;
            }
        }

        switch (op) {
            case 0: {
                y = a + b;
                break;
            }
            case 1: {
                y = a - b;
                break;
            }
            case 2: {
                y = a * b;
                break;
            }
            case 3: {
                y = a/b;
                break;
            }
            case 4: {
                a = abs(a);
                b = (float)0x10000000;
                y = sqrt(a);
                break;
            }
        }

        printf("@%d %d_%d_%08x_%08x_%08x \n", i, mode, op, *(int*)&a, *(int*)&b, *(int*)&y);
    }

    return 0;
}