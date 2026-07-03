#include "DMA.h"
DMA::DMA(bus& system_bus, InterruptEnhancer& ie) : Bus(system_bus), enhancer(ie)
{
	readableAddresses = { 0x07ff'fff2,0x07ff'fff1,0x07ff'fff0,0x07ff'ffef,0x07ff'ffee};
	writableAddresses = { 0x07ff'fff2,0x07ff'fff1,0x07ff'fff0,0x07ff'ffef,0x07ff'ffee};
	return;
}
uint16_t DMA::read(uint32_t address)
{ 
	switch (address)
	{
	case 0x07ff'fff2:
		return src_address & 0xFFFF;
	case 0x07ff'fff1:
		return dest_address & 0xFFFF;
	case 0x07ff'fff0:
		return count;
	case 0x07ff'ffef:
		return (src_address & 0xFFFF0000) >> 16;
	case 0x07ff'ffee:
		return (dest_address & 0xFFFF0000) >> 16;
	default:
		return 0;
	}
}
void DMA::write(uint32_t address, uint16_t value)
{
	switch (address)
	{
	case 0x07ff'fff2:
		src_address &= 0xFFFF0000;
		src_address |= value;
		break;
	case 0x07ff'fff1:
		dest_address &= 0xFFFF0000;
		dest_address |= value;
		break;
	case 0x07ff'fff0:
		count = value;
		break;
	case 0x07ff'ffef:
		src_address &= 0x0000FFFF;
		src_address |= value << 16;
		break;
	case 0x07ff'ffee:
		dest_address &= 0x0000FFFF;
		dest_address |= value << 16;
		break;
	default:
		return;
	}
}
void DMA::tick()
{ 
	uint16_t x;
	if (count != 0)
	{
		x = Bus.read(src_address);
		Bus.write(dest_address,x);
		src_address++;
		dest_address++;
		count--;
	}
	
}