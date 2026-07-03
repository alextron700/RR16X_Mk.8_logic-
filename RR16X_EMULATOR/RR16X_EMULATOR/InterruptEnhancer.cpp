#include "InterruptEnhancer.h"
#include <iostream>
InterruptEnhancer::InterruptEnhancer()
{
	interrupt_lines = {};
    interrupt_lines.resize(16);
    readableAddresses = { 0x07ff'fff5, 0x07ff'fff4 };
    writableAddresses = { 0x07ff'fff5 };
}
bool InterruptEnhancer::has_active_interrupt() const {
    // Check if any unmasked line is actively requesting attention
    for (size_t i = 0; i < interrupt_lines.size(); ++i) {
        if (interrupt_lines[i].is_pending && (mask_register & (1U << i))) {
            return true;
        }
    }
    return false;
}

uint32_t InterruptEnhancer::get_highest_priority_vector() const {
    // Loop from 0 to 7. The first pending one we find wins priority!
    for (size_t i = 0; i < interrupt_lines.size(); ++i) {
        if (interrupt_lines[i].is_pending && (mask_register & (1U << i))) {
            return interrupt_lines[i].vector_address;
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
    std::cerr<<"ERROR: ATTEMPTED TO WRITE TO READ-ONLY REGION";
    break;
    case 0x07FFFFF5:
        mask_register = value;
        break;
    default:
        // If the address doesn't match our registers, fall back to our safe base class alert
        return;
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
        // If the address doesn't match our registers, fall back to our safe base class alert
        return 0;
    }
}
void InterruptEnhancer::raise_interrupt(uint16_t line_number, uint32_t vector_address)
{ 
    if (line_number >= 16) return;

    interrupt_lines[line_number].is_pending = true;
    interrupt_lines[line_number].vector_address = vector_address;

    // Update the status register bit so the CPU can see it via memory
    status_register |= (1 << line_number);
}
void InterruptEnhancer::clear_interrupt(uint16_t line_number)
{
    if (line_number >= 16) return;

    interrupt_lines[line_number].is_pending = false;

    // Clear the corresponding bit in the status register
    status_register &= ~(1 << line_number);
}