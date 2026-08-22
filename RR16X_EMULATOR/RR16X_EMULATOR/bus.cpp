#include "bus.h"
#include <fstream>
#include <iostream>
#include <string>
#include <filesystem>
#include <vector>
#include <algorithm>
bus::bus(size_t size) : memory(size, 0) {}
void bus::initDevices(std::vector<AbstractPeripheral*> listDevices)
{
    devices = listDevices;
}
// see if there's a device with a readable memory-mapped address here
AbstractPeripheral* bus::findDeviceRead(uint32_t address)
{
    for (auto* d : devices)
    {
        std::vector<int32_t>& R = d->readableAddresses;
        if (std::find(R.begin(), R.end(), address) != R.end())
        {
            return d;
        }
    }
    return nullptr;
}
// see if there's amemory-mapped register we can write to
AbstractPeripheral* bus::findDeviceWrite(uint32_t address)
{ 
    for (auto* d : devices)
    {
        std::vector<int32_t>& R = d->writableAddresses;
        if (std::find(R.begin(), R.end(), address) != R.end())
        {
            return d;
        }
    }
    return nullptr;
}
// The read implementation

uint16_t bus::read(uint32_t address) {
    if (address < memory.size()) {
        AbstractPeripheral* d = findDeviceRead(address);
        if (d != nullptr)
        {
            // CRITICAL CHECK: Print or assert to ensure the pointer itself isn't garbage
            // If the program crashes exactly on the line below, 'd' is a dangling/corrupted pointer!
           // std::cout << "DEBUG READ: Device found at 0x" << std::hex << address << "\n";

            return d->read(address);
        }
        else {
            return memory[address];
        }
    }
    std::cerr << "CRITICAL: Out of bounds bus read attempted at 0x" << std::hex << address << "\n";
    return 0;
}

void bus::write(uint32_t address, uint16_t value) {
    if (address < memory.size()) {
        AbstractPeripheral* d = findDeviceWrite(address);
        if (d != nullptr)
        {
           // std::cout << "DEBUG WRITE: Device found at 0x" << std::hex << address << "\n";

            d->write(address, value);
        }
        else {
            memory[address] = value;
        }
    }
    else {
        std::cerr << "CRITICAL: Out of bounds bus write attempted at 0x" << std::hex << address << "\n";
       // __debugbreak(); // Forces MSVC to halt immediately right here
    }
   // std::cout << "[DEBUG] Bus Size: " << memory.size() << " | Target Addr: " <<std::hex<< address << std::endl;
}
bool bus::loadProgram(const std::string& filename, uint32_t startAddress, bool isHex) {
    std::filesystem::path FS(filename);

    // FIX: Open in binary mode if it's not a hex file!
    std::ios_base::openmode mode = std::ios::in;
    if (!isHex) mode |= std::ios::binary;

    std::ifstream file(FS, mode);
    if (!file) {
        std::cerr << "File not found!" << std::endl;
        return false;
    }

    std::string hexWord;
    std::vector<uint16_t> buffer;

    if (!isHex) {
        // FIX: Read proper 2-byte blocks instead of individual chars
        uint16_t word;
        while (file.read(reinterpret_cast<char*>(&word), sizeof(word))) {
            buffer.push_back(word);
        }
    }
    else {
        int tokens = 0;
        while (file >> std::hex >> hexWord) {
            try {
                unsigned long wordValue = std::stoul(hexWord, nullptr, 16);
                buffer.push_back(static_cast<uint16_t>(wordValue));
                
                // Direct conversion verification
                std::cout << "[PARSER DEBUG] Token #" << tokens++
                    << " | String: " << hexWord
                    << " -> Int: 0x" << std::hex << static_cast<uint16_t>(wordValue) << "\n";
            }
            catch (const std::invalid_argument& e) {
                std::cerr << "Warning: Skipped invalid hex token '" << hexWord << "'\n";
            }
            catch (const std::out_of_range& e) {
                std::cerr << "Warning: Hex token out of range '" << hexWord << "'\n";
            }
        }
    }

    std::cout << "\n--- BUS WRITE LOG ---\n";
    for (size_t i = 0; i < buffer.size(); ++i) {
        uint32_t currentAddress = startAddress + i;

        // OPTIONAL: You should add a boundary check here!
        // if (currentAddress >= MAX_BUS_SIZE) { std::cerr << "Bus overflow!"; break; }

        std::cout << "Token #" << std::dec << i
            << " | Target Bus Addr: 0x" << std::hex << (startAddress + i)
            << " | Value Written: 0x" << buffer[i] << "\n";

        write(currentAddress, buffer[i]);

     
    }
        
    std::cout << "---------------------\n\n";

    return true;
}
