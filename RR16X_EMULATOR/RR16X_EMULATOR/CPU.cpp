#include "CPU.h"
#include <iostream>
#include <bit>
#include <cstdint>
#include <ostream>
#include <string>
#include "bus.h"
//init the processor
CPU::CPU()
{ 
	registers = { 0,0,0,0,0,0,0,0 };
	PC = 0;
	JR = 0;
	stack = {};
	//SP = 0;
	programEAM = 0;
	dataEAM = 0;
	IVR = 0;
	interruptMask = false;

}

void CPU::dumpState(std::ostream& out)
{
	out << "DUMPING STATE!\n";
	out << "R0: " << std::hex << registers[0] << std::endl;
	out<< "R1: " << std::hex << registers[1] << std::endl;
	out<< "R2: " << std::hex << registers[2] << std::endl;
	out<< "R3: " << std::hex << registers[3] << std::endl;
	out<< "R4: " << std::hex << registers[4] << std::endl;
	out<< "R5: " << std::hex << registers[5] << std::endl;
	out<< "R6: " << std::hex << registers[6] << std::endl;
	out<< "R7: " << std::hex << registers[7] << std::endl;
	out<< "PC: " << std::hex << PC << std::endl;
	out<< "programEAM: " << std::hex << programEAM << std::endl;
	out<< "dataEAM: " << std::hex << dataEAM << std::endl;
	out<< "JR: " << std::hex <<JR << std::endl;
	//out<< "SP: " << std::hex <<SP<< std::endl;
	out<< "IVR:" << std::hex << IVR << std::endl;
}
//executes one clock cycle of program time
void CPU::step(bus& memory, bool interrupt, bool trace)
{
	if (interrupt && !interruptMask) {
		// 1. You should probably clear the interrupt source here,
		//    or ensure your emulator caller stops sending it.

		//SP++;
		// Use the explicit mask to ensure no sign-extension issues
		stack.push_back(static_cast<uint32_t>((programEAM << 16) | (PC & 0xFFFF)));

		PC = (IVR & 0xFFFF);
		programEAM = (IVR >> 16) & 0xFFFF;
		interruptMask = true; // Typically, you mask interrupts upon entering a handler
	}
	const uint32_t instructionAddress = (programEAM << 16) | PC;
	uint16_t instruction = memory.read(instructionAddress);
	int opcode = (instruction & 0xF000) >> 12;
	bool M_flag = (instruction & 0x0800) != 0;
	int Dest = (instruction & 0x0700) >> 8;
	bool LX = (instruction & 0x0080) != 0;
	int srcX = (instruction & 0x0070) >> 4;
	bool LY = (instruction & 0x0008) != 0;
	int srcY = (instruction & 0x0007);
	bool A = false;
	uint32_t pushValue = 0;
	uint32_t popValue = 0;
	uint32_t Address = 0;
	int16_t X = 0;
	int16_t Y = 0;
	uint16_t i;
	int16_t Result = 0;
	bool makes = true;

	if (LX && !LY)
	{
		X = memory.read(instructionAddress + 1);
		Y = registers[srcY];
	}
	else if (!LX && LY)
	{
		X = registers[srcX];
		Y = memory.read(instructionAddress + 1);
	}
	else if (LX && LY)
	{
		X = memory.read(instructionAddress + 1);
		Y = memory.read(instructionAddress + 2);
	}
	else {
		X = registers[srcX];
		Y = registers[srcY];
	}
	if (trace)
	{
		std::cout << "PC: " << std::hex << instructionAddress
			<< " | Op: " << opcode
			<< " | X: " << X
			<< " | Y: " << Y << std::endl;
		std::cout << "LX: " << LX << " LY: " << LY << std::endl;
		std::cout << "JR:" << JR << std::endl;
		std::cout << " | IR: " << instruction << std::endl;
	}
	if (instructionAddress + (LX + LY) > 0x07FF'FFFF)
	{
		std::cerr << "ERROR: Tried to access invalid memory!";

	}
	switch (opcode)
	{
	case 0:
		if (M_flag)
		{
			IVR = (dataEAM << 16) | X;
		}
		else
		{
			dataEAM = (X & 0x7FF);
		}
		makes = false;
		break;
	case 1:
		Result = X + Y;
		if (M_flag)
		{
			++Result;
		}
		break;
	case 2:
		Result = X - Y;
		if (M_flag)
		{
			--Result;
		}
		break;
	case 3:
		if (M_flag)
		{
			Y = ~Y;
		}
		Result = X & Y;
		break;

	case 4:
		if (M_flag)
		{
			Y = ~Y;
		}
		Result = X | Y;
		break;
	case 5:
		Result = ~X;
		if (M_flag)
		{
			++Result;
		}
		break;
	case 6:
		if (M_flag)
		{
			Y = ~Y;
		}
		Result = X ^ Y;
		break;
	case 7:
		if (M_flag)
		{
			Result = std::rotl(static_cast<uint16_t>(X), (Y & 0xF));//((X << (Y & 0xF)) | (X >> (0xF - (Y & 0xF))));
		}
		else {
			Result = (X << (Y & 0xf))& 0xFFFF;
		}
		break;
	case 8:
		if (M_flag)
		{
			Result = std::rotr(static_cast<uint16_t>((X)), (Y & 0xF));
		}
		else {
			Result = (X >> (Y & 0xf)) & 0xFFFF;
		}
		break;
	case 9:
		Address = static_cast<uint32_t>((dataEAM << 16) | (static_cast<uint16_t>(X) & 0xFFFF));
		if (Address > 0x07FF'FFFF)
		{
			std::cerr << "Error: Reading from invalid memory";
			return;
		}
		Result = memory.read(static_cast<uint32_t>(Address));
		if (M_flag)
		{
			++X;
			if (!LX) {
				registers[srcX] = X;
			}
		}
		break;
	case 10:
		Address = static_cast<uint32_t>((dataEAM << 16) | (static_cast<uint16_t>(X) & 0xFFFF));
		if (Address > 0x07FF'FFFF)
		{
			std::cerr << "Error: Writing to invalid memory";
			return;
		}
		//std::cout << "DEBUG, writing: " << std::hex << Y << " To: " << std::hex << static_cast<uint32_t>((dataEAM << 16) | (uint16_t)X )<< std::endl;
		memory.write(Address,Y);
		if (M_flag)
		{
			++X;
			if (!LX) {
				registers[srcX] = X;
			}
		}
		makes = false;
		break;
	case 11:
		if (!M_flag)
		{
			JR = static_cast<uint32_t>((dataEAM << 16) | static_cast<uint16_t>(X));
		}
		else {
			JR &= 0xFFFF0000;
			JR |= (static_cast<uint16_t>(X) & 0xFFFF);
		}
		std::cout << "JR IS NOW:" << std::hex << JR << std::endl; 
		makes = false;
		break;
	case 12:
		i = (M_flag << 3) | Dest;
		A = false;
		switch (i)
		{
		case 0x0:
			break;
		case 0x1:
			A = X < Y;
			break;
		case 0x2:
			A = X == Y;
			break;
		case 0x3:
			A = X <= Y;
			break;
		case 0x4:
			A = X > Y;
			break;
		case 0x5:
			A = X != Y;
			break;
		case 0x6:
			A = X >= Y;
			break;
		case 0x7:
			A = true;
			break;
		case 0x8:
			A = static_cast<int16_t>(X) < static_cast<int16_t>(Y);
			break;
		case 0x9:
			A = static_cast<int16_t>(X) == static_cast<int16_t>(Y);
			break;
		case 0xA:
			A = static_cast<int16_t>(X) <= static_cast<int16_t>(Y);
			break;
		case 0xB:
			A = static_cast<int16_t>(X) > static_cast<int16_t>(Y);
			break;
		case 0xC:
			A = static_cast<int16_t>(X) != static_cast<int16_t>(Y);
			break;
		case 0xD:
			A = static_cast<int16_t>(X) >= static_cast<int16_t>(Y);
			break;
		default:
			std::cerr << "Unused or invalid jump condition!\n";
			return;
		}
		if (A)
		{
			PC = (JR & 0x0000FFFF);
			programEAM = (JR & 0xFFFF0000) >> 16;
			std::cout << "BRANCHING TO:" << std::hex <<JR<<'\n';
			return;
		}
		makes = false;
		break;
	case 13:
		pushValue = PC + LX + LY + 1;
		pushValue |= programEAM << 16;
		std::cout << "FIRST INSTRUCTION OF SUBROUTINE:" << std::hex << memory.read(X) << std::endl;
		std::cout <<"AT ADDRESS: "<< std::hex << X << std::endl;
		if (stack.size() >= 255)
		{
			std::cerr << "Stack Overflow!" << std::endl;
			return;
		}
		makes = false;
		stack.push_back(pushValue);
		PC = X;
		if (!M_flag) programEAM = dataEAM;
		return;
	case 14:
		popValue = stack.back();
		std::cout << "RETURNING!" << std::endl;
		if (stack.empty())
		{
			std::cerr << "Stack underflow!" << std::endl;
			return;
		}
		stack.pop_back();
		PC = popValue & 0xFFFF;
		programEAM = (popValue >> 16) & 0x7FF;
		interruptMask = M_flag;
		makes = false;
		return;
	default:
		std::cerr << "CRITICAL: Unhandled Opcode " << std::hex << opcode << " at PC " << instructionAddress << std::endl;
		makes = false;
		return;
	}
	if (makes)
	{
		registers[Dest] = Result;
	}
	

	
	if (PC + LX + LY > 0xFFFF)
	{
	 PC = (PC + LX + LY + 1) & 0xFFFF;
	 programEAM++;
	}
	else {
		PC += LX + LY + 1;
	}
	
	
}
