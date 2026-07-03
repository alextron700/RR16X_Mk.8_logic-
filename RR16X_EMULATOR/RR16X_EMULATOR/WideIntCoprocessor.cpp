#include "WideIntCoprocessor.h"
WideIntCoprocessor::WideIntCoprocessor()
{
	ALow = 0;
	AHigh = 0;
	BHigh = 0;
	BLow = 0;
	outLow = 0;
	outHigh = 0;
	command = 0;
	readableAddresses = { 0x07ff'ffe8, 0x07ff'ffe8 };
	writableAddresses = { 0x07ff'ffed, 0x07ff'ffec,0x07ff'ffeb,0x07ff'ffea,0x07ff'ffe9 };
}
uint16_t WideIntCoprocessor::read(uint32_t address)
{
	switch (address)
	{
	case 0x07ff'ffe8:
		return outLow;
	case 0x07ff'ffe7:
		return outHigh;
	default:
		return 0;
}

}
void WideIntCoprocessor::write(uint32_t address, uint16_t value)
{
	switch (address)
	{
	case 0x07ff'ffed:
		ALow = value;
		break;
	case 0x07ff'ffec:
		AHigh = value;
		break;
	case 0x07ff'ffeb:
		BLow = value;
		break;
	case 0x07ff'ffea:
		BHigh = value;
		break;
	case 0x07ff'ffe9:
		command = value;
		break;
	default:
		return;
	}
}
void WideIntCoprocessor::tick()
{
	uint32_t Awide = (AHigh << 16) | ALow;
	uint32_t Bwide = (BHigh << 16) | BHigh;
	int32_t outWide = 0;
	switch (command)
	{
	case 0:
		outWide = Awide + Bwide;
		break;
	case 1:
		outWide = Awide - Bwide;
		break;
	case 2:
		outWide = Awide << (Bwide & 0x1f);
		break;
	case 3:
		outWide = Awide >> (Bwide & 0x1f);
		break;
	case 4:
		outWide = Awide & Bwide;
		break;
	case 5:
		outWide = Awide | Bwide;
		break;
	case 6:
		outWide = Awide ^ Bwide;
		break;
	default:
		outWide = 0;
	}
	outLow = outWide & 0xFFFF;
	outHigh =static_cast<int16_t>((outWide >> 16) & 0xFFFF);
	return;
}