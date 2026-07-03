#pragma once
#include "AbstractPeripheral.h"
#include <vector>
class InterruptEnhancer :
    public AbstractPeripheral
{
public: 
    InterruptEnhancer();
    
    ~InterruptEnhancer() = default;
    void write(uint32_t address, uint16_t value) override;
    uint16_t read(uint32_t address) override;
    void tick() override;

    void raise_interrupt(uint16_t line_number, uint32_t vector_address);
    void clear_interrupt(uint16_t line_number);

    bool has_active_interrupt() const;
    uint32_t get_highest_priority_vector() const;

private:
    // Simple structure to keep track of pending requests
    struct InterruptRequest {
        bool is_pending = false;
        uint32_t vector_address = 0;
    };

    // Supports 8 hardware lines (0 is highest priority, 7 is lowest)
    std::vector<InterruptRequest> interrupt_lines;

    // Internal registers mapped to memory space (e.g., status, masks)
    uint16_t status_register = 0;
    uint16_t mask_register = 0xFFFF; // All lines enabled by default
};