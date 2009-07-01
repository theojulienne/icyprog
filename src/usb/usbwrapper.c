#include <usb.h>

struct usb_bus *usb_bus_get_next( struct usb_bus *curr ) {
	return curr->next;
}

struct usb_device *usb_bus_first_device( struct usb_bus *bus ) {
	return bus->devices;
}

struct usb_device *usb_device_get_next( struct usb_device *dev ) {
	return dev->next;
}

struct usb_device_descriptor usb_get_device_descriptor( struct usb_device *dev ) {
	return dev->descriptor;
}

struct usb_config_descriptor usb_get_configuration_descriptor( struct usb_device *dev, int cfg ) {
	return dev->config[cfg];
}
