#pragma once
#include "AbstractPeripheral.h"
class WideIntCoprocessor:public AbstractPeripheral
{
public:
	WideIntCoprocessor();	
	uint16_t read(uint32_t address) override;
	void write(uint32_t address, uint16_t value) override;
	void tick() override;
private:
	uint16_t ALow;
	uint16_t AHigh;
	uint16_t BLow;
	uint16_t BHigh;
	uint16_t outLow;
	int16_t outHigh;
	uint16_t command;
};

