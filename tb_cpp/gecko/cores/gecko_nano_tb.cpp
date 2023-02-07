#include <stdlib.h>
#include <chrono>
#include <filesystem>
#include <iostream>
#include <fstream>
#include <iterator>
#include <vector>
#include <string>

#include "Vgecko_nano.h"
#include "Vgecko_nano_gecko_nano_wrapper.h"
#include "Vgecko_nano_gecko_nano__M10_TBz2_TCz3.h"
#include "Vgecko_nano_gecko_core__pi2.h"
#include "Vgecko_nano_gecko_decode__pi8.h"
#include "Vgecko_nano_mem_sequential_double__pi1.h"
#include "Vgecko_nano_xilinx_block_ram_double__pi3.h"
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

    std::string program_path = std::string("");
    bool debug = false;
    for (int i = 1; i < argc; i++) {
        std::string s = std::string(argv[i]);
        if (s == "--debug" || s == "-d") {
            debug = true;
        }
        if (s == "--binary" || s == "-b") {
            if (i + 1 < argc) {
                program_path = std::string(argv[i + 1]);
                i++;
            }
        }
    }

    if (program_path == "") {
        printf("No program given!\n");
        return 1;
    }

    std::ifstream program_input(program_path, std::ios::binary);
    std::vector<unsigned char> program_buffer(
            std::istreambuf_iterator<char>(program_input), {});

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

    int memory_address_width = tb->dut->gecko_nano_wrapper->inst->mem->gen_xilinx__DOT__xilinx_block_ram_double_inst->ADDR_WIDTH;
    int memory_data_width = tb->dut->gecko_nano_wrapper->inst->mem->gen_xilinx__DOT__xilinx_block_ram_double_inst->DATA_WIDTH;

    int memory_bytes = (1 << memory_address_width) * (memory_data_width / 8);

    if (program_buffer.size() > memory_bytes) {
        printf("Program will not fit in memory!\n");
        return 1;
    }

    // Load program into memory
    for (int i = 0; i < (program_buffer.size() / 4); i += 1) {
        uint32_t word = program_buffer[(i * 4) + 0] |
                       (program_buffer[(i * 4) + 1] << 8) |
                       (program_buffer[(i * 4) + 2] << 16) |
                       (program_buffer[(i * 4) + 3] << 24);
        tb->dut->gecko_nano_wrapper->inst->mem->gen_xilinx__DOT__xilinx_block_ram_double_inst->data[i] = word;
    }

    // Tick the clock until we are done
    for (int i = 0; i < 100000; i++) {
        tb->tick();
        if (tb->dut->tty_out_valid) {
            char c = (char) tb->dut->tty_out_data;
            printf("%c", c);
        }
        if (debug) {
            int jump_valid = tb->dut->gecko_nano_wrapper->inst->core->gecko_decode_inst->debug_jump_valid;
            int register_write = tb->dut->gecko_nano_wrapper->inst->core->gecko_decode_inst->debug_register_write;
            int register_addr = tb->dut->gecko_nano_wrapper->inst->core->gecko_decode_inst->debug_register_addr;
            int jump_address = tb->dut->gecko_nano_wrapper->inst->core->gecko_decode_inst->debug_jump_address;
            int register_data = tb->dut->gecko_nano_wrapper->inst->core->gecko_decode_inst->debug_register_data;

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
    printf("%lu cycles in %lld us\n", tb->cycles, duration);

    exit(EXIT_SUCCESS);
}