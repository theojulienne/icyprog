module usb.bus;

import usb.libusb;
import usb.device;

class USBBus {
	static USBBus[usb_bus*] bus_map;
	static USBBus fromC( usb_bus *c_bus ) {
		if ( !(c_bus in bus_map) )
			bus_map[c_bus] = new USBBus( c_bus );
		
		return bus_map[c_bus];
	}
	
	usb_bus *_bus;
	
	this( usb_bus *native ) {
		_bus = native;
	}
	
	USBUSBDeviceEnumerator devices( ) {
		return new USBUSBDeviceEnumerator( this );
	}
}

class USBUSBDeviceEnumerator {
	USBBus bus;
	
	this( USBBus _bus ) {
		this.bus = _bus;
	}
	
	int opApply( int delegate(ref USBDevice) dg ) {
		int result;
		
		usb_device *curr = usb_bus_first_device( bus._bus );
		
		for ( ; curr !is null; curr = usb_device_get_next(curr) ) {
			USBDevice dev = USBDevice.fromC( curr );
			
			result = dg( dev );
			
			if ( result )
				break;
		}
		
		return result;
	}
}
