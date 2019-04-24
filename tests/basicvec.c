#include "libair/src/include/libair/air.h"

#define VLEN 4

int main(int argc, char** argv) {

  int test1[VLEN] = {1,1,1,1};
  int test2[VLEN] = {1,2,3,4};
  int x = 2;
  int y = 986;
  int z = 9;

  vsetvl(x, y, z);
}
