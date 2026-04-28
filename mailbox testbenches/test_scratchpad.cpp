#include "Vscratchpad.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
	
	Verilated::traceEverOn(true);


    Vscratchpad* dut = new Vscratchpad;
    VerilatedVcdC* vcd = new VerilatedVcdC;

    dut->trace(vcd, 99);
    vcd->open("scratchpad.vcd");

    dut->clk = 0;
    dut->rst = 1;

    // Reset for 2 cycles
    for (int i = 0; i < 4; i++) {
        dut->clk ^= 1;
        dut->eval();
        vcd->dump(i);
    }
    dut->rst = 0;

    int t = 4;

    // Write test
    std::cout << "Writing values to scratchpad..." << std::endl;
    for (int i = 0; i < 8; i++) {
        dut->we = 1;
        dut->waddr = i;
        dut->wdata = 100 + i;
        dut->clk ^= 1; dut->eval(); vcd->dump(++t);
        dut->clk ^= 1; dut->eval(); vcd->dump(++t);
    }
    dut->we = 0;

    // Read test
    std::cout << "Reading values back..." << std::endl;
    for (int i = 0; i < 8; i++) {
        dut->re = 1;
        dut->raddr = i;
        dut->clk ^= 1; dut->eval(); vcd->dump(++t);
        dut->clk ^= 1; dut->eval(); vcd->dump(++t);

        if (dut->rvalid)
            std::cout << "Read[" << i << "] = " << dut->rdata << std::endl;
        else
            std::cout << "Read[" << i << "] no valid data??" << std::endl;
    }

    vcd->close();
    delete dut;
    return 0;
}
