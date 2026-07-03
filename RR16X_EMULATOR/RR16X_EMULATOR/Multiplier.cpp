#include "Multiplier.h"
#include <iostream>

void Multiplier::multiplySigned(int16_t x, int16_t y)
{
    // Sign-extend to 32-bit to capture full product correctly
    int32_t z = static_cast<int32_t>(x) * static_cast<int32_t>(y);
    outLow = z & 0xFFFF;
    outHigh = (z >> 16) & 0xFFFF;
}

void Multiplier::multiplyUnsigned(uint16_t x, uint16_t y)
{
    // Force absolute unsigned calculations via casting
    uint32_t z = static_cast<uint32_t>(static_cast<uint16_t>(x)) *
        static_cast<uint32_t>(static_cast<uint16_t>(y));
    outLow = z & 0xFFFF;
    outHigh = (z >> 16) & 0xFFFF;
}
void Multiplier::tick()
{
    return;
}
uint16_t Multiplier::read(uint32_t address)
{
    switch (address)
    {
    case 0x07ff'fffb:
        return outLow;
    case 0x07ff'fffa:
        return outHigh;
    default:
        return 0;
    }
}

void Multiplier::write(uint32_t address, uint16_t value)
{
    switch (address)
    {
    case 0x07ff'fffd:
        a = value;
        // Trigger Signed calculation whenever register 'a' is populated
        multiplySigned(a, b);
        break;
    case 0x07ff'fffc:
        b = value;
        // Trigger Unsigned calculation whenever register 'b' is populated
        multiplyUnsigned(a, b);
        break;
    default:
        //AbstractPeripheral::write(address, value);
        break;
    }
}