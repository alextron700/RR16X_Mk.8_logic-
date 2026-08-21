#include "AbstractPeripheral.h"
#include <iostream>
uint16_t AbstractPeripheral::read(uint32_t address)
{
	std::cerr << "ERROR: Attempted to read with AbstractPeripheral. Check that the peripheral being addressed has been implemented properly.\n";
	std::cerr << "Address:" << std::hex << address << std::endl;
	return 0xFFFF;
}
void AbstractPeripheral::write(uint32_t address, uint16_t value)
{
	std::cerr << "ERROR: Attempted to write with AbstractPeripheral. Check that the peripheral being addressed has been implemented properly\n";
	std::cerr << "Address:" << std::hex << address << std::endl;
}
void AbstractPeripheral::tick()
{
	//std::cerr << "ERROR: Attempted to tick with AbstractPeripheral. Check that the peripheral being addressed has been implemented properly\n";
	return;
}