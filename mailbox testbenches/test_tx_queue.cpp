#include "Vtx_queue.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <cstdint>

static void tick(Vtx_queue* dut, VerilatedVcdC* vcd, int& t) {
    dut->clk = 0; dut->eval(); vcd->dump(t++);
    dut->clk = 1; dut->eval(); vcd->dump(t++);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    auto* dut = new Vtx_queue;
    auto* vcd = new VerilatedVcdC;
    dut->trace(vcd, 99);
    vcd->open("tx_queue.vcd");

    int t = 0;

    // Reset
    dut->rst = 1;
    dut->enq = 0;
    dut->deq = 0;
    dut->enq_data = 0;
    tick(dut, vcd, t);
    tick(dut, vcd, t);
    dut->rst = 0;

    // put {dest, len, slot} into DATA_W bits
    auto pack = [](uint8_t dest, uint8_t slot, uint8_t len) -> uint32_t {
        // DATA_W=4+8+8=20 bits by default
        return (uint32_t(dest) << 16) | (uint32_t(len) << 8) | uint32_t(slot);
    };

    std::cout << "Enqueue 0 to 5 (dest=0, slot=i, len=20+i)" << std::endl;
    for (int i = 0; i < 6; i++) {
        dut->enq = 1;
        dut->enq_data = pack(0, uint8_t(i), uint8_t(20 + i));
        tick(dut, vcd, t);
    }
    dut->enq = 0;

    std::cout << "Dequeue 3" << std::endl;
    for (int i = 0; i < 3; i++) {
        dut->deq = 1;
        tick(dut, vcd, t);

        if (!dut->deq_valid) {
            std::cerr << "ERROR: expected deq_valid\n";
            return 1;
        }

        uint32_t got = dut->deq_data;
        uint8_t slot = got & 0xFF;
        uint8_t len  = (got >> 8) & 0xFF;
        uint8_t dest = (got >> 16) & 0x0F;

        std::cout << "Got dest=" << int(dest)
                  << " slot=" << int(slot)
                  << " len=" << int(len) << "\n";

        if (dest != 0 || slot != i || len != 20 + i) {
            std::cerr << "ERROR: mismatch\n";
            return 1;
        }
    }
    dut->deq = 0;

    std::cout << "Enqueue 2 more (dest=1, slot=100to101, len=60to61)" << std::endl;
    for (int i = 0; i < 2; i++) {
        dut->enq = 1;
        dut->enq_data = pack(1, uint8_t(100 + i), uint8_t(60 + i));
        tick(dut, vcd, t);
    }
    dut->enq = 0;

    std::cout << "Dequeue until empty" << std::endl;
    while (!dut->empty) {
        dut->deq = 1;
        tick(dut, vcd, t);
        if (dut->deq_valid) {
            uint32_t got = dut->deq_data;
            uint8_t slot = got & 0xFF;
            uint8_t len  = (got >> 8) & 0xFF;
            uint8_t dest = (got >> 16) & 0x0F;
            std::cout << "Got dest=" << int(dest)
                      << " slot=" << int(slot)
                      << " len=" << int(len) << "\n";
        }
    }
    dut->deq = 0;

    std::cout << "TX queue test PASS\n";

    vcd->close();
    delete dut;
    delete vcd;
    return 0;
}
