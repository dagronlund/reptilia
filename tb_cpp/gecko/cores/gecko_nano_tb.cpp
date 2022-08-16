#include <stdlib.h>
#include <chrono>
#include <filesystem>
#include <iostream>
#include <fstream>
#include <string>

#include "Vgecko_nano.h"
#include "verilated_vcd_c.h"
#include "verilated.h"

template<class Module>
class Testbench {
  public:
    Module *dut;
    VerilatedVcdC *trace;
    unsigned long cycles;

    Testbench(void) {
        Verilated::traceEverOn(true);
        dut = new Module();
        trace = NULL;
        cycles = 0;
    }

    ~Testbench(void) {
        delete dut;
        if (trace != NULL) {
            trace->close();
            delete trace;
            trace = NULL;
        }
    }

    void openTrace(const char *vcdname) {
        if (trace == NULL) {
            trace = new VerilatedVcdC;
            dut->trace(trace, 99);
            trace->open(vcdname);
        }
    }

    void closeTrace(void) {
        if (trace != NULL) {
            trace->close();
            delete trace;
            trace = NULL;
        }
    }

    void reset() {
        dut->rst = 1;
        for (int i = 0; i < 20; i++) {
            this->tick();
        }
        dut->rst = 0;
    }

    void tick(void) {
        dut->clk = 1;
        dut->eval();
        if (trace != NULL) {
            trace->dump((vluint64_t) (10 * cycles + 5));
        }
        dut->clk = 0;
        dut->eval();
        if (trace != NULL) {
            trace->dump((vluint64_t) (10 * cycles + 10));
        }
        cycles++;
    }
};

int main(int argc, char **argv) {
    // Initialize Verilators variables
    Verilated::commandArgs(argc, argv);
    std::filesystem::create_directories("bin/");
    std::filesystem::create_directories("bin/debug/");

    bool debug = false;
    for (int i = 1; i < argc; i++) {
        std::string s = std::string(argv[i]);
        if (s == "--debug" || s == "-d") {
            printf("Debugging!!!\n\n\n");
            debug = true;
        }
    }

    std::ofstream trace_pc;
    std::ofstream trace_reg;

    if (debug) {
        trace_pc.open("bin/debug/trace_pc.log");
        trace_pc << "pc" << std::endl;
        trace_reg.open("bin/debug/trace_regs.log");
        trace_reg << "reg, addr" << std::endl;
    }

    const auto start_time = std::chrono::system_clock::now();
    Testbench<Vgecko_nano> *tb = new Testbench<Vgecko_nano>();
    tb->openTrace("bin/gecko_nano.vcd");
    tb->reset();

    tb->dut->tty_in_valid = 1;
    tb->dut->tty_out_ready = 1;

    // Tick the clock until we are done
    for (int i = 0; i < 100000; i++) {
        tb->tick();
        if (tb->dut->tty_out_valid) {
            char c = (char) tb->dut->tty_out_data;
            printf("%c", c);
        }
        if (debug) {
            int jump_valid = tb->dut->debug_info_jump_valid;
            int register_write = tb->dut->debug_info_register_write;
            int register_addr = tb->dut->debug_info_register_addr;
            int jump_address = tb->dut->debug_info_jump_address;
            int register_data = tb->dut->debug_info_register_data;

            if (jump_valid) {
                trace_pc << ">0x" << std::setfill('0') << std::hex << std::setw(8) << jump_address << std::endl;
            }

            if (register_write) {
                trace_reg << "0x" << std::setfill('0') << std::hex << std::setw(2) << register_addr << ", " <<
                             "0x" << std::setfill('0') << std::hex << std::setw(8) << register_data << std::endl;
            }
        }
        if (Verilated::gotFinish()) {
            printf("\nSimulator finished!\n");
            break;
        } else if (tb->dut->exit_flag) {
            if (tb->dut->error_flag) {
                printf("\nGecko error!\n");
            } else {
                for (int i = 0; i < 10; i++) {
                    tb->tick();
                }
                printf("\nGecko finished: %d!\n", tb->dut->exit_code);
            }
            break;
        }
    }

    if (debug) {
        trace_pc.close();
        trace_reg.close();
    }

    if (!Verilated::gotFinish() && !tb->dut->exit_flag) {
        printf("\nSimulator timed out!\n");
    }

    tb->tick();
    tb->closeTrace();

    auto elapsed = std::chrono::system_clock::now() - start_time;
    uint64_t duration = std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count();
    printf("%d cycles in %lld us\n", tb->cycles, duration);

    exit(EXIT_SUCCESS);
}