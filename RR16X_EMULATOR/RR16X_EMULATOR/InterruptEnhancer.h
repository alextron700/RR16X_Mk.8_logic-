#pragma once
#include "AbstractPeripheral.h"
#include "bus.h"
#include <vector>

class InterruptEnhancer :
    public AbstractPeripheral
{
public:
    InterruptEnhancer(bus& memoryBus, uint32_t vectorTableBase = 0x0000FF00);

    ~InterruptEnhancer() = default;
    void write(uint32_t address, uint16_t value) override;
    uint16_t read(uint32_t address) override;
    void tick() override;

    // No longer takes a vector address - the vector is looked up from
    // memory (the vector table) at the moment it's needed, not baked
    // in at construction time.
    void raise_interrupt(uint16_t line_number);
    void clear_interrupt(uint16_t line_number);
    bool has_active_interrupt() const;
    uint32_t get_highest_priority_vector() const;

private:
    struct InterruptRequest {
        bool is_pending = false;
    };
    // Supports 16 hardware lines (0 is highest priority, 15 is lowest)
    std::vector<InterruptRequest> interrupt_lines;

    uint16_t status_register = 0;
    uint16_t mask_register = 0;      // all lines masked by default (safety fix)

    bus& memBus;
    uint32_t vecTableBase;
};