#pragma once
#include "AbstractPeripheral.h"
#include "InterruptEnhancer.h"
#include "bus.h"
class bus;
class DMA :
    public AbstractPeripheral
{
public:
    DMA(bus& system_bus, InterruptEnhancer& ie, uint32_t handler);
    uint16_t read(uint32_t address) override;
    void write(uint32_t address, uint16_t value) override;
    void tick() override;
private:
    bus& Bus;
    InterruptEnhancer& enhancer;
    uint32_t handler_address;
    uint32_t src_address = 0;
    uint32_t dest_address = 0;
    uint16_t count = 0;

};

