#pragma once
#include <cstdint>
#include <vector>
class AbstractPeripheral
{
public:
	virtual ~AbstractPeripheral() = default;
	virtual uint16_t read(uint32_t address) = 0;
	virtual void write(uint32_t address, uint16_t value) = 0;
	virtual void tick() = 0;
	std::vector<int32_t> writableAddresses = {};
	std::vector<int32_t> readableAddresses = {};
};

