// Derived from rustdv's shared Verilator host at commit
// 55beaf332ba1c56e80efb4a99409a688c4836973.
// rustdv is licensed under MIT OR Apache-2.0; see:
// https://github.com/rustdv/rustdv
//
// This host keeps the RTL and VPI event queues in lockstep. It also supports
// VCD or FST output when the corresponding Verilator trace mode is compiled.

#include "Vrustdv_dut.h"
#include "verilated.h"
#include "verilated_vpi.h"

#if VM_TRACE_VCD
#include "verilated_vcd_c.h"
#endif
#if VM_TRACE_FST
#include "verilated_fst_c.h"
#endif

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <memory>

extern "C" void (*vlog_startup_routines[])() VL_ATTR_WEAK;

namespace {
constexpr std::uint64_t kNoDeadline = std::numeric_limits<std::uint64_t>::max();
constexpr unsigned kSettleLimit = 100000;

bool settle(Vrustdv_dut& dut) {
    for (unsigned iteration = 0; iteration < kSettleLimit; ++iteration) {
        VerilatedVpi::doInertialPuts();
        VerilatedVpi::clearEvalNeeded();
        dut.eval();
        VerilatedVpi::callValueCbs();
        VerilatedVpi::callCbs(cbAtEndOfSimTime);
        VerilatedVpi::callCbs(cbReadWriteSynch);
        if (!VerilatedVpi::evalNeeded() && !VerilatedVpi::hasCbs(cbReadWriteSynch)) {
            VerilatedVpi::callCbs(cbReadOnlySynch);
            return true;
        }
    }
    std::fprintf(stderr, "rustdv: scheduler did not settle at time %llu\n",
                 static_cast<unsigned long long>(Verilated::time()));
    return false;
}
}

int main(int argc, char** argv, char**) {
    const std::unique_ptr<VerilatedContext> context{new VerilatedContext};
    context->threads(1);
    context->commandArgs(argc, argv);
    const std::unique_ptr<Vrustdv_dut> dut{new Vrustdv_dut{context.get(), ""}};

#if VM_TRACE_VCD
    std::unique_ptr<VerilatedVcdC> vcd;
    if (const char* path = std::getenv("RUSTDV_WAVE")) {
        context->traceEverOn(true);
        vcd = std::make_unique<VerilatedVcdC>();
        dut->trace(vcd.get(), 99);
        vcd->open(path);
    }
#endif
#if VM_TRACE_FST
    std::unique_ptr<VerilatedFstC> fst;
    if (const char* path = std::getenv("RUSTDV_WAVE")) {
        context->traceEverOn(true);
        fst = std::make_unique<VerilatedFstC>();
        dut->trace(fst.get(), 99);
        fst->open(path);
    }
#endif

    if (vlog_startup_routines) {
        for (auto routine = &vlog_startup_routines[0]; *routine; ++routine) (*routine)();
    }
    VerilatedVpi::callCbs(cbStartOfSimulation);

    bool ok = true;
    while (!context->gotFinish()) {
        VerilatedVpi::callTimedCbs();
        VerilatedVpi::callCbs(cbNextSimTime);
        VerilatedVpi::callCbs(cbAtStartOfSimTime);
        if (!settle(*dut)) { ok = false; break; }

#if VM_TRACE_VCD
        if (vcd) vcd->dump(context->time());
#endif
#if VM_TRACE_FST
        if (fst) fst->dump(context->time());
#endif
        if (context->gotFinish()) break;

        const std::uint64_t rtl_deadline =
            dut->eventsPending() ? dut->nextTimeSlot() : kNoDeadline;
        const std::uint64_t deadline =
            std::min(rtl_deadline, VerilatedVpi::cbNextDeadline());
        if (deadline == kNoDeadline) break;
        if (deadline < context->time()) { ok = false; break; }
        context->time(deadline);
    }

    dut->final();
    VerilatedVpi::callCbs(cbEndOfSimulation);
#if VM_TRACE_VCD
    if (vcd) vcd->close();
#endif
#if VM_TRACE_FST
    if (fst) fst->close();
#endif
    return ok ? 0 : 1;
}
