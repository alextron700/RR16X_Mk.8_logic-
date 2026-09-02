#include "InterruptEnhancer.h"
#include <iostream>

InterruptEnhancer::InterruptEnhancer(bus& memoryBus, uint32_t vectorTableBase)
    : memBus(memoryBus), vecTableBase(vectorTableBase)
{
    interrupt_lines.resize(16);
    readableAddresses = { 0x07ff'fff5, 0x07ff'fff4 };
    writableAddresses = { 0x07ff'fff5 };
}

bool InterruptEnhancer::has_active_interrupt() const {
    for (size_t i = 0; i < interrupt_lines.size(); ++i) {
        if (interrupt_lines[i].is_pending && (mask_register & (1U << i))) {
            return true;
        }
    }
    return false;
}

uint32_t InterruptEnhancer::get_highest_priority_vector() const {
    for (size_t i = 0; i < interrupt_lines.size(); ++i) {
        if (interrupt_lines[i].is_pending && (mask_register & (1U << i))) {
            // Pull the CURRENT vector straight from the table in memory.
            // Whatever program is running is responsible for having
            // written a real ISR address here before unmasking this line.
            return memBus.read(vecTableBase + (uint32_t)i);
        }
    }
    return 0x00000000; // Fallback vector
}

void InterruptEnhancer::tick()
{
    return;
}

void InterruptEnhancer::write(uint32_t address, uint16_t value)
{
    switch (address)
    {
    case 0x07FFFFF4:
        std::cerr << "ERROR: ATTEMPTED TO WRITE TO READ-ONLY REGION";
        break;
    case 0x07FFFFF5:
        mask_register = value;
        break;
    default:
        AbstractPeripheral::write(address, value);
    }
}

uint16_t InterruptEnhancer::read(uint32_t address)
{
    switch (address)
    {
    case 0x07FFFFF4:
        return status_register;
    case 0x07FFFFF5:
        return mask_register;
    default:
        return AbstractPeripheral::read(address);
    }
}

void InterruptEnhancer::raise_interrupt(uint16_t line_number)
{
    if (line_number >= 16) return;
    interrupt_lines[line_number].is_pending = true;
    status_register |= (1 << line_number);
}

void InterruptEnhancer::clear_interrupt(uint16_t line_number)
{
    if (line_number >= 16) return;
    interrupt_lines[line_number].is_pending = false;
    status_register &= ~(1 << line_number);
}