// RR16X_EMULATOR.cpp : This file contains the 'main' function. Program execution begins and ends there.
//

#include <iostream>
#include <fstream>
#include <string>
#include "CPU.h"
#include "bus.h"
#include "AbstractPeripheral.h"

#include "interruptEnhancer.h"
#include "Timer.h"
#include "Multiplier.h"
#include "UART.h"
#include "WideIntCoprocessor.h"
#include "FP32Coprocessor.h"
#include "DMA.h"

#include <filesystem>
int main()
{
    std::string filePath;
    std::cout << "Enter program file path: ";
    std::cin >> std::ws;
    std::getline(std::cin, filePath);
    //std::cout << "Looking for files in: " << std::filesystem::current_path() << std::endl;
    bus myBus(0x800'0000); // Initialize with your desired memory size
    char haveTrace = '\0';
    std::string input;
    std::cout << "Would you like to have an execution trace? Y/N\n";
    while (haveTrace == '\0')
    {
       
        std::getline(std::cin, input);
        if (input[0] == 'Y')
        {
            haveTrace = 'Y';
        }
        else if (input[0] == 'N')
        {
            haveTrace = 'N';
        }
        else {
            std::cout << "Invalid answer.\n";
        }
    }
    bool trace;
    if (haveTrace == 'Y')
    {
        trace = true;
    }
    else {
        trace = false;
    }
    std::cout << "STARTING EXECUTION...\n";
   // std::cout << "[TRACER 1] Initializing IE...\n";
    InterruptEnhancer IE;

   // std::cout << "[TRACER 2] Initializing Timer...\n";
    Timer timer(IE, 0);

    //std::cout << "[TRACER 3] Initializing Multiplier...\n";
    Multiplier multiplier;

    //std::cout << "[TRACER 4] Initializing UART...\n";
    UART uart(IE, 0);

   // std::cout << "[TRACER 5] Initializing WIC...\n";
    WideIntCoprocessor WIC;

   // std::cout << "[TRACER 6] Initializing FC...\n";
    FP32Coprocessor FC;

   // std::cout << "[TRACER 7] Initializing DMA...\n";
    DMA dma(myBus, IE);

    //std::cout << "[TRACER 8] About to load program from: " << filePath << "\n";
    if (!myBus.loadProgram(filePath, 0x0000,true)) {
        std::cerr << "Failed to load program!" << std::endl;
        return 1;
    }
    for (uint32_t addr = 0x7FF'0000; addr < 0x07ff'7fff; ++addr)
    {
        myBus.write(addr, 0x0000);
    }
    //bus BUS = bus(0xFFFF * 0x0800);
    CPU cpu = CPU();
    uint32_t PC = cpu.getPC(true);
    std::cout << "Program load success!\n";
    // get the memory address at the program counter. If the instruction isn't halt
    std::vector<AbstractPeripheral*> APList = { &timer,&dma,&uart,&IE,&multiplier,&WIC,&FC };
    myBus.initDevices(APList);
    while (myBus.read(PC) < 0xF000)
    {
        //std::cerr << "LOOP: PC=" << std::hex << PC << std::endl;
    
        bool int_signal = IE.has_active_interrupt();
            if(int_signal)
            {
                cpu.updateIVR(IE.get_highest_priority_vector());
            }
   
            for (auto AP : APList)
            {
                AP->tick();
            }
          // std::cout << "FETCHING:" << std::hex << myBus.read(PC)<<std::endl;
            if (trace)
            {
                cpu.dumpState();
            }
            cpu.step(myBus, int_signal, trace);
            PC = cpu.getPC(true);
            //cpu.dumpState();
    }
   // std::cerr << "LOOP EXIT: PC=" << std::hex << PC
   //     << " opcode=" << myBus.read(PC) << std::endl;
    return 0;
}

// Run program: Ctrl + F5 or Debug > Start Without Debugging menu
// Debug program: F5 or Debug > Start Debugging menu

// Tips for Getting Started: 
//   1. Use the Solution Explorer window to add/manage files
//   2. Use the Team Explorer window to connect to source control
//   3. Use the Output window to see build output and other messages
//   4. Use the Error List window to view errors
//   5. Go to Project > Add New Item to create new code files, or Project > Add Existing Item to add existing code files to the project
//   6. In the future, to open this project again, go to File > Open > Project and select the .sln file
