InterruptEnhancer::InterruptEnhancer(bus& memoryBus, uint32_t vectorTableBase)
    : memBus(memoryBus), vecTableBase(vectorTableBase)
{
    interrupt_lines.resize(16);
    readableAddresses = { 0x07ff'fff5, 0x07ff'fff4 };
    writableAddresses = { 0x07ff'fff5 };
}

void InterruptEnhancer::raise_interrupt(uint16_t line_number)
{
    if (line_number >= 16) return;
    interrupt_lines[line_number].is_pending = true;
    status_register |= (1 << line_number);
}

uint32_t InterruptEnhancer::get_highest_priority_vector() const
{
    for (size_t i = 0; i < interrupt_lines.size(); ++i)
    {
        if (interrupt_lines[i].is_pending && (mask_register & (1U << i)))
        {
            // Look up the CURRENT vector for this line, straight from memory.
            // If the program never wrote a real ISR address here, this
            // reads whatever's there - see the safety note below.
            return memBus.read(vecTableBase + (uint32_t)i);
        }
    }
    return 0x00000000;
}
