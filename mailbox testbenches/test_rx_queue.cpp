#include "Vrx_queue.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <cstdint>

static void tick(Vrx_queue* dut, VerilatedVcdC* vcd, int& t) {
    dut->clk = 0; dut->eval(); vcd->dump(t++);
    dut->clk = 1; dut->eval(); vcd->dump(t++);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    auto* dut = new Vrx_queue;
    auto* vcd = new VerilatedVcdC;
    dut->trace(vcd, 99);
    vcd->open("rx_queue.vcd");

    int t = 0;

    // Reset
    dut->rst = 1;
    dut->enq = 0;
    dut->deq = 0;
    dut->enq_data = 0;
    tick(dut, vcd, t);
    tick(dut, vcd, t);
    dut->rst = 0;

    // Helper: pack descriptor = {len, slot}
    auto pack = [](uint8_t slot, uint8_t len) -> uint16_t {
        return (uint16_t(len) << 8) | uint16_t(slot);
    };

    std::cout << "Enqueue 0 to 7 (slot=i, len=10+i) " << std::endl;
    for (int i = 0; i < 8; i++) {
        dut->enq = 1;
        dut->enq_data = pack(uint8_t(i), uint8_t(10 + i));
        tick(dut, vcd, t);
    }
    dut->enq = 0;

    std::cout << "Dequeue 4 " << std::endl;
    for (int i = 0; i < 4; i++) {
        dut->deq = 1;
        tick(dut, vcd, t); // output becomes valid this cycle (registered on posedge)
        // After tick(), deq_valid should be 1 if queue wasn't empty
        if (!dut->deq_valid) {
            std::cerr << "ERROR: expected deq_valid=1\n";
            return 1;
        }
        uint16_t got = dut->deq_data;
        uint8_t slot = got & 0xFF;
        uint8_t len  = (got >> 8) & 0xFF;
        std::cout << "Got slot=" << int(slot) << " len=" << int(len) << "\n";
        if (slot != i || len != 10 + i) {
            std::cerr << "ERROR: mismatch\n";
            return 1;
        }
    }
    dut->deq = 0;

    std::cout << "Enqueue 2 more (slot=100 to 101) " << std::endl;
    for (int i = 0; i < 2; i++) {
        dut->enq = 1;
        dut->enq_data = pack(uint8_t(100 + i), uint8_t(50 + i));
        tick(dut, vcd, t);
    }
    dut->enq = 0;

    std::cout << "Dequeue until empty" << std::endl;
    while (!dut->empty) {
        dut->deq = 1;
        tick(dut, vcd, t);
        if (dut->deq_valid) {
            uint16_t got = dut->deq_data;
            uint8_t slot = got & 0xFF;
            uint8_t len  = (got >> 8) & 0xFF;
            std::cout << "Got slot=" << int(slot) << " len=" << int(len) << "\n";
        }
    }
    dut->deq = 0;

    std::cout << "Rx_queue test pass\n";

    vcd->close();
    delete dut;
    delete vcd;
    return 0;
}
