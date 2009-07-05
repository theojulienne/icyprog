module usb.descriptors;

align(1):

struct USBDeviceDescriptor {
	ubyte bLength;
	ubyte bDescriptorType;
	ushort bcdUSB;
	ubyte bDeviceClass;
	ubyte bDeviceSubClass;
	ubyte bDeviceProtocol;
	ubyte bMaxPacketSize0;
	ushort idVendor;
	ushort idProduct;
	ushort bcdDevice;
	ubyte iManufacturer;
	ubyte iProduct;
	ubyte iSerialNumber;
	ubyte bNumConfigurations;
}

struct USBConfigurationDescriptor {
	ubyte  bLength;
	ubyte  bDescriptorType;
	ushort wTotalLength;
	ubyte  bNumInterfaces;
	ubyte  bConfigurationValue;
	ubyte  iConfiguration;
	ubyte  bmAttributes;
	ubyte  MaxPower;
}
