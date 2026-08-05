#pragma once
#include <vector>
#include <cstdint> // Added for uint16_t and uint32_t
#include <string>
#include "AbstractPeripheral.h"
class bus // Note: Standard C++ style usually uses uppercase for class names (Bus)
{
private:
    std::vector<uint16_t> memory;
    std::vector < AbstractPeripheral*> devices;
public:
    bus(size_t size);
    // initialises all devices
    void initDevices(std::vector<AbstractPeripheral*> listDevices);
    AbstractPeripheral* findDeviceRead(uint32_t address);
    // reads a word from memory
    AbstractPeripheral* findDeviceWrite(uint32_t address);
    uint16_t read(uint32_t address);
    // writes a word to memory
    void write(uint32_t address, uint16_t value);
    // loads a program to memory
    bool loadProgram(const std::string& filepath, uint32_t startAddress, bool isHex = true);
};
