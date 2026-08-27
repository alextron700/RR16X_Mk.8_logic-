#pragma once
#include <vector>
#include <cstdint> 
#include <string>
#include <unordered_map> // Needed for fast constant-time lookup maps
#include "AbstractPeripheral.h"

class bus
{
private:
    std::vector<uint16_t> memory;
    std::vector<AbstractPeripheral*> devices;

    // --- Fast O(1) Address Mapping Lookups ---
    // Maps absolute 32-bit addresses straight to their peripheral pointers,
    // bypassing the need to loop through vectors at runtime.
    std::unordered_map<uint32_t, AbstractPeripheral*> readMap;
    std::unordered_map<uint32_t, AbstractPeripheral*> writeMap;

public:
    bus(size_t size);

    // Initialises all devices and builds the fast routing maps
    void initDevices(std::vector<AbstractPeripheral*> listDevices);

    AbstractPeripheral* findDeviceRead(uint32_t address);
    AbstractPeripheral* findDeviceWrite(uint32_t address);

    // Reads a word from memory or mapped peripheral
    uint16_t read(uint32_t address);

    // Writes a word to memory or mapped peripheral
    void write(uint32_t address, uint16_t value);

    // Loads a program to memory
    bool loadProgram(const std::string& filepath, uint32_t startAddress, bool isHex = true);
};