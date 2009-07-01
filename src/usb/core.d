module usb.core;

import usb.libusb;
import usb.bus;

static this( ) {
	usb_init( );
}

class USB {
	static int findUSBBusses( ) {
		return usb_find_busses( );
	}
	
	static int findDevices( ) {
		return usb_find_devices( );
	}
	
	static USBUSBBusEnumerator busses( ) {
		findUSBBusses( );
		findDevices( );
		
		return new USBUSBBusEnumerator( );
	}
}

class USBUSBBusEnumerator {
	this( ) {
		
	}
	
	int opApply( int delegate(ref USBBus) dg ) {
		int result;
		
		usb_bus *curr = usb_get_busses( );
		
		for ( ; curr !is null; curr = usb_bus_get_next(curr) ) {
			USBBus bus = USBBus.fromC( curr );
			
			result = dg( bus );
			
			if ( result )
				break;
		}
		
		return result;
	}
}
