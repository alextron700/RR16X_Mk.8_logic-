#pragma once
#include "AbstractPeripheral.h"
#include "InterruptEnhancer.h"
#include <queue>
class UART :
    public AbstractPeripheral
{
public:
    UART(InterruptEnhancer& ie,uint32_t IVA);

    // Overrides from AbstractPeripheral
    uint16_t read(uint32_t address) override;
    void write(uint32_t address, uint16_t value) override;
    void tick() override; // Used to check if the user typed a new key

private:
    InterruptEnhancer& enhancer;

    std::queue<char> rx_buffer; // Queue of characters typed by the user
    uint16_t status_register = 0x0002; // Bit 1 (TX Ready) defaults to 1
    uint16_t control_register = 0;

    // Permanent assignment for our UART interrupt line (e.g., Line 1)
    const uint16_t UART_INTERRUPT_LINE = 1;
    uint32_t UART_VECTOR_ADDRESS;// = 0x00004000;
};


