#include "FP32Coprocessor.h"
#include <cstring> //note: This used to be bit but bit died for some reason
#include <cmath>
uint16_t FP32Coprocessor::read(uint32_t address)
{
	switch (address)
	{
	case 0x07ff'ffd5:
		return outLow;
	case 0x07ff'ffd6:
		return outHigh;
	default:
		return 0;
	}
}
void FP32Coprocessor::write(uint32_t address, uint16_t value)
{
	switch (address)
	{
	case 0x07ff'ffd0:
		ALow = value;
		break;
	case 0x07ff'ffd1:
		AHigh = value;
		break;
	case 0x07ff'ffd2:
		BLow = value;
		break;
	case 0x07ff'ffd3:
		BHigh = value;
		break;
	case 0x07ff'ffd4:
		command = value;
		break;
	default:
		return;
	}

}
void FP32Coprocessor::tick()
{
	uint32_t AInt =
		(static_cast<uint32_t>(static_cast<uint16_t>(AHigh)) << 16)
		| ALow;
	uint32_t BInt =
		(static_cast<uint32_t>(static_cast<uint16_t>(BHigh)) << 16)
		| BLow;
	float output = 0.0f;
	float Afloat;
	std::memcpy(&Afloat, &AInt, sizeof(Afloat));

	float Bfloat;
	std::memcpy(&Bfloat, &BInt, sizeof(Bfloat));
	switch (command)
	{
	case 0:
		output = Afloat + Bfloat;
		break;
	case 1:
		output = Afloat - Bfloat;
		break;
	case 2:
		output = Afloat * Bfloat;
		break;
	case 3:
		if (fabs(Bfloat) > 0.0f)
		{
			output = Afloat / Bfloat;
		}
		else {
			output = INFINITY;
		}
		break;
	default:
		output = 0.0f;
	}
	int32_t outInt;
	std::memcpy(&outInt, &output, sizeof(output));
	outLow = outInt & 0xFFFF;
	outHigh = (outInt >> 16) & 0xFFFF;
}
