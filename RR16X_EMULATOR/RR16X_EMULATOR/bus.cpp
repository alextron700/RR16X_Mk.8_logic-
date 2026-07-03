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
          std::vector<int32_t> R = d->readableAddresses;
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
        std::vector<int32_t> R = d->writableAddresses;
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
            return d->read(address);
        }
        else {
            return memory[address];
        }
    }
    return 0;
}

// The write implementation
void bus::write(uint32_t address, uint16_t value) {
    if (address < memory.size()) {
        AbstractPeripheral* d = findDeviceWrite(address);
        if (d != nullptr)
        {
            d->write(address, value);
        }
        else {
            memory[address] = value;
        }
    }
}
bool bus::loadProgram(const std::string& filename, uint32_t startAddress, bool isHex) {
    std::filesystem::path FS(filename);
    std::ifstream file(FS,std::ios::in);
    if (!file) {
        // Handle error: File not found
        std::cerr << "File not found!" << std::endl;
        return false;
    }
    std::string hexWord;
    std::vector<uint16_t> buffer;
    if (!isHex)
    {
        // Read the file into a temporary buffer
        buffer.assign((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    }
    else {
        while (file >> std::hex >> hexWord) {
            // Convert the 4-character hex string to a 16-bit integer
            try {
                unsigned long wordValue = std::stoul(hexWord, nullptr, 16);
                buffer.push_back(static_cast<uint16_t>(wordValue));
            }
            catch (const std::invalid_argument& e) {
                std::cerr << "Warning: Skipped invalid hex token '" << hexWord << "'\n";
            }
            catch (const std::out_of_range& e) {
                std::cerr << "Warning: Hex token out of range '" << hexWord << "'\n";
            }
        }
    }
  //  std::cout << "DEBUG: Is Hex Mode? " << (isHex ? "YES" : "NO") << "\n";
 // std::cout << "DEBUG: Buffer size collected: " << buffer.size() << " elements.\n";
  std::cout << "\n--- BUS WRITE LOG ---\n";
    // Write to the Bus
    for (size_t i = 0; i < buffer.size(); ++i) {
     std::cout << "Writing to Addr: 0x" << std::hex << (startAddress + i)
      << " | Value: 0x" << buffer[i] << "\n";
        write(startAddress + i, buffer[i]);
    }
    std::cout << "---------------------\n\n";
    return true;
}