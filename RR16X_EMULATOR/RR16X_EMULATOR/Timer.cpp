#include "Timer.h"
uint16_t Timer::read(uint32_t address)
{
	switch (address)
	{
	case 0x07FFFFFE:
		return time;
	default:
		return AbstractPeripheral::read(address);
	}
}
void Timer::write(uint32_t address, uint16_t value)
{
	switch (address)
	{
	default:
		AbstractPeripheral::write(address, value);
	}
}
void Timer::tick()
{ 
		
		if (++time == 0)
		{
			enhancer.raise_interrupt(0, interruptAddr);
		}
		else {
			enhancer.clear_interrupt(0);
		}
}
