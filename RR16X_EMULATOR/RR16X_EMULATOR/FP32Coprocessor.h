#pragma once
#include "AbstractPeripheral.h"
class FP32Coprocessor :
    public AbstractPeripheral
{
public:
    FP32Coprocessor() {
        readableAddresses = { 0x07ff'ffd5, 0x07ff'ffd6 };
        writableAddresses = { 0x07ff'ffd0, 0x07ff'ffd1, 0x07ff'ffd2, 0x07ff'ffd3, 0x07ff'ffd4 };
    };
    uint16_t read(uint32_t address) override;
    void write(uint32_t address, uint16_t value) override;
    void tick() override;
private:
    uint16_t ALow = 0;
    int16_t AHigh = 0;
    uint16_t BLow = 0;
    int16_t BHigh = 0;
    int16_t command = 0;
    uint16_t outLow = 0;
    int16_t outHigh = 0;
};

