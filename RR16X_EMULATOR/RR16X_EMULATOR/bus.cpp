#include "bus.h"
#include <fstream>
#include <iostream>
#include <string>
#include <filesystem>
#include <vector>
#include <algorithm>
#include <unordered_map>

bus::bus(size_t size) : memory(size, 0) {}

void bus::initDevices(std::vector<AbstractPeripheral*> listDevices)
{
    devices = listDevices;

    // Clear any stale lookups if initDevices is re-called
    readMap.clear();
    writeMap.clear();

    // Fast O(1) Pre-indexing: Flatten device vectors into quick-lookup tables
    for (auto* d : devices)
    {
        if (d == nullptr) continue;

        for (int32_t addr : d->readableAddresses) {
            readMap[static_cast<uint32_t>(addr)] = d;
        }
        for (int32_t addr : d->writableAddresses) {
            writeMap[static_cast<uint32_t>(addr)] = d;
        }
    }
}

// Drastically optimized to true O(1) constant time lookups
AbstractPeripheral* bus::findDeviceRead(uint32_t address)
{
    auto it = readMap.find(address);
    if (it != readMap.end()) {
        return it->second;
    }
    return nullptr;
}

AbstractPeripheral* bus::findDeviceWrite(uint32_t address)
{
    auto it = writeMap.find(address);
    if (it != writeMap.end()) {
        return it->second;
    }
    return nullptr;
}

uint16_t bus::read(uint32_t address) {
    if (address < memory.size()) {
        // Fast pointer extraction bypasses linear iteration loops
        AbstractPeripheral* d = findDeviceRead(address);
        if (d != nullptr) {
            return d->read(address);
        }
        return memory[address];
    }
    std::cerr << "CRITICAL: Out of bounds bus read attempted at 0x" << std::hex << address << "\n";
    return 0;
}

void bus::write(uint32_t address, uint16_t value) {
    if (address < memory.size()) {
        AbstractPeripheral* d = findDeviceWrite(address);
        if (d != nullptr) {
            d->write(address, value);
        }
        else {
            memory[address] = value;
        }
    }
    else {
        std::cerr << "CRITICAL: Out of bounds bus write attempted at 0x" << std::hex << address << "\n";

    }
}

bool bus::loadProgram(const std::string& filename, uint32_t startAddress, bool isHex) {
    std::filesystem::path FS(filename);

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
        uint16_t word;
        while (file.read(reinterpret_cast<char*>(&word), sizeof(word))) {
            buffer.push_back(word);
        }
    }
    else {
        while (file >> std::hex >> hexWord) {
            try {
                unsigned long wordValue = std::stoul(hexWord, nullptr, 16);
                buffer.push_back(static_cast<uint16_t>(wordValue));
            }
            catch (const std::invalid_argument&) {}
            catch (const std::out_of_range&) {}
        }
    }

    // Optimization: Bulk verify size boundaries before starting loop
    if (startAddress + buffer.size() > memory.size()) {
        std::cerr << "CRITICAL: Program load size overflows bus bounds!\n";
        return false;
    }

    // Write straight to memory space or active peripherals
    for (size_t i = 0; i < buffer.size(); ++i) {
        write(startAddress + i, buffer[i]);
    }

    std::cout << "Successfully mapped " << std::dec << buffer.size() << " words to bus address 0x" << std::hex << startAddress << "\n";
    return true;
}
