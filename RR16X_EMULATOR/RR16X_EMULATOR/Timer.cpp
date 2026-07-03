#include "Timer.h"
uint16_t Timer::read(uint32_t address)
{
	switch (address)
	{
	case 0x07FFFFFE:
		return time;
	default:
		return 0;
 }
}
void Timer::write(uint32_t address, uint16_t value)
{
	switch (address)
	{
	default:
		return;
	}
}
void Timer::tick()
{ 
		time++;
		if (time + 1 >= 0xFFFF)
		{
			time = 0;
			enhancer.raise_interrupt(0, interruptAddr);
		}
		else {
			enhancer.clear_interrupt(0);
		}
}