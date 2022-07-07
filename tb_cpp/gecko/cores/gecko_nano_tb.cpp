#include <stdlib.h>
#include <chrono>
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
    const auto start_time = std::chrono::system_clock::now();
    Testbench<Vgecko_nano> *tb = new Testbench<Vgecko_nano>();
    tb->openTrace("gecko_nano.vcd");
    tb->reset();

    tb->dut->print_out_ready = 1;

    // Tick the clock until we are done
    for (int i = 0; i < 1000000; i++) {
        tb->tick();
        if (tb->dut->print_out_valid) {
            char c = (char) tb->dut->print_out_data;
            printf("%c", c);
        }
        if (Verilated::gotFinish()) {
            printf("\nSimulator finished!\n");
            break;
        } else if (tb->dut->finished_flag) {
            printf("\nGecko finished!\n");
            break;
        } else if (tb->dut->faulted_flag) {
            printf("\nGecko faulted!\n");
            break;
        }
    }

    if (!Verilated::gotFinish() && !tb->dut->finished_flag && !tb->dut->faulted_flag) {
        printf("\nSimulator timed out!\n");
    }

    tb->tick();
    tb->closeTrace();

    auto elapsed = std::chrono::system_clock::now() - start_time;
    uint64_t duration = std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count();
    printf("%d cycles in %lld us\n", tb->cycles, duration);

    exit(EXIT_SUCCESS);
}