#ifndef __RISCV_TEST_H
#define __RISCV_TEST_H

#define RVTEST_RV32U
#define RVTEST_CODE_BEGIN \
    .section .text.start; \
    .globl _start; \
    _start:
#define RVTEST_CODE_END
#define RVTEST_DATA_BEGIN
#define RVTEST_DATA_END

#define TESTNUM gp

#define RVTEST_PASS \
    csrwi 0x800, 0; \
    ebreak;

#define RVTEST_FAIL \
    csrwi 0x800, 1; \
    ebreak;

#endif