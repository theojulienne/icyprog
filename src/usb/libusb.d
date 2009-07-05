module usb.libusb;

import usb.descriptors;

extern (C) {
	typedef void usb_bus;
	typedef void usb_device;
	typedef void usb_dev_handle;
	
	void usb_init( );
	int usb_find_busses( );
	int usb_find_devices( );
	usb_bus *usb_get_busses( );
	
	usb_dev_handle *usb_open( usb_device *dev );
	int usb_close( usb_dev_handle *dev );
	int usb_set_configuration( usb_dev_handle *dev, int configuration );
	int usb_claim_interface( usb_dev_handle *dev, int iface );
	int usb_release_interface( usb_dev_handle *dev, int iface );
	
	int usb_bulk_read( usb_dev_handle *dev, int ep, ubyte *bytes, int size, int timeout );
	int usb_bulk_write( usb_dev_handle *dev, int ep, ubyte *bytes, int size, int timeout );
	
	
	/* wrapper functions to get out of duplicating the struct definitions */
	
	usb_bus *usb_bus_get_next( usb_bus *curr );
	
	usb_device *usb_bus_first_device( usb_bus *bus );
	usb_device *usb_device_get_next( usb_device *dev );
	
	USBDeviceDescriptor usb_get_device_descriptor( usb_device *dev );
	
	USBConfigurationDescriptor usb_get_configuration_descriptor( usb_device *dev, int cfg );
}