#pragma once
#include "AbstractPeripheral.h"
#include "InterruptEnhancer.h"
class Timer :
    public AbstractPeripheral
{
private:
    InterruptEnhancer& enhancer;
    int16_t time = 0;
    uint32_t interruptAddr;
public:
    Timer(InterruptEnhancer &ie, uint32_t handler) : enhancer(ie) {
        interruptAddr = handler;
        readableAddresses = { 0x07ff'fffe };
    };
    void write(uint32_t address, uint16_t value) override;
    uint16_t read(uint32_t address) override;
    void tick() override;
};

