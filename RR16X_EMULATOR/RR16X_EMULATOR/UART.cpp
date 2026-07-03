#include "UART.h"
#include <iostream>
#if defined(_WIN32)
#include <conio.h> // Windows keyboard console handling
#else
#include <unistd.h>    // Linux standard symbolic constants
#include <sys/select.h>// Linux select() for non-blocking I/O
#include <termios.h>   // Linux terminal control definitions
#endif
#if !defined(_WIN32)
// Linux helper function to check if a key is waiting in stdin without blocking
int linux_kbhit() {
    struct timeval tv = { 0, 0 }; // Return instantly (0 timeout)
    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(STDIN_FILENO, &fds);
    return select(STDIN_FILENO + 1, &fds, NULL, NULL, &tv);
}
#endif
UART::UART(InterruptEnhancer& ie, uint32_t IVA = 0) : enhancer(ie) {
    status_register = 0x0002; // TX is always ready to receive characters
    UART_VECTOR_ADDRESS = IVA;
    readableAddresses = { 0x07ff'ffe6,0x7ff'ffe5,0x07ff'ffe4};
    writableAddresses = { 0x07ff'ffff, 0x07ff'ffe4 };
}

uint16_t UART::read(uint32_t address)
{
    switch (address)
    {
    case 0x07FFFFFE6: // Data Register Read
        if (!rx_buffer.empty()) {
            char c = rx_buffer.front();
            rx_buffer.pop();

            // If the buffer is now empty, clear the RX Ready status bit (Bit 0)
            if (rx_buffer.empty()) {
                status_register &= ~0x0001;
            }
            return static_cast<uint16_t>(c);
        }
        return 0; // Return null if no data is waiting

    case 0x07FFFFFE5: // Status Register Read
        return status_register;

    case 0x07FFFFFE4: // Control Register Read
        return control_register;

    default:
        return AbstractPeripheral::read(address);
    }
}

void UART::write(uint32_t address, uint16_t value)
{
    switch (address)
    {
    case 0x07FFFFFF: // Data Register Write -> Print directly to screen!
        std::cout << static_cast<char>(value & 0xFF);
        std::cout.flush(); // Force character to display immediately without waiting for \n
        break;

    case 0x07FFFFFE5:
        std::cerr << "ERROR: Attempted illegal write to Read-Only UART Status Register\n";
        break;

    case 0x07FFFFFE4: // Control Register Write
        control_register = value;
        break;

    default:
        AbstractPeripheral::write(address, value);
        break;
    }
}
void UART::tick()
{
    bool key_pressed = false;
    char key_char = 0;

#if defined(_WIN32)
    // --- Windows Path ---
    if (_kbhit()) {
        key_char = static_cast<char>(_getch());
        key_pressed = true;
    }
#else
    // --- Linux Path ---
    if (linux_kbhit()) {
        // Suppress terminal echo and buffering so keys read instantly
        struct termios old_t, new_t;
        tcgetattr(STDIN_FILENO, &old_t);
        new_t = old_t;
        new_t.c_lflag &= ~(ICANON | ECHO);
        tcsetattr(STDIN_FILENO, TCSANOW, &new_t);

        // Read the single raw byte
        read(STDIN_FILENO, &key_char, 1);

        // Restore standard terminal settings immediately
        tcsetattr(STDIN_FILENO, TCSANOW, &old_t);
        key_pressed = true;
    }
#endif

    // --- Unified Processing Engine ---
    if (key_pressed)
    {
        rx_buffer.push(key_char);
        status_register |= 0x0001; // Mark RX Ready bit active

        // Alert the Interrupt Enhancer if UART interrupts are configured active
        if (control_register & 0x0001)
        {
            enhancer.raise_interrupt(UART_INTERRUPT_LINE, UART_VECTOR_ADDRESS);
        }
    }
}