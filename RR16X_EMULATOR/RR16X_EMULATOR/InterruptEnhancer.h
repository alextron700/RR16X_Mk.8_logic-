class InterruptEnhancer : public AbstractPeripheral
{
public:
    InterruptEnhancer(bus& memoryBus, uint32_t vectorTableBase = 0x0000FF00);
    ~InterruptEnhancer() = default;
    void write(uint32_t address, uint16_t value) override;
    uint16_t read(uint32_t address) override;
    void tick() override;
    void raise_interrupt(uint16_t line_number);   // <-- no more vector_address param
    void clear_interrupt(uint16_t line_number);
    bool has_active_interrupt() const;
    uint32_t get_highest_priority_vector() const;
private:
    struct InterruptRequest {
        bool is_pending = false;
        // vector_address removed - looked up from memory instead
    };
    std::vector<InterruptRequest> interrupt_lines;
    uint16_t status_register = 0;
    uint16_t mask_register = 0;     // now 0 by default, per the earlier fix
    bus& memBus;
    uint32_t vecTableBase;
};
