#pragma once
#include "AbstractPeripheral.h"
class Multiplier :
    public AbstractPeripheral
{
public:
    Multiplier() {
        readableAddresses = { 0x07ff'fffb,0x07ff'fffa };
        writableAddresses = { 0x07ff'fffc,0x07ff'fffd };
    }
    void multiplySigned(int16_t x, int16_t y);
    void multiplyUnsigned(uint16_t x, uint16_t y);
    uint16_t read(uint32_t address);
    void write(uint32_t address, uint16_t value);
    void tick();
private:
    uint16_t outLow = 0;
    uint16_t outHigh = 0;
    uint16_t a = 0;
    uint16_t b = 0;
};

