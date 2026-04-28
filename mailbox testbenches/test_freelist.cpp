#include "Vfreelist.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    Vfreelist* dut = new Vfreelist;
    VerilatedVcdC* vcd = new VerilatedVcdC;

    dut->trace(vcd, 99);
    vcd->open("freelist.vcd");

    dut->clk = 0;
    dut->rst = 1;

    // Reset for 2 cycles
    for (int i = 0; i < 4; i++) {
        dut->clk ^= 1; dut->eval(); vcd->dump(i);
    }
    dut->rst = 0;

    int t = 4;

    // PUSH initial values
    std::cout << "Pushing initial values:" << std::endl;
    for (int i = 0; i < 8; i++) {
        dut->push = 1;
        dut->push_data = i;

        dut->clk ^= 1; dut->eval(); vcd->dump(++t);
        dut->clk ^= 1; dut->eval(); vcd->dump(++t);
    }
    dut->push = 0;

    // POP a few values
    std::cout << "Popping values:" << std::endl;
    for (int i = 0; i < 4; i++) {
        dut->pop = 1;

        dut->clk ^= 1; dut->eval(); vcd->dump(++t);
        dut->clk ^= 1; dut->eval(); vcd->dump(++t);

        if (dut->pop_valid)
            std::cout << "Popped: " << int(dut->pop_data) << std::endl;
        else
            std::cout << "Nothing popped :(" << std::endl;
    }
    dut->pop = 0;

    // PUSH back a few values
    std::cout << "Pushing back values." << std::endl;
    for (int i = 100; i < 104; i++) {
        dut->push = 1;
        dut->push_data = i;

        dut->clk ^= 1; dut->eval(); vcd->dump(++t);
        dut->clk ^= 1; dut->eval(); vcd->dump(++t);
    }
    dut->push = 0;

    vcd->close();
    delete dut;
    return 0;
}
