#include "Vrefcount_mem.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>

static void tick(Vrefcount_mem* dut, VerilatedVcdC* vcd, int& t) {
    dut->clk = 0; dut->eval(); vcd->dump(t++);
    dut->clk = 1; dut->eval(); vcd->dump(t++);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    auto* dut = new Vrefcount_mem;

    auto* vcd = new VerilatedVcdC;
    dut->trace(vcd, 99);
    vcd->open("refcount.vcd");

    int t = 0;

    // Reset
    dut->rst = 1;
    dut->inc = 0;
    dut->dec = 0;
    dut->inc_slot = 0;
    dut->dec_slot = 0;

    tick(dut, vcd, t);
    tick(dut, vcd, t);
    dut->rst = 0;

    std::cout << "Increment slot 5 twice\n";
    dut->inc = 1; dut->inc_slot = 5; tick(dut, vcd, t);
    dut->inc = 1; dut->inc_slot = 5; tick(dut, vcd, t);
    dut->inc = 0; tick(dut, vcd, t);

    std::cout << "Decrement slot 5 once\n";
    dut->dec = 1; dut->dec_slot = 5; tick(dut, vcd, t);
    if (dut->free_valid) {
        std::cerr << "ERROR: freed too early\n";
        return 1;
    }

    std::cout << "Decrement slot 5 again\n";
    dut->dec = 1; dut->dec_slot = 5; tick(dut, vcd, t);
    if (!dut->free_valid || dut->free_slot != 5) {
        std::cerr << "ERROR: expected free slot 5\n";
        return 1;
    }

    dut->dec = 0;
    tick(dut, vcd, t);

    std::cout << "Refcount test PASS\n";

    vcd->close();
    delete vcd;
    delete dut;
    return 0;
}
