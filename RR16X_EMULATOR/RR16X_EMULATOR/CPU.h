#pragma once
#include <vector>
#include <ostream>
#include <iostream>
#include "bus.h"
class CPU
{
public:
	//init CPU
	CPU();
	//dumps state to configurable output
	void step(bus& memory, bool interrupt = false, bool trace = false);
	// dump current state to configurable output
	void dumpState(std::ostream& out = std::cout);
	// returns all registers
	std::vector<uint16_t> getRegs() const
	{
	const std::vector<uint16_t> l = this->registers;
	return l;
	}
	// returns the program counter
	uint32_t getPC(const bool includeProgramEAM = true) const
	{
		if (includeProgramEAM)
		{
			return (programEAM << 16) | PC;
		}
		else {
			return PC;
		}
	}
	// gets the jump register
	uint32_t getJR() const
	{
		return JR;
	}
	/*//returns the stack pointer
	int16_t getSP() const 
	{
		return SP;
	}
	*/
	// returns the contents of the hardware return addres stack 
	std::vector<uint32_t> getStack() const
	{
		return stack;
	}
	//returns the bank ID where the CPU is running code
	uint16_t getDataEAM() const
	{
		return dataEAM;
	}
	//returns the interrupt vector
	uint32_t getIVR() const
	{
		return IVR;
	}
	void updateIVR(uint32_t value)
	{
		IVR = value;
	}


private:
	// all general purpose registers
	std::vector<uint16_t> registers;
	// the offset of the current instruction
	uint16_t PC;
	// the bank of the current instruction
	uint16_t programEAM;
	// stores a jump target
	uint32_t JR;
	//points to the top of the hardware's on-board hardware return address stack
	//int16_t SP = 0;
	// the hardware return address stack
	std::vector<uint32_t> stack;
	// the bank where the system may be reading or writing data to
	int16_t dataEAM;
	// the place in memory where execution goes when an interrupt occurs
	uint32_t IVR;
	bool interruptMask;
};

