module icyprog.interfaces.penguinoavr;

import icyprog.interfaces.penprog;

class PenguinoAVRInterface : PenprogInterface {
	const uint USBVendorId = 0x16D0;
	const uint USBProductId = 0x04CA;
	
	this( ) {
		super( );
	}
	
	public static void DiscoverInterfaces( ) {
		PenprogInterface.DiscoverInterfaces!(PenguinoAVRInterface)( USBVendorId, USBProductId );
	}
}
