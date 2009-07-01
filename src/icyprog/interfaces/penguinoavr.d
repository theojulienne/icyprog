module icyprog.interfaces.penguinoavr;

import icyprog.interfaces.penprog;

class PenguinoAVRInterface : PenprogInterface {
	const uint USBVendorId = 0x2424;
	const uint USBProductId = 0x5041;
	
	this( ) {
		super( );
	}
	
	public static void DiscoverInterfaces( ) {
		PenprogInterface.DiscoverInterfaces!(PenguinoAVRInterface)( USBVendorId, USBProductId );
	}
}
