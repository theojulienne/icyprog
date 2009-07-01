module usb.descriptors;

align(1):

struct USBDeviceDescriptor {
	byte bLength;
	byte bDescriptorType;
	ushort bcdUSB;
	byte bDeviceClass;
	byte bDeviceSubClass;
	byte bDeviceProtocol;
	byte bMaxPacketSize0;
	ushort idVendor;
	ushort idProduct;
	ushort bcdDevice;
	byte iManufacturer;
	byte iProduct;
	byte iSerialNumber;
	byte bNumConfigurations;
}

struct USBConfigurationDescriptor {
	byte  bLength;
	byte  bDescriptorType;
	ushort wTotalLength;
	byte  bNumInterfaces;
	byte  bConfigurationValue;
	byte  iConfiguration;
	byte  bmAttributes;
	byte  MaxPower;
}
